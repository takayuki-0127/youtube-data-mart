-- 00_create_database.sql：E 用のデータベースとスキーマを作る（1回だけ実行）
IF DB_ID(N'youtube_data_mart') IS NULL
    CREATE DATABASE youtube_data_mart;
GO
USE youtube_data_mart;
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
GO
IF SCHEMA_ID(N'mart') IS NULL EXEC(N'CREATE SCHEMA mart');
GO
