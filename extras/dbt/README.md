# extras/dbt：同じビューを dbt で書き直す（BigQuery／DuckDB）

求人88件（2026-10-21 時点）で、BigQuery は29件（33%）、dbt は8件（9%）に出てきた。BigQuery は `extras/bigquery` で一度動かしたので、今回は **dbt でモデルとテストの形にする**ところを足した。題材は同じ `v_channel_ma7`（7日移動平均・前週同曜日の値）。

## 構成
```
seeds/channel_daily.csv                 日別の視聴回数（2026-07-14〜10-14、93日）
models/staging/stg_channel_daily.sql    型をそろえるだけの staging（view）
models/marts/v_channel_ma7.sql          7日移動平均・前週同曜日（view、ウィンドウ関数）
macros/weekday_name.sql                 曜日名。DB ごとに関数が違うので adapter.dispatch で切り替え
models/schema.yml                       not_null・unique・accepted_values のテスト
tests/assert_matches_sql_server.sql     SQL Server 版と同じ値か（合計 36,577／10/14 = 602.29／10/13 = 631.71／93日）
profiles.yml.example                    接続先の例（BigQuery サンドボックス／手元の DuckDB）
bigquery_check.sql                      dbt が BigQuery 向けに生成した SQL を、コンソールで流して確かめる用
```

`stg_ → mart` の流れは本体（SQL Server の `stg` → `mart`）と同じ。違うのは、**依存関係（`ref`）とテストがコードに入っている**こと。`dbt build` 1回で、作る順番の解決・ビューの作成・テストまで通る。

## 結果（2026-10-21）
| 実行先 | やったこと | 結果 |
|---|---|---|
| DuckDB（手元） | `dbt build --target local`（seed 1・view 2・テスト 8） | **PASS=11 ERROR=0**。10/14 の7日移動平均 602.29、10/13 は 631.71、合計 36,577 で SQL Server 版と一致 |
| BigQuery | `dbt compile --target bq` で BigQuery 向けの SQL を生成（曜日は `FORMAT_DATE('%a', date)` に切り替わる）→ `bigquery_check.sql` | （下の「BigQuery で確かめる」を参照） |

## SQL Server・BigQuery・dbt で変わったところ
| | SQL Server（sql/04_views.sql） | BigQuery（extras/bigquery） | dbt（ここ） |
|---|---|---|---|
| 曜日名 | `dim_date` を JOIN | `FORMAT_DATE('%a', date)` | マクロ `weekday_name()` が接続先に合わせて切り替える |
| 参照 | `mart.channel_daily` と直書き | `youtube_mart.channel_daily` と直書き | `{{ ref('stg_channel_daily') }}`（作る順番を dbt が決める） |
| 答え合わせ | 手で SELECT | `03_check.sql` を手で実行 | `tests/` に置き、`dbt build` のたびに自動で実行 |
| データの投入 | `INSERT` | `CREATE TABLE AS SELECT`（サンドボックスは DML 不可） | `dbt seed`（CSV をロード） |

## 動かし方
```bash
pip install -r requirements.txt
cp profiles.yml.example ~/.dbt/profiles.yml   # Windows は %USERPROFILE%\.dbt\profiles.yml
dbt build --target local                      # DuckDB で seed → view → テスト
```
BigQuery で動かすとき（鍵ファイルは作らず、自分の Google アカウントで認証する）：
1. Google Cloud CLI を入れて `gcloud auth application-default login`（ブラウザで許可）
2. `~/.dbt/profiles.yml` の `YOUR_GCP_PROJECT_ID` をサンドボックスのプロジェクト ID に書き換える
3. `dbt build --target bq` → データセット `youtube_dbt` に seed のテーブルとビュー2本ができ、テストが流れる（サンドボックスのテーブルは60日で消える）

参考：dbt 公式ドキュメント（[BigQuery setup](https://docs.getdbt.com/docs/core/connect-data-platform/bigquery-setup)・[adapter.dispatch](https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch)・[data tests](https://docs.getdbt.com/docs/build/data-tests)）
