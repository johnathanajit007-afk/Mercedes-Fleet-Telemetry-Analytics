USE DATABASE MERCEDES_BENZ_FLEET;
USE SCHEMA TELEMETRY_STAGE;

-- Populate 250 realistic vehicle telemetry events directly in Snowflake SQL
INSERT INTO RAW_VEHICLE_TELEMETRY (EVENT_ID, RAW_PAYLOAD)
SELECT 
    UUID_STRING() AS EVENT_ID,
    OBJECT_CONSTRUCT(
        'vehicle', OBJECT_CONSTRUCT(
            'vin_id', 'W1K-EQS-' || UNIFORM(100, 999, RANDOM()),
            'model_name', GET(ARRAY_CONSTRUCT('EQE 350+', 'EQS 450+', 'AMG EQE Sedan', 'EQS SUV', 'AMG GT 63 S'), UNIFORM(0, 4, RANDOM())),
            'production_year', UNIFORM(2023, 2025, RANDOM()),
            'country_code', GET(ARRAY_CONSTRUCT('DE', 'US', 'IN', 'UK', 'CA'), UNIFORM(0, 4, RANDOM()))
        ),
        'metrics', OBJECT_CONSTRUCT(
            'battery_soc_pct', ROUND(UNIFORM(120, 990, RANDOM()) / 10.0, 2),
            'battery_temp_celsius', ROUND(UNIFORM(220, 580, RANDOM()) / 10.0, 1),
            'brake_pad_wear_pct', ROUND(UNIFORM(50, 950, RANDOM()) / 10.0, 1),
            'speed_kmh', ROUND(UNIFORM(0, 1600, RANDOM()) / 10.0, 1)
        ),
        'diagnostics', OBJECT_CONSTRUCT(
            'dtc_code', GET(ARRAY_CONSTRUCT('NONE', 'NONE', 'P0A7F', 'P0217', 'C0035'), UNIFORM(0, 4, RANDOM())),
            'dtc_description', 'Diagnostic Trouble Log'
        ),
        'timestamp', CURRENT_TIMESTAMP()
    ) AS RAW_PAYLOAD
FROM TABLE(GENERATOR(ROWCOUNT => 250));

SELECT COUNT(*) AS TOTAL_RECORD_COUNT FROM RAW_VEHICLE_TELEMETRY;

USE DATABASE MERCEDES_BENZ_FLEET;
USE SCHEMA TELEMETRY_STAGE;

-- =========================================================
-- STEP 3: TRANSFORM RAW JSON INTO STRUCTURED RELATIONAL TABLE
-- =========================================================

-- Clear out any previous runs so we start fresh
USE DATABASE MERCEDES_BENZ_FLEET;
USE SCHEMA TELEMETRY_STAGE;

-- Clear out any previous runs so we start fresh
TRUNCATE TABLE PROCESSED_VEHICLE_TELEMETRY;

-- Insert parsed, structured data from the RAW VARIANT column
INSERT INTO PROCESSED_VEHICLE_TELEMETRY
SELECT 
    EVENT_ID,
    RAW_PAYLOAD:vehicle:vin_id::STRING AS VEHICLE_ID,
    RAW_PAYLOAD:vehicle:model_name::STRING AS MODEL_NAME,
    RAW_PAYLOAD:vehicle:production_year::INT AS PRODUCTION_YEAR,
    RAW_PAYLOAD:metrics:battery_soc_pct::FLOAT AS BATTERY_SOC_PCT,
    RAW_PAYLOAD:metrics:battery_temp_celsius::FLOAT AS BATTERY_TEMP_CELSIUS,
    RAW_PAYLOAD:metrics:brake_pad_wear_pct::FLOAT AS BRAKE_PAD_WEAR_PCT,
    RAW_PAYLOAD:diagnostics:dtc_code::STRING AS DIAGNOSTIC_TROUBLE_CODE,
    RAW_PAYLOAD:metrics:speed_kmh::FLOAT AS SPEED_KMH,
    RAW_PAYLOAD:vehicle:country_code::STRING AS COUNTRY_CODE,
    RAW_PAYLOAD:timestamp::TIMESTAMP_NTZ AS EVENT_TIMESTAMP,
    
    -- Analytical risk score calculation based on temperature and brake wear
    ROUND(
        (RAW_PAYLOAD:metrics:battery_temp_celsius::FLOAT * 0.6) + 
        (RAW_PAYLOAD:metrics:brake_pad_wear_pct::FLOAT * 0.4), 2
    ) AS COMPONENT_RISK_SCORE,
    
    -- Categorize alert status based on diagnostic codes or thresholds
    CASE 
        WHEN RAW_PAYLOAD:diagnostics:dtc_code::STRING != 'NONE' THEN 'CRITICAL ALERT'
        WHEN RAW_PAYLOAD:metrics:battery_temp_celsius::FLOAT > 45.0 THEN 'THERMAL WARNING'
        WHEN RAW_PAYLOAD:metrics:brake_pad_wear_pct::FLOAT > 80.0 THEN 'MAINTENANCE DUE'
        ELSE 'NORMAL'
    END AS ALERT_STATUS

FROM RAW_VEHICLE_TELEMETRY;

SELECT COUNT(*) AS PROCESSED_COUNT FROM PROCESSED_VEHICLE_TELEMETRY;
SELECT * FROM PROCESSED_VEHICLE_TELEMETRY LIMIT 10;

USE DATABASE MERCEDES_BENZ_FLEET;
USE SCHEMA TELEMETRY_STAGE;

-- Verify total ingested rows from Snowpark Python
SELECT COUNT(*) AS TOTAL_RECORD_COUNT FROM RAW_VEHICLE_TELEMETRY;

-- Preview the latest records
SELECT * FROM RAW_VEHICLE_TELEMETRY LIMIT 5;