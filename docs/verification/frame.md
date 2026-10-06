# 2-D Frame and Beam Solver — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/frame/index.html` (122 pictures before the fixes; `after-*.png` after
them: the gable frame's deflected shape and Summary, and the propped cantilever at Larger text in
the light theme; run `dlab.dev.captureVerification("frame")` to make them again)

## Model as implemented

**Solver** (`frame_engine.m`): Euler–Bernoulli beam-column elements, three degrees of freedom
per node (u, v, θ, θ anticlockwise). The local stiffness has EA/L and 12EI/L³, 6EI/L², 4EI/L,
2EI/L; T = blkdiag(R, R) turns it into global axes. Element loads enter as consistent nodal
loads: uniform q gives [q_x L/2, q_y L/2, q_y L²/12, q_x L/2, q_y L/2, −q_y L²/12]; a point load
P at a gives P b²(3a + b)/L³, P a b²/L², … (checked against the fixed-end tables). Projected
loads are per horizontal (or vertical) length: w_y |c|, w_x |s|. Hinges are condensed out and
their rotations recovered afterwards; a node where every element end is hinged has its rotation
held (it carries no moment). A mechanism is found from the scaled stiffness's null vector.

**Diagrams:** N, V, M from the end forces and the loads (V' = q, M' = V; M positive sagging and
drawn on the tension side, which I checked holds for elements in any direction); the deflection
is the Hermite cubic through the end displacements plus the fixed-end beam's particular solution
(w x²(L − x)²/24EI for a uniform load, the standard point-load forms). Since this round: 101
points per element plus the zero-shear points of uniform loads (finding 1).

**Indeterminacy:** 3m + r − 3j − releases, with k hinged ends at an otherwise free node counted
as k − 1.

**Against the docs page and `about()`:** they match; the docs now say how the maxima are found.

## Reference values

Independent of the engine: closed forms, and my own frame solver in Python (numpy), written
separately: each element split into 200 sub-elements with the distributed loads lumped at their
nodes (no fixed-end-load formulas), so a different discretization; it reproduces the closed forms
below to 10⁻⁵ before being used for the frames. E = 200 GPa, A = 53.8 cm², I = 8356 cm⁴
(EI = 16.712 MN·m²).

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Cantilever 4 m, 10 kN at the tip | PL³/3EI = 12.76528 mm, PL²/2EI = 4.78698 mrad, root moment 40 kN·m | 12.7653, 4.78698, 40 | 0 | ✓ |
| Simply supported 6 m, 5 kN/m | wL²/8 = 22.5 kN·m at 3 m; 5wL⁴/384EI = 5.04877 mm; end rotations ±2.69268 mrad | 22.5 at 3 m, 5.04877, ±2.69268 | 0 | ✓ |
| Fixed-end 6 m, 5 kN/m | end moments wL²/12 = 15, mid-span wL²/24 = 7.5 kN·m; δ = wL⁴/384EI = 1.00975 mm | 15, 1.00975 | 0 | ✓ |
| Propped cantilever 5 m, 4 kN/m | prop 3wL/8 = 7.5 kN; root wL²/8 = 12.5 kN·m; sagging peak 9wL²/128 = 7.03125 kN·m at 5L/8; δ_max = 0.0054161 wL⁴/EI = 0.81021 mm at 0.578 L from the root | 7.5, 12.5; δ_max 0.807803 mm before, 0.81021 after | 0.3 % low before | ✗ → ✓ (finding 1) |
| Continuous beam, 3 × 5 m, 5 kN/m | support moments 0.1 wL² = 12.5 kN·m; reactions 0.4 wL = 10, 1.1 wL = 27.5 kN | 12.5; 10, 27.5, 27.5, 10 | 0 | ✓ |
| Portal frame (my solver) | sway at B 2.59566 mm; reactions H 3.38612 / −13.38612 kN, V 27.33701 / 32.66299 kN, M 0.9075 / 23.11456 kN·m; max \|M\| 30.430 kN·m at C | 2.59566; 3.38633 / −13.38633, 27.33701 / 32.66299, 0.90722 / 23.11484; 30.4305 | 10⁻⁴ (lumping) | ✓ |
| Gable frame (my solver) | ridge down 2.00250 mm (and 0 sideways); thrust 1.89665 kN; reactions 8 kN; max \|M\| 7.58659 kN·m at the eaves | 2.00251; 1.89666; 8; 7.58663 | 10⁻⁵ | ✓ |
| Lesson numbers | 12.77 mm; 22.5; 15 and 7.5 kN·m; a fifth of the deflection; a few mm of sway (2.6) | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.21 s headless; every Summary number
reaches the metrics; every exported column has its units, with no non-finite values; a second
solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 6.5 s for the first run while MATLAB warms
up, median 1.0 s); a scenario round trip; CSV (node, ux, uy, rotation, with units), MAT, plot,
and report exports (6 images); theme and text-size switches keep the result. Undo, Sweep, Map,
Optimize and Uncertainty have nothing to act on: every model input is a table (accepted below).

### Tests

`tests/sims/frame` (new: `testProppedCantileverPeakDeflection`, `summaryAndLabelsAreClean`),
run with the truss's: 88 passed, 0 failed, and the frame's app tests again after the last fix
(FRAMEUI). None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: element stiffness, fixed-end loads, projection, hinges, signs and the diagrams'
  tension side checked by hand; they match the docs page and `about()`
- [x] Numbers: every preset against closed forms or my own solver; a hinge, a point load, a
  mechanism (tests)
- [x] Inputs: tables with units; tooltips added to the tables and display options; presets load
  what their names say
- [x] Outputs: every tab readable in both themes and at Larger text; diagrams on the tension
  side; labels without rounding noise
- [x] Summary and exports: Summary, tables and CSV agree; units only in the units column; no
  NaN shown; the report is complete
- [x] Analysis: nothing to sweep (accepted)
- [x] Teaching: every lesson statement and number checked (all right)
- [x] Behaviour: readable errors (mechanism with its node and direction, bad references); drags
  are one undo step; nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | The maxima were read from 21 points per element: the propped cantilever's largest displacement was 0.8078 mm for 0.8102 (0.3 % low), and a sagging moment peak between points could be missed (by 2·10⁻⁴ with 101 points). | 101 points plus the exact zero-shear points of uniform loads: moments exact, deflections within 10⁻⁵. | `testProppedCantileverPeakDeflection` |
| 2 | Summary | The units column held prose: "m from the element start", "relative". | "Max \|M\| position (from the element start)" in m; "Equilibrium residual (relative)" with no units. | `summaryAndLabelsAreClean` |
| 3 | Outputs | The gable's deflected-shape label read "C: −8.4e−15, −2 mm" (rounding noise for a ridge that moves straight down). | Values below 10⁻⁹ of the largest are shown as 0. | `summaryAndLabelsAreClean` |
| 4 | Inputs | The element, support and node-load tables and two display options had no tooltip (the support types and the moment's sign were explained nowhere in the app). | Tooltips: what each column means, the support types, M positive anticlockwise. | — |

Accepted:
- **No Analyze tools.** Every model input is a table, so Sweep, Map, Optimize and Uncertainty
  have nothing to vary; a load factor would only show that the model is linear (the truss has
  one, with its strength check to make it useful).
- **The input tables scroll sideways** in the input panel (E, A, I and the hinges of the
  elements table): seven columns do not fit its width.
- **The CSV export holds the node displacements only**; the MAT export has the reactions, end
  forces and diagrams.
