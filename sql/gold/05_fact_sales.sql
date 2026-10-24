-- 05 - GOLD FACT_SALES
-- Source: silver.sales (run gold 01 -> 04 first, PART D checks the links to every dimension)
-- Target: gold.fact_sales (VIEW, 1 row = 1 product line inside 1 order)


-- PART A. EXPLORE - decide which columns stay in the fact table

-- A1. Check the columns of silver.sales
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
   AND table_name = 'sales'
ORDER BY ordinal_position;
       -- Outcome: 25 columns. Where each group goes in the star schema:
       --     * region, province, channel -> dim_customer
       --     * product_category -> dim_product
       --     * order_month, order_quarter, order_year -> dim_date
       --     * ingestion_timestamp -> dropped
       -- Decision: fact keeps only keys + measures + line status + flags.

-- A2. Check the weight of cancelled lines
SELECT delivery_status,
       COUNT(*) AS lines,
       SUM(quantity) AS quantity,
       SUM(net_amount) AS net_amount
FROM silver.sales
GROUP BY delivery_status
ORDER BY lines DESC;
       -- Outcome:
       --     * Delivered: 104720 lines
       --     * Delivering: 9581 lines
       --     * Cancelled: 4800 lines | net 6,428,757,100
       -- Decision: keep cancelled lines but add is_cancelled, recognized_revenue and recognized_quantity = 0 for them.


-- PART B. TEST - try each new column with SELECT

-- B1. Test the revenue logic
SELECT SUM(net_amount) AS total_net,
       SUM(CASE WHEN delivery_status = 'Cancelled' THEN 0 ELSE net_amount END) AS recognized_revenue
FROM silver.sales;
       -- Outcome: total_net 158,957,563,200 | recognized_revenue 152,528,806,100
       --     * difference = 6,428,757,100 = the cancelled lines in A2.

-- B2. Test the new columns on cancelled lines
SELECT order_id, product_id, delivery_status, quantity, net_amount,
       (delivery_status = 'Cancelled') AS is_cancelled,
       CASE WHEN delivery_status = 'Cancelled' THEN 0 ELSE quantity END AS recognized_quantity,
       CASE WHEN delivery_status = 'Cancelled' THEN 0 ELSE net_amount END AS recognized_revenue
FROM silver.sales
WHERE delivery_status = 'Cancelled'
LIMIT 10;
       -- Outcome: is_cancelled = true, recognized_quantity = 0, recognized_revenue = 0 on every cancelled line.


-- PART C. CREATE - build the gold view with all tested columns

-- C1. Drop the old version (so this script can be re-run safely)
DROP VIEW IF EXISTS gold.fact_sales;

-- C2. Create gold.fact_sales
CREATE VIEW gold.fact_sales AS
SELECT
    order_id,
    product_id,
    order_date,
    customer_id,
    employee_id,
    quantity,
    unit_price,
    discount_pct,
    gross_amount,
    discount_amount,
    net_amount,
    CASE WHEN delivery_status = 'Cancelled' THEN 0 ELSE quantity END AS recognized_quantity,
    CASE WHEN delivery_status = 'Cancelled' THEN 0 ELSE net_amount END AS recognized_revenue,
    delivery_status,
    payment_method,
    payment_status,
    (delivery_status = 'Cancelled') AS is_cancelled,
    flag_cancelled_but_paid,
    flag_order_before_join,
    flag_region_mismatch_employee
FROM silver.sales;
       -- Outcome: "CREATE VIEW" success.
       --     * keys: order_id (no own table), product_id -> dim_product, order_date -> dim_date.full_date, customer_id -> dim_customer, employee_id -> dim_employee
       --     * delivery / payment status stay at line level.


-- PART D. VALIDATE - check the new gold view

-- D1. Row count must equal silver and respect the grain
SELECT (SELECT COUNT(*) FROM silver.sales) AS silver_rows,
       (SELECT COUNT(*) FROM gold.fact_sales) AS gold_rows,
       (SELECT COUNT(DISTINCT (order_id, product_id)) FROM gold.fact_sales) AS distinct_lines,
       (SELECT COUNT(DISTINCT order_id) FROM gold.fact_sales) AS orders;
       -- Outcome: 119101 | 119101 | 119101 | 50000.

-- D2. Data types of the view
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
   AND table_name = 'fact_sales'
ORDER BY ordinal_position;
       -- Outcome: 20 columns, recognized_quantity = integer, recognized_revenue = bigint, is_cancelled = boolean.

-- D3. Totals must equal silver
SELECT 'silver' AS layer, SUM(gross_amount) AS gross, SUM(net_amount) AS net, SUM(quantity) AS qty
FROM silver.sales
UNION ALL
SELECT 'gold', SUM(gross_amount), SUM(net_amount), SUM(quantity)
FROM gold.fact_sales;
       -- Outcome: both rows identical: gross 163,848,720,000 | net 158,957,563,200 | qty 7,455,076

-- D4. Check the recognized measures
SELECT SUM(recognized_revenue) AS recognized_revenue,
       SUM(recognized_quantity) AS recognized_quantity,
       SUM(is_cancelled::int) AS cancelled_lines
FROM gold.fact_sales;
       -- Outcome: 152,528,806,100 | 7,153,328 | 4800

-- D5. Check every key finds its dimension row
SELECT
    SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END) AS missing_customer,
    SUM(CASE WHEN e.employee_id IS NULL THEN 1 ELSE 0 END) AS missing_employee,
    SUM(CASE WHEN p.product_id IS NULL THEN 1 ELSE 0 END) AS missing_product,
    SUM(CASE WHEN d.full_date IS NULL THEN 1 ELSE 0 END) AS missing_date
FROM gold.fact_sales f
LEFT JOIN gold.dim_customer c ON c.customer_id = f.customer_id
LEFT JOIN gold.dim_employee e ON e.employee_id = f.employee_id
LEFT JOIN gold.dim_product p ON p.product_id = f.product_id
LEFT JOIN gold.dim_date d ON d.full_date = f.order_date;
       -- Outcome: 0 | 0 | 0 | 0

-- D6. Check the joins do not multiply rows
SELECT COUNT(*) AS joined_rows
FROM gold.fact_sales f
JOIN gold.dim_customer c ON c.customer_id = f.customer_id
JOIN gold.dim_employee e ON e.employee_id = f.employee_id
JOIN gold.dim_product p ON p.product_id = f.product_id
JOIN gold.dim_date d ON d.full_date = f.order_date;
       -- Outcome: 119101

-- D7. Business preview: recognized revenue by customer region and category
SELECT c.region, p.product_category,
       SUM(f.recognized_revenue) AS recognized_revenue
FROM gold.fact_sales f
JOIN gold.dim_customer c ON c.customer_id = f.customer_id
JOIN gold.dim_product p ON p.product_id = f.product_id
GROUP BY ROLLUP (c.region, p.product_category)
ORDER BY c.region, p.product_category;
       -- Outcome:
       --     * Mien Bac: 48,023,129,800 | Mien Nam: 48,861,233,600 | Mien Trung: 55,644,442,700 (highest)
       --     * Grand total: 152,528,806,100
       --     * by category: Thuc uong 57.3B | Thuc pham 41.5B | Gia dung 27.1B | Cham soc ca nhan 26.7B

-- D8. Business preview: recognized revenue by month
SELECT d.year_month,
       SUM(f.recognized_revenue) AS recognized_revenue
FROM gold.fact_sales f
JOIN gold.dim_date d ON d.full_date = f.order_date
GROUP BY d.year_month
ORDER BY d.year_month;
       -- Outcome: peak in 2024-01 (18.9B) and 2024-12 (16.7B), lowest in 2024-02 (8.7B) -> seasonality around Tet / year end.
