-- ============================================================
-- 02_business_kpis.sql
-- Project : Olist Marketplace Analytics (Brazil, 2016–2018)
-- Author  : Emiliia Ismailova
-- Tool    : SQLite (olist.sqlite)
-- Purpose : Executive KPIs used to evaluate overall business performance
-- Questions:
--   • How many completed orders, customers and active sellers are there?
--   • What is the product, freight and total revenue?
--   • What is the average order value (AOV)?
--   • How does revenue change by month and quarter?
--   • When do customers order (weekday / hour)?
--   • Which categories and states generate the most revenue?
-- Note: only orders with status 'delivered' are counted as completed.
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERALL BUSINESS SNAPSHOT
--    Revenue is aggregated per order first, so joining items
--    does not multiply order totals (avoids join fan-out).
-- ------------------------------------------------------------
WITH order_totals AS (
    SELECT
        order_id,
        SUM(price)                 AS product_amount,
        SUM(freight_value)         AS freight_amount,
        SUM(price + freight_value) AS order_total
    FROM order_items
    GROUP BY order_id
),
delivered AS (
    SELECT o.order_id, o.customer_id, ot.product_amount, ot.freight_amount, ot.order_total
    FROM orders o
    JOIN order_totals ot ON o.order_id = ot.order_id
    WHERE o.order_status = 'delivered'
)
SELECT
    COUNT(*)                                    AS total_orders,
    (SELECT COUNT(DISTINCT c.customer_unique_id)
       FROM delivered d
       JOIN customers c ON d.customer_id = c.customer_id) AS unique_customers,
    (SELECT COUNT(DISTINCT oi.seller_id)
       FROM order_items oi
       JOIN delivered d ON oi.order_id = d.order_id)      AS active_sellers,
    ROUND(SUM(product_amount), 2)               AS product_revenue,
    ROUND(SUM(freight_amount), 2)               AS freight_revenue,
    ROUND(SUM(order_total), 2)                  AS total_revenue,
    ROUND(AVG(order_total), 2)                  AS average_order_value,
    ROUND(100.0 * SUM(freight_amount) / SUM(order_total), 2) AS freight_share_pct
FROM delivered;


-- ------------------------------------------------------------
-- 2. MONTHLY REVENUE TREND (with month-over-month growth)
-- ------------------------------------------------------------
WITH order_totals AS (
    SELECT order_id, SUM(price + freight_value) AS order_total
    FROM order_items
    GROUP BY order_id
),
monthly_sales AS (
    SELECT
        strftime('%Y-%m', o.order_purchase_timestamp) AS month,
        COUNT(DISTINCT o.order_id)                     AS total_orders,
        COUNT(DISTINCT o.customer_id)                  AS total_customers,
        SUM(ot.order_total)                            AS revenue,
        AVG(ot.order_total)                            AS average_order_value
    FROM orders o
    JOIN order_totals ot ON o.order_id = ot.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY month
)
SELECT
    month,
    total_orders,
    total_customers,
    ROUND(revenue, 2)             AS revenue,
    ROUND(average_order_value, 2) AS average_order_value,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month), 2
    )                             AS mom_growth_pct
FROM monthly_sales
ORDER BY month;


-- ------------------------------------------------------------
-- 3. QUARTERLY PERFORMANCE
-- ------------------------------------------------------------
WITH order_totals AS (
    SELECT order_id, SUM(price + freight_value) AS order_total
    FROM order_items
    GROUP BY order_id
)
SELECT
    strftime('%Y', o.order_purchase_timestamp) AS year,
    'Q' || ((CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) + 2) / 3) AS quarter,
    COUNT(DISTINCT o.order_id)    AS total_orders,
    ROUND(SUM(ot.order_total), 2) AS revenue,
    ROUND(AVG(ot.order_total), 2) AS average_order_value
FROM orders o
JOIN order_totals ot ON o.order_id = ot.order_id
WHERE o.order_status = 'delivered'
GROUP BY year, quarter
ORDER BY year, quarter;


-- ------------------------------------------------------------
-- 4.1 ORDERS BY DAY OF WEEK
-- ------------------------------------------------------------
SELECT
    CAST(strftime('%w', order_purchase_timestamp) AS INTEGER) AS weekday_num,
    CASE CAST(strftime('%w', order_purchase_timestamp) AS INTEGER)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END                                                       AS day_of_week,
    COUNT(*)                                                  AS total_orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY weekday_num, day_of_week
ORDER BY weekday_num;


-- ------------------------------------------------------------
-- 4.2 ORDERS BY HOUR OF DAY
-- ------------------------------------------------------------
SELECT
    CAST(strftime('%H', order_purchase_timestamp) AS INTEGER) AS hour_of_day,
    COUNT(*)                                                  AS total_orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- ------------------------------------------------------------
-- 5. PRODUCT CATEGORY PERFORMANCE
-- ------------------------------------------------------------
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2)    AS product_revenue,
    ROUND(AVG(oi.price), 2)    AS average_item_price,
    ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 2) AS revenue_share_pct
FROM order_items oi
JOIN orders o               ON oi.order_id = o.order_id
JOIN products p             ON oi.product_id = p.product_id
LEFT JOIN category_translation t
                            ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY product_revenue DESC;


-- ------------------------------------------------------------
-- 6. REGIONAL PERFORMANCE (by customer state)
-- ------------------------------------------------------------
WITH order_totals AS (
    SELECT order_id, SUM(price + freight_value) AS order_total
    FROM order_items
    GROUP BY order_id
)
SELECT
    c.customer_state              AS state,
    COUNT(DISTINCT o.order_id)    AS total_orders,
    ROUND(SUM(ot.order_total), 2) AS revenue,
    ROUND(AVG(ot.order_total), 2) AS average_order_value,
    ROUND(100.0 * SUM(ot.order_total) / SUM(SUM(ot.order_total)) OVER (), 2) AS revenue_share_pct
FROM orders o
JOIN customers c     ON o.customer_id = c.customer_id
JOIN order_totals ot ON o.order_id = ot.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue DESC;
