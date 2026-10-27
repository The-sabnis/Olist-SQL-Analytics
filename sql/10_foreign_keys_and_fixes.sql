/* =====================================================================
   10_foreign_keys_and_fixes.sql
   Project : Olist Retail Analytics (OlistRetailDB, schema ctr)
   Purpose : Phase 6 integrity work
             A. Foreign keys order_items -> products, sellers (+ re-trust orders FK)
             B. shipping_limit_date: varchar(50) -> datetime2(0)
   Rule    : preview with SELECT before every ALTER / UPDATE.
   ===================================================================== */
USE OlistRetailDB;
GO

/* =====================================================================
   A. FOREIGN KEYS
   ===================================================================== */

/* A1. Orphan checks: order_items rows whose parent does not exist.
       Start FROM the child table (order_items), LEFT JOIN the parent,
       filter on the parent key being NULL. Expect 0 for each. */
SELECT COUNT(*) AS orphan_rows,
       COUNT(DISTINCT oi.product_id) AS orphan_products
FROM ctr.order_items oi
LEFT JOIN ctr.products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS orphan_rows,
       COUNT(DISTINCT oi.seller_id) AS orphan_sellers
FROM ctr.order_items oi
LEFT JOIN ctr.sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;
GO

/* A2. Column lengths must match for a foreign key (Msg 1753 otherwise).
       order_items.product_id / seller_id had been widened to varchar(100) earlier
       to fix a load truncation, and were never matched back to the parent keys
       (varchar(50)). Preview, then narrow the CHILD column.
       Always restate NULL / NOT NULL in ALTER COLUMN, or it resets to nullable. */
SELECT MAX(LEN(seller_id))  AS longest_seller_id,
       MAX(LEN(product_id)) AS longest_product_id
FROM ctr.order_items;                            -- IDs are 32 chars

ALTER TABLE ctr.order_items ALTER COLUMN product_id varchar(50) NOT NULL;
ALTER TABLE ctr.order_items ALTER COLUMN seller_id  varchar(50) NOT NULL;
GO

/* A3. Add the constraints (named explicitly). */
ALTER TABLE ctr.order_items
ADD CONSTRAINT fk_order_item_product
FOREIGN KEY (product_id) REFERENCES ctr.products (product_id);
GO

ALTER TABLE ctr.order_items
ADD CONSTRAINT fk_order_item_seller
FOREIGN KEY (seller_id) REFERENCES ctr.sellers (seller_id);
GO

/* A4. Re-trust the older orders FK (it showed is_not_trusted = 1).
       An untrusted FK cannot be used by the optimizer to simplify joins.
       WITH CHECK re-validates existing rows; WITH NOCHECK would leave it untrusted. */
SELECT COUNT(*) AS orphan_rows                   -- expect 0
FROM ctr.order_items oi
LEFT JOIN ctr.orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;

ALTER TABLE ctr.order_items
WITH CHECK CHECK CONSTRAINT fk_orders_item;
GO

/* A5. Verify: all three should show is_disabled = 0, is_not_trusted = 0. */
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('ctr.order_items');
GO

/* =====================================================================
   B. shipping_limit_date: varchar(50) -> datetime2(0)
   ===================================================================== */

/* B1. Raw format is dd-MM-yyyy HH:mm (e.g. '19-09-2017 09:45').
       Default (month-first) parsing fails on 70,099 rows and would silently
       flip day/month on the rest (05-09 read as May 9). Use style 105. */
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN TRY_CONVERT(datetime2(0), shipping_limit_date)      IS NULL THEN 1 ELSE 0 END) AS fail_default,   -- 70,099
       SUM(CASE WHEN TRY_CONVERT(datetime2(0), shipping_limit_date, 105) IS NULL THEN 1 ELSE 0 END) AS fail_dmy,       -- 0
       MIN(TRY_CONVERT(datetime2(0), shipping_limit_date, 105)) AS min_dt,   -- 2016-09-19 00:15
       MAX(TRY_CONVERT(datetime2(0), shipping_limit_date, 105)) AS max_dt    -- 2020-04-09 22:35
FROM ctr.order_items;
GO

/* B2. Source anomaly: 4 line items (3 orders) have a shipping limit in 2020,
       about 3 years after a normal 2017 purchase. The parse is right; the
       source value is wrong. Do not fix or delete. Log them. */
SELECT oi.order_id, oi.order_item_id, oi.shipping_limit_date
FROM ctr.order_items oi
WHERE TRY_CONVERT(datetime2(0), oi.shipping_limit_date, 105) >= '2019-01-01';   -- expect 4

INSERT INTO ctr.data_quality_log (table_name, record_id, issue_desc)
SELECT 'order_items', oi.order_id,
       'shipping_limit_date years after purchase (2020)'
FROM ctr.order_items oi
WHERE TRY_CONVERT(datetime2(0), oi.shipping_limit_date, 105) >= '2019-01-01';
GO
SELECT COUNT(*) AS log_rows FROM ctr.data_quality_log;   -- 14
GO

/* B3. Add a real date column and fill it (old column kept until verified). */
ALTER TABLE ctr.order_items ADD shipping_limit_dt datetime2(0) NULL;
GO

UPDATE ctr.order_items
SET shipping_limit_dt = TRY_CONVERT(datetime2(0), shipping_limit_date, 105);
GO

/* B4. Verify: 112,650 rows | 0 NULLs | 2016-09-19 00:15 to 2020-04-09 22:35 */
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN shipping_limit_dt IS NULL THEN 1 ELSE 0 END) AS null_dt,
       MIN(shipping_limit_dt) AS min_dt,
       MAX(shipping_limit_dt) AS max_dt
FROM ctr.order_items;
GO

/* B5. Safety check: nothing references the old column (both returned no rows). */
SELECT OBJECT_NAME(d.referencing_id) AS referencing_object, c.name AS column_name
FROM sys.sql_expression_dependencies d
JOIN sys.columns c ON c.object_id = d.referenced_id AND c.column_id = d.referenced_minor_id
WHERE d.referenced_id = OBJECT_ID('ctr.order_items') AND c.name = 'shipping_limit_date';

SELECT OBJECT_NAME(object_id) AS obj
FROM sys.sql_modules
WHERE definition LIKE '%shipping_limit_date%';
GO

/* B6. Drop the old varchar column, rename the new one, rebuild to reclaim space
       (the added column had bloated the table: order_items reads 4,549 -> 1,992). */
ALTER TABLE ctr.order_items DROP COLUMN shipping_limit_date;
GO
EXEC sp_rename 'ctr.order_items.shipping_limit_dt', 'shipping_limit_date', 'COLUMN';
GO
ALTER INDEX ALL ON ctr.order_items REBUILD;
GO

/* B7. Final check: column is datetime2, nullable; data intact. */
SELECT name, TYPE_NAME(system_type_id) AS type, is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID('ctr.order_items') AND name LIKE 'shipping_limit%';
