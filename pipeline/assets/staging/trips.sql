/* @bruin

name: staging.trips
type: duckdb.sql

materialization:
  type: table
  strategy: time_interval
  incremental_key: pickup_datetime
  time_granularity: timestamp

depends:
  - ingestion.trips
  - ingestion.payment_lookup

columns:
  - name: pickup_datetime
    type: timestamp
    description: When the trip started
    primary_key: true
    nullable: false
    checks:
      - name: not_null
  - name: dropoff_datetime
    type: timestamp
    description: When the trip ended
    primary_key: true
    nullable: false
    checks:
      - name: not_null
  - name: pickup_location_id
    type: integer
    description: TLC pickup zone identifier
    primary_key: true
    checks:
      - name: not_null
  - name: dropoff_location_id
    type: integer
    description: TLC dropoff zone identifier
    primary_key: true
    checks:
      - name: not_null
  - name: fare_amount
    type: float
    description: Base fare in USD
    primary_key: true
    checks:
      - name: non_negative
  - name: taxi_type
    type: string
    description: Taxi fleet type (yellow or green)
    primary_key: true
    checks:
      - name: not_null
  - name: payment_type
    type: integer
    description: TLC payment type code
    checks:
      - name: not_null
  - name: payment_type_name
    type: string
    description: Human-readable payment type from lookup
  - name: trip_distance
    type: float
    description: Trip distance in miles
    checks:
      - name: non_negative
  - name: passenger_count
    type: integer
    description: Number of passengers

custom_checks:
  - name: no_duplicate_composite_keys
    description: Composite trip keys must be unique after deduplication
    value: 0
    query: |-
      SELECT COUNT(*) FROM (
        SELECT
          pickup_datetime,
          dropoff_datetime,
          pickup_location_id,
          dropoff_location_id,
          fare_amount,
          taxi_type
        FROM staging.trips
        GROUP BY 1, 2, 3, 4, 5, 6
        HAVING COUNT(*) > 1
      )

@bruin */

WITH filtered AS (
  SELECT *
  FROM ingestion.trips
  WHERE pickup_datetime >= '{{ start_datetime }}'
    AND pickup_datetime < '{{ end_datetime }}'
    AND pickup_datetime IS NOT NULL
    AND dropoff_datetime IS NOT NULL
    AND fare_amount >= 0
),
enriched AS (
  SELECT
    f.pickup_datetime,
    f.dropoff_datetime,
    f.taxi_type,
    f.payment_type,
    p.payment_type_name,
    f.pickup_location_id,
    f.dropoff_location_id,
    f.fare_amount,
    f.trip_distance,
    f.passenger_count,
    ROW_NUMBER() OVER (
      PARTITION BY
        f.pickup_datetime,
        f.dropoff_datetime,
        f.pickup_location_id,
        f.dropoff_location_id,
        f.fare_amount,
        f.taxi_type
      ORDER BY f.extracted_at DESC
    ) AS row_num
  FROM filtered AS f
  LEFT JOIN ingestion.payment_lookup AS p
    ON f.payment_type = p.payment_type_id
)
SELECT
  pickup_datetime,
  dropoff_datetime,
  taxi_type,
  payment_type,
  payment_type_name,
  pickup_location_id,
  dropoff_location_id,
  fare_amount,
  trip_distance,
  passenger_count
FROM enriched
WHERE row_num = 1
