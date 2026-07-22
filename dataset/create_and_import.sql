-- ============================================================
-- Olist Brazilian E-Commerce Database
-- SQL Server Import Script
-- Tạo bảng với Khóa Chính, Khóa Ngoại và import CSV
-- ============================================================

USE master;
GO

-- Tạo database nếu chưa có
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'OlistDB')
BEGIN
    CREATE DATABASE OlistDB;
    PRINT 'Database OlistDB đã được tạo.';
END
ELSE
BEGIN
    PRINT 'Database OlistDB đã tồn tại.';
END
GO

USE OlistDB;
GO

-- ============================================================
-- XÓA CÁC BẢNG CŨ (nếu tồn tại) theo đúng thứ tự FK
-- ============================================================
IF OBJECT_ID('dbo.order_reviews', 'U') IS NOT NULL     DROP TABLE dbo.order_reviews;
IF OBJECT_ID('dbo.order_payments', 'U') IS NOT NULL    DROP TABLE dbo.order_payments;
IF OBJECT_ID('dbo.order_items', 'U') IS NOT NULL       DROP TABLE dbo.order_items;
IF OBJECT_ID('dbo.orders', 'U') IS NOT NULL            DROP TABLE dbo.orders;
IF OBJECT_ID('dbo.customers', 'U') IS NOT NULL         DROP TABLE dbo.customers;
IF OBJECT_ID('dbo.products', 'U') IS NOT NULL          DROP TABLE dbo.products;
IF OBJECT_ID('dbo.sellers', 'U') IS NOT NULL           DROP TABLE dbo.sellers;
IF OBJECT_ID('dbo.geolocation', 'U') IS NOT NULL       DROP TABLE dbo.geolocation;
IF OBJECT_ID('dbo.product_category_translation', 'U') IS NOT NULL DROP TABLE dbo.product_category_translation;
GO

-- ============================================================
-- 1. BẢNG: product_category_translation
--    (Không có FK, tạo trước để products tham chiếu)
-- ============================================================
CREATE TABLE dbo.product_category_translation (
    product_category_name         NVARCHAR(100)  NOT NULL,
    product_category_name_english NVARCHAR(100)  NULL,
    CONSTRAINT PK_product_category_translation PRIMARY KEY (product_category_name)
);
GO

-- ============================================================
-- 2. BẢNG: geolocation
--    (Không có FK, dùng zip_code_prefix làm khóa chính)
-- ============================================================
CREATE TABLE dbo.geolocation (
    geolocation_zip_code_prefix CHAR(5)        NOT NULL,
    geolocation_lat             FLOAT          NULL,
    geolocation_lng             FLOAT          NULL,
    geolocation_city            NVARCHAR(100)  NULL,
    geolocation_state           CHAR(2)        NULL,
    CONSTRAINT PK_geolocation PRIMARY KEY (geolocation_zip_code_prefix)
);
GO

-- ============================================================
-- 3. BẢNG: customers
--    FK -> geolocation (zip_code_prefix)
-- ============================================================
CREATE TABLE dbo.customers (
    customer_id              CHAR(32)       NOT NULL,
    customer_unique_id       CHAR(32)       NOT NULL,
    customer_zip_code_prefix CHAR(5)        NULL,
    customer_city            NVARCHAR(100)  NULL,
    customer_state           CHAR(2)        NULL,
    CONSTRAINT PK_customers PRIMARY KEY (customer_id)
    -- NOTE: FK tới geolocation được thêm sau khi import xong
    --       vì geolocation có thể thiếu một số zip code
);
GO

-- ============================================================
-- 4. BẢNG: sellers
--    FK -> geolocation (zip_code_prefix)
-- ============================================================
CREATE TABLE dbo.sellers (
    seller_id              CHAR(32)       NOT NULL,
    seller_zip_code_prefix CHAR(5)        NULL,
    seller_city            NVARCHAR(100)  NULL,
    seller_state           CHAR(2)        NULL,
    CONSTRAINT PK_sellers PRIMARY KEY (seller_id)
);
GO

-- ============================================================
-- 5. BẢNG: products
--    FK -> product_category_translation (category_name)
-- ============================================================
CREATE TABLE dbo.products (
    product_id                   CHAR(32)       NOT NULL,
    product_category_name        NVARCHAR(100)  NULL,
    product_name_lenght          INT            NULL,
    product_description_lenght   INT            NULL,
    product_photos_qty           INT            NULL,
    product_weight_g             FLOAT          NULL,
    product_length_cm            FLOAT          NULL,
    product_height_cm            FLOAT          NULL,
    product_width_cm             FLOAT          NULL,
    CONSTRAINT PK_products PRIMARY KEY (product_id),
    CONSTRAINT FK_products_category FOREIGN KEY (product_category_name)
        REFERENCES dbo.product_category_translation (product_category_name)
        ON UPDATE CASCADE ON DELETE SET NULL
);
GO

-- ============================================================
-- 6. BẢNG: orders
--    FK -> customers (customer_id)
-- ============================================================
CREATE TABLE dbo.orders (
    order_id                        CHAR(32)       NOT NULL,
    customer_id                     CHAR(32)       NOT NULL,
    order_status                    NVARCHAR(20)   NULL,
    order_purchase_timestamp        DATETIME2      NULL,
    order_approved_at               DATETIME2      NULL,
    order_delivered_carrier_date    DATETIME2      NULL,
    order_delivered_customer_date   DATETIME2      NULL,
    order_estimated_delivery_date   DATETIME2      NULL,
    CONSTRAINT PK_orders PRIMARY KEY (order_id),
    CONSTRAINT FK_orders_customers FOREIGN KEY (customer_id)
        REFERENCES dbo.customers (customer_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);
GO

-- ============================================================
-- 7. BẢNG: order_items
--    FK -> orders (order_id), products (product_id), sellers (seller_id)
--    Khóa chính tổ hợp: (order_id, order_item_id)
-- ============================================================
CREATE TABLE dbo.order_items (
    order_id            CHAR(32)       NOT NULL,
    order_item_id       INT            NOT NULL,
    product_id          CHAR(32)       NULL,
    seller_id           CHAR(32)       NULL,
    shipping_limit_date DATETIME2      NULL,
    price               DECIMAL(10,2)  NULL,
    freight_value       DECIMAL(10,2)  NULL,
    CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT FK_order_items_orders FOREIGN KEY (order_id)
        REFERENCES dbo.orders (order_id)
        ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT FK_order_items_products FOREIGN KEY (product_id)
        REFERENCES dbo.products (product_id)
        ON UPDATE NO ACTION ON DELETE SET NULL,
    CONSTRAINT FK_order_items_sellers FOREIGN KEY (seller_id)
        REFERENCES dbo.sellers (seller_id)
        ON UPDATE NO ACTION ON DELETE SET NULL
);
GO

-- ============================================================
-- 8. BẢNG: order_payments
--    FK -> orders (order_id)
--    Khóa chính tổ hợp: (order_id, payment_sequential)
-- ============================================================
CREATE TABLE dbo.order_payments (
    order_id              CHAR(32)      NOT NULL,
    payment_sequential    INT           NOT NULL,
    payment_type          NVARCHAR(30)  NULL,
    payment_installments  INT           NULL,
    payment_value         DECIMAL(10,2) NULL,
    CONSTRAINT PK_order_payments PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT FK_order_payments_orders FOREIGN KEY (order_id)
        REFERENCES dbo.orders (order_id)
        ON UPDATE NO ACTION ON DELETE CASCADE
);
GO

-- ============================================================
-- 9. BẢNG: order_reviews
--    FK -> orders (order_id)
-- ============================================================
CREATE TABLE dbo.order_reviews (
    review_id                CHAR(32)       NOT NULL,
    order_id                 CHAR(32)       NOT NULL,
    review_score             TINYINT        NULL,
    review_comment_title     NVARCHAR(100)  NULL,
    review_comment_message   NVARCHAR(MAX)  NULL,
    review_creation_date     DATETIME2      NULL,
    review_answer_timestamp  DATETIME2      NULL,
    CONSTRAINT PK_order_reviews PRIMARY KEY (review_id),
    CONSTRAINT FK_order_reviews_orders FOREIGN KEY (order_id)
        REFERENCES dbo.orders (order_id)
        ON UPDATE NO ACTION ON DELETE CASCADE
);
GO

PRINT '>>> Tất cả bảng đã được tạo thành công!';
GO

-- ============================================================
-- IMPORT DỮ LIỆU BẰNG BULK INSERT
-- !! Thay đường dẫn CSV_PATH nếu cần !!
-- ============================================================

DECLARE @csv_path NVARCHAR(200) = 'C:\Users\nghah\OneDrive\Documents\dataset\';

-- ------------------------------------------------------------
-- BƯỚC 1: Import geolocation (chỉ lấy 1 row mỗi zip_code_prefix)
--         Dùng staging table trước để loại duplicate
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#geo_stage', 'U') IS NOT NULL DROP TABLE #geo_stage;
CREATE TABLE #geo_stage (
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat             FLOAT,
    geolocation_lng             FLOAT,
    geolocation_city            NVARCHAR(100),
    geolocation_state           CHAR(2)
);

BULK INSERT #geo_stage
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_geolocation_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);

-- Chỉ insert zip_code_prefix đầu tiên xuất hiện (tránh duplicate PK)
INSERT INTO dbo.geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
SELECT geolocation_zip_code_prefix,
       AVG(geolocation_lat),
       AVG(geolocation_lng),
       MAX(geolocation_city),
       MAX(geolocation_state)
FROM   #geo_stage
GROUP BY geolocation_zip_code_prefix;

DROP TABLE #geo_stage;
PRINT '>>> geolocation: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 2: Import product_category_translation
-- ------------------------------------------------------------
BULK INSERT dbo.product_category_translation
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\product_category_name_translation.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> product_category_translation: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 3: Import customers
-- ------------------------------------------------------------
BULK INSERT dbo.customers
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_customers_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> customers: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 4: Import sellers
-- ------------------------------------------------------------
BULK INSERT dbo.sellers
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_sellers_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> sellers: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 5: Import products
--         Tạm thời tắt FK constraint để import dữ liệu có category NULL
-- ------------------------------------------------------------
ALTER TABLE dbo.products NOCHECK CONSTRAINT FK_products_category;

BULK INSERT dbo.products
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_products_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);

-- Đặt NULL cho category_name không tồn tại trong bảng translation
UPDATE dbo.products
SET    product_category_name = NULL
WHERE  product_category_name IS NOT NULL
  AND  product_category_name NOT IN (SELECT product_category_name FROM dbo.product_category_translation);

ALTER TABLE dbo.products CHECK CONSTRAINT FK_products_category;
PRINT '>>> products: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 6: Import orders
-- ------------------------------------------------------------
BULK INSERT dbo.orders
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_orders_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> orders: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 7: Import order_items
-- ------------------------------------------------------------
BULK INSERT dbo.order_items
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_order_items_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> order_items: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 8: Import order_payments
-- ------------------------------------------------------------
BULK INSERT dbo.order_payments
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_order_payments_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);
PRINT '>>> order_payments: import xong';
GO

-- ------------------------------------------------------------
-- BƯỚC 9: Import order_reviews
--         Có thể có review_id trùng -> dùng staging
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#reviews_stage', 'U') IS NOT NULL DROP TABLE #reviews_stage;
CREATE TABLE #reviews_stage (
    review_id               CHAR(32),
    order_id                CHAR(32),
    review_score            TINYINT,
    review_comment_title    NVARCHAR(100),
    review_comment_message  NVARCHAR(MAX),
    review_creation_date    DATETIME2,
    review_answer_timestamp DATETIME2
);

BULK INSERT #reviews_stage
FROM 'C:\Users\nghah\OneDrive\Documents\dataset\olist_order_reviews_dataset.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001',
    FORMAT          = 'CSV'
);

-- Chỉ insert review_id đầu tiên (tránh PK duplicate)
INSERT INTO dbo.order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp)
SELECT review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY review_id ORDER BY review_creation_date) AS rn
    FROM #reviews_stage
    WHERE order_id IN (SELECT order_id FROM dbo.orders)
) t
WHERE rn = 1;

DROP TABLE #reviews_stage;
PRINT '>>> order_reviews: import xong';
GO

-- ============================================================
-- KIỂM TRA SỐ LƯỢNG DÒNG
-- ============================================================
SELECT 'product_category_translation' AS bang, COUNT(*) AS so_dong FROM dbo.product_category_translation
UNION ALL
SELECT 'geolocation',   COUNT(*) FROM dbo.geolocation
UNION ALL
SELECT 'customers',     COUNT(*) FROM dbo.customers
UNION ALL
SELECT 'sellers',       COUNT(*) FROM dbo.sellers
UNION ALL
SELECT 'products',      COUNT(*) FROM dbo.products
UNION ALL
SELECT 'orders',        COUNT(*) FROM dbo.orders
UNION ALL
SELECT 'order_items',   COUNT(*) FROM dbo.order_items
UNION ALL
SELECT 'order_payments',COUNT(*) FROM dbo.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM dbo.order_reviews;
GO

PRINT '>>> HOÀN THÀNH! Database OlistDB đã được tạo và import đầy đủ.';
GO
