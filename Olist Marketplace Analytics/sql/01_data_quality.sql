-- ============================================================
-- 01_Data_Quality.sql
-- Project : Ecommerce Customer Analytics (Olist Brazil)
-- Purpose : Validate dataset integrity before any analysis
-- Questions:
--   • Are there NULL values in critical columns?
--   • Are there duplicate records?
--   • What is the actual date range of orders?
--   • Are all foreign keys consistent across tables?
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERVIEW: Row counts for all tables
-- ------------------------------------------------------------
SELECT 'orders'            AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'order_items',                     COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments',                  COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews',                   COUNT(*) FROM order_reviews
UNION ALL
SELECT 'customers',                       COUNT(*) FROM customers
UNION ALL
SELECT 'sellers',                         COUNT(*) FROM sellers
UNION ALL
SELECT 'products',                        COUNT(*) FROM products
UNION ALL
SELECT 'product_category_name_translation', COUNT(*) FROM category_translation;


-- ------------------------------------------------------------
-- 2. NULL CHECK: Critical columns in orders table
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                          AS total_orders,
    SUM(CASE WHEN order_id           IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN customer_id        IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_status       IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_date,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_delivery_date
FROM orders;

SELECT
    order_status,
    COUNT(*) AS orders_with_null_delivery
FROM orders
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status
ORDER BY orders_with_null_delivery DESC;

-- ------------------------------------------------------------
-- 3. NULL CHECK: Products table (common source of gaps)
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                        AS total_products,
    SUM(CASE WHEN product_category_name  IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN product_weight_g       IS NULL THEN 1 ELSE 0 END) AS null_weight,
    SUM(CASE WHEN product_length_cm      IS NULL THEN 1 ELSE 0 END) AS null_length,
    ROUND(100.0 * SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
                                                                    AS pct_missing_category
FROM products;


-- ------------------------------------------------------------
-- 4. DUPLICATES: Check for duplicate order_ids
-- ------------------------------------------------------------
SELECT
    order_id,
    COUNT(*) AS occurrences
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 10;
-- Expected result: 0 rows (no duplicates)


-- ------------------------------------------------------------
-- 5. DATE RANGE: Understand the analysis window
-- ------------------------------------------------------------
SELECT
    MIN(DATE(order_purchase_timestamp)) AS first_order_date,
    MAX(DATE(order_purchase_timestamp)) AS last_order_date,
    COUNT(DISTINCT DATE(order_purchase_timestamp)) AS active_days,
    ROUND(
        (julianday(MAX(order_purchase_timestamp)) -
         julianday(MIN(order_purchase_timestamp))) / 30.0, 1
    ) AS span_months
FROM orders
WHERE order_status != 'canceled';


-- ------------------------------------------------------------
-- 6. ORDER STATUS DISTRIBUTION
-- ------------------------------------------------------------
SELECT
    order_status,
    COUNT(*)                                    AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ------------------------------------------------------------
-- 7. REFERENTIAL INTEGRITY: Orders without matching customers
-- ------------------------------------------------------------
SELECT COUNT(*) AS orders_without_customer
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
-- Expected: 0


-- ------------------------------------------------------------
-- 8. REFERENTIAL INTEGRITY: Order items without matching products
-- ------------------------------------------------------------
SELECT COUNT(*) AS items_without_product
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


-- ------------------------------------------------------------
-- 9. PRICE SANITY CHECK: Detect outliers
-- ------------------------------------------------------------
SELECT
    MIN(price)                        AS min_price,
    MAX(price)                        AS max_price,
    ROUND(AVG(price), 2)              AS avg_price,
    ROUND(AVG(freight_value), 2)      AS avg_freight,
    SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END) AS zero_or_neg_price
FROM order_items;


-- ------------------------------------------------------------
-- 10. DATA QUALITY SUMMARY SCORE
-- ------------------------------------------------------------
-- Run after all checks above to get a quick pass/fail summary
SELECT
    'Duplicate orders'      AS check_name,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT order_id FROM orders GROUP BY order_id HAVING COUNT(*) > 1
)
UNION ALL
SELECT
    'Orphan order items',
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT
    'Zero-price items',
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items
WHERE price <= 0;
