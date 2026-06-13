-- =============================================================
-- Comparison of predicted vs actual group standings.
-- Shows how predictions compared to real outcomes.
-- =============================================================

with predicted as (
    select
        group_name,
        team,
        avg_pts as pred_pts,
        avg_goal_diff as pred_gd,
        avg_goals_scored as pred_gf,
        p_finish_1st,
        p_finish_2nd,
        p_finish_3rd,
        p_finish_4th,
        p_advance as p_qualify
    from {{ ref('pred_group_stage_standings') }}
),

actual as (
    select
        group_name,
        team,
        total_pts as actual_pts,
        total_gd as actual_gd,
        total_gf as actual_gf,
        position as actual_position,
        qualified_direct
    from {{ ref('int_actual__group_standings') }}
),

comparison as (
    select
        coalesce(p.group_name, a.group_name) as group_name,
        coalesce(p.team, a.team) as team,
        
        -- Predicted metrics
        p.pred_pts,
        p.pred_gd,
        p.pred_gf,
        p.p_finish_1st,
        p.p_finish_2nd,
        p.p_finish_3rd,
        p.p_finish_4th,
        
        -- Actual metrics
        a.actual_pts,
        a.actual_gd,
        a.actual_gf,
        a.actual_position,
        a.qualified_direct,
        
        -- Differences
        a.actual_pts - p.pred_pts as pts_diff,
        a.actual_gd - p.pred_gd as gd_diff,
        a.actual_gf - p.pred_gf as gf_diff,
        
        -- Accuracy indicators
        case
            when a.actual_position is null then 'pending'  -- No result yet
            when a.actual_position = 1 then (case when p.p_finish_1st >= 0.5 then 'correct' else 'miss' end)
            when a.actual_position = 2 then (case when p.p_finish_2nd >= 0.5 then 'correct' else 'miss' end)
            else 'no_advance'
        end as position_accuracy
    from predicted p
    full outer join actual a on p.group_name = a.group_name and p.team = a.team
)

select * from comparison
order by group_name, team
