-- revenue_changing.sql
-- Дневная выручка, накопительная выручка и изменение выручки относительно предыдущего дня
WITH daily_revenue AS (
    SELECT
        date,
        SUM(price) AS revenue
    FROM (SELECT order_id,
      			     UNNEST(product_ids) AS product_id,
    		         creation_time::date AS date
          FROM orders) AS t
    LEFT JOIN products USING (product_id)
    WHERE order_id NOT IN (SELECT order_id
          					       FROM user_actions
          					       WHERE action = 'cancel_order')
    GROUP BY date
)

SELECT
    date,
    revenue,
    SUM(revenue) OVER (ORDER BY date) AS total_revenue,
    ROUND(100 * (revenue - LAG(revenue, 1) OVER (ORDER BY date))::decimal / LAG(revenue, 1) OVER (ORDER BY date), 2) AS revenue_change
FROM daily_revenue;
