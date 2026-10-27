/* =====================================================================
   02_load_data.sql
   Project : Olist Retail Analytics (OlistRetailDB, schema ctr)
   Purpose : Load the 9 Olist CSVs into the ctr tables
   Source  : D:\SQL Analyst Projects\Project 1\archive\  (Kaggle olistbr/brazilian-ecommerce)
   Pattern : "load first, clean second"
             - simple, unquoted CSVs  -> BULK INSERT straight into the table
             - quoted / date-format-sensitive CSVs -> loose staging table, then
               INSERT ... SELECT with explicit CAST / TRY_CONVERT
   Lessons (details in README):
     1. Files are comma-separated (Excel hides the commas). Inspect in Notepad.
     2. BULK INSERT maps columns by POSITION, not name. Table column order must
        match the CSV, or data loads into the wrong columns with no error.
     3. Check max lengths in the source before choosing varchar sizes.
   NOTE: file names below follow the standard Kaggle names. Check them against
         your folder before running.
   ===================================================================== */
USE OlistRetailDB;
GO

/* ---------------------------------------------------------------------
   1. customers  (expect 99,441)
   --------------------------------------------------------------------- */
BULK INSERT ctr.customers
FROM 'D:\SQL Analyst Projects\Project 1234\archive\olist_customers_dataset.csv'  --example
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
GO
SELECT COUNT(*) AS customers_rows FROM ctr.customers;   -- 99,441
GO

/* ---------------------------------------------------------------------
   2. products  (expect 32,951)
   --------------------------------------------------------------------- */
BULK INSERT ctr.products
FROM 'D:\SQL Analyst Projects\Project 12bc\archive\olist_products_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
GO
SELECT COUNT(*) AS products_rows FROM ctr.products;     -- 32,951
GO

/* ---------------------------------------------------------------------
   3. sellers  (expect 3,095)
   --------------------------------------------------------------------- */
BULK INSERT ctr.sellers
FROM 'D:\SQL Analyst Projects\Project 1098\archive\olist_sellers_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
GO
SELECT COUNT(*) AS sellers_rows FROM ctr.sellers;       -- 3,095
GO

/* ---------------------------------------------------------------------
   4. product_category_name_translation  (expect 71)
   --------------------------------------------------------------------- */
BULK INSERT ctr.product_category_name_translation
FROM 'D:\SQL Analyst Projects\Project 1lo\archive\product_category_name_translation.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, CODEPAGE = '65001');
GO
SELECT COUNT(*) AS translation_rows FROM ctr.product_category_name_translation;  -- 71
GO

/* ---------------------------------------------------------------------
   5. geolocation  (expect 1,000,163)
      DECIMAL(18,8) for coordinates: DECIMAL(10,2) would have rounded them.
   --------------------------------------------------------------------- */
BULK INSERT ctr.geolocation
FROM 'D:\SQL Analyst Projects\Project 1yu\archive\olist_geolocation_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, CODEPAGE = '65001');
GO
SELECT COUNT(*) AS geolocation_rows FROM ctr.geolocation;   -- 1,000,163
GO

/* ---------------------------------------------------------------------
   6. orders  (expect 99,441)
      Dates in the CSV are dd-MM-yyyy: they fail as DATETIME, so they are
      loaded as text into staging, then converted with an explicit style.
      CSV column order: order_id, customer_id, order_status, purchase,
      approved, delivered_carrier, delivered_customer, estimated.
      The INSERT lists columns by NAME, which avoids the positional
      misalignment bug that BULK INSERT straight into the table caused.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS ctr.stg_orders_raw;
CREATE TABLE ctr.stg_orders_raw (
    order_id                       varchar(50),
    customer_id                    varchar(50),
    order_status                   varchar(15),
    order_purchase_timestamp       varchar(30),
    order_approved_at              varchar(30),
    order_delivered_carrier_date   varchar(30),
    order_delivered_customer_date  varchar(30),
    order_estimated_delivery_date  varchar(30)
);
GO
BULK INSERT ctr.stg_orders_raw
FROM 'D:\SQL Analyst Projects\Project 1\archive\olist_orders_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
GO

-- Preview before converting: every non-empty date must parse (expect 0 failures
-- in each column). Style 105 = dd-mm-yyyy. Adjust if your file shows seconds
-- or a different layout.
SELECT SUM(CASE WHEN order_purchase_timestamp      <> '' AND TRY_CONVERT(datetime2(0), order_purchase_timestamp, 105)      IS NULL THEN 1 ELSE 0 END) AS bad_purchase,
       SUM(CASE WHEN order_approved_at             <> '' AND TRY_CONVERT(datetime2(0), order_approved_at, 105)             IS NULL THEN 1 ELSE 0 END) AS bad_approved,
       SUM(CASE WHEN order_delivered_carrier_date  <> '' AND TRY_CONVERT(datetime2(0), order_delivered_carrier_date, 105)  IS NULL THEN 1 ELSE 0 END) AS bad_carrier,
       SUM(CASE WHEN order_delivered_customer_date <> '' AND TRY_CONVERT(datetime2(0), order_delivered_customer_date, 105) IS NULL THEN 1 ELSE 0 END) AS bad_customer,
       SUM(CASE WHEN order_estimated_delivery_date <> '' AND TRY_CONVERT(datetime2(0), order_estimated_delivery_date, 105) IS NULL THEN 1 ELSE 0 END) AS bad_estimated
FROM ctr.stg_orders_raw;
GO

INSERT INTO ctr.orders (order_id, customer_id, order_status,
                        order_purchase_timestamp, order_approved_at,
                        order_delivered_carrier_date, order_delivered_customer_date,
                        order_estimated_delivery_date)
SELECT order_id, customer_id, order_status,
       TRY_CONVERT(datetime2(0), order_purchase_timestamp, 105),
       TRY_CONVERT(datetime2(0), NULLIF(order_approved_at, ''), 105),
       TRY_CONVERT(datetime2(0), NULLIF(order_delivered_carrier_date, ''), 105),
       TRY_CONVERT(datetime2(0), NULLIF(order_delivered_customer_date, ''), 105),
       TRY_CONVERT(datetime2(0), order_estimated_delivery_date, 105)
FROM ctr.stg_orders_raw;
GO
SELECT COUNT(*) AS orders_rows FROM ctr.orders;   -- 99,441
GO

/* ---------------------------------------------------------------------
   7. order_items  (expect 112,650)
      shipping_limit_date arrives as dd-MM-yyyy HH:mm text. It is loaded as
      varchar and converted later (see 10_foreign_keys_and_fixes.sql).
   --------------------------------------------------------------------- */
/* Original load used a varchar(50) shipping_limit_date column, then the fix in
   file 10 converted it. Load order_items into a table whose shipping_limit_date
   is varchar(50) (or into a staging table), then follow file 10. */

/* ---------------------------------------------------------------------
   8. order_payments  (expect 103,886)
      CSV has double-quoted values. BULK INSERT and FORMAT='CSV' both failed
      (Msg 7301). Workaround: SSMS "Import Flat File" wizard into a staging
      table (ctr.stg_order_payments_raw), then:
   --------------------------------------------------------------------- */
-- INSERT INTO ctr.order_payments (order_id, payment_sequential, payment_type,
--                                 payment_installments, payment_value)
-- SELECT order_id, payment_sequential, payment_type, payment_installments,
--        CAST(payment_value AS decimal(10,2))      -- wizard imports as float
-- FROM ctr.stg_order_payments_raw;
-- SELECT COUNT(*) FROM ctr.order_payments;          -- 103,886

/* ---------------------------------------------------------------------
   9. order_reviews  (expect 99,224)
      Quoted comment text: same wizard + staging route as payments.
      review_id is shared by 2 orders in 25 cases, so the PK is
      (review_id, order_id).
   --------------------------------------------------------------------- */
-- INSERT INTO ctr.order_reviews (review_id, order_id, review_score,
--        review_comment_title, review_comment_message,
--        review_creation_date, review_answer_timestamp)
-- SELECT ... FROM <wizard staging table>;
-- SELECT COUNT(*) FROM ctr.order_reviews;           -- 99,224

/* ---------------------------------------------------------------------
   10. Row-count reconciliation
   --------------------------------------------------------------------- */
SELECT t.name AS table_name, SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.schema_id = SCHEMA_ID('ctr')
GROUP BY t.name
ORDER BY t.name;
/* Expected: customers 99,441 | orders 99,441 | order_items 112,650 |
   order_payments 103,886 | order_reviews 99,224 | products 32,951 |
   sellers 3,095 | geolocation 1,000,163 | translation 71 */

-- Staging tables were dropped after the load was verified.
-- DROP TABLE IF EXISTS ctr.stg_orders_raw, ctr.stg_order_payments_raw;
