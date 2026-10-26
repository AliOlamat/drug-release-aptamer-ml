# Data

## `drug_release_dataset.csv`

The complete experimental dataset underlying the study: in vitro cumulative
drug-release profiles for **three drugs × two surface conditions = six
formulations**, each measured once (single experimental run; no replicates).
Each profile is sampled at 11 time points (0, 0.5, 1, 2, 4, 6, 8, 12, 24, 36,
48 h), giving 6 × 11 = **66 rows**.

This CSV is the **sole input** for all machine-learning results reported in the
manuscript. No synthetic/augmented data are included here or used in the
reported metrics.

### Columns

| Column          | Type    | Units | Description |
|-----------------|---------|-------|-------------|
| `Drug`          | string  | —     | Drug name: Raloxifene, Naringin, or Etoricoxib |
| `Aptamer`       | string  | —     | Surface condition: `No` (non-targeted control) or `Yes` (aptamer-functionalized) |
| `Time_hr`       | float   | hours | Sampling time point (0–48 h) |
| `Release_%`     | float   | %     | Cumulative percentage drug release at `Time_hr` |
| `Zero_k`        | float   | —     | Zero-order rate constant (per profile) |
| `First_k`       | float   | —     | First-order rate constant (per profile) |
| `Higuchi_k`     | float   | —     | Higuchi rate constant (per profile) |
| `KP_K`          | float   | —     | Korsmeyer–Peppas constant (per profile) |
| `KP_n`          | float   | —     | Korsmeyer–Peppas release exponent (per profile) |
| `Weibull_alpha` | float   | —     | Weibull scale parameter α (per profile) |
| `Weibull_beta`  | float   | —     | Weibull shape parameter β (per profile) |

The kinetic columns (`Zero_k` … `Weibull_beta`) are constant within a given
profile (they are per-profile fitted descriptors repeated across that profile's
11 rows).

### Notes

- **Single runs only.** Each (Drug, Aptamer) combination corresponds to one
  experimental run. There are no technical or biological replicates, which is
  why the analysis uses grouped cross-validation and reports descriptive
  (not inferential) effect sizes. See the manuscript, Section 4.7 (Limitations).
- **Aptamer-functionalized vs control** formulations were prepared identically
  and are compositionally equivalent except for surface aptamer conjugation.
- Physicochemical characterization (size, PDI, zeta potential, encapsulation
  efficiency, aptamer conjugation efficiency) is reported in the manuscript
  (Table 5).

## License

The data in this directory are released under
**Creative Commons Attribution 4.0 International (CC BY 4.0)**.
