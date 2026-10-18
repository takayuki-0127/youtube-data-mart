# E：要因分析（重回帰）。mart.v_video_features を読み、視聴回数に何が効いているかを確かめる
import os
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
from dotenv import load_dotenv
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sqlalchemy import create_engine

pd.set_option("display.width", 200)
ROOT = Path(__file__).resolve().parents[1] if "__file__" in globals() else Path.cwd().parent
load_dotenv(ROOT / ".env")
engine = create_engine(os.environ["SQLSERVER_URL"])

# ---- 1. 読み込みと目的変数 ----
df = pd.read_sql("SELECT * FROM mart.v_video_features", engine)
d = df.dropna(subset=["published_date", "views"]).copy()
d["log_views"] = np.log1p(d["views"])
d["log_duration"] = np.log(d["duration_sec"])
print("使う行:", len(d), "（期待 329）  Shorts:", int(d.is_short.sum()), " 長尺:", int((1 - d.is_short).sum()))


def table(res, name):
    t = pd.DataFrame({"係数": res.params, "標準誤差": res.bse, "p値": res.pvalues})
    t["倍率(exp係数)"] = np.exp(t["係数"])
    print(f"\n===== {name} =====")
    print(f"n={int(res.nobs)}  R2={res.rsquared:.3f}  調整済みR2={res.rsquared_adj:.3f}")
    print(t.round(4))
    return t


# ---- 2. 全体モデル（長さは Shorts と相関 -0.99 なので入れない） ----
m_all = smf.ols("log_views ~ is_short + days_since_publish + is_weekend_publish + is_holiday_publish", data=d).fit()
t_all = table(m_all, "全体モデル（329本）")

# ---- 3. 長尺だけのモデル ----
lg = d[(d.is_short == 0)].dropna(subset=["ctr_pct"]).copy()
m_long = smf.ols("log_views ~ log_duration + days_since_publish + ctr_pct + is_weekend_publish", data=lg).fit()
t_long = table(m_long, f"長尺モデル（インプレッションなし・{len(lg)}本）")
lg2 = lg.dropna(subset=["impressions"]).copy()
lg2["log_impressions"] = np.log1p(lg2["impressions"])
m_long_imp = smf.ols("log_views ~ log_duration + days_since_publish + ctr_pct + is_weekend_publish + log_impressions",
                     data=lg2).fit()
t_long_imp = table(m_long_imp, "長尺モデル（インプレッションあり）")
print(f"\nインプレッションを入れると R2 {m_long.rsquared:.3f} → {m_long_imp.rsquared:.3f}")

# ---- 4. scikit-learn：8:2 で分けて検証データの当てはまり ----
X_cols = ["is_short", "days_since_publish", "is_weekend_publish", "is_holiday_publish"]
X_tr, X_te, y_tr, y_te = train_test_split(d[X_cols], d["log_views"], test_size=0.2, random_state=42,
                                          stratify=d["is_short"])
lr = LinearRegression().fit(X_tr, y_tr)
pred = lr.predict(X_te)
print("\n===== scikit-learn（全体モデル・8:2）=====")
print(f"学習 {len(X_tr)}行 / 検証 {len(X_te)}行  検証R2={r2_score(y_te, pred):.3f}  検証RMSE={mean_squared_error(y_te, pred) ** 0.5:.3f}（log の単位）")
print("係数（sklearn）:", dict(zip(X_cols, np.round(lr.coef_, 4))))
print("係数（statsmodels・全データ）:", m_all.params[X_cols].round(4).to_dict())

# ---- 5. 結果を CSV に残す ----
out = ROOT / "docs" / "regression_results.csv"
pd.concat({"全体": t_all, "長尺": t_long, "長尺+インプレッション": t_long_imp}).to_csv(out, encoding="utf-8-sig")
print("\n保存:", out.name)
