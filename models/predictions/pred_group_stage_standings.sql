-- =============================================================
-- Monte Carlo group stage standings simulation.
-- 
-- Method:
--   1. For each of N simulations, draw a random outcome for every
--      group match using the ensemble probability distribution.
--   2. Award 3 pts (win), 1 pt (draw), 0 pts (loss) per team.
--   3. Simulate goal counts from Poisson(xg) using a quantile approximation.
--   4. Rank teams by: points → goal_diff → goals_scored → head_to_head.
--   5. Determine who advances: top 2 from each group (32 direct)
--      + best 8 third-placed teams (rounds up to 32 total).
--   6. Aggregate across simulations for probabilities.
-- =============================================================

with predictions as (
    select * from {{ ref('pred_group_stage_combined') }}
),

-- Expand to N simulations per fixture
simulations as (
    select
        sim_id,
        fixture_id,
        group_name,
        group_round,
        home_team,
        away_team,
        p_home_win,
        p_draw,
        p_away_win,
        home_xg,
        away_xg,
        rand()                                  as r_outcome,
        rand()                                  as r_home_goals,
        rand()                                  as r_away_goals
    from predictions
    cross join unnest(generate_array(1, {{ var('n_simulations') }})) as sim_id
),

-- Determine match outcome and approximate scoreline
match_outcomes as (
    select
        sim_id,
        fixture_id,
        group_name,
        home_team,
        away_team,

        -- Outcome drawn from probability distribution
        case
            when r_outcome < p_home_win               then 'home_win'
            when r_outcome < p_home_win + p_draw      then 'draw'
            else                                           'away_win'
        end                                         as sim_result,

        -- Approximate Poisson random variate via inverse CDF (simple quantile mapping)
        -- For small lambda, this gives reasonable goal distributions
        case
            when r_home_goals < exp(-home_xg)               then 0
            when r_home_goals < exp(-home_xg) * (1 + home_xg) then 1
            when r_home_goals < exp(-home_xg) * (1 + home_xg + pow(home_xg,2)/2) then 2
            when r_home_goals < exp(-home_xg) * (1 + home_xg + pow(home_xg,2)/2 + pow(home_xg,3)/6) then 3
            when r_home_goals < exp(-home_xg) * (1 + home_xg + pow(home_xg,2)/2 + pow(home_xg,3)/6 + pow(home_xg,4)/24) then 4
            else                                                 5
        end                                         as sim_home_goals,

        case
            when r_away_goals < exp(-away_xg)               then 0
            when r_away_goals < exp(-away_xg) * (1 + away_xg) then 1
            when r_away_goals < exp(-away_xg) * (1 + away_xg + pow(away_xg,2)/2) then 2
            when r_away_goals < exp(-away_xg) * (1 + away_xg + pow(away_xg,2)/2 + pow(away_xg,3)/6) then 3
            when r_away_goals < exp(-away_xg) * (1 + away_xg + pow(away_xg,2)/2 + pow(away_xg,3)/6 + pow(away_xg,4)/24) then 4
            else                                                 5
        end                                         as sim_away_goals

    from simulations
),

-- Correct goal values so they match the simulated result
-- (handles edge case where Poisson draw doesn't match outcome)
corrected_outcomes as (
    select
        sim_id,
        group_name,
        home_team,
        away_team,
        sim_result,
        case sim_result
            when 'home_win' then greatest(sim_home_goals, sim_away_goals + 1)
            when 'draw'     then sim_home_goals
            when 'away_win' then least(sim_home_goals, sim_away_goals - 1)
        end                                         as final_home_goals,
        case sim_result
            when 'home_win' then least(sim_away_goals, sim_home_goals - 1)
            when 'draw'     then sim_home_goals
            when 'away_win' then greatest(sim_away_goals, sim_home_goals + 1)
        end                                         as final_away_goals
    from match_outcomes
),

-- Flatten to per-team, per-simulation view
team_sim_stats as (
    -- Home team perspective
    select
        sim_id, group_name, home_team as team,
        case sim_result when 'home_win' then 3 when 'draw' then 1 else 0 end as pts,
        final_home_goals as goals_scored,
        final_away_goals as goals_conceded
    from corrected_outcomes

    union all

    -- Away team perspective
    select
        sim_id, group_name, away_team as team,
        case sim_result when 'away_win' then 3 when 'draw' then 1 else 0 end as pts,
        final_away_goals as goals_scored,
        final_home_goals as goals_conceded
    from corrected_outcomes
),

-- Group totals per team per simulation
team_sim_totals as (
    select
        sim_id,
        group_name,
        team,
        sum(pts)                        as total_pts,
        sum(goals_scored)               as total_gf,
        sum(goals_conceded)             as total_ga,
        sum(goals_scored - goals_conceded) as total_gd
    from team_sim_stats
    group by sim_id, group_name, team
),

-- Rank teams within each group/simulation
-- Tiebreaker: pts → gd → gf → random (approximate draw)
team_sim_rank as (
    select
        *,
        row_number() over (
            partition by sim_id, group_name
            order by total_pts desc, total_gd desc, total_gf desc, rand()
        )                               as group_position
    from team_sim_totals
),

-- Best 3rd-place teams advance (top 8 of 12 third-placed teams)
third_place_ranked as (
    select
        *,
        row_number() over (
            partition by sim_id
            order by total_pts desc, total_gd desc, total_gf desc
        )                               as third_place_overall_rank
    from team_sim_rank
    where group_position = 3
),

-- Mark teams that advance in each simulation
advancement as (
    select
        sim_id,
        group_name,
        team,
        group_position,
        total_pts,
        total_gd,
        total_gf,
        total_ga,
        case
            when group_position in (1, 2)   then true
            when group_position = 3
                and third_place_overall_rank <= 8  then true
            else false
        end                             as advances
    from team_sim_rank
    left join third_place_ranked using (sim_id, group_name, team, group_position, total_pts, total_gd, total_gf, total_ga)
)

-- Aggregate across simulations
select
    group_name,
    team,
    {{ var('n_simulations') }}                                  as n_simulations,

    -- Position probabilities
    round(countif(group_position = 1) / {{ var('n_simulations') }}, 4)  as p_finish_1st,
    round(countif(group_position = 2) / {{ var('n_simulations') }}, 4)  as p_finish_2nd,
    round(countif(group_position = 3) / {{ var('n_simulations') }}, 4)  as p_finish_3rd,
    round(countif(group_position = 4) / {{ var('n_simulations') }}, 4)  as p_finish_4th,

    -- Advancement probability
    round(countif(advances) / {{ var('n_simulations') }}, 4)            as p_advance,
    round(countif(not advances) / {{ var('n_simulations') }}, 4)        as p_eliminated,

    -- Average points/GD across simulations
    round(avg(total_pts), 2)            as avg_pts,
    round(avg(total_gd), 2)             as avg_goal_diff,
    round(avg(total_gf), 2)             as avg_goals_scored,
    round(avg(total_ga), 2)             as avg_goals_conceded

from advancement
group by group_name, team
order by group_name, p_finish_1st desc
