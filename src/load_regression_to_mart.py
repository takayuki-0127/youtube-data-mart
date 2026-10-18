"""要因分析の結果（docs/regression_ratios_ci.csv）を mart.regression_ratios に入れる（Power BI の4ページ目用）"""
import os
from pathlib import Path
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")
engine = create_engine(os.environ["SQLSERVER_URL"])
df = pd.read_csv(ROOT / "docs" / "regression_ratios_ci.csv", encoding="utf-8-sig")
df["sort_order"] = range(1, len(df) + 1)
with engine.begin() as con:
    con.execute(text("DROP TABLE IF EXISTS mart.regression_ratios"))
df.to_sql("regression_ratios", engine, schema="mart", index=False)
print(df)
