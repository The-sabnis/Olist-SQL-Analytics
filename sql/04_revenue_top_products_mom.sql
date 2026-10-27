--##Month-over-Month Growth



WITH monthly_revenue AS (
    SELECT 
        YEAR(order_purchase_timestamp) AS yr,
        MONTH(order_purchase_timestamp) AS mth,
        SUM(oi.price) AS revenue
    FROM ctr.orders co
    JOIN ctr.order_items oi ON co.order_id = oi.order_id
    WHERE co.order_status IN ('delivered','shipped')
    GROUP BY YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp)
),
rev as (
SELECT 
    yr, mth, revenue,
    LAG(revenue) OVER (ORDER BY yr, mth) AS prev_month_revenue
FROM monthly_revenue
)
select rev.*,
    (revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0) * 100 AS growth
from rev
WHERE (yr = 2017 AND mth >= 2) OR (yr = 2018 AND mth <= 8)
ORDER BY yr, mth
