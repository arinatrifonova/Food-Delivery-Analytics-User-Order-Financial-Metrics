-- Этот запрос рассчитывает, какие товары пользуются наибольшим спросом и приносят нам основной доход

-- В CTE product_revenue рассчитывается выручка по каждому товару и общая выручка
WITH product_revenue AS (
    SELECT
        name AS product_name,											-- Название продукта
        COUNT(product_id) * MAX(price) AS revenue,						-- Доход с товара 1 категории
        SUM(COUNT(product_id) * MAX(price)) OVER () AS total_revenue	-- Общая выручка за весь период
    FROM (
        SELECT
            order_id,
            UNNEST(product_ids) AS product_id,							-- Из массива товаров получаем id каждого купленного товара 
            creation_time::date AS date
        FROM orders
    ) AS prepared_orders
    LEFT JOIN products USING (product_id)								-- Объединяем данные о заказах с таблицей товаров
    WHERE order_id NOT IN (												-- Исключаем отмененные заказы из рассчетов
        SELECT order_id
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY name
),

-- В CTE product_revenue_share рассчитываем долю каждого товара в общей выручке
-- Товары с долей < 0.5% объединяются в категорию "ДРУГОЕ"
product_revenue_share AS (
    SELECT
        CASE
            WHEN revenue / total_revenue < 0.005 THEN 'ДРУГОЕ'
            ELSE product_name
        END AS product_name,
        revenue,
        ROUND(100 * revenue / total_revenue, 2) AS share			-- Рассчитываем долю товара в общей выручке в процентах
    FROM product_revenue
)

SELECT
    product_name,						-- Название категории
    SUM(revenue) AS revenue,			-- Выручка от товара 1 категории
    SUM(share) AS share_in_revenue		-- Доля выручки от товара 1 категории
FROM product_revenue_share 
GROUP BY product_name
ORDER BY revenue DESC;
