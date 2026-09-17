-- Этот запрос возвращает ARPU, ARPPU и AOV за день

-- В CTE daily_revenue рассчитываем дневную выручку и количество заказов
-- UNNEST преобразует массив product_ids в отдельные строки, затем данные объединяются с таблицей Products для получения стоимости товаров
-- Отмененные заказы исключаются из рассчетов
WITH daily_revenue AS (
    SELECT
        date,
        SUM(price) AS revenue,
        COUNT(DISTINCT order_id) AS orders_count
    FROM (
		SELECT 
			order_id,
       		UNNEST(product_ids) AS product_id,		-- Из массива товаров получаем id каждого купленного товара 
         	creation_time::date AS date
		FROM orders
	) AS t
    LEFT JOIN products USING (product_id)			-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (							      -- Исключаем отмененные заказы из рассчетов
  		SELECT order_id
  		FROM user_actions
  		WHERE action = 'cancel_order'
	)
    GROUP BY date
),

-- CTE daily_users рассчитывает количество всех пользователей и платящих пользователей за каждый день
daily_users AS (
    SELECT
        time::date AS date,
        COUNT(DISTINCT user_id) AS count_users,
        COUNT(DISTINCT user_id) FILTER (
    			WHERE order_id NOT IN (
    				SELECT order_id
    				FROM user_actions
    				WHERE action = 'cancel_order'
    			)
    		) AS paying_users_count
    FROM user_actions
    GROUP BY time::date
)

SELECT
    date,											                        -- Конкретный день
    ROUND(revenue / count_users, 2) AS arpu,			    -- Средняя выручка на 1 пользователя
    ROUND(revenue / paying_users_count, 2) AS arppu,	-- Средняя выручка на 1 платящего пользователя
    ROUND(revenue / orders_count, 2) AS aov				    -- Средняя стоимость 1 заказа
FROM daily_revenue
LEFT JOIN daily_users USING (date)
ORDER BY date;
