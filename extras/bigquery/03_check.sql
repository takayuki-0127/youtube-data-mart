-- 答え合わせ（SQL Server 版と同じ値になるか）
SELECT
  (SELECT SUM(views) FROM youtube_mart.channel_daily) AS total_views,          -- 36577
  (SELECT views_ma7 FROM youtube_mart.v_channel_ma7 WHERE date = '2026-10-14') AS ma7_1014,  -- 602.29
  (SELECT views_ma7 FROM youtube_mart.v_channel_ma7 WHERE date = '2026-10-13') AS ma7_1013,  -- 631.71
  (SELECT COUNT(*) FROM youtube_mart.v_channel_ma7) AS n_days;                  -- 93
