-- dbt が BigQuery 向けに生成した SQL（target/compiled）を、BigQuery サンドボックスのコンソールで流して確かめる用
-- dbt run をまだ自分の PC で動かしていないときの確認手段。dbt seed の代わりに CREATE TABLE AS SELECT でテーブルを作る
CREATE SCHEMA IF NOT EXISTS youtube_dbt;

CREATE OR REPLACE TABLE youtube_dbt.channel_daily AS
SELECT DATE_ADD(DATE '2026-07-14', INTERVAL i DAY) AS date, views
FROM UNNEST([0, 4, 0, 7, 8, 57, 33, 50, 62, 10, 76, 110, 91, 139, 206, 144, 412, 221, 335, 277, 201, 171, 207, 166, 175, 199, 160, 172, 203, 15, 33, 29, 22, 12, 23, 71, 732, 410, 858, 217, 351, 271, 318, 415, 200, 932, 712, 1430, 228, 62, 95, 2185, 1447, 122, 1332, 161, 599, 518, 738, 907, 979, 620, 951, 590, 371, 305, 560, 486, 203, 560, 234, 82, 205, 94, 277, 63, 794, 1123, 561, 275, 413, 461, 124, 813, 1115, 761, 142, 555, 511, 241, 1095, 1117, 555]) AS views WITH OFFSET AS i;

-- models/staging/stg_channel_daily.sql（コンパイル後）
CREATE OR REPLACE VIEW youtube_dbt.stg_channel_daily AS
select
    cast(date as date) as date,
    cast(views as INT64) as views
from youtube_dbt.channel_daily;

-- models/marts/v_channel_ma7.sql（コンパイル後。曜日はマクロ weekday_name → FORMAT_DATE）
CREATE OR REPLACE VIEW youtube_dbt.v_channel_ma7 AS
select
    date,
    FORMAT_DATE('%a', date) as weekday_name,
    views,
    round(avg(views) over (order by date rows between 6 preceding and current row), 2) as views_ma7,
    count(*) over (order by date rows between 6 preceding and current row) as days_in_window,
    lag(views, 7) over (order by date) as views_same_day_last_week
from youtube_dbt.stg_channel_daily;

-- tests/assert_matches_sql_server.sql と同じ答え合わせ（ok がすべて true なら合格。2026-10-21 実行：4項目とも true）
with checks as (
    select 'total_views' as item, cast(sum(views) as FLOAT64) as actual, 36577.0 as expected from youtube_dbt.v_channel_ma7
    union all
    select 'ma7_1014', max(case when date = DATE '2026-10-14' then views_ma7 end), 602.29 from youtube_dbt.v_channel_ma7
    union all
    select 'ma7_1013', max(case when date = DATE '2026-10-13' then views_ma7 end), 631.71 from youtube_dbt.v_channel_ma7
    union all
    select 'n_days', cast(count(*) as FLOAT64), 93.0 from youtube_dbt.v_channel_ma7
)
select item, actual, expected, abs(actual - expected) <= 0.005 as ok from checks;
