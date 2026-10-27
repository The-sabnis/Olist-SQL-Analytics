/* =====================================================
   06_retention.sql
   Retention / repeat-customer analysis
   Scope: orders with status 'delivered' or 'shipped'
   Customer = customer_unique_id (the person, not the order)
   ===================================================== */


/* -----------------------------------------------------
   Query 1 + 2: One-time vs repeat customers
   Customer count, revenue split, revenue per customer
   Source: ctr.vw_customer_rfm_segments
   Check: 91,537 one-time + 2,861 repeat = 94,398
          revenue sums to 13,372,225.55
   ----------------------------------------------------- */
SELECT  CASE WHEN frequency = 1 THEN 'one time buyer' ELSE 'repeat buyer' END AS customer_type,
        COUNT(*) AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_customers,
        SUM(monetary) AS total_revenue,
        CAST(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER () AS DECIMAL(5,2)) AS pct_revenue,
        CAST(AVG(monetary) AS DECIMAL(10,2)) AS avg_revenue_per_customer
FROM ctr.vw_customer_rfm_segments
GROUP BY CASE WHEN frequency = 1 THEN 'one time buyer' ELSE 'repeat buyer' END;
GO


/* -----------------------------------------------------
   Query 3A: Time to second order, average and median
   Check: 2,861 repeat customers, avg ~80.63, median 28
   ----------------------------------------------------- */
WITH orders_ranked AS (
    SELECT  c.customer_unique_id,
            co.order_purchase_timestamp,
            ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                               ORDER BY co.order_purchase_timestamp) AS rn
    FROM ctr.customers c
    JOIN ctr.orders co ON co.customer_id = c.customer_id
    WHERE co.order_status IN ('delivered','shipped')
),
pivoted AS (
    SELECT  customer_unique_id,
            MAX(CASE WHEN rn = 1 THEN order_purchase_timestamp END) AS first_order,
            MAX(CASE WHEN rn = 2 THEN order_purchase_timestamp END) AS second_order
    FROM orders_ranked
    WHERE rn <= 2
    GROUP BY customer_unique_id
),
days AS (
    SELECT  customer_unique_id,
            CAST(DATEDIFF(day, first_order, second_order) AS DECIMAL(10,2)) AS days_to_second
    FROM pivoted
    WHERE second_order IS NOT NULL
)
SELECT DISTINCT
       COUNT(*) OVER ()                                                    AS repeat_customers,
       AVG(days_to_second) OVER ()                                         AS avg_days,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_second) OVER () AS median_days
FROM days;
GO


/* -----------------------------------------------------
   Query 3B: Time to second order, buckets
   Check: 1,453 / 503 / 419 / 486 = 2,861
   ----------------------------------------------------- */
WITH orders_ranked AS (
    SELECT  c.customer_unique_id,
            co.order_purchase_timestamp,
            ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                               ORDER BY co.order_purchase_timestamp) AS rn
    FROM ctr.customers c
    JOIN ctr.orders co ON co.customer_id = c.customer_id
    WHERE co.order_status IN ('delivered','shipped')
),
pivoted AS (
    SELECT  customer_unique_id,
            MAX(CASE WHEN rn = 1 THEN order_purchase_timestamp END) AS first_order,
            MAX(CASE WHEN rn = 2 THEN order_purchase_timestamp END) AS second_order
    FROM orders_ranked
    WHERE rn <= 2
    GROUP BY customer_unique_id
),
days AS (
    SELECT  customer_unique_id,
            CAST(DATEDIFF(day, first_order, second_order) AS DECIMAL(10,2)) AS days_to_second
    FROM pivoted
    WHERE second_order IS NOT NULL
)
SELECT  CASE WHEN days_to_second <= 30  THEN '0-30'
             WHEN days_to_second <= 90  THEN '31-90'
             WHEN days_to_second <= 180 THEN '91-180'
             ELSE '180+' END AS bucket,
        COUNT(*) AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM days
GROUP BY CASE WHEN days_to_second <= 30  THEN '0-30'
              WHEN days_to_second <= 90  THEN '31-90'
              WHEN days_to_second <= 180 THEN '91-180'
              ELSE '180+' END
ORDER BY MIN(days_to_second);
GO


/* -----------------------------------------------------
   Findings (for README)
   - 3.03% of customers are repeat buyers, 5.54% of revenue
   - Repeat buyer total spend 258.85 vs 138.00 one-time (~1.9x),
     but this is from ordering more often, not bigger orders
   - Time to second order: average 80.6 days, median 28 days
   - ~51% return within 30 days, ~68% within 90 days
   ----------------------------------------------------- */