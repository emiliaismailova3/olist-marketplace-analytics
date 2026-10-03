-- ============================================================
-- 03_customer_segmentation.sql
-- Project : Olist Marketplace Analytics (Brazil, 2016–2018)
-- Author  : Emiliia Ismailova
-- Purpose : Understand customer behaviour, segmentation, and value
-- Note    : revenue = price + freight_value (full amount paid by the customer);
--           customers are identified by customer_unique_id.
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
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
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
--    R = days since last purchase (lower = better), scored by tertiles
--    F = number of orders. ~97% of customers buy only once, so NTILE
--        would split identical values randomly; fixed thresholds are
--        used instead: 1 order = 1, 2 orders = 2, 3+ orders = 3
--    M = total amount spent, scored by tertiles
--    Reference date = day after the last order in the dataset
-- ------------------------------------------------------------
WITH ref AS (
    SELECT julianday(MAX(DATE(order_purchase_timestamp))) + 1 AS ref_day
    FROM orders
),
rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(DATE(o.order_purchase_timestamp))      AS last_purchase_date,
        COUNT(DISTINCT o.order_id)                 AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS monetary
    FROM customers c
    JOIN orders o       ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT
        b.customer_unique_id,
        b.last_purchase_date,
        CAST(r.ref_day - julianday(b.last_purchase_date) AS INT) AS recency_days,
        b.frequency,
        b.monetary,
        -- Scores 1-3 for each dimension (3 = best)
        4 - NTILE(3) OVER (ORDER BY r.ref_day - julianday(b.last_purchase_date)) AS r_score,
        CASE WHEN b.frequency >= 3 THEN 3
             WHEN b.frequency = 2  THEN 2
             ELSE 1 END                                                          AS f_score,
        NTILE(3) OVER (ORDER BY b.monetary)                                      AS m_score
    FROM rfm_base b
    CROSS JOIN ref r
),
rfm_segmented AS (
    SELECT
        *,
        (r_score + f_score + m_score) AS rfm_total,
        CASE
            WHEN f_score >= 2 AND r_score >= 2 AND m_score = 3 THEN 'Champions'
            WHEN f_score >= 2                                  THEN 'Loyal'
            WHEN r_score = 3                                   THEN 'New / Recent'
            WHEN m_score = 3                                   THEN 'At Risk (High Value)'
            ELSE 'Lost / Low Value'
        END AS rfm_segment
    FROM rfm_scored
)

-- 3a. Segment summary (used in the dashboards)
SELECT
    rfm_segment,
    COUNT(*)                                           AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
    ROUND(AVG(recency_days), 0)                        AS avg_recency_days,
    ROUND(AVG(frequency), 2)                           AS avg_frequency,
    ROUND(AVG(monetary), 2)                            AS avg_monetary,
    ROUND(SUM(monetary), 2)                            AS total_revenue
FROM rfm_segmented
GROUP BY rfm_segment
ORDER BY total_revenue DESC;

-- 3b. Customer-level RFM table: run the CTEs above with
--     SELECT * FROM rfm_segmented ORDER BY rfm_total DESC;


-- ------------------------------------------------------------
-- 4. CUSTOMER LIFETIME VALUE (CLV) — simplified
-- ------------------------------------------------------------
WITH customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)                                  AS total_orders,
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
    ROUND(AVG(total_spent / total_orders), 2)      AS avg_order_value,
    MAX(total_spent)                                AS max_clv,
    COUNT(CASE WHEN total_orders > 1 THEN 1 END)   AS repeat_customers,
    COUNT(*)                                        AS total_customers
FROM customer_summary;


-- ------------------------------------------------------------
-- 5. TOP 20 CUSTOMERS BY REVENUE WITH RANK()
-- ------------------------------------------------------------
WITH customer_totals AS (
    SELECT
        c.customer_unique_id,
        MAX(c.customer_city)                        AS customer_city,
        MAX(c.customer_state)                       AS customer_state,
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


