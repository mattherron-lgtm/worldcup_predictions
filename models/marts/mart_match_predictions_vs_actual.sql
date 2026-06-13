with fixtures as (
    select
        fixture_id,
        group_name,
        group_round,
        match_number,
        home_team,
        away_team,
        p_home_win,
        p_draw,
        p_away_win,
        ensemble_predicted_result,
        home_xg,
        away_xg
    from {{ ref('mart_wc_group_predictions') }}
),

actual_results as (
    select
        `Match Number` as match_number,
        `Home Team` as home_team,
        `Away Team` as away_team,
        cast(`Home Goals` as int64) as home_goals,
        cast(`Away Goals` as int64) as away_goals
    from {{ ref('fifa_world_cup_2026_schedule') }}
    where `Group` is not null
      and `Home Goals` is not null
      and `Home Goals` != ''
),

comparison as (
    select
        f.fixture_id,
        f.group_name,
        f.group_round,
        f.match_number,
        f.home_team,
        f.away_team,
        
        -- Predicted probabilities and result
        f.p_home_win,
        f.p_draw,
        f.p_away_win,
        f.ensemble_predicted_result,
        f.home_xg,
        f.away_xg,
        
        -- Actual result
        ar.home_goals,
        ar.away_goals,
        case
            when ar.home_goals > ar.away_goals then 'home_win'
            when ar.home_goals = ar.away_goals then 'draw'
            else 'away_win'
        end as actual_result,
        
        -- Accuracy
        case
            when ar.home_goals is null then 'pending'
            when f.ensemble_predicted_result = case
                    when ar.home_goals > ar.away_goals then 'home_win'
                    when ar.home_goals = ar.away_goals then 'draw'
                    else 'away_win'
                end
            then 'correct'
            else 'incorrect'
        end as prediction_accurate,
        
        -- Get the probability of the actual outcome
        case
            when ar.home_goals > ar.away_goals then f.p_home_win
            when ar.home_goals = ar.away_goals then f.p_draw
            else f.p_away_win
        end as actual_outcome_probability,
        
        -- Score difference (actual vs xG)
        abs(ar.home_goals - f.home_xg) as home_xg_diff,
        abs(ar.away_goals - f.away_xg) as away_xg_diff
        
    from fixtures f
    left join actual_results ar on f.match_number = ar.match_number
)

select * from comparison
order by match_number
