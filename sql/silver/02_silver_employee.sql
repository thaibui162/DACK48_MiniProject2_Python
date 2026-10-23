-- 02 - SILVER EMPLOYEE
-- Source : bronze."Raw_Employee"   (loaded by ELT/3_Employee_ELT.py)
-- Target : silver.employee


-- PART A. EXPLORE - understand the raw data

-- A1. Preview the first 10 rows
SELECT *
FROM bronze."Raw_Employee"
LIMIT 10;
       -- Outcome: 
       --     * 16 columns = 15 source columns + ingestion_timestamp.
       --     * date_of_birth / join_date / effective_date: already ISO format, but stored as text because pandas read them as text ('1980-06-29')
       --     * phone: looks 9 digits, leading 0 lost (928728463)
       --     * resign_date and transfer_note: empty

-- A2. Check the data type of every column
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
   AND table_name = 'Raw_Employee'
ORDER BY ordinal_position;
       -- Outcome:
       --     * text: employee_id, full_name, gender, date_of_birth, join_date, position, region, team, email, status, version, effective_date
       --     * bigint: phone
       --     * double precision: resign_date, transfer_note
       --     * timestamp: ingestion_timestamp
       -- To fix: 3 date columns -> DATE, resign_date -> DATE, transfer_note -> text, phone -> text.

-- A3. Checck how many times has this table been loaded?
SELECT ingestion_timestamp, COUNT(*) AS row_count
FROM bronze."Raw_Employee"
GROUP BY ingestion_timestamp;
       -- Outcome: 1 row only, 114 records -> loaded once.

-- A4. Check row count vs. distinct employee_id
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT employee_id) AS distinct_employee_id
FROM bronze."Raw_Employee";
       -- Outcome: 114 | 114 -> employee_id is unique today.

-- A5. Check NULL count per column
SELECT
    COUNT(*) - COUNT(employee_id) AS null_employee_id,
    COUNT(*) - COUNT(full_name) AS null_full_name,
    COUNT(*) - COUNT(gender) AS null_gender,
    COUNT(*) - COUNT(date_of_birth) AS null_date_of_birth,
    COUNT(*) - COUNT(join_date) AS null_join_date,
    COUNT(*) - COUNT("position") AS null_position,
    COUNT(*) - COUNT(region) AS null_region,
    COUNT(*) - COUNT(team) AS null_team,
    COUNT(*) - COUNT(email) AS null_email,
    COUNT(*) - COUNT(phone) AS null_phone,
    COUNT(*) - COUNT(resign_date) AS null_resign_date,
    COUNT(*) - COUNT(transfer_note) AS null_transfer_note
FROM bronze."Raw_Employee";
       -- Outcome: only resign_date and transfer_note are NULL: 114 / 114.
       -- Decision: keep both columns (correct types).

-- A6. Check leading / trailing spaces in text columns
SELECT COUNT(*) AS rows_with_extra_spaces
FROM bronze."Raw_Employee"
WHERE employee_id <> TRIM(employee_id)
   OR full_name <> TRIM(full_name)
   OR gender <> TRIM(gender)
   OR "position" <> TRIM("position")
   OR region <> TRIM(region)
   OR team <> TRIM(team)
   OR email <> TRIM(email);
       -- Outcome: 0 -> clean. TRIM() is still applied in silver as a defensive step.

-- A7. Check distinct values of categorical columns (look for typos / inconsistencies)
SELECT 'gender' AS col, gender AS value, COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY gender
UNION ALL
SELECT 'position', "position", COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY "position"
UNION ALL
SELECT 'region', region, COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY region
UNION ALL
SELECT 'status', status, COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY status
UNION ALL
SELECT 'version', version, COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY version
UNION ALL
SELECT 'effective_date', effective_date, COUNT(*) 
FROM bronze."Raw_Employee" 
GROUP BY effective_date
ORDER BY 1, 3 DESC;
       -- Outcome: values are clean, no typos.
       --   * gender (2): Nu 61, Nam 53
       --   * position (4): Senior Sales Representative 58, Sales Representative 44, Sales Supervisor 9, Area Manager 3
       --   * region (3): Mien Nam 61, Mien Bac 34, Mien Trung 19
       --   * status: Active 114 (everyone active)
       --   * version: v1 114, effective_date: 2024-01-01 for everyone

-- A8. Check the consistent of team vs. region
SELECT team, region, COUNT(*) AS employees
FROM bronze."Raw_Employee"
GROUP BY team, region
ORDER BY region, team;
       -- Outcome: consistent.
       --   * Team Bac 1-3 -> Mien Bac (11 each)
       --   * Team Nam 1-4 -> Mien Nam (15 each)
       --   * Team Trung 1-2 -> Mien Trung (9 each)
       --   * Management -> 3 Area Managers, 1 per region

-- A9. Check the employee names are unique
SELECT full_name, STRING_AGG(employee_id, ', ') AS ids, COUNT(*) AS cnt
FROM bronze."Raw_Employee"
GROUP BY full_name
   HAVING COUNT(*) > 1;
       -- Outcome: 2 names repeated:
       --     * Hoang Ba Van -> EMP1068, EMP1109
       --     * Do Thanh Kien -> EMP1082, EMP1088
       -- Different people with the same name -> NOT duplicates. Always join on employee_id.

-- A10. Check the email follows the pattern (<employee_id>@vietdist.com.vn)
SELECT COUNT(*) AS email_not_matching_pattern
FROM bronze."Raw_Employee"
WHERE email <> LOWER(employee_id) || '@vietdist.com.vn';
       -- Outcome: 0 -> all 114 emails follow the company pattern.

-- A11. Check the date text format before converting
SELECT date_of_birth, join_date, effective_date
FROM bronze."Raw_Employee"
WHERE date_of_birth  !~ '^\d{4}-\d{2}-\d{2}'
   OR join_date      !~ '^\d{4}-\d{2}-\d{2}'
   OR effective_date !~ '^\d{4}-\d{2}-\d{2}';
       -- Outcome: 0 rows -> all dates are YYYY-MM-DD -> a simple ::date cast works.


-- PART B. TEST - try each transformation with SELECT

-- B1. Convert the date columns: text -> DATE and check the ranges
SELECT MIN(date_of_birth::date) AS min_dob, MAX(date_of_birth::date) AS max_dob,
       MIN(join_date::date) AS min_join, MAX(join_date::date) AS max_join
FROM bronze."Raw_Employee";
       -- Outcome: date_of_birth: 1976-01-08 -> 2003-09-28, join_date: 2010-12-27 -> 2023-11-19

-- B2. Age at joining date
SELECT employee_id,
       date_of_birth::date AS date_of_birth,
       join_date::date AS join_date,
       DATE_PART('year', AGE(join_date::date, date_of_birth::date)) AS age_at_join,
       "position"
FROM bronze."Raw_Employee"
WHERE AGE(join_date::date, date_of_birth::date) < INTERVAL '18 years'
ORDER BY age_at_join;
       -- Outcome: 8 employees joined BEFORE 18 years old (15 - 17): EMP1045 (15), EMP1059 (15), EMP1046 (16), EMP1069 (16), EMP1104 (16), EMP1006 (17), EMP1019 (17), EMP1035 (17)
       --     -> Data quality issue, might me wrong birth date or join date in source.
       -- Decision: Cannot know the correct value -> keep the row and add a flag column flag_joined_under_18 so it can be filtered in reports.

-- B3. Calculate age and tenure
SELECT employee_id,
       DATE_PART('year', AGE(DATE '2024-12-31', date_of_birth::date))::int AS age,
       DATE_PART('year', AGE(DATE '2024-12-31', join_date::date))::int AS tenure_years
FROM bronze."Raw_Employee"
LIMIT 10;
       -- Outcome: e.g. EMP1001 -> age 44, tenure 7 years.
       -- Overall: age ~21 -> 48, tenure ~1 -> 14 years.

-- B4. Convert phone: number -> text and add back the leading 0
SELECT phone AS phone_raw,
       '0' || phone::text  AS phone_clean
FROM bronze."Raw_Employee"
LIMIT 10;
       -- Outcome: 928728463 -> '0928728463' (10 digits = VN mobile format).


-- PART C. CREATE - build the silver table with all tested transformations

-- C1. Drop the old version (so this script can be re-run safely)
DROP TABLE IF EXISTS silver.employee CASCADE;

-- C2. Create silver.employee
CREATE TABLE silver.employee AS
SELECT
    TRIM(employee_id) AS employee_id,
    TRIM(full_name) AS full_name,
    TRIM(gender) AS gender,
    date_of_birth::date AS date_of_birth,
    join_date::date AS join_date,
    TRIM("position") AS "position",
    TRIM(region) AS region,
    TRIM(team) AS team,
    LOWER(TRIM(email)) AS email,
    '0' || phone::text AS phone,
    TRIM(status) AS status,
    TRIM(version) AS version,
    effective_date::date AS effective_date,
    resign_date::text::date AS resign_date,   
    transfer_note::text AS transfer_note, 
    DATE_PART('year', AGE(DATE '2024-12-31', date_of_birth::date))::int AS age,
    DATE_PART('year', AGE(DATE '2024-12-31', join_date::date))::int AS tenure_years,
    (AGE(join_date::date, date_of_birth::date) < INTERVAL '18 years') AS flag_joined_under_18,
    ingestion_timestamp
FROM bronze."Raw_Employee"
WHERE ingestion_timestamp = 
       (SELECT MAX(ingestion_timestamp)
       FROM bronze."Raw_Employee"
       );
       -- Outcome: "Updated Rows: 114".

-- C3. Add the primary key
ALTER TABLE silver.employee ADD PRIMARY KEY (employee_id, version);


-- PART D. VALIDATE - check the new silver table

-- D1. Row count must equal bronze
SELECT (SELECT COUNT(*) FROM bronze."Raw_Employee") AS bronze_rows,
       (SELECT COUNT(*) FROM silver.employee) AS silver_rows;
       -- Outcome: 114 | 114 -> no rows lost.


-- D2. Data types after cleaning
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name = 'employee'
ORDER BY ordinal_position;
       -- Outcome: 
       --     * date_of_birth / join_date / effective_date / resign_date = date,
       --     * phone / transfer_note = text, age / tenure_years = integer,
       --     * flag_joined_under_18 = boolean.

-- D3. Flag check
SELECT flag_joined_under_18, COUNT(*)
FROM silver.employee
GROUP BY flag_joined_under_18;
       -- Outcome: false 106 | true 8.


-- D4. Final look at the clean data
SELECT *
FROM silver.employee
LIMIT 10;
       -- Outcome: real dates, phone starts with 0, new columns age / tenure_years / flag_joined_under_18 are filled.
