-- ============================================================
-- 04_sales_analysis.sql
-- Project : Olist Marketplace Analytics (Brazil, 2016–2018)
-- Author  : Emiliia Ismailova
-- Tool    : SQLite (olist.sqlite)
-- Purpose : Sales, product and seller performance
-- Questions:
--   • How concentrated is revenue across product categories (Pareto)?
--   • Which categories grew the most from 2017 to 2018?
--   • How many items does a typical order contain?
--   • Which price bands drive orders and revenue?
--   • How do customers pay (payment type, installments)?
--   • How concentrated are sales among sellers?
-- Note: only orders with status 'delivered' are counted as completed.
-- ============================================================


-- ------------------------------------------------------------
-- 1. CATEGORY PARETO: cumulative share of product revenue
-- ------------------------------------------------------------
WITH category_revenue AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category,
        SUM(oi.price) AS revenue
    FROM order_items oi
    JOIN orders o   ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN category_translation t
                    ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY category
)
SELECT
    ROW_NUMBER() OVER (ORDER BY revenue DESC)                     AS rank,
    category,
    ROUND(revenue, 2)                                             AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)              AS revenue_share_pct,
    ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                     ROWS UNBOUNDED PRECEDING)
                / SUM(revenue) OVER (), 2)                        AS cumulative_share_pct
FROM category_revenue
ORDER BY revenue DESC;


-- ------------------------------------------------------------
-- 2. CATEGORY GROWTH: Jan–Aug 2018 vs Jan–Aug 2017
--    (same months compared, because 2018 data ends in late summer)
-- ------------------------------------------------------------
WITH yearly AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category,
        SUM(CASE WHEN strftime('%Y', o.order_purchase_timestamp) = '2017' THEN oi.price ELSE 0 END) AS revenue_2017,
        SUM(CASE WHEN strftime('%Y', o.order_purchase_timestamp) = '2018' THEN oi.price ELSE 0 END) AS revenue_2018
    FROM order_items oi
    JOIN orders o   ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN category_translation t
                    ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
      AND CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) BETWEEN 1 AND 8
    GROUP BY category
)
SELECT
    category,
    ROUND(revenue_2017, 2) AS revenue_2017_jan_aug,
    ROUND(revenue_2018, 2) AS revenue_2018_jan_aug,
    ROUND(100.0 * (revenue_2018 - revenue_2017) / NULLIF(revenue_2017, 0), 1) AS yoy_growth_pct
FROM yearly
WHERE revenue_2017 >= 10000          -- ignore very small categories
ORDER BY yoy_growth_pct DESC;


-- ------------------------------------------------------------
-- 3. BASKET SIZE: items per order
-- ------------------------------------------------------------
WITH basket AS (
    SELECT
        oi.order_id,
        COUNT(*)                         AS items,
        SUM(oi.price + oi.freight_value) AS order_total
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
)
SELECT
    CASE WHEN items >= 4 THEN '4+' ELSE CAST(items AS TEXT) END AS items_per_order,
    COUNT(*)                                                    AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_orders,
    ROUND(AVG(order_total), 2)                                  AS avg_order_value
FROM basket
GROUP BY items_per_order
ORDER BY items_per_order;


-- ------------------------------------------------------------
-- 4. PRICE BANDS: which item prices drive volume and revenue
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN oi.price < 50   THEN '1: < R$50'
        WHEN oi.price < 100  THEN '2: R$50–99'
        WHEN oi.price < 200  THEN '3: R$100–199'
        WHEN oi.price < 500  THEN '4: R$200–499'
        ELSE                      '5: R$500+'
    END                                                        AS price_band,
    COUNT(*)                                                   AS items_sold,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_items,
    ROUND(SUM(oi.price), 2)                                    AS revenue,
    ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 1) AS pct_of_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY price_band
ORDER BY price_band;


-- ------------------------------------------------------------
-- 5. PAYMENT METHODS
-- ------------------------------------------------------------
SELECT
    op.payment_type,
    COUNT(DISTINCT op.order_id)                                AS orders,
    ROUND(100.0 * COUNT(DISTINCT op.order_id)
          / (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered'), 1)
                                                               AS pct_of_orders,
    ROUND(SUM(op.payment_value), 2)                            AS payment_value,
    ROUND(AVG(op.payment_value), 2)                            AS avg_payment
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY op.payment_type
ORDER BY payment_value DESC;
-- Note: an order can use more than one payment type, so pct_of_orders
--       may add up to slightly more than 100%.


-- ------------------------------------------------------------
-- 6. CREDIT CARD INSTALLMENTS
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN op.payment_installments <= 1 THEN '01: 1 (single payment)'
        WHEN op.payment_installments <= 3 THEN '02: 2–3'
        WHEN op.payment_installments <= 6 THEN '03: 4–6'
        WHEN op.payment_installments <= 10 THEN '04: 7–10'
        ELSE                                  '05: 11+'
    END                                                        AS installments,
    COUNT(*)                                                   AS payments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_payments,
    ROUND(AVG(op.payment_value), 2)                            AS avg_payment_value
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND op.payment_type = 'credit_card'
GROUP BY installments
ORDER BY installments;


-- ------------------------------------------------------------
-- 7. SELLER CONCENTRATION: revenue share of top sellers
-- ------------------------------------------------------------
WITH seller_revenue AS (
    SELECT
        oi.seller_id,
        SUM(oi.price) AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
ranked AS (
    SELECT
        seller_id,
        revenue,
        NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM seller_revenue
)
SELECT
    decile                                                    AS seller_decile,   -- 1 = top 10% of sellers
    COUNT(*)                                                  AS sellers,
    ROUND(SUM(revenue), 2)                                    AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue
FROM ranked
GROUP BY decile
ORDER BY decile;


-- ------------------------------------------------------------
-- 8. TOP 10 SELLERS BY REVENUE (with average review score)
-- ------------------------------------------------------------
WITH seller_stats AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        COUNT(DISTINCT oi.order_id) AS orders,
        SUM(oi.price)               AS revenue
    FROM order_items oi
    JOIN orders o  ON oi.order_id = o.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id, s.seller_state
),
seller_reviews AS (
    SELECT
        x.seller_id,
        AVG(r.review_score) AS avg_review
    FROM (SELECT DISTINCT order_id, seller_id FROM order_items) x
    JOIN order_reviews r ON x.order_id = r.order_id
    GROUP BY x.seller_id
)
SELECT
    RANK() OVER (ORDER BY ss.revenue DESC) AS rank,
    ss.seller_id,
    ss.seller_state,
    ss.orders,
    ROUND(ss.revenue, 2)                   AS revenue,
    ROUND(sr.avg_review, 2)                AS avg_review_score
FROM seller_stats ss
LEFT JOIN seller_reviews sr ON ss.seller_id = sr.seller_id
ORDER BY ss.revenue DESC
LIMIT 10;
