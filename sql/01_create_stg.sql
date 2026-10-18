-- 01_create_stg.sql：stg テーブル（pandas で整えた後の形。CSV 1ファイル = 1テーブル）
-- 型の変換・「合計」行の除去・重複の除去・ID の空白除去は pandas（src/load_stg.py）で済ませてから入れる
-- 取り込みは毎回「全件入れ替え」（TRUNCATE → INSERT）。loaded_at で取り込んだ日時が分かる
USE youtube_data_mart;
GO

DROP TABLE IF EXISTS stg.daily_metrics;
CREATE TABLE stg.daily_metrics (
    report_date        date          NOT NULL,
    views              int           NULL,
    watch_hours        decimal(12,4) NULL,
    avg_view_sec       int           NULL,   -- 「0:10:53」→ 653 秒
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_daily_metrics PRIMARY KEY (report_date)
);

DROP TABLE IF EXISTS stg.daily_subscribers;
CREATE TABLE stg.daily_subscribers (
    report_date        date          NOT NULL,
    subscribers        int           NULL,
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_daily_subscribers PRIMARY KEY (report_date)
);

DROP TABLE IF EXISTS stg.videos;
CREATE TABLE stg.videos (
    video_id           nvarchar(20)  NOT NULL,
    title              nvarchar(400) NULL,
    published_date     date          NULL,   -- 「Aug 17, 2026」→ 2026-08-17（変換できなければ空）
    duration_sec       int           NULL,
    views              int           NULL,
    watch_hours        decimal(12,4) NULL,
    subscribers        int           NULL,
    impressions        int           NULL,
    ctr_pct            decimal(6,2)  NULL,
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_videos PRIMARY KEY (video_id)
);

DROP TABLE IF EXISTS stg.video_daily;
CREATE TABLE stg.video_daily (
    report_date        date          NOT NULL,
    video_id           nvarchar(20)  NOT NULL,
    views              int           NULL,
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_video_daily PRIMARY KEY (report_date, video_id)
);

DROP TABLE IF EXISTS stg.traffic_source_daily;
CREATE TABLE stg.traffic_source_daily (
    report_date        date          NOT NULL,
    source_name        nvarchar(50)  NOT NULL,
    views              int           NULL,
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_traffic_source_daily PRIMARY KEY (report_date, source_name)
);

DROP TABLE IF EXISTS stg.subscription_source_daily;
CREATE TABLE stg.subscription_source_daily (
    report_date        date          NOT NULL,
    sub_source_name    nvarchar(50)  NOT NULL,
    subscribers        int           NULL,
    loaded_at          datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_stg_subscription_source_daily PRIMARY KEY (report_date, sub_source_name)
);
GO
