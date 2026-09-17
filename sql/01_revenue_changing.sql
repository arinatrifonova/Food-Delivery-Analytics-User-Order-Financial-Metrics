-- Этот запрос считает дневную выручку, накопительную выручку и изменение выручки относительно предыдущего дня

-- В CTE daily_revenue рассчитываем дневную выручку
-- UNNEST преобразует массив product_ids в отдельные строки, затем данные объединяются с таблицей Products для получения стоимости товаров
-- Отмененные заказы исключаются из рассчетов
WITH daily_revenue AS (
    SELECT
        date,					
        SUM(price) AS revenue						-- Дневная выручка
    FROM (											
		SELECT 
			order_id,
			UNNEST(product_ids) AS product_id,		-- Из массива товаров получаем id каждого купленного товара 
			creation_time::date AS date
        FROM orders
	) AS t
    LEFT JOIN products USING (product_id)			-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (							-- Исключаем отмененные заказы из рассчетов
		SELECT order_id 
		FROM user_actions 
		WHERE action = 'cancel_order'
	)
    GROUP BY date
)

SELECT
    date,																		-- Конкретный день
    revenue,																	-- Выручка за конкретный день
    SUM(revenue) OVER (ORDER BY date) AS total_revenue,							-- Накопительная выручка с начала периода
    ROUND(100 * (revenue - LAG(revenue, 1) OVER (ORDER BY date))::decimal /		-- Изменение выручки относительно предыдущего дня в процентах
					LAG(revenue, 1) OVER (), 2) AS revenue_change
FROM daily_revenue
ORDER BY date;
