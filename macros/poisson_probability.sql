{% macro poisson_pmf(lambda_col, k) %}
    -- =============================================================
    -- Poisson probability mass function: P(X = k | lambda)
    -- = exp(-lambda) × lambda^k / k!
    -- Hardcoded for k in {0, 1, 2, 3, 4, 5}. 
    -- Use in a CASE expression or per-row column reference.
    -- =============================================================
    (
        exp(-cast({{ lambda_col }} as float64))
        * pow(cast({{ lambda_col }} as float64), {{ k }})
        / {{ [1, 1, 2, 6, 24, 120][k] }}
    )
{% endmacro %}


{% macro poisson_cdf(lambda_col, max_k) %}
    -- Cumulative Poisson probability P(X <= max_k)
    -- Returns sum of PMF for k = 0..max_k
    (
        {% for k in range(max_k + 1) %}
            {{ poisson_pmf(lambda_col, k) }}
            {% if not loop.last %} + {% endif %}
        {% endfor %}
    )
{% endmacro %}
