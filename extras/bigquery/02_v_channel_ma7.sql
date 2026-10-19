-- BigQuery 版 v_channel_ma7（元：sql/04_views.sql の SQL Server 版）
-- 日別の視聴回数と 7日移動平均・前週同曜日の値（ウィンドウ関数）
-- 答え合わせ：10/14 = 602.29、10/13 = 631.71、93日の合計 = 36,577（SQL Server 版と同じ）
CREATE OR REPLACE VIEW youtube_mart.v_channel_ma7 AS
SELECT
  date,
  FORMAT_DATE('%a', date) AS weekday_name,
  views,
  ROUND(AVG(views) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS views_ma7,
  COUNT(*) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS days_in_window,
  LAG(views, 7) OVER (ORDER BY date) AS views_same_day_last_week
FROM youtube_mart.channel_daily;
