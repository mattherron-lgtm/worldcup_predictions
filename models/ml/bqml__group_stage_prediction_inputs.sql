-- =============================================================
-- BQML prediction input features for the 2026 World Cup group stage.
-- This feeds directly into ML.PREDICT() alongside the trained model.
-- Structure must match the training features in int_ml__match_training_features.
-- =============================================================

with fixtures as (
    select * from {{ ref('int_wc__group_fixtures') }}
),

form as (
    select * from {{ ref('int_results__team_recent_form') }}
),

h2h as (
    select * from {{ ref('int_results__head_to_head') }}
),

teams as (
    select team_name, elo_rating from {{ ref('wc_2026_teams') }}
)

select
    f.fixture_id,
    f.group_name,
    f.group_round,
    f.home_team,
    f.away_team,
    f.home_elo,
    f.away_elo,

    -- ELO diff (positive = home team stronger)
    f.elo_diff,

    -- No home advantage at World Cup (neutral venues)
    0                                                   as home_advantage,

    -- WC group stage has highest tournament weight
    3.0                                                 as tournament_weight,

    -- Home team form
    coalesce(hf.form_pts_pct, 0.4)                      as home_form_pts_pct,
    coalesce(hf.avg_goals_scored, 1.2)                  as home_avg_goals_scored,
    coalesce(hf.avg_goals_conceded, 1.2)                as home_avg_goals_conceded,

    -- Away team form
    coalesce(af.form_pts_pct, 0.4)                      as away_form_pts_pct,
    coalesce(af.avg_goals_scored, 1.2)                  as away_avg_goals_scored,
    coalesce(af.avg_goals_conceded, 1.2)                as away_avg_goals_conceded,

    -- H2H features
    coalesce(h.h2h_win_rate, 0.33)                      as h2h_home_win_rate,
    coalesce(h.h2h_draw_rate, 0.25)                     as h2h_draw_rate,

    -- Poisson strength indices (carried through for ensemble)
    hf.avg_goals_scored_3yr                             as home_avg_goals_scored_3yr,
    hf.avg_goals_conceded_3yr                           as home_avg_goals_conceded_3yr,
    af.avg_goals_scored_3yr                             as away_avg_goals_scored_3yr,
    af.avg_goals_conceded_3yr                           as away_avg_goals_conceded_3yr

from fixtures f
left join form hf
    on f.home_team = hf.team
left join form af
    on f.away_team = af.team
left join h2h h
    on f.home_team = h.team
    and f.away_team = h.opponent
qualify row_number() over (partition by f.fixture_id order by h.h2h_win_rate desc nulls last) = 1
