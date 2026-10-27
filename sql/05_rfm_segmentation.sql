
--##Customer Segmentation (RFM)

WITH ref AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM ctr.orders
    WHERE order_status IN ('delivered','shipped')
),
rfm AS (
    SELECT  c.customer_unique_id,
            COUNT(DISTINCT co.order_id) AS frequency,
            SUM(oi.price) AS monetary,
            CAST(MAX(co.order_purchase_timestamp) AS date) AS last_order_date,
            DATEDIFF(day, MAX(co.order_purchase_timestamp), ref.ref_date) AS recency
    FROM ctr.customers c
    JOIN ctr.orders co ON c.customer_id = co.customer_id
    JOIN ctr.order_items oi ON co.order_id = oi.order_id
    CROSS JOIN ref
    WHERE co.order_status IN ('delivered','shipped')
    GROUP BY c.customer_unique_id, ref.ref_date
),
scored AS (
    SELECT  customer_unique_id,
            frequency,
            monetary,
            recency,
            last_order_date,
            NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
            NTILE(5) OVER (ORDER BY monetary)     AS m_score,
            CASE
                WHEN frequency = 1 THEN 1
                WHEN frequency = 2 THEN 2
                ELSE 3
            END AS f_score
    FROM rfm
),
segmented AS (
    SELECT  customer_unique_id,
            frequency, monetary, recency,
            r_score, f_score, m_score,
            CASE
                WHEN r_score >= 4 AND f_score >= 2 THEN 'Champions'
                WHEN f_score >= 2 AND r_score <= 3 THEN 'Loyal'
                WHEN f_score = 1  AND r_score >= 4 THEN 'New / Promising'
                WHEN r_score <= 3 AND m_score >= 4 THEN 'At-Risk'
                WHEN r_score <= 2 AND m_score <= 3 THEN 'Lost'
                ELSE 'Needs Attention'
            END AS segment
    FROM scored
)
SELECT  segment,
        COUNT(*)                                              AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_customers,
        AVG(recency)                                          AS avg_recency_days,
        CAST(AVG(monetary) AS DECIMAL(10,2))                  AS avg_spend,
        SUM(monetary)                                         AS total_revenue
FROM segmented
GROUP BY segment