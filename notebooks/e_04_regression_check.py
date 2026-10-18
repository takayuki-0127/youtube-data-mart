# E：重回帰の補強（目的変数の見直し・頑健な標準誤差 HC3・VIF・残差・5-fold CV）
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
from dotenv import load_dotenv
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import KFold, cross_val_score
from sqlalchemy import create_engine
from statsmodels.stats.outliers_influence import variance_inflation_factor

pd.set_option("display.width", 200)
ROOT = Path(__file__).resolve().parents[1] if "__file__" in globals() else Path.cwd().parent
load_dotenv(ROOT / ".env")
engine = create_engine(os.environ["SQLSERVER_URL"])
DOCS = ROOT / "docs"
IMG = ROOT / "images"
IMG.mkdir(exist_ok=True)

df = pd.read_sql("SELECT * FROM mart.v_video_features", engine)
d = df.dropna(subset=["published_date", "views"]).copy()
d = d[d["days_since_publish"] >= 1].copy()          # 集計日（10/15）当日公開は日数0なので外す
d["log_views"] = np.log1p(d["views"])
# 目的変数の見直し：累計だと「長く出ているほど多い」を拾うので、1日あたりの視聴回数にそろえる
d["views_per_day"] = d["views"] / d["days_since_publish"]
d["log_views_per_day"] = np.log1p(d["views_per_day"])
print("使う行:", len(d), " 公開7日間の視聴回数がある動画:", int(d["first7_views"].notna().sum()), "本（日別データは上位24本だけ）")

X = ["is_short", "days_since_publish", "is_weekend_publish", "is_holiday_publish"]
f = "log_views_per_day ~ " + " + ".join(X)

# ---- 1. 通常の標準誤差 と HC3（ばらつきが種類で違っても崩れない標準誤差）の比較 ----
m = smf.ols(f, data=d).fit()
m_hc3 = smf.ols(f, data=d).fit(cov_type="HC3")
cmp = pd.DataFrame({"係数": m.params, "p値(通常)": m.pvalues, "p値(HC3)": m_hc3.pvalues,
                    "倍率": np.exp(m.params),
                    "95%CI下(HC3)": np.exp(m_hc3.conf_int()[0]), "95%CI上(HC3)": np.exp(m_hc3.conf_int()[1])})
print(f"\n===== 全体モデル：目的変数 log(1+1日あたり視聴回数)  n={int(m.nobs)} R2={m.rsquared:.3f} =====")
print(cmp.round(4))
print("残差の分散 Shorts / 長尺:", round(m.resid[d.is_short == 1].var(), 3), "/", round(m.resid[d.is_short == 0].var(), 3))

# 参考：前回の累計モデル
m_cum = smf.ols("log_views ~ " + " + ".join(X), data=d).fit(cov_type="HC3")
print(f"\n参考 累計モデル（HC3）R2={m_cum.rsquared:.3f}  Shorts 倍率 {np.exp(m_cum.params['is_short']):.2f}  日数 p={m_cum.pvalues['days_since_publish']:.4f}")

# 長尺モデルも 1日あたり ＋ HC3
lg = d[d.is_short == 0].dropna(subset=["ctr_pct"]).copy()
lg["log_duration"] = np.log(lg["duration_sec"])
fl = "log_views_per_day ~ log_duration + days_since_publish + ctr_pct + is_weekend_publish"
ml = smf.ols(fl, data=lg).fit(cov_type="HC3")
cmp_l = pd.DataFrame({"係数": ml.params, "p値(HC3)": ml.pvalues, "倍率": np.exp(ml.params),
                      "95%CI下": np.exp(ml.conf_int()[0]), "95%CI上": np.exp(ml.conf_int()[1])})
print(f"\n===== 長尺モデル：1日あたり・HC3  n={int(ml.nobs)} R2={ml.rsquared:.3f} =====")
print(cmp_l.round(4))

# ---- 2. VIF ----
def vif(frame, cols):
    Z = frame[cols].astype(float).assign(const=1.0)
    return pd.Series([variance_inflation_factor(Z.values, i) for i in range(len(cols))], index=cols).round(2)
print("\nVIF 全体:", vif(d, X).to_dict())
print("VIF 長尺:", vif(lg, ["log_duration", "days_since_publish", "ctr_pct", "is_weekend_publish"]).to_dict())
print("参考 VIF（Shorts と長さを同時に入れた場合）:", vif(d.assign(log_duration=np.log(d.duration_sec)), ["is_short", "log_duration"]).to_dict())

# ---- 3. 残差 ----
d["fitted"] = m.fittedvalues
d["resid"] = m.resid
fig, ax = plt.subplots(figsize=(7, 4.5))
for s, c, lab in [(1, "#1f77b4", "Shorts"), (0, "#ff7f0e", "Long")]:
    q = d[d.is_short == s]
    ax.scatter(q.fitted, q.resid, s=14, alpha=0.6, c=c, label=lab)
ax.axhline(0, color="gray", lw=1)
ax.set_xlabel("fitted log(1+views/day)"); ax.set_ylabel("residual"); ax.legend(); ax.set_title("Residuals vs fitted")
fig.tight_layout(); fig.savefig(IMG / "regression_residuals.png", dpi=120)
top = d.reindex(d.resid.abs().sort_values(ascending=False).index).head(5)
print("\n残差の大きい上位5本:")
print(top[["title", "content_type", "published_date", "views", "views_per_day", "resid"]].round(2).to_string(index=False))

# ---- 4. 5-fold CV ----
kf = KFold(n_splits=5, shuffle=True, random_state=42)
r2 = cross_val_score(LinearRegression(), d[X], d["log_views_per_day"], cv=kf, scoring="r2")
print(f"\n5-fold CV R2: 平均 {r2.mean():.3f}  標準偏差 {r2.std():.3f}  各fold {np.round(r2, 3).tolist()}")

# ---- 5. Power BI 用に倍率と 95%CI を書き出す ----
label = {"is_short": "Shorts（長尺比）", "days_since_publish": "公開から1日", "is_weekend_publish": "土日に公開",
         "is_holiday_publish": "祝日に公開", "log_duration": "長さ（e倍）", "ctr_pct": "クリック率+1pt"}
rows = []
for model, tab in [("全体", cmp.rename(columns={"95%CI下(HC3)": "ci_low", "95%CI上(HC3)": "ci_high", "p値(HC3)": "p"})),
                   ("長尺", cmp_l.rename(columns={"95%CI下": "ci_low", "95%CI上": "ci_high", "p値(HC3)": "p"}))]:
    for k, r in tab.drop(index="Intercept").iterrows():
        rows.append({"model": model, "variable": label.get(k, k), "ratio": r["倍率"], "ci_low": r["ci_low"],
                     "ci_high": r["ci_high"], "p_value": r["p"], "significant": int(r["p"] < 0.05)})
pd.DataFrame(rows).round(4).to_csv(DOCS / "regression_ratios_ci.csv", index=False, encoding="utf-8-sig")
print("\n保存: docs/regression_ratios_ci.csv, images/regression_residuals.png")
