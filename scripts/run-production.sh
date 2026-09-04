#!/usr/bin/env bash
# Load MOTHERDUCK_TOKEN from .env and run the pipeline on MotherDuck (production).
# Usage:
#   ./scripts/run-production.sh --full-refresh --start-date 2022-01-01 --end-date 2022-02-01 --var 'taxi_types=["yellow"]'

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${MOTHERDUCK_TOKEN:-}" ]]; then
  echo "Error: MOTHERDUCK_TOKEN is not set."
  echo "  1. cp .env.example .env"
  echo "  2. Add your token: MOTHERDUCK_TOKEN=md_..."
  echo "  Or run: export MOTHERDUCK_TOKEN=\"md_...\""
  exit 1
fi

exec bruin run ./pipeline/pipeline.yml --environment production --workers 1 "$@"
