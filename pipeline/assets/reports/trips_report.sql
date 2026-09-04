/* @bruin

name: reports.trips_report
type: duckdb.sql

depends:
  - staging.trips

materialization:
  type: table
  strategy: time_interval
  incremental_key: trip_date
  time_granularity: date

columns:
  - name: trip_date
    type: date
    description: Trip date (derived from pickup_datetime)
    primary_key: true
    checks:
      - name: not_null
  - name: taxi_type
    type: string
    description: Taxi fleet type (yellow or green)
    primary_key: true
    checks:
      - name: not_null
  - name: payment_type
    type: integer
    description: TLC payment type code
    primary_key: true
    checks:
      - name: not_null
  - name: payment_type_name
    type: string
    description: Human-readable payment type
  - name: trip_count
    type: bigint
    description: Number of trips in the group
    checks:
      - name: non_negative
  - name: total_fare_amount
    type: float
    description: Sum of fare amounts for the group
    checks:
      - name: non_negative
  - name: total_trip_distance
    type: float
    description: Sum of trip distances for the group
    checks:
      - name: non_negative

@bruin */

SELECT
  CAST(pickup_datetime AS DATE) AS trip_date,
  taxi_type,
  payment_type,
  payment_type_name,
  COUNT(*) AS trip_count,
  SUM(fare_amount) AS total_fare_amount,
  SUM(trip_distance) AS total_trip_distance
FROM staging.trips
WHERE pickup_datetime >= '{{ start_datetime }}'
  AND pickup_datetime < '{{ end_datetime }}'
GROUP BY 1, 2, 3, 4
