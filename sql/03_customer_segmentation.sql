-- ============================================================
-- 03_Customer_Analysis.sql
-- Project : Ecommerce Customer Analytics (Olist Brazil)
-- Purpose : Understand customer behaviour, segmentation, and value
-- Questions:
--   • What share of customers are one-time vs repeat buyers?
--   • Which cities/states have the most valuable customers?
--   • How can we segment customers by RFM (Recency, Frequency, Monetary)?
--   • What is the average customer lifetime value?
-- ============================================================


-- ------------------------------------------------------------
-- 1. ONE-TIME vs REPEAT CUSTOMERS
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT o.order_id)                 AS total_orders,
        -- Правка 1+3: считаем полную сумму заказа (товар + доставка)
        ROUND(SUM(oi.price + oi.freight_value), 2) AS total_spent
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN customers c    ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN total_orders = 1 THEN '1_One-time'
        WHEN total_orders = 2 THEN '2_Two orders'
        ELSE '3_Loyal (3+)'
    END                                              AS segment,
    COUNT(*)                                         AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct_of_customers,
    ROUND(AVG(total_spent), 2)                       AS avg_lifetime_spend
FROM customer_orders
GROUP BY segment
ORDER BY segment;


-- ------------------------------------------------------------
-- 2. TOP 10 CITIES BY CUSTOMER COUNT AND REVENUE
-- ------------------------------------------------------------
SELECT
    c.customer_city                          AS city,
    c.customer_state                         AS state,
    COUNT(DISTINCT c.customer_unique_id)     AS unique_customers,
    COUNT(DISTINCT o.order_id)               AS total_orders,
    -- Правка 3: полная выручка включая доставку
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    -- Правка 1: настоящий AOV = сумма заказа / кол-во заказов
    ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM customers c
JOIN orders o       ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id    = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_city, c.customer_state
ORDER BY unique_customers DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 3. RFM SEGMENTATION
--    R = days since last purchase (lower = better)
--    F = number of orders
--    M = total amount spent
-- ------------------------------------------------------------
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(DATE(o.order_purchase_timestamp))  AS last_purchase_date,
        COUNT(DISTINCT o.order_id)             AS frequency,
        -- Правка 3: monetary = полная сумма включая доставку
        ROUND(SUM(oi.price + oi.freight_value), 2) AS monetary
    FROM customers c
    JOIN orders o       ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        last_purchase_date,
        CAST(julianday('2018-10-01') - julianday(last_purchase_date) AS INT) AS recency_days,
        frequency,
        monetary,
        -- Score 1-3 for each dimension (3 = best)
        -- Правка 2: ASC для recency — чем меньше дней, тем выше score
      4-NTILE(3) OVER (ORDER BY julianday('2018-10-01') - julianday(last_purchase_date) ASC) AS r_score,
        NTILE(3) OVER (ORDER BY frequency)  AS f_score,
        NTILE(3) OVER (ORDER BY monetary)   AS m_score
    FROM rfm_base
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN (r_score + f_score + m_score) >= 8 THEN 'Champions'
        WHEN (r_score + f_score + m_score) >= 6 THEN 'Loyal'
        WHEN r_score >= 2 AND f_score = 1       THEN 'Promising'
        WHEN r_score = 1 AND f_score >= 2       THEN 'At Risk'
        ELSE 'Lost'
    END AS rfm_segment
FROM rfm_scored
ORDER BY rfm_total DESC
LIMIT 100;  -- remove LIMIT to get full table





-- ------------------------------------------------------------
-- 4. CUSTOMER LIFETIME VALUE (CLV) — simplified
-- ------------------------------------------------------------
WITH customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)                                  AS total_orders,
        -- Правка 3: полная сумма включая доставку
        ROUND(SUM(oi.price + oi.freight_value), 2)                  AS total_spent,
        MIN(DATE(o.order_purchase_timestamp))                        AS first_order,
        MAX(DATE(o.order_purchase_timestamp))                        AS last_order,
        CAST(julianday(MAX(o.order_purchase_timestamp)) -
             julianday(MIN(o.order_purchase_timestamp)) AS INT)      AS active_days
    FROM customers c
    JOIN orders o       ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    ROUND(AVG(total_spent), 2)                     AS avg_clv,
    ROUND(AVG(total_orders), 2)                    AS avg_orders_per_customer,
    -- Правка 1: настоящий AOV = total_spent / total_orders
    ROUND(AVG(total_spent / total_orders), 2)      AS avg_order_value,
    MAX(total_spent)                                AS max_clv,
    COUNT(CASE WHEN total_orders > 1 THEN 1 END)   AS repeat_customers,
    COUNT(*)                                        AS total_customers
FROM customer_summary;


-- ------------------------------------------------------------
-- 5. TOP 20 CUSTOMERS BY REVENUE WITH RANK()
-- ------------------------------------------------------------
-- Правка 4: добавлен RANK() для ранжирования клиентов
WITH customer_totals AS (
    SELECT
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        COUNT(DISTINCT o.order_id)                  AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2)  AS total_spent
    FROM customers c
    JOIN orders o       ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    RANK() OVER (ORDER BY total_spent DESC)              AS rank,
    customer_unique_id,
    customer_city,
    customer_state,
    total_orders,
    total_spent,
    ROUND(100.0 * total_spent / SUM(total_spent) OVER(), 4) AS pct_of_revenue
FROM customer_totals
ORDER BY rank
LIMIT 20;


