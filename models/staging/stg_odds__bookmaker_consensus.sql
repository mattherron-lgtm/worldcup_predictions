-- =============================================================
-- Staging model for bookmaker odds fetched via fetch_odds.py.
-- Normalises team names to match historical results naming convention,
-- and provides a "market consensus" probability for each match outcome.
--
-- Falls back gracefully: if no odds exist for a fixture, downstream
-- models use NULL and the ensemble ignores the odds signal.
-- If the odds_bookmaker table doesn't exist yet (no API key configured),
-- this model returns zero rows so the ensemble falls back to BQML + Poisson.
-- =============================================================

{% set odds_table = 'analytics-project-production.ML_WC_2026.odds_bookmaker' %}

with raw as (
    {% if execute %}
        {% set table_exists_query %}
            select count(*) as cnt
            from `analytics-project-production.ML_WC_2026.INFORMATION_SCHEMA.TABLES`
            where table_name = 'odds_bookmaker'
        {% endset %}
        {% set results = run_query(table_exists_query) %}
        {% set table_exists = results.columns[0].values()[0] > 0 %}
    {% else %}
        {% set table_exists = false %}
    {% endif %}

    {% if table_exists %}
    select * from `{{ odds_table }}`
    {% else %}
    -- Odds table not yet populated — return empty schema
    select
        cast(null as string)    as match_id,
        cast(null as timestamp) as kickoff_utc,
        cast(null as string)    as home_team,
        cast(null as string)    as away_team,
        cast(null as int64)     as bookmaker_count,
        cast(null as float64)   as implied_p_home,
        cast(null as float64)   as implied_p_draw,
        cast(null as float64)   as implied_p_away,
        cast(null as float64)   as best_odds_home,
        cast(null as float64)   as best_odds_draw,
        cast(null as float64)   as best_odds_away,
        cast(null as timestamp) as fetched_at
    from (select 1) _empty
    where 1 = 0
    {% endif %}
),

-- Team name normalisation (Odds API uses FIFA names, we use historical names)
normalised as (
    select
        match_id,
        kickoff_utc,
        case home_team
            when 'United States'    then 'United States'
            when 'USA'              then 'United States'
            when 'Korea Republic'   then 'South Korea'
            when 'Iran'             then 'Iran'
            when 'Ivory Coast'      then 'Ivory Coast'
            when 'DR Congo'         then 'DR Congo'
            when 'Cape Verde'       then 'Cape Verde'
            when 'Turkey'           then 'Turkey'
            else home_team
        end                         as home_team,
        case away_team
            when 'United States'    then 'United States'
            when 'USA'              then 'United States'
            when 'Korea Republic'   then 'South Korea'
            when 'Iran'             then 'Iran'
            when 'Ivory Coast'      then 'Ivory Coast'
            when 'DR Congo'         then 'DR Congo'
            when 'Cape Verde'       then 'Cape Verde'
            when 'Turkey'           then 'Turkey'
            else away_team
        end                         as away_team,
        bookmaker_count,
        implied_p_home,
        implied_p_draw,
        implied_p_away,
        best_odds_home,
        best_odds_draw,
        best_odds_away,
        fetched_at
    from raw
)

select * from normalised
