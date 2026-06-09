#!/usr/bin/env python3
"""
Fetch live bookmaker odds for World Cup 2026 group stage matches
from The Odds API (free tier: 500 requests/month).

Sign up at: https://the-odds-api.com — free tier gives 500 req/month.
Set your key: export ODDS_API_KEY="your_key_here"
Or add to ~/.zshrc: export ODDS_API_KEY="your_key_here"

What it does:
  1. Fetches current odds for soccer_fifa_world_cup from The Odds API
  2. Normalises to implied probabilities (removes bookmaker margin)
  3. Writes/merges results to BigQuery: ML_WC_2026.odds_bookmaker
  4. Can be called from refresh.py before dbt run

Usage:
  python3 fetch_odds.py          # fetch and load to BQ
  python3 fetch_odds.py --dry-run  # print only, don't write to BQ
"""

import os
import sys
import json
import argparse
from datetime import datetime, timezone
from pathlib import Path

import requests
from google.cloud import bigquery
from google.cloud.bigquery import SchemaField, LoadJobConfig, SourceFormat, WriteDisposition

BQ_PROJECT = "analytics-project-production"
BQ_DATASET = "ML_WC_2026"
BQ_TABLE   = "odds_bookmaker"
API_BASE   = "https://api.the-odds-api.com/v4"
SPORT_KEY  = "soccer_fifa_world_cup"
MARKETS    = "h2h"          # head-to-head (win/draw/win)
REGIONS    = "uk,eu"        # UK + EU bookmakers

SCHEMA = [
    SchemaField("fetched_at",        "TIMESTAMP"),
    SchemaField("match_id",          "STRING"),
    SchemaField("kickoff_utc",       "TIMESTAMP"),
    SchemaField("home_team",         "STRING"),
    SchemaField("away_team",         "STRING"),
    SchemaField("bookmaker_count",   "INTEGER"),
    # Consensus implied probabilities (averaged across bookmakers, margin removed)
    SchemaField("implied_p_home",    "FLOAT64"),
    SchemaField("implied_p_draw",    "FLOAT64"),
    SchemaField("implied_p_away",    "FLOAT64"),
    # Best available odds (highest = most value)
    SchemaField("best_odds_home",    "FLOAT64"),
    SchemaField("best_odds_draw",    "FLOAT64"),
    SchemaField("best_odds_away",    "FLOAT64"),
]

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def get_api_key():
    key = os.environ.get("ODDS_API_KEY")
    if not key:
        raise EnvironmentError(
            "ODDS_API_KEY not set. Get a free key at https://the-odds-api.com\n"
            "Then run: export ODDS_API_KEY='your_key'"
        )
    return key

def fetch_odds(api_key):
    url = f"{API_BASE}/sports/{SPORT_KEY}/odds"
    params = {
        "apiKey":  api_key,
        "regions": REGIONS,
        "markets": MARKETS,
        "oddsFormat": "decimal",
        "dateFormat": "iso",
    }
    resp = requests.get(url, params=params, timeout=15)
    resp.raise_for_status()

    remaining = resp.headers.get("x-requests-remaining", "?")
    used      = resp.headers.get("x-requests-used", "?")
    log(f"API quota: {used} used, {remaining} remaining this month")

    return resp.json()

def normalise_to_probs(odds_list):
    """Convert decimal odds to implied probabilities, removing overround."""
    # Raw implied probs (sum > 1.0 due to bookmaker margin)
    raw = [1.0 / o for o in odds_list]
    total = sum(raw)
    # Normalise so they sum to 1.0
    return [p / total for p in raw]

def process_events(events):
    rows = []
    now = datetime.now(timezone.utc).isoformat()

    for event in events:
        home = event["home_team"]
        away = event["away_team"]
        kickoff = event["commence_time"]
        bookmakers = event.get("bookmakers", [])

        if not bookmakers:
            continue

        all_home, all_draw, all_away = [], [], []

        for bm in bookmakers:
            for market in bm.get("markets", []):
                if market["key"] != "h2h":
                    continue
                outcomes = {o["name"]: o["price"] for o in market["outcomes"]}
                h = outcomes.get(home)
                d = outcomes.get("Draw")
                a = outcomes.get(away)
                if h and d and a:
                    all_home.append(h)
                    all_draw.append(d)
                    all_away.append(a)

        if not all_home:
            continue

        # Consensus: average odds across bookmakers
        avg_home = sum(all_home) / len(all_home)
        avg_draw = sum(all_draw) / len(all_draw)
        avg_away = sum(all_away) / len(all_away)

        # Normalised implied probabilities
        p_home, p_draw, p_away = normalise_to_probs([avg_home, avg_draw, avg_away])

        rows.append({
            "fetched_at":       now,
            "match_id":         event["id"],
            "kickoff_utc":      kickoff,
            "home_team":        home,
            "away_team":        away,
            "bookmaker_count":  len(all_home),
            "implied_p_home":   round(p_home, 4),
            "implied_p_draw":   round(p_draw, 4),
            "implied_p_away":   round(p_away, 4),
            "best_odds_home":   round(max(all_home), 2),
            "best_odds_draw":   round(max(all_draw), 2),
            "best_odds_away":   round(max(all_away), 2),
        })

    return rows

def write_to_bigquery(rows):
    client = bigquery.Client(project=BQ_PROJECT)
    table_ref = f"{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}"

    # Use WRITE_TRUNCATE so we always have fresh odds (not accumulating stale rows)
    job_config = LoadJobConfig(
        schema=SCHEMA,
        write_disposition=WriteDisposition.WRITE_TRUNCATE,
        source_format=SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    job = client.load_table_from_json(rows, table_ref, job_config=job_config)
    job.result()
    log(f"Written {len(rows)} matches to {BQ_TABLE}")

def main(dry_run=False):
    log("=== Fetching bookmaker odds ===")
    api_key = get_api_key()
    events  = fetch_odds(api_key)
    rows    = process_events(events)

    log(f"Processed {len(rows)} upcoming matches with odds")
    for r in rows:
        log(f"  {r['home_team']} vs {r['away_team']}: "
            f"H={r['implied_p_home']:.1%} D={r['implied_p_draw']:.1%} A={r['implied_p_away']:.1%} "
            f"({r['bookmaker_count']} books)")

    if dry_run:
        log("Dry run — not writing to BigQuery")
        return

    if not rows:
        log("No matches with odds found — skipping BQ write")
        return

    write_to_bigquery(rows)
    log("=== Done ===")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        main(dry_run=args.dry_run)
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
