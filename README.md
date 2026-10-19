# youtube-data-mart

YouTube Studio のエクスポート（CSV 7種）を、pandas → SQL Server（stg → mart）→ Power BI とつなぎ、最後に「動画の視聴回数に何が効いているか」を重回帰で確かめるポートフォリオです。

## 目的
1本目（youtube-analytics-powerbi）は CSV を Power BI で直接読んでいた。2本目では、取り込み（pandas）→ 保管（SQL Server の stg）→ 分析用の形（mart のスタースキーマ）→ 可視化（Power BI）→ 要因分析（重回帰）を分け、**何度流しても同じ数字が出るデータの流れ**を作る。そのうえで「動画の視聴回数に何が効いているか」を数字で確かめる。

## データの流れ
```
YouTube Studio の CSV ─▶ pandas（src/load_stg.py）─▶ SQL Server stg ─▶ SQL Server mart（スタースキーマ・ビュー）
                                                                            ├─▶ Power BI（レポート・RLS）
                                                                            └─▶ 要因分析（statsmodels / scikit-learn）
```

### mart のテーブル（sql/02_create_mart.sql・03_load_mart.sql）
| 種類 | テーブル | 1行の単位 |
|---|---|---|
| ディメンション | dim_date（再帰 CTE で作る。曜日・週・月・祝日フラグ） | 日 |
| ディメンション | dim_video（代理キー video_key／業務キー video_id） | 動画 |
| ディメンション | dim_content_type（Shorts／長尺／Live） | 種類 |
| ディメンション | dim_traffic_source・dim_subscription_source | 流入元・登録元 |
| ファクト | fact_channel_daily | 日 |
| ファクト | fact_video_daily | 動画×日（上位24本） |
| ファクト | fact_traffic_daily・fact_subscription_daily | 流入元×日・登録元×日 |
| ファクト | fact_video_summary | 動画（期間合計） |

### mart のビュー（sql/04_views.sql）
| ビュー | 中身 | 使った構文 |
|---|---|---|
| mart.v_channel_ma7 | 日別の視聴回数と7日移動平均 | AVG() OVER (ROWS 6 PRECEDING)・LAG |
| mart.v_channel_weekly_wow | 週ごとの視聴回数と前週比 | CTE・LAG |
| mart.v_video_rank_first7 | 公開7日間の視聴回数の種類別順位 | CTE・ROW_NUMBER() OVER (PARTITION BY) |
| mart.v_video_features | 重回帰用の動画単位の表 | JOIN |

## 使った技術
Python（pandas・SQLAlchemy・pyodbc・statsmodels・scikit-learn）／SQL Server（CTE・再帰 CTE・ウィンドウ関数・代理キー）／Power BI（スタースキーマ・RLS）

## 再現の手順
1. `pip install -r requirements.txt`
2. `.env.example` を `.env` にコピーし、接続文字列を自分の環境に合わせる（Windows 認証・ODBC Driver 17/18）
3. SSMS で `sql/00_create_database.sql` → `sql/01_create_stg.sql` を実行
4. `python src/load_stg.py`（CSV → stg。`data/raw/` に YouTube Studio のエクスポートを置く）
5. `python src/run_sql.py sql/02_create_mart.sql sql/03_load_mart.sql sql/04_views.sql`（mart とビュー。確認クエリの結果も表示）
6. `python notebooks/e_03_regression.py`・`notebooks/e_04_regression_check.py`（要因分析）
- Windows では `run_load_stg.bat` → `run_mart.bat` → `run_regression_check.bat` をダブルクリックでも同じ

## フォルダ
| フォルダ | 中身 |
|---|---|
| docs/ | 設計・答え合わせのメモ |
| sql/ | DDL（00 データベース・01 stg・…）と確認用 SQL |
| src/ | pandas の取り込み（load_stg.py） |
| notebooks/ | 要因分析のノートブック |

## 答え合わせ
| 確認 | 結果 |
|---|---|
| stg 6テーブルの行数・合計が CSV と一致 | ○ |
| mart ファクトの行数・合計が stg と一致、ディメンションに結びつかない行 0件 | ○ |
| 10/14 の7日移動平均 602.29・10/13 631.71（1本目の SQL・Power BI と同じ） | ○ |
| 93日・14週の視聴回数合計 36,577 | ○ |
| Shorts の公開7日間1位「They Are In for the Night」945回（初日354・37.5%） | ○ |
| v_video_features：使える行 329・欠損が pandas の下見と一致 | ○ |

## Power BI（youtube_data_mart.pbix・リポジトリには含めない）
mart の10テーブルとビュー・回帰結果（mart.regression_ratios）を読み込み、リレーションはすべて多対1・単方向。dim_date を日付テーブルに設定し、キー列は非表示。メジャーは表示フォルダ（チャンネル／動画）に分けた。見た目は自作テーマ（powerbi/theme_youtube_mart.json）でそろえた。

| ページ | 中身 |
|---|---|
| 1 全体の推移 | 日別の視聴回数と7日移動平均（DAX の DATESINPERIOD）、総視聴回数・登録者増減・動画数 |
| 2 Shortsと長尺 | 種類別の1本あたり視聴回数と動画数（Live は3本だけなので参考値） |
| 3 公開7日間の伸び | v_video_rank_first7 の種類別ランキング（初日の割合つき） |
| 4 何が効いているか | 重回帰の倍率（全体／長尺）と95%信頼区間・p値。相関であって因果ではない |

![全体の推移](images/pbi_page1_trend.png)
![Shortsと長尺](images/pbi_page2_shorts_vs_long.png)
![公開7日間の伸び](images/pbi_page3_first7.png)
![何が効いているか](images/pbi_page4_drivers.png)

### 行レベルセキュリティ（RLS）
| ロール | 見える範囲 |
|---|---|
| Shorts担当 | content_type = "Shorts" |
| 長尺担当 | content_type が "長尺" または "Live"（Live は3本だけなので長尺担当が持つ） |

「ロールとして表示」で、それぞれ自分の担当分だけが出ることを確かめた。

![Shorts担当で表示](images/rls_shorts.png)
![長尺担当で表示](images/rls_longform.png)

## 分かったこと（重回帰・328本・目的変数は log(1＋1日あたりの視聴回数)・HC3）
- 公開からの日数をそろえると、Shorts は長尺の約2.8倍、1日あたりに見られる（95%信頼区間 2.4〜3.3）→ Shorts は入口
- 動画は公開直後がいちばん伸び、1日ごとに約1.6% ずつ落ちる
- 長尺はクリック率（サムネイル）だけがはっきり効く（+1ポイントで1日あたり約1.07倍）。土日・祝日の公開や長さは関係ない
- 5-fold CV の R² は 0.42 ± 0.09。相関であって因果ではない。詳しくは docs/2026-10-18_要因分析の結果.md

![残差](images/regression_residuals.png)

### Shorts を出すと長尺の視聴は増えるか（日次・分布ラグ回帰・HAC）

長尺の日次視聴（全体 −「ショート フィード」−「関連のショート動画」経由で近似）を、Shorts の投稿本数（当日〜7日前）・曜日・トレンド・長尺の投稿本数で回帰した（86日、Newey–West ラグ7）。当日は1本あたり約 +15 回多いが、新しい Shorts 自身がブラウジング・検索経由で得た視聴の混入でほぼ説明でき、純粋な長尺（上位12本）では差がない。翌日〜7日後の合計は +10.8 回（95%CI −7.4〜+29.0）で、この期間では「Shorts が長尺を引っぱる」ははっきり見えない。期間が短く CI が広いので「効果がない」とも言えず、投稿日は自分で選んでいるため因果も言えない。詳細は [notebooks/e_05_shorts_to_longform.ipynb](notebooks/e_05_shorts_to_longform.ipynb)。

![Shorts の投稿本数と長尺の日次視聴（ラグ別の係数）](images/shorts_lag_effect.png)

## SQL の練習問題
- [SQL 面接用の5問](docs/SQL面接用の5問.md)：gaps and islands（連続して伸びた日数）・前週比の上位・パレート（上位20%の占有率）・種類別の中央値（PERCENTILE_CONT）・ROW_NUMBER での重複除去
