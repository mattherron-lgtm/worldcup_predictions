# World Cup 2026 Predictions — dbt Pipeline

A data science pipeline for predicting the 2026 FIFA World Cup (USA / Canada / Mexico, June 11–August 2, 2026) using a multi-model ensemble: Poisson expected-goals model + BigQuery ML boosted tree classifier + Gemini AI narrative generation.

---

## Architecture

```
Historical Results (Kaggle CSV)
        │
        ▼
┌──────────────────┐
│  staging/        │  Clean & type-cast raw data
│  stg_results     │  Derive result, tournament_weight, recency
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────┐
│  intermediate/                           │
│  ├── int_wc__group_fixtures              │  Auto-generate 72 group games from seed
│  ├── int_results__team_recent_form       │  Rolling form metrics (last 10 matches)
│  ├── int_results__head_to_head          │  H2H records (last 10 years)
│  ├── int_poisson__team_strengths        │  Attack/defense indices
│  └── int_ml__match_training_features   │  Point-in-time ML feature set
└────────┬──────────────────────┬──────────┘
         │                      │
         ▼                      ▼
┌────────────────┐    ┌──────────────────────┐
│  BQML Model   │    │  Poisson Model        │
│  (boosted     │    │  Score matrix (0-5    │
│   tree, BQ)   │    │  goals per team)      │
└───────┬────────┘    └──────────┬───────────┘
        └──────────┬─────────────┘
                   ▼
         ┌──────────────────┐
         │  Ensemble (60/40)│  BQML + Poisson blend
         │  pred_combined   │  Falls back to Poisson only
         └────────┬─────────┘
                  │
          ┌───────┼────────────┐
          ▼       ▼            ▼
┌──────────────┐ ┌──────────┐ ┌───────────────────────┐
│ Monte Carlo  │ │ Knockout │ │ Tournament winner      │
│ Group Stage  │ │ Bracket  │ │ probability (chain     │
│ Standings    │ │ Simulator│ │ rule, Elo-based)       │
└──────┬───────┘ └─────┬────┘ └──────────┬────────────┘
       └───────┬────────┘                │
               ▼                         ▼
    ┌────────────────────┐    ┌────────────────────────┐
    │  mart_wc_bracket   │    │  mart_wc_group_preds   │
    │  mart_wc_narratives│    │  (dashboard table)     │
    │  (Gemini AI text)  │    └────────────────────────┘
    └────────────────────┘
```

---

## Quick Start

### 1. Set up BigQuery datasets
```bash
# Run in BigQuery console or bq CLI
bq query --use_legacy_sql=false < bigquery_setup/01_create_datasets.sql
```

### 2. Load historical match data
See `bigquery_setup/data_sources_guide.md` for download instructions.

```bash
# Download results.csv from https://www.kaggle.com/datasets/martj42/international-football-results-from-1872-to-2017
# Upload to GCS, then:
bq load --autodetect --source_format=CSV \
  analytics-project-production:worldcup_raw.historical_match_results \
  gs://YOUR_BUCKET/worldcup/historical_results/results.csv
```

### 3. Update team data (important!)
Before running, verify the groups in `seeds/wc_2026_teams.csv` against the [official FIFA draw](https://www.fifa.com/fifaplus/en/tournaments/mens/worldcup/canadamexicousa2026).
Also update ELO ratings from [eloratings.net](https://www.eloratings.net/).

### 4. Install dbt deps and run staging
```bash
cd /Users/mattherron/Documents/worldcup_predictions
cp profiles.yml ~/.dbt/profiles.yml  # or append to existing

dbt deps
dbt seed
dbt run --select staging intermediate
```

### 5. Train the BQML model (one-time)
```bash
# Run in BigQuery console — takes ~5 minutes
bq query --use_legacy_sql=false < bigquery_setup/04_train_bqml_model.sql
```

### 6. Run the full pipeline
```bash
dbt run
# For Poisson-only (no BQML required):
dbt run --exclude bqml__group_stage_predictions mart_wc_match_narratives
```

### 7. Set up Gemini narratives (optional)
```bash
bq query --use_legacy_sql=false < bigquery_setup/03_create_gemini_connection.sql
dbt run --select mart_wc_match_narratives
```

---

## Model Layers

| Layer | Dataset suffix | Materialization | Description |
|-------|---------------|-----------------|-------------|
| staging | `wc_staging` | view | Clean raw data |
| intermediate | `wc_intermediate` | view | Feature engineering |
| ml | `wc_ml` | view | BQML input/output tables |
| predictions | `wc_predictions` | table | Poisson + ensemble outputs |
| marts | `wc_marts` | table | Dashboard-ready outputs |
| seeds | `wc_seeds` | table | 48 teams + metadata |

---

## Key Output Tables

| Table | Rows | Description |
|-------|------|-------------|
| `mart_wc_group_predictions` | 72 | All group stage match predictions with probabilities |
| `mart_wc_bracket` | 48 | Each team's probability of reaching each stage |
| `mart_wc_match_narratives` | 72 | Match predictions + Gemini AI pre-match analysis |
| `pred_group_stage_standings` | 48 | Simulated group standings (N=200 Monte Carlo runs) |
| `pred_tournament_winner` | 48 | Tournament winner probabilities (ranked) |

---

## Prediction Models

### 1. Poisson Expected Goals Model
- Computes attack/defense strength indices per team from 3-year rolling stats
- Builds a 6×6 score probability matrix (0–5 goals per team)
- Sums matrix to get P(home_win), P(draw), P(away_win)
- No training required — runs from historical averages in seeds

### 2. BigQuery ML — Boosted Tree Classifier
- Features: ELO diff, form %, H2H win rate, avg goals scored/conceded
- Trained on 2010–2022 international matches (WC + major tournaments)
- 2022 World Cup held out for validation
- Run `bigquery_setup/04_train_bqml_model.sql` once to train

### 3. Ensemble
- 60% BQML + 40% Poisson (configurable in the model)
- Falls back to Poisson-only if BQML not yet trained

### 4. Monte Carlo Group Stage Simulation
- 200 simulations of the group stage (configurable via `n_simulations` var)
- Samples match outcomes from ensemble probability distribution
- Approximates Poisson random variates for scorelines
- Outputs P(finish 1st/2nd/3rd/4th) and P(advance) per team

### 5. Gemini AI Narratives
- Calls Gemini 1.5 Flash via BigQuery ML `ML.GENERATE_TEXT()`
- Generates a 150-word match preview per fixture
- Includes: form context, predicted scoreline, tactical insight, upset potential

---

## Configuration

Adjust `vars` in `dbt_project.yml`:

```yaml
vars:
  bq_project: "your-gcp-project-id"       # Your BigQuery project
  bq_ml_dataset: "worldcup_ml"             # Where BQML models are stored
  n_simulations: 200                        # Monte Carlo simulation count
  form_lookback_months: 36                  # Historical form window
```

---

## Data Sources

| Source | Required? | URL |
|--------|-----------|-----|
| International results (Kaggle) | Yes | https://kaggle.com/datasets/martj42/international-football-results-from-1872-to-2017 |
| ELO ratings | Recommended | https://eloratings.net |
| BigQuery StatsBomb data | Optional | `bigquery-public-data.soccer` |
| Betting odds | Optional | https://football-data.co.uk |

---

## Accuracy Notes

- ELO ratings in `seeds/wc_2026_teams.csv` are **approximate** — update before running
- Group assignments in the seed may need correcting against the official FIFA draw
- The knockout bracket seeding (`pred_knockout_simulator`) uses a simplified bracket structure — adjust match IDs to match the official 2026 bracket once confirmed
- Point-in-time form in the training features is approximated (12-month window) which slightly overestimates training accuracy
