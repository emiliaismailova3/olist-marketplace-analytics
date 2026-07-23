-- ============================================================
-- 05_Delivery_Analysis.sql
-- Project : Ecommerce Customer Analytics (Olist Brazil)
-- Purpose : Analyse delivery performance and logistics efficiency
-- Questions:
--   • What is the average delivery time overall and by state?
--   • How often are orders delivered late vs on time?
--   • Which states have the worst delivery performance?
--   • Does delivery speed affect review scores?
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERALL DELIVERY TIME STATS
-- ------------------------------------------------------------
SELECT
    COUNT(*)                          AS delivered_orders,
    ROUND(AVG(
        julianday(order_delivered_customer_date) -
        julianday(order_purchase_timestamp)
    ), 1)                             AS avg_delivery_days,
    ROUND(MIN(
        julianday(order_delivered_customer_date) -
        julianday(order_purchase_timestamp)
    ), 1)                             AS min_delivery_days,
    ROUND(MAX(
        julianday(order_delivered_customer_date) -
        julianday(order_purchase_timestamp)
    ), 1)                             AS max_delivery_days,
    -- Estimated vs actual
    ROUND(AVG(
        julianday(order_estimated_delivery_date) -
        julianday(order_purchase_timestamp)
    ), 1)                             AS avg_estimated_days
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


-- ------------------------------------------------------------
-- 2. ON-TIME vs LATE DELIVERIES
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'On Time'
        ELSE 'Late'
    END                                                     AS delivery_status,
    COUNT(*)                                                AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1)      AS pct,
    ROUND(AVG(
        julianday(order_delivered_customer_date) -
        julianday(order_estimated_delivery_date)
    ), 1)                                                   AS avg_days_diff
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL
GROUP BY delivery_status;


-- ------------------------------------------------------------
-- 3. DELIVERY PERFORMANCE BY STATE
-- ------------------------------------------------------------
SELECT
    c.customer_state                        AS state,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(AVG(
        julianday(o.order_delivered_customer_date) -
        julianday(o.order_purchase_timestamp)
    ), 1)                                   AS avg_delivery_days,
    SUM(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
        ELSE 0
    END)                                    AS late_orders,
    ROUND(100.0 * SUM(CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
        ELSE 0
    END) / COUNT(*), 1)                     AS late_rate_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;



-- ------------------------------------------------------------
-- 4. IMPACT OF DELIVERY SPEED ON REVIEW SCORE
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN delivery_days <= 7  THEN '01: Fast (≤7 days)'
        WHEN delivery_days <= 14 THEN '02: Normal (8-14 days)'
        WHEN delivery_days <= 21 THEN '03: Slow (15-21 days)'
        ELSE                          '04: Very Slow (21+ days)'
    END                             AS speed_bucket,
    COUNT(*)                        AS orders,
    ROUND(AVG(r.review_score), 2)   AS avg_review_score
FROM (
    SELECT
        o.order_id,
        CAST(julianday(o.order_delivered_customer_date) -
             julianday(o.order_purchase_timestamp) AS INT) AS delivery_days
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
) d
JOIN order_reviews r ON d.order_id = r.order_id
GROUP BY speed_bucket
ORDER BY speed_bucket;


