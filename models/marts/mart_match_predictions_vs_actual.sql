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
        match_number,
        home_team,
        away_team,
        home_goals,
        away_goals,
        actual_result
    from {{ ref('int_wc__schedule_with_results') }}
    where group_name is not null
),

goals_by_half as (
    select
        fixture_id,
        goals_1h,
        goals_2h,
        home_goals_1h,
        home_goals_2h,
        away_goals_1h,
        away_goals_2h
    from {{ ref('int_match_goals_by_half') }}
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
        abs(ar.away_goals - f.away_xg) as away_xg_diff,
        
        -- Actual goals by half (when match is played)
        coalesce(gbh.goals_1h, 0) as actual_goals_1h,
        coalesce(gbh.goals_2h, 0) as actual_goals_2h,
        coalesce(gbh.home_goals_1h, 0) as actual_home_goals_1h,
        coalesce(gbh.home_goals_2h, 0) as actual_home_goals_2h,
        coalesce(gbh.away_goals_1h, 0) as actual_away_goals_1h,
        coalesce(gbh.away_goals_2h, 0) as actual_away_goals_2h
        
    from fixtures f
    left join actual_results ar on f.match_number = ar.match_number
    left join goals_by_half gbh on f.fixture_id = gbh.fixture_id
)

select * from comparison
order by match_number
