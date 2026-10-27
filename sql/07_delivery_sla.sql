
--##Delivery Performance (SLA)

SELECT
   customer_state,
    COUNT(*) AS delivered_orders,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    CAST(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS late_pct,
    CAST(AVG(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
                  THEN CAST(DATEDIFF(day, order_estimated_delivery_date, order_delivered_customer_date) AS DECIMAL(10,2)) END)
         AS DECIMAL(10,2)) AS avg_days_late,
    CAST(AVG(CAST(DATEDIFF(day, order_purchase_timestamp, order_delivered_customer_date) AS DECIMAL(10,2)))
         AS DECIMAL(10,2)) AS avg_delivery_days    
FROM ctr.orders co
join ctr.customers cc on co.customer_id=cc.customer_id
WHERE order_status = 'delivered'
 AND order_delivered_customer_date IS NOT NULL
 group by customer_state
 HAVING COUNT(*) >= 100

