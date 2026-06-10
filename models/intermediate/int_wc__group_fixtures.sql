-- =============================================================
-- Group stage fixtures sourced from the official FIFA 2026 schedule.
-- Joined with wc_2026_teams to enrich with ELO, confederation, group seed.
-- Includes real kickoff times (UTC + local) and venue.
-- =============================================================

with schedule as (
    select
        `Match Number`    as match_number,
        `Round Number`    as group_round,
        `Date Time - BST` as kickoff_bst_raw,
        `Local Time`      as kickoff_local_raw,
        `Location`        as venue,
        `Home Team`       as home_team,
        `Away Team`       as away_team,
        `Group`           as group_name,
        `Home Goals`      as home_goals,
        `Away Goals`      as away_goals
    from {{ ref('fifa_world_cup_2026_schedule') }}
    -- Group stage only: Group column is populated and teams are confirmed
    where `Group` is not null
      and trim(`Group`) != ''
      and `Home Team` != 'To be announced'
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
        s.group_round,

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

        -- UTC kickoff parsed from DD/MM/YYYY HH:MM format
        parse_datetime('%d/%m/%Y %H:%M', s.kickoff_utc_raw)  as kickoff_utc,

        -- Local kickoff parsed from "YYYY-MM-DD HH:MM (UTC±H)" format
        parse_datetime(
            '%Y-%m-%d %H:%M',
            regexp_extract(s.kickoff_local_raw, r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2})')
        )                               as kickoff_local,

        -- UTC offset hours extracted from e.g. "(UTC-6)"
        cast(
            regexp_extract(s.kickoff_local_raw, r'UTC([+-]\d+)\)')
        as int64)                        as utc_offset_hours,

        s.venue,
        s.home_goals,
        s.away_goals

    from schedule s
    left join teams ht  on ht.team_name  = s.home_team
    left join teams awt on awt.team_name = s.away_team
)

select * from fixtures
order by group_name, group_round, match_number
