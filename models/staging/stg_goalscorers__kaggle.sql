{{ config(
    materialized='table',
    tags=['kaggle']
) }}

-- =============================================================
-- Staging model for raw goalscorer data from Kaggle.
-- Cleans and normalizes goal scorer events including penalties
-- and own goals.
-- 
-- Source: kagglehub/martj42/international-football-results-from-1872-to-2017
--         staging_goalscorers_kaggle table
-- =============================================================

with source as (
    select * from {{ source('kaggle_staging', 'goalscorers') }}
)

select
    cast(date as date) as match_date,
    home_team,
    away_team,
    team as scoring_team,
    scorer,
    safe_cast(
        case 
            when cast(minute as string) like '%+%' then cast(substring(cast(minute as string), 1, 2) as int64) + 45
            else safe_cast(minute as int64)
        end as int64
    ) as goal_minute,
    coalesce(own_goal, false) as is_own_goal,
    coalesce(penalty, false) as is_penalty
from source
where date is not null
    and home_team is not null
    and away_team is not null
order by match_date, goal_minute
