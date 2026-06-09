#!/usr/bin/env python3
"""
Daily refresh script for the World Cup 2026 predictions pipeline.

What it does:
  1. Downloads the latest results.csv from Kaggle
  2. Reloads it into BigQuery (worldcup_raw_eu.historical_match_results)
  3. Runs dbt to rebuild all prediction tables in ML_WC_2026

Usage:
  python3 refresh.py

Schedule daily via cron (runs at 8am):
  0 8 * * * cd /Users/mattherron/Documents/worldcup_predictions && python3 refresh.py >> logs/refresh.log 2>&1
"""

import os
import subprocess
import sys
import shutil
from pathlib import Path
from datetime import datetime

from google.cloud import bigquery
from google.cloud.bigquery import LoadJobConfig, SchemaField, SourceFormat, WriteDisposition

PROJECT_DIR   = Path(__file__).parent
DATA_DIR      = PROJECT_DIR / "data"
BQ_PROJECT    = "analytics-project-production"
BQ_DATASET    = "worldcup_raw_eu"
BQ_TABLE      = "historical_match_results"
KAGGLE_SLUG   = "martj42/international-football-results-from-1872-to-2017"
RESULTS_SCHEMA = [
    SchemaField("date",       "DATE"),
    SchemaField("home_team",  "STRING"),
    SchemaField("away_team",  "STRING"),
    SchemaField("home_score", "STRING"),
    SchemaField("away_score", "STRING"),
    SchemaField("tournament", "STRING"),
    SchemaField("city",       "STRING"),
    SchemaField("country",    "STRING"),
    SchemaField("neutral",    "BOOL"),
]

def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def run(cmd, **kwargs):
    log(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, check=True, **kwargs)
    return result

def download_results():
    log("Downloading latest dataset from Kaggle...")
    tmp_dir = DATA_DIR / "_kaggle_tmp"
    tmp_dir.mkdir(exist_ok=True)

    run([
        "kaggle", "datasets", "download",
        "--dataset", KAGGLE_SLUG,
        "--path", str(tmp_dir),
        "--unzip"
    ])

    src = tmp_dir / "results.csv"
    dst = DATA_DIR / "results.csv"

    if not src.exists():
        raise FileNotFoundError(f"results.csv not found in {tmp_dir}")

    shutil.move(str(src), str(dst))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    log(f"results.csv updated at {dst}")

def reload_bigquery():
    log("Reloading results.csv into BigQuery...")
    client = bigquery.Client(project=BQ_PROJECT)
    table_ref = f"{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}"
    job_config = LoadJobConfig(
        schema=RESULTS_SCHEMA,
        source_format=SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=WriteDisposition.WRITE_TRUNCATE,
    )
    with open(DATA_DIR / "results.csv", "rb") as f:
        job = client.load_table_from_file(f, table_ref, job_config=job_config)
    job.result()  # wait for completion
    log(f"BigQuery load complete. {job.output_rows} rows loaded.")

def fetch_odds():
    """Fetch bookmaker odds and load to BQ (requires ODDS_API_KEY env var)."""
    import importlib.util
    if not os.environ.get("ODDS_API_KEY"):
        log("ODDS_API_KEY not set — skipping odds fetch (set it to enable)")
        return
    log("Fetching bookmaker odds...")
    spec = importlib.util.spec_from_file_location(
        "fetch_odds", PROJECT_DIR / "fetch_odds.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.main()

def run_dbt():
    log("Running dbt pipeline...")
    run(
        ["dbt", "run", "--exclude", "mart_wc_match_narratives"],
        cwd=str(PROJECT_DIR)
    )
    log("dbt run complete.")

def row_count():
    """Quick sanity check — print row count and latest date after reload."""
    client = bigquery.Client(project=BQ_PROJECT)
    query = (
        f"SELECT COUNT(*) as total_rows, MAX(date) as latest_date "
        f"FROM `{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}`"
    )
    row = next(client.query(query).result())
    log(f"Table stats: {row.total_rows:,} rows, latest match date: {row.latest_date}")

if __name__ == "__main__":
    log("=== World Cup 2026 daily refresh starting ===")
    try:
        download_results()
        reload_bigquery()
        row_count()
        fetch_odds()
        run_dbt()
        log("=== Refresh complete ===")
    except subprocess.CalledProcessError as e:
        log(f"ERROR: command failed with exit code {e.returncode}")
        sys.exit(1)
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
