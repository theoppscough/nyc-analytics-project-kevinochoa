WITH source AS (
    SELECT *
    FROM {{ source('raw', 'source_open_parking_project') }}
), -- Easier to refer to the dbt reference to a long table name

cleaned AS (
    SELECT

        -- Identifiers
        CAST(summons_number AS STRING) AS summons_number,

        -- Date/Time
        SAFE.PARSE_TIMESTAMP('%m/%d/%Y', TRIM(issue_date)) AS issue_date,
        SAFE.PARSE_TIMESTAMP('%m/%d/%Y', TRIM(judgment_entry_date)) AS judgment_entry_date, 
        TRIM(CAST(violation_time AS STRING)) AS violation_time,

        --details
        TRIM(CAST(issuing_agency AS STRING)) AS agency_name,
        TRIM(CAST(plate AS STRING)) AS plate,
        TRIM(CAST(license_type AS STRING)) AS license_type,

        -- Location
        TRIM(CAST(precinct AS STRING)) AS police_precinct,
        TRIM(CAST(state AS STRING)) AS state,

        -- Standardize borough names
        CASE
            WHEN UPPER(TRIM(county))
                IN ('MANHATTAN', 'NEW YORK COUNTY')
                THEN 'Manhattan'
            WHEN UPPER(TRIM(county))
                IN ('BRONX', 'THE BRONX')
                THEN 'Bronx'
            WHEN UPPER(TRIM(county))
                IN ('BROOKLYN', 'KINGS COUNTY')
                THEN 'Brooklyn'
            WHEN UPPER(TRIM(county))
                IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY')
                THEN 'Queens'
            WHEN UPPER(TRIM(county))
                IN ('STATEN ISLAND', 'RICHMOND COUNTY')
                THEN 'Staten Island'
            ELSE 'UNKNOWN or CITYWIDE'
        END AS borough,

        --amounts
        SAFE_CAST(amount_due as NUMERIC) AS amount_due,
        SAFE_CAST(fine_amount as NUMERIC) AS fine_amount,
        SAFE_CAST(interest_amount as NUMERIC) AS interest_amount,
        SAFE_CAST(payment_amount as NUMERIC) AS payment_amount,
        SAFE_CAST(penalty_amount as NUMERIC) AS penalty_amount,
        SAFE_CAST(reduction_amount as NUMERIC) AS reduction_amount,

        --violation details
        TRIM(CAST(violation AS STRING)) AS type_of_violation,
        TRIM(CAST(violation_status AS STRING)) AS violation_status,

        -- Metadata
        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source

    -- Filters: NYPD requests in the four selected complaint types
    WHERE UPPER(TRIM(issuing_agency)) = 'POLICE DEPARTMENT'
      AND summons_number IS NOT NULL
      AND issue_date IS NOT NULL

    -- Deduplicate
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY summons_number
        ORDER BY issue_date DESC
    ) = 1
)

SELECT * FROM cleaned