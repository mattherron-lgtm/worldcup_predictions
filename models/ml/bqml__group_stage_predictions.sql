-- =============================================================
-- BQML predictions for all 72 group stage fixtures.
-- Requires: bigquery_setup/04_train_bqml_model.sql to have been run.
-- 
-- Output: one row per fixture with predicted probabilities for
-- home_win, draw, away_win from the boosted tree classifier.
-- =============================================================

select
    inputs.fixture_id,
    inputs.group_name,
    inputs.group_round,
    inputs.home_team,
    inputs.away_team,
    inputs.home_elo,
    inputs.away_elo,
    inputs.elo_diff,

    -- BQML predicted class (most likely outcome)
    pred.predicted_result                               as bqml_predicted_result,

    -- Extract per-class probabilities from the predicted_result_probs array
    (
        select p.prob
        from unnest(pred.predicted_result_probs) p
        where p.label = 'home_win'
        limit 1
    )                                                   as bqml_p_home_win,

    (
        select p.prob
        from unnest(pred.predicted_result_probs) p
        where p.label = 'draw'
        limit 1
    )                                                   as bqml_p_draw,

    (
        select p.prob
        from unnest(pred.predicted_result_probs) p
        where p.label = 'away_win'
        limit 1
    )                                                   as bqml_p_away_win

from (
    select *
    from ML.PREDICT(
        MODEL `{{ var('bq_project') }}.{{ var('bq_ml_dataset') }}.match_outcome_model`,
        (
            select
                fixture_id,
                elo_diff,
                home_advantage,
                tournament_weight,
                home_form_pts_pct,
                away_form_pts_pct,
                home_avg_goals_scored,
                away_avg_goals_scored,
                home_avg_goals_conceded,
                away_avg_goals_conceded,
                h2h_home_win_rate,
                h2h_draw_rate
            from {{ ref('bqml__group_stage_prediction_inputs') }}
        )
    )
) pred
inner join {{ ref('bqml__group_stage_prediction_inputs') }} inputs
    using (fixture_id)
