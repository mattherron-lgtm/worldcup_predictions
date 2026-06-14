{{ config(
    materialized='table',
    tags=['wc_2026']
) }}

-- =============================================================
-- Penalty shootout results for 2026 FIFA World Cup matches.
-- Joins staged shootout data with the 2026 schedule to attach
-- fixture_id for easy cross-referencing with predictions.
--
-- Currently empty until 2026 knockout matches with shootouts occur
-- and Kaggle updates the historical results dataset.
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
),

raw_shootouts as (
    select
        cast(date as date) as match_date,
        home_team,
        away_team,
        winner as winning_team,
        first_shooter
    from {{ source('raw', 'shootouts') }}
    where date is not null
        and home_team is not null
        and away_team is not null
),

joined as (
    select
        {{ dbt_utils.generate_surrogate_key(['s.group_name', 's.home_team', 's.away_team']) }} as fixture_id,
        s.match_number,
        s.group_name,
        s.home_team,
        s.away_team,
        sh.winning_team,
        sh.first_shooter,
        case
            when sh.winning_team = s.home_team then 'home'
            when sh.winning_team = s.away_team then 'away'
            else 'unknown'
        end as shootout_winner_side
    from schedule s
    left join raw_shootouts sh
        on lower(s.home_team) = lower(sh.home_team)
        and lower(s.away_team) = lower(sh.away_team)
        and abs(date_diff(sh.match_date, s.scheduled_date, DAY)) <= 1
)

select * from joined
