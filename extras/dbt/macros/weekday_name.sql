{# 曜日の略称（Mon〜Sun）。SQL Server 版は dim_date を JOIN していたところ。
   データベースごとに関数が違うので、dbt の adapter.dispatch で切り替える #}
{% macro weekday_name(col) %}
  {{ return(adapter.dispatch('weekday_name')(col)) }}
{% endmacro %}

{% macro bigquery__weekday_name(col) %}FORMAT_DATE('%a', {{ col }}){% endmacro %}

{% macro duckdb__weekday_name(col) %}strftime({{ col }}, '%a'){% endmacro %}

{% macro default__weekday_name(col) %}to_char({{ col }}, 'Dy'){% endmacro %}
