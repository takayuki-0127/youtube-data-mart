-- 02_create_mart.sql：mart のテーブル（スタースキーマ）を作る
-- ディメンション：代理キー（INT IDENTITY）を主キーにし、元の ID（業務キー）は UNIQUE にする
-- ファクト：ディメンションの代理キーを外部キーに持つ
USE youtube_data_mart;
GO

-- 外部キーがあるので、ファクト → ディメンションの順に消す
DROP TABLE IF EXISTS mart.fact_video_summary;
DROP TABLE IF EXISTS mart.fact_video_daily;
DROP TABLE IF EXISTS mart.fact_traffic_daily;
DROP TABLE IF EXISTS mart.fact_subscription_daily;
DROP TABLE IF EXISTS mart.fact_channel_daily;
DROP TABLE IF EXISTS mart.dim_video;
DROP TABLE IF EXISTS mart.dim_content_type;
DROP TABLE IF EXISTS mart.dim_traffic_source;
DROP TABLE IF EXISTS mart.dim_subscription_source;
DROP TABLE IF EXISTS mart.dim_date;
GO

/* ---------- ディメンション ---------- */
CREATE TABLE mart.dim_date (
    date_key        int          NOT NULL,          -- 20260714（日付から作るので IDENTITY ではなくスマートキー）
    [date]          date         NOT NULL,
    [year]          smallint     NOT NULL,
    [month]         tinyint      NOT NULL,
    month_label     char(7)      NOT NULL,          -- 2026-07
    [day]           tinyint      NOT NULL,
    weekday_no      tinyint      NOT NULL,          -- 1=月 … 7=日
    weekday_name    nchar(1)     NOT NULL,          -- 月・火 …
    week_start      date         NOT NULL,          -- その週の月曜日
    is_weekend      bit          NOT NULL,
    is_holiday      bit          NOT NULL,          -- 祝日（土日は含めない）
    holiday_name    nvarchar(20) NULL,
    CONSTRAINT PK_dim_date PRIMARY KEY (date_key),
    CONSTRAINT UQ_dim_date_date UNIQUE ([date])
);

CREATE TABLE mart.dim_content_type (
    content_type_key   int IDENTITY(1,1) NOT NULL,
    content_type       nvarchar(10)      NOT NULL,  -- Shorts／長尺／Live
    sort_order         tinyint           NOT NULL,
    CONSTRAINT PK_dim_content_type PRIMARY KEY (content_type_key),
    CONSTRAINT UQ_dim_content_type UNIQUE (content_type)
);

CREATE TABLE mart.dim_video (
    video_key          int IDENTITY(1,1) NOT NULL,
    video_id           nvarchar(20)      NOT NULL,  -- 業務キー
    title              nvarchar(400)     NULL,
    published_date     date              NULL,
    published_date_key int               NULL,
    duration_sec       int               NULL,
    content_type_key   int               NOT NULL,
    CONSTRAINT PK_dim_video PRIMARY KEY (video_key),
    CONSTRAINT UQ_dim_video_video_id UNIQUE (video_id),
    CONSTRAINT FK_dim_video_content_type FOREIGN KEY (content_type_key) REFERENCES mart.dim_content_type (content_type_key),
    CONSTRAINT FK_dim_video_published FOREIGN KEY (published_date_key) REFERENCES mart.dim_date (date_key)
);

CREATE TABLE mart.dim_traffic_source (
    source_key      int IDENTITY(1,1) NOT NULL,
    source_name     nvarchar(50)      NOT NULL,     -- 業務キー
    source_group    nvarchar(20)      NOT NULL,     -- ショート／検索／おすすめ／チャンネル内／外部・その他
    CONSTRAINT PK_dim_traffic_source PRIMARY KEY (source_key),
    CONSTRAINT UQ_dim_traffic_source UNIQUE (source_name)
);

CREATE TABLE mart.dim_subscription_source (
    sub_source_key  int IDENTITY(1,1) NOT NULL,
    sub_source_name nvarchar(50)      NOT NULL,     -- 業務キー
    CONSTRAINT PK_dim_subscription_source PRIMARY KEY (sub_source_key),
    CONSTRAINT UQ_dim_subscription_source UNIQUE (sub_source_name)
);
GO

/* ---------- ファクト ---------- */
CREATE TABLE mart.fact_channel_daily (            -- 粒度：日
    date_key        int           NOT NULL,
    views           int           NOT NULL,         -- 行がない日（7/14・7/16）は 0
    watch_hours     decimal(12,4) NOT NULL,
    avg_view_sec    int           NULL,
    subscribers_net int           NOT NULL,
    CONSTRAINT PK_fact_channel_daily PRIMARY KEY (date_key),
    CONSTRAINT FK_fact_channel_daily_date FOREIGN KEY (date_key) REFERENCES mart.dim_date (date_key)
);

CREATE TABLE mart.fact_video_daily (              -- 粒度：動画×日（上位24本）
    date_key           int NOT NULL,
    video_key          int NOT NULL,
    views              int NOT NULL,
    days_since_publish int NULL,
    CONSTRAINT PK_fact_video_daily PRIMARY KEY (date_key, video_key),
    CONSTRAINT FK_fact_video_daily_date  FOREIGN KEY (date_key)  REFERENCES mart.dim_date (date_key),
    CONSTRAINT FK_fact_video_daily_video FOREIGN KEY (video_key) REFERENCES mart.dim_video (video_key)
);

CREATE TABLE mart.fact_traffic_daily (            -- 粒度：流入元×日
    date_key   int NOT NULL,
    source_key int NOT NULL,
    views      int NOT NULL,
    CONSTRAINT PK_fact_traffic_daily PRIMARY KEY (date_key, source_key),
    CONSTRAINT FK_fact_traffic_daily_date   FOREIGN KEY (date_key)   REFERENCES mart.dim_date (date_key),
    CONSTRAINT FK_fact_traffic_daily_source FOREIGN KEY (source_key) REFERENCES mart.dim_traffic_source (source_key)
);

CREATE TABLE mart.fact_subscription_daily (       -- 粒度：登録元×日
    date_key       int NOT NULL,
    sub_source_key int NOT NULL,
    subscribers    int NOT NULL,
    CONSTRAINT PK_fact_subscription_daily PRIMARY KEY (date_key, sub_source_key),
    CONSTRAINT FK_fact_subscription_daily_date   FOREIGN KEY (date_key)       REFERENCES mart.dim_date (date_key),
    CONSTRAINT FK_fact_subscription_daily_source FOREIGN KEY (sub_source_key) REFERENCES mart.dim_subscription_source (sub_source_key)
);

CREATE TABLE mart.fact_video_summary (            -- 粒度：動画（期間合計）
    video_key    int           NOT NULL,
    views        int           NULL,               -- CSV で空の 9 本は NULL のまま（0 回と区別する）
    watch_hours  decimal(12,4) NULL,
    subscribers  int           NULL,
    impressions  int           NULL,
    ctr_pct      decimal(6,2)  NULL,
    CONSTRAINT PK_fact_video_summary PRIMARY KEY (video_key),
    CONSTRAINT FK_fact_video_summary_video FOREIGN KEY (video_key) REFERENCES mart.dim_video (video_key)
);
GO
