-- 03 - SILVER SALES
-- Source : bronze."Raw_Sales" (loaded by ELT/2_Sales_Transaction_ELT.py) + silver.customer, silver.employee (used for cross-table checks)
-- Target : silver.sales


-- PART A. EXPLORE - understand the raw data

-- A1. Preview the first 10 rows
SELECT *
FROM bronze."Raw_Sales"
LIMIT 10;
    -- Outcome: 
    --      * 22 columns = 21 source columns + ingestion_timestamp.
    --      * order_date looks like '8/22/2024' (M/D/YYYY text)
    --      * the same order_id appears on several rows (e.g. ORD0010002 x 3 rows)
    --      * order_month / order_quarter / order_year are already split out

-- A2. Check the data type of every column
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
   AND table_name = 'Raw_Sales'
ORDER BY ordinal_position;
    -- Outcome:
    --      * text: order_id, order_date, customer_id, region, province, channel, employee_id, product_id, product_category, delivery_status, payment_method, payment_status
    --      * bigint: order_month, order_quarter, order_year, quantity, unit_price, discount_pct, discount_amount, gross_amount, net_amount
    --      * timestamp: ingestion_timestamp
    -- To fix: order_date -> DATE.

-- A3. How many times has this table been loaded?
SELECT ingestion_timestamp, COUNT(*) AS row_count
FROM bronze."Raw_Sales"
GROUP BY ingestion_timestamp;
    -- Outcome: 1 row only, 119101 records -> loaded once.

-- A4. Grain of the table: rows vs. orders
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT order_id) AS distinct_orders,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT order_id), 2) AS avg_lines_per_order,
       COUNT(DISTINCT customer_id) AS distinct_customers,
       COUNT(DISTINCT employee_id) AS distinct_employees,
       COUNT(DISTINCT product_id) AS distinct_products
FROM bronze."Raw_Sales";
    -- Outcome: 
    --      * 119101 rows | 50000 orders | 2.38 lines per order | 1802 customers | 108 employees | 92 products
    --      -> order_id alone is NOT unique. The real key is (order_id, product_id).

-- A5. Distribution of lines per order
SELECT lines_per_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS lines_per_order
      FROM bronze."Raw_Sales"
      GROUP BY order_id) AS t
GROUP BY lines_per_order
ORDER BY lines_per_order;
    -- Outcome: 1 line 14910 | 2 lines 15070 | 3 lines 9996 | 4 lines 6057 | 5 lines 3967

-- A6. Check the unique of order_id and product_id
SELECT order_id, product_id, COUNT(*)
FROM bronze."Raw_Sales"
GROUP BY order_id, product_id
   HAVING COUNT(*) > 1;
    -- Outcome: 0 rows -> (order_id, product_id) can be the primary key.

-- A7. NULL count per column
SELECT
    COUNT(*) - COUNT(order_id) AS null_order_id,
    COUNT(*) - COUNT(order_date) AS null_order_date,
    COUNT(*) - COUNT(customer_id) AS null_customer_id,
    COUNT(*) - COUNT(employee_id) AS null_employee_id,
    COUNT(*) - COUNT(product_id) AS null_product_id,
    COUNT(*) - COUNT(quantity) AS null_quantity,
    COUNT(*) - COUNT(unit_price) AS null_unit_price,
    COUNT(*) - COUNT(net_amount) AS null_net_amount,
    COUNT(*) - COUNT(delivery_status) AS null_delivery_status,
    COUNT(*) - COUNT(payment_status) AS null_payment_status
FROM bronze."Raw_Sales";   
    -- Outcome: all 0 -> no missing values.

-- A8. Leading / trailing spaces in key text columns
SELECT COUNT(*) AS rows_with_extra_spaces
FROM bronze."Raw_Sales"
WHERE order_id <> TRIM(order_id)
   OR customer_id <> TRIM(customer_id)
   OR employee_id <> TRIM(employee_id)
   OR product_id  <> TRIM(product_id);
    -- Outcome: 0 -> clean. TRIM() still applied as a defensive step.

-- A9. Distinct values of categorical columns
SELECT 'region' AS col, region AS value, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY region
UNION ALL 
SELECT 'channel', channel, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY channel
UNION ALL 
SELECT 'product_category', product_category, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY product_category
UNION ALL 
SELECT 'delivery_status', delivery_status, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY delivery_status
UNION ALL 
SELECT 'payment_method', payment_method, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY payment_method
UNION ALL 
SELECT 'payment_status', payment_status, COUNT(*) 
FROM bronze."Raw_Sales" 
GROUP BY payment_status
ORDER BY 1, 3 DESC;
    -- Outcome: values are clean, no typos.
    --      * region: Mien Trung 43393, Mien Nam 38266, Mien Bac 37442
    --      * channel: Traditional Trade 55110, Modern Trade 46080, E-commerce 17911
    --      * product_category: Thuc pham 40001, Thuc uong 37691, Cham soc ca nhan 21984, Gia dung 19425
    --      * delivery_status: Delivered 104720, Delivering 9581, Cancelled 4800
    --      * payment_method: Cong no 39775, Chuyen khoan 39734, Tien mat 39592
    --      * payment_status: Paid 89524, Partial 17791, Unpaid 11786


-- A10. Check the order_date text format before converting
SELECT order_date
FROM bronze."Raw_Sales"
WHERE order_date !~ '^\d{1,2}/\d{1,2}/\d{4}$';
    -- Outcome: 0 rows -> every value is M/D/YYYY -> safe to convert.

-- A11. Numeric ranges (look for negative / zero / extreme values)
SELECT MIN(quantity) AS min_qty, MAX(quantity) AS max_qty,
       MIN(unit_price) AS min_price, MAX(unit_price) AS max_price,
       MIN(discount_pct) AS min_disc, MAX(discount_pct) AS max_disc,
       MIN(net_amount) AS min_net, MAX(net_amount) AS max_net
FROM bronze."Raw_Sales";
    -- Outcome: quantity 5 -> 120, unit_price 8,500 -> 50,000, discount_pct 0 -> 15 (values 0/2/5/8/10/15), net_amount 36,100 -> 6,000,000
    -- -> no negative or zero values.

-- A12. Check the logic of the amount columns
SELECT
    SUM(CASE WHEN gross_amount <> quantity * unit_price THEN 1 ELSE 0 END) AS wrong_gross,
    SUM(CASE WHEN net_amount <> gross_amount - discount_amount THEN 1 ELSE 0 END) AS wrong_net,
    SUM(CASE WHEN discount_amount <> gross_amount * discount_pct / 100.0 THEN 1 ELSE 0 END) AS disc_not_exact,
    SUM(CASE WHEN ABS(discount_amount - gross_amount * discount_pct / 100.0) > 50 THEN 1 ELSE 0 END) AS disc_diff_over_50
FROM bronze."Raw_Sales";
    -- Outcome: wrong_gross = 0 | wrong_net = 0 | disc_not_exact = 13971 | disc_diff_over_50 = 0
    --      -> gross and net are always correct.
    --      -> discount_amount differs from gross * pct by at most 50 VND in 13971 rows

-- A13. Check the consistent of the order_month / order_quarter with order_date
SELECT COUNT(*) AS mismatched_rows
FROM bronze."Raw_Sales"
WHERE EXTRACT(MONTH   FROM TO_DATE(order_date, 'MM/DD/YYYY')) <> order_month
   OR EXTRACT(QUARTER FROM TO_DATE(order_date, 'MM/DD/YYYY')) <> order_quarter
   OR EXTRACT(YEAR    FROM TO_DATE(order_date, 'MM/DD/YYYY')) <> order_year;
    -- Outcome: 0 -> consistent. All data is in year 2024.

-- A14. Check the consistent of each order have only one date / customer / employee
SELECT
    SUM(CASE WHEN n_date > 1 THEN 1 ELSE 0 END) AS orders_multi_date,
    SUM(CASE WHEN n_customer > 1 THEN 1 ELSE 0 END) AS orders_multi_customer,
    SUM(CASE WHEN n_employee > 1 THEN 1 ELSE 0 END) AS orders_multi_employee,
    SUM(CASE WHEN n_pay > 1 THEN 1 ELSE 0 END) AS orders_multi_payment_status,
    SUM(CASE WHEN n_deliv > 1 THEN 1 ELSE 0 END) AS orders_multi_delivery_status
FROM (SELECT order_id,
             COUNT(DISTINCT order_date) AS n_date,
             COUNT(DISTINCT customer_id) AS n_customer,
             COUNT(DISTINCT employee_id) AS n_employee,
             COUNT(DISTINCT payment_status) AS n_pay,
             COUNT(DISTINCT delivery_status) AS n_deliv
      FROM bronze."Raw_Sales"
      GROUP BY order_id) AS t;
    -- Outcome: date / customer / employee = 0 -> each order has one header (good), payment_status differs inside 18861 orders, delivery_status differs inside 10904 orders.

-- A15. Check the consistent of one price and one category per product
SELECT product_id,
       COUNT(DISTINCT unit_price) AS n_price,
       COUNT(DISTINCT product_category) AS n_category
FROM bronze."Raw_Sales"
GROUP BY product_id
   HAVING COUNT(DISTINCT unit_price) > 1
   OR COUNT(DISTINCT product_category) > 1;
    -- Outcome: 0 rows -> each product has a fixed price and category.

-- A16. Check the integrity do all customers / employees exist in silver
SELECT
    SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END) AS orphan_customer_rows,
    SUM(CASE WHEN e.employee_id IS NULL THEN 1 ELSE 0 END) AS orphan_employee_rows
FROM bronze."Raw_Sales" s
LEFT JOIN silver.customer c ON c.customer_id = s.customer_id
LEFT JOIN silver.employee e ON e.employee_id = s.employee_id;
    -- Outcome: 0 | 0 -> every sale links to a known customer and employee.

-- A17. Check the region / province / channel in sales match the customer master
SELECT
    SUM(CASE WHEN s.region   <> c.region   THEN 1 ELSE 0 END) AS region_mismatch,
    SUM(CASE WHEN s.province <> c.province THEN 1 ELSE 0 END) AS province_mismatch,
    SUM(CASE WHEN s.channel  <> c.channel  THEN 1 ELSE 0 END) AS channel_mismatch
FROM bronze."Raw_Sales" s
JOIN silver.customer c ON c.customer_id = s.customer_id;
    -- Outcome: 0 | 0 | 0 -> region/province/channel in sales = the customer's location.

-- A18. Check the sale region match the employee's region
SELECT s.employee_id, e."position",
       e.region AS employee_region, s.region AS sale_region,
       COUNT(*) AS lines, COUNT(DISTINCT s.order_id) AS orders
FROM bronze."Raw_Sales" s
JOIN silver.employee e ON e.employee_id = s.employee_id
WHERE s.region <> e.region
GROUP BY 1, 2, 3, 4
ORDER BY lines DESC;
    -- Outcome: 253 lines (104 orders) from only 3 employees not match, all from Mien Bac:
    --      * EMP1004 -> 229 lines sold to Mien Trung
    --      * EMP1018 -> 14 lines sold to Mien Nam
    --      * EMP1026 -> 10 lines sold to Mien Nam
    -- Decision: keep rows, add flag_region_mismatch_employee.

-- A19. Check the cancelled orders that are marked as paid
SELECT delivery_status, payment_status, COUNT(*) AS lines
FROM bronze."Raw_Sales"
GROUP BY delivery_status, payment_status
ORDER BY delivery_status, payment_status;
    -- Outcome:
    --      * Cancelled + Paid = 3570 lines
    --      * Cancelled + Partial =  691
    --      * Cancelled + Unpaid = 539
    -- Decision: keep rows, add flag_cancelled_but_paid.

-- A20. Check the orders placed before the customer joined
SELECT COUNT(*) AS lines,
       COUNT(DISTINCT s.order_id) AS orders,
       COUNT(DISTINCT s.customer_id) AS customers
FROM bronze."Raw_Sales" s
JOIN silver.customer c ON c.customer_id = s.customer_id
WHERE TO_DATE(s.order_date, 'MM/DD/YYYY') < c.join_date;
    -- Outcome: 638 lines | 273 orders | 42 customers.
    -- Decision: keep rows, add flag_order_before_join.

-- A21. Check customers and employees without any sales
SELECT 'customer' AS entity, COUNT(*) AS without_sales
FROM silver.customer c
WHERE NOT EXISTS 
    (SELECT 1 FROM bronze."Raw_Sales" s 
    WHERE s.customer_id = c.customer_id)
UNION ALL
SELECT 'employee', COUNT(*)
FROM silver.employee e
WHERE NOT EXISTS 
    (SELECT 1 FROM bronze."Raw_Sales" s 
    WHERE s.employee_id = e.employee_id);
    -- Outcome: 198 customers and 6 employees have no sales.
    

-- PART B. TEST - try the transformations with SELECT

-- B1. Convert order_date: text -> DATE and check the range
SELECT MIN(TO_DATE(order_date, 'MM/DD/YYYY')) AS min_order_date,
       MAX(TO_DATE(order_date, 'MM/DD/YYYY')) AS max_order_date,
       COUNT(DISTINCT TO_DATE(order_date, 'MM/DD/YYYY')) AS distinct_days
FROM bronze."Raw_Sales";
    -- Outcome: 2024-01-01 -> 2024-12-31, 366 distinct days (2024 is a leap year, so there are sales on every single day).

-- B2. Test the 3 data quality flags together
SELECT
    SUM((s.delivery_status = 'Cancelled' AND s.payment_status = 'Paid')::int) AS flag_cancelled_but_paid,
    SUM((TO_DATE(s.order_date, 'MM/DD/YYYY') < c.join_date)::int) AS flag_order_before_join,
    SUM((s.region <> e.region)::int) AS flag_region_mismatch_employee
FROM bronze."Raw_Sales" s
LEFT JOIN silver.customer c ON c.customer_id = s.customer_id
LEFT JOIN silver.employee e ON e.employee_id = s.employee_id;
    -- Outcome: 3570 | 638 | 253 -> matches A19, A20, A18.


-- PART C. CREATE - build the silver table with all tested transformations

-- C1. Drop the old version (so this script can be re-run safely)
DROP TABLE IF EXISTS silver.sales CASCADE;

-- C2. Create silver.sales
CREATE TABLE silver.sales AS
SELECT
    TRIM(s.order_id) AS order_id,
    TO_DATE(s.order_date, 'MM/DD/YYYY') AS order_date,
    s.order_month::int AS order_month,
    s.order_quarter::int AS order_quarter,
    s.order_year::int AS order_year,
    TRIM(s.customer_id) AS customer_id,
    TRIM(s.employee_id) AS employee_id,
    TRIM(s.product_id) AS product_id,
    TRIM(s.product_category) AS product_category,
    TRIM(s.region) AS region,
    TRIM(s.province) AS province,
    TRIM(s.channel) AS channel,
    s.quantity::int AS quantity,
    s.unit_price::bigint S unit_price,
    s.discount_pct::int S discount_pct,
    s.discount_amount::bigint AS discount_amount,
    s.gross_amount::bigint AS gross_amount,
    s.net_amount::bigint AS net_amount,
    TRIM(s.delivery_status) AS delivery_status,
    TRIM(s.payment_method) AS payment_method,
    TRIM(s.payment_status) AS payment_status,
    (s.delivery_status = 'Cancelled' AND s.payment_status = 'Paid') AS flag_cancelled_but_paid,
    (TO_DATE(s.order_date, 'MM/DD/YYYY') < c.join_date) AS flag_order_before_join,
    (s.region <> e.region) AS flag_region_mismatch_employee,
    s.ingestion_timestamp
FROM bronze."Raw_Sales" s
LEFT JOIN silver.customer c ON c.customer_id = TRIM(s.customer_id)
LEFT JOIN silver.employee e ON e.employee_id = TRIM(s.employee_id)
WHERE s.ingestion_timestamp = 
    (SELECT MAX(ingestion_timestamp)
    FROM bronze."Raw_Sales");
    -- Outcome: "Updated Rows: 119101".

-- C3. Add the primary key
ALTER TABLE silver.sales ADD PRIMARY KEY (order_id, product_id);


-- PART D. VALIDATE - check the new silver table

-- D1. Row count must equal bronze
SELECT (SELECT COUNT(*) FROM bronze."Raw_Sales") AS bronze_rows,
       (SELECT COUNT(*) FROM silver.sales) AS silver_rows;
    -- Outcome: 119101 | 119101.

-- D2. Totals must equal bronze
SELECT 'bronze' AS layer, SUM(gross_amount) AS gross, SUM(discount_amount) AS discount, SUM(net_amount) AS net
FROM bronze."Raw_Sales"
UNION ALL
SELECT 'silver', SUM(gross_amount), SUM(discount_amount), SUM(net_amount)
FROM silver.sales;
    -- Outcome: both rows identical: gross 163,848,720,000 | discount 4,891,156,800 | net 158,957,563,200

-- D3. Data types after cleaning
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
   AND table_name = 'sales'
ORDER BY ordinal_position;
    -- Outcome: order_date = date, quantity / discount_pct / order_month... = integer, amounts = bigint, the 3 flags = boolean.

-- D4. Flag summary
SELECT
    SUM(flag_cancelled_but_paid::int) AS cancelled_but_paid,
    SUM(flag_order_before_join::int) AS order_before_join,
    SUM(flag_region_mismatch_employee::int) AS region_mismatch_employee
FROM silver.sales;
    -- Outcome: 3570 | 638 | 253
    
-- D5. Final look at the clean data
SELECT *
FROM silver.sales
LIMIT 10;
    -- Outcome: real dates, correct types, 3 flag columns at the end.
