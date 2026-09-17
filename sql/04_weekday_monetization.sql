-- Этот запрос направлен на сравнение ARPU, ARPPU и AOV по дням недели
-- Анализ проводится с 26 августа по 8 сентября 2022 года

-- В CTE daily_revenue рассчитываем дневную выручку и количество заказов
-- UNNEST преобразует массив product_ids в отдельные строки, затем данные объединяются с таблицей Products для получения стоимости товаров
-- Отмененные заказы исключаются из рассчетов
WITH daily_revenue AS (
    SELECT
        weekday,
        SUM(price) AS revenue,							-- Дневная выручка
        COUNT(DISTINCT order_id) AS orders_count		-- Количество заказов
    FROM (
        SELECT
            order_id,
            UNNEST(product_ids) AS product_id,	
            TO_CHAR(creation_time, 'day') AS weekday	-- Из массива товаров получаем id каждого купленного товара 
        FROM orders
        WHERE 
			creation_time >= '2022-08-26'
          	AND creation_time < '2022-09-09'
    ) AS prepared_orders
    LEFT JOIN products USING (product_id)				-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (								-- Исключаем отмененные заказы из рассчетов
        SELECT order_id
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY weekday
),

-- CTE daily_users рассчитывает количество всех пользователей и платящих пользователей по дням недели
daily_users AS (
    SELECT
        TO_CHAR(time, 'day') AS weekday,				
		DATE_PART('isodow', time) AS weekday_number,	-- Определяем порядковый номер дня недели для корректной сортировки
        COUNT(DISTINCT user_id) AS count_users,			-- Количество уникальных пользователей в сервисе
        COUNT(DISTINCT user_id) FILTER (				-- Количество платящих пользователей
            WHERE order_id NOT IN (
                SELECT order_id
                FROM user_actions
                WHERE action = 'cancel_order'
            )
        ) AS paying_users
    FROM user_actions
    WHERE time >= '2022-08-26'
      	  AND time < '2022-09-09'
    GROUP BY 
		TO_CHAR(time, 'day'),
		DATE_PART('isodow', time) 
)

SELECT
    INITCAP(weekday) AS weekday,				-- День недели
    weekday_number,								-- Номер дня недели
    ROUND(revenue / count_users, 2) AS arpu,	-- Средняя выручка на 1 пользователя
    ROUND(revenue / paying_users, 2) AS arppu,	-- Средняя выручка на 1 платящего пользователя
    ROUND(revenue / orders_count, 2) AS aov		-- Средняя стоимость 1 заказа
FROM daily_revenue 
LEFT JOIN daily_users USING (weekday)
ORDER BY weekday_number;
