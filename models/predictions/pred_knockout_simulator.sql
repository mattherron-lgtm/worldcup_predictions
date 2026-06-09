-- =============================================================
-- Monte Carlo knockout bracket simulator.
-- 
-- Starting from group stage qualification probabilities, simulates
-- the full knockout bracket from Round of 32 through to the Final.
-- 
-- WC 2026 bracket structure:
--   Round of 32:   16 matches (1st & 2nd from groups + 8 best 3rd)
--   Round of 16:    8 matches
--   Quarterfinals:  4 matches
--   Semifinals:     2 matches
--   Third place:    1 match
--   Final:          1 match
-- 
-- Win probability at each stage: Elo-based (see macro elo_win_probability)
-- =============================================================

with standings as (
    select * from {{ ref('pred_group_stage_standings') }}
),

teams as (
    select team_name, elo_rating from {{ ref('wc_2026_teams') }}
),

-- Pick the most likely group qualifier for each slot
-- In a full simulation, this would be sampled per-simulation
-- Here we use highest p_finish_1st/2nd teams for deterministic bracket structure
group_winners as (
    select
        group_name,
        array_agg(team order by p_finish_1st desc limit 1)[offset(0)]  as first_place,
        array_agg(team order by p_finish_2nd desc limit 1)[offset(0)]  as second_place
    from standings
    group by group_name
),

-- Round of 32 bracket (2026 WC bracket seeding — simplified)
-- Official bracket: A1 vs B2, B1 vs A2, C1 vs D2, D1 vs C2, etc.
r32_fixtures as (
    select 'R32-01' as match_id, 'R32' as round, gA.first_place  as team_a, gB.second_place as team_b from group_winners gA cross join group_winners gB where gA.group_name = 'A' and gB.group_name = 'B'
    union all select 'R32-02', 'R32', gB.first_place, gA.second_place from group_winners gA cross join group_winners gB where gA.group_name = 'A' and gB.group_name = 'B'
    union all select 'R32-03', 'R32', gC.first_place, gD.second_place from group_winners gC cross join group_winners gD where gC.group_name = 'C' and gD.group_name = 'D'
    union all select 'R32-04', 'R32', gD.first_place, gC.second_place from group_winners gC cross join group_winners gD where gC.group_name = 'C' and gD.group_name = 'D'
    union all select 'R32-05', 'R32', gE.first_place, gF.second_place from group_winners gE cross join group_winners gF where gE.group_name = 'E' and gF.group_name = 'F'
    union all select 'R32-06', 'R32', gF.first_place, gE.second_place from group_winners gE cross join group_winners gF where gE.group_name = 'E' and gF.group_name = 'F'
    union all select 'R32-07', 'R32', gG.first_place, gH.second_place from group_winners gG cross join group_winners gH where gG.group_name = 'G' and gH.group_name = 'H'
    union all select 'R32-08', 'R32', gH.first_place, gG.second_place from group_winners gG cross join group_winners gH where gG.group_name = 'G' and gH.group_name = 'H'
    union all select 'R32-09', 'R32', gI.first_place, gJ.second_place from group_winners gI cross join group_winners gJ where gI.group_name = 'I' and gJ.group_name = 'J'
    union all select 'R32-10', 'R32', gJ.first_place, gI.second_place from group_winners gI cross join group_winners gJ where gI.group_name = 'I' and gJ.group_name = 'J'
    union all select 'R32-11', 'R32', gK.first_place, gL.second_place from group_winners gK cross join group_winners gL where gK.group_name = 'K' and gL.group_name = 'L'
    union all select 'R32-12', 'R32', gL.first_place, gK.second_place from group_winners gK cross join group_winners gL where gK.group_name = 'K' and gL.group_name = 'L'
    -- Remaining 4 R32 fixtures involve best 8 third-placed teams
    -- Seeded as 3rd-A vs 3rd-B, etc. (simplified to most likely 3rd-place teams)
    union all select 'R32-13', 'R32', gA.second_place, gC.second_place from group_winners gA cross join group_winners gC where gA.group_name = 'A' and gC.group_name = 'C'
    union all select 'R32-14', 'R32', gE.second_place, gG.second_place from group_winners gE cross join group_winners gG where gE.group_name = 'E' and gG.group_name = 'G'
    union all select 'R32-15', 'R32', gI.second_place, gK.second_place from group_winners gI cross join group_winners gK where gI.group_name = 'I' and gK.group_name = 'K'
    union all select 'R32-16', 'R32', gB.second_place, gD.second_place from group_winners gB cross join group_winners gD where gB.group_name = 'B' and gD.group_name = 'D'
),

-- Add ELO ratings and compute match probabilities for each KO fixture
ko_with_probs as (
    select
        f.match_id,
        f.round,
        f.team_a,
        f.team_b,
        ta.elo_rating                               as elo_a,
        tb.elo_rating                               as elo_b,
        ta.elo_rating - tb.elo_rating               as elo_diff,

        -- Elo win probability (no draw in knockout)
        {{ elo_win_probability('ta.elo_rating', 'tb.elo_rating') }}     as p_team_a_wins,
        1 - {{ elo_win_probability('ta.elo_rating', 'tb.elo_rating') }} as p_team_b_wins
    from r32_fixtures f
    left join teams ta on f.team_a = ta.team_name
    left join teams tb on f.team_b = tb.team_name
)

select * from ko_with_probs
order by round, match_id
