import json
import random
import uuid
from datetime import datetime, timezone
import snowflake.snowpark as snowpark
import pandas as pd

# ==========================================
# MERCEDES VEHICLE CONSTANTS & DTC CODES
# ==========================================
MODELS = ["EQE 350+", "EQS 450+", "AMG EQE Sedan", "EQS SUV", "AMG GT 63 S"]
COUNTRIES = ["DE", "US", "IN", "UK", "CA"]

DTC_CODES = {
    "P0A7F": "Hybrid/EV Battery Pack Deterioration",
    "P0A3F": "Drive Motor Position Sensor Circuit Fault",
    "C0035": "Left Front Wheel Speed Sensor Fault",
    "P0217": "Engine/Battery Thermal Overheat Condition",
    "NONE": "System Status Nominal"
}

def generate_vehicle_telemetry(num_records=250):
    events = []
    for _ in range(num_records):
        vehicle_num = random.randint(100, 999)
        model = random.choice(MODELS)
        
        battery_soc = round(random.uniform(12.0, 99.0), 2)
        battery_temp = round(random.uniform(22.0, 58.0), 1)
        brake_wear = round(random.uniform(5.0, 95.0), 1)
        speed = round(random.uniform(0.0, 160.0), 1)
        
        if battery_temp > 50.0:
            dtc = "P0217"
        elif battery_soc < 15.0 and random.random() > 0.5:
            dtc = "P0A7F"
        elif brake_wear > 85.0:
            dtc = "C0035"
        else:
            dtc = random.choice(["NONE", "NONE", "NONE", "P0A3F"])

        payload = {
            "vehicle": {
                "vin_id": f"W1K-{model[:3]}-{vehicle_num}",
                "model_name": model,
                "production_year": random.choice([2023, 2024, 2025]),
                "country_code": random.choice(COUNTRIES)
            },
            "metrics": {
                "battery_soc_pct": battery_soc,
                "battery_temp_celsius": battery_temp,
                "brake_pad_wear_pct": brake_wear,
                "speed_kmh": speed
            },
            "diagnostics": {
                "dtc_code": dtc,
                "dtc_description": DTC_CODES[dtc]
            },
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

        event_id = str(uuid.uuid4())[:18]
        events.append((event_id, json.dumps(payload)))
        
    return events

def main(session: snowpark.Session):
    # Set context inside Python
    session.sql("USE DATABASE MERCEDES_BENZ_FLEET").collect()
    session.sql("USE SCHEMA TELEMETRY_STAGE").collect()
    
    # Generate telemetry records in Python
    telemetry_data = generate_vehicle_telemetry(250)
    
    # Load into a Pandas DataFrame for high-speed bulk ingestion
    df_raw = pd.DataFrame(telemetry_data, columns=["EVENT_ID", "RAW_PAYLOAD_STR"])
    
    # Push Pandas dataframe to a Snowpark DataFrame temporary table
    df_snow = session.create_dataframe(df_raw)
    df_snow.create_or_replace_temp_view("temp_telemetry_stream")
    
    # Parse JSON strings into VARIANT column and insert into RAW table
    session.sql("""
        INSERT INTO RAW_VEHICLE_TELEMETRY (EVENT_ID, RAW_PAYLOAD)
        SELECT EVENT_ID, PARSE_JSON(RAW_PAYLOAD_STR)
        FROM temp_telemetry_stream
    """).collect()
    
    success_msg = f"✅ Success! Ingested {len(telemetry_data)} raw Mercedes IoT JSON records using Snowpark Python."
    print(success_msg)
    return success_msg