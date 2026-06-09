with source as (
    select * from {{ source('raw', 'historical_match_results') }}
),

cleaned as (
    select
        -- Identifiers
        {{ dbt_utils.generate_surrogate_key(['date', 'home_team', 'away_team']) }} as match_id,
        cast(date as date)           as match_date,

        -- Teams (normalise common name variants)
        trim(home_team)              as home_team,
        trim(away_team)              as away_team,

        -- Scores
        safe_cast(nullif(home_score, 'NA') as int64)  as home_goals,
        safe_cast(nullif(away_score, 'NA') as int64)  as away_goals,

        -- Match context
        tournament,
        city,
        country                                        as host_country,
        coalesce(neutral, false)                       as is_neutral_venue,

        -- Derived columns
        safe_cast(nullif(home_score, 'NA') as int64)
            - safe_cast(nullif(away_score, 'NA') as int64)              as goal_diff,
        safe_cast(nullif(home_score, 'NA') as int64)
            + safe_cast(nullif(away_score, 'NA') as int64)              as total_goals,

        case
            when cast(home_score as int64) > cast(away_score as int64)  then 'home_win'
            when cast(home_score as int64) < cast(away_score as int64)  then 'away_win'
            else                                                              'draw'
        end                          as result,

        -- Tournament weight for training — higher = more meaningful match
        case tournament
            when 'FIFA World Cup'                   then 3.0
            when 'UEFA Euro'                        then 2.5
            when 'UEFA European Championship'       then 2.5
            when 'Copa América'                     then 2.5
            when 'AFC Asian Cup'                    then 2.0
            when 'Africa Cup of Nations'            then 2.0
            when 'CONCACAF Gold Cup'                then 1.5
            when 'FIFA World Cup qualification'     then 1.5
            when 'UEFA Euro qualification'          then 1.5
            when 'Friendly'                         then 0.5
            else                                         1.0
        end                          as tournament_weight,

        -- Era flag for recency weighting
        case
            when date >= date_sub(current_date(), interval 2 year)  then 'recent'
            when date >= date_sub(current_date(), interval 5 year)  then 'mid'
            else                                                          'historic'
        end                          as recency_tier

    from source
    where home_score is not null and home_score != 'NA'
      and away_score is not null and away_score != 'NA'
      and date is not null
)

select * from cleaned
