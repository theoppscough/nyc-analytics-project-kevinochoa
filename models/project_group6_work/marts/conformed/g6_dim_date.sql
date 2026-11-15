{{ config(alias='dim_date') }}  -- model name must be unique project-wide; table is still called dim_date

-- Conformed date dimension shared by Fact_311Complaint and
-- Fact_open_parking_camera_violations.
-- Grain: one row per calendar day, plus one '-1' row for unknown/missing dates.
-- date_key format: 'YYYYMMDD' (string), e.g. '20240315'.

WITH bounds_source AS (
    -- Pull every date the facts can point to, so no fact row is ever orphaned
    SELECT DATE(issue_date) AS d FROM {{ ref('stg_open_camera_violations') }}
    UNION ALL
    SELECT DATE(judgment_entry_date) FROM {{ ref('stg_open_camera_violations') }}
    UNION ALL
    SELECT DATE(created_date) FROM {{ ref('stg_311_requests') }}
    UNION ALL
    SELECT DATE(closed_date) FROM {{ ref('stg_311_requests') }}
),

bounds AS (
    SELECT
        DATE_TRUNC(MIN(d), YEAR)                         AS start_date,
        LAST_DAY(GREATEST(MAX(d), CURRENT_DATE()), YEAR) AS end_date
    FROM bounds_source
    WHERE d IS NOT NULL
),

spine AS (
    SELECT full_date
    FROM bounds,
    UNNEST(GENERATE_DATE_ARRAY(start_date, end_date, INTERVAL 1 DAY)) AS full_date
),

calendar AS (
    SELECT
        FORMAT_DATE('%Y%m%d', full_date)          AS date_key,
        full_date,
        EXTRACT(YEAR FROM full_date)              AS year,
        EXTRACT(MONTH FROM full_date)             AS month,
        EXTRACT(DAY FROM full_date)               AS day,
        FORMAT_DATE('%B', full_date)              AS month_name,
        FORMAT_DATE('%A', full_date)              AS day_of_week,
        EXTRACT(DAYOFWEEK FROM full_date)         AS dow_num,   -- 1 = Sunday ... 7 = Saturday
        CAST(CEIL(EXTRACT(DAY FROM full_date) / 7) AS INT64) AS week_of_month
    FROM spine
)

SELECT
    date_key,
    full_date,
    year,
    month,
    day,
    month_name,
    day_of_week,
    dow_num IN (1, 7) AS is_weekend,

    -- US federal holidays (actual date, not the observed Fri/Mon)
    (
           (month = 1  AND day = 1)                                   -- New Year's Day
        OR (month = 1  AND dow_num = 2 AND week_of_month = 3)         -- MLK Day
        OR (month = 2  AND dow_num = 2 AND week_of_month = 3)         -- Presidents' Day
        OR (month = 5  AND dow_num = 2 AND day > 24)                  -- Memorial Day (last Mon)
        OR (month = 6  AND day = 19 AND year >= 2021)                 -- Juneteenth
        OR (month = 7  AND day = 4)                                   -- Independence Day
        OR (month = 9