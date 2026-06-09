-- =============================================================
-- 02: Create external table for historical international match results
-- Prerequisite: Upload results.csv to GCS first (see data_sources_guide.md)
-- =============================================================

-- Replace YOUR_BUCKET with your GCS bucket name
CREATE OR REPLACE EXTERNAL TABLE `analytics-project-production.worldcup_raw.historical_match_results`
OPTIONS (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://YOUR_BUCKET/worldcup/historical_results/results.csv']
) AS (
    SELECT
        CAST(date AS DATE)           AS match_date,
        home_team                    AS home_team,
        away_team                    AS away_team,
        CAST(home_score AS INT64)    AS home_score,
        CAST(away_score AS INT64)    AS away_score,
        tournament                   AS tournament,
        city                         AS city,
        country                      AS host_country,
        CAST(neutral AS BOOL)        AS is_neutral_venue
    FROM EXTERNAL_QUERY(...)
);

-- Simpler alternative: load directly from CSV via BigQuery UI or bq load command
-- bq load \
--   --autodetect \
--   --source_format=CSV \
--   --skip_leading_rows=1 \
--   analytics-project-production:worldcup_raw.historical_match_results \
--   gs://YOUR_BUCKET/worldcup/historical_results/results.csv

-- Validate load:
SELECT
    COUNT(*)            AS total_matches,
    MIN(match_date)     AS earliest_match,
    MAX(match_date)     AS latest_match,
    COUNT(DISTINCT home_team) AS unique_teams
FROM `analytics-project-production.worldcup_raw.historical_match_results`;
