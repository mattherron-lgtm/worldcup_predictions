-- =============================================================
-- Gemini AI match narratives for all group stage fixtures.
-- 
-- Uses BigQuery ML ML.GENERATE_TEXT() with Gemini Flash to produce:
--   1. Pre-match analysis (form, key players, tactical context)
--   2. Predicted scoreline with reasoning
--   3. Upset potential rating (Low / Medium / High)
-- 
-- Prerequisites:
--   - Run bigquery_setup/03_create_gemini_connection.sql first
--   - Ensure worldcup_ml.gemini_flash model exists
-- =============================================================

with predictions as (
    select * from {{ ref('mart_wc_group_predictions') }}
),

-- Build a rich prompt for each match
prompts as (
    select
        fixture_id,
        group_name,
        group_round,
        home_team,
        away_team,

        -- Structured prompt with prediction context
        concat(
            '2026 FIFA World Cup — Group ', group_name, ' (Matchday ', group_round, ')\n',
            'Match: ', home_team, ' vs ', away_team, '\n\n',

            'Pre-match statistics:\n',
            '- ELO ratings: ', home_team, ' ', cast(round(home_elo) as string),
            ' vs ', away_team, ' ', cast(round(away_elo) as string), '\n',
            '- Our model probabilities: ',
            home_team, ' win ', cast(round(p_home_win * 100, 1) as string), '% | ',
            'Draw ', cast(round(p_draw * 100, 1) as string), '% | ',
            away_team, ' win ', cast(round(p_away_win * 100, 1) as string), '%\n',
            '- Expected goals: ', home_team, ' ', cast(home_xg as string),
            ' — ', away_team, ' ', cast(away_xg as string), '\n',
            '- Recent form (points %): ', home_team, ' ',
            cast(round(home_form_pts_pct * 100, 1) as string), '% | ',
            away_team, ' ', cast(round(away_form_pts_pct * 100, 1) as string), '%\n',
            '- Model prediction: ', ensemble_predicted_result, '\n\n',

            'Please provide:\n',
            '1. A 2-sentence match preview covering recent form and what\'s at stake in the group.\n',
            '2. One key tactical matchup or player battle to watch.\n',
            '3. Your predicted scoreline and brief reasoning.\n',
            '4. Upset potential: Low / Medium / High with one sentence of explanation.\n',
            'Be concise — max 150 words total.'
        )                                   as prompt

    from predictions
),

-- Call Gemini Flash for each match (only when gemini_enabled = true in dbt_project.yml).
-- To enable: create the model via bigquery_setup/03_create_gemini_connection.sql,
-- then set gemini_enabled: true in dbt_project.yml vars.
{% set gemini_model = var('bq_project') ~ '.' ~ var('bq_ml_dataset') ~ '.gemini_flash' %}
{% set model_exists = var('gemini_enabled', false) %}

-- Call Gemini Flash for each match (only when model is available)
narratives as (
    {% if model_exists %}
    select
        p.fixture_id,
        json_value(gen.ml_generate_text_result, '$.candidates[0].content.parts[0].text')
                                            as gemini_narrative
    from prompts p
    join (
        select *
        from ML.GENERATE_TEXT(
            MODEL `{{ gemini_model }}`,
            (select fixture_id, prompt from prompts),
            struct(
                0.7  as temperature,
                256  as max_output_tokens,
                true as flatten_json_output
            )
        )
    ) gen
    on gen.fixture_id = p.fixture_id
    {% else %}
    -- Gemini model not yet configured — returning null narratives.
    -- To enable: run bigquery_setup/03_create_gemini_connection.sql
    select
        fixture_id,
        cast(null as string) as gemini_narrative
    from prompts
    {% endif %}
)

select
    p.fixture_id,
    p.group_name,
    p.group_round,
    p.home_team,
    p.away_team,
    p.home_elo,
    p.away_elo,
    p.p_home_win,
    p.p_draw,
    p.p_away_win,
    p.ensemble_predicted_result,
    p.home_xg,
    p.away_xg,
    p.prediction_confidence,
    n.gemini_narrative

from predictions p
left join narratives n using (fixture_id)
order by group_name, group_round
