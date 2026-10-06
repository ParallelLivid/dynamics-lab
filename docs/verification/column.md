# Column Buckling — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/column/index.html` (90 pictures before the fixes; `after-*.png` after
them: the defaults' deflected shape, Summary and End conditions, the elastica preset's
load–deflection, column curve and Summary, the flagpole at Larger text in the light theme, and
the elastica at 3 P_cr; run `dlab.dev.captureVerification("column")` to make them again)

## Model as implemented

**Euler** (`eulerModes.m`): P_cr = π² EI/(K L)², K = 1, 2, π/β, 1/2 with β = 4.4934095 the first
root of tan β = β. I derived the fixed–pinned mode from w'''' + k² w'' = 0 with w(0) = w'(0) = 0,
w(1) = w''(1) = 0: w = β(1 − cos βx) − βx + sin βx and tan β = β, as the code has it. Modes are
scaled to a largest value of 1.

**Imperfection** (`column_engine.m`): a bow e0 φ grows to δ = e0/(1 − P/P_cr), exact for any end
condition when the bow is the mode. The bending moment is EI (w − w0)'' = EI (δ − e0) φ'', and
with δ − e0 = ρδ its peak is m P δ, m = EI max|φ''| / P_cr: 1 (pinned, fixed–free at the base),
1/2 (fixed–fixed), √(β² + 1)/max φ = 0.73264 (fixed–pinned, at x = 0.65 L, larger than the
base's β/max φ). First yield (Perry–Robertson) is the smaller root of
σ² − σ(σ_cr(1 + η) + σy) + σy σ_cr = 0, η = m e0 c A / I, which I rederived from
σ (1 + η/(1 − σ/σ_cr)) = σy. The column curve holds e0/L, so η = m (e0/L) λ c/(K r). Southwell:
Δ = δ − e0 gives Δ/P = Δ/P_cr + e0/P_cr, so the slope is 1/P_cr and intercept/slope is e0.

**Elastica** (`elastica.m`): θ'' + μ sin θ = 0, μ = π² ρ in units of the effective length;
shooting finds α with the first θ = 0 at s = 1/2; for a given α, μ = (2T)² with T the quarter
length at μ = 1, i.e. ρ = (2K(k)/π)². Fixed–free is the piece s ∈ [0.5, 1] of the curve of length
2L (a crest at the fixed base, the free tip at the inflection point) and fixed–fixed s ∈ [0.5, 2.5]
of length L/2 (two crests apart): the deflections are one and two crests, and the shortening is
L(2 − 2E/K) for all three. The largest moment is P times the crest's offset from the line of
thrust, in all three.

**Against the docs page and `about()`:** they match, except that `about()` gave m as "1, or 1/2
for fixed–fixed", leaving out fixed–pinned's 0.733 (finding 9).

## Reference values

Independent of the engine: closed forms, elliptic integrals (scipy `ellipk`, `ellipe`; no
shooting), and my own finite-difference solver in Python for the bowed column, which does not
use the amplification formula: EI (w − w0)'''' + P w'' = 0 on 2000 intervals with the end
conditions written as ghost-node rows (pinned: w = 0, (w − w0)'' = 0; fixed: w = 0, w' = 0), and
for fixed–free the integrated form EI (w − w0)'' = P (w_tip − w) (my first version imposed the free
end's shear with a one-sided row and was 0.24 % off; this one agrees at 2000 and 8000 intervals).
First yield is the root of its largest stress = σy (brentq).

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Fixed–pinned β, K, m | tan β = β: β = 4.4934095, K = 0.6991557; m by finite differences of φ'' 0.73264 | the same | 0 | ✓ |
| Defaults: tube 60 × 4, 3 m, steel, 40 kN, e0 3 mm | P_cr 60.81089 kN; r 19.84943 mm; λ 151.1378; limit 88.85766; A σy 175.9292 kN; δ 8.76621 mm (×2.92207); σ 94.7812 MPa; first yield 54.5655 kN | 60.81089, 19.84943, 151.1378, 88.85766, 175.9292, 8.766212, 94.78121, 54.56553 | 10⁻⁵ (FD) | ✓ |
| Flagpole: fixed–free, 6 m Al tube 100 × 3, 2 kN, e0 6 mm | P_cr 5.089767 kN; tip δ 9.883788 mm; σ 3.106054 MPa; first yield 5.063207 kN | 5.089767, 9.883788, 3.106054, 5.063207 | 0 | ✓ |
| Timber post: fixed–fixed 100 mm square, 3 m, 100 kN | P_cr 402.095 kN (the lesson's "about 400"); A σy 210 kN; λ 51.96 against 71.90; δ 3.99302 mm; σ 11.1979 MPa; first yield 180.519 kN | 402.095, 210, 51.96152, 71.90127, 3.993065, 11.19792, 180.5175 | 10⁻⁵ | ✓ |
| Slender Al rod: 20 mm, 2 m, 0.8 P_cr, e0 2 mm | P_cr 1.337146 kN; λ 400; δ 10.0002 mm (×5); σ 17.0254 MPa; first yield 1.320595 kN | 1.337146, 400, 10, 17.02507, 1.320601 | 10⁻⁵ | ✓ |
| Near P_cr: defaults at 0.95 P_cr, e0 5 mm | δ 100.015 mm (×20.003); σ 707.27 MPa = 2.829 σy (the lesson's 2.8); first yield 51.2846 kN = 0.84 P_cr | 100, 707.1681, 2.828672, 51.28519 | 10⁻⁴ (FD) | ✓ |
| … Southwell with 3 % scatter | a straight-line fit of the app's eight points: P_cr 60.624 kN, e0 4.931 mm | 60.62411 (−0.31 %), 4.93131 | 0 | ✓ |
| Elastica: Al rod 10 mm, 1 m, 2 P_cr | K(k) = π√2/2: α = 124.5527°, crest 398.4807 mm, shortening 929.1382 mm, σ 2722.18 MPa (the lesson's "about 125°") | 124.5527, 398.4807, 929.1382, 2722.177 | 0 | ✓ |
| Fixed–pinned default tube, 40 kN | P_cr 124.4038 kN; δ 4.42178 mm; σ 70.8622 MPa; first yield 98.1375 kN | 124.4038, 4.421737, 70.86186, 98.1384 | 10⁻⁵ | ✓ |
| Fixed–free default tube, 10 kN | P_cr 15.20272 kN; δ 8.766212 mm; σ 23.6953 MPa; first yield 14.88182 kN | the same | 0 | ✓ |
| Fixed–fixed default tube, 100 kN | P_cr 243.2436 kN (the lesson's 243); δ 5.09415 mm; σ 169.661 MPa; first yield 138.929 kN | 243.2436, 5.094335, 169.663, 138.9289 | 10⁻⁵ | ✓ |
| Elastica fixed–free and fixed–fixed, 1.5 P_cr | α 98.67146°; tip 2365.727 mm; mid-height 1182.864 mm; shortening 1909.235 mm in both | the same | 0 | ✓ |
| Lesson: the tube at 6 m | P_cr 15.20272 kN, a quarter | 15.20272 | 0 | ✓ |
| Ends of the elastica meet | 2E(k) = K(k): k = 0.90891, α = 130.71°, ρ = 2.18338 | — (finding 6) | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.14 s headless (0.95 s for the first,
while MATLAB warms up); every Summary number reaches the metrics; every exported column has its
units (height, initial bow, lateral; m), with no non-finite values; a second solve gives the
identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 11.5 s for the first run while MATLAB warms
up, median 1.3 s); undo and redo of L; a scenario round trip; CSV, MAT, plot and report exports
(7 images); a sweep of L; a map; uncertainty of L ± 2 %; a short optimization of P_cr over L;
theme and text-size switches keep the result. The map ran over L × E, and E is hidden (and
ignored) unless the material is Custom: a flat map (finding 1). The check now picks inputs that
are in use.

### Tests

`tests/sims/column` (new: `inputsFitAndExplainThemselves`, `summaryRowsAreClean`,
`elasticaWarnsWhenItsEndsPass`, `analyzeVariesOnlyInputsInUse`): 21 passed, 0 failed; for the shared
change, `TestAnalysis`, `TestMap`, `TestOptimizePanel`, `TestUncertaintyPanel`, `TestLessons`,
`TestLessonChecks` and `TestShell`: 125 passed, 0 failed. None excluded. `codeIssues` on every
touched file: 0. The elastica preset now solves in 0.42 s headless (0.13 s before finding 7).

## Checklist

- [x] Physics: Euler loads, the fixed–pinned mode, moment factors, Perry–Robertson, Southwell, and
  the elastica pieces derived by hand; they match the docs page (`about()` fixed, finding 9)
- [x] Numbers: every preset, all four end conditions and both elastica pieces against my own
  solver and elliptic integrals
- [x] Inputs: labels, units, ranges, tooltips (added for nine inputs, finding 3), visibility
  (custom material and section, wall only for hollow shapes, the load or the ratio, the
  deflection scale only for the imperfect analysis); presets load what their names say
- [x] Outputs: every tab readable in both themes and at Larger text (findings 4, 5, 7, 8, 10)
- [x] Summary and exports: Summary, plots and CSV agree; units only in the units column
  (finding 2); the report is complete
- [x] Analysis: Sweep, Map, Optimize and Uncertainty no longer offer or accept hidden inputs
  (finding 1); no Modes or Bode (static)
- [x] Teaching: every lesson number checked; one statement fixed (finding 11)
- [x] Behaviour: readable errors (fixed–pinned elastica, a wall thicker than half D, a bow over
  L/10); nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Analysis (all simulators) | Sweep, Map, Optimize and Uncertainty listed inputs that the current inputs hide and the model ignores: the Map opened on L × E, and E is used only for a Custom material, so the map was flat in E. | Their defaults are inputs in use, and running one with a hidden input says "Young's modulus E is not used with the inputs set on the left, so varying it would change nothing." | `analyzeVariesOnlyInputsInUse` |
| 2 | Summary | The units column held prose ("1 = buckling, 0 = yield (perfect column)", "kN (with the initial bow)", "P / failure load", "1 / (1 − P/P_cr)", "deg (fixed–fixed: at the quarter points)", "kN (from the fitted slope)"); the imperfect analysis listed "Elastica end rotation 0" and "end shortening 0" (and past P_cr an elastica the analysis does not show); exact Southwell points gave an error of −1.2·10⁻¹⁴ %. | Units only; "Buckling governs" reads "yes (P_cr < A σy)" or "no: yield (A σy < P_cr)"; "Utilization P / failure load", "Southwell P_cr (fitted)", "Elastica rotation at the quarter points" for fixed–fixed; elastica rows only in the elastica analysis; rounding noise shown as 0. | `summaryRowsAreClean` |
| 3 | Inputs | Every choice was cut off in its field ("Pinned–pinne…", "Aluminium (6…", "Fraction of P_cr", "Small deflecti…"), and L, E, yield stress, section, t, A, load mode, P and the load ratio had no tooltip. | "Pin–pin", "Fixed–free", "Fixed–pin", "Fixed–fixed"; "Steel", "Aluminium", "Timber"; "Square bar"; "P / P_cr"; "Imperfect" / "Elastica"; the tooltips give K, the grades, and the formulas. | `inputsFitAndExplainThemselves` |
| 4 | Outputs | The Deflected shape's legend covered the base support (all of it at Larger text). | The legend sits top left, clear of the column. | screenshots |
| 5 | Outputs | The column curve's legend read "First yield, bow e0 = L/4503599627370496" with no bow (the elastica preset). | "Perfect column: the smaller of Euler and yield". | `summaryRowsAreClean` |
| 6 | Behaviour | Past 2.18 P_cr the elastica's ends pass each other (the shortening exceeds L), and nothing said so; the analysis allows 10 P_cr. | A warning: "past 2.18 P_cr the elastica's ends pass each other: a shape a real column and its supports cannot reach"; the docs say it. | `elasticaWarnsWhenItsEndsPass` |
| 7 | Outputs | The elastica's load–deflection and stress curves were drawn from 22 end rotations, 10° apart: visible kinks near the turn in deflection. | 1° steps to 10°, then 2.5°. | screenshots |
| 8 | Outputs | With no bow, the Load–deflection tab listed "Imperfect (e0 = 0 mm)" for a line hidden on the axis. | Drawn only with a bow. | screenshots |
| 9 | Physics | `about()` gave the moment factor as "1, or 1/2 for fixed–fixed", leaving out fixed–pinned (0.733). | All four. | — |
| 10 | Outputs | The End conditions tab had vertical grid lines at random places under its hidden x axis, and a y axis down to −0.5. | No x grid; ticks 0, 0.5, 1. | screenshots |
| 11 | Teaching | "243 kN … A flagpole (fixed–free, K = 2) gets a quarter of it" reads as a quarter of 243 kN; it is a quarter of the pinned 60.8 kN. | "…gets a quarter of the pinned column's: 15.2 kN." | — |

Accepted:
- **The deflected shape's x axis is in scaled metres** ("Lateral deflection × 34.2 (m)"): the
  title and the label both say so, and δ is labelled in mm on the shape.
- **The perfect column's first yield is reported at min(P_cr, A σy).** On the elastica a slender
  metal column yields a little above P_cr; the docs define the perfect column's failure load this
  way, and the stress check shows the curve.
- **The elastica ignores e0** (it is the perfect column); the Southwell plot still uses it.
