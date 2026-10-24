-- 01 - GOLD DIM_CUSTOMER
-- Source: silver.customer
-- Target: gold.dim_customer (VIEW, 1 row = 1 customer)


-- PART A. EXPLORE - check the silver data is ready to be a dimension

-- A1. Check the dimension key is unique
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT customer_id) AS distinct_customer_id
FROM silver.customer;
       -- Outcome: 2000 | 2000 -> customer_id is unique and can be the dimension key.

-- A2. Check the join year distribution
SELECT EXTRACT(YEAR FROM join_date)::int AS join_year,
       COUNT(*) AS customers
FROM silver.customer
GROUP BY 1
ORDER BY 1;
       -- Outcome: 
       --     * 2018: 319 | 2019: 346 | 2020: 317 | 2021: 304 | 2022: 329 | 2023: 303 | 2024: 82
       -- Decision: add join_year as a slicer for Power BI (customers acquired per year).

-- A3. Check the credit limit tiers
SELECT credit_limit, COUNT(*) AS customers
FROM silver.customer
GROUP BY credit_limit
ORDER BY credit_limit;
       -- Outcome: 4 tiers -> 50,000,000 (502) | 100,000,000 (512) | 200,000,000 (477) | 500,000,000 (509)
       -- Decision: add a readable label ('50M', '100M'...) for charts.


-- PART B. TEST - try each new column with SELECT

-- B1. Test join_year and credit_limit_tier
SELECT customer_id,
       join_date,
       EXTRACT(YEAR FROM join_date)::int AS join_year,
       credit_limit,
       (credit_limit / 1000000)::text || 'M' AS credit_limit_tier
FROM silver.customer
LIMIT 10;
       -- Outcome: 2023-11-17 -> 2023, 100000000 -> '100M'. Works.
       --     * integer division keeps the label clean ('100M', not '100.0000M').


-- PART C. CREATE - build the gold view with all tested columns

-- C1. Drop the old version (so this script can be re-run safely)
DROP VIEW IF EXISTS gold.dim_customer;

-- C2. Create gold.dim_customer
CREATE VIEW gold.dim_customer AS
SELECT
    customer_id,
    customer_name,
    customer_type,
    channel,
    province,
    region,
    address,
    phone,
    tax_code,
    has_tax_code,
    join_date,
    EXTRACT(YEAR FROM join_date)::int AS join_year,
    credit_limit,
    (credit_limit / 1000000)::text || 'M' AS credit_limit_tier,
    status
FROM silver.customer;
       -- Outcome: "CREATE VIEW" success.
       --     * channel / province / region are kept here and removed from fact_sales (silver sales A17).
       --     * ingestion_timestamp is not exposed (technical column, not for business users).


-- PART D. VALIDATE - check the new gold view

-- D1. Row count must equal silver
SELECT (SELECT COUNT(*) FROM silver.customer) AS silver_rows,
       (SELECT COUNT(*) FROM gold.dim_customer) AS gold_rows,
       (SELECT COUNT(DISTINCT customer_id) FROM gold.dim_customer) AS distinct_customer_id;
       -- Outcome: 2000 | 2000 | 2000 -> no rows lost, key still unique.

-- D2. Data types of the view
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
   AND table_name = 'dim_customer'
ORDER BY ordinal_position;
       -- Outcome: join_year = integer, credit_limit_tier = text, other columns same as silver.

-- D3. Check the credit_limit_tier label
SELECT credit_limit_tier, COUNT(*)
FROM gold.dim_customer
GROUP BY credit_limit_tier
ORDER BY MIN(credit_limit);
       -- Outcome: 50M 502 | 100M 512 | 200M 477 | 500M 509
       --     * ORDER BY MIN(credit_limit) sorts by the number, not the text ('50M' would come after '100M' as text).

-- D4. Final look at the view
SELECT *
FROM gold.dim_customer
LIMIT 10;
       -- Outcome: 15 business columns, no technical columns.
