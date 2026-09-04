# MotherDuck + Bruin Cloud Setup

Use this guide after the code changes in this repo. **You must complete the manual steps below** — tokens and cloud UI config cannot be automated here.

## Architecture

| Environment | Command | Where data lives |
|-------------|---------|------------------|
| `default` | `bruin run ... -e default` | Local `duckdb.db` |
| `production` | `./scripts/run-production.sh ...` | [MotherDuck](https://motherduck.com/) database `nyc_taxi` |

Pipeline assets stay the same (`duckdb.sql`, `duckdb.seed`, Python). Only the connection backend changes per environment.

---

## Manual steps (you do these)

### 1. Create a MotherDuck account

1. Go to [https://motherduck.com/](https://motherduck.com/) and sign up.
2. Open [MotherDuck UI](https://app.motherduck.com/).

### 2. Create a database

```sql
CREATE DATABASE nyc_taxi;
```

Must match `database: nyc_taxi` in `.bruin.yml`.

### 3. Create an access token

1. MotherDuck UI → **Settings** → **Access Tokens**
2. **Create token** → copy it (`md_...`, shown once)

### 4. Set the token locally

**Bruin does not read `.env` automatically.**

```bash
cp .env.example .env
# Edit .env: MOTHERDUCK_TOKEN=md_...
```

### 5. Copy Bruin config (if needed)

```bash
cp .bruin.yml.example .bruin.yml
```

### 6. Run the pipeline on MotherDuck

**Recommended — helper script** (loads `.env`, uses `--workers 1`):

```bash
chmod +x scripts/run-production.sh

# Small month (quick test)
./scripts/run-production.sh \
  --full-refresh \
  --start-date 2022-01-01 \
  --end-date 2022-02-01 \
  --var 'taxi_types=["yellow"]' \
  --force

# Large month (6.4M rows — uses chunked batches)
./scripts/run-production.sh \
  --full-refresh \
  --start-date 2020-01-01 \
  --end-date 2020-02-01 \
  --var 'taxi_types=["yellow"]' \
  --force
```

You should see logs like `Yielding batch 1 (150000 rows)...` for large months.

Verify:

```bash
set -a && source .env && set +a
bruin query --connection duckdb-default --environment production \
  --query "SELECT COUNT(*) FROM ingestion.trips"
```

### 7. Connect Bruin Cloud

1. [Bruin Cloud dashboard](https://cloud.getbruin.com/)
2. **Projects** → connect `ZakariaeJaafari/DataPlatforme-Bruin`
3. **Connections** → **MotherDuck**
   - **Name:** `duckdb-default`
   - **Token:** your MotherDuck token
   - **Database:** `nyc_taxi`
4. **Catalog → Pipelines** → enable `nyc-taxi-pipeline`
5. Run with environment **`production`**

---

## How chunked ingestion works

`trips.py` uses a **generator** that yields **150,000-row PyArrow batches**. Each batch stays under Bruin's ~256 MB Arrow IPC limit, so large months (e.g. January 2020 with 6.4M rows) upload successfully.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `MotherDuck token is required` | Use `./scripts/run-production.sh` or `export MOTHERDUCK_TOKEN=...` — `.env` alone is not enough |
| `Access is denied` (Windows extension) | Script uses `--workers 1`; don't run ingestion assets in parallel |
| `file block body length ... exceeds limit 268435456` | Fixed by chunked generator — pull latest `trips.py` |
| `trip_distance.non_negative` failed | Staging filters negative distances; re-run staging with `--downstream` |
| Connection not found in Cloud | Name must be `duckdb-default` |
| Missing tables | Run with `--full-refresh` on `production` |

### Re-run staging + reports only

```bash
set -a && source .env && set +a
bruin run ./pipeline/assets/staging/trips.sql \
  --environment production \
  --workers 1 \
  --start-date 2020-01-01 \
  --end-date 2020-02-01 \
  --downstream \
  --force
```

---

## References

- [Bruin MotherDuck platform docs](https://getbruin.com/docs/bruin/platforms/motherduck)
- [Bruin Cloud getting started](https://bruin-data.github.io/bruin/cloud/getting-started.html)
- [MotherDuck + Bruin integration](https://motherduck.com/ecosystem/bruin/)
