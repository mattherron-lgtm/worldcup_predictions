-- =============================================================
-- ML training feature set — one row per historical match.
-- This is the table that feeds 04_train_bqml_model.sql.
-- Covers all international matches 2010–present for WC-qualified teams.
-- =============================================================

with matches as (
    select * from {{ ref('stg_results__international_matches') }}
    where match_date >= '2010-01-01'
),

-- We need point-in-time form: form BEFORE each match
-- Approximation: use the team's form computed from all matches in the 12 months
-- preceding the match date. This avoids data leakage.
prior_form as (
    select
        anchor.match_id,
        anchor.match_date,
        anchor.home_team,
        anchor.away_team,

        -- Home team form in the 12 months prior to this match
        avg(case when form.home_team = anchor.home_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then case when form.result = 'home_win' then 3
                       when form.result = 'draw'     then 1
                       else 0 end
             when form.away_team = anchor.home_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then case when form.result = 'away_win' then 3
                       when form.result = 'draw'     then 1
                       else 0 end
            end)                                            as home_prior_pts_avg,

        -- Away team form in the 12 months prior
        avg(case when form.home_team = anchor.away_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then case when form.result = 'home_win' then 3
                       when form.result = 'draw'     then 1
                       else 0 end
             when form.away_team = anchor.away_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then case when form.result = 'away_win' then 3
                       when form.result = 'draw'     then 1
                       else 0 end
            end)                                            as away_prior_pts_avg,

        -- Home team goals scored/conceded in prior 12 months
        avg(case when form.home_team = anchor.home_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then form.home_goals end)                      as home_avg_gs_prior,

        avg(case when form.away_team = anchor.home_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then form.away_goals end)                      as home_avg_gs_prior_away_role,

        avg(case when form.home_team = anchor.away_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then form.home_goals end)                      as away_avg_gs_prior,

        avg(case when form.away_team = anchor.away_team
                  and form.match_date < anchor.match_date
                  and form.match_date >= date_sub(anchor.match_date, interval 12 month)
             then form.away_goals end)                      as away_avg_gs_prior_away_role

    from matches anchor
    left join matches form
        on (form.home_team in (anchor.home_team, anchor.away_team)
            or form.away_team in (anchor.home_team, anchor.away_team))
        and form.match_date < anchor.match_date
        and form.match_date >= date_sub(anchor.match_date, interval 12 month)
    group by anchor.match_id, anchor.match_date, anchor.home_team, anchor.away_team
),

-- Head-to-head prior to each match (all time)
h2h_prior as (
    select
        anchor.match_id,
        safe_divide(
            countif(
                (sub.home_team = anchor.home_team and sub.result = 'home_win')
                or (sub.away_team = anchor.home_team and sub.result = 'away_win')
            ),
            count(*)
        )                                                   as h2h_home_win_rate,
        safe_divide(
            countif(sub.result = 'draw'),
            count(*)
        )                                                   as h2h_draw_rate
    from matches anchor
    left join matches sub
        on ((sub.home_team = anchor.home_team and sub.away_team = anchor.away_team)
             or (sub.home_team = anchor.away_team and sub.away_team = anchor.home_team))
        and sub.match_date < anchor.match_date
    group by anchor.match_id
),

-- ELO ratings from seed (static — best available pre-match proxy for training)
elo as (
    select team_name, elo_rating
    from {{ ref('wc_2026_teams') }}
),

features as (
    select
        m.match_id,
        m.match_date,
        m.home_team,
        m.away_team,
        m.tournament,
        m.tournament_weight,
        m.is_neutral_venue,
        m.result,  -- label

        -- ELO features (static approximation — ideally would be point-in-time)
        coalesce(he.elo_rating, 1500)                       as home_elo,
        coalesce(ae.elo_rating, 1500)                       as away_elo,
        coalesce(he.elo_rating, 1500)
            - coalesce(ae.elo_rating, 1500)                 as elo_diff,

        -- Home advantage (neutral venue = no advantage)
        case when not m.is_neutral_venue then 1 else 0 end  as home_advantage,

        -- Point-in-time form features
        coalesce(
            safe_divide(pf.home_prior_pts_avg, 3.0), 0.4
        )                                                   as home_form_pts_pct,
        coalesce(
            safe_divide(pf.away_prior_pts_avg, 3.0), 0.4
        )                                                   as away_form_pts_pct,
        coalesce(
            coalesce(pf.home_avg_gs_prior, pf.home_avg_gs_prior_away_role), 1.2
        )                                                   as home_avg_goals_scored,
        coalesce(
            coalesce(pf.away_avg_gs_prior, pf.away_avg_gs_prior_away_role), 1.2
        )                                                   as away_avg_goals_scored,

        -- Conceded approximated as goals scored by opponent
        coalesce(
            coalesce(pf.away_avg_gs_prior, pf.away_avg_gs_prior_away_role), 1.2
        )                                                   as home_avg_goals_conceded,
        coalesce(
            coalesce(pf.home_avg_gs_prior, pf.home_avg_gs_prior_away_role), 1.2
        )                                                   as away_avg_goals_conceded,

        -- H2H features
        coalesce(h.h2h_home_win_rate, 0.33)                 as h2h_home_win_rate,
        coalesce(h.h2h_draw_rate, 0.25)                     as h2h_draw_rate

    from matches m
    left join elo he on m.home_team = he.team_name
    left join elo ae on m.away_team = ae.team_name
    left join prior_form pf on m.match_id = pf.match_id
    left join h2h_prior h on m.match_id = h.match_id
    where m.tournament_weight >= 1.0  -- exclude friendlies from training set
)

select * from features
