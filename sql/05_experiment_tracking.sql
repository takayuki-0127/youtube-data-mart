-- 05_experiment_tracking.sql：実験1（Shorts に「関連動画」リンクを付ける）の計測ビュー
-- 設計：extras/experiment_01/設計_2026-10-20.md
-- 区分：前＝2026-09-23〜10-20（直前の4週間）／期間中＝10-21〜11-17（4週間）／後＝11-18 以降／それ以前＝9/22 まで（比較には使わない）
-- 毎週 YouTube Studio の CSV を data/raw に入れ直し、run_load_stg.bat → run_mart_reload.bat を流すと、このビューの数字も更新される
USE youtube_data_mart;
GO

/* ============================================================
   1. mart.v_experiment_tracking：日ごとの区分と、見る指標
   - related_shorts_views：主の指標。流入元「関連のショート動画」（Shorts に付けたリンクから長尺へ）の視聴回数
   - longform_approx_views：副の指標。全体 −「ショート フィード」−「関連のショート動画」で長尺の視聴を近似（e_05 と同じ）
   - watch_hours：チャンネル全体の総再生時間（長尺だけの再生時間は日別の CSV にないので、全体で見る）
   - shorts_posted／longform_posted：その日に公開した本数（比べるときにそろえる）
   ============================================================ */
CREATE OR ALTER VIEW mart.v_experiment_tracking AS
WITH traffic AS (
    SELECT f.date_key,
           SUM(CASE WHEN s.source_name = N'ショート フィード'     THEN f.views ELSE 0 END) AS shorts_feed_views,
           SUM(CASE WHEN s.source_name = N'関連のショート動画'   THEN f.views ELSE 0 END) AS related_shorts_views
    FROM mart.fact_traffic_daily AS f
    JOIN mart.dim_traffic_source AS s ON s.source_key = f.source_key
    GROUP BY f.date_key
),
posted AS (
    SELECT v.published_date_key AS date_key,
           SUM(CASE WHEN ct.content_type = N'Shorts' THEN 1 ELSE 0 END) AS shorts_posted,
           SUM(CASE WHEN ct.content_type = N'長尺'   THEN 1 ELSE 0 END) AS longform_posted
    FROM mart.dim_video AS v
    JOIN mart.dim_content_type AS ct ON ct.content_type_key = v.content_type_key
    WHERE v.published_date_key IS NOT NULL
    GROUP BY v.published_date_key
)
SELECT d.[date],
       CASE WHEN d.[date] <  '2026-09-23' THEN N'それ以前'
            WHEN d.[date] <= '2026-10-20' THEN N'前'
            WHEN d.[date] <= '2026-11-17' THEN N'期間中'
            ELSE N'後' END                                   AS phase,
       d.weekday_name,
       c.views                                               AS total_views,
       COALESCE(t.shorts_feed_views, 0)                      AS shorts_feed_views,
       COALESCE(t.related_shorts_views, 0)                   AS related_shorts_views,
       c.views - COALESCE(t.shorts_feed_views, 0) - COALESCE(t.related_shorts_views, 0) AS longform_approx_views,
       c.watch_hours,
       COALESCE(p.shorts_posted, 0)                          AS shorts_posted,
       COALESCE(p.longform_posted, 0)                        AS longform_posted
FROM mart.fact_channel_daily AS c
JOIN mart.dim_date AS d ON d.date_key = c.date_key
LEFT JOIN traffic AS t ON t.date_key = c.date_key
LEFT JOIN posted  AS p ON p.date_key = c.date_key;
GO

/* ============================================================
   2. mart.v_experiment_summary：区分ごとの1日あたりの平均（前と期間中を並べて見る）
   判断の基準（設計で先に決めたもの）：主の指標が 1日 3回以上になれば「誘導の入口として使える」
   ============================================================ */
CREATE OR ALTER VIEW mart.v_experiment_summary AS
SELECT phase,
       COUNT(*)                                                         AS days,
       MIN([date])                                                      AS first_date,
       MAX([date])                                                      AS last_date,
       CAST(AVG(CAST(related_shorts_views  AS decimal(10, 2))) AS decimal(10, 2)) AS related_shorts_per_day,
       CAST(AVG(CAST(longform_approx_views AS decimal(10, 2))) AS decimal(10, 2)) AS longform_approx_per_day,
       CAST(AVG(CAST(total_views           AS decimal(10, 2))) AS decimal(10, 2)) AS total_views_per_day,
       CAST(AVG(watch_hours)                                    AS decimal(10, 2)) AS watch_hours_per_day,
       SUM(shorts_posted)                                               AS shorts_posted,
       SUM(longform_posted)                                             AS longform_posted
FROM mart.v_experiment_tracking
WHERE phase IN (N'前', N'期間中', N'後')
GROUP BY phase;
GO
