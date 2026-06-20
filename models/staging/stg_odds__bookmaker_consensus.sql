-- =============================================================
-- Staging model referencing local static/historic dbt seeds 
-- uploaded via seeds/wc_2026_consensus_odds.csv
--
-- Normalises team names to match historical results naming convention,
-- and provides a "market consensus" probability for each match outcome.
-- =============================================================

with raw as (
    select
        match_id,
        cast(kickoff_utc as timestamp) as kickoff_utc,
        home_team,
        away_team,
        cast(bookmaker_count as int64) as bookmaker_count,
        cast(implied_p_home as float64) as implied_p_home,
        cast(implied_p_draw as float64) as implied_p_draw,
        cast(implied_p_away as float64) as implied_p_away,
        cast(best_odds_home as float64) as best_odds_home,
        cast(best_odds_draw as float64) as best_odds_draw,
        cast(best_odds_away as float64) as best_odds_away,
        cast(fetched_at as timestamp) as fetched_at
    from {{ ref('wc_2026_consensus_odds') }}
),

-- Team name normalisation (Odds data sources use FIFA names, we use historical names)
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
