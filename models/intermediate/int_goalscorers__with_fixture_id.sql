{{ config(
    materialized='table',
    tags=['wc_2026']
) }}

-- =============================================================
-- Goalscorer events for 2026 FIFA World Cup matches with fixture IDs.
-- Joins staged goalscorer data with the 2026 schedule to attach
-- fixture_id for easy cross-referencing with predictions.
-- 
-- Currently empty until 2026 matches are played and Kaggle updates
-- the historical results dataset.
-- =============================================================

with schedule as (
    select
        match_number,
        scheduled_date,
        home_team,
        away_team,
        group_name,
        venue
    from {{ ref('int_wc__schedule_with_results') }}
    where group_name is not null
),

goalscorers as (
    select
        match_date,
        home_team,
        away_team,
        scoring_team,
        scorer,
        goal_minute,
        is_own_goal,
        is_penalty
    from {{ ref('stg_goalscorers__kaggle') }}
),

joined as (
    select
        {{ dbt_utils.generate_surrogate_key(['s.group_name', 's.home_team', 's.away_team']) }} as fixture_id,
        s.match_number,
        s.group_name,
        s.home_team,
        s.away_team,
        g.scoring_team,
        g.scorer,
        g.goal_minute,
        g.is_own_goal,
        g.is_penalty,
        case
            when g.scoring_team = s.home_team then 'home'
            when g.scoring_team = s.away_team then 'away'
            else 'unknown'
        end as goal_for
    from schedule s
    left join goalscorers g
        on lower(s.home_team) = lower(g.home_team)
        and lower(s.away_team) = lower(g.away_team)
        and abs(date_diff(g.match_date, s.scheduled_date, DAY)) <= 1
)

select * from joined
order by fixture_id, goal_minute
