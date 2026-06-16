-- =============================================================
-- Compares bookmaker odds accuracy vs model ensemble accuracy.
-- For each completed match, derives the outcome each "predictor"
-- favoured (highest implied probability) and checks it against
-- the actual result.
--
-- Use this to answer: "Are we beating the market?"
-- =============================================================

with match_data as (
    select
        m.match_number,
        m.fixture_id,
        m.group_name,
        m.group_round,
        m.home_team,
        m.away_team,

        -- Model ensemble probabilities
        m.p_home_win,
        m.p_draw,
        m.p_away_win,
        m.ensemble_predicted_result,

        -- Odds probabilities from combined predictions (null if no odds fetched)
        c.odds_p_home_win,
        c.odds_p_draw,
        c.odds_p_away_win,

        -- Actual result
        m.home_goals,
        m.away_goals,
        m.actual_result,

        m.prediction_accurate   as model_accurate

    from {{ ref('mart_match_predictions_vs_actual') }} m
    left join {{ ref('pred_group_stage_combined') }} c using (fixture_id)
),

with_odds_prediction as (
    select
        *,

        -- Derive the outcome the odds favoured most
        case
            when odds_p_home_win is null then null   -- no odds data
            when odds_p_home_win >= odds_p_draw
             and odds_p_home_win >= odds_p_away_win then 'home_win'
            when odds_p_draw >= odds_p_home_win
             and odds_p_draw >= odds_p_away_win      then 'draw'
            else 'away_win'
        end as odds_predicted_result,

        -- Highest probability for each predictor (confidence proxy)
        greatest(p_home_win, p_draw, p_away_win)                  as model_max_prob,
        greatest(
            coalesce(odds_p_home_win, 0),
            coalesce(odds_p_draw, 0),
            coalesce(odds_p_away_win, 0)
        )                                                           as odds_max_prob

    from match_data
),

final as (
    select
        match_number,
        fixture_id,
        group_name,
        group_round,
        home_team,
        away_team,

        -- Actual result
        home_goals,
        away_goals,
        actual_result,

        -- Model prediction
        ensemble_predicted_result   as model_predicted_result,
        p_home_win                  as model_p_home_win,
        p_draw                      as model_p_draw,
        p_away_win                  as model_p_away_win,
        model_max_prob,
        model_accurate,

        -- Odds prediction
        odds_predicted_result,
        odds_p_home_win,
        odds_p_draw,
        odds_p_away_win,
        odds_max_prob,
        case
            when actual_result is null              then 'pending'
            when odds_predicted_result is null      then 'no_odds'
            when odds_predicted_result = actual_result then 'correct'
            else 'incorrect'
        end as odds_accurate,

        -- Head-to-head: did both agree?
        case
            when actual_result is null              then 'pending'
            when odds_predicted_result is null      then 'no_odds'
            when ensemble_predicted_result = actual_result
             and odds_predicted_result     = actual_result then 'both_correct'
            when ensemble_predicted_result = actual_result then 'model_only'
            when odds_predicted_result     = actual_result then 'odds_only'
            else 'both_wrong'
        end as head_to_head

    from with_odds_prediction
)

select * from final
order by match_number
