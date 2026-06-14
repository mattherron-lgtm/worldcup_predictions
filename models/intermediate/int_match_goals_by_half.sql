{{ config(
    materialized='table',
    tags=['wc_2026']
) }}

-- =============================================================
-- Actual goals broken down by match half.
-- Uses goalscorer event times to count goals in:
--   - First half:  minutes 0-45
--   - Second half: minutes 46+
-- 
-- Currently empty until 2026 matches are played and goalscorer
-- data flows through from Kaggle.
-- =============================================================

with goalscorers as (
    select
        fixture_id,
        goal_for,
        goal_minute
    from {{ ref('int_goalscorers__with_fixture_id') }}
    where fixture_id is not null
),

by_half as (
    select
        fixture_id,
        countif(goal_for = 'home' and goal_minute <= 45) as home_goals_1h,
        countif(goal_for = 'home' and goal_minute > 45) as home_goals_2h,
        countif(goal_for = 'away' and goal_minute <= 45) as away_goals_1h,
        countif(goal_for = 'away' and goal_minute > 45) as away_goals_2h,
        countif(goal_for = 'home') as home_goals_total,
        countif(goal_for = 'away') as away_goals_total,
        countif(goal_for = 'home') + countif(goal_for = 'away') as total_goals
    from goalscorers
    group by fixture_id
)

select
    fixture_id,
    home_goals_1h,
    home_goals_2h,
    away_goals_1h,
    away_goals_2h,
    home_goals_1h + away_goals_1h as goals_1h,
    home_goals_2h + away_goals_2h as goals_2h,
    home_goals_total + away_goals_total as goals_total
from by_half
