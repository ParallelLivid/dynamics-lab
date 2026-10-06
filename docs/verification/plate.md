# Heat in a Plate — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/plate/index.html` (before the fixes; `after-*.png` after them: the
Temperature field at Larger text in both themes, and the ADI Stability tab; run
`dlab.dev.captureVerification("plate")` to make them again)

## Model as implemented

**Scheme** (`simulatePlate.m`): finite differences on nx × ny nodes, edges included; each 1-D
operator has a mirrored ghost node at both ends (any edge type), convection adds −2αh/(kΔ) on its
diagonal and 2α hT∞/(kΔ) to the forcing, fixed nodes are set directly (a corner between two fixed
edges takes their average). Explicit FTCS, or Peaceman–Rachford ADI: x-implicit then y-implicit
half steps, each a tridiagonal solve per grid line. The largest stable explicit step is 2/(|μx| +
|μy|) from the 1-D operators' extreme eigenvalues.

**Energy:** stored heat with trapezoidal node areas, which the ghost-node operators conserve; the
heat through a fixed edge is what keeps its nodes at temperature (minus the operator's action on
them), and the ADI half steps are weighted as the scheme weights them. I checked the bookkeeping
term by term; it closes to rounding (unlike the 1-D rod's before its fix, this one was right).

**Exact solution:** a separable mode inside four edges fixed at T0 decays as
exp(−απ²(m²/a² + n²/b²)t); the Stability tab plots each scheme's growth factor per grid mode
(ADI: the product of one factor per direction).

**Against the docs page and `about()`:** they match.

## Reference values

Independent of the engine: the double sine series of the continuum hot spot (120 × 120 terms,
projections by quadrature), the discrete amplification factors, my own steady 2-D solver for the
fin (cell-centred finite volumes on 400 × 80 cells, the convection in series with half a cell:
a different discretization from the app's nodes), the 1-D fin formula, and closed-form source
integrals. Steel α = 1.299883·10⁻⁵ m²/s; aluminium 9.785705·10⁻⁵.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Hot spot (defaults): steel 0.2 m, 80 °C spot at (0.4, 0.55), edges at 20 °C, 60 s | series: max 37.875 °C (on a 201-point grid), mean 24.8868, probe (0.14, 0.1) 27.1282 | max 37.9166, mean 24.8817, probe 27.1225 | 2·10⁻⁴ | ✓ |
| … ADI step at r = ½ | Δt = 0.5 Δx²/α = 0.9616 s, shortened to 0.95238 (60/63) | 0.952381 | 0 | ✓ |
| Largest stable explicit step, 41 × 41, fixed edges | 2/(2 · (4α/Δx²) sin²(39π/80)) = 0.481555 s | 0.4815547 | 0 | ✓ |
| Separable mode (1,1), explicit r = 0.2, 300 s | exact λ = 2απ²/a² = 6.414666·10⁻³ 1/s; the scheme's discrete rate −ln(1 − 8r sin²(πΔx/2a))/Δt = 6.419287·10⁻³ (+0.072 %); amplitude at 300 s 7.28806 °C | decay rate 0.006419287, exact 0.006414666, error 0.07204 %, final max 27.28806 | 0 | ✓ |
| Explicit at r = ¼ / 0.3 | r_x + r_y 0.499 ≤ ½ stable; 0.6 > ½ grows (checkerboard × −1.4 per step) | stable / unstable | — | ✓ |
| ADI at r = 5: growth factors | fine along one direction −0.793, checkerboard +0.669, exact e⁻⁴⁰ | the Stability tab's points span −0.79 to +0.67 | 0 | ✓ (finding 2: the lesson's words) |
| Cooling fin: aluminium 0.2 × 0.04 m, 100 °C base, h 200 to 20 °C elsewhere | my 2-D solver: tip 56.750 °C, mean 71.333; 1-D fin with a convective tip: 56.53 °C (m = 6.4957 1/m) | at 900 s: probe (tip) 56.7406, mean 71.3326; at 3000 s 56.7436, 71.3346 | 10⁻⁴ | ✓ |
| Insulated aluminium plate, spot heater 10⁷ W/m³ peak, width 0.02 m at (0.06, 0.08), 5 mm, 300 s | power q d ∫e^(−r²/w²) dA = 62.83116 W; 18849.35 J; mean rise 38.9144 °C | generated 18849.31 J; mean 58.9143 °C | 2·10⁻⁶ | ✓ |
| Energy balance, every preset | stored change = heat in + generated | 10⁻¹¹ % or less | — | ✓ |
| Lesson numbers | peak from 100 to under 40 °C in a minute (37.9); checkerboard × −0.99 at r = ¼; 20 % too big blows up; twenty times the explicit step stable | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.3 s headless; every Summary number
reaches the metrics; every exported column has its units; no non-finite values except the
unstable preset's last fields, which it reports as unstable; a second solve gives the identical
result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 11.1 s for the first run while MATLAB warms
up, median 3.7 s with the six contour snapshots); undo and redo of a; a scenario round trip;
CSV, MAT, plot and report exports (6 images); a 10-frame GIF; a sweep of a; a map of a × b;
uncertainty of a ± 2 %; a short optimization over a; theme and text-size switches keep the result.

### Tests

`tests/sims/plate` (new: `inputsFitAndExplainThemselves`) and `TestLessons`: 62 passed, 0 failed.
None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: the ghost-node operators, convection, corners, ADI half steps, the stability
  bound and the energy bookkeeping checked by hand; docs and `about()` match
- [x] Numbers: every preset against series, discrete amplification factors, my own fin solver,
  and source integrals
- [x] Inputs: labels, units, ranges, tooltips (added for 22 inputs, finding 1), visibility (each
  edge's values by type, spot, mode, hot edge and heater inputs by choice, r or Δt)
- [x] Outputs: every tab readable in both themes and at Larger text (finding 3); the animation
  agrees with the snapshots and probes
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on a and b; no Modes or Bode
- [x] Teaching: every lesson number checked; one statement corrected (finding 2)
- [x] Behaviour: an unstable run stops with a readable warning; too many steps are refused;
  nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | Choices were cut off ("Fixed temper…" on all four edges, "Heat flux (0 = …", "ADI (Peaceman–…", "Stability number r", "Separable mode", "Spot (heater)"), and 22 inputs had no tooltip. | "Fixed T" / "Heat flux" / "Convection", "Explicit" / "ADI", "r" / "Time step", "Mode", "Heater"; the tooltips give the full names (FTCS, Peaceman–Rachford), what insulated means, and each position's axis. | `inputsFitAndExplainThemselves` |
| 2 | Teaching | The ADI step said that at very large steps "the shortest wavelengths are multiplied by nearly −1 and ring". For Peaceman–Rachford the factor is a product of one per direction: at r = 5 a pattern fine along one direction is multiplied by −0.79 and rings, but the checkerboard (fine along both) by +0.67, so it does not ring: it barely decays, where the exact factor is e⁻⁴⁰. | The success text gives both, with the numbers, and points at the Stability tab, which plotted them correctly. | `TestLessons` |
| 3 | Outputs | At Larger text the Temperature field's colour-bar label was cut off at the panel's edge ("T (°" on the defaults, gone on the fin). | The label sits above the bar. | screenshots |

Accepted:
- **The Energy tab's title gives the end-of-run residual in joules** (2·10⁻¹⁰ J for the defaults):
  rounding, and it shows the balance closes.
- **An unstable run's Summary lists its final extremes**, as in the rod: the status says it blew up.
