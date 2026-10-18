"""SQL ファイルを GO で区切って順に実行し、結果セットを表で表示する（SSMS の代わりにバッチから流す用）。

使い方: python src/run_sql.py sql/02_create_mart.sql sql/03_load_mart.sql ...
"""
import os
import re
import sys
from pathlib import Path

import pyodbc
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")
url = os.environ["SQLSERVER_URL"]
driver = re.search(r"driver=([^&]+)", url).group(1).replace("+", " ")
conn = pyodbc.connect(f"DRIVER={{{driver}}};SERVER=localhost;Trusted_Connection=yes;TrustServerCertificate=yes",
                      autocommit=True)


def run_file(path: Path):
    print(f"\n######## {path.name} ########")
    sql = path.read_text(encoding="utf-8-sig")
    batches = [b for b in re.split(r"^\s*GO\s*$", sql, flags=re.M | re.I) if b.strip()]
    cur = conn.cursor()
    for b in batches:
        cur.execute(b)
        while True:
            if cur.description:
                cols = [c[0] for c in cur.description]
                rows = cur.fetchall()
                print(" | ".join(cols))
                for r in rows:
                    print(" | ".join("" if v is None else str(v) for v in r))
                print()
            if not cur.nextset():
                break


for p in sys.argv[1:]:
    run_file(ROOT / p)
print("\nSQL 実行完了")
