#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Leakage-free forecasting re-analysis for:
"Predictive Modeling of Aptamer-Induced Modulation in Drug Release Profile
 in Targeted PEGylated Nanoliposomes: A Proof-of-Concept Study"

Reproduces the manuscript's Section 4.5 numbers (Tables 1, 2, 3) and the
Table 4 effect sizes, using ONLY the six real experimental release profiles
(no synthetic / augmented data).

Task: predict late-stage release (8, 12, 24, 36, 48 h) from early measurements
(0, 0.5, 1, 2, 4, 6 h) plus drug/aptamer descriptors.

Evaluation: grouped cross-validation, so a formulation's own points are never in
training. Two schemes are reported:
  - leave-one-formulation-out (6 folds)
  - leave-one-drug-out (3 folds; both conditions of a drug held out together)

Baselines (deterministic, leakage-free): last-observation-carried-forward (LOCF),
leave-one-out mean profile, and a classical Weibull model fitted to 0-6 h and
extrapolated to 48 h.

Deterministic: no random augmentation, no RNG. Ridge regression has a closed-form
solution, so results are exactly reproducible across runs and machines.

Usage:
    python leakage_free_forecast_reanalysis.py [path/to/drug_release_dataset.csv]

If no path is given, it defaults to ../../data/drug_release_dataset.csv relative
to this script. A .xlsx file is also accepted.

Requires: pandas, numpy, scipy, scikit-learn  (see requirements.txt)
"""
import os
import sys
import numpy as np
import pandas as pd
from scipy.optimize import curve_fit
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

RIDGE_ALPHA = 10.0          # regularization strength (stated in Methods)
EARLY_MAX_H = 6.0           # input window upper bound
LATE_MIN_H  = 8.0           # forecast target lower bound


def default_data_path():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "data",
                                         "drug_release_dataset.csv"))


def load_table(path):
    if str(path).lower().endswith((".xlsx", ".xls")):
        return pd.read_excel(path)
    return pd.read_csv(path)


def r2(y, yhat):
    y = np.asarray(y).ravel(); yhat = np.asarray(yhat).ravel()
    ss_res = np.sum((y - yhat) ** 2); ss_tot = np.sum((y - y.mean()) ** 2)
    return 1 - ss_res / ss_tot if ss_tot > 0 else np.nan


def rmse(y, yhat):
    return float(np.sqrt(np.mean((np.asarray(y).ravel() - np.asarray(yhat).ravel()) ** 2)))


def weibull(t, Cinf, alpha, beta):
    return Cinf * (1 - np.exp(-(t / alpha) ** beta))


def t_at(times, rel, target):
    times = np.asarray(times, float); rel = np.asarray(rel, float)
    if rel.max() < target:
        return np.nan
    for i in range(1, len(rel)):
        if rel[i-1] <= target <= rel[i]:
            if rel[i] == rel[i-1]:
                return times[i]
            return times[i-1] + (target - rel[i-1]) * (times[i]-times[i-1]) / (rel[i]-rel[i-1])
    return np.nan


def rel_at(times, rel, t):
    return float(np.interp(t, np.asarray(times, float), np.asarray(rel, float)))


def main(path):
    print("Loading:", path)
    df = load_table(path)
    drugs = list(dict.fromkeys(df['Drug']))
    aps = ['No', 'Yes']
    T = np.array([0, 0.5, 1, 2, 4, 6, 8, 12, 24, 36, 48], float)
    em, lm = T <= EARLY_MAX_H, T >= LATE_MIN_H
    Te, Tl = T[em], T[lm]

    profiles, labels = [], []
    for d in drugs:
        for a in aps:
            g = df[(df['Drug'] == d) & (df['Aptamer'] == a)].sort_values('Time_hr')
            profiles.append(g['Release_%'].values.astype(float))
            labels.append((d, a))
    P = np.array(profiles); E = P[:, em]; L = P[:, lm]
    n = len(labels)

    # ---- features: 6 early values + drug one-hot + aptamer flag ----
    def feats(i):
        d, a = labels[i]
        oh = [1.0 if d == dd else 0.0 for dd in drugs] + [1.0 if a == 'Yes' else 0.0]
        return np.concatenate([E[i], oh])
    X = np.array([feats(i) for i in range(n)])

    # ---- ML: grouped CV ----
    def cv(groups):
        pred = np.zeros_like(L)
        for gkey in dict.fromkeys(groups):
            te = [i for i in range(n) if groups[i] == gkey]
            tr = [i for i in range(n) if groups[i] != gkey]
            sc = StandardScaler().fit(X[tr])
            m = Ridge(alpha=RIDGE_ALPHA).fit(sc.transform(X[tr]), L[tr])
            for i in te:
                pred[i] = m.predict(sc.transform(X[i:i+1]))
        return pred

    ml_lofo = cv([i for i in range(n)])               # leave-one-formulation-out
    ml_lodo = cv([labels[i][0] for i in range(n)])    # leave-one-drug-out

    # ---- baselines ----
    locf = np.zeros_like(L); meanp = np.zeros_like(L); weib = np.zeros_like(L)
    for i in range(n):
        locf[i, :] = E[i, -1]
        others = [j for j in range(n) if j != i]
        meanp[i, :] = L[others, :].mean(axis=0)
        try:
            popt, _ = curve_fit(weibull, Te, E[i, :], p0=[100, 10, 1.3],
                                bounds=([50, 0.1, 0.3], [120, 100, 4]), maxfev=20000)
            weib[i, :] = weibull(Tl, *popt)
        except Exception:
            weib[i, :] = np.nan

    def report(name, pred):
        print("\n" + name)
        print("  pooled R2 = %.3f   pooled RMSE = %.2f" % (r2(L, pred), rmse(L, pred)))
        for i in range(n):
            print("    %-18s R2=%6.3f  RMSE=%5.2f" % (labels[i][0] + "/" + labels[i][1],
                                                      r2(L[i], pred[i]), rmse(L[i], pred[i])))

    print("=" * 64)
    print("LEAKAGE-FREE FORECASTING RE-ANALYSIS  (six real profiles only)")
    print("=" * 64)
    report("ML  (ridge, leave-one-formulation-out, 6 folds)  -> Table 2", ml_lofo)
    report("ML  (ridge, leave-one-drug-out, 3 folds)", ml_lodo)
    report("Baseline: classical Weibull 0-6h -> extrapolate", weib)
    report("Baseline: leave-one-out mean profile", meanp)
    report("Baseline: last-observation-carried-forward (LOCF)", locf)

    print("\nSUMMARY  -> Table 3")
    print("  %-40s %7s %7s" % ("Method", "R2", "RMSE"))
    for nm, pr in [("ML (leave-one-formulation-out)", ml_lofo),
                   ("ML (leave-one-drug-out)", ml_lodo),
                   ("Classical Weibull 0-6h extrapolation", weib),
                   ("Mean profile", meanp),
                   ("LOCF", locf)]:
        print("  %-40s %7.3f %7.2f" % (nm, r2(L, pr), rmse(L, pr)))

    # ---- Table 4 effect sizes (Yes - No) ----
    print("\nTABLE 4  effect sizes (Yes - No), from single runs")
    print("  %-12s %9s %7s %7s %7s" % ("Drug", "d_rel@2h", "d_t50", "d_t80", "d_Cinf"))
    for d in drugs:
        N = df[(df['Drug'] == d) & (df['Aptamer'] == 'No')].sort_values('Time_hr')
        Y = df[(df['Drug'] == d) & (df['Aptamer'] == 'Yes')].sort_values('Time_hr')
        dr2 = rel_at(Y['Time_hr'], Y['Release_%'], 2) - rel_at(N['Time_hr'], N['Release_%'], 2)
        dt50 = t_at(Y['Time_hr'], Y['Release_%'], 50) - t_at(N['Time_hr'], N['Release_%'], 50)
        dt80 = t_at(Y['Time_hr'], Y['Release_%'], 80) - t_at(N['Time_hr'], N['Release_%'], 80)
        dci = float(Y[Y['Time_hr'] == 48]['Release_%'].iloc[0]) - float(N[N['Time_hr'] == 48]['Release_%'].iloc[0])
        print("  %-12s %9.1f %7.2f %7.2f %7.1f" % (d, dr2, dt50, dt80, dci))


if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else default_data_path()
    main(p)
