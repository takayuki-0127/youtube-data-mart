# E：mart.v_video_features を pd.read_sql で読み、下見（e_01）と行数・欠損が一致するか確かめる
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")
engine = create_engine(os.environ["SQLSERVER_URL"])

df = pd.read_sql("SELECT * FROM mart.v_video_features", engine)
print("行数（Live 除く）:", len(df), " 期待 339")
miss = df[["published_date", "views", "ctr_pct", "subscribers"]].isna().sum().to_dict()
print("欠損:", miss, " 期待 {'published_date': 6, 'views': 9, 'ctr_pct': 4, 'subscribers': 12}")
use = df.dropna(subset=["published_date", "views"])
print("使える行:", len(use), " 期待 329  / Shorts:", int(use["is_short"].sum()), " 期待 194 / 長尺:", int((1 - use["is_short"]).sum()), " 期待 135")
print("first7_views がある動画:", int(df["first7_views"].notna().sum()))
print(use[["is_short", "duration_sec", "days_since_publish", "is_weekend_publish", "ctr_pct", "views"]].describe().round(2))
