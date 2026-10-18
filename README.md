# youtube-data-mart

YouTube Studio のエクスポート（CSV 7種）を、pandas → SQL Server（stg → mart）→ Power BI とつなぎ、最後に「動画の視聴回数に何が効いているか」を重回帰で確かめるポートフォリオです。

## 目的
（あとで埋める）

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
（あとで埋める）

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

## 分かったこと
- 同じ公開日数なら、Shorts は長尺の約7.5倍見られている（重回帰・329本・p<0.001）→ Shorts は入口
- 長尺の視聴回数はクリック率（1ポイントで約1.22倍）と公開からの日数で決まり、土日・祝日の公開は関係ない
- 詳しくは docs/2026-10-18_要因分析の結果.md（インプレッションを入れない理由・多重共線性の扱いも記載）
