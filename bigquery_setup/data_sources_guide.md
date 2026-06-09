# World Cup 2026 Predictions — Data Sources Guide

## Overview
This project requires historical international football results as its primary training data.
Below are the recommended sources, all free and publicly available.

---

## 1. Historical International Match Results (REQUIRED)

### Source: Kaggle — International Football Results (1872–2024)
- **URL**: https://www.kaggle.com/datasets/martj42/international-football-results-from-1872-to-2017
- **File**: `results.csv` (~50k rows)
- **Columns**: `date, home_team, away_team, home_score, away_score, tournament, city, country, neutral`
- **License**: CC0 (public domain)

### Loading into BigQuery:
```bash
# 1. Download results.csv from Kaggle
# 2. Upload to GCS
gsutil cp results.csv gs://YOUR_BUCKET/worldcup/historical_results/results.csv

# 3. Create external table — run 02_create_historical_results_table.sql
```

---

## 2. ELO Ratings (RECOMMENDED — improves prediction accuracy significantly)

### Source: eloratings.net
- **URL**: https://www.eloratings.net/
- **Download**: Click "Download" → "Full History CSV"
- **Columns**: `rank, country, points, previous_points, change, highest, lowest`
- The seed `wc_2026_teams.csv` has approximate ELO values — replace with latest for best accuracy

### Current ratings snapshot:
Update the `elo_rating` column in `seeds/wc_2026_teams.csv` with the latest values before running.

---

## 3. StatsBomb Open Data (OPTIONAL — for richer event data)

### Source: BigQuery Public Dataset
```sql
-- Available tables:
SELECT table_id FROM `bigquery-public-data.soccer.__TABLES__`
-- Includes: 2018 World Cup, 2019 Women's WC, 2020 Euros, Premier League, La Liga
```
This has detailed pass/shot/pressure event data but limited tournament coverage.

---

## 4. Betting Odds (OPTIONAL — adds market-implied probability as a feature)

### Source: football-data.co.uk (international tournaments)
- **URL**: https://www.football-data.co.uk/
- Contains historical odds from Bet365, Pinnacle, William Hill
- Useful as a `market_implied_home_win_prob` feature in the ensemble model

---

## 5. Player Statistics (OPTIONAL)

### Source: Transfermarkt / FBref via StatsBomb
- For squad-level features: avg player value, squad age, key player availability
- Can be loaded as additional seeds or external tables

---

## Setup Order

```
1. Run: bigquery_setup/01_create_datasets.sql
2. Download results.csv from Kaggle → upload to GCS
3. Run: bigquery_setup/02_create_historical_results_table.sql
4. Run: dbt deps
5. Run: dbt seed
6. Run: dbt run --select staging intermediate
7. Run: bigquery_setup/04_train_bqml_model.sql  (one-time training)
8. Run: bigquery_setup/03_create_gemini_connection.sql  (for AI narratives)
9. Run: dbt run  (full pipeline)
```
