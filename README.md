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
（あとで埋める）

## 分かったこと
（あとで埋める）
