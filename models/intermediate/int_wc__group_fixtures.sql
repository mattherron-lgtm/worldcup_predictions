-- =============================================================
-- Group stage fixtures sourced from the official FIFA 2026 schedule.
-- Joined with wc_2026_teams to enrich with ELO, confederation, group seed.
-- Joined with schedule_with_results to include actual match outcomes.
-- Includes real kickoff times (UTC + local) and venue.
-- =============================================================

with schedule_with_results as (
    select
        match_number,
        scheduled_date,
        kickoff_bst_raw,
        kickoff_local_raw,
        group_name,
        home_team,
        away_team,
        home_goals,
        away_goals,
        actual_result,
        venue
    from {{ ref('int_wc__schedule_with_results') }}
    where group_name is not null
),

teams as (
    select
        t.team_name,
        t.group_name,
        t.confederation,
        -- Use static ELO from wc_2026_teams.csv (updated manually each day)
        t.elo_rating,
        row_number() over (
            partition by t.group_name
            order by t.elo_rating desc
        ) as group_seed
    from {{ ref('wc_2026_teams') }} t
),

fixtures as (
    select
        {{ dbt_utils.generate_surrogate_key(['s.group_name', 's.home_team', 's.away_team']) }} as fixture_id,
        s.match_number,
        s.group_name,
        1 as group_round,  -- Hard-coded to 1 since all group stage matches are in the initial round

        s.home_team,
        ht.group_seed             as home_seed,
        ht.elo_rating             as home_elo,
        ht.confederation          as home_confederation,

        s.away_team,
        awt.group_seed            as away_seed,
        awt.elo_rating            as away_elo,
        awt.confederation         as away_confederation,

        ht.elo_rating - awt.elo_rating  as elo_diff,
        case
            when ht.elo_rating - awt.elo_rating >= 100  then s.home_team
            when awt.elo_rating - ht.elo_rating >= 100  then s.away_team
            else 'Evenly matched'
        end                             as pre_match_favourite,

        true                            as is_neutral_venue,

        -- BST kickoff parsed from DD/MM/YYYY HH:MM format
        parse_datetime('%d/%m/%Y %H:%M', s.kickoff_bst_raw)  as kickoff_utc,

        -- Local kickoff parsed from DD/MM/YYYY HH:MM format
        parse_datetime('%d/%m/%Y %H:%M', s.kickoff_local_raw) as kickoff_local,

        -- UTC offset hours: calculate as difference between BST and local time
        cast(
            timestamp_diff(
                parse_datetime('%d/%m/%Y %H:%M', s.kickoff_bst_raw),
                parse_datetime('%d/%m/%Y %H:%M', s.kickoff_local_raw),
                hour
            )
        as int64)                        as utc_offset_hours,

        s.venue,
        s.home_goals,
        s.away_goals,
        s.actual_result

    from schedule_with_results s
    left join teams ht  on ht.team_name  = s.home_team
    left join teams awt on awt.team_name = s.away_team
)

select * from fixtures
order by group_name, group_round, match_number
