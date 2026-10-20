# サンプルデータ（data/sample/）だけで動く確認用スクリプト。SQL Server は不要
# 実行：python src/try_sample.py （リポジトリのいちばん上のフォルダで）
from pathlib import Path
import pandas as pd

S = Path(__file__).resolve().parents[1] / "data" / "sample"
d = pd.read_csv(S / "channel_daily.csv", parse_dates=["日付"]).sort_values("日付")
d["7日移動平均"] = d["視聴回数"].rolling(7, min_periods=1).mean().round(2)   # mart.v_channel_ma7 と同じ計算
print("日別：", len(d), "日・合計", int(d["視聴回数"].sum()), "回")
print(d.tail(3).to_string(index=False))

v = pd.read_csv(S / "videos_sample.csv")
print("\n動画（サンプル40本）の種類ごとの視聴回数")
print(v.groupby("種類")["視聴回数"].agg(["count", "median", "mean"]).round(1).to_string())
