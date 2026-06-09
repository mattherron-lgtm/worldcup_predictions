-- =============================================================
-- Poisson expected-goals model for group stage match predictions.
-- 
-- For each fixture:
--   1. Compute expected goals (xG) for each team
--   2. Build P(home=i goals, away=j goals) matrix for i,j in 0..5
--   3. Sum over matrix cells to get P(home_win), P(draw), P(away_win)
-- 
-- All WC group games are at neutral venues — no home advantage.
-- =============================================================

with fixtures as (
    select * from {{ ref('int_wc__group_fixtures') }}
),

strengths as (
    select
        team,
        final_attack_index,
        final_defense_index,
        league_avg_goals
    from {{ ref('int_poisson__team_strengths') }}
),

-- Join team Poisson parameters onto each fixture
fixture_params as (
    select
        f.fixture_id,
        f.group_name,
        f.group_round,
        f.home_team,
        f.away_team,
        f.elo_diff,

        -- Baseline league average
        coalesce(hs.league_avg_goals, 1.25)                     as mu,

        -- Expected goals: attack_index × opponent_defense_index × league_avg
        -- Clamp between 0.3 and 4.0 for numerical stability
        greatest(0.3, least(4.0,
            coalesce(hs.final_attack_index, 1.0)
            * coalesce(as_.final_defense_index, 1.0)
            * coalesce(hs.league_avg_goals, 1.25)
        ))                                                      as home_xg,

        greatest(0.3, least(4.0,
            coalesce(as_.final_attack_index, 1.0)
            * coalesce(hs.final_defense_index, 1.0)
            * coalesce(hs.league_avg_goals, 1.25)
        ))                                                      as away_xg

    from fixtures f
    left join strengths hs on f.home_team = hs.team
    left join strengths as_ on f.away_team = as_.team
),

-- Generate Poisson PMF for k = 0..5 goals using BigQuery UNNEST trick
-- P(X=k | lambda) = exp(-lambda) * lambda^k / k!
goal_range as (
    select k from unnest([0, 1, 2, 3, 4, 5]) as k
),

-- Score probability matrix: P(home_goals=i, away_goals=j)
score_matrix as (
    select
        fp.fixture_id,
        fp.home_team,
        fp.away_team,
        fp.home_xg,
        fp.away_xg,
        h.k                             as home_goals,
        a.k                             as away_goals,

        -- Poisson PMF for home goals
        exp(-fp.home_xg) * pow(fp.home_xg, h.k)
            / case h.k when 0 then 1 when 1 then 1 when 2 then 2
                       when 3 then 6 when 4 then 24 when 5 then 120 end
                                        as p_home_score,

        -- Poisson PMF for away goals (independent)
        exp(-fp.away_xg) * pow(fp.away_xg, a.k)
            / case a.k when 0 then 1 when 1 then 1 when 2 then 2
                       when 3 then 6 when 4 then 24 when 5 then 120 end
                                        as p_away_score

    from fixture_params fp
    cross join goal_range h
    cross join goal_range a
),

-- Aggregate over score matrix to get W/D/L probs
wdl_raw as (
    select
        fixture_id,
        home_team,
        away_team,
        any_value(home_xg)              as home_xg,
        any_value(away_xg)              as away_xg,

        -- Normalisation factor (captures truncation at 5 goals)
        sum(p_home_score * p_away_score)            as total_prob,

        sum(case when home_goals > away_goals
            then p_home_score * p_away_score else 0 end)    as raw_p_home_win,

        sum(case when home_goals = away_goals
            then p_home_score * p_away_score else 0 end)    as raw_p_draw,

        sum(case when home_goals < away_goals
            then p_home_score * p_away_score else 0 end)    as raw_p_away_win

    from score_matrix
    group by fixture_id, home_team, away_team
)

-- Re-normalise to ensure probabilities sum to exactly 1.0
select
    fp.fixture_id,
    fp.group_name,
    fp.group_round,
    wdl.home_team,
    wdl.away_team,
    fp.elo_diff,
    round(wdl.home_xg, 3)               as home_xg,
    round(wdl.away_xg, 3)               as away_xg,

    round(safe_divide(wdl.raw_p_home_win, wdl.total_prob), 4)  as poisson_p_home_win,
    round(safe_divide(wdl.raw_p_draw,     wdl.total_prob), 4)  as poisson_p_draw,
    round(safe_divide(wdl.raw_p_away_win, wdl.total_prob), 4)  as poisson_p_away_win,

    -- Most likely outcome
    case
        when safe_divide(wdl.raw_p_home_win, wdl.total_prob)
            >= safe_divide(wdl.raw_p_draw, wdl.total_prob)
            and safe_divide(wdl.raw_p_home_win, wdl.total_prob)
            >= safe_divide(wdl.raw_p_away_win, wdl.total_prob)
            then 'home_win'
        when safe_divide(wdl.raw_p_draw, wdl.total_prob)
            >= safe_divide(wdl.raw_p_away_win, wdl.total_prob)
            then 'draw'
        else 'away_win'
    end                                 as poisson_predicted_result

from fixture_params fp
join wdl_raw wdl using (fixture_id)
