-- 03 - GOLD DIM_PRODUCT
-- Source: silver.sales (there is no product master file)
-- Target: gold.dim_product (VIEW, 1 row = 1 product)


-- PART A. EXPLORE - check the silver data is ready to be a dimension

-- A1. Check one category and one price per product
SELECT product_id,
       COUNT(DISTINCT product_category) AS n_category,
       COUNT(DISTINCT unit_price) AS n_price
FROM silver.sales
GROUP BY product_id
   HAVING COUNT(DISTINCT product_category) > 1
   OR COUNT(DISTINCT unit_price) > 1;
       -- Outcome: 0 rows -> GROUP BY product_id gives a clean dimension.

-- A2. Check how many products and the ID range
SELECT COUNT(DISTINCT product_id) AS products,
       MIN(product_id) AS first_id,
       MAX(product_id) AS last_id
FROM silver.sales;
       -- Outcome: 92 products, IDs from PRD0001 to PRD0100.
       --     * 8 IDs never appear: PRD0021, 0025, 0033, 0039, 0053, 0058, 0073, 0074.

-- A3. Check the price range per category
SELECT product_category,
       COUNT(DISTINCT product_id) AS products,
       MIN(unit_price) AS min_price,
       MAX(unit_price) AS max_price
FROM silver.sales
GROUP BY product_category
ORDER BY products DESC;
       -- Outcome:
       --     * Thuc pham: 31 products | 8,500 -> 50,000
       --     * Thuc uong: 29 products | 8,500 -> 50,000
       --     * Cham soc ca nhan: 17 products | 9,000 -> 40,000
       --     * Gia dung: 15 products | 8,500 -> 50,000
       -- Decision: add price_tier -> 'Low (<=10k)' | 'Mid (10k-25k)' | 'High (>25k)'


-- PART B. TEST - try each new column with SELECT

-- B1. Test one row per product with price_tier
SELECT product_id,
       product_category,
       MAX(unit_price) AS unit_price,
       CASE WHEN MAX(unit_price) <= 10000 THEN 'Low (<=10k)'
            WHEN MAX(unit_price) <= 25000 THEN 'Mid (10k-25k)'
            ELSE 'High (>25k)' END AS price_tier
FROM silver.sales
GROUP BY product_id, product_category
ORDER BY product_id
LIMIT 10;
       -- Outcome: 1 row per product with its price and tier.
       --     * MAX() is needed by GROUP BY; each product has only 1 price (A1), so MAX = the price.


-- PART C. CREATE - build the gold view with all tested columns

-- C1. Drop the old version (so this script can be re-run safely)
DROP VIEW IF EXISTS gold.dim_product;

-- C2. Create gold.dim_product
CREATE VIEW gold.dim_product AS
SELECT
    product_id,
    product_category,
    MAX(unit_price) AS unit_price,
    CASE WHEN MAX(unit_price) <= 10000 THEN 'Low (<=10k)'
         WHEN MAX(unit_price) <= 25000 THEN 'Mid (10k-25k)'
         ELSE 'High (>25k)' END AS price_tier
FROM silver.sales
GROUP BY product_id, product_category;
       -- Outcome: "CREATE VIEW" success.
       --     * product_category is kept here and removed from fact_sales.


-- PART D. VALIDATE - check the new gold view

-- D1. Row count must equal distinct products in silver
SELECT (SELECT COUNT(DISTINCT product_id) FROM silver.sales) AS silver_products,
       (SELECT COUNT(*) FROM gold.dim_product) AS gold_rows,
       (SELECT COUNT(DISTINCT product_id) FROM gold.dim_product) AS distinct_product_id;
       -- Outcome: 92 | 92 | 92 -> key unique.

-- D2. Data types of the view
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
   AND table_name = 'dim_product'
ORDER BY ordinal_position;
       -- Outcome: product_id / product_category / price_tier = text, unit_price = bigint.

-- D3. Check products per category and price tier
SELECT product_category, price_tier, COUNT(*) AS products
FROM gold.dim_product
GROUP BY product_category, price_tier
ORDER BY product_category, price_tier;
       -- Outcome: totals per tier -> Low 23 | Mid 39 | High 30 (sum = 92).

-- D4. Final look at the view
SELECT *
FROM gold.dim_product
ORDER BY product_id
LIMIT 10;
       -- Outcome: 4 columns, 1 row per product.
