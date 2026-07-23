-- ============================================================
-- 06_Review_Analysis.sql
-- Project : Ecommerce Customer Analytics (Olist Brazil)
-- Purpose : Analyse customer satisfaction and review patterns
-- Questions:
--   • What is the overall review score distribution?
--   • Which categories get the best and worst reviews?
--   • What factors drive low (1-2 star) reviews?
--   • How does delivery experience relate to satisfaction?
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERALL REVIEW SCORE DISTRIBUTION
-- ------------------------------------------------------------
SELECT
    review_score,
    COUNT(*)                                             AS reviews,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)    AS pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;


-- ------------------------------------------------------------
-- 2. AVERAGE SCORE AND SATISFACTION METRICS
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                    AS total_reviews,
    ROUND(AVG(review_score), 2)                                 AS avg_score,
    ROUND(
        100.0 * SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*),
        1
    )                                                           AS pct_positive,
    ROUND(
        100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*),
        1
    )                                                           AS pct_negative
FROM order_reviews;


-- ------------------------------------------------------------
-- 3. REVIEW SCORES BY PRODUCT CATEGORY
-- ------------------------------------------------------------
WITH order_categories AS (
    SELECT DISTINCT
        oi.order_id,
        COALESCE(
            t.product_category_name_english,
            p.product_category_name,
            'Unknown'
        ) AS category
    FROM order_items oi
    JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation t
        ON p.product_category_name = t.product_category_name
)

SELECT
    oc.category,
    COUNT(r.review_id)                                        AS review_count,
    ROUND(AVG(r.review_score), 2)                             AS avg_score,
    SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END)       AS five_star,
    SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END)       AS one_star,
    ROUND(
        100.0 *
        SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END)
        / COUNT(*),
        1
    )                                                         AS pct_one_star
FROM order_reviews r
JOIN orders o
    ON r.order_id = o.order_id
JOIN order_categories oc
    ON o.order_id = oc.order_id
WHERE o.order_status = 'delivered'
GROUP BY oc.category
HAVING COUNT(r.review_id) > 50
ORDER BY avg_score DESC;



-- ------------------------------------------------------------
-- 4. REVIEW SCORE BY STATE
-- ------------------------------------------------------------
SELECT
    c.customer_state                                        AS state,
    COUNT(r.review_id)                                      AS reviews,
    ROUND(AVG(r.review_score), 2)                           AS avg_score,
    ROUND(
        100.0 *
        SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*),
        1
    )                                                       AS pct_positive
FROM order_reviews r
JOIN orders o
    ON r.order_id = o.order_id
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY avg_score ASC;


