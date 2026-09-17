-- Этот запрос рассчитывает долю дневной выручки с новых пользователей

-- В CTE user_first_dates определяется дата первого появления пользователя в сервисе
-- Используется чтобы выделить заказы новых пользователей
WITH user_first_dates AS (
    SELECT
        MIN(time::date) AS min_date,
        user_id
    FROM user_actions
    GROUP BY user_id
),

-- В CTE users_revenue рассчитывается общая дневная выручка сервиса и выручка от новых пользователей 
users_revenue AS (
    SELECT
        date,   
        SUM(price) AS revenue,									-- Дневная выручка от всех пользователей
        SUM(price) filter (										-- Дневная выручка от новых пользователей:
            WHERE order_id IN (									-- оставляем заказы пользователей только в день их первого появления
    			SELECT order_id
    			FROM user_actions
    			LEFT JOIN user_first_dates USING (user_id)	
    			WHERE time::date = min_date						
    		)
    	) AS new_users_revenue
    FROM (
		SELECT
            order_id,
            UNNEST(product_ids) AS product_id,					-- Из массива товаров получаем id каждого купленного товара 
            creation_time::date AS date
	    FROM orders
	) AS prepared_orders
    LEFT JOIN products USING (product_id)						-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (										-- Исключаем отмененные заказы из рассчетов
		SELECT order_id
		FROM user_actions
		WHERE action = 'cancel_order'
	)										          
    GROUP BY date
)

SELECT
    date,																			-- Конкретный день
    revenue,																		-- Выручка за 1 день 
    new_users_revenue,																-- Выручка новых пользователей за 1 день
    ROUND(100 * new_users_revenue / revenue, 2) AS new_users_revenue_share,			-- Доля выручки новых пользователей в общей выручке за 1 день
    100 - ROUND(100 * new_users_revenue / revenue, 2) AS old_users_revenue_share	-- Доля выручки остальных пользователей в общей выручке за 1 день
FROM users_revenue
ORDER BY date;
