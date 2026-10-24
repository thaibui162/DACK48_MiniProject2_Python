-- 04 - GOLD DIM_DATE
-- Source: generated calendar (range taken from silver.sales)
-- Target: gold.dim_date (VIEW, 1 row = 1 calendar day)


-- PART A. EXPLORE - decide the period the calendar must cover

-- A1. Check the first and last order date
SELECT MIN(order_date) AS first_order,
       MAX(order_date) AS last_order
FROM silver.sales;
       -- Outcome: 2024-01-01 -> 2024-12-31.
       -- Decision: cover full years from the first to the last order year, so the calendar extends automatically when new years are loaded.


-- PART B. TEST - try each new column with SELECT

-- B1. Generate one row per day
SELECT d::date AS full_date
FROM generate_series(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1 day') AS d
LIMIT 10;
       -- Outcome: 2024-01-01, 2024-01-02, ... one row per day.

-- B2. Test the date attributes
SELECT d::date AS full_date,
       TO_CHAR(d, 'YYYYMMDD')::int AS date_key,
       TO_CHAR(d, 'FMDay') AS day_name,
       EXTRACT(ISODOW FROM d)::int AS day_of_week,
       TO_CHAR(d, 'FMMonth') AS month_name,
       TO_CHAR(d, 'YYYY-MM') AS year_month
FROM generate_series(DATE '2024-01-01', DATE '2024-01-07', INTERVAL '1 day') AS d;
       -- Outcome: 2024-01-01 -> 20240101, Monday, 1, January, 2024-01 ... 2024-01-07 -> Sunday, 7
       --     * ISODOW: Monday = 1 ... Sunday = 7 (ISO standard, week starts on Monday).
       --     * 'FM' removes the padding spaces added by TO_CHAR ('Monday   ' -> 'Monday').

-- B3. Test the dynamic start and end of the calendar
SELECT DATE_TRUNC('year', MIN(order_date)) AS calendar_start,
       DATE_TRUNC('year', MAX(order_date)) + INTERVAL '1 year - 1 day' AS calendar_end
FROM silver.sales;
       -- Outcome: 2024-01-01 00:00:00 -> 2024-12-31 00:00:00
       --     * DATE_TRUNC('year', ...) = 1st of January, + '1 year - 1 day' = 31st of December.


-- PART C. CREATE - build the gold view with all tested columns

-- C1. Drop the old version (so this script can be re-run safely)
DROP VIEW IF EXISTS gold.dim_date;

-- C2. Create gold.dim_date
CREATE VIEW gold.dim_date AS
SELECT
    d::date AS full_date,
    TO_CHAR(d, 'YYYYMMDD')::int AS date_key,
    EXTRACT(DAY FROM d)::int AS day_of_month,
    EXTRACT(ISODOW FROM d)::int AS day_of_week,
    TO_CHAR(d, 'FMDay') AS day_name,
    TO_CHAR(d, 'Dy') AS day_short,
    (EXTRACT(ISODOW FROM d) IN (6, 7)) AS is_weekend,
    EXTRACT(WEEK FROM d)::int AS iso_week,
    EXTRACT(MONTH FROM d)::int AS month,
    TO_CHAR(d, 'FMMonth') AS month_name,
    TO_CHAR(d, 'Mon') AS month_short,
    TO_CHAR(d, 'YYYY-MM') AS year_month,
    EXTRACT(QUARTER FROM d)::int AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)::int AS quarter_name,
    EXTRACT(YEAR FROM d)::int AS year
FROM generate_series(
       (SELECT DATE_TRUNC('year', MIN(order_date)) FROM silver.sales),
       (SELECT DATE_TRUNC('year', MAX(order_date)) + INTERVAL '1 year - 1 day' FROM silver.sales),
       INTERVAL '1 day'
       ) AS d;
       -- Outcome: "CREATE VIEW" success.
       --     * month / quarter / year replace order_month / order_quarter / order_year of the sales table.


-- PART D. VALIDATE - check the new gold view

-- D1. Row count, range and key uniqueness
SELECT COUNT(*) AS days,
       MIN(full_date) AS first_day,
       MAX(full_date) AS last_day,
       COUNT(DISTINCT full_date) AS distinct_days
FROM gold.dim_date;
       -- Outcome: 366 | 2024-01-01 | 2024-12-31 | 366 (2024 is a leap year).

-- D2. Data types of the view
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
   AND table_name = 'dim_date'
ORDER BY ordinal_position;
       -- Outcome: full_date = date, is_weekend = boolean, names / labels = text, numbers = integer.

-- D3. Check weekend vs weekday
SELECT is_weekend, COUNT(*)
FROM gold.dim_date
GROUP BY is_weekend;
       -- Outcome: false 262 | true 104.

-- D4. Check every order date exists in the calendar
SELECT COUNT(*) AS sales_rows_without_date
FROM silver.sales s
LEFT JOIN gold.dim_date d ON d.full_date = s.order_date
WHERE d.full_date IS NULL;
       -- Outcome: 0 -> every sale finds its day.

-- D5. Final look at the view
SELECT *
FROM gold.dim_date
LIMIT 10;
       -- Outcome: 15 columns, 1 row per day.
       -- Note: iso_week of 2024-12-30 and 2024-12-31 = 1 (ISO week 1 of 2025). This is the ISO standard, not an error.
