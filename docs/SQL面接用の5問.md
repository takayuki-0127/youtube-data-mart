# SQL 面接用の5問（youtube_data_mart）

このリポジトリの mart を使って、自分で出して解いた5問です。各問に「何を確かめたいクエリか」と、答え（2026-07-14〜10-14 の CSV で確認した値）を付けています。
（答えは同じロジックを DuckDB でも流して確かめた値。クエリは SQL Server 用）

### Q1. 視聴回数が「前日より増えた日」が続いた最長の日数（gaps and islands）
何を確かめたいか：伸びが一時的か、何日も続く波があるか
```sql
WITH d AS (
    SELECT dd.[date], f.views,
           f.views - LAG(f.views) OVER (ORDER BY dd.[date]) AS diff
    FROM mart.fact_channel_daily AS f
    JOIN mart.dim_date AS dd ON dd.date_key = f.date_key
),
up AS (   -- 増えた日だけに番号をふる
    SELECT [date], ROW_NUMBER() OVER (ORDER BY [date]) AS rn
    FROM d WHERE diff > 0
),
grp AS (  -- 連続した日は「日付 − 番号」が同じ値になる
    SELECT [date], DATEADD(day, -CAST(rn AS int), [date]) AS g FROM up
)
SELECT TOP (3) MIN([date]) AS start_date, MAX([date]) AS end_date, COUNT(*) AS days
FROM grp GROUP BY g
ORDER BY days DESC, start_date;
```
答え：最長 **3日**（7/17〜7/19、8/17〜8/19、9/10〜9/12 の3回）→ 伸びは長く続かず、投稿直後の単発の山が中心

### Q2. 前週比で伸びた動画の上位5本
何を確かめたいか：直近で勢いが出た動画（季節もの・おすすめに乗ったもの）を見つける
```sql
WITH w AS (
    SELECT f.video_key, dd.week_start, SUM(f.views) AS views
    FROM mart.fact_video_daily AS f
    JOIN mart.dim_date AS dd ON dd.date_key = f.date_key
    GROUP BY f.video_key, dd.week_start
),
x AS (
    SELECT video_key, week_start, views,
           LAG(views) OVER (PARTITION BY video_key ORDER BY week_start) AS prev_views
    FROM w
)
SELECT TOP (5) v.title, ct.content_type, x.prev_views, x.views,
       x.views - x.prev_views AS diff,
       CAST((x.views - x.prev_views) * 100.0 / NULLIF(x.prev_views, 0) AS decimal(8, 1)) AS wow_pct
FROM x
JOIN mart.dim_video        AS v  ON v.video_key = x.video_key
JOIN mart.dim_content_type AS ct ON ct.content_type_key = v.content_type_key
WHERE x.week_start = '2026-10-05' AND x.prev_views >= 5      -- 前週が少なすぎる動画は外す
ORDER BY wow_pct DESC;
```
答え（10/5 週 vs 9/28 週）：1位 暖炉×雪の長尺 14→131回（+836%）、2位 クリスマスマーケットの長尺 13→20回（+54%）。前週5回以上は5本しかなく、3〜5位はマイナス → **クリスマス系の長尺が10月から動き始めた**

### Q3. 上位20%の動画が全体の視聴の何%を占めるか（パレート）
何を確かめたいか：一部のヒットに頼っているか、広く見られているか
```sql
WITH r AS (
    SELECT views,
           ROW_NUMBER() OVER (ORDER BY views DESC, video_key) AS rn,
           COUNT(*)     OVER ()                                AS n,
           SUM(views)   OVER (ORDER BY views DESC, video_key ROWS UNBOUNDED PRECEDING) AS cum_views,
           SUM(views)   OVER ()                                AS total_views
    FROM mart.fact_video_summary
    WHERE views IS NOT NULL                -- 視聴回数が空の 9 本は除く
)
SELECT MAX(n) AS videos,
       MAX(CASE WHEN rn <= CEILING(n * 0.2) THEN rn END) AS top20_videos,
       CAST(MAX(CASE WHEN rn <= CEILING(n * 0.2) THEN cum_views END) * 100.0 / MAX(total_views) AS decimal(5, 1)) AS top20_share_pct,
       MIN(CASE WHEN cum_views * 1.0 / total_views >= 0.8 THEN rn END) AS videos_for_80pct
FROM r;
```
答え：333本のうち上位67本（20%）で **69.8%**。80%に届くのは上位101本（約30%）→ 典型的な「8割」よりは分散している

### Q4. 種類（Shorts／長尺／Live）ごとの視聴回数の中央値
何を確かめたいか：平均は一部のヒットに引っぱられるので、中央値で「ふつうの1本」を比べる
```sql
SELECT DISTINCT ct.content_type,
       COUNT(*) OVER (PARTITION BY ct.content_type) AS videos,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.views) OVER (PARTITION BY ct.content_type) AS median_views,
       AVG(CAST(s.views AS decimal(10, 1)))  OVER (PARTITION BY ct.content_type) AS avg_views
FROM mart.fact_video_summary AS s
JOIN mart.dim_video          AS v  ON v.video_key = s.video_key
JOIN mart.dim_content_type   AS ct ON ct.content_type_key = v.content_type_key
WHERE s.views IS NOT NULL;
```
答え：Shorts 中央値 **87回**（平均 162）／長尺 **12回**（平均 33）／Live 90回（3本だけ）→ 平均と中央値の差が大きく、どちらも少数のヒットが平均を押し上げている
- SQL Server の PERCENTILE_CONT は分析関数（OVER が必須）なので、GROUP BY ではなく DISTINCT で1行にまとめる、が聞かれやすいポイント

### Q5. 重複を除いて、動画×日ごとに最新の取り込み1件だけ残す（ROW_NUMBER）
何を確かめたいか：同じ CSV を2回取り込んだ・後から数字が修正された、ときに最新の値だけを使う
- stg.video_daily は「全件入れ替え＋主キー（report_date, video_id）」なので重複は入らない。ここでは取り込みごとに積む履歴テーブル stg.video_daily_hist（同じ列＋loaded_at、主キーなし）がある想定
```sql
-- 見るだけ（最新の1件）
WITH r AS (
    SELECT report_date, video_id, views, loaded_at,
           ROW_NUMBER() OVER (PARTITION BY video_id, report_date ORDER BY loaded_at DESC) AS rn
    FROM stg.video_daily_hist
)
SELECT report_date, video_id, views, loaded_at
FROM r WHERE rn = 1;

-- 消す場合（CTE 経由で DELETE できるのが SQL Server の特徴）
WITH r AS (
    SELECT ROW_NUMBER() OVER (PARTITION BY video_id, report_date ORDER BY loaded_at DESC) AS rn
    FROM stg.video_daily_hist
)
DELETE FROM r WHERE rn > 1;
```
答え（確かめ方）：2,232行に、2回目の取り込みで300行を重ねた 2,532行で流すと、残るのは 2,232行・消えるのは300行（2回目の新しい値が残る）
- DISTINCT ではなく ROW_NUMBER を使う理由：値が違う重複（修正後の数字）は DISTINCT では消えない。「どれを残すか」を ORDER BY で決められる
