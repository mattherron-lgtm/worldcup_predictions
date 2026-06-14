{{ config(
    materialized='view',
    tags=['wc_2026']
) }}

with schedule as (
    select
        `Match Number` as match_number,
        cast(parse_datetime('%d/%m/%Y %H:%M', `Date Time - BST`) as date) as scheduled_date,
        `Date Time - BST` as kickoff_bst_raw,
        `Local Time` as kickoff_local_raw,
        `Home Team` as home_team,
        `Away Team` as away_team,
        `Group` as group_name,
        Location as venue
    from {{ ref('fifa_world_cup_2026_schedule') }}
),

-- Read directly from staging table with all 2026 FIFA World Cup results  
results as (
    select
        date as result_date,
        home_team,
        away_team,
        safe_cast(home_score as int64) as home_goals,
        safe_cast(away_score as int64) as away_goals,
        tournament,
        case
            when safe_cast(home_score as int64) > safe_cast(away_score as int64) then 'home_win'
            when safe_cast(home_score as int64) = safe_cast(away_score as int64) then 'draw'
            else 'away_win'
        end as result
    from `analytics-project-production.ML_WC_2026.staging_historical_results_kaggle`
    where tournament = 'FIFA World Cup'
        and date >= '2026-06-01'  -- Only 2026 World Cup matches
),

joined as (
    select
        s.match_number,
        s.scheduled_date,
        s.kickoff_bst_raw,
        s.kickoff_local_raw,
        s.home_team,
        s.away_team,
        s.group_name,
        s.venue,
        r.result_date,
        r.home_goals,
        r.away_goals,
        r.result as actual_result
    from schedule s
    left join results r
        on lower(s.home_team) = lower(r.home_team)
        and lower(s.away_team) = lower(r.away_team)
        and abs(date_diff(cast(r.result_date as date), s.scheduled_date, DAY)) <= 1  -- Allow 1 day difference for timezone
)

select * from joined
