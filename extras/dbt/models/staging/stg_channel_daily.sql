-- 日別の視聴回数（seed の channel_daily をそのまま型をそろえて出す）
select
    cast(date as date) as date,
    cast(views as {{ dbt.type_int() }}) as views
from {{ ref('channel_daily') }}
