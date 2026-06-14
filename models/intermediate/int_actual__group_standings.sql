-- =============================================================
-- Actual group stage standings calculated from match results.
-- Automatically joins schedule with historical results from results.csv
-- Re-calculates each time dbt runs as new results are available.
-- =============================================================

with matches as (
    select
        match_number,
        group_name,
        home_team,
        away_team,
        home_goals,
        away_goals
    from {{ ref('int_wc__schedule_with_results') }}
    where group_name is not null
      and home_goals is not null
),

-- Calculate points and goal metrics
results as (
    select
        group_name,
        home_team as team,
        away_team as opponent,
        home_goals as goals_for,
        away_goals as goals_against,
        case
            when home_goals > away_goals then 3
            when home_goals = away_goals then 1
            else 0
        end as points
    from matches
    
    union all
    
    select
        group_name,
        away_team as team,
        home_team as opponent,
        away_goals as goals_for,
        home_goals as goals_against,
        case
            when away_goals > home_goals then 3
            when away_goals = home_goals then 1
            else 0
        end as points
    from matches
),

-- Aggregate by team and group
standings as (
    select
        group_name,
        team,
        count(*) as matches_played,
        sum(points) as total_pts,
        sum(goals_for) as total_gf,
        sum(goals_against) as total_ga,
        sum(goals_for) - sum(goals_against) as total_gd,
        row_number() over (partition by group_name order by sum(points) desc, sum(goals_for) - sum(goals_against) desc, sum(goals_for) desc) as position
    from results
    group by group_name, team
)

select
    group_name,
    team,
    matches_played,
    total_pts,
    total_gf,
    total_ga,
    total_gd,
    position,
    case when position <= 2 then true else false end as qualified_direct
from standings
order by group_name, position
