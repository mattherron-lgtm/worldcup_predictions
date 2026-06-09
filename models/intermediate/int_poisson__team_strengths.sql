-- =============================================================
-- Poisson model parameters: team attack and defense strength indices.
-- 
-- Method (Dixon-Coles variant with temporal decay + opponent quality weighting):
--   attack_index  = team_avg_goals_scored   / league_avg_goals_scored
--   defense_index = team_avg_goals_conceded / league_avg_goals_conceded
--
-- Expected goals for match A vs B:
--   xg_a = attack_index_A × defense_index_B × overall_avg_goals
--   xg_b = attack_index_B × defense_index_A × overall_avg_goals
--
-- Combined weight per match = time_decay × tournament_weight × opponent_quality
--   time_decay:        exp(-0.03 * months_ago)  — half-life ~23 months
--   tournament_weight: 3.0 (WC) → 0.5 (friendly)
--   opponent_quality:  least(1.0, opponent_elo / 1800)
--                      e.g. France (2020 ELO) → 1.00x
--                           Morocco (1824 ELO) → 1.00x
--                           Tanzania (1580 ELO) → 0.88x
--                           Burundi  (1380 ELO) → 0.77x
--                      This means beating Burundi 5-0 barely moves the needle,
--                      while beating France 1-0 counts fully.
-- =============================================================

with wc_teams as (
    select team_name from {{ ref('wc_2026_teams') }}
),

-- ELO ratings for all teams (WC + non-WC) to weight opponent quality
elo_ratings as (
    select team_name, elo_rating from {{ ref('wc_2026_teams') }}
    union all
    select team_name, elo_rating
    from {{ ref('int_elo__team_ratings') }}
    where team_name not in (select team_name from {{ ref('wc_2026_teams') }})
),

-- All results in the last 5 years involving WC teams, with combined weight
relevant_matches as (
    select
        m.home_team,
        m.away_team,
        m.home_goals,
        m.away_goals,
        m.tournament_weight,
        date_diff(current_date(), m.match_date, month)  as months_ago,
        exp(-0.03 * date_diff(current_date(), m.match_date, month)) as time_decay,

        -- Opponent quality weight: scales 0.77–1.0 based on opponent ELO.
        -- Caps at 1.0 so elite opponents don't over-inflate.
        -- Falls back to 1.0 if ELO is unknown (don't penalise missing data).
        least(1.0, coalesce(a_elo.elo_rating, 1800) / 1800.0) as home_opp_quality,
        least(1.0, coalesce(h_elo.elo_rating, 1800) / 1800.0) as away_opp_quality,

        -- Home team combined weight: time × tournament × away team quality
        exp(-0.03 * date_diff(current_date(), m.match_date, month))
            * m.tournament_weight
            * least(1.0, coalesce(a_elo.elo_rating, 1800) / 1800.0) as home_combined_weight,

        -- Away team combined weight: time × tournament × home team quality
        exp(-0.03 * date_diff(current_date(), m.match_date, month))
            * m.tournament_weight
            * least(1.0, coalesce(h_elo.elo_rating, 1800) / 1800.0) as away_combined_weight,

        -- Shared weight used for global average (average of both sides)
        exp(-0.03 * date_diff(current_date(), m.match_date, month))
            * m.tournament_weight
            * (
                least(1.0, coalesce(a_elo.elo_rating, 1800) / 1800.0)
                + least(1.0, coalesce(h_elo.elo_rating, 1800) / 1800.0)
              ) / 2.0                                                 as combined_weight

    from {{ ref('stg_results__international_matches') }} m
    left join elo_ratings h_elo on m.home_team = h_elo.team_name
    left join elo_ratings a_elo on m.away_team = a_elo.team_name
    where m.match_date >= date_sub(current_date(), interval 60 month)
      and (
          m.home_team in (select team_name from wc_teams)
          or m.away_team in (select team_name from wc_teams)
      )
),

-- Global weighted average goals per game (baseline rate)
global_avg as (
    select
        sum((home_goals + away_goals) / 2.0 * combined_weight)
            / sum(combined_weight)   as avg_goals_per_team_per_game,
        sum(home_goals * combined_weight) / sum(combined_weight) as avg_home_goals,
        sum(away_goals * combined_weight) / sum(combined_weight) as avg_away_goals
    from relevant_matches
),

-- Per-team weighted stats from both perspectives
-- Use asymmetric weights: home team's stats weighted by the away team's ELO quality
-- (and vice versa), so goals against weak opponents count for less
team_stats as (
    select
        home_team                                            as team,
        safe_divide(sum(home_goals * home_combined_weight), sum(home_combined_weight)) as avg_scored,
        safe_divide(sum(away_goals * home_combined_weight), sum(home_combined_weight)) as avg_conceded,
        sum(home_combined_weight)                            as effective_matches
    from relevant_matches
    group by home_team

    union all

    select
        away_team                                            as team,
        safe_divide(sum(away_goals * away_combined_weight), sum(away_combined_weight)) as avg_scored,
        safe_divide(sum(home_goals * away_combined_weight), sum(away_combined_weight)) as avg_conceded,
        sum(away_combined_weight)                            as effective_matches
    from relevant_matches
    group by away_team
),

team_aggregated as (
    select
        team,
        safe_divide(
            sum(avg_scored   * effective_matches),
            sum(effective_matches)
        )                                               as avg_goals_scored,
        safe_divide(
            sum(avg_conceded * effective_matches),
            sum(effective_matches)
        )                                               as avg_goals_conceded,
        sum(effective_matches)                          as total_matches
    from team_stats
    group by team
),

strengths as (
    select
        t.team,
        t.avg_goals_scored,
        t.avg_goals_conceded,
        t.total_matches,
        g.avg_goals_per_team_per_game                as league_avg_goals,

        -- Attack index: >1.0 = above-average attack
        safe_divide(t.avg_goals_scored,   g.avg_goals_per_team_per_game)  as attack_index,

        -- Defense index: <1.0 = strong defense (fewer goals conceded relative to avg)
        safe_divide(t.avg_goals_conceded, g.avg_goals_per_team_per_game)  as defense_index

    from team_aggregated t
    cross join global_avg g
    where t.total_matches >= 1  -- at least some weighted signal
)

select
    s.team,
    s.avg_goals_scored,
    s.avg_goals_conceded,
    s.total_matches,
    s.league_avg_goals,
    s.attack_index,
    s.defense_index,

    -- Final attack/defense values (fall back to 1.0 = league average if no historical data)
    coalesce(s.attack_index,  1.0)  as final_attack_index,
    coalesce(s.defense_index, 1.0)  as final_defense_index

from {{ ref('wc_2026_teams') }} wct
left join strengths s on wct.team_name = s.team
cross join (select avg_goals_per_team_per_game from global_avg) league
