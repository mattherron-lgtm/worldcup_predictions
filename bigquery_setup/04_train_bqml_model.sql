-- =============================================================
-- 04: Train BigQuery ML model for match outcome prediction
-- Run AFTER: dbt run --select staging intermediate ml
-- This creates the model in the worldcup_ml dataset
-- =============================================================

-- Option A: Boosted Tree Classifier (recommended — handles categorical teams well)
CREATE OR REPLACE MODEL `analytics-project-production.worldcup_ml.match_outcome_model`
OPTIONS (
    model_type          = 'BOOSTED_TREE_CLASSIFIER',
    input_label_cols    = ['result'],
    num_parallel_tree   = 6,
    max_iterations      = 100,
    learn_rate          = 0.1,
    max_tree_depth      = 6,
    l1_reg              = 0.1,
    l2_reg              = 0.1,
    data_split_method   = 'AUTO_SPLIT',
    enable_global_explain = TRUE
) AS
SELECT
    -- Match context
    elo_diff,
    home_advantage,
    tournament_weight,
    -- Team form features
    home_form_pts_pct,
    away_form_pts_pct,
    home_avg_goals_scored,
    away_avg_goals_scored,
    home_avg_goals_conceded,
    away_avg_goals_conceded,
    -- Head-to-head
    h2h_home_win_rate,
    h2h_draw_rate,
    -- Label
    result
FROM `analytics-project-production.worldcup_dev_wc_ml.int_ml__match_training_features`
WHERE match_date BETWEEN '2010-01-01' AND '2022-10-31'  -- Leave 2022 WC for validation
  AND result IS NOT NULL;


-- Option B: Logistic Regression (faster to train, good baseline)
CREATE OR REPLACE MODEL `analytics-project-production.worldcup_ml.match_outcome_logistic`
OPTIONS (
    model_type          = 'LOGISTIC_REG',
    input_label_cols    = ['result'],
    max_iterations      = 50,
    l1_reg              = 0.01,
    l2_reg              = 0.01,
    data_split_method   = 'AUTO_SPLIT'
) AS
SELECT
    elo_diff,
    home_advantage,
    tournament_weight,
    home_form_pts_pct,
    away_form_pts_pct,
    home_avg_goals_scored,
    away_avg_goals_scored,
    home_avg_goals_conceded,
    away_avg_goals_conceded,
    result
FROM `analytics-project-production.worldcup_dev_wc_ml.int_ml__match_training_features`
WHERE match_date BETWEEN '2010-01-01' AND '2022-10-31'
  AND result IS NOT NULL;


-- Evaluate model performance on 2022 WC held-out set
SELECT *
FROM ML.EVALUATE(
    MODEL `analytics-project-production.worldcup_ml.match_outcome_model`,
    (
        SELECT
            elo_diff, home_advantage, tournament_weight,
            home_form_pts_pct, away_form_pts_pct,
            home_avg_goals_scored, away_avg_goals_scored,
            home_avg_goals_conceded, away_avg_goals_conceded,
            h2h_home_win_rate, h2h_draw_rate,
            result
        FROM `analytics-project-production.worldcup_dev_wc_ml.int_ml__match_training_features`
        WHERE match_date >= '2022-11-01'
    )
);

-- Feature importance
SELECT *
FROM ML.GLOBAL_EXPLAIN(MODEL `analytics-project-production.worldcup_ml.match_outcome_model`)
ORDER BY attribution DESC;
