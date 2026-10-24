-- 02 - GOLD DIM_EMPLOYEE
-- Source: silver.employee
-- Target: gold.dim_employee (VIEW, 1 row = 1 employee, latest version only)


-- PART A. EXPLORE - check the silver data is ready to be a dimension

-- A1. Check how many versions each employee has (SCD Type 2)
SELECT versions, COUNT(*) AS employees
FROM (SELECT employee_id, COUNT(*) AS versions
      FROM silver.employee
      GROUP BY employee_id) AS t
GROUP BY versions;
       -- Outcome: versions = 1 -> 114 employees. Today each employee has only v1.

-- A2. Check the age distribution
SELECT age, COUNT(*) AS employees
FROM silver.employee
GROUP BY age
ORDER BY age;
       -- Outcome: age 21 -> 48, most employees are 25 - 34.
       -- Decision: add age_group -> '<25' | '25-34' | '35-44' | '45+'

-- A3. Check the tenure distribution
SELECT tenure_years, COUNT(*) AS employees
FROM silver.employee
GROUP BY tenure_years
ORDER BY tenure_years;
       -- Outcome: tenure 1 -> 14 years.
       -- Decision: add tenure_group -> '0-1 yr' | '2-4 yrs' | '5-9 yrs' | '10+ yrs'


-- PART B. TEST - try each new column with SELECT

-- B1. Pick the latest version with a window function
SELECT employee_id, version, effective_date,
       ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY effective_date DESC) AS rn
FROM silver.employee
LIMIT 10;
       -- Outcome: rn = 1 for every row today (only one version each).

-- B2. Test age_group and tenure_group
SELECT employee_id, age, tenure_years,
       CASE WHEN age < 25 THEN '<25'
            WHEN age < 35 THEN '25-34'
            WHEN age < 45 THEN '35-44'
            ELSE '45+' END AS age_group,
       CASE WHEN tenure_years <= 1 THEN '0-1 yr'
            WHEN tenure_years <= 4 THEN '2-4 yrs'
            WHEN tenure_years <= 9 THEN '5-9 yrs'
            ELSE '10+ yrs' END AS tenure_group
FROM silver.employee
LIMIT 10;
       -- Outcome: e.g. EMP1001 -> age 44 -> '35-44', tenure 7 -> '5-9 yrs'.


-- PART C. CREATE - build the gold view with all tested columns

-- C1. Drop the old version (so this script can be re-run safely)
DROP VIEW IF EXISTS gold.dim_employee;

-- C2. Create gold.dim_employee
CREATE VIEW gold.dim_employee AS
WITH latest AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY effective_date DESC) AS rn
    FROM silver.employee
)
SELECT
    employee_id,
    full_name,
    gender,
    date_of_birth,
    age,
    CASE WHEN age < 25 THEN '<25'
         WHEN age < 35 THEN '25-34'
         WHEN age < 45 THEN '35-44'
         ELSE '45+' END AS age_group,
    join_date,
    tenure_years,
    CASE WHEN tenure_years <= 1 THEN '0-1 yr'
         WHEN tenure_years <= 4 THEN '2-4 yrs'
         WHEN tenure_years <= 9 THEN '5-9 yrs'
         ELSE '10+ yrs' END AS tenure_group,
    "position",
    team,
    region AS employee_region,
    email,
    phone,
    status,
    version,
    effective_date,
    resign_date,
    flag_joined_under_18
FROM latest
WHERE rn = 1;
       -- Outcome: "CREATE VIEW" success.


-- PART D. VALIDATE - check the new gold view

-- D1. Row count must equal silver
SELECT (SELECT COUNT(*) FROM silver.employee) AS silver_rows,
       (SELECT COUNT(*) FROM gold.dim_employee) AS gold_rows,
       (SELECT COUNT(DISTINCT employee_id) FROM gold.dim_employee) AS distinct_employee_id;
       -- Outcome: 114 | 114 | 114 -> no rows lost, key unique.

-- D2. Data types of the view
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
   AND table_name = 'dim_employee'
ORDER BY ordinal_position;
       -- Outcome: age_group / tenure_group / employee_region = text, other columns same as silver.

-- D3. Check the group columns
SELECT 'age_group' AS col, age_group AS value, COUNT(*)
FROM gold.dim_employee
GROUP BY age_group
UNION ALL
SELECT 'tenure_group', tenure_group, COUNT(*)
FROM gold.dim_employee
GROUP BY tenure_group
ORDER BY 1, 2;
       -- Outcome:
       --     * age_group: <25 = 25 | 25-34 = 77 | 35-44 = 7 | 45+ = 5
       --     * tenure_group: 0-1 yr = 12 | 2-4 yrs = 51 | 5-9 yrs = 48 | 10+ yrs = 3
       --     * each group sums to 114.

-- D4. Final look at the view
SELECT *
FROM gold.dim_employee
LIMIT 10;
       -- Outcome: new columns age_group / tenure_group / employee_region are filled.
