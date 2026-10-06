# 2-D Truss Solver — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/truss/index.html` (98 pictures before the fixes; `after-*.png` after
them: the footbridge's Summary, member forces, reactions and model, and a load-scaled triangle at
Larger text in the light theme; run `dlab.dev.captureVerification("truss")` to make them again)

## Model as implemented

**Solver** (`truss_engine.m`): the direct stiffness method for pin-jointed bars, two degrees of
freedom per node. Each bar contributes (EA/L)[c², cs; cs, s²] blocks; supports hold X and Y (pin),
X (roller), or Y (roller); K_ff U_f = F_f; member force N = (EA/L)[−c −s c s]·u (tension
positive); reactions K U − F at the held degrees of freedom. A mechanism is refused when
rcond(K_ff) < 10⁻¹².

**Strength check:** σ = N/A against the yield stress; in compression, |N| against the pin-ended
Euler load P_cr = π²EI/L²; utilization u = max of the two ratios; safety factor 1/max u. The
plugin multiplies the loads by the Load scale and the capacities by the Strength scale.

**Sections** (`dlab.physics.sectionLibrary`): tube A = π(D² − d²)/4, I = π(D⁴ − d⁴)/64; rod,
square box, solid square likewise (checked by hand); A36 steel 200 GPa / 250 MPa, 6061-T6 69 GPa /
276 MPa, C24 timber 11 GPa / 21 MPa (EN 338's characteristic compressive strength along the grain,
also used in tension, as the docs say).

**Against the docs page and `about()`:** they match.

## Reference values

Independent of the engine: every preset is statically determinate (m + r = 2j), so the member
forces and reactions follow from the joint equilibrium equations alone; I assembled and solved
them in Python (numpy), and computed each free displacement by virtual work (Σ N n L/EA with unit
loads), and the utilizations by hand formulas.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Simple triangle, 20 kN at the apex | sloping members −P/(2 sin 60°) = −11.5471 kN, base +5.7737 kN; reactions 0, 10, 10 kN; largest displacement 0.030551 mm | the same; 0.0305505 mm | 0 | ✓ |
| Pratt, five 12 kN loads | members 0, 20, 32, 32, 20, 0 / −20, −32, −36, −36, −32, −20 / posts −30, −30, −18, −12, −18, −30, −30 / diagonals +36.056, +21.633, +7.211 (×2) kN; 0.231274 mm | all 25 the same | 10⁻⁴ kN (print) | ✓ |
| Warren | chords ±17.32 … 62.354 kN, max 58.890 T / 62.354 C; 0.344378 mm | the same | 0 | ✓ |
| Howe | max 36 T / 36.056 C (diagonals in compression); 0.185599 mm | the same | 0 | ✓ |
| Cantilever truss | −30, −80, +42.43, +50, −30, −50, +42.43, +20, −20, −20, +28.28 kN; reactions 80, 30, −80 kN; 0.800454 mm | the same | 0 | ✓ |
| Fink roof | chords +26.667, rafters −33.333 / −25, struts −8.333, king post +10 kN; 0.214379 mm | the same | 0 | ✓ |
| Footbridge (steel tubes) | 4 posts at −100 kN in 60.3 × 3.2 tubes: u = 1.34918 (buckling), diagonal 20 at 0.98546 (yield); 4 fail; SF 0.74119; 33.92478 mm | the same | 10⁻⁵ | ✓ |
| … with 76.1 × 3.2 posts | largest web utilization 0.77188 (SF 1.2955) | lesson: "1.30, 0.77" | — | ✓ |
| Timber roof (75 mm C24) | rafters u = 1.45557 and 1.09166 (buckling), 4 fail; with 100 mm 0.46055 | the same | 10⁻⁵ | ✓ |
| Lesson: doubling E | largest displacement 0.23127 → 0.11564 mm, forces unchanged | "about 0.116 mm" | — | ✓ |
| Lesson: 76.1 against 60.3 mm tube | A +27.7 %, I ×2.078 | "28 % more steel … roughly doubled" | — | ✓ |
| Lesson: 100 against 75 mm square | I ×(4/3)⁴ = 3.16 | "3.2 times" | — | ✓ |
| Lesson: Monte Carlo, 10 % on the load | σ = 0.1 × 0.772 = 0.077 (the sample's 0.073); with 10 % on the strength too, √2 × that = 0.109 | "σ ≈ 0.073 … 0.11" | sampling | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.08 s headless; every Summary number
reaches the metrics; every exported column has its units; a second solve gives the identical
result. One failure: the export had non-finite values in every preset (1 to 15 each): the
"buckling_load" of members in tension or carrying nothing was Inf (finding 1).

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs (slowest 8.7 s for the
first run while MATLAB warms up, median 1.3 s); undo and redo; a scenario round trip; CSV, MAT,
plot, and report exports; a sweep over the load scale, a load × strength map, a 6-sample Monte
Carlo study, a short optimization; no animation, Modes or Bode (a static solver); theme and
text-size switches keep the result. The optimization picked "Members" (a count), the Summary's
first row, as its metric (finding 3).

### Tests

`tests/sims/truss` (new: `testEulerLoadForEveryMember`, `summaryNamesTiesAndHandlesNoLoad`,
`exportIsFiniteAndNamed`, `inputsFitAndCanvasShowsScaledLoads`; the drag test reads the table in
kN), `tests/sims/frame`, `PluginConformanceTest` for both plugins, `TestLessons` for their four
lessons, and `ArchitectureTest`: 88 passed, 0 failed, none excluded. `codeIssues` on every
touched file: 0.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
- [x] Numbers: every preset and the strength checks against the joint-equilibrium reference;
  zero loads; a strength scale
- [x] Inputs: labels, units, ranges, tooltips, visibility; presets load what their names say;
  the section editor's columns map to the right fields (checked in the code)
- [x] Outputs: every tab readable in both themes and at Larger text
- [x] Summary and exports: Summary, tables and CSV agree; units everywhere; no NaN or Inf shown
  or exported; the report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly on the load and strength scales
- [x] Teaching: every lesson statement and number checked (all three lessons right)
- [x] Behaviour: readable errors (mechanism, missing supports, bad references); drags are one
  undo step; nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Export | The "buckling_load" column was Inf for every member in tension or carrying nothing. | The column is each member's Euler load π²EI/L² (finite; it governs only in compression), named `euler_load`. | `testEulerLoadForEveryMember`, `exportIsFiniteAndNamed` |
| 2 | Export | Members were exported by index, not by the names the tables use. | Named (A-B, …). | `exportIsFiniteAndNamed` |
| 3 | Summary | The first rows were the member and degree-of-freedom counts, so Sweep, Optimize and Uncertainty offered "Members" by default. | Results first (tension, compression, displacement, the strength check), counts last. | `summaryNamesTiesAndHandlesNoLoad` |
| 4 | Summary | The footbridge's four end posts share the largest utilization, but the Summary named only one (F-M, picked by rounding). | "F-M (buckling) and 3 more as high". | `summaryNamesTiesAndHandlesNoLoad` |
| 5 | Summary | With no load the safety factor read "Inf" and the governing member "A-B ()". | "— (no load)" for both. | `summaryNamesTiesAndHandlesNoLoad` |
| 6 | Outputs | A zero-force member whose force was rounding noise (10⁻¹² N) was marked as governed by "yield". | Zero-force members are governed by nothing. | `exportIsFiniteAndNamed` |
| 7 | Outputs | The member-force table mixed "100000" and "1.4142e+05" N; the Summary uses kN. | Forces and reactions in kN, to 4 decimals. | `simpleTriangleMatchesReadme` (reads kN) |
| 8 | Inputs | "Strength check (utilization)" was cut off ("Strength che…"). | "Utilization" / "Force (T/C)", explained in the tooltip. | `inputsFitAndCanvasShowsScaledLoads` |
| 9 | Outputs | The Model canvas drew and labelled the nominal loads whatever the Load scale (already known). | Drawn as solved, scale included. | `inputsFitAndCanvasShowsScaledLoads` |

Accepted:
- **C24 timber uses its compressive strength (21 MPa) in tension too**; EN 338 gives 14.5 MPa in
  tension. One yield stress per section is the model; the docs and the library say so, and every
  timber member in the presets that fails does so in compression.
- **The input tables' tab strip scrolls** at the panel's width (Supports is behind the arrow);
  the arrow shows it, and the tab names cannot be shorter.
