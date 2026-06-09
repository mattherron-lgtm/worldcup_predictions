-- =============================================================
-- Dashboard table: group stage predictions summary.
-- One row per fixture with all prediction signals combined.
-- Designed to be queried directly by Looker Studio / Tableau.
-- =============================================================

select
    -- Fixture info
    c.fixture_id,
    c.group_name,
    c.group_round,
    c.home_team,
    c.away_team,

    -- Team metadata
    ht.confederation                as home_confederation,
    at_.confederation               as away_confederation,
    ht.is_host                      as home_is_host,
    at_.is_host                     as away_is_host,
    ht.elo_rating                   as home_elo,
    at_.elo_rating                  as away_elo,

    -- ELO edge
    c.elo_diff,
    case
        when abs(c.elo_diff) < 50  then 'Even'
        when c.elo_diff > 0        then concat(c.home_team, ' favoured')
        else                            concat(c.away_team, ' favoured')
    end                             as elo_edge_label,

    -- Ensemble probabilities
    c.p_home_win,
    c.p_draw,
    c.p_away_win,
    c.ensemble_predicted_result,

    -- Expected goals
    c.home_xg,
    c.away_xg,

    -- Implied odds
    c.implied_odds_home,
    c.implied_odds_draw,
    c.implied_odds_away,

    -- Form context
    c.home_form_pts_pct,
    c.away_form_pts_pct,

    -- Component model agreement
    case when c.poisson_predicted_result = c.bqml_predicted_result
        then 'Models agree'
        else 'Models disagree'
    end                             as model_agreement,
    c.poisson_predicted_result,
    c.bqml_predicted_result,

    -- Confidence indicator (max probability of any outcome)
    greatest(c.p_home_win, c.p_draw, c.p_away_win)  as max_outcome_prob,
    case
        when greatest(c.p_home_win, c.p_draw, c.p_away_win) >= 0.55 then 'High'
        when greatest(c.p_home_win, c.p_draw, c.p_away_win) >= 0.42 then 'Medium'
        else 'Low'
    end                             as prediction_confidence,

    -- Venue & kickoff info
    f.venue,
    f.kickoff_utc,
    f.kickoff_local,
    f.utc_offset_hours,
    v.city                          as venue_city,
    v.country                       as venue_country,
    v.altitude_m,
    v.avg_temp_june_c

from {{ ref('pred_group_stage_combined') }} c
left join {{ ref('wc_2026_teams') }} ht  on c.home_team = ht.team_name
left join {{ ref('wc_2026_teams') }} at_ on c.away_team = at_.team_name
left join {{ ref('int_wc__group_fixtures') }} f on f.fixture_id = c.fixture_id
left join {{ ref('wc_2026_venues') }} v on v.venue = f.venue
order by c.group_name, c.group_round
