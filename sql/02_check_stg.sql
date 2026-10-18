-- 02_check_stg.sql：取り込んだ件数と合計が CSV と一致するか確認する
-- 期待値（CSV 側）は src/load_stg.py の実行ログに出る
USE youtube_data_mart;
GO
SELECT 'daily_metrics'  AS tbl, COUNT(*) AS rows, SUM(views) AS views_sum FROM stg.daily_metrics
UNION ALL SELECT 'daily_subscribers', COUNT(*), SUM(subscribers) FROM stg.daily_subscribers
UNION ALL SELECT 'videos', COUNT(*), SUM(views) FROM stg.videos
UNION ALL SELECT 'video_daily', COUNT(*), SUM(views) FROM stg.video_daily
UNION ALL SELECT 'traffic_source_daily', COUNT(*), SUM(views) FROM stg.traffic_source_daily
UNION ALL SELECT 'subscription_source_daily', COUNT(*), SUM(subscribers) FROM stg.subscription_source_daily;
GO
