# E ポートフォリオ2本目：設計（2026-10-17 たたき台 → 10/18 確定）

最終ゴールはデータサイエンティスト。1社目はその入り口（データアナリスト／BI／データエンジニア）。
2本目は「ETL とデータマート設計」に加えて、最後に「要因分析（回帰）」を1つ入れる。

## 1. 使うデータ（決めること）
| 候補 | よいところ | 気になるところ |
|---|---|---|
| **YouTube データ（おすすめ）** | 1本目で使っていない CSV が多い（流入元の日別・登録元の日別・動画ごとのインプレッションとクリック率）。342本あるので回帰ができる。自分のデータなので GitHub で公開できる | 1本目と同じ題材に見える → 「複数ファイルの ETL ＋ データマート ＋ 要因分析」で中身を変える |
| SNS 集計データ（匿名化済み） | 実務に近い。B と同じ題材で「業務の ETL」を見せやすい | 16本×3媒体で行数が少なく、回帰には向かない。公開にはクライアントの了承が要る |

### 3点で比べた結果（10/18）
| 観点 | YouTube | 匿名化した SNS |
|---|---|---|
| ① 今すぐ GitHub で公開できるか | ○ 自分のデータ（タイトル・チャンネル名も公開してよい） | × クライアントの了承待ち |
| ② RLS を入れる理由が自然か | △ 「Shorts担当／長尺担当」で分ける（1人運営なので想定の話になる） | ○ 「クライアントごとに自分の分だけ見せる」は実務そのもの |
| ③ 重回帰の目的変数と説明変数がそろうか | ○ 動画342本。視聴回数・長さ・公開日・インプレッション・クリック率がそろう | × 16本×3媒体で行が少ない |

**決定：YouTube データを使う。**
理由：今すぐ公開できて（①）、342本あるので重回帰が成り立つ（③）。RLS は「担当者ごとに見る範囲を分ける」想定として README に書き、実務で SNS のクライアント別 RLS を作った経験は面接で話す。

## 2. 流れの図（YouTube データの場合）
```
[1 元データ]                [2 取り込み]                 [3 stg]                  [4 mart]                        [5 Power BI]
YouTube Studio の CSV  →  pandas                   →  SQL Server stg      →  SQL Server mart            →  Power Query → スタースキーマ → レポート
 7ファイル                  列名を英語にそろえる          CSV と同じ形のまま       ファクト・ディメンション         RLS（Shorts担当／長尺担当）
                            「合計」行を外す              取り込み日時の列を足す    ビュー（CTE・ウィンドウ関数）
                            型の変換（日付・数値）                                                                [6 要因分析]
                            動画IDの空白を消す                                                                    pandas / scikit-learn
                                                                                                                  mart から読んで回帰
```
矢印の上に書くこと
- 1→2：「合計」行を外す／列名をそろえる／日付・数値に型変換／ID の空白を消す（1本目でつまずいた所をコードで再現）
- 2→3：そのまま入れる（pandas の `to_sql` か BULK INSERT）。件数と合計を CSV と突き合わせる
- 3→4：ID 化、種類（Shorts／長尺／Live）の判定、公開後日数、週の開始日、前週比、7日移動平均
- 4→5：mart のビューだけを読む
- 4→6：動画単位の表（説明変数と視聴回数）を読み、回帰で「何が効いているか」を見る

## 3. 元データ（CSV）
| ファイル | 1行の単位 | 主な列 |
|---|---|---|
| daily_metrics | 日 | 日付・視聴回数・総再生時間・平均視聴時間 |
| daily_subscribers | 日 | 日付・登録者の増減 |
| videos | 動画 | 動画ID・タイトル・公開日・長さ・視聴回数・総再生時間・登録者・インプレッション・クリック率 |
| video_daily_views | 動画×日（上位24本） | 日付・動画ID・視聴回数 |
| traffic_source_daily | 流入元×日 | 日付・流入元・視聴回数 |
| subscription_source_daily | 登録元×日 | 日付・登録元・登録者 |
| top5_daily_subscribers | 動画×日（上位5本） | 日付・動画ID・登録者 |

## 4. stg スキーマ（CSV と同じ形）
- stg.daily_metrics／stg.daily_subscribers／stg.videos／stg.video_daily／stg.traffic_source_daily／stg.subscription_source_daily
- 全テーブル共通で `loaded_at datetime2` を足す（いつ取り込んだか）
- 型は pandas で変換して入れる（変換できない値は空にして落とさない）

## 5. mart スキーマ（テーブルと列）
### ディメンション
| テーブル | 列（型） | キー |
|---|---|---|
| dim_date | date_key int（20260714）・date date・week_start date・month nvarchar(7)・weekday tinyint | PK date_key |
| dim_video | video_key int・video_id nvarchar(20)・title nvarchar(200)・published_date date・duration_sec int・content_type nvarchar(10)（Shorts／長尺／Live）・publish_weekday tinyint | PK video_key |
| dim_traffic_source | source_key int・source_name nvarchar(50)・source_group nvarchar(20)（ショート／検索／おすすめ／外部 など） | PK source_key |
| dim_subscription_source | sub_source_key int・sub_source_name nvarchar(50) | PK sub_source_key |

### ファクト
| テーブル | 1行の単位 | 列（型） | キー |
|---|---|---|---|
| fact_channel_daily | 日 | date_key・views int・watch_hours decimal(10,4)・avg_view_sec int・subscribers_net int | FK date_key |
| fact_video_daily | 動画×日 | date_key・video_key・views int・days_since_publish int | FK date_key, video_key |
| fact_traffic_daily | 流入元×日 | date_key・source_key・views int | FK date_key, source_key |
| fact_subscription_daily | 登録元×日 | date_key・sub_source_key・subscribers int | FK date_key, sub_source_key |
| fact_video_summary | 動画（期間合計） | video_key・views・watch_hours・subscribers・impressions・ctr_pct | FK video_key |

### stg → mart で変えること（1行ずつ）
- dim_date：期間の全日を作る（視聴0回の日も行を作る → 7日移動平均が「7行」ではなく「7日」になる）
- dim_video：英語の公開日を date に、長さと LIVE の文字で種類を判定、ID の空白を消す
- dim_traffic_source：流入元の名前をグループにまとめる
- fact_*：名前を ID に置き換える、空欄は 0、「合計」行は入れない、公開後日数を計算

## 6. mart のビュー（SQL）
| ビュー | 中身 | 使う構文 |
|---|---|---|
| v_channel_weekly_wow | 週ごとの視聴回数と前週比 | CTE・LAG |
| v_channel_ma7 | 日別の視聴回数と7日移動平均（0の日を含む） | AVG() OVER (ROWS 6 PRECEDING) |
| v_traffic_share_weekly | 週ごとの流入元の割合（ショートフィードが何割か） | SUM() OVER (PARTITION BY 週) |
| v_video_rank_first7 | 公開7日間の視聴回数の種類別ランキング | ROW_NUMBER() OVER (PARTITION BY 種類) |
| v_video_features | 回帰に使う動画単位の表（種類・長さ・公開曜日・公開からの日数・インプレッション・クリック率・視聴回数） | JOIN |

## 7. Power BI
- mart のビューとテーブルだけを読む（Power Query の処理は最小限）
- ページ案：①チャンネル全体（7日移動平均・前週比）②流入元の推移（ショートフィードの割合）③動画（種類別・公開7日間）④要因分析の結果（係数の棒グラフ）
- RLS：「Shorts担当」「長尺担当」（dim_video[content_type] で絞る）

## 8. 要因分析（データサイエンティスト寄りの要素）
- 問い：動画の視聴回数に何が効いているか（「Shorts は入口、長尺は本体」を数字で確かめる）
- 目的変数：視聴回数（偏りが大きいので log(1+視聴回数)）
- 説明変数：種類（Shorts／長尺）・公開からの日数・公開曜日・インプレッション・クリック率
- 方法：pandas ＋ statsmodels の重回帰（係数と p 値を見る）→ scikit-learn で同じ回帰を書き、学習データと検証データに分けて当てはまりを見る
- 注意：インプレッションは視聴回数とほぼ同時に決まる（結果に近い）ので、入れる版と入れない版を比べる
- 統計検定2級の知識（回帰係数・決定係数・p 値）をここで見せる

## 9. GitHub（予定）
- リポジトリ名案：youtube-data-mart（公開）
- フォルダ：`etl/`（pandas の取り込み）・`sql/stg`・`sql/mart`・`analysis/`（回帰のノートブック）・`images/`・README（流れの図・テーブル一覧・答え合わせ・回帰の結果）
- 元の CSV は入れない

## 10. 作る順番（2〜3月）
1. pandas で7ファイルを読み、整えて stg に入れる（件数と合計を CSV と突き合わせる）
2. mart のテーブルを作る（dim → fact の順）
3. ビュー5本を書き、1本目と同じ数字（36,577回・10/14 の7日移動平均 602.29。dim_date は0の日も含めて93日）が出るか確認
4. Power BI で mart を読んでレポート、RLS
5. 要因分析（statsmodels → scikit-learn）
6. README と GitHub 公開、note 2本目


---
# 10/18 確定版（テーブル・ビュー・要因分析）

## A. 元データの実際（data/raw の CSV を確認した結果）
- videos.csv：342本（＋先頭に「合計」行）。公開日が空 6本、視聴回数が空 9本、クリック率が空 4本
- 種類は1本目（dbo.v_video）と同じ判定：長さ0 か タイトルに LIVE → Live、60秒以下 → Shorts、それ以外 → 長尺（Shorts 201・長尺 138・Live 3）
- インプレッションは長尺の方がずっと多い（中央値 168 vs 21）＝ Shorts はショートフィード経由でサムネイルを通らない
- video_daily_views.csv は上位24本だけ（全動画の日別ではない）。先頭に BOM あり

## B. stg（CSV 1ファイル＝1テーブル。型は pandas で変換してから入れる）
- 10/18 変更：最初は「stg は nvarchar のまま」の案だったが、pandas で型変換まで済ませる流れにしたので、stg も date・int・decimal の型を持たせる。DDL は youtube-data-mart\sql\01_create_stg.sql（データベースは youtube_data_mart。1本目の youtube_dashboard とは分ける）
| テーブル | 列（型） | キー | pandas で整えること（1行ずつ） |
|---|---|---|---|
| stg.daily_metrics | report_date nvarchar(10)・views nvarchar(20)・watch_hours nvarchar(20)・avg_view_duration nvarchar(10)・loaded_at datetime2 | なし（stg なので重複も入れる） | 「合計」行を外す／列名を英語に |
| stg.daily_subscribers | report_date・subscribers nvarchar(20)・loaded_at | なし | 列名を英語に |
| stg.videos | video_id nvarchar(20)・title nvarchar(400)・published_at_text nvarchar(20)（"Aug 17, 2026" のまま）・duration_sec・views・watch_hours・subscribers・impressions・ctr_pct（すべて nvarchar(20)）・loaded_at | なし | 「合計」行を外す／動画IDの前後の空白を消す |
| stg.video_daily | report_date・video_id・title・published_at_text・duration_sec・views・loaded_at | なし | 先頭の BOM を外して読む（encoding="utf-8-sig"）／ID の空白を消す |
| stg.traffic_source_daily | report_date・source_name nvarchar(50)・views・loaded_at | なし | 列名を英語に |
| stg.subscription_source_daily | report_date・sub_source_name nvarchar(50)・subscribers・loaded_at | なし | 列名を英語に |
- pandas で揃える型・欠損・日付（stg に入れる前に）
  - 日付：「2026-10-14」はそのまま、videos の公開日「Aug 17, 2026」は `pd.to_datetime(format="%b %d, %Y")` で日付に（失敗は空）
  - 平均視聴時間「0:10:53」は秒（653）に変換した列も作る
  - 数値：視聴回数・登録者は整数、総再生時間・クリック率は小数に変換（変換できない値は空）
  - 重複：同じ日付（日別）・同じ動画ID（videos）・同じ「日付×動画ID」が2行以上ないか確認し、あれば最後の1行を残す（`drop_duplicates(keep="last")`）。今の CSV は重複0（取り込み時にログに件数を出す）
  - 欠損：stg では空のまま入れる（公開日 6本・視聴回数 9本・クリック率 4本が空）。mart で「視聴回数の空は 0」「公開日の空は種類を判定せず除外フラグ」と決めて埋める
- 入れ方：pandas の `to_sql`（SQLAlchemy ＋ pyodbc）。入れたあと「件数」と「視聴回数の合計（36,577）」を CSV と突き合わせる

## C. mart
### ファクト
| テーブル | 粒度（1行の単位） | 列（型） | キー |
|---|---|---|---|
| fact_channel_daily | 日 | date_key int・views int・watch_hours decimal(10,4)・avg_view_sec int・subscribers_net int | PK・FK date_key |
| fact_video_daily | 動画×日（上位24本） | date_key・video_key・views int・days_since_publish int | PK (date_key, video_key) |
| fact_traffic_daily | 流入元×日 | date_key・source_key・views int | PK (date_key, source_key) |
| fact_subscription_daily | 登録元×日 | date_key・sub_source_key・subscribers int | PK (date_key, sub_source_key) |
| fact_video_summary | 動画（期間合計） | video_key・views・watch_hours decimal(10,4)・subscribers・impressions int・ctr_pct decimal(5,2) | PK・FK video_key |

### ディメンション
| テーブル | 列（型） | キー |
|---|---|---|
| dim_date | date_key int（20260714）・date date・week_start date（月曜）・month char(7)・weekday tinyint | PK date_key（期間の全日。視聴0の日も行を作る） |
| dim_video | video_key int IDENTITY・video_id nvarchar(20)・title nvarchar(400)・published_date date・duration_sec int・content_type nvarchar(10)（Shorts／長尺／Live）・publish_weekday tinyint | PK video_key、UNIQUE video_id |
| dim_traffic_source | source_key・source_name・source_group（ショート／検索／おすすめ／外部 など） | PK source_key |
| dim_subscription_source | sub_source_key・sub_source_name | PK sub_source_key |


### テーブルのつながり（スタースキーマ）
```
                 dim_date ─────────────┬──────────────┬───────────────┐
                    │ date_key         │              │               │
                    ▼                  ▼              ▼               ▼
dim_video ──▶ fact_video_daily   fact_channel_daily  fact_traffic_daily ◀── dim_traffic_source
    │          (動画×日)           (日)               (流入元×日)
    │
    └──────▶ fact_video_summary                    fact_subscription_daily ◀── dim_subscription_source
               (動画・期間合計)                       (登録元×日)  ▲ date_key も dim_date から
```
- 1対多：dim_* の主キー → fact_* の外部キー（すべて片方向）
- 種類（Shorts／長尺／Live）は dim_video の content_type 列に持たせる（種類だけのディメンションは作らない。3値しかないため）

## D. ビュー（CTE ＋ ウィンドウ関数の3本を本命にする）
| ビュー | 出す内容 | 使う構文 |
|---|---|---|
| **mart.v_channel_ma7** | 日別の視聴回数と7日移動平均（視聴0の日も含めて「7日」で平均） | CTE（dim_date と LEFT JOIN して0埋め）＋ AVG() OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) |
| **mart.v_video_rank_first7** | 公開7日間の視聴回数を、種類（Shorts／長尺）ごとに順位付け | CTE（公開後0〜6日に絞って動画ごとに合計）＋ ROW_NUMBER() OVER (PARTITION BY content_type ORDER BY 7日計 DESC) |
| **mart.v_channel_weekly_wow** | 週ごとの視聴回数と前週比（％） | CTE（週ごとに合計）＋ LAG(週計) OVER (ORDER BY week_start) |
| （予備）v_traffic_share_weekly | 週ごとの流入元の割合 | SUM() OVER (PARTITION BY 週) |
| （回帰用）v_video_features | 動画単位の説明変数と目的変数 | JOIN |
- 答え合わせ：1本目と同じ数字（10/14 の7日移動平均 602.29、dim_date 93日）が出ること

## E. 要因分析（重回帰）
- **目的変数**：log(1＋視聴回数)（動画ごと。偏りが大きいので対数）
- **説明変数の候補**
  1. Shorts かどうか（0/1）
  2. 長さ（秒、対数）※ Shorts と一緒に入れると重なるので、長尺だけのモデルでも見る
  3. 公開からの日数（集計日 10/15 まで）
  4. 公開曜日（土日かどうか）
  5. サムネイルのクリック率（長尺のみ意味がある）
- インプレッションは視聴回数とほぼ同時に決まる（結果に近い）ので、入れない版を本命にし、入れた版と比べる
- 342本のうち空欄のある行（公開日・視聴回数）は外す。外した本数を README に書く

## F. RLS（10/18）
- ロール「Shorts担当」：dim_video[content_type] = "Shorts"／ロール「長尺担当」：dim_video[content_type] IN {"長尺", "Live"}（動画に関係するファクトだけ絞られ、チャンネル全体の数字は全員が見られる）

## G. 要因分析の下見（10/18・pandas で videos.csv を確認）
- 行数：342本 → Live 3本と、公開日か視聴回数が空の行を外すと **329本**（Shorts 194・長尺 135）。動画単位で重回帰に十分な行数がある
- 目的変数の分布：視聴回数は右に大きく偏る（歪度 3.04）→ log(1＋視聴回数) で歪度 -0.12 とほぼ左右対称になるので対数をとる
- 目的変数：「公開7日間の視聴回数」は日別データが上位24本しかないので使えない → **log(1＋期間合計の視聴回数)** にし、公開からの日数を説明変数で調整する
- 相関（329本）：**Shorts かどうか と log(長さ) の相関が -0.99（VIF 約56）＝多重共線性**。同時に入れない。全体モデルは「Shorts かどうか」だけ、長さの効果は長尺137本だけのモデルで見る
- 長尺だけ（135本）では：公開からの日数 0.41・クリック率 0.36 が視聴回数と相関、長さ -0.16、土日公開 0.05（ほぼ無関係）。説明変数どうしの相関は 0.1 以下で問題なし
- 全体では Shorts かどうか が視聴回数と 0.62（Shorts の方が回る）
- 下見のコード：python\\e_01_regression_preview.py
- 粒度は動画単位のままでよい（動画×日にする必要はない）。動画×日は上位24本・2,232行しかなく、同じ動画の行が並ぶので独立ではない
