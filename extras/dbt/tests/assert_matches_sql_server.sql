-- SQL Server 版と同じ値になるかの答え合わせ。1行でも返ればテスト失敗
with checks as (
    select 'total_views' as item, cast(sum(views) as {{ dbt.type_float() }}) as actual, 36577.0 as expected from {{ ref('v_channel_ma7') }}
    union all
    select 'ma7_1014', max(case when date = cast('2026-10-14' as date) then views_ma7 end), 602.29 from {{ ref('v_channel_ma7') }}
    union all
    select 'ma7_1013', max(case when date = cast('2026-10-13' as date) then views_ma7 end), 631.71 from {{ ref('v_channel_ma7') }}
    union all
    select 'n_days', cast(count(*) as {{ dbt.type_float() }}), 93.0 from {{ ref('v_channel_ma7') }}
)
select * from checks
where actual is null or abs(actual - expected) > 0.005
