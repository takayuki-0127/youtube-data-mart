-- 03_load_mart.sql：stg → mart。ディメンション → ファクトの順に入れる
-- 何度流しても同じ結果になるように、最初にファクト → ディメンションの順で全件消す（外部キーがあるので DELETE）
USE youtube_data_mart;
GO
SET NOCOUNT ON;

DELETE FROM mart.fact_video_summary;
DELETE FROM mart.fact_video_daily;
DELETE FROM mart.fact_traffic_daily;
DELETE FROM mart.fact_subscription_daily;
DELETE FROM mart.fact_channel_daily;
DELETE FROM mart.dim_video;
DELETE FROM mart.dim_content_type;
DELETE FROM mart.dim_traffic_source;
DELETE FROM mart.dim_subscription_source;
DELETE FROM mart.dim_date;
-- IDENTITY を 1 から振り直す（毎回同じキーになるように）。作りたてで一度も使っていない表は振り直さない（0 から始まってしまうため）
DECLARE @t sysname;
DECLARE c CURSOR LOCAL FOR SELECT N'mart.' + OBJECT_NAME(object_id) FROM sys.identity_columns
    WHERE OBJECT_SCHEMA_NAME(object_id) = N'mart' AND last_value IS NOT NULL;
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0 BEGIN DBCC CHECKIDENT (@t, RESEED, 0) WITH NO_INFOMSGS; FETCH NEXT FROM c INTO @t; END;
CLOSE c; DEALLOCATE c;
GO

/* ===== 1. dim_date：stg に出てくる日付の最小〜最大を、再帰 CTE で切れ目なく作る ===== */
SET DATEFIRST 1;   -- 週の始まりを月曜にする
DECLARE @from date, @to date;
SELECT @from = MIN(d), @to = MAX(d)
FROM (
    SELECT report_date AS d FROM stg.daily_metrics
    UNION ALL SELECT report_date FROM stg.daily_subscribers
    UNION ALL SELECT report_date FROM stg.video_daily
    UNION ALL SELECT report_date FROM stg.traffic_source_daily
    UNION ALL SELECT report_date FROM stg.subscription_source_daily
    UNION ALL SELECT published_date FROM stg.videos      -- 公開日もディメンションに結びつけたいので含める
) AS x;

WITH holidays AS (   -- 期間内の祝日（2026年）
    SELECT CAST(h AS date) AS hd, n FROM (VALUES
        ('2026-07-20', N'海の日'), ('2026-08-11', N'山の日'), ('2026-09-21', N'敬老の日'),
        ('2026-09-22', N'国民の休日'), ('2026-09-23', N'秋分の日'), ('2026-10-12', N'スポーツの日')
    ) AS v(h, n)
),
cal AS (
    SELECT @from AS d
    UNION ALL
    SELECT DATEADD(day, 1, d) FROM cal WHERE d < @to
)
INSERT INTO mart.dim_date (date_key, [date], [year], [month], month_label, [day], weekday_no, weekday_name,
                           week_start, is_weekend, is_holiday, holiday_name)
SELECT CONVERT(int, FORMAT(c.d, 'yyyyMMdd')),
       c.d, YEAR(c.d), MONTH(c.d), FORMAT(c.d, 'yyyy-MM'), DAY(c.d),
       DATEPART(weekday, c.d),
       SUBSTRING(N'月火水木金土日', DATEPART(weekday, c.d), 1),
       DATEADD(day, 1 - DATEPART(weekday, c.d), c.d),
       CASE WHEN DATEPART(weekday, c.d) >= 6 THEN 1 ELSE 0 END,
       CASE WHEN h.hd IS NOT NULL THEN 1 ELSE 0 END,
       h.n
FROM cal AS c
LEFT JOIN holidays AS h ON h.hd = c.d
OPTION (MAXRECURSION 0);
GO

/* ===== 2. その他のディメンション ===== */
INSERT INTO mart.dim_content_type (content_type, sort_order)
VALUES (N'Shorts', 1), (N'長尺', 2), (N'Live', 3);

-- 種類の判定は 1本目（dbo.v_video）と同じ：長さ0 か タイトルに LIVE → Live、60秒以下 → Shorts、それ以外 → 長尺
INSERT INTO mart.dim_video (video_id, title, published_date, published_date_key, duration_sec, content_type_key)
SELECT v.video_id, v.title, v.published_date, dd.date_key, v.duration_sec, ct.content_type_key
FROM stg.videos AS v
CROSS APPLY (SELECT CASE WHEN v.duration_sec = 0 OR v.title LIKE N'%LIVE%' THEN N'Live'
                         WHEN v.duration_sec <= 60 THEN N'Shorts'
                         ELSE N'長尺' END AS content_type) AS t
JOIN mart.dim_content_type AS ct ON ct.content_type = t.content_type
LEFT JOIN mart.dim_date AS dd ON dd.[date] = v.published_date
ORDER BY v.published_date, v.video_id;

INSERT INTO mart.dim_traffic_source (source_name, source_group)
SELECT s.source_name,
       CASE WHEN s.source_name IN (N'ショート フィード', N'関連のショート動画')        THEN N'ショート'
            WHEN s.source_name IN (N'YouTube 検索', N'ハッシュタグのページ')           THEN N'検索'
            WHEN s.source_name IN (N'ブラウジング機能', N'関連動画', N'通知')          THEN N'おすすめ'
            WHEN s.source_name IN (N'チャンネル ページ', N'再生リスト', N'音声のページ') THEN N'チャンネル内'
            ELSE N'外部・その他' END
FROM (SELECT DISTINCT source_name FROM stg.traffic_source_daily) AS s
ORDER BY s.source_name;

INSERT INTO mart.dim_subscription_source (sub_source_name)
SELECT DISTINCT sub_source_name FROM stg.subscription_source_daily ORDER BY sub_source_name;
GO

/* ===== 3. ファクト（stg と JOIN して代理キーに置き換える） ===== */
-- 日別：日付ディメンションの全日に、視聴（daily_metrics）と登録者（daily_subscribers）を寄せる。行がない日は 0
INSERT INTO mart.fact_channel_daily (date_key, views, watch_hours, avg_view_sec, subscribers_net)
SELECT d.date_key,
       ISNULL(m.views, 0), ISNULL(m.watch_hours, 0), m.avg_view_sec, ISNULL(s.subscribers, 0)
FROM mart.dim_date AS d
LEFT JOIN stg.daily_metrics     AS m ON m.report_date = d.[date]
LEFT JOIN stg.daily_subscribers AS s ON s.report_date = d.[date]
WHERE d.[date] BETWEEN (SELECT MIN(report_date) FROM stg.daily_subscribers)
                   AND (SELECT MAX(report_date) FROM stg.daily_subscribers);

INSERT INTO mart.fact_video_daily (date_key, video_key, views, days_since_publish)
SELECT d.date_key, v.video_key, ISNULL(s.views, 0), DATEDIFF(day, v.published_date, s.report_date)
FROM stg.video_daily AS s
JOIN mart.dim_date  AS d ON d.[date] = s.report_date
JOIN mart.dim_video AS v ON v.video_id = s.video_id;

INSERT INTO mart.fact_traffic_daily (date_key, source_key, views)
SELECT d.date_key, t.source_key, ISNULL(s.views, 0)
FROM stg.traffic_source_daily AS s
JOIN mart.dim_date           AS d ON d.[date] = s.report_date
JOIN mart.dim_traffic_source AS t ON t.source_name = s.source_name;

INSERT INTO mart.fact_subscription_daily (date_key, sub_source_key, subscribers)
SELECT d.date_key, t.sub_source_key, ISNULL(s.subscribers, 0)
FROM stg.subscription_source_daily AS s
JOIN mart.dim_date                AS d ON d.[date] = s.report_date
JOIN mart.dim_subscription_source AS t ON t.sub_source_name = s.sub_source_name;

INSERT INTO mart.fact_video_summary (video_key, views, watch_hours, subscribers, impressions, ctr_pct)
SELECT v.video_key, s.views, s.watch_hours, s.subscribers, s.impressions, s.ctr_pct
FROM stg.videos AS s
JOIN mart.dim_video AS v ON v.video_id = s.video_id;
GO

/* ===== 確認①：ファクトの行数 ＝ stg の行数 ===== */
SELECT N'①行数' AS chk, x.tbl, x.stg_rows, x.mart_rows,
       CASE WHEN x.stg_rows = x.mart_rows THEN N'一致' ELSE N'不一致' END AS result
FROM (
    SELECT N'channel_daily（日付の和集合）' AS tbl,
           (SELECT COUNT(*) FROM (SELECT report_date FROM stg.daily_metrics UNION SELECT report_date FROM stg.daily_subscribers) u) AS stg_rows,
           (SELECT COUNT(*) FROM mart.fact_channel_daily) AS mart_rows
    UNION ALL SELECT N'video_daily', (SELECT COUNT(*) FROM stg.video_daily), (SELECT COUNT(*) FROM mart.fact_video_daily)
    UNION ALL SELECT N'traffic_daily', (SELECT COUNT(*) FROM stg.traffic_source_daily), (SELECT COUNT(*) FROM mart.fact_traffic_daily)
    UNION ALL SELECT N'subscription_daily', (SELECT COUNT(*) FROM stg.subscription_source_daily), (SELECT COUNT(*) FROM mart.fact_subscription_daily)
    UNION ALL SELECT N'video_summary', (SELECT COUNT(*) FROM stg.videos), (SELECT COUNT(*) FROM mart.fact_video_summary)
) AS x;

/* ===== 確認②：合計 ＝ stg の合計 ===== */
SELECT N'②合計' AS chk, x.item, x.stg_sum, x.mart_sum,
       CASE WHEN x.stg_sum = x.mart_sum THEN N'一致' ELSE N'不一致' END AS result
FROM (
    SELECT N'channel 視聴回数' AS item, (SELECT SUM(views) FROM stg.daily_metrics) AS stg_sum, (SELECT SUM(views) FROM mart.fact_channel_daily) AS mart_sum
    UNION ALL SELECT N'channel 登録者', (SELECT SUM(subscribers) FROM stg.daily_subscribers), (SELECT SUM(subscribers_net) FROM mart.fact_channel_daily)
    UNION ALL SELECT N'video_daily 視聴回数', (SELECT SUM(views) FROM stg.video_daily), (SELECT SUM(views) FROM mart.fact_video_daily)
    UNION ALL SELECT N'traffic 視聴回数', (SELECT SUM(views) FROM stg.traffic_source_daily), (SELECT SUM(views) FROM mart.fact_traffic_daily)
    UNION ALL SELECT N'subscription 登録者', (SELECT SUM(subscribers) FROM stg.subscription_source_daily), (SELECT SUM(subscribers) FROM mart.fact_subscription_daily)
    UNION ALL SELECT N'video_summary 視聴回数', (SELECT SUM(views) FROM stg.videos), (SELECT SUM(views) FROM mart.fact_video_summary)
) AS x;

/* ===== 確認③：ディメンションに結びつかない行（LEFT JOIN で NULL）＝ 0件 ===== */
SELECT N'③結びつかない行' AS chk, x.tbl, x.orphan_rows,
       CASE WHEN x.orphan_rows = 0 THEN N'0件' ELSE N'あり' END AS result
FROM (
    SELECT N'stg.video_daily → dim_video' AS tbl, (SELECT COUNT(*) FROM stg.video_daily s LEFT JOIN mart.dim_video v ON v.video_id = s.video_id WHERE v.video_key IS NULL) AS orphan_rows
    UNION ALL SELECT N'stg.video_daily → dim_date', (SELECT COUNT(*) FROM stg.video_daily s LEFT JOIN mart.dim_date d ON d.[date] = s.report_date WHERE d.date_key IS NULL)
    UNION ALL SELECT N'stg.traffic → dim_traffic_source', (SELECT COUNT(*) FROM stg.traffic_source_daily s LEFT JOIN mart.dim_traffic_source t ON t.source_name = s.source_name WHERE t.source_key IS NULL)
    UNION ALL SELECT N'stg.subscription → dim_subscription_source', (SELECT COUNT(*) FROM stg.subscription_source_daily s LEFT JOIN mart.dim_subscription_source t ON t.sub_source_name = s.sub_source_name WHERE t.sub_source_key IS NULL)
    UNION ALL SELECT N'stg.videos → dim_video', (SELECT COUNT(*) FROM stg.videos s LEFT JOIN mart.dim_video v ON v.video_id = s.video_id WHERE v.video_key IS NULL)
    UNION ALL SELECT N'dim_video（公開日あり）→ dim_date', (SELECT COUNT(*) FROM mart.dim_video v LEFT JOIN mart.dim_date d ON d.date_key = v.published_date_key WHERE v.published_date IS NOT NULL AND d.date_key IS NULL)
) AS x;

/* 参考：件数の内訳 */
SELECT N'参考' AS chk, ct.content_type, COUNT(*) AS videos
FROM mart.dim_video v JOIN mart.dim_content_type ct ON ct.content_type_key = v.content_type_key
GROUP BY ct.content_type, ct.sort_order ORDER BY ct.sort_order;
SELECT N'参考 dim_date' AS chk, MIN([date]) AS from_date, MAX([date]) AS to_date, COUNT(*) AS days, SUM(CAST(is_holiday AS int)) AS holidays FROM mart.dim_date;
GO
