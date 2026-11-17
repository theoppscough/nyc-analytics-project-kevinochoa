-- Grain: one row per open parking or camera violation summons issued to a license plate.
-- Built from stg_open_camera_violations (already filtered to NYPD + deduped on summons_number).
--
-- KEY RULES (the dims MUST build their keys with the exact same expressions):
--   license_key        = MD5 hash of state | license_type
--   issuing_agency_key = MD5 hash of agency_name
--   precinct_key       = MD5 hash of precinct number (leading zeros stripped)
--   *_date_key         = 'YYYYMMDD', or '-1' if missing
--   violation_time_key = 2-digit hour '00'-'23', or '-1' if missing/unparseable

WITH stg AS (
    SELECT * FROM {{ ref('stg_open_camera_violations') }}
),

prepped AS (
    SELECT
        *,

        -- Normalize precinct: '019' -> '19'; blanks/0/non-numeric -> 'UNKNOWN'
        COALESCE(
            CAST(NULLIF(SAFE_CAST(police_precinct AS INT64), 0) AS STRING),
            'UNKNOWN'
        ) AS precinct_clean,

        -- violation_time looks like '0915A', '09:15A', '1142P'
        REGEXP_EXTRACT(UPPER(violation_time), r'^(\d{1,2}):?\d{2}\s*[AP]') AS vt_hour_raw,
        REGEXP_EXTRACT(UPPER(violation_time), r'^\d{1,2}:?\d{2}\s*([AP])') AS vt_ampm
    FROM stg
),

with_hour AS (
    SELECT
        *,
        CASE
            WHEN SAFE_CAST(vt_hour_raw AS INT64) NOT BETWEEN 0 AND 12 THEN NULL
            WHEN vt_ampm = 'A' AND SAFE_CAST(vt_hour_raw AS INT64) = 12 THEN 0
            WHEN vt_ampm = 'P' AND SAFE_CAST(vt_hour_raw AS INT64) < 12
                THEN SAFE_CAST(vt_hour_raw AS INT64) + 12
            ELSE SAFE_CAST(vt_hour_raw AS INT64)
        END AS violation_hour_24
    FROM prepped
)

SELECT
    -- Surrogate key
    TO_HEX(MD5(summons_number))                                   AS violation_key,

    -- Degenerate dimensions / measures
    summons_number,
    type_of_violation,
    fine_amount,
    penalty_amount,
    interest_amount,
    reduction_amount,
    payment_amount,
    amount_due,
    violation_status,
    plate,

    -- Foreign keys
    TO_HEX(MD5(CONCAT(
        COALESCE(UPPER(state), 'UNKNOWN'), '|',
        COALESCE(UPPER(license_type), 'UNKNOWN')
    )))                                                           AS license_key,

    TO_HEX(MD5(COALESCE(UPPER(agency_name), 'UNKNOWN')))          AS issuing_agency_key,

    COALESCE(FORMAT_DATE('%Y%m%d', DATE(issue_date)), '-1')       AS issue_date_key,

    COALESCE(LPAD(CAST(violation_hour_24 AS STRING), 2, '0'), '-1') AS violation_time_key,

    TO_HEX(MD5(precinct_clean))                                   AS precinct_key,

    COALESCE(FORMAT_DATE('%Y%m%d', DATE(judgment_entry_date)), '-1') AS judgement_entry_date_key

FROM with_hour