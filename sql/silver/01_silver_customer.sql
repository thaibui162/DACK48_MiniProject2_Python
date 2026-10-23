-- 01 - SILVER CUSTOMER
-- Source: bronze."Raw_Customer"   (loaded by ELT/1_Customer_Master_ELT.py)
-- Target: silver.customer


-- PART A. EXPLORE - understand the raw data

-- A1. Preview the first 10 rows
SELECT *
FROM bronze."Raw_Customer"
LIMIT 10;
       -- Outcome: 
       --     * 13 columns = 12 source columns + ingestion_timestamp.
       --     * join_date: text, not a real date ('11/17/2023')
       --     * tax_code: stored as a decimal number (2416011000.0)
       --     * phone: leading 0 lost because it is a number (2868978194)

-- A2. Check the data type of every column
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
   AND table_name = 'Raw_Customer'
ORDER BY ordinal_position;
       -- Outcome:
       --     * text: customer_id, customer_name, customer_type, channel, province, region, address, join_date, status
       --     * bigint: phone, credit_limit
       --     * double precision: tax_code
       --     * timestamp: ingestion_timestamp
       -- To fix: join_date -> DATE, phone -> text, tax_code -> text.

-- A3. Checck how many times has this table been loaded?
SELECT ingestion_timestamp, 
       COUNT(*) AS row_count
FROM bronze."Raw_Customer"
GROUP BY ingestion_timestamp;
       -- Outcome: 1 row only, 2000 records -> table only been loaded once, no duplicated load.

-- A4. Check row count vs. distinct customer_id
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT customer_id) AS distinct_customer_id
FROM bronze."Raw_Customer";
       -- Outcome: 2000 / 2000 -> customer_id is unique and can be the primary key.

-- A5. Check NULL count per column
SELECT
    COUNT(*) - COUNT(customer_id) AS null_customer_id,
    COUNT(*) - COUNT(customer_name) AS null_customer_name,
    COUNT(*) - COUNT(customer_type) AS null_customer_type,
    COUNT(*) - COUNT(channel) AS null_channel,
    COUNT(*) - COUNT(province) AS null_province,
    COUNT(*) - COUNT(region) AS null_region,
    COUNT(*) - COUNT(address) AS null_address,
    COUNT(*) - COUNT(phone) AS null_phone,
    COUNT(*) - COUNT(tax_code) AS null_tax_code,
    COUNT(*) - COUNT(join_date) AS null_join_date,
    COUNT(*) - COUNT(credit_limit) AS null_credit_limit,
    COUNT(*) - COUNT(status) AS null_status
FROM bronze."Raw_Customer";
       -- Outcome: only tax_code has nulls: 1035 / 2000.
       -- Decision: keep NULL and add a helper column has_tax_code (true/false) for analysis if needed.

-- A6. Check leading / trailing spaces in text columns
SELECT COUNT(*) AS rows_with_extra_spaces
FROM bronze."Raw_Customer"
WHERE customer_id <> TRIM(customer_id)
   OR customer_name <> TRIM(customer_name)
   OR customer_type <> TRIM(customer_type)
   OR channel <> TRIM(channel)
   OR province <> TRIM(province)
   OR region <> TRIM(region)
   OR status <> TRIM(status);
       -- Outcome: 0 -> no extra spaces today.
       -- Decision: still apply TRIM() in silver as a defensive step for future loads.

-- A7. Check distinct values of categorical columns (look for typos / inconsistencies)
SELECT 'customer_type' AS col, customer_type AS value, COUNT(*) 
FROM bronze."Raw_Customer" 
GROUP BY customer_type
UNION ALL
SELECT 'channel', channel, COUNT(*) 
FROM bronze."Raw_Customer" 
GROUP BY channel
UNION ALL
SELECT 'region', region, COUNT(*) 
FROM bronze."Raw_Customer" 
GROUP BY region
UNION ALL
SELECT 'status', status, COUNT(*) 
FROM bronze."Raw_Customer" 
GROUP BY status
ORDER BY 1, 3 DESC;
       -- Outcome: values are clean, no typos.
       --     * customer_type (6): Canteen - 366, Online Seller - 362, Tap hoa - 340, Cua hang tien loi - 333, Sieu thi - 313, Nha hang - 286
       --     * channel (3): Traditional Trade - 992, Modern Trade - 646, E-commerce - 362
       --     * region (3): Mien Bac - 704, Mien Trung - 660, Mien Nam - 636
       --     * status (2): Active - 1843, Inactive - 157

-- A8. Check each customer_type always in the same channel
SELECT customer_type, channel, COUNT(*) AS customers
FROM bronze."Raw_Customer"
GROUP BY customer_type, channel
ORDER BY channel, customer_type;
       -- Outcome: yes, 1 type -> 1 channel (consistent business rule):
       --     * Traditional Trade = Canteen, Nha hang, Tap hoa
       --     * Modern Trade = Cua hang tien loi, Sieu thi
       --     * E-commerce = Online Seller

-- A9. Check every province belong to only one region
SELECT province, COUNT(DISTINCT region) AS region_count
FROM bronze."Raw_Customer"
GROUP BY province
   HAVING COUNT(DISTINCT region) > 1;
       -- Outcome: 0 rows -> province/region mapping is consistent.

-- A10. Check the numeric column for negative, zero, or anomalous values.
SELECT credit_limit, COUNT(*) AS customers
FROM bronze."Raw_Customer"
GROUP BY credit_limit
ORDER BY credit_limit;
       -- Outcome: 
       --     * Only 4 fixed tiers -> 50M (502), 100M (512), 200M (477), 500M (509).
       --     * No negative or zero values -> nothing to fix.

-- A11. Check the customer names are unique
SELECT customer_name, COUNT(*) AS cnt
FROM bronze."Raw_Customer"
GROUP BY customer_name
   HAVING COUNT(*) > 1
ORDER BY cnt DESC;
       -- Outcome: 58 names appear more than once, but customer_id is different. These are different shops with the same name, not duplicates.
       -- Note: join on customer_id, never on customer_name.

-- A12. Check the join_date text format (M/D/YYYY or MM/DD/YYYY) before converting
SELECT join_date
FROM bronze."Raw_Customer"
WHERE join_date !~ '^\d{1,2}/\d{1,2}/\d{4}$';
       -- Outcome: 0 rows -> every value follows M/D/YYYY.


-- PART B. TEST - try each transformation with SELECT

-- B1. Convert join_date: text -> DATE
SELECT join_date AS join_date_raw,
       TO_DATE(join_date, 'MM/DD/YYYY') AS join_date_clean
FROM bronze."Raw_Customer"
LIMIT 10;
       -- Outcome: '5/3/2022' -> 2022-05-03, '11/17/2023' -> 2023-11-17. Works.

-- B2. Check the minimum and maximum dates after the conversion (to check the sanity of the converted dates)
SELECT MIN(TO_DATE(join_date, 'MM/DD/YYYY')) AS min_join_date,
       MAX(TO_DATE(join_date, 'MM/DD/YYYY')) AS max_join_date
FROM bronze."Raw_Customer";
       -- Outcome: 2018-01-01 -> 2024-03-29. Reasonable range, no strange dates.

-- B3. Convert phone: number -> text and add back the leading 0
SELECT phone AS phone_raw,
       '0' || phone::text AS phone_clean
FROM bronze."Raw_Customer"
LIMIT 10;
       -- Outcome: 2868978194 -> '02868978194' (11 digits = VN landline format).

-- B4. Convert tax_code: decimal number -> text
SELECT tax_code AS tax_code_raw,
       tax_code::bigint::text AS tax_code_clean,
       LENGTH(tax_code::bigint::text) AS tax_code_length,
       (tax_code IS NOT NULL) AS has_tax_code
FROM bronze."Raw_Customer"
LIMIT 10;
       -- Outcome: 2416011000.0 -> '2416011000'. 
       --     * NULL stays NULL, has_tax_code = false.
       --     * Casting to bigint first removes the ".0" before turning it into text.

-- B5. Check legistimate of tax codes
SELECT LENGTH(tax_code::bigint::text) AS tax_code_length, COUNT(*)
FROM bronze."Raw_Customer"
WHERE tax_code IS NOT NULL
GROUP BY 1;
       -- Outcome: 10 digits -> 965 rows. All valid VN tax code length.


-- PART C. CREATE - build the silver table with all tested transformations

-- C1. Drop the old version (so this script can be re-run safely)
DROP TABLE IF EXISTS silver.customer CASCADE;

-- C2. Create silver.customer
CREATE TABLE silver.customer AS
SELECT
    TRIM(customer_id) AS customer_id,
    TRIM(customer_name) AS customer_name,
    TRIM(customer_type) AS customer_type,
    TRIM(channel) AS channel,
    TRIM(province) AS province,
    TRIM(region) AS region,
    TRIM(address) AS address,
    '0' || phone::text AS phone,
    tax_code::bigint::text AS tax_code,
    (tax_code IS NOT NULL) AS has_tax_code,
    TO_DATE(join_date, 'MM/DD/YYYY') AS join_date,
    credit_limit::bigint AS credit_limit,
    TRIM(status) AS status,
    ingestion_timestamp
FROM bronze."Raw_Customer"
WHERE ingestion_timestamp = (
       SELECT MAX(ingestion_timestamp)
       FROM bronze."Raw_Customer"
       );
       -- Outcome: "Updated Rows: 2000".

-- C3. Add the primary key
ALTER TABLE silver.customer ADD PRIMARY KEY (customer_id);


-- PART D. VALIDATE - check the new silver table

-- D1. Row count must equal bronze
SELECT (SELECT COUNT(*) FROM bronze."Raw_Customer") AS bronze_rows,
       (SELECT COUNT(*) FROM silver.customer)       AS silver_rows;
       -- Outcome: 2000 | 2000 -> no rows lost.

-- D2. Data types after cleaning
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
   AND table_name = 'customer'
ORDER BY ordinal_position;
       -- Outcome: join_date = date, phone = text, tax_code = text, has_tax_code = boolean, credit_limit = bigint.

-- D3. Final look at the clean data
SELECT *
FROM silver.customer
LIMIT 10;
       -- Outcome: dates are real dates, phone starts with 0, tax_code has no ".0".

-- D4. has_tax_code split
SELECT has_tax_code, COUNT(*)
FROM silver.customer
GROUP BY has_tax_code;
       -- Outcome: true 965 | false 1035.