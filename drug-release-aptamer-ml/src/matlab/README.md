# MATLAB source

The original exploratory / figure-generation pipeline.

> **Scope note.** The machine-learning performance **reported in the manuscript**
> (Tables 1–3) is produced by the Python script in `../python`, computed on the
> six **real** experimental profiles only. The MATLAB code here covers kinetic
> fitting, exploratory analysis (EDA/PCA), figure generation, and the original
> (exploratory) augmentation. Any synthetic/augmented data are used for
> exploration only and never enter the reported ML metrics.

## Files

| File | Purpose |
|------|---------|
| `DrugReleaseAnalysis.m` | Core class: load/process dataset, EDA + PCA, kinetic model fitting (zero-, first-order, Higuchi, Weibull, modified first-order with lag), and the exploratory ML routines. |
| `DrugReleaseAnalysisGUI.m` | Interactive GUI wrapper for plotting and exporting figures (tabs per figure, styling controls, JPG export). |
| `augmentation.m` | Exploratory data augmentation by Weibull-parameter perturbation (α ±10%, β ±5%, 2% measurement noise, 10 synthetic curves per profile). For exploration only. |
| `plotSyntheticReleaseFigures.m` | Standalone script reproducing Figure 3/4-style EDA, PCA, and kinetic-fit panels. |

## Requirements

- MATLAB R2020b or newer (uses `uifigure`/`uigridlayout`, `boxchart`, `tiledlayout`).
- Statistics and Machine Learning Toolbox (`pca`, `fitrensemble`, `dummyvar`).

## Usage

```matlab
% From this folder (src/matlab):
ana = DrugReleaseAnalysis('..\..\data\drug_release_dataset.csv');  % or an .xlsx
ana = ana.runAnalysis('all', 'ByAptamer', true);

% Interactive GUI:
ana.launchGUI();
```

> The dataset loader accepts the columns `Drug, Aptamer, Time_hr, Release_%`
> (plus optional kinetic-descriptor columns). `readtable` reads both `.csv` and
> `.xlsx`. The paths hard-coded at the top of `augmentation.m` and
> `plotSyntheticReleaseFigures.m` should be updated to point at
> `../../data/drug_release_dataset.csv` on your machine.
