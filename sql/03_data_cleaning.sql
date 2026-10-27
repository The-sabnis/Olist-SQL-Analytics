/* =====================================================================
   03_data_cleaning.sql
   Project : Olist Retail Analytics (OlistRetailDB, schema ctr)
   Purpose : Validate loaded data, fix what is safely fixable, LOG what is not
   Rules   : - Never invent data (no dummy dates like 1990-01-01: they poison
               AVG(DATEDIFF) analysis). Leave NULL and log the anomaly.
             - Preview with SELECT before every UPDATE / INSERT.
             - Flag bad rows, do not delete them.
   Audit   : ctr.data_quality_log (table_name, record_id, issue_desc, logged_at)
   ===================================================================== */
USE OlistRetailDB;
GO

/* ---------------------------------------------------------------------
   1. ORDERS: NULL profile
      Many NULLs are legitimate (orders still in progress or canceled).
      Expected after the column-alignment fix:
        order_approved_at 160 | carrier date 1,783 | customer date 2,965
   --------------------------------------------------------------------- */
SELECT SUM(CASE WHEN order_approved_at            IS NULL THEN 1 ELSE 0 END) AS null_approved,
       SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS null_carrier,
       SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_customer
FROM ctr.orders;

-- NULL delivery date by status
-- Expected: shipped 1,107 | canceled 619 | unavailable 609 | invoiced 314 |
--           processing 301 | delivered 8 | created 5 | approved 2
SELECT order_status, COUNT(*) AS null_delivery_date
FROM ctr.orders
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status
ORDER BY null_delivery_date DESC;

/* ---------------------------------------------------------------------
   2. ORDERS: true anomaly = 'delivered' but no delivery date (expect 8)
      Preview, then log. Do NOT fill in a fake date.
   --------------------------------------------------------------------- */
SELECT order_id, order_status, order_delivered_customer_date
FROM ctr.orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

INSERT INTO ctr.data_quality_log (table_name, record_id, issue_desc)
SELECT 'orders', order_id, 'status delivered but order_delivered_customer_date is NULL'
FROM ctr.orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
  AND NOT EXISTS (SELECT 1 FROM ctr.data_quality_log l
                  WHERE l.table_name = 'orders' AND l.record_id = ctr.orders.order_id);
GO

/* ---------------------------------------------------------------------
   3. PRODUCTS: 610 NULL categories -> 'uncategorized'
      Reason: all 610 have real sales; NULL would be dropped or blanked by
      GROUP BY and BI tools. Preview first.
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS null_category                 -- expect 610
FROM ctr.products
WHERE product_category_name IS NULL;

UPDATE ctr.products
SET product_category_name = 'uncategorized'
WHERE product_category_name IS NULL;

SELECT COUNT(*) AS uncategorized_now             -- expect 610
FROM ctr.products
WHERE product_category_name = 'uncategorized';
GO

/* ---------------------------------------------------------------------
   4. PRODUCTS: 2 products with all four dimensions missing -> log only
      (one is 'bebes', one is 'uncategorized'; do NOT filter by category)
   --------------------------------------------------------------------- */
SELECT product_id, product_category_name
FROM ctr.products
WHERE product_weight_g IS NULL AND product_length_cm IS NULL
  AND product_height_cm IS NULL AND product_width_cm IS NULL;   -- expect 2

INSERT INTO ctr.data_quality_log (table_name, record_id, issue_desc)
SELECT 'products', product_id, 'weight, length, height and width all NULL'
FROM ctr.products
WHERE product_weight_g IS NULL AND product_length_cm IS NULL
  AND product_height_cm IS NULL AND product_width_cm IS NULL;
GO

/* ---------------------------------------------------------------------
   5. ORDER_PAYMENTS: no stray quote characters left from the CSV
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS rows_with_quotes              -- expect 0
FROM ctr.order_payments
WHERE order_id LIKE '%"%' OR payment_type LIKE '%"%';

/* ---------------------------------------------------------------------
   6. CUSTOMERS: duplicates in customer_unique_id are EXPECTED
      One person places many orders, each with a new customer_id.
      2,997 customers repeat (worst case 17 orders). A UNIQUE constraint here
      would block valid returning-customer rows, so none is added.
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS repeat_unique_ids
FROM (SELECT customer_unique_id
      FROM ctr.customers
      GROUP BY customer_unique_id
      HAVING COUNT(*) > 1) d;

/* ---------------------------------------------------------------------
   7. Audit log state after cleaning
      10 rows here (8 orders + 2 products). It reaches 14 after
      10_foreign_keys_and_fixes.sql logs 4 shipping_limit_date anomalies.
   --------------------------------------------------------------------- */
SELECT table_name, COUNT(*) AS logged_rows
FROM ctr.data_quality_log
GROUP BY table_name;
