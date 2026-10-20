-- 06_data_quality_checks.sql：データ品質のチェック（stg と mart を見比べて、合格／不合格の一覧を出す）
-- 実行の順番：01_create_stg → load_stg.py → 02_create_mart → 03_load_mart → このファイル
-- 実行方法：SSMS で開いて実行、または python src/run_sql.py sql/06_data_quality_checks.sql
-- チェックは5種類：① 行数の一致 ② 主キーの重複 ③ NULL の割合 ④ 日付の欠け ⑤ 合計値の一致
-- 判定：合格／不合格／注意（注意 = mart 側で手当て済みの既知の欠け。数字だけ確かめる）
USE youtube_data_mart;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #dq;
CREATE TABLE #dq (
    no        int IDENTITY(1,1),
    category  nvarchar(20),
    target    nvarchar(80),
    value     decimal(18,4),
    expected  decimal(18,4),
    rule_text nvarchar(40),
    result    nvarchar(10)
);

/* ===== ① 行数の一致（stg → mart で行が増えたり減ったりしていないか） ===== */
-- fact_channel_daily は daily_subscribers の期間の全日を持つ（daily_metrics に行がない日は 0 で埋める）
INSERT INTO #dq (category, target, value, expected, rule_text)
SELECT N'①行数', N'fact_channel_daily = stg.daily_subscribers', (SELECT COUNT(*) FROM mart.fact_channel_daily), (SELECT COUNT(*) FROM stg.daily_subscribers), N'等しい'
UNION ALL SELECT N'①行数', N'fact_video_daily = stg.video_daily', (SELECT COUNT(*) FROM mart.fact_video_daily), (SELECT COUNT(*) FROM stg.video_daily), N'等しい'
UNION ALL SELECT N'①行数', N'fact_traffic_daily = stg.traffic_source_daily', (SELECT COUNT(*) FROM mart.fact_traffic_daily), (SELECT COUNT(*) FROM stg.traffic_source_daily), N'等しい'
UNION ALL SELECT N'①行数', N'fact_subscription_daily = stg.subscription_source_daily', (SELECT COUNT(*) FROM mart.fact_subscription_daily), (SELECT COUNT(*) FROM stg.subscription_source_daily), N'等しい'
UNION ALL SELECT N'①行数', N'fact_video_summary = stg.videos', (SELECT COUNT(*) FROM mart.fact_video_summary), (SELECT COUNT(*) FROM stg.videos), N'等しい'
UNION ALL SELECT N'①行数', N'dim_video = stg.videos', (SELECT COUNT(*) FROM mart.dim_video), (SELECT COUNT(*) FROM stg.videos), N'等しい'
UNION ALL SELECT N'①行数', N'dim_traffic_source = stg の流入元の種類', (SELECT COUNT(*) FROM mart.dim_traffic_source), (SELECT COUNT(DISTINCT source_name) FROM stg.traffic_source_daily), N'等しい'
UNION ALL SELECT N'①行数', N'dim_subscription_source = stg の登録元の種類', (SELECT COUNT(*) FROM mart.dim_subscription_source), (SELECT COUNT(DISTINCT sub_source_name) FROM stg.subscription_source_daily), N'等しい';

/* ===== ② 主キーの重複（同じキーが2行以上ある数。0 なら合格） ===== */
INSERT INTO #dq (category, target, value, expected, rule_text)
SELECT N'②重複', N'stg.daily_metrics (report_date)', (SELECT COUNT(*) FROM (SELECT report_date FROM stg.daily_metrics GROUP BY report_date HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'stg.daily_subscribers (report_date)', (SELECT COUNT(*) FROM (SELECT report_date FROM stg.daily_subscribers GROUP BY report_date HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'stg.videos (video_id)', (SELECT COUNT(*) FROM (SELECT video_id FROM stg.videos GROUP BY video_id HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'stg.video_daily (report_date, video_id)', (SELECT COUNT(*) FROM (SELECT report_date, video_id FROM stg.video_daily GROUP BY report_date, video_id HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'stg.traffic_source_daily (report_date, source_name)', (SELECT COUNT(*) FROM (SELECT report_date, source_name FROM stg.traffic_source_daily GROUP BY report_date, source_name HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'stg.subscription_source_daily (report_date, sub_source_name)', (SELECT COUNT(*) FROM (SELECT report_date, sub_source_name FROM stg.subscription_source_daily GROUP BY report_date, sub_source_name HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'mart.dim_date ([date])', (SELECT COUNT(*) FROM (SELECT [date] FROM mart.dim_date GROUP BY [date] HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'mart.dim_video (video_id)', (SELECT COUNT(*) FROM (SELECT video_id FROM mart.dim_video GROUP BY video_id HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'mart.fact_video_daily (date_key, video_key)', (SELECT COUNT(*) FROM (SELECT date_key, video_key FROM mart.fact_video_daily GROUP BY date_key, video_key HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'mart.fact_traffic_daily (date_key, source_key)', (SELECT COUNT(*) FROM (SELECT date_key, source_key FROM mart.fact_traffic_daily GROUP BY date_key, source_key HAVING COUNT(*) > 1) x), 0, N'等しい'
UNION ALL SELECT N'②重複', N'mart.fact_subscription_daily (date_key, sub_source_key)', (SELECT COUNT(*) FROM (SELECT date_key, sub_source_key FROM mart.fact_subscription_daily GROUP BY date_key, sub_source_key HAVING COUNT(*) > 1) x), 0, N'等しい';

/* ===== ③ NULL の割合（%）。キーと日別の数値は 0%、動画の CSV は YouTube 側で空の欄があるので 5% まで ===== */
INSERT INTO #dq (category, target, value, expected, rule_text)
SELECT N'③NULL', N'stg.daily_metrics.views', (SELECT 100.0 * SUM(CASE WHEN views IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.daily_metrics), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.daily_subscribers.subscribers', (SELECT 100.0 * SUM(CASE WHEN subscribers IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.daily_subscribers), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.video_daily.views', (SELECT 100.0 * SUM(CASE WHEN views IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.video_daily), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.traffic_source_daily.views', (SELECT 100.0 * SUM(CASE WHEN views IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.traffic_source_daily), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.title', (SELECT 100.0 * SUM(CASE WHEN title IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.duration_sec', (SELECT 100.0 * SUM(CASE WHEN duration_sec IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 0, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.published_date', (SELECT 100.0 * SUM(CASE WHEN published_date IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 5, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.views', (SELECT 100.0 * SUM(CASE WHEN views IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 5, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.ctr_pct', (SELECT 100.0 * SUM(CASE WHEN ctr_pct IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 5, N'以下'
UNION ALL SELECT N'③NULL', N'stg.videos.subscribers', (SELECT 100.0 * SUM(CASE WHEN subscribers IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) FROM stg.videos), 5, N'以下';

/* ===== ④ 日付の欠け ===== */
-- dim_date と fact_channel_daily は最小〜最大の全日がそろっているか（行数 = 日数）
INSERT INTO #dq (category, target, value, expected, rule_text)
SELECT N'④日付', N'mart.dim_date：最小〜最大の全日', (SELECT COUNT(*) FROM mart.dim_date), (SELECT DATEDIFF(day, MIN([date]), MAX([date])) + 1 FROM mart.dim_date), N'等しい'
UNION ALL SELECT N'④日付', N'mart.fact_channel_daily：期間の全日',
       (SELECT COUNT(*) FROM mart.fact_channel_daily),
       (SELECT DATEDIFF(day, MIN(d.[date]), MAX(d.[date])) + 1 FROM mart.fact_channel_daily f JOIN mart.dim_date d ON d.date_key = f.date_key), N'等しい'
-- 日別×区分の表は「日数 × 区分の数」の行がそろっているか
UNION ALL SELECT N'④日付', N'stg.video_daily：日数 × 動画数', (SELECT COUNT(*) FROM stg.video_daily),
       (SELECT COUNT(DISTINCT report_date) * COUNT(DISTINCT video_id) FROM stg.video_daily), N'等しい'
UNION ALL SELECT N'④日付', N'stg.traffic_source_daily：日数 × 流入元', (SELECT COUNT(*) FROM stg.traffic_source_daily),
       (SELECT COUNT(DISTINCT report_date) * COUNT(DISTINCT source_name) FROM stg.traffic_source_daily), N'等しい'
UNION ALL SELECT N'④日付', N'stg.subscription_source_daily：日数 × 登録元', (SELECT COUNT(*) FROM stg.subscription_source_daily),
       (SELECT COUNT(DISTINCT report_date) * COUNT(DISTINCT sub_source_name) FROM stg.subscription_source_daily), N'等しい';

-- 既知の欠け：daily_metrics は視聴0回の日（7/14・7/16）に行がない。mart では 0 で埋めているので「注意」として日数だけ出す
INSERT INTO #dq (category, target, value, expected, rule_text, result)
SELECT N'④日付', N'stg.daily_metrics に行がない日（mart で 0 埋め）',
       (SELECT COUNT(*) FROM stg.daily_subscribers s WHERE NOT EXISTS (SELECT 1 FROM stg.daily_metrics m WHERE m.report_date = s.report_date)),
       NULL, N'参考', N'注意';

/* ===== ⑤ 合計値の一致（stg と mart で数字が変わっていないか） ===== */
INSERT INTO #dq (category, target, value, expected, rule_text)
SELECT N'⑤合計', N'視聴回数：fact_channel_daily = stg.daily_metrics', (SELECT SUM(views) FROM mart.fact_channel_daily), (SELECT SUM(views) FROM stg.daily_metrics), N'等しい'
UNION ALL SELECT N'⑤合計', N'総再生時間：fact_channel_daily = stg.daily_metrics', (SELECT SUM(watch_hours) FROM mart.fact_channel_daily), (SELECT SUM(watch_hours) FROM stg.daily_metrics), N'等しい'
UNION ALL SELECT N'⑤合計', N'登録者：fact_channel_daily = stg.daily_subscribers', (SELECT SUM(subscribers_net) FROM mart.fact_channel_daily), (SELECT SUM(subscribers) FROM stg.daily_subscribers), N'等しい'
UNION ALL SELECT N'⑤合計', N'視聴回数：fact_video_daily = stg.video_daily', (SELECT SUM(views) FROM mart.fact_video_daily), (SELECT SUM(views) FROM stg.video_daily), N'等しい'
UNION ALL SELECT N'⑤合計', N'視聴回数：fact_traffic_daily = stg.traffic_source_daily', (SELECT SUM(views) FROM mart.fact_traffic_daily), (SELECT SUM(views) FROM stg.traffic_source_daily), N'等しい'
UNION ALL SELECT N'⑤合計', N'登録者：fact_subscription_daily = stg.subscription_source_daily', (SELECT SUM(subscribers) FROM mart.fact_subscription_daily), (SELECT SUM(subscribers) FROM stg.subscription_source_daily), N'等しい'
UNION ALL SELECT N'⑤合計', N'視聴回数：fact_video_summary = stg.videos', (SELECT SUM(views) FROM mart.fact_video_summary), (SELECT SUM(views) FROM stg.videos), N'等しい'
-- 別の CSV どうし：登録者の日別合計と登録元別の合計は同じになるはず
UNION ALL SELECT N'⑤合計', N'登録者：日別 = 登録元別（別の CSV どうし）', (SELECT SUM(subscribers) FROM stg.daily_subscribers), (SELECT SUM(subscribers) FROM stg.subscription_source_daily), N'等しい';

/* ===== 判定と結果 ===== */
UPDATE #dq
SET result = CASE
        WHEN value IS NULL OR expected IS NULL THEN N'不合格'
        WHEN rule_text = N'等しい' AND value = expected THEN N'合格'
        WHEN rule_text = N'以下'   AND value <= expected THEN N'合格'
        ELSE N'不合格' END
WHERE result IS NULL;

SELECT no, category AS 種類, target AS チェック, CAST(value AS decimal(18,2)) AS 値,
       CAST(expected AS decimal(18,2)) AS 基準, rule_text AS 条件, result AS 判定
FROM #dq ORDER BY no;

SELECT COUNT(*) AS チェック数,
       SUM(CASE WHEN result = N'合格'   THEN 1 ELSE 0 END) AS 合格,
       SUM(CASE WHEN result = N'不合格' THEN 1 ELSE 0 END) AS 不合格,
       SUM(CASE WHEN result = N'注意'   THEN 1 ELSE 0 END) AS 注意
FROM #dq;
GO
