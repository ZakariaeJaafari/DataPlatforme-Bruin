"""@bruin

name: ingestion.trips
type: python
image: python:3.11
connection: duckdb-default

materialization:
  type: table
  strategy: append

columns:
  - name: pickup_datetime
    type: timestamp
    description: When the trip started
    checks:
      - name: not_null
  - name: dropoff_datetime
    type: timestamp
    description: When the trip ended
  - name: payment_type
    type: integer
    description: TLC payment type code (joins to payment_lookup)
  - name: taxi_type
    type: string
    description: Taxi fleet type (yellow or green)
  - name: pickup_location_id
    type: integer
    description: TLC pickup zone identifier
  - name: dropoff_location_id
    type: integer
    description: TLC dropoff zone identifier
  - name: fare_amount
    type: float
    description: Base fare in USD
  - name: trip_distance
    type: float
    description: Trip distance in miles
  - name: passenger_count
    type: integer
    description: Number of passengers
  - name: extracted_at
    type: timestamp
    description: Timestamp when the row was extracted from the TLC source

@bruin"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
from dateutil.relativedelta import relativedelta

TLC_BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
CACHE_DIR = Path(__file__).resolve().parent / "cache"
# Keep each Arrow batch under Bruin's ~256 MB IPC limit (large months e.g. 2020-01).
BATCH_SIZE = 150_000

DATETIME_COLUMNS = {
    "yellow": {
        "tpep_pickup_datetime": "pickup_datetime",
        "tpep_dropoff_datetime": "dropoff_datetime",
    },
    "green": {
        "lpep_pickup_datetime": "pickup_datetime",
        "lpep_dropoff_datetime": "dropoff_datetime",
    },
}

PARQUET_COLUMNS = {
    "yellow": [
        "tpep_pickup_datetime",
        "tpep_dropoff_datetime",
        "PULocationID",
        "DOLocationID",
        "payment_type",
        "fare_amount",
        "trip_distance",
        "passenger_count",
    ],
    "green": [
        "lpep_pickup_datetime",
        "lpep_dropoff_datetime",
        "PULocationID",
        "DOLocationID",
        "payment_type",
        "fare_amount",
        "trip_distance",
        "passenger_count",
    ],
}


def ensure_cached(url: str, taxi_type: str, year: int, month: int) -> Path:
    columns = PARQUET_COLUMNS[taxi_type]
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / f"{taxi_type}_tripdata_{year}-{month:02d}.parquet"

    if cache_path.exists():
        print(f"Using cached file: {cache_path}")
        return cache_path

    print(f"Downloading: {url}")
    pq.write_table(pq.read_table(url, columns=columns), cache_path)
    return cache_path


def transform_batch(
    batch: pa.RecordBatch,
    taxi_type: str,
    extracted_at: datetime,
    rename_map: dict[str, str],
) -> pa.Table:
    df = batch.to_pandas()
    df = df.rename(columns={k: v for k, v in rename_map.items() if k in df.columns})
    df["taxi_type"] = taxi_type
    df["extracted_at"] = extracted_at
    return pa.Table.from_pandas(df, preserve_index=False)


def materialize():
    start_date = os.environ["BRUIN_START_DATE"]
    end_date = os.environ["BRUIN_END_DATE"]
    vars_json = json.loads(os.environ.get("BRUIN_VARS", "{}"))
    taxi_types = vars_json.get("taxi_types", ["yellow"])

    start_dt = datetime.fromisoformat(start_date)
    end_dt = datetime.fromisoformat(end_date)
    extracted_at = datetime.now(timezone.utc)

    current_dt = start_dt

    while current_dt < end_dt:
        year = current_dt.year
        month = current_dt.month

        for taxi_type in taxi_types:
            url = f"{TLC_BASE_URL}/{taxi_type}_tripdata_{year}-{month:02d}.parquet"
            columns = PARQUET_COLUMNS[taxi_type]
            rename_map = {
                **DATETIME_COLUMNS.get(taxi_type, {}),
                "PULocationID": "pickup_location_id",
                "DOLocationID": "dropoff_location_id",
            }

            try:
                cache_path = ensure_cached(url, taxi_type, year, month)
                parquet_file = pq.ParquetFile(cache_path)
                total_rows = 0
                batch_num = 0

                for batch in parquet_file.iter_batches(
                    batch_size=BATCH_SIZE, columns=columns
                ):
                    batch_num += 1
                    total_rows += batch.num_rows
                    print(
                        f"Yielding batch {batch_num} "
                        f"({batch.num_rows} rows) for {taxi_type} {year}-{month:02d}"
                    )
                    yield transform_batch(batch, taxi_type, extracted_at, rename_map)

                print(f"Loaded {total_rows} rows for {taxi_type} {year}-{month:02d}")
            except Exception as exc:
                raise RuntimeError(
                    f"Failed to load {taxi_type} trips for {year}-{month:02d} "
                    f"from {url}"
                ) from exc

        current_dt += relativedelta(months=1)
