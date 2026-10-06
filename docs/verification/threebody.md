# Three-Body Problem — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/threebody/index.html` (before the fixes; run
`dlab.dev.captureVerification("threebody")` to make them again)

## Model as implemented

**Restricted problem** (`cr3bpRhs.m`, `simulateCr3bp.m`): the rotating frame with the primaries
at (−μ, 0) and (1 − μ, 0), ẍ − 2ẏ = Ω_x, ÿ + 2ẋ = Ω_y, z̈ = Ω_z with Ω = ½(x² + y²) + (1 − μ)/r₁ +
μ/r₂, units of the separation, the total mass, and 1/(angular rate); `ode113` (RelTol 10⁻¹²),
stopped by collisions with the primaries' radii. The Jacobi constant C = 2Ω − v², the inertial view
(rotation by t), the Lagrange points (collinear equation bracketed between and beyond the
primaries; L4/L5 at (½ − μ, ±√3/2)), and the exact linearization (`cr3bpJacobian.m`: the Hessian of
Ω and the Coriolis block) all checked by hand.

**N bodies** (`simulateNBody.m`): G = 1, optional softening r² + ε², `ode113` (RelTol 10⁻¹²);
energy, momentum and angular momentum drifts relative to their scales.

**Systems:** Earth–Moon μ = 0.01215058 (384 400 km, a sidereal month 27.321661 days), Sun–Earth
3.0035·10⁻⁶, Sun–Jupiter 9.5388·10⁻⁴ (7.7857·10⁸ km, 4332.59 days): the published values.

**Against the docs page and `about()`:** they match, except that the docs gave the Lyapunov
orbit's period as 2.7429, which is its half period (finding 3).

## Reference values

Independent of the engine: my own CR3BP and N-body integrations (scipy DOP853, rtol 10⁻¹³), the
Lagrange points and Jacobi constants from `brentq`, and the classic orbits' published initial
conditions (Arenstorf's; Simó's figure-8).

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Arenstorf orbit, μ = 0.012277471, T = 17.0652165601580 | L1 0.8362925909, L2 1.1561681659, L3 −1.0051155116; C(L1) 3.1895084, C(L2) 3.1731592; C₀ 2.8564125; closest 0.463275 and 0.00627747; return error 3.4·10⁻¹⁰ | 0.8362926, 1.156168, −1.005116; 3.189508, 3.173159; 2.856413; 0.4632805, 0.006277471; 4.6·10⁻⁸ | ode113 at 10⁻¹² | ✓ |
| Earth–Moon (μ = 0.01215058) | L1 0.8369151534, L2 1.1556821439, L3 −1.0050626435; C(L1) 3.1883411, C(L2) 3.1721604 | 0.8369152, 1.155682, −1.005063; 3.188341, 3.17216 | 0 | ✓ |
| Tadpole at L4, 100 units | C₀ 2.9881227; closest 0.980922 (377 067 km) and 0.924224 (355 272 km); 434.84 days | 2.988123; 0.9809223 (377 066.5 km), 0.9242235 (355 271.5 km); 434.8377 | 0 | ✓ |
| Lyapunov orbit at L1, one period 5.4858 | C₀ 3.1743732; closest to the Moon 0.133066 (51 151 km); return error 5·10⁻⁷; after two periods 0.73 from the start | 3.174373; 0.1330658 (51 150.5 km); 6.7·10⁻⁷ | 0 | ✓ (finding 2: the lesson's run) |
| Through the L1 neck | C₀ 3.17 < C(L1); closest to the Moon 0.019411 | 3.17; 0.01946561 | 0.3 % (closest sample) | ✓ |
| Sun–Jupiter Trojan | L1 0.9323654771, C₀ 2.9990527; closest 0.955501 | 0.9323655, 2.999053, 0.9555008 | 0 | ✓ |
| Figure-8, T = 6.32591398 | return error 7.5·10⁻⁸; closest approach 0.690527 | 7.544·10⁻⁸; 0.6905266 | 0 | ✓ |
| Lagrange triangle, three equal masses | a circle at speed 1 and period 2π/√3 (return error 6·10⁻¹³ after one); unstable: sides within 2·10⁻⁵ to t = 20, changed by 3.2 at t = 40 | at t = 20 (the preset's end): closest 0.99999, "return error 4.0" (5.51 periods, not a breakup) | — | ✓ (finding 4) |
| Pythagorean 3-4-5, 20 units | closest approach 0.0059746 | 0.005975143 | 10⁻⁴ | ✓ |
| Lesson numbers | saddles at L1–L3; ẏ₀ 0.03 gives C 3.189408 > C(L1) 3.188341; Routh 0.0385; the Moon 1.2 %; Arenstorf 1963, return better than 10⁻⁶ | as stated (the unravelling after finding 2) | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves quickly headless; every Summary number reaches
the metrics; every exported column has its units; no non-finite values; a second solve gives the
identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass (presets, undo, a scenario round trip, the exports and report, a GIF, Sweep, Map,
Uncertainty, a short optimization, Modes, theme and text-size switches).

### Tests

`tests/sims/threebody` (new: `inputsFitAndExplainThemselves`, `summaryUnitsAndTheTriangleBreaksUp`;
`lagrangePointModes` extended for findings 6–8), `PluginConformanceTest` for `ThreeBodyPlugin`,
`TestLessons` for its lesson, `ArchitectureTest`, and, for the shared changes, `tests/core/TestAnalysis`
and the attractor tests: 108 + 18 passed, 0 failed. None excluded. `codeIssues` on every touched
file: 0. `TestAnalysis/animationRecordsEveryAxesInTheGrid` failed once in four runs (the inset's
pixel read before it was drawn), in code these changes do not touch, so left as a known flaky test. After
the shared changes the whole suite was run (`buildtool ptest`, with the rocket, entry and attitude
fixes too): 1401 tests, 0 failed, 0 errors.

## Checklist

- [x] Physics: the equations, the Jacobi constant, the Lagrange points, the linearization, the
  N-body forces and invariants checked by hand; the docs' period fixed (finding 3)
- [x] Numbers: every preset against my own integrations
- [x] Inputs: labels, ranges, tooltips (added for eleven, finding 5), visibility by model
- [x] Outputs: every tab readable in both themes and at Larger text
- [x] Summary and exports: units only in the units column (finding 1)
- [x] Analysis: Modes at each Lagrange point (saddles, oscillations, Routh's limit), now named and
  in time units (findings 6–8); Sweep and Map
- [x] Teaching: every lesson number checked; the first step's run lengthened (finding 2)
- [x] Behaviour: readable errors (starting inside a primary, bad bodies); collisions end the run
  with a note; nothing left behind

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | The N-body drifts had "relative" in the units column, and the Earth–Moon rows doubled their units ("Closest to Earth (km)" in km, "Duration (days)" in days). | "Energy drift (relative)" etc. with no units; "Closest to Earth in km", "Duration in days". | `summaryUnitsAndTheTriangleBreaksUp` |
| 2 | Teaching | The first step said "watch the orbit unravel after a couple of loops", but the Lyapunov preset runs exactly one period and returns to within 7·10⁻⁷: nothing unravels. | The step runs three periods (16.457): the orbit leaves in the second loop (0.73 from the start after two). | `TestLessons` |
| 3 | Physics | The docs gave the Lyapunov orbit's period as 2.7429; that is the half period differential correction finds, and the preset runs 5.4858. | Corrected. | — |
| 4 | Outputs | The equal-mass triangle, which the docs say "eventually breaks up", ran 20 units: it held its shape to 2·10⁻⁵, and its "return error" of 4.0 only meant that 20 is 5.51 periods. | 40 units: it keeps its shape to t ≈ 20, then breaks up. | `summaryUnitsAndTheTriangleBreaksUp` |
| 5 | Inputs | Choices were cut off ("Restricted (two primaries + a small body)", "Custom mass ratio", "Rotating with the primaries"), and eleven inputs had no tooltip. | "Restricted" / "N bodies", "Custom", "Rotating" / "Inertial", explained in the tooltips. | `inputsFitAndExplainThemselves` |
| 6 | Analysis | Both halves of the saddle at L1–L3 were called "Saddle (unstable)", and the second one's Stability said "Stable" (λ = −2.934, which is right for that direction). | "Saddle, growing direction" (Unstable) and "Saddle, decaying direction" (Stable); the lesson and docs follow. | `lagrangePointModes` |
| 7 | Analysis (shared) | The Modes table and pole plot said 1/s, rad/s and s, but the model's time is dimensionless (1/n: 4.348 days for Earth–Moon). The Attractors sheet had accepted the same thing (its finding 20). | A linearization may name its `TimeUnit`; the table's columns, the pole plot's axes and the exported mode units use it ("Period (time units)"). Three-body and attractors give "time unit"; the note says what one is in days for a named system. | `lagrangePointModes`, `TestAnalysis/saddlesAndNonEquilibriaAreFlagged`, `modesAtTheEquilibrium` (attractors) |
| 8 | Analysis (shared) | At Earth–Moon's L1 the in-plane oscillation read "−1.943e−16 ± 2.334i" with ζ 8.3e−17: round-off from the numerically found point, while Stability said Neutral. | Real parts within the same tolerance as the stability test are shown as 0. | `lagrangePointModes` |
