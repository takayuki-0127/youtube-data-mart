-- 04_views.sql：mart のテーブルから作るビュー3本 ＋ 要因分析用のビュー
USE youtube_data_mart;
GO

/* ============================================================
   1. mart.v_channel_ma7：日別の視聴回数と7日移動平均（AVG OVER）
   fact_channel_daily は視聴0回の日も行がある（0埋め済み）ので、「7行」＝「7日」になる
   答え合わせ：10/14 = 602.29、10/13 = 631.71、93日の合計 = 36,577
   ============================================================ */
CREATE OR ALTER VIEW mart.v_channel_ma7 AS
WITH daily AS (
    SELECT d.[date], d.weekday_name, f.views
    FROM mart.fact_channel_daily AS f
    JOIN mart.dim_date AS d ON d.date_key = f.date_key
)
SELECT [date], weekday_name, views,
       CAST(AVG(CAST(views AS decimal(10, 2))) OVER (
            ORDER BY [date] ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS decimal(10, 2)) AS views_ma7,
       COUNT(*) OVER (ORDER BY [date] ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)          AS days_in_window,
       LAG(views, 7) OVER (ORDER BY [date])                                               AS views_same_day_last_week
FROM daily;
GO

/* ============================================================
   2. mart.v_channel_weekly_wow：週（月曜始まり）ごとの視聴回数と前週比（CTE ＋ LAG）
   答え合わせ：週の合計を全部足すと 36,577
   ============================================================ */
CREATE OR ALTER VIEW mart.v_channel_weekly_wow AS
WITH weekly AS (
    SELECT d.week_start,
           COUNT(*)      AS days_in_week,
           SUM(f.views)  AS views,
           SUM(f.subscribers_net) AS subscribers_net
    FROM mart.fact_channel_daily AS f
    JOIN mart.dim_date AS d ON d.date_key = f.date_key
    GROUP BY d.week_start
)
SELECT week_start, days_in_week, views, subscribers_net,
       LAG(views) OVER (ORDER BY week_start) AS views_prev_week,
       CAST((views - LAG(views) OVER (ORDER BY week_start)) * 100.0
            / NULLIF(LAG(views) OVER (ORDER BY week_start), 0) AS decimal(8, 1)) AS wow_pct
FROM weekly;
GO

/* ============================================================
   3. mart.v_video_rank_first7：公開7日間の視聴回数を種類ごとに順位付け（CTE ＋ SUM OVER ＋ ROW_NUMBER）
   日別データ（fact_video_daily）は上位24本だけ。7日分そろう 10/8 公開までを対象
   答え合わせ：Shorts 1位 "They Are In for the Night" 945回（初日354・37.5%）
   ============================================================ */
CREATE OR ALTER VIEW mart.v_video_rank_first7 AS
WITH first7 AS (
    SELECT v.video_key, v.title, ct.content_type, v.published_date,
           f.days_since_publish, f.views
    FROM mart.fact_video_daily AS f
    JOIN mart.dim_video        AS v  ON v.video_key = f.video_key
    JOIN mart.dim_content_type AS ct ON ct.content_type_key = v.content_type_key
    WHERE v.published_date <= '2026-10-08'
      AND f.days_since_publish BETWEEN 0 AND 6
),
summary AS (
    SELECT video_key, title, content_type, published_date,
           SUM(CASE WHEN days_since_publish = 0 THEN views ELSE 0 END) AS day1_views,
           SUM(views) AS first7_views
    FROM first7
    GROUP BY video_key, title, content_type, published_date
)
SELECT content_type,
       ROW_NUMBER() OVER (PARTITION BY content_type ORDER BY first7_views DESC, published_date) AS rank_in_type,
       title, published_date, day1_views, first7_views,
       CAST(day1_views * 100.0 / NULLIF(first7_views, 0) AS decimal(5, 1)) AS day1_share_pct
FROM summary;
GO

/* ============================================================
   4. mart.v_video_features：要因分析（重回帰）用。1行＝1動画（Live を除く）
   目的変数：views（期間合計。分析側で log(1+views)）
     ※ 公開7日間の視聴回数は日別データが上位24本しかないため、first7_views は参考列（24本以外は NULL）
   説明変数：is_short・duration_sec・publish_weekday・is_weekend_publish・is_holiday_publish・days_since_publish・ctr_pct
     ※ YouTube Studio の CSV に公開時刻（時間帯）はないので入れていない
   答え合わせ：339行（Live 3本を除く）→ 公開日と視聴回数がある行は 329行
   ============================================================ */
CREATE OR ALTER VIEW mart.v_video_features AS
WITH f7 AS (
    SELECT video_key, SUM(views) AS first7_views
    FROM mart.fact_video_daily
    WHERE days_since_publish BETWEEN 0 AND 6
    GROUP BY video_key
)
SELECT v.video_id,
       v.title,
       ct.content_type,
       CASE WHEN ct.content_type = N'Shorts' THEN 1 ELSE 0 END             AS is_short,
       v.duration_sec,
       v.published_date,
       d.weekday_no                                                      AS publish_weekday,
       CAST(d.is_weekend AS int)                                         AS is_weekend_publish,
       CAST(d.is_holiday AS int)                                         AS is_holiday_publish,
       DATEDIFF(day, v.published_date, '2026-10-15')                     AS days_since_publish,
       s.impressions,
       s.ctr_pct,
       s.subscribers,
       s.views,
       f7.first7_views
FROM mart.dim_video AS v
JOIN mart.dim_content_type   AS ct ON ct.content_type_key = v.content_type_key
JOIN mart.fact_video_summary AS s  ON s.video_key = v.video_key
LEFT JOIN mart.dim_date      AS d  ON d.date_key = v.published_date_key
LEFT JOIN f7                       ON f7.video_key = v.video_key
WHERE ct.content_type <> N'Live';
GO

/* ===== 答え合わせ ===== */
SELECT N'1. ma7' AS chk, [date], views, views_ma7, days_in_window FROM mart.v_channel_ma7 WHERE [date] IN ('2026-10-13', '2026-10-14');
SELECT N'1. ma7 合計' AS chk, COUNT(*) AS days, SUM(views) AS views_sum FROM mart.v_channel_ma7;
SELECT N'2. weekly 合計' AS chk, COUNT(*) AS weeks, SUM(views) AS views_sum FROM mart.v_channel_weekly_wow;
SELECT N'2. weekly 最後の3週' AS chk, * FROM (SELECT TOP 3 * FROM mart.v_channel_weekly_wow ORDER BY week_start DESC) t ORDER BY week_start;
SELECT N'3. first7 各1位' AS chk, content_type, rank_in_type, title, day1_views, first7_views, day1_share_pct FROM mart.v_video_rank_first7 WHERE rank_in_type = 1;
SELECT N'4. features' AS chk, COUNT(*) AS rows_all,
       SUM(CASE WHEN published_date IS NOT NULL AND views IS NOT NULL THEN 1 ELSE 0 END) AS rows_usable,
       SUM(CASE WHEN published_date IS NULL THEN 1 ELSE 0 END) AS miss_published,
       SUM(CASE WHEN views IS NULL THEN 1 ELSE 0 END) AS miss_views,
       SUM(CASE WHEN ctr_pct IS NULL THEN 1 ELSE 0 END) AS miss_ctr,
       SUM(CASE WHEN subscribers IS NULL THEN 1 ELSE 0 END) AS miss_subs,
       SUM(is_short) AS shorts
FROM mart.v_video_features;
GO
