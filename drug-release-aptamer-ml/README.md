# Kinetic-Informed Machine Learning for Aptamer-Induced Modulation of Drug Release in PEGylated Nanoliposomes

Code and data accompanying the proof-of-concept study:

> **Predictive Modeling of Aptamer-Induced Modulation in Drug Release Profile in Targeted PEGylated Nanoliposomes: A Proof-of-Concept Study**

This repository contains everything needed to reproduce the machine-learning
results reported in the manuscript, together with the original kinetic-modeling
and figure-generation pipeline.

---

## What this study does

Six in vitro cumulative drug-release profiles — three drugs (**Raloxifene,
Naringin, Etoricoxib**) under two surface conditions (**aptamer-functionalized
vs. non-functionalized control**) — are analyzed with:

1. **Classical release kinetics** — zero-order, first-order, Higuchi,
   Korsmeyer–Peppas, Weibull, and a modified first-order model with an explicit
   lag time (T_lag).
2. **Machine learning** — forecasting late-stage release (8–48 h) from early
   measurements (0–6 h) plus formulation descriptors.

**Important (reproducibility & honesty):** every reported ML metric is computed
on the **six real experimental profiles only**, using **leakage-free grouped
cross-validation** (a formulation's own measurements never appear in training).
No synthetic/augmented data enter the reported metrics.

Because each of the six profiles is a **single experimental run (no replicates)**,
this is explicitly a proof-of-concept; see the manuscript's Limitations section.

---

## Repository structure

```
drug-release-aptamer-ml/
├── README.md
├── LICENSE                     # MIT (code); data is CC BY 4.0 (see data/README.md)
├── CITATION.cff
├── requirements.txt
├── .gitignore
├── data/
│   ├── drug_release_dataset.csv    # the 6 real profiles (66 rows) — sole ML input
│   └── README.md                   # data dictionary
├── src/
│   ├── python/
│   │   └── leakage_free_forecast_reanalysis.py   # reproduces Tables 1–4
│   └── matlab/
│       ├── DrugReleaseAnalysis.m            # core class (kinetics, EDA/PCA, ML)
│       ├── DrugReleaseAnalysisGUI.m         # interactive GUI / figure export
│       ├── augmentation.m                   # exploratory augmentation only
│       ├── plotSyntheticReleaseFigures.m    # Fig 3/4-style figures
│       └── README.md
└── results/                    # (generated outputs; empty in version control)
```

---

## Quick start (Python — reproduces the reported numbers)

```bash
pip install -r requirements.txt
python src/python/leakage_free_forecast_reanalysis.py
```

The script defaults to `data/drug_release_dataset.csv`. It is fully deterministic
(ridge regression has a closed-form solution; no RNG), so results are identical
across runs and machines.

### Expected output (headline numbers)

| Method | R² | RMSE (% release) |
|--------|----|------------------|
| **ML — leave-one-formulation-out** | **0.943** | 4.63 |
| ML — leave-one-drug-out | 0.921 | 5.44 |
| Classical Weibull (0–6 h extrapolation) | 0.680 | 10.94 |
| Mean-profile baseline | 0.697 | 10.64 |
| Last-observation-carried-forward | −3.79 | 42.34 |

Aptamer effect sizes (aptamer = Yes minus No), from single runs:

| Drug | Δ release @2 h (pp) | Δt₅₀ (h) | Δt₈₀ (h) | ΔC∞ (pp) |
|------|------|------|------|------|
| Raloxifene | −5.2 | +5.9 | +12.3 | −5.7 |
| Naringin | −4.3 | +2.2 | +6.9 | −1.1 |
| Etoricoxib | −3.8 | +1.2 | +4.9 | 0.0 |

---

## MATLAB pipeline (original kinetics + figures)

See `src/matlab/README.md`. In brief:

```matlab
ana = DrugReleaseAnalysis('..\..\data\drug_release_dataset.csv');
ana = ana.runAnalysis('all', 'ByAptamer', true);
ana.launchGUI();   % interactive plotting & JPG export
```

Requires MATLAB R2020b+ and the Statistics and Machine Learning Toolbox.

---

## Data and Code Availability

All data underlying the findings and all author-generated code are in this
repository without restriction, satisfying the journal's data- and
code-sharing policy. Code is MIT-licensed; the dataset is CC BY 4.0.

---

## How to cite

See `CITATION.cff`. Please cite both the article and this repository (add the
Zenodo DOI once the repository is archived).

## Authors

Ali Olamat (ORCID 0000-0002-3544-7916), Ali Al-Samydai, Jamal I. Al-Nabulsi,
Hamdi Nsairat, Arwa Al-khatib, Hamza Abu Owida — Al-Ahliyya Amman University, Amman, Jordan.
