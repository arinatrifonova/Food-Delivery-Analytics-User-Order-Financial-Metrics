-- Этот запрос возвращет накопленные ARPU, ARPPU и AOV 

-- В CTE daily_revenue рассчитываем дневную выручку и количество заказов
-- UNNEST преобразует массив product_ids в отдельные строки, затем данные объединяются с таблицей Products для получения стоимости товаров
-- Отмененные заказы исключаются из рассчетов
WITH daily_revenue AS (
    SELECT
        date,
        SUM(price) AS revenue,						-- Дневная выручка
        COUNT(DISTINCT order_id) AS orders_count	-- Количество заказов
    FROM (
		SELECT 
			order_id,
          	UNNEST(product_ids) AS product_id,		-- Из массива товаров получаем id каждого купленного товара 
		    creation_time::date AS date
        FROM orders
    ) AS prepared_orders
    LEFT JOIN products USING (product_id)			-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (							-- Исключаем отмененные заказы из рассчетов
        SELECT order_id
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY date
),

-- В CTE dates_array собираем даты активности каждого пользователя,
-- чтобы каждый пользователь учитывался в накопительных метриках только один раз
-- Первый элемент массива это дата первого появления пользователя
dates_array AS (
    SELECT
        ARRAY_AGG(time::date ORDER BY time::date) AS dates_users,
        ARRAY_AGG(time::date ORDER BY time::date) FILTER (
            WHERE order_id NOT IN (
                SELECT order_id
                FROM user_actions
                WHERE action = 'cancel_order'
            )
        ) AS dates_paying_users,
        user_id
    FROM user_actions
    GROUP BY user_id
),

-- В CTE daily_new_users с помощью данных из dates_array находим количество новых и новых платящих пользователей
daily_new_users AS (
    SELECT
        time::date AS date,
        COUNT(DISTINCT user_id) FILTER (				-- Количество пользователей, для которых 
			WHERE time::date = dates_users[1]			-- текущая дата - это дата их первого появления в сервисе
		) AS count_new_users,
        COUNT(DISTINCT user_id) FILTER (				-- Количество пользователей, для которых 
			WHERE time::date = dates_paying_users[1]	-- текущая дата - это дата их первой активности
		) AS count_paying_new_users
    FROM dates_array
    LEFT JOIN user_actions USING (user_id)
    GROUP BY time::date
)

SELECT
    date,																			-- Конкретный день
    ROUND(SUM(revenue) OVER (ORDER BY date) / 										-- Накопленнаня выручка на 1 пользователя
		  SUM(count_new_users) OVER (ORDER BY date), 2) AS running_arpu,		
    ROUND(SUM(revenue) OVER (ORDER BY date) / 										-- Накопленная выручка на 1 платящего пользователя
		  SUM(count_paying_new_users) OVER (ORDER BY date), 2) AS running_arppu,	
    ROUND(SUM(revenue) OVER (ORDER BY date) / 										-- Накопленная выручка с 1 заказа	
	      SUM(orders_count) OVER (ORDER BY date), 2) AS running_aov
FROM daily_revenue
LEFT JOIN daily_new_users USING (date)
ORDER BY date;
