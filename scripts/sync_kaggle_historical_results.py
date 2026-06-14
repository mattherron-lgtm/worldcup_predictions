#!/usr/bin/env python3
"""
Sync international football data from Kaggle to BigQuery.
Downloads:
  - Match results (1872-present)
  - Goalscorer events (when 2026 data available)
  - Penalty shootout data (for knockout stages)

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
    print("🔄 Starting Kaggle data sync...\\n")

    # ─── Authenticate Kaggle ───
    print("📥 Downloading Kaggle dataset...")
    try:
        path = kagglehub.dataset_download("martj42/international-football-results-from-1872-to-2017")
        print(f"   ✅ Dataset downloaded to: {path}")
    except Exception as e:
        print(f"   ❌ Failed to download Kaggle dataset: {e}")
        sys.exit(1)

    # ─── Read all CSV files ───
    datasets = {}
    
    # Results (required)
    print("📖 Reading results.csv...")
    try:
        datasets['results'] = pd.read_csv(f"{path}/results.csv")
        print(f"   ✅ Loaded {len(datasets['results'])} match records")
    except Exception as e:
        print(f"   ❌ Failed to read results.csv: {e}")
        sys.exit(1)

    # Goalscorers (optional - may not exist for all seasons)
    print("📖 Reading goalscorers.csv...")
    try:
        datasets['goalscorers'] = pd.read_csv(f"{path}/goalscorers.csv")
        print(f"   ✅ Loaded {len(datasets['goalscorers'])} goalscorer records")
    except FileNotFoundError:
        print(f"   ⚠️  goalscorers.csv not found (expected for older Kaggle versions)")
        datasets['goalscorers'] = None
    except Exception as e:
        print(f"   ⚠️  Failed to read goalscorers.csv: {e}")
        datasets['goalscorers'] = None

    # Shootouts (optional - only for penalty shootout data)
    print("📖 Reading shootouts.csv...")
    try:
        datasets['shootouts'] = pd.read_csv(f"{path}/shootouts.csv")
        print(f"   ✅ Loaded {len(datasets['shootouts'])} shootout records")
    except FileNotFoundError:
        print(f"   ⚠️  shootouts.csv not found")
        datasets['shootouts'] = None
    except Exception as e:
        print(f"   ⚠️  Failed to read shootouts.csv: {e}")
        datasets['shootouts'] = None

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
    print("📤 Loading to BigQuery...\\n")
    
    # Load each dataset with error handling
    load_config = {
        'results': {
            'table': 'staging_historical_results_kaggle',
            'required': True,
            'df': datasets['results']
        },
        'goalscorers': {
            'table': 'staging_goalscorers_kaggle',
            'required': False,
            'df': datasets['goalscorers']
        },
        'shootouts': {
            'table': 'staging_shootouts_kaggle',
            'required': False,
            'df': datasets['shootouts']
        }
    }
    
    loaded_count = 0
    for dataset_name, config in load_config.items():
        if config['df'] is None:
            if config['required']:
                print(f"   ❌ {dataset_name} is required but not available")
                sys.exit(1)
            else:
                print(f"   ⏭️  Skipping {dataset_name} (not available)")
                continue
        
        try:
            table_id = f"analytics-project-production.ML_WC_2026.{config['table']}"
            
            job_config = bigquery.LoadJobConfig(
                autodetect=True,
                write_disposition="WRITE_TRUNCATE",  # Replace entire table
            )
            
            job = client.load_table_from_dataframe(config['df'], table_id, job_config=job_config)
            job.result()  # Wait for completion
            
            print(f"   ✅ Loaded {len(config['df'])} rows to {config['table']}")
            loaded_count += 1
        except Exception as e:
            if config['required']:
                print(f"   ❌ Failed to load {dataset_name}: {e}")
                sys.exit(1)
            else:
                print(f"   ⚠️  Failed to load {dataset_name} (non-fatal): {e}")
    
    print(f"\\n✅ Sync completed successfully! ({loaded_count} datasets loaded)")


if __name__ == "__main__":
    main()
