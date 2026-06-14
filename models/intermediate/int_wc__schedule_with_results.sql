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

results as (
    select
        match_date as result_date,
        home_team,
        away_team,
        home_goals,
        away_goals,
        tournament,
        result
    from {{ ref('stg_results__international_matches') }}
    where tournament = 'FIFA World Cup'
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
        and abs(date_diff(s.scheduled_date, r.result_date, day)) <= 1  -- Allow 1 day difference for timezone
)

select * from joined
