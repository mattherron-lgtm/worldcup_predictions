#!/usr/bin/env python3
"""
Sync historical football results from Kaggle to BigQuery.
Downloads latest international match results and loads to staging table.

Usage (local):
  python scripts/sync_kaggle_historical_results.py

Usage (GitHub Actions):
  Set environment variables: KAGGLE_USERNAME, KAGGLE_KEY, GOOGLE_APPLICATION_CREDENTIALS_JSON
"""

import os
import json
import sys
import kagglehub
import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account


def main():
    print("🔄 Starting Kaggle historical results sync...\n")

    # ─── Authenticate Kaggle ───
    print("📥 Downloading Kaggle dataset...")
    try:
        path = kagglehub.dataset_download("martj42/international-football-results-from-1872-to-2017")
        print(f"   ✅ Dataset downloaded to: {path}")
    except Exception as e:
        print(f"   ❌ Failed to download Kaggle dataset: {e}")
        sys.exit(1)

    # ─── Read CSV ───
    print("📖 Reading results.csv...")
    try:
        df = pd.read_csv(f"{path}/results.csv")
        print(f"   ✅ Loaded {len(df)} match records")
    except Exception as e:
        print(f"   ❌ Failed to read CSV: {e}")
        sys.exit(1)

    # ─── Authenticate BigQuery ───
    print("🔑 Authenticating to BigQuery...")
    try:
        # Check if running in GitHub Actions (has GOOGLE_APPLICATION_CREDENTIALS_JSON env var)
        creds_json = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
        
        if creds_json:
            # Parse JSON from environment variable (GitHub Actions)
            creds_dict = json.loads(creds_json)
            credentials = service_account.Credentials.from_service_account_info(creds_dict)
            client = bigquery.Client(project="analytics-project-production", credentials=credentials)
            print("   ✅ Authenticated via service account (GitHub Actions)")
        else:
            # Use default credentials (local dev with gcloud auth)
            client = bigquery.Client(project="analytics-project-production")
            print("   ✅ Authenticated via default credentials (local dev)")
    except Exception as e:
        print(f"   ❌ Failed to authenticate to BigQuery: {e}")
        sys.exit(1)

    # ─── Load to BigQuery ───
    print("📤 Loading to BigQuery...")
    try:
        table_id = "analytics-project-production.ML_WC_2026.staging_historical_results_kaggle"
        
        job_config = bigquery.LoadJobConfig(
            autodetect=True,
            write_disposition="WRITE_TRUNCATE",  # Replace entire table
        )
        
        job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
        job.result()  # Wait for completion
        
        print(f"   ✅ Loaded {len(df)} rows to {table_id}")
    except Exception as e:
        print(f"   ❌ Failed to load to BigQuery: {e}")
        sys.exit(1)

    print("\n✅ Sync completed successfully!")


if __name__ == "__main__":
    main()
