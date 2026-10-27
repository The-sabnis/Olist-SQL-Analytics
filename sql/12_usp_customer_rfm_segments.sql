USE [OlistRetailDB]
GO
/****** Object:  StoredProcedure [ctr].[usp_customer_rfm_segments]    Script Date: 10/23/2026 3:23:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROCEDURE [ctr].[usp_customer_rfm_segments]
AS
BEGIN
    SET NOCOUNT ON;
   
    DROP TABLE IF EXISTS #rfm;


WITH ref AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM ctr.orders
    WHERE order_status IN ('delivered','shipped')
)
SELECT  c.customer_unique_id,
        COUNT(DISTINCT co.order_id) AS frequency,
        SUM(oi.price) AS monetary,
        DATEDIFF(day, MAX(co.order_purchase_timestamp), ref.ref_date) AS recency
INTO    #rfm
FROM ctr.customers c
JOIN ctr.orders co ON c.customer_id = co.customer_id
JOIN ctr.order_items oi ON co.order_id = oi.order_id
CROSS JOIN ref
WHERE co.order_status IN ('delivered','shipped')
GROUP BY c.customer_unique_id, ref.ref_date;


WITH numbered AS (
    SELECT  r.customer_unique_id, r.frequency, r.monetary, r.recency,
            t.n,
            ROW_NUMBER() OVER (ORDER BY r.recency DESC, r.customer_unique_id) AS rn_r,
            ROW_NUMBER() OVER (ORDER BY r.monetary,     r.customer_unique_id) AS rn_m
    FROM #rfm r
    CROSS JOIN (SELECT COUNT(*) AS n FROM #rfm) t
),
scored AS (
    SELECT  customer_unique_id, frequency, monetary, recency,
            5 * (rn_r - 1) / n + 1 AS r_score,
            5 * (rn_m - 1) / n + 1 AS m_score,
            CASE WHEN frequency = 1 THEN 1
                 WHEN frequency = 2 THEN 2
                 ELSE 3 END AS f_score
    FROM numbered
),
segmented AS (
    SELECT  customer_unique_id, r_score, f_score, m_score,
            CASE
                WHEN r_score >= 4 AND f_score >= 2 THEN 'Champions'
                WHEN f_score >= 2 AND r_score <= 3 THEN 'Loyal'
                WHEN f_score = 1  AND r_score >= 4 THEN 'New / Promising'   
                WHEN r_score <= 3 AND m_score >= 4 THEN 'At-Risk'
                WHEN r_score <= 2 AND m_score <= 3 THEN 'Lost'
                ELSE 'Needs Attention'
            END AS segment,
            frequency, monetary, recency
    FROM scored
)
SELECT customer_unique_id, frequency, monetary, recency, r_score, f_score, m_score,segment
FROM segmented


END;
