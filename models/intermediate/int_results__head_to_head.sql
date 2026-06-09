-- =============================================================
-- Head-to-head records between all pairs of WC 2026 teams.
-- Covers the last 10 years of matches between each pair.
-- Used as a feature in the BQML model.
-- =============================================================

with wc_teams as (
    select team_name from {{ ref('wc_2026_teams') }}
),

matches as (
    select
        match_date,
        home_team,
        away_team,
        home_goals,
        away_goals,
        result,
        tournament_weight
    from {{ ref('stg_results__international_matches') }}
    where match_date >= date_sub(current_date(), interval 10 year)
),

-- All matches between WC teams, from both perspectives
h2h_records as (
    -- From home_team's perspective
    select
        home_team                                        as team,
        away_team                                        as opponent,
        count(*)                                         as h2h_matches,
        sum(case when result = 'home_win' then 1 else 0 end)  as h2h_wins,
        sum(case when result = 'draw'     then 1 else 0 end)  as h2h_draws,
        sum(case when result = 'away_win' then 1 else 0 end)  as h2h_losses,
        avg(home_goals)                                  as h2h_avg_goals_scored,
        avg(away_goals)                                  as h2h_avg_goals_conceded
    from matches
    where home_team in (select team_name from wc_teams)
      and away_team in (select team_name from wc_teams)
    group by home_team, away_team

    union all

    -- From away_team's perspective
    select
        away_team                                        as team,
        home_team                                        as opponent,
        count(*)                                         as h2h_matches,
        sum(case when result = 'away_win' then 1 else 0 end)  as h2h_wins,
        sum(case when result = 'draw'     then 1 else 0 end)  as h2h_draws,
        sum(case when result = 'home_win' then 1 else 0 end)  as h2h_losses,
        avg(away_goals)                                  as h2h_avg_goals_scored,
        avg(home_goals)                                  as h2h_avg_goals_conceded
    from matches
    where home_team in (select team_name from wc_teams)
      and away_team in (select team_name from wc_teams)
    group by away_team, home_team
),

h2h_rates as (
    select
        team,
        opponent,
        h2h_matches,
        h2h_wins,
        h2h_draws,
        h2h_losses,
        safe_divide(h2h_wins,   h2h_matches) as h2h_win_rate,
        safe_divide(h2h_draws,  h2h_matches) as h2h_draw_rate,
        safe_divide(h2h_losses, h2h_matches) as h2h_loss_rate,
        h2h_avg_goals_scored,
        h2h_avg_goals_conceded
    from h2h_records
    where h2h_matches > 0
)

select * from h2h_rates
