-- =============================================================
-- Ensemble model: blend Poisson, BQML, and bookmaker odds.
-- 
-- Weights when all three signals present:
--   Poisson:  25% — physics-based, good for goal totals
--   BQML:     40% — learns from historical patterns
--   Odds:     35% — market consensus (reflects all public information)
--
-- When odds unavailable: Poisson 40% / BQML 60%
-- When BQML unavailable: Poisson 100% (fallback)
-- =============================================================

with poisson as (
    select * from {{ ref('pred_group_stage_poisson') }}
),

bqml as (
    select * from {{ ref('bqml__group_stage_predictions') }}
),

inputs as (
    select * from {{ ref('bqml__group_stage_prediction_inputs') }}
),

-- Odds joined by matching team names — null rows = no odds available yet
odds as (
    select
        home_team,
        away_team,
        implied_p_home  as odds_p_home_win,
        implied_p_draw  as odds_p_draw,
        implied_p_away  as odds_p_away_win,
        bookmaker_count,
        fetched_at      as odds_fetched_at
    from {{ ref('stg_odds__bookmaker_consensus') }}
),

blended as (
    select
        p.fixture_id,
        p.group_name,
        p.group_round,
        p.home_team,
        p.away_team,
        p.elo_diff,
        p.home_xg,
        p.away_xg,

        -- Poisson predictions
        p.poisson_p_home_win,
        p.poisson_p_draw,
        p.poisson_p_away_win,
        p.poisson_predicted_result,

        -- BQML predictions
        b.bqml_p_home_win,
        b.bqml_p_draw,
        b.bqml_p_away_win,
        b.bqml_predicted_result,

        -- Bookmaker consensus (null if not yet fetched)
        o.odds_p_home_win,
        o.odds_p_draw,
        o.odds_p_away_win,
        o.bookmaker_count,
        o.odds_fetched_at,

        -- Ensemble — three tiers of signal availability
        case
            -- All three signals: Poisson 25% + BQML 40% + Odds 35%
            when b.bqml_p_home_win is not null and o.odds_p_home_win is not null
            then round(
                    0.25 * p.poisson_p_home_win
                  + 0.40 * b.bqml_p_home_win
                  + 0.35 * o.odds_p_home_win, 4)
            -- No odds: Poisson 40% + BQML 60%
            when b.bqml_p_home_win is not null
            then round(0.4 * p.poisson_p_home_win + 0.6 * b.bqml_p_home_win, 4)
            -- Fallback: Poisson only
            else p.poisson_p_home_win
        end                                         as ensemble_p_home_win,

        case
            when b.bqml_p_draw is not null and o.odds_p_draw is not null
            then round(
                    0.25 * p.poisson_p_draw
                  + 0.40 * b.bqml_p_draw
                  + 0.35 * o.odds_p_draw, 4)
            when b.bqml_p_draw is not null
            then round(0.4 * p.poisson_p_draw + 0.6 * b.bqml_p_draw, 4)
            else p.poisson_p_draw
        end                                         as ensemble_p_draw,

        case
            when b.bqml_p_away_win is not null and o.odds_p_away_win is not null
            then round(
                    0.25 * p.poisson_p_away_win
                  + 0.40 * b.bqml_p_away_win
                  + 0.35 * o.odds_p_away_win, 4)
            when b.bqml_p_away_win is not null
            then round(0.4 * p.poisson_p_away_win + 0.6 * b.bqml_p_away_win, 4)
            else p.poisson_p_away_win
        end                                         as ensemble_p_away_win,

        i.home_form_pts_pct,
        i.away_form_pts_pct,
        i.h2h_home_win_rate,
        i.h2h_draw_rate

    from poisson p
    left join bqml   b using (fixture_id)
    left join inputs i using (fixture_id)
    left join odds   o on p.home_team = o.home_team and p.away_team = o.away_team
),

-- Final normalisation to ensure ensemble probs sum to 1.0
normalised as (
    select
        *,
        ensemble_p_home_win + ensemble_p_draw + ensemble_p_away_win as prob_sum
    from blended
)

select
    fixture_id,
    group_name,
    group_round,
    home_team,
    away_team,
    elo_diff,
    home_xg,
    away_xg,
    home_form_pts_pct,
    away_form_pts_pct,
    h2h_home_win_rate,

    -- Normalised ensemble probabilities
    round(safe_divide(ensemble_p_home_win, prob_sum), 4)    as p_home_win,
    round(safe_divide(ensemble_p_draw,     prob_sum), 4)    as p_draw,
    round(safe_divide(ensemble_p_away_win, prob_sum), 4)    as p_away_win,

    -- Component model predictions for transparency
    poisson_p_home_win,
    poisson_p_draw,
    poisson_p_away_win,
    poisson_predicted_result,
    bqml_p_home_win,
    bqml_p_draw,
    bqml_p_away_win,
    bqml_predicted_result,
    odds_p_home_win,
    odds_p_draw,
    odds_p_away_win,
    bookmaker_count,
    odds_fetched_at,

    -- Ensemble most likely outcome
    case
        when safe_divide(ensemble_p_home_win, prob_sum) >=
             safe_divide(ensemble_p_draw, prob_sum)
         and safe_divide(ensemble_p_home_win, prob_sum) >=
             safe_divide(ensemble_p_away_win, prob_sum)
        then 'home_win'
        when safe_divide(ensemble_p_draw, prob_sum) >=
             safe_divide(ensemble_p_away_win, prob_sum)
        then 'draw'
        else 'away_win'
    end                                                     as ensemble_predicted_result,

    -- Implied odds (1 / probability) for comparison with bookmakers
    round(safe_divide(1.0, safe_divide(ensemble_p_home_win, prob_sum)), 2) as implied_odds_home,
    round(safe_divide(1.0, safe_divide(ensemble_p_draw,     prob_sum)), 2) as implied_odds_draw,
    round(safe_divide(1.0, safe_divide(ensemble_p_away_win, prob_sum)), 2) as implied_odds_away

from normalised
