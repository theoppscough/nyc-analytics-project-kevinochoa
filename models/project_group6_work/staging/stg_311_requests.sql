-- CIS 9440 Group 6 - Milestone 4
-- Clean and standardize NYPD parking/traffic-related 311 service requests
-- One row per service request

WITH source AS (
    SELECT *
    FROM {{ source('raw', 'source_311_service_requests_project') }}
), -- Easier to refer to the dbt reference to a long table name

cleaned AS (
    SELECT
        -- Get all columns from source, except ones we're transforming below
        * EXCEPT (
            unique_key,
            created_date,
            closed_date,
            agency,
            agency_name,
            complaint_type,
            descriptor,
            status,
            location_type,
            incident_zip,
            incident_address,
            street_name,
            city,
            borough,
            police_precinct,
            open_data_channel_type,
            vehicle_type
        ),

        -- Identifiers
        CAST(unique_key AS STRING) AS request_id,

        -- Date/Time
        SAFE_CAST(created_date AS TIMESTAMP) AS created_date,
        SAFE_CAST(closed_date AS TIMESTAMP) AS closed_date,

        -- Request details
        TRIM(CAST(agency AS STRING)) AS agency,
        TRIM(CAST(agency_name AS STRING)) AS agency_name,
        TRIM(CAST(complaint_type AS STRING)) AS complaint_type,
        TRIM(CAST(descriptor AS STRING)) AS descriptor,
        UPPER(TRIM(CAST(status AS STRING))) AS status,

        -- Location
        TRIM(CAST(location_type AS STRING)) AS location_type,

        -- Clean ZIP code
        CASE
            WHEN UPPER(TRIM(CAST(incident_zip AS STRING)))
                IN ('N/A', 'NA', '') THEN NULL
            WHEN UPPER(TRIM(CAST(incident_zip AS STRING)))
                = 'ANONYMOUS' THEN 'Anonymous'
            WHEN REGEXP_CONTAINS(
                TRIM(CAST(incident_zip AS STRING)),
                r'^\d{5}(-\d{4})?$'
            )
            THEN TRIM(CAST(incident_zip AS STRING))
            ELSE NULL
        END AS incident_zip,

        -- Standardize borough names
        CASE
            WHEN UPPER(TRIM(borough))
                IN ('MANHATTAN', 'NEW YORK COUNTY')
                THEN 'Manhattan'
            WHEN UPPER(TRIM(borough))
                IN ('BRONX', 'THE BRONX')
                THEN 'Bronx'
            WHEN UPPER(TRIM(borough))
                IN ('BROOKLYN', 'KINGS COUNTY')
                THEN 'Brooklyn'
            WHEN UPPER(TRIM(borough))
                IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY')
                THEN 'Queens'
            WHEN UPPER(TRIM(borough))
                IN ('STATEN ISLAND', 'RICHMOND COUNTY')
                THEN 'Staten Island'
            ELSE 'UNKNOWN or CITYWIDE'
        END AS borough,

        TRIM(CAST(incident_address AS STRING)) AS incident_address,
        TRIM(CAST(street_name AS STRING)) AS street_name,
        TRIM(CAST(city AS STRING)) AS city,
        TRIM(CAST(police_precinct AS STRING)) AS police_precinct,

        -- Method of submission
        CAST(open_data_channel_type AS STRING) AS channel_type,

        -- Vehicle information
        CAST(vehicle_type AS STRING) AS vehicle_type,

        -- Metadata
        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source

    -- Filters: NYPD requests in the four selected complaint types
    WHERE agency = 'NYPD'
      AND complaint_type IN (
          'Blocked Driveway',
          'Illegal Parking',
          'Noise - Vehicle',
          'Traffic'
      )
      AND unique_key IS NOT NULL
      AND created_date IS NOT NULL

    -- Deduplicate
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY unique_key
        ORDER BY created_date DESC
    ) = 1
)

SELECT * FROM cleaned