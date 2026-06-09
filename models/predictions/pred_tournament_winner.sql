-- =============================================================
-- Tournament winner probability — propagate win probabilities
-- through all knockout rounds using chain-rule multiplication.
-- 
-- P(team wins tournament) = P(advance from group)
--   × P(win R32) × P(win R16) × P(win QF) × P(win SF) × P(win Final)
-- =============================================================

with standings as (
    select
        team,
        group_name,
        p_advance,
        p_finish_1st,
        p_finish_2nd
    from {{ ref('pred_group_stage_standings') }}
),

ko as (
    select * from {{ ref('pred_knockout_simulator') }}
),

teams as (
    select team_name, elo_rating, confederation
    from {{ ref('wc_2026_teams') }}
),

-- For each team, compute approximate probability of winning each KO round
-- This uses the Elo-based win probability against a "typical opponent"
-- A full Monte Carlo implementation would sample opponents per simulation

team_tournament_path as (
    select
        s.team,
        t.elo_rating,
        t.confederation,
        s.group_name,
        s.p_advance,
        s.p_finish_1st,
        s.p_finish_2nd,

        -- Approximate win probabilities per round using "field strength" method:
        -- P(win round) = weighted avg of Elo win prob vs all possible opponents

        -- R32 win prob vs average R32 opponent (elo ~1850)
        {{ elo_win_probability('t.elo_rating', 1850) }}             as p_win_r32_vs_avg,

        -- R16 win prob vs average R16 opponent (elo ~1900, stronger field)
        {{ elo_win_probability('t.elo_rating', 1900) }}             as p_win_r16_vs_avg,

        -- Quarterfinal vs elo ~1950
        {{ elo_win_probability('t.elo_rating', 1950) }}             as p_win_qf_vs_avg,

        -- Semifinal vs elo ~2000 (only top teams remain)
        {{ elo_win_probability('t.elo_rating', 2000) }}             as p_win_sf_vs_avg,

        -- Final vs elo ~2050
        {{ elo_win_probability('t.elo_rating', 2050) }}             as p_win_final_vs_avg

    from standings s
    join teams t on s.team = t.team_name
),

-- Chain probabilities for tournament winner
tournament_winner_prob as (
    select
        team,
        elo_rating,
        confederation,
        group_name,

        -- Component probabilities
        p_advance,
        p_finish_1st,
        p_finish_2nd,
        round(p_win_r32_vs_avg, 4)      as p_win_r32,
        round(p_win_r16_vs_avg, 4)      as p_win_r16,
        round(p_win_qf_vs_avg, 4)       as p_win_qf,
        round(p_win_sf_vs_avg, 4)       as p_win_sf,
        round(p_win_final_vs_avg, 4)    as p_win_final,

        -- Cumulative probability of winning tournament
        round(
            p_advance
            * p_win_r32_vs_avg
            * p_win_r16_vs_avg
            * p_win_qf_vs_avg
            * p_win_sf_vs_avg
            * p_win_final_vs_avg,
            5
        )                               as p_win_tournament_raw

    from team_tournament_path
),

-- Normalise so all 48 teams' probabilities sum to 1.0
normalised as (
    select
        *,
        sum(p_win_tournament_raw) over () as total_prob
    from tournament_winner_prob
)

select
    team,
    elo_rating,
    confederation,
    group_name,
    p_advance,
    p_win_r32,
    p_win_r16,
    p_win_qf,
    p_win_sf,
    p_win_final,

    round(safe_divide(p_win_tournament_raw, total_prob), 5)  as p_win_tournament,

    -- Implied bookmaker odds (for comparison)
    round(safe_divide(1.0, safe_divide(p_win_tournament_raw, total_prob)), 1) as implied_odds,

    -- Rank
    rank() over (order by p_win_tournament_raw desc)          as tournament_rank

from normalised
order by p_win_tournament_raw desc
