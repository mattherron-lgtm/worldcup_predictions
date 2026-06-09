{% macro generate_schema_name(custom_schema_name, node) -%}
    {# Always use the target schema (profile dataset) — ignore per-layer +schema config.
       This keeps all models in a single dataset: ML_WC_2026. #}
    {{ target.schema }}
{%- endmacro %}
