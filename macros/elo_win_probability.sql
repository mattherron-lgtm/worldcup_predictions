{% macro elo_win_probability(elo_a, elo_b) %}
    -- =============================================================
    -- Elo win probability formula (no draw — for knockout rounds).
    -- P(team_a wins) = 1 / (1 + 10^((elo_b - elo_a) / 400))
    -- 
    -- For group stage use pred_group_stage_poisson which includes
    -- draw probability via the Poisson score matrix.
    -- =============================================================
    (1.0 / (1.0 + pow(10.0, (cast({{ elo_b }} as float64) - cast({{ elo_a }} as float64)) / 400.0)))
{% endmacro %}
