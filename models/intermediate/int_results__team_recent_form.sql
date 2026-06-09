-- =============================================================
-- Team recent form metrics — computed from historical match results.
-- Produces one row per team with rolling stats over the last N months.
-- Used as features in both Poisson model and BQML model.
-- =============================================================

with all_team_match_stats as (
    -- Home perspective
    select
        match_date,
        home_team                                as team,
        away_team                                as opponent,
        home_goals                               as goals_scored,
        away_goals                               as goals_conceded,
        home_goals - away_goals                  as goal_diff,
        case when result = 'home_win' then 3
             when result = 'draw'     then 1
             else                          0
        end                                      as points,
        tournament_weight,
        is_neutral_venue
    from {{ ref('stg_results__international_matches') }}

    union all

    -- Away perspective
    select
        match_date,
        away_team                                as team,
        home_team                                as opponent,
        away_goals                               as goals_scored,
        home_goals                               as goals_conceded,
        away_goals - home_goals                  as goal_diff,
        case when result = 'away_win' then 3
             when result = 'draw'     then 1
             else                          0
        end                                      as points,
        tournament_weight,
        is_neutral_venue
    from {{ ref('stg_results__international_matches') }}
),

recent_matches as (
    select
        *,
        row_number() over (
            partition by team
            order by match_date desc
        )                                        as recency_rank
    from all_team_match_stats
    where match_date >= date_sub(current_date(), interval {{ var('form_lookback_months') }} month)
),

-- Last 10 matches stats (primary form window)
last_10 as (
    select
        team,
        count(*)                                          as matches_played,
        sum(points)                                       as total_points,
        safe_divide(sum(points), count(*) * 3.0)          as form_pts_pct,
        avg(goals_scored)                                 as avg_goals_scored,
        avg(goals_conceded)                               as avg_goals_conceded,
        avg(goal_diff)                                    as avg_goal_diff,
        sum(case when points = 3 then 1 else 0 end)       as wins,
        sum(case when points = 1 then 1 else 0 end)       as draws,
        sum(case when points = 0 then 1 else 0 end)       as losses,
        -- Tournament-weighted form (WC/major tournaments count more)
        safe_divide(
            sum(points * tournament_weight),
            sum(tournament_weight)
        )                                                 as weighted_form_pts,
        -- Clean sheets
        sum(case when goals_conceded = 0 then 1 else 0 end) as clean_sheets,
        -- Failed to score
        sum(case when goals_scored = 0 then 1 else 0 end)   as blanks
    from recent_matches
    where recency_rank <= 10
    group by team
),

-- 3-year average goals (for Poisson base rates)
long_form as (
    select
        team,
        count(*)                 as total_matches_3yr,
        avg(goals_scored)        as avg_goals_scored_3yr,
        avg(goals_conceded)      as avg_goals_conceded_3yr
    from all_team_match_stats
    where match_date >= date_sub(current_date(), interval 36 month)
    group by team
)

select
    coalesce(l.team, lf.team)   as team,
    l.matches_played,
    l.total_points,
    l.form_pts_pct,
    l.avg_goals_scored,
    l.avg_goals_conceded,
    l.avg_goal_diff,
    l.wins,
    l.draws,
    l.losses,
    l.weighted_form_pts,
    l.clean_sheets,
    l.blanks,
    -- Longer window stats for Poisson
    lf.total_matches_3yr,
    lf.avg_goals_scored_3yr,
    lf.avg_goals_conceded_3yr
from last_10 l
left join long_form lf using (team)
