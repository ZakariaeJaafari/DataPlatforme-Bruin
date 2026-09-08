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

unit_tests:
  - name: filters_invalid_rows_and_keeps_latest_duplicate
    inputs:
      - asset: ingestion.trips
        rows:
          - {pickup_datetime: "2022-01-10 10:00:00", dropoff_datetime: "2022-01-10 10:15:00", payment_type: 1, taxi_type: yellow, pickup_location_id: 1, dropoff_location_id: 2, fare_amount: 12.5, trip_distance: 3.0, passenger_count: 1, extracted_at: "2022-02-01 00:00:00"}
          - {pickup_datetime: "2022-01-10 10:00:00", dropoff_datetime: "2022-01-10 10:15:00", payment_type: 2, taxi_type: yellow, pickup_location_id: 1, dropoff_location_id: 2, fare_amount: 12.5, trip_distance: 3.0, passenger_count: 1, extracted_at: "2022-02-02 00:00:00"}
          - {pickup_datetime: "2022-01-11 10:00:00", dropoff_datetime: "2022-01-11 10:05:00", payment_type: 1, taxi_type: yellow, pickup_location_id: 1, dropoff_location_id: 2, fare_amount: -1.0, trip_distance: 1.0, passenger_count: 1, extracted_at: "2022-02-02 00:00:00"}
      - asset: ingestion.payment_lookup
        rows:
          - {payment_type_id: 1, payment_type_name: Credit card}
          - {payment_type_id: 2, payment_type_name: Cash}
    expected:
      rows:
        - {pickup_datetime: "2022-01-10 10:00:00", dropoff_datetime: "2022-01-10 10:15:00", taxi_type: yellow, payment_type: 2, payment_type_name: Cash, pickup_location_id: 1, dropoff_location_id: 2, fare_amount: 12.5, trip_distance: 3.0, passenger_count: 1}

@bruin */

WITH filtered AS (
  SELECT *
  FROM ingestion.trips
  WHERE pickup_datetime >= '{{ start_datetime }}'
    AND pickup_datetime < '{{ end_datetime }}'
    AND pickup_datetime IS NOT NULL
    AND dropoff_datetime IS NOT NULL
    AND fare_amount >= 0
    AND (trip_distance IS NULL OR trip_distance >= 0)
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
