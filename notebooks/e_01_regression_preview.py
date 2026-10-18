# E ポートフォリオ2本目：要因分析の下見（2026-10-18）
# videos.csv を読み、目的変数と説明変数の候補を作って、行数・欠損・相関・VIF を確認する
import numpy as np
import pandas as pd

RAW = "../data/raw/2026-10-15_videos.csv"
v = pd.read_csv(RAW)
v = v[v["コンテンツ"] != "合計"].copy()                       # 「合計」行を外す
v.columns = ["video_id", "title", "published", "duration_sec", "views",
             "watch_hours", "subscribers", "impressions", "ctr_pct"]
v["video_id"] = v["video_id"].str.strip()                    # ID の空白を消す
v["published"] = pd.to_datetime(v["published"], format="%b %d, %Y", errors="coerce")  # "Aug 17, 2026" → 日付

# 説明変数の候補
# 種類の判定は1本目（dbo.v_video）と同じ：長さ0 か タイトルに LIVE → Live、60秒以下 → Shorts、それ以外 → 長尺
v["content_type"] = np.where((v["duration_sec"] == 0) | v["title"].str.contains("LIVE"), "Live",
                     np.where(v["duration_sec"] <= 60, "Shorts", "長尺"))
print("種類の内訳:", v["content_type"].value_counts().to_dict())   # 答え合わせ：Shorts 201・長尺 138・Live 3
v = v[v["content_type"] != "Live"].copy()                     # Live 3本は外す
v["is_short"] = (v["content_type"] == "Shorts").astype(int)
v["log_duration"] = np.log1p(v["duration_sec"])
v["days_since_publish"] = (pd.Timestamp("2026-10-15") - v["published"]).dt.days
v["is_weekend"] = v["published"].dt.dayofweek.isin([5, 6]).astype(int)
# 目的変数
v["log_views"] = np.log1p(v["views"])

print("Live を外した行:", len(v))
print("目的変数の偏り（歪度）: 視聴回数", round(v["views"].skew(), 2), "→ log(1+視聴回数)", round(v["log_views"].skew(), 2))
print("欠損:", v[["published", "views", "ctr_pct", "subscribers"]].isna().sum().to_dict())
d = v.dropna(subset=["published", "views"])
print("使える行:", len(d), " Shorts:", d["is_short"].sum(), " 長尺:", (1 - d["is_short"]).sum())

X = ["is_short", "log_duration", "days_since_publish", "is_weekend", "ctr_pct"]
print(d[X + ["log_views"]].corr().round(2))

# VIF（相関行列の逆行列の対角）
Z = d[["is_short", "log_duration", "days_since_publish", "is_weekend"]].astype(float)
C = np.corrcoef(((Z - Z.mean()) / Z.std()).T.values)
print("VIF:", dict(zip(Z.columns, np.round(np.diag(np.linalg.inv(C)), 1))))

long = d[d["is_short"] == 0]
print("長尺のみ:", len(long))
print(long[["log_duration", "days_since_publish", "is_weekend", "ctr_pct", "log_views"]].corr().round(2))
