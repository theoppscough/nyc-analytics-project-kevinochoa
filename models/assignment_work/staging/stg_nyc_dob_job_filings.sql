-- Clean and standardize NYC DOB Job Applications
-- One row per service request

WITH source AS (
   SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
), -- Easier to refer to the dbt reference to a long name table this way

cleaned AS (
   SELECT
       -- Get all columns from source, except ones we're transforming below
       -- To do cleaning on them or explicitly cast them as types just in case
       * EXCEPT (
           job_filing_number,
           filing_status,
           job_type,
           filing_date,
           current_status_date,
           house_no,
           street_name,
           borough,
           zip,
           bin,
           block,
           lot,
           latitude,
           longitude,
           commmunity_board,           -- yes, the raw column really has 3 m's
           owner_s_business_name,
           job_description,
           first_permit_date,
           approved_date,
           signoff_date
       ),

       -- Identifiers
       TRIM(CAST(job_filing_number AS STRING)) AS job_filing_id,
       CAST(bin AS STRING) AS building_id,       -- BIN = Building Identification Number; keep as string (it's an ID, not a number to sum)
       CAST(block AS STRING) AS tax_block,
       CAST(lot AS STRING) AS tax_lot,

       -- Filing details
       UPPER(TRIM(CAST(filing_status AS STRING))) AS filing_status,
       UPPER(TRIM(CAST(job_type AS STRING))) AS job_type,
       CAST(job_description AS STRING) AS job_description,
       CAST(owner_s_business_name AS STRING) AS owner_business_name,

       -- Date/Time (if these load as strings and SAFE_CAST returns NULL, switch to PARSE_TIMESTAMP)
       SAFE_CAST(filing_date AS TIMESTAMP) AS filing_date,
       SAFE_CAST(current_status_date AS TIMESTAMP) AS current_status_date,
        SAFE_CAST(first_permit_date AS TIMESTAMP) AS first_permit_date,
       SAFE_CAST(approved_date AS TIMESTAMP) AS approved_date,
       SAFE_CAST(signoff_date AS TIMESTAMP) AS signoff_date,

       -- Location - address, renamed to line up with 311's incident_address
       TRIM(CONCAT(
           COALESCE(CAST(house_no AS STRING), ''), ' ',
           COALESCE(CAST(street_name AS STRING), '')
       )) AS incident_address,
       CAST(street_name AS STRING) AS street_name,

       -- Location - zip, conformed name "zip" to match 311
       -- Valid 5-digit or ZIP+4 → keep first 5 digits; anything else → NULL
       CASE
           WHEN REGEXP_CONTAINS(TRIM(CAST(zip AS STRING)), r'^\d{5}(-?\d{4})?$')
               THEN LEFT(TRIM(CAST(zip AS STRING)), 5)
           ELSE NULL
       END AS zip,

       -- Location - borough, SAME output values as stg_nyc_311_dot so they join cleanly
       CASE
           WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('MANHATTAN', 'NEW YORK COUNTY', '1') THEN 'Manhattan'
           WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('BRONX', 'THE BRONX', '2') THEN 'Bronx'
           WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('BROOKLYN', 'KINGS COUNTY', '3') THEN 'Brooklyn'
           WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('QUEENS', 'QUEENS COUNTY', '4') THEN 'Queens'
           WHEN UPPER(TRIM(CAST(borough AS STRING))) IN ('STATEN ISLAND', 'RICHMOND COUNTY', '5') THEN 'Staten Island'
           ELSE 'UNKNOWN or CITYWIDE'
       END AS borough,

       CAST(commmunity_board AS STRING) AS community_board,
       SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude,

       -- Metadata
       CURRENT_TIMESTAMP() AS _stg_loaded_at
 
   FROM source
 
    -- Filters (kept light so we don't drop too many rows)
    WHERE job_filing_number IS NOT NULL
    AND filing_date IS NOT NULL

   -- Deduplicate: keep the most recently updated version of each filing
   QUALIFY ROW_NUMBER() OVER (
       PARTITION BY TRIM(CAST(job_filing_number AS STRING))
       ORDER BY SAFE_CAST(current_status_date AS TIMESTAMP) DESC NULLS LAST
   ) = 1
)
 
SELECT * FROM cleaned
-- Builds table: stg_nyc_dob_job_filings