-- 日別の視聴回数と 7日移動平均・前週同曜日の値
-- 元：sql/04_views.sql（SQL Server の mart.v_channel_ma7）、extras/bigquery/02_v_channel_ma7.sql（BigQuery 版）
-- 答え合わせ：10/14 = 602.29、10/13 = 631.71、93日の合計 = 36,577（tests/ で自動で確かめる）
select
    date,
    {{ weekday_name('date') }} as weekday_name,
    views,
    round(avg(views) over (order by date rows between 6 preceding and current row), 2) as views_ma7,
    count(*) over (order by date rows between 6 preceding and current row) as days_in_window,
    lag(views, 7) over (order by date) as views_same_day_last_week
from {{ ref('stg_channel_daily') }}
