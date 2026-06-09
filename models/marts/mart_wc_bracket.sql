-- =============================================================
-- Bracket table: full tournament probabilities per team per round.
-- One row per team with probabilities for reaching each stage.
-- =============================================================

with winner as (
    select * from {{ ref('pred_tournament_winner') }}
),

standings as (
    select * from {{ ref('pred_group_stage_standings') }}
),

teams as (
    select * from {{ ref('wc_2026_teams') }}
)

select
    w.team,
    w.group_name,
    t.confederation,
    t.elo_rating,
    t.is_host,

    -- Group stage outcomes
    s.p_finish_1st,
    s.p_finish_2nd,
    s.p_finish_3rd,
    s.p_finish_4th,
    w.p_advance                             as p_qualify_r32,
    s.avg_pts,
    s.avg_goal_diff,

    -- Knockout round reach probabilities
    round(w.p_advance * w.p_win_r32, 4)     as p_reach_r16,
    round(w.p_advance * w.p_win_r32 * w.p_win_r16, 4)              as p_reach_qf,
    round(w.p_advance * w.p_win_r32 * w.p_win_r16 * w.p_win_qf, 4) as p_reach_sf,
    round(w.p_advance * w.p_win_r32 * w.p_win_r16 * w.p_win_qf * w.p_win_sf, 4) as p_reach_final,
    w.p_win_tournament,
    w.implied_odds                          as outright_implied_odds,
    w.tournament_rank

from winner w
join standings s using (team)
join teams t on w.team = t.team_name
order by w.p_win_tournament desc
