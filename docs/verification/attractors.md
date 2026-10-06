# Strange Attractors — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/attractors/index.html` (142 pictures, taken before and again after the
fixes; run `dlab.dev.captureVerification("attractors")` to make them again)

## Model as implemented

**Equations** (`simulateAttractor.m`), dimensionless:

    Lorenz    x' = σ (y − x),       y' = x (ρ − z) − y,   z' = x y − β z
    Rössler   x' = −y − z,          y' = x + a y,         z' = b + z (x − c)
    Chua      x' = α (y − x − f(x)), y' = x − y + z,      z' = −β y
              f(x) = m1 x + ½ (m0 − m1)(|x + 1| − |x − 1|)   (slope m0 inside |x| < 1, m1 outside)

- **Integration:** `ode45` at RelTol 1e-10, AbsTol 1e-12 on nine states: the trajectory, a twin
  started `delta` away in x, and the tangent vector v' = J(x) v (Jacobians checked by hand; Chua's
  uses the diode slope of the side x is on). Samples every output step, the duration appended
  when the step does not divide it. A state beyond 10⁶ stops the run with "The trajectory ran off
  to infinity at t = …".
- **Largest Lyapunov exponent:** Benettin's method. v starts as (1, 1, 1)/√3 and is renormalized
  every round(10/dt) samples (10 time units); λ = (log growth from the end of the transient to
  the end) / elapsed time. The running estimate is shown from 2 time units after the transient
  (since finding 6).
- **Maxima** of z (Lorenz) or x (Rössler, Chua) after the transient: since finding 8, located by
  the solver's event detection (rate falling through zero), not interpolated between samples.
  Distinct values: greedy clustering at 10⁻³ · max(1, size); more than 32 is "chaotic" when also
  λ > 0.01. **Settled:** the last sample within 10⁻³ · max(1, size) of an equilibrium with a rate
  below the same.
- **Size** (`extent`): the largest range of x, y, or z after the transient. **Twins apart:** the
  first sample where |X − twin| > 10 % of the size.
- **Equilibria:** Lorenz origin and C± = (±√(β(ρ − 1)), ±√(β(ρ − 1)), ρ − 1) for ρ > 1; Rössler
  x = (c ± √(c² − 4ab))/2, y = −x/a, z = x/a; Chua origin and ±(k, 0, −k) with
  k = (m1 − m0)/(m1 + 1) ≥ 1 (since finding 9).
- **Modes** (`linearization`): the free system at Lorenz C+ (origin for ρ ≤ 1), Rössler's inner
  equilibrium, Chua's P+ (since finding 10); nothing when there is no equilibrium (finding 11).

**Against the docs page and `about()`:** the equations, signs, Benettin renormalization, and the
equilibria formulas match. Differences, now closed: the docs said the maxima were refined by a
parabola (now events, finding 8), Chua's outer equilibria exist "when |k| ≥ 1" (only k ≥ 1,
finding 9), and Chua's Modes were at "the equilibrium it circles, Chua's origin" (the scrolls
circle P±, finding 10). The input ρ was called the "Rayleigh number" (it is the ratio to the
critical one, finding 14).

## Reference values

Independent of the engine and its tests: closed forms, published values (Sprott, *Chaos and
Time-Series Analysis*, 2003; Lorenz 1963), and my own integrations in Python (SciPy DOP853 at
RelTol 1e-10…1e-12 with my own right-hand sides; the full Lyapunov spectrum by Benettin with QR
re-orthonormalization every 0.5 time units; maxima by event location). App values are the
Summary, Modes, and the engine's result, after the fixes unless marked.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Lorenz σ = 10, β = 8/3: Hopf point of C± | ρ_H = σ(σ + β + 3)/(σ − β − 1) = 24.7368 | Modes: C+ stable spiral −0.0072 ± 9.581i at ρ = 24.5, unstable 0.0940 ± 10.19i at 28 | — | ✓ |
| Lorenz ρ = 28: C± | (±8.485281, ±8.485281, 27); eigenvalues −13.854578, 0.093956 ± 10.194505i | equilibria the same; Modes −13.85, 0.09396 ± 10.19i | < 1e-6 | ✓ |
| Lorenz ρ = 28: origin | saddle, eigenvalues 11.8277, −2.6667, −22.8277 | listed among the equilibria | — | ✓ |
| Lorenz ρ = 28: Lyapunov spectrum | 0.9070, −0.0012, −14.5725 (QR, 2000 units); Sprott 0.9056, 0, −14.5723; sum −13.666667 = −(σ + 1 + β) to 4e-10 (constant divergence) | λ1 0.9045 (1000 units), 0.9110 (defaults, 90 units) | 0.002; 0.004 | ✓ (finite-time spread; the app gives λ1 only) |
| Lorenz ρ = 28: twins | ensemble growth rate of 40 twin pairs over 12 units 0.903 ± 0.136 | the app's twins grow at 0.898 over t = 14–31 (fit), λ = 0.911 | 1 % | ✓ (e^{λt}) |
| Lorenz ρ = 28: twins' distance from (1, 1, 1) | 1.245e-8 (t = 5), 2.378e-7 (15), 9.254e-6 (20), 1.97e-3 (25) (my twin pair) | 1.245e-8, 2.378e-7, 9.252e-6, 1.97e-3 | < 3e-4 relative | ✓ |
| Twins apart (10 % of the size) | 32.06 (mine) | 33.38 | 1.3 | ✓ (after t ≈ 25 the two integrators' own trajectories differ by as much as the twins: a forecast-horizon effect; the lesson says "about 30") |
| Lorenz maxima of z from (1, 1, 1), the first twelve | 47.840828629, 29.36233592, 29.507895129 … 31.535554048 (event location, RelTol 1e-12) | before: 2.5e-4 to 4e-3 off at dt = 0.01, 0.08 at dt = 0.05; after: 1e-9 at dt = 0.01, 0.05, 0.2 | 1e-9 | ✗ → fixed (finding 8) |
| Lorenz return map (successive maxima of z) | 13 227 maxima over 10 000 units: a cusp-shaped (tent-like) map on 30.14–47.13, peak at z_n = 38.554 → 47.130, slopes about +1.68 and −1.71, \|slope\| > 1 everywhere (Lorenz 1963) | 1198 points over 1000 units: range 30.62–46.69, peak at 38.555; distance to my map median 8e-4, max 0.031 (the map's own thickness) | — | ✓ |
| Lorenz ρ = 14 | settles on C+ = (5.887841, 5.887841, 13); slowest eigenvalue −0.394486 ± 7.326953i | end (5.887841, 5.887841, 13); λ = −0.39551; Modes −0.3945 ± 7.327i, −12.88 | 1e-3 (finite-time) | ✓ |
| Lorenz ρ = 24.0, 24.5 from (1, 1, 1) | still chaotic after 3000 units (the butterfly coexists with stable C± from ρ ≈ 24.06) | ρ = 24.5: chaotic, λ = 0.80 over 300 units | — | ✓ (tooltip and lesson reworded, findings 14, 15) |
| Lorenz ρ = 160 (preset: 60 units) | after a chaotic transient of about 20 units, a cycle with maxima 188.65839, 216.63417; λ ≈ 0 (second half: −0.003) | before: "periodic: 12 distinct maxima", λ = 0.098, Lyapunov time 10.2; after (half left out): 2 maxima 188.6584, 216.6342, λ = −0.0030 | 1e-6 | ✗ → fixed (finding 1) |
| Lorenz ρ = 0.5 | only the origin, stable; slowest eigenvalue −0.475062 | settles, λ = −0.47506; 1 equilibrium | 2e-6 | ✓ |
| Rössler a = b = 0.2, c = 5.7: spectrum | 0.0689, 0.0001, −5.3910 (5000 units); Sprott 0.0714, 0, −5.3943 | λ1 0.0704 (2000 units), 0.0765 (preset, 320 units) | 0.002; 0.008 | ✓ (finite-time) |
| Rössler c = 5.7: equilibria | inner (0.007026, −0.035131, 0.035131): 0.097001 ± 0.995193i, −5.686976; outer (5.692974, −28.464869, 28.464869): 0.192983, −4.6e-6 ± 5.428i | 2 equilibria; Modes 0.097 ± 0.9952i, −5.687 | < 1e-6 | ✓ |
| Rössler a = b = 0.2: period doubling | period-2 from c ≈ 2.80–2.83, period-4 from ≈ 3.84, period-8 ≈ 4.12, chaos from ≈ 4.20 (my scan, 1500 units, steps of 0.01–0.02) | c = 2.5, 3.5, 4.0: 1, 2, 4 distinct maxima; tooltip "chaos from about c = 4.2" | — | ✓ |
| Rössler c² < 4ab (a = 0.5, b = 2, c = 1) | no equilibrium; the motion runs off | "The trajectory ran off to infinity at t = 30."; before: Modes at a non-equilibrium; after: no Modes | — | ✗ → fixed (finding 11) |
| Chua α = 15.6, β = 28, m0 = −1.143, m1 = −0.714: equilibria | 0 and ±(1.5, 0, −1.5) (k = 0.429/0.286 = 1.5); origin 3.475642, −1.122421 ± 4.087987i; P± 0.305496 ± 4.525326i, −6.072592 | the same three; Modes at P+ 0.3055 ± 4.525i, −6.073 | < 1e-6 | ✓ |
| Chua: Lyapunov spectrum | 0.4276, 0.0007, −4.2341 (QR, 3000 units); over 1000 units from four starts 0.414–0.463; at m0 = −8/7, m1 = −5/7: 0.4372, 0.0004, −4.2167. The docs cite no published value at these constants. | λ1 0.4354 (1000 units), 0.4400 (preset, 135 units); 0.474 at −8/7, −5/7 (1000 units) | within the finite-time spread | ✓ (test tightened from λ > 0.2 to 0.43 ± 0.04, the finite-time spread; Linux CI gives 0.463) |
| Chua m0 = 2, m1 = 0 (k = −2) | only the origin: x = ±k lies outside the outer pieces | before: 3 equilibria (±(−2, 0, 2) are not equilibria: rate 4α); after: 1; settles, λ = −0.331 (eigenvalue −0.3331 ± 5.262i) | — | ✗ → fixed (finding 9) |
| Lesson: "λ ≈ 0.9: the forecast loses one digit every 2.5 time units" | ln 10 / 0.906 = 2.54 | λ = 0.911 | — | ✓ |
| Lesson: twins apart "about 30 time units" | 32 (mine), 33.4 (app) | 33.38 | — | ✓ |
| Lesson: "period-4 near 4.0, then chaos from about 4.2" | period-4 on 3.84–4.11, chaos from ≈ 4.20 | — | — | ✓ |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.5–1.2 s headless; every
Summary number reaches the metrics; every exported column has its units entry (time in "time
units", x, y, z and the twins' distance dimensionless, the transient flag) and no NaN or Inf; a
second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs; undo and redo; a
scenario round trip keeps every input; CSV (6 columns), MAT, plot, and report exports (the report
has every Summary row and 7 images); a 10-frame GIF; a sweep over σ, a σ × ρ map, a 6-sample
Monte Carlo study, and a short optimization of λ over σ (best 0.9335 at σ = 10.53); Modes shows
C+'s unstable spiral and stable direction; theme and text-size switches keep the result. A run in
the app takes 2–8 s, the slowest the first (MATLAB's plotting warm-up, K5). The longest allowed run
(5000 time units) solves in 34 s.

### Tests

`tests/sims/attractors` (22: 13 engine, 9 in the app; 10 of them new), `PluginConformanceTest`
for the plugin (14), `TestLessons` for "The butterfly effect" (1), `TestLessonChecks` (7), and
`ArchitectureTest` (10): 54 passed, 0 failed, none excluded. `codeIssues` on the engine, the
plugin, and both test files: 0. No shared code changed. The showcase (the butterfly's Attractor
tab) is unchanged, so the images were not made again.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (gaps closed: findings 8, 9, 10, 14)
- [x] Numbers: defaults, every preset, and edge cases (ρ = 0.5, 14, 24.5, 160, σ = 100 with
  ρ = 500, a twin offset of 1, Rössler with no equilibrium and with a = 0, Chua with k = −2 and
  with the exact 8/7, 5/7 slopes, the longest run) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (ρ and β reworded or added, finding 14), visibility
  rules (σ, ρ, β for Lorenz; a, b, c for Rössler; α, β, m0, m1 for Chua); presets load what they
  say (ρ = 160 now does, finding 1)
- [x] Outputs: every tab readable in both themes and at Larger text (142 screenshots, before and
  after the fixes); the animation's |Δ| readout agrees with the Sensitivity plot at the same time
  (1.6 at t = 50 in both, defaults)
- [x] Summary and exports: Summary, plots, and CSV agree; units hold units only; the report is
  complete
- [x] Analysis: Sweep (and the bifurcation diagram over c), Map, Optimize, Uncertainty run
  cleanly; Modes against hand values (Lorenz C+, Rössler inner equilibrium, Chua P+)
- [x] Teaching: the lesson passes, and its statements and numbers agree with the reference values
  (step 4 reworded, finding 15)
- [x] Behaviour: readable errors (unknown model, bad step, too many samples, Rössler a = 0,
  divergence); Cancel through the progress callback (covered by the suite); results survive theme
  and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | The "periodic window (ρ = 160)" preset left out only 6 of its 60 time units, but the motion is chaotic for its first 20 or so: it reported "periodic: 12 distinct maxima", λ = 0.098, and a Lyapunov time of 10.2. | The preset leaves out the first half: 2 maxima (188.658, 216.634, as my integration), λ = −0.003. | `testLorenzPeriodicWindow`, `periodicWindowIsPeriodic` |
| 2 | Summary | A periodic orbit whose estimate of λ came out slightly positive (Rössler c = 3.5: 0.0032) showed a "Lyapunov time" of 317 and a growth line on the Sensitivity tab. | Both only when λ > 0.01, the threshold the run note already used for chaos (the docs say so). | `summaryRowsSayWhatTheyMean`, `testGrowthLineFollowsTheTwins` |
| 3 | Outputs | The line δ·e^{λt} was drawn through δ at t = 0, but from (1, 1, 1) the twins' distance stays near 10⁻⁸ for 13 time units while the start spirals out from C+ (rate 0.094): the line reached the attractor's size at t ≈ 20, the twins at 33, so the line did not show the slope it claims to. | A line of slope λ fitted (in log) through the samples where the distance grows exponentially, labelled "∝ e^{λt}". | `testGrowthLineFollowsTheTwins` |
| 4 | Outputs | Twins that become identical (ρ = 14) were drawn at `realmin`: the log axis ran from 1 to 10⁻³⁰⁸ and the convergence was invisible. | Zero distances are not drawn; the axis shows the decay to rounding level (10⁻¹⁵). | `summaryRowsSayWhatTheyMean` |
| 5 | Outputs | The "apart at t = 33.4" label sat across the twins' curve. | At the bottom of the line. | — (layout) |
| 6 | Outputs | The running estimate of λ divides by almost nothing just after the transient: spikes of −7 (Chua) and 18 (ρ = 160) set the axis and flattened the curve. | Shown from 2 time units after the transient (or a tenth of the rest, if shorter). | `testRunningEstimateSkipsItsFirstMoments` |
| 7 | Outputs | The return map of a period-1 cycle (Rössler c = 2.5) zoomed into its slow convergence: a diagonal line of dots on an axis 0.004 wide. Period-2 points sat in the corners. | Axes at least a tenth of the attractor's size with a margin, centred on the points; larger dots for a cycle. | `returnMapOfACycleIsADot` |
| 8 | Numbers | Maxima were refined by a parabola through three samples: 2.5e-4 to 4e-3 off at the default step (7e-3 at ρ = 160), 0.08 at a step of 0.05, so the return map and the distinct count depended on the output step. | The solver's event detection locates each maximum: 1e-9 against my integration at steps 0.01, 0.05, and 0.2. | `testMaximaDoNotDependOnTheOutputStep` |
| 9 | Physics | Chua's outer equilibria ±(k, 0, −k) were listed whenever \|k\| ≥ 1, but for k ≤ −1 they are not equilibria (m0 = 2, m1 = 0: rate 4α there); the docs said the same. | Only for k ≥ 1; docs corrected. | `testChuaEquilibriaOnlyWhereTheyExist` |
| 10 | Physics | Modes for Chua were at the origin, "the equilibrium the motion circles", but the double scroll circles P± (unstable spiral 0.3055 ± 4.525i, stable direction −6.073); the origin is a saddle between them. | Modes at P+ when it exists (as Lorenz's at C+); docs updated. | `chuaModesAtTheScrollCentre` |
| 11 | Behaviour | Rössler with c² < 4ab has no equilibrium, but Modes clamped the discriminant and analysed a point that is not one; with a = 0 it divided by zero. | No Modes then. | `chuaModesAtTheScrollCentre` |
| 12 | Summary | "Distinct maxima" had "of z; > 32: chaotic" and "Settled at an equilibrium" had "yes = 1" in the Units column; a settled run showed "Distinct maxima 0". | Units empty; "yes"/"no"; "— (settled)". The metrics keep the numbers, so the lesson checks still work. | `summaryRowsSayWhatTheyMean` |
| 13 | Exports | The time column's unit "(model time)" became "time ((model time))" in the Custom plot. | "time units"; x, y, z and the distance are dimensionless (docs). | `summaryRowsSayWhatTheyMean` |
| 14 | Inputs | ρ was labelled "Rayleigh number" (it is the ratio to the critical one) and its tooltip said "Chaos above ρ ≈ 24.74", but the butterfly exists from ρ ≈ 24.06 (my runs at 24.0 and 24.5 stay chaotic for 3000 units) and has periodic windows above; β had no tooltip. | "ρ (relative Rayleigh number)" with a tooltip giving 24.74 (C± stable below), 24.06, and the windows; β described. | — |
| 15 | Teaching | Lesson step 4 said that below ρ ≈ 24.74 the motion spirals into one of the equilibria; between 24.06 and 24.74 it need not (ρ = 24.5 stays chaotic). | The text says the butterfly survives just below 24.74 and that well below it (ρ = 14) the motion spirals in. | `TestLessons` |
| 16 | Inputs | The twin offset could be 0: two identical runs and an empty Sensitivity plot. | Must be positive. | — |
| 17 | Outputs | A cycle's trajectory (0.7 px, drawn over itself) was hard to see against the grey transient in the Attractor tab (Rössler c = 2.5, 3.5). | 1.5 px for a cycle or a settled run. | — (layout) |
| 18 | Outputs | The time-series legend ("best") sat on the data (Rössler chaos). | One row above the axes. | — (layout) |
| 19 | Docs | The Chua reference was only "λ > 0.2", with no source. | λ = 0.43 ± 0.04 over 1000 units, from my integration (no published value at these constants is cited). ± 0.03 failed on Linux CI (0.463, round-off on another platform), inside the 0.414–0.463 spread already measured, so the tolerance now spans it. | `testChuaExponent` |
| 20 | Outputs (shared) | The Modes table's column units say 1/s, rad/s, s for a dimensionless model; at Larger text the playback time "100.0 / 100.0…" is cut. | The playback time: accepted (shared, still readable). The Modes units: fixed on 4 October with the three-body verification (finding 7 there): the columns say "1/time unit", "time units". | `modesAtTheEquilibrium` |
