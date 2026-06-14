{{ config(
    materialized='table',
    tags=['wc_2026']
) }}

-- =============================================================
-- Match goalscorers for 2026 FIFA World Cup group stage.
-- Aggregates all goalscorer events per match with context
-- for display in Match Previews and narratives.
--
-- Empty until 2026 matches are played and Kaggle dataset updates.
-- =============================================================

with goalscorers_raw as (
    select
        fixture_id,
        match_number,
        group_name,
        home_team,
        away_team,
        scorer,
        goal_minute,
        goal_for,
        is_own_goal,
        is_penalty
    from {{ ref('int_goalscorers__with_fixture_id') }}
    where fixture_id is not null
),

-- Aggregate goalscorers per match for summary display
scorers_by_match as (
    select
        fixture_id,
        match_number,
        group_name,
        home_team,
        away_team,
        string_agg(
            distinct case
                when goal_for = 'home' then scorer
            end,
            ', '
            order by case
                when goal_for = 'home' then scorer
            end
        ) as home_scorers,
        string_agg(
            distinct case
                when goal_for = 'away' then scorer
            end,
            ', '
            order by case
                when goal_for = 'away' then scorer
            end
        ) as away_scorers,
        count(*) as total_goals,
        countif(goal_for = 'home') as home_goals_count,
        countif(goal_for = 'away') as away_goals_count,
        countif(is_penalty) as total_penalties
    from goalscorers_raw
    group by fixture_id, match_number, group_name, home_team, away_team
)

select
    s.fixture_id,
    s.match_number,
    s.group_name,
    s.home_team,
    s.away_team,
    s.home_scorers,
    s.away_scorers,
    s.total_goals,
    s.home_goals_count,
    s.away_goals_count,
    s.total_penalties
from scorers_by_match s
order by s.match_number
