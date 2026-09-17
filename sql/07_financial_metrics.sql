-- В этом запросе рассчитывается НДС, валовая прибыль, выручка и затраты по дням

-- Также учитывались следующие условия: 
-- 1) Постоянные затраты за август 2022 года 120 000 рублей в день, 
-- 	  постоянные затраты за сентябрь 2022 года 150 000 рублей в день;
-- 2) Переменные затраты за август 2022 года: 140 рублей за сборку 1 заказа,
-- 	  150 рублей оплата 1 доставки курьеру 
--    + бонус 400 рублей если курьер доставил не менее 5 заказов за день;
-- 3) Переменные затраты за сентябрь 2022 года: 115 рублей за сборку 1 заказа,
-- 	  150 рублей оплата 1 доставки курьеру 
--    + бонус 500 рублей если курьер доставил не менее 5 заказов за день;
-- 4) НДС для некоторых товаров составляет 10%, а не 20%

-- В CTE daily_revenue рассчитывается дневная выручка по всем неотмененным заказам
WITH daily_revenue AS (
    SELECT
        date,										-- Дата создания заказа
        SUM(price) AS revenue						-- Общая выручка за день
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

-- В CTE daily_orders рассчитывается количество доставленных заказов по дням 
-- и определяется месяц, к которому относится дата (для соблюдения условий рассчета)
daily_orders AS (
    SELECT
        time::date AS date,										-- Дата действия курьера	
        COUNT(order_id) FILTER (								-- Количество дотсавленных заказов
			WHERE action = 'deliver_order'
		) AS orders_count,
        CASE
            WHEN time::date >= '2022-08-01' 
				AND time::date < '2022-09-01' THEN 'август'		-- Месяц доставки
            WHEN time::date >= '2022-09-01' 
				AND time::date < '2022-10-01' THEN 'сентябрь'	
        END AS orders_month
    FROM courier_actions
    WHERE order_id NOT IN (										-- Исключаем отмененные заказы из рассчетов
        SELECT order_id
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY time::date
),

-- В CTE daily_deliveries рассчитываем количество принятых заказов по дате их создания
-- Необходимо для рассчета затрат на сборку заказа
daily_deliveries AS (
    SELECT
        creation_time::date AS date,			-- Дата создания заказа
        COUNT(order_id) FILTER (				-- Количество принятых заказов
            WHERE order_id IN (
                SELECT order_id
                FROM courier_actions
                WHERE action = 'accept_order'
            )
        ) AS delivered_orders_count
    FROM orders
    WHERE order_id NOT IN (						-- Исключаем отмененные заказы из рассчетов
        SELECT order_id
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY creation_time::date
),

-- В CTE courier_bonuses определяем количество курьеров, выполнивших 5 и более заказов за день
-- Необходимо для верного рассчета затрат на бонусы курьерам 
courier_bonuses  AS (
    SELECT
        date,													-- Дата доставки
        COUNT(count_order_per_courier) AS couriers_with_bonus	-- Количество курьеров, которые получают бонус за день
    FROM (														-- Считаем количество доставок каждого курьера за день
        SELECT
            time::date AS date,
            courier_id,
            COUNT(order_id) AS count_order_per_courier
        FROM courier_actions
        WHERE order_id NOT IN (									-- Исключаем отмененные заказы
            SELECT order_id
            FROM user_actions
            WHERE action = 'cancel_order'
        )
          AND action = 'deliver_order'											
        GROUP BY time::date, courier_id
        HAVING COUNT(order_id) >= 5								-- Оставляем курьеров, доставивших минимум 5 заказов за день
    ) AS courier_daily_orders
    GROUP BY date
),

-- В CTE taxes рассчитываем сумму НДС по товарам за каждый день
taxes AS (
    SELECT
        date,										-- Дата дотсавки заказа											
        SUM(
            CASE
                WHEN name IN ( 
                    'сахар', 'сухарики', 'сушки', 'семечки', 'масло льняное', 					-- Товары с пониженной НДС
					'виноград', 'рис', 'масло оливковое', 'арбуз', 'батон', 'йогурт',
					'сливки', 'гречка', 'лаваш', 'овсянка', 'макароны', 'баранина',
					'апельсины', 'бублики', 'хлеб', 'горох', 'сметана', 'рыба копченая',
					'мука', 'шпроты', 'сосиски', 'свинина', 'вафли', 'масло кунжутное',
					'сгущенка', 'ананас', 'говядина', 'соль', 'рыба вяленая', 'мандарины',		
                    'масло подсолнечное', 'яблоки', 'груши', 'лепешка', 'молоко', 'курица',
                )
                THEN ROUND(price * 10 / 110, 2)		-- Извлекаем НДС из цены товара (пониженная ставка)
                ELSE ROUND(price * 20 / 120, 2)		-- Извлекаем НДС из цены остальных товаров
            END
        ) AS tax
    FROM (
        SELECT
            order_id,
            UNNEST(product_ids) AS product_id,		-- Из массива товаров получаем id каждого купленного товара 
            creation_time::date AS date
        FROM orders
    ) AS prepared_orders
    LEFT JOIN products USING (product_id)
    WHERE order_id NOT IN (							-- Исключаем отмененные заказы из рассчетов
        SELECT order_id	
        FROM user_actions
        WHERE action = 'cancel_order'
    )
    GROUP BY date
),

-- В CTE daily_costs объединяем все рассчитанные показатели и находим дневные затраты
daily_costs AS (
    SELECT
        date,																	-- Дата доставки
        CASE
            WHEN MIN(orders_month) = 'август'									-- Рассчет затрат за сентябрь
                THEN 120000 * COUNT(date) + 140 * SUM(delivered_orders_count)	
                   + 150 * SUM(orders_count) 
				   + SUM(COALESCE(couriers_with_bonus, 0)) * 400
            WHEN MIN(orders_month) = 'сентябрь'
                THEN 150000 * COUNT(date) + 115 * SUM(delivered_orders_count)	-- Рассчет затрат за август
                   + 150 * SUM(orders_count) 
				   + SUM(COALESCE(couriers_with_bonus, 0)) * 500
        END AS costs,
        MAX(tax) AS tax															-- Получаем рассчитанную сумму НДС за день
    FROM daily_orders 
    LEFT JOIN courier_bonuses USING (date)
    LEFT JOIN daily_deliveries USING (date)
    LEFT JOIN taxes USING (date)
    GROUP BY date
)

SELECT
    date,																		-- Дата
    revenue,																	-- Выручка за день
    costs,																		-- Затраты за день
    tax,																		-- НДС за день
    revenue - costs - tax AS gross_profit,										-- Валовая прибыль за день
    SUM(revenue) OVER (ORDER BY date) AS total_revenue,							-- Накопленная выручка
    SUM(costs) OVER (ORDER BY date) AS total_costs,								-- Накопленные затраты
    SUM(tax) OVER (ORDER BY date) AS total_tax,									-- Накопленный НДС
    SUM(revenue - costs - tax) OVER (ORDER BY date) AS total_gross_profit,		-- Накопленная валовая прибыль
    ROUND(100 * (revenue - costs - tax) / revenue, 2) AS gross_profit_ratio,	-- Доля валовой прибыли в дневной выручке в %
    ROUND(100 * SUM(revenue - costs - tax) OVER (ORDER BY date) /				-- Доля накопленной прибыли в дневной выручке в %
			SUM(revenue) OVER (ORDER BY date), 2) AS total_gross_profit_ratio

FROM daily_costs 
LEFT JOIN daily_revenue USING (date);
