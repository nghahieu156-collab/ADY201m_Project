"""
Olist E-Commerce - Import CSV to SQL Server
Server: localhost\SQLEXPRESS | Database: OlistDB
"""

import pyodbc
import pandas as pd
import os
import sys
import time
from datetime import datetime

# Force UTF-8 output
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────
SERVER   = r"localhost\SQLEXPRESS"
DATABASE = "OlistDB"
DRIVER   = "ODBC Driver 17 for SQL Server"
CSV_DIR  = r"C:\Users\nghah\OneDrive\Documents\dataset"

CONN_STR = (
    f"DRIVER={{{DRIVER}}};"
    f"SERVER={SERVER};"
    f"Trusted_Connection=yes;"
    f"TrustServerCertificate=yes;"
)

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def get_conn(database=None):
    cs = CONN_STR + (f"DATABASE={database};" if database else "")
    return pyodbc.connect(cs, autocommit=True)

def insert_df(conn, table, df, batch=2000):
    if df.empty:
        log(f"  SKIP {table} - empty")
        return
    cursor = conn.cursor()
    cursor.fast_executemany = True
    cols = ", ".join(f"[{c}]" for c in df.columns)
    placeholders = ", ".join(["?"] * len(df.columns))
    sql = f"INSERT INTO {table} ({cols}) VALUES ({placeholders})"
    total = 0
    for i in range(0, len(df), batch):
        chunk = df.iloc[i:i+batch]
        rows = [tuple(None if pd.isna(v) else v for v in row)
                for row in chunk.itertuples(index=False)]
        cursor.executemany(sql, rows)
        total += len(rows)
        print(f"  -> {total:,}/{len(df):,} rows...", end="\r", flush=True)
    conn.commit()
    print(f"  OK {total:,} rows -> {table}                    ")


# ─────────────────────────────────────────────
# STEP 1 - CREATE DATABASE
# ─────────────────────────────────────────────
log("=== STEP 1: Create database OlistDB ===")
conn_master = get_conn()
cur = conn_master.cursor()
cur.execute(f"""
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '{DATABASE}')
    CREATE DATABASE [{DATABASE}]
""")
log(f"  OK Database '{DATABASE}' ready")
conn_master.close()


# ─────────────────────────────────────────────
# STEP 2 - CREATE TABLES
# ─────────────────────────────────────────────
log("=== STEP 2: Create tables (DROP & CREATE) ===")
conn = get_conn(DATABASE)
cur = conn.cursor()

drop_order = [
    "order_reviews", "order_payments", "order_items",
    "orders", "customers", "products", "sellers",
    "geolocation", "product_category_translation"
]
for tbl in drop_order:
    cur.execute(f"IF OBJECT_ID('dbo.{tbl}','U') IS NOT NULL DROP TABLE dbo.[{tbl}]")
log("  OK dropped old tables")

cur.execute("""
CREATE TABLE dbo.product_category_translation (
    product_category_name         NVARCHAR(100) NOT NULL,
    product_category_name_english NVARCHAR(100) NULL,
    CONSTRAINT PK_pct PRIMARY KEY (product_category_name)
)""")

cur.execute("""
CREATE TABLE dbo.geolocation (
    geolocation_zip_code_prefix CHAR(5)       NOT NULL,
    geolocation_lat             FLOAT         NULL,
    geolocation_lng             FLOAT         NULL,
    geolocation_city            NVARCHAR(100) NULL,
    geolocation_state           CHAR(2)       NULL,
    CONSTRAINT PK_geo PRIMARY KEY (geolocation_zip_code_prefix)
)""")

cur.execute("""
CREATE TABLE dbo.customers (
    customer_id              CHAR(32)      NOT NULL,
    customer_unique_id       CHAR(32)      NOT NULL,
    customer_zip_code_prefix CHAR(5)       NULL,
    customer_city            NVARCHAR(100) NULL,
    customer_state           CHAR(2)       NULL,
    CONSTRAINT PK_customers PRIMARY KEY (customer_id),
    CONSTRAINT FK_customers_geo FOREIGN KEY (customer_zip_code_prefix)
        REFERENCES dbo.geolocation (geolocation_zip_code_prefix)
        ON UPDATE NO ACTION ON DELETE SET NULL
)""")

cur.execute("""
CREATE TABLE dbo.sellers (
    seller_id              CHAR(32)      NOT NULL,
    seller_zip_code_prefix CHAR(5)       NULL,
    seller_city            NVARCHAR(100) NULL,
    seller_state           CHAR(2)       NULL,
    CONSTRAINT PK_sellers PRIMARY KEY (seller_id),
    CONSTRAINT FK_sellers_geo FOREIGN KEY (seller_zip_code_prefix)
        REFERENCES dbo.geolocation (geolocation_zip_code_prefix)
        ON UPDATE NO ACTION ON DELETE SET NULL
)""")

cur.execute("""
CREATE TABLE dbo.products (
    product_id                 CHAR(32)      NOT NULL,
    product_category_name      NVARCHAR(100) NULL,
    product_name_lenght        INT           NULL,
    product_description_lenght INT           NULL,
    product_photos_qty         INT           NULL,
    product_weight_g           FLOAT         NULL,
    product_length_cm          FLOAT         NULL,
    product_height_cm          FLOAT         NULL,
    product_width_cm           FLOAT         NULL,
    CONSTRAINT PK_products PRIMARY KEY (product_id),
    CONSTRAINT FK_products_cat FOREIGN KEY (product_category_name)
        REFERENCES dbo.product_category_translation (product_category_name)
        ON UPDATE CASCADE ON DELETE SET NULL
)""")

cur.execute("""
CREATE TABLE dbo.orders (
    order_id                      CHAR(32)     NOT NULL,
    customer_id                   CHAR(32)     NOT NULL,
    order_status                  NVARCHAR(20) NULL,
    order_purchase_timestamp      DATETIME2    NULL,
    order_approved_at             DATETIME2    NULL,
    order_delivered_carrier_date  DATETIME2    NULL,
    order_delivered_customer_date DATETIME2    NULL,
    order_estimated_delivery_date DATETIME2    NULL,
    CONSTRAINT PK_orders PRIMARY KEY (order_id),
    CONSTRAINT FK_orders_customers FOREIGN KEY (customer_id)
        REFERENCES dbo.customers (customer_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)""")

cur.execute("""
CREATE TABLE dbo.order_items (
    order_id            CHAR(32)      NOT NULL,
    order_item_id       INT           NOT NULL,
    product_id          CHAR(32)      NULL,
    seller_id           CHAR(32)      NULL,
    shipping_limit_date DATETIME2     NULL,
    price               DECIMAL(10,2) NULL,
    freight_value       DECIMAL(10,2) NULL,
    CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT FK_oi_orders   FOREIGN KEY (order_id)
        REFERENCES dbo.orders   (order_id)   ON DELETE CASCADE,
    CONSTRAINT FK_oi_products FOREIGN KEY (product_id)
        REFERENCES dbo.products (product_id) ON DELETE SET NULL,
    CONSTRAINT FK_oi_sellers  FOREIGN KEY (seller_id)
        REFERENCES dbo.sellers  (seller_id)  ON DELETE SET NULL
)""")

cur.execute("""
CREATE TABLE dbo.order_payments (
    order_id             CHAR(32)      NOT NULL,
    payment_sequential   INT           NOT NULL,
    payment_type         NVARCHAR(30)  NULL,
    payment_installments INT           NULL,
    payment_value        DECIMAL(10,2) NULL,
    CONSTRAINT PK_order_payments PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT FK_op_orders FOREIGN KEY (order_id)
        REFERENCES dbo.orders (order_id) ON DELETE CASCADE
)""")

cur.execute("""
CREATE TABLE dbo.order_reviews (
    review_id               CHAR(32)      NOT NULL,
    order_id                CHAR(32)      NOT NULL,
    review_score            TINYINT       NULL,
    review_comment_title    NVARCHAR(200) NULL,
    review_comment_message  NVARCHAR(MAX) NULL,
    review_creation_date    DATETIME2     NULL,
    review_answer_timestamp DATETIME2     NULL,
    CONSTRAINT PK_order_reviews PRIMARY KEY (review_id),
    CONSTRAINT FK_or_orders FOREIGN KEY (order_id)
        REFERENCES dbo.orders (order_id) ON DELETE CASCADE
)""")

log("  OK all tables created with PK & FK")


# ─────────────────────────────────────────────
# STEP 3 - READ CSV
# ─────────────────────────────────────────────
log("=== STEP 3: Read CSV files ===")

def read_csv(filename):
    path = os.path.join(CSV_DIR, filename)
    df = pd.read_csv(path, dtype=str, keep_default_na=False,
                     na_values=["", "NA", "NaN", "nan"])
    df.columns = df.columns.str.strip().str.replace('"', '')
    log(f"  OK {filename}: {len(df):,} rows, {len(df.columns)} cols")
    return df

df_cat  = read_csv("product_category_name_translation.csv")
df_geo  = read_csv("olist_geolocation_dataset.csv")
df_cust = read_csv("olist_customers_dataset.csv")
df_sell = read_csv("olist_sellers_dataset.csv")
df_prod = read_csv("olist_products_dataset.csv")
df_ord  = read_csv("olist_orders_dataset.csv")
df_oi   = read_csv("olist_order_items_dataset.csv")
df_pay  = read_csv("olist_order_payments_dataset.csv")
df_rev  = read_csv("olist_order_reviews_dataset.csv")


# ─────────────────────────────────────────────
# STEP 4 - CLEAN DATA
# ─────────────────────────────────────────────
log("=== STEP 4: Clean & validate data ===")

# geolocation: deduplicate by zip_code_prefix
df_geo["geolocation_zip_code_prefix"] = df_geo["geolocation_zip_code_prefix"].str.zfill(5)
df_geo["geolocation_lat"] = pd.to_numeric(df_geo["geolocation_lat"], errors="coerce")
df_geo["geolocation_lng"] = pd.to_numeric(df_geo["geolocation_lng"], errors="coerce")
df_geo = (df_geo.groupby("geolocation_zip_code_prefix", as_index=False)
               .agg({"geolocation_lat":"mean","geolocation_lng":"mean",
                     "geolocation_city":"first","geolocation_state":"first"}))
log(f"  OK geolocation deduplicated: {len(df_geo):,} unique zip codes")

valid_zips = set(df_geo["geolocation_zip_code_prefix"])

# customers: pad zip, null invalid FK
df_cust["customer_zip_code_prefix"] = df_cust["customer_zip_code_prefix"].str.zfill(5)
mask = ~df_cust["customer_zip_code_prefix"].isin(valid_zips)
df_cust.loc[mask, "customer_zip_code_prefix"] = None
log(f"  OK customers: {mask.sum()} invalid zip -> NULL")

# sellers: pad zip, null invalid FK
df_sell["seller_zip_code_prefix"] = df_sell["seller_zip_code_prefix"].str.zfill(5)
mask_s = ~df_sell["seller_zip_code_prefix"].isin(valid_zips)
df_sell.loc[mask_s, "seller_zip_code_prefix"] = None
log(f"  OK sellers: {mask_s.sum()} invalid zip -> NULL")

# products: null invalid category FK, convert numeric cols
valid_cats = set(df_cat["product_category_name"].dropna())
mask_p = ~df_prod["product_category_name"].isin(valid_cats)
df_prod.loc[mask_p, "product_category_name"] = None
for col in ["product_name_lenght","product_description_lenght","product_photos_qty",
            "product_weight_g","product_length_cm","product_height_cm","product_width_cm"]:
    df_prod[col] = pd.to_numeric(df_prod[col], errors="coerce")
log(f"  OK products: {mask_p.sum()} invalid category -> NULL")

# orders: parse datetime
for c in ["order_purchase_timestamp","order_approved_at","order_delivered_carrier_date",
          "order_delivered_customer_date","order_estimated_delivery_date"]:
    df_ord[c] = pd.to_datetime(df_ord[c], errors="coerce")
    df_ord[c] = df_ord[c].apply(lambda x: None if pd.isna(x) else x.strftime("%Y-%m-%d %H:%M:%S"))
log(f"  OK orders: datetime parsed")

valid_orders = set(df_ord["order_id"])

# order_items: numeric + datetime, filter FK
df_oi["order_item_id"] = pd.to_numeric(df_oi["order_item_id"], errors="coerce")
df_oi["price"]         = pd.to_numeric(df_oi["price"], errors="coerce")
df_oi["freight_value"] = pd.to_numeric(df_oi["freight_value"], errors="coerce")
df_oi["shipping_limit_date"] = pd.to_datetime(df_oi["shipping_limit_date"], errors="coerce")
df_oi["shipping_limit_date"] = df_oi["shipping_limit_date"].apply(
    lambda x: None if pd.isna(x) else x.strftime("%Y-%m-%d %H:%M:%S"))
before_oi = len(df_oi)
df_oi = df_oi[df_oi["order_id"].isin(valid_orders)].drop_duplicates(subset=["order_id","order_item_id"])
log(f"  OK order_items: {before_oi:,} -> {len(df_oi):,} rows after FK filter")

# order_payments: numeric, filter FK, dedup PK
df_pay["payment_sequential"]  = pd.to_numeric(df_pay["payment_sequential"],  errors="coerce")
df_pay["payment_installments"] = pd.to_numeric(df_pay["payment_installments"], errors="coerce")
df_pay["payment_value"]        = pd.to_numeric(df_pay["payment_value"],        errors="coerce")
before_pay = len(df_pay)
df_pay = df_pay[df_pay["order_id"].isin(valid_orders)].drop_duplicates(subset=["order_id","payment_sequential"])
log(f"  OK order_payments: {before_pay:,} -> {len(df_pay):,} rows after FK filter")

# order_reviews: datetime, filter FK, dedup review_id
for c in ["review_creation_date","review_answer_timestamp"]:
    df_rev[c] = pd.to_datetime(df_rev[c], errors="coerce")
    df_rev[c] = df_rev[c].apply(lambda x: None if pd.isna(x) else x.strftime("%Y-%m-%d %H:%M:%S"))
df_rev["review_score"] = pd.to_numeric(df_rev["review_score"], errors="coerce")
before_rev = len(df_rev)
df_rev = df_rev[df_rev["order_id"].isin(valid_orders)].drop_duplicates(subset=["review_id"])
log(f"  OK order_reviews: {before_rev:,} -> {len(df_rev):,} rows after FK filter & dedup")


# ─────────────────────────────────────────────
# STEP 5 - INSERT DATA
# ─────────────────────────────────────────────
log("=== STEP 5: Insert data into SQL Server ===")

datasets = [
    ("dbo.product_category_translation", df_cat),
    ("dbo.geolocation",                  df_geo),
    ("dbo.customers",                    df_cust),
    ("dbo.sellers",                      df_sell),
    ("dbo.products",                     df_prod),
    ("dbo.orders",                       df_ord),
    ("dbo.order_items",                  df_oi),
    ("dbo.order_payments",               df_pay),
    ("dbo.order_reviews",                df_rev),
]

for table, df in datasets:
    t0 = time.time()
    log(f"Inserting -> {table} ({len(df):,} rows)...")
    insert_df(conn, table, df)
    log(f"  DONE {table} ({time.time()-t0:.1f}s)")


# ─────────────────────────────────────────────
# STEP 6 - VERIFY ROW COUNTS
# ─────────────────────────────────────────────
log("=== STEP 6: Row count verification ===")
cur = conn.cursor()
tables = [
    "product_category_translation","geolocation","customers","sellers",
    "products","orders","order_items","order_payments","order_reviews"
]
print("\n" + "-"*48)
print(f"{'Table':<35} {'Rows':>10}")
print("-"*48)
for tbl in tables:
    cur.execute(f"SELECT COUNT(*) FROM dbo.[{tbl}]")
    count = cur.fetchone()[0]
    print(f"{tbl:<35} {count:>10,}")
print("-"*48)

conn.close()
log("DONE! All data imported into OlistDB successfully.")
