"""CSV（YouTube Studio のエクスポート）を整えて SQL Server の stg に入れる。

使い方:
    pip install pandas sqlalchemy pyodbc python-dotenv
    .env.example を .env にコピーして接続文字列を書く
    python src/load_stg.py
"""
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
load_dotenv(ROOT / ".env")
engine = create_engine(os.environ["SQLSERVER_URL"], fast_executemany=True)


def read(name: str) -> pd.DataFrame:
    """CSV を読む。先頭の BOM は utf-8-sig で外す。「合計」行を外す。"""
    df = pd.read_csv(RAW / name, encoding="utf-8-sig")
    return df[df.iloc[:, 0].astype(str) != "合計"].copy()


def to_int(s):
    return pd.to_numeric(s, errors="coerce").astype("Int64")


def to_num(s):
    return pd.to_numeric(s, errors="coerce")


def hms_to_sec(s):
    """「0:10:53」→ 653"""
    return pd.to_timedelta(s, errors="coerce").dt.total_seconds().astype("Int64")


def dedup(df: pd.DataFrame, keys: list[str], name: str) -> pd.DataFrame:
    n = df.duplicated(keys, keep="last").sum()
    print(f"  {name}: 重複 {n} 行を除去")
    return df.drop_duplicates(keys, keep="last")


def build() -> dict[str, pd.DataFrame]:
    out = {}

    d = read("2026-10-15_daily_metrics.csv")
    out["daily_metrics"] = dedup(pd.DataFrame({
        "report_date": pd.to_datetime(d["日付"]).dt.date,
        "views": to_int(d["視聴回数"]),
        "watch_hours": to_num(d["総再生時間（単位: 時間）"]),
        "avg_view_sec": hms_to_sec(d["平均視聴時間"]),
    }), ["report_date"], "daily_metrics")

    d = read("2026-10-15_daily_subscribers.csv")
    out["daily_subscribers"] = dedup(pd.DataFrame({
        "report_date": pd.to_datetime(d["日付"]).dt.date,
        "subscribers": to_int(d["チャンネル登録者"]),
    }), ["report_date"], "daily_subscribers")

    d = read("2026-10-15_videos.csv")
    out["videos"] = dedup(pd.DataFrame({
        "video_id": d["コンテンツ"].str.strip(),
        "title": d["動画のタイトル"],
        "published_date": pd.to_datetime(d["動画公開時刻"], format="%b %d, %Y", errors="coerce").dt.date,
        "duration_sec": to_int(d["長さ"]),
        "views": to_int(d["視聴回数"]),
        "watch_hours": to_num(d["総再生時間（単位: 時間）"]),
        "subscribers": to_int(d["チャンネル登録者"]),
        "impressions": to_int(d["サムネイルのインプレッション"]),
        "ctr_pct": to_num(d["サムネイルのクリック率 (%)"]),
    }), ["video_id"], "videos")

    d = read("2026-10-16_video_daily_views.csv")
    out["video_daily"] = dedup(pd.DataFrame({
        "report_date": pd.to_datetime(d["日付"]).dt.date,
        "video_id": d["コンテンツ"].str.strip(),
        "views": to_int(d["視聴回数"]),
    }), ["report_date", "video_id"], "video_daily")

    d = read("2026-10-15_traffic_source_daily.csv")
    out["traffic_source_daily"] = dedup(pd.DataFrame({
        "report_date": pd.to_datetime(d["日付"]).dt.date,
        "source_name": d["トラフィック ソース"],
        "views": to_int(d["視聴回数"]),
    }), ["report_date", "source_name"], "traffic_source_daily")

    d = read("2026-10-15_subscription_source_daily.csv")
    out["subscription_source_daily"] = dedup(pd.DataFrame({
        "report_date": pd.to_datetime(d["日付"]).dt.date,
        "sub_source_name": d["チャンネル登録元"],
        "subscribers": to_int(d["チャンネル登録者"]),
    }), ["report_date", "sub_source_name"], "subscription_source_daily")
    return out


def main():
    tables = build()
    print("\n=== CSV 側の件数と合計（SSMS の 02_check_stg.sql と比べる）===")
    for name, df in tables.items():
        col = "views" if "views" in df.columns else "subscribers"
        print(f"{name:28s} rows={len(df):5d}  {col}_sum={int(df[col].sum())}")

    with engine.begin() as con:
        for name, df in tables.items():
            con.execute(text(f"TRUNCATE TABLE stg.{name}"))
            df.to_sql(name, con, schema="stg", if_exists="append", index=False)
    print("\nstg への取り込み完了")


if __name__ == "__main__":
    main()
