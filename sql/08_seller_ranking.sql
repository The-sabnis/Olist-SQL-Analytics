--08_seller_ranking.sql

WITH seller_stats AS (
    SELECT  ss.seller_id,
            ss.seller_state,
            COUNT(DISTINCT oi.order_id) AS total_orders,
            SUM(oi.price)               AS revenue
    FROM ctr.order_items oi
    JOIN ctr.orders  co ON oi.order_id  = co.order_id
    JOIN ctr.sellers ss ON oi.seller_id = ss.seller_id
    WHERE co.order_status IN ('delivered','shipped')
    GROUP BY ss.seller_id, ss.seller_state
),
ranked as (
select DENSE_RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC) AS rank_in_state,*
from seller_stats
)
SELECT seller_state,
       rank_in_state,
       seller_id,
       total_orders,
       revenue
FROM ranked
WHERE rank_in_state <= 3
ORDER BY seller_state, rank_in_state;



