-- ============================================================
/*
===============================================================================
Project      : E-commerce Customer Analytics
Dataset      : Olist Brazilian E-commerce Dataset
Author       : Emilya Ismayilova
Tool         : SQLite
Database     : olist.sqlite

File         : 02_Executive_KPI.sql

Description
-----------
This script calculates the key business metrics (KPIs) used by
executive management to evaluate the overall business performance.

Business Questions
------------------
1. How many completed orders were placed?
2. How many unique customers made purchases?
3. How many active sellers participated?
4. What is the total product revenue?
5. What is the total freight revenue?
6. What is the average order value (AOV)?
7. How has revenue changed over time?
===============================================================================
*/
-- ============================================================


-- ------------------------------------------------------------
-- 1. OVERALL BUSINESS SNAPSHOT
-- ------------------------------------------------------------
-- ============================================================================
-- SECTION 1. OVERALL BUSINESS SNAPSHOT
-- ============================================================================

/*
Business Question

What are the overall business KPIs?

Metrics

• Total Orders
• Unique Customers
• Active Sellers
• Product Revenue
• Freight Revenue
• Total Revenue
• Average Order Value (AOV)
• Freight Share
*/

WITH order_totals AS (

SELECT

oi.order_id,

SUM(oi.price) AS product_amount,

SUM(oi.freight_value) AS freight_amount,

SUM(oi.price + oi.freight_value) AS order_total

FROM order_items oi

GROUP BY oi.order_id

)

SELECT

COUNT(DISTINCT o.order_id) AS total_orders,

COUNT(DISTINCT o.customer_id) AS unique_customers,

COUNT(DISTINCT oi.seller_id) AS active_sellers,

ROUND(SUM(ot.product_amount),2) AS product_revenue,

ROUND(SUM(ot.freight_amount),2) AS freight_revenue,

ROUND(SUM(ot.order_total),2) AS total_revenue,

ROUND(AVG(ot.order_total),2) AS average_order_value,

ROUND(

SUM(ot.freight_amount)

/

SUM(ot.product_amount)

*100

,2)

AS freight_share_pct

FROM orders o

JOIN order_totals ot
ON o.order_id=ot.order_id

JOIN order_items oi
ON o.order_id=oi.order_id

WHERE o.order_status='delivered';


-- ============================================================================
-- SECTION 2. MONTHLY REVENUE TREND
-- ============================================================================

/*
Business Question

How does revenue change month by month?

Metrics

• Orders
• Customers
• Revenue
• Average Order Value
• Month-over-Month Growth
*/

WITH order_totals AS (

SELECT

order_id,

SUM(price+freight_value) AS order_total

FROM order_items

GROUP BY order_id

),

monthly_sales AS (

SELECT

strftime('%Y-%m',o.order_purchase_timestamp) AS month,

COUNT(DISTINCT o.order_id) AS total_orders,

COUNT(DISTINCT o.customer_id) AS total_customers,

SUM(ot.order_total) AS revenue,

AVG(ot.order_total) AS average_order_value

FROM orders o

JOIN order_totals ot
ON o.order_id=ot.order_id

WHERE o.order_status='delivered'

GROUP BY month

)

SELECT

month,

total_orders,

total_customers,

ROUND(revenue,2) AS revenue,

ROUND(average_order_value,2) AS average_order_value,

ROUND(

(revenue-LAG(revenue) OVER(ORDER BY month))

/

LAG(revenue) OVER(ORDER BY month)*100

,2)

AS mom_growth_pct

FROM monthly_sales

ORDER BY month;



-- ============================================================================
-- SECTION 3. QUARTERLY PERFORMANCE
-- ============================================================================

/*
Business Question

How does business performance change across quarters?

Metrics

• Total Orders
• Total Revenue
• Average Order Value
*/

WITH order_totals AS (

SELECT
    order_id,
    SUM(price + freight_value) AS order_total
FROM order_items
GROUP BY order_id

)

SELECT

    strftime('%Y', o.order_purchase_timestamp) AS year,

    CASE
        WHEN CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) BETWEEN 1 AND 3 THEN 'Q1'
        WHEN CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) BETWEEN 4 AND 6 THEN 'Q2'
        WHEN CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) BETWEEN 7 AND 9 THEN 'Q3'
        ELSE 'Q4'
    END AS quarter,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(SUM(ot.order_total),2) AS revenue,

    ROUND(AVG(ot.order_total),2) AS average_order_value

FROM orders o

JOIN order_totals ot
ON o.order_id = ot.order_id

WHERE o.order_status='delivered'

GROUP BY year, quarter

ORDER BY year, quarter;


============================================================================
--SECTION 4. CUSTOMER PURCHASE PATTERNS
============================================================================

---Business Question

--When do customers place orders most frequently?
-- ============================================================================
-- 4.1 ORDERS BY DAY OF WEEK
-- ============================================================================

/*
Business Question

Which day of the week has the highest number of completed orders?
*/

SELECT

CASE CAST(strftime('%w', order_purchase_timestamp) AS INTEGER)

WHEN 0 THEN 'Sunday'
WHEN 1 THEN 'Monday'
WHEN 2 THEN 'Tuesday'
WHEN 3 THEN 'Wednesday'
WHEN 4 THEN 'Thursday'
WHEN 5 THEN 'Friday'
WHEN 6 THEN 'Saturday'

END AS day_of_week,

COUNT(DISTINCT order_id) AS total_orders

FROM orders

WHERE order_status='delivered'

GROUP BY day_of_week

ORDER BY CAST(strftime('%w', order_purchase_timestamp) AS INTEGER);

-- ============================================================================
-- 4.2 ORDERS BY HOUR
-- ============================================================================

/*
Business Question

At what time of day do customers place orders?
*/

SELECT

CAST(strftime('%H', order_purchase_timestamp) AS INTEGER) AS hour_of_day,

COUNT(DISTINCT order_id) AS total_orders

FROM orders

WHERE order_status='delivered'

GROUP BY hour_of_day

ORDER BY hour_of_day;




-- ============================================================================
-- SECTION 5. PRODUCT CATEGORY PERFORMANCE
-- ============================================================================

/*
Business Question

Which product categories generate the highest revenue?

Metrics

• Orders
• Revenue
• Average Item Price
• Revenue Share
*/

SELECT

COALESCE(

t.product_category_name_english,

p.product_category_name,

'Unknown'

) AS category,

COUNT(DISTINCT o.order_id) AS total_orders,

ROUND(SUM(oi.price),2) AS product_revenue,

ROUND(AVG(oi.price),2) AS average_item_price,

ROUND(

100.0 *

SUM(oi.price)

/ SUM(SUM(oi.price)) OVER()

,2)

AS revenue_share_pct

FROM order_items oi

JOIN orders o

ON oi.order_id=o.order_id

JOIN products p

ON oi.product_id=p.product_id

LEFT JOIN category_translation t

ON p.product_category_name=t.product_category_name

WHERE o.order_status='delivered'

GROUP BY category

ORDER BY product_revenue DESC


-- ============================================================================
-- SECTION 6. REGIONAL PERFORMANCE
-- ============================================================================

/*
Business Question

Which states generate the highest revenue?

Metrics

• Orders
• Revenue
• Average Order Value
• Revenue Share
*/

WITH order_totals AS (

SELECT

order_id,

SUM(price + freight_value) AS order_total

FROM order_items

GROUP BY order_id

)

SELECT

c.customer_state,

COUNT(DISTINCT o.order_id) AS total_orders,

ROUND(SUM(ot.order_total),2) AS revenue,

ROUND(AVG(ot.order_total),2) AS average_order_value,

ROUND(

100.0 *

SUM(ot.order_total)

/ SUM(SUM(ot.order_total)) OVER()

,2)

AS revenue_share_pct

FROM orders o

JOIN customers c

ON o.customer_id=c.customer_id

JOIN order_totals ot

ON o.order_id=ot.order_id

WHERE o.order_status='delivered'

GROUP BY c.customer_state

ORDER BY revenue DESC;

