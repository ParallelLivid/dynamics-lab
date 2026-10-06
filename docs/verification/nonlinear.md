# Nonlinear Oscillators — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/nonlinear/index.html` (177 pictures, taken before and again after the
fixes; run `dlab.dev.captureVerification("nonlinear")` to make them again)

## Model as implemented

**Equations** (`simulateOscillator.m`), one degree of freedom, forced by A cos ωt:

    Duffing         x'' + δ x' + α x + β x³ = A cos ωt
    Van der Pol     x'' − μ (1 − x²) x' + x = A cos ωt
    Pendulum        θ'' + θ'/q + sin θ = A cos ωt        (θ from straight down)

- Time is in seconds; the Van der Pol oscillator's and the pendulum's natural frequency is scaled
  to 1 rad/s, the Duffing's small-swing frequency is √α (α > 0), or √(−2α) at the bottom of a
  double well (α < 0 < β). x carries whatever unit the coefficients suit, θ is in radians.
- Forced means A ≠ 0 and ω > 0. A ≠ 0 with ω = 0 is a constant force, run as unforced.
- **Integration:** classical RK4 between output samples, n = ⌈Δt · rate / 0.1⌉ equal substeps,
  rate fixed at the start of each sample interval: √|α + 3βx²| + δ (Duffing),
  √|1 + 2μxv| + μ|1 − x²| (Van der Pol), 1 + 1/q + |θ'| (pendulum), plus ω, at least 0.5. When
  forced the samples fall on exact multiples of 2π/ω / samplesPerPeriod, so the stroboscopic
  section needs no interpolation; when free the samples are every 2π/samplesPerPeriod s, with the
  final time appended. Non-finite states stop the run with "The motion grew without bound".
- **Poincaré section:** forced, the samples at whole drive periods from ⌈transient · periods⌉ on
  (θ wrapped to (−π, π]); free, every maximum of x after the transient (x' crossing zero from
  above). Since the fix of finding 1, the sample interval holding a maximum is integrated again in
  at least 32 RK4 substeps (step · rate ≤ 0.05), and the crossing is found by cubic Hermite
  interpolation and Newton's method in the substep that holds it.
- **Distinct points:** greedy clustering at 10⁻³ of the motion's size (max(π, |θ'|) for the
  pendulum, θ on the circle); more than 32 is reported as chaotic or quasi-periodic. Spread is
  the largest range of either section coordinate (θ as an arc).
- **Steady amplitude** (max − min)/2 of x after the transient (none when a pendulum crosses an
  odd multiple of π after the transient); **cycle period** (free) the mean time between
  maxima; **spectrum** dlab.physics.amplitudeSpectrum (mean removed, Hann window, parabolic peak
  on log magnitudes) of x after the transient, of θ' for the pendulum; **energy** v²/2 + V(x),
  V = αx²/2 + βx⁴/4 or 1 − cos θ (none for Van der Pol).
- **Settled** (since finding 7): free motion after the transient smaller than 10⁻⁶ of the run's
  size; no dominant frequency is reported then.
- **Modes** (`linearization`): the free system at x = 0 (Duffing double well: the bottom of the
  well on the side of x0; pendulum hanging), modes named Oscillation, Settling, Growing, or
  Unstable (saddle).

**Against the docs page and `about()`:** the equations, signs, section, clustering, spectrum, and
modes match. Differences, now closed: the docs called the equations dimensionless while the
inputs, plots, Summary, and export use s and rad/s (finding 12); the hardening preset was said to
sit "on the upper branch, just below the jump", though at ω = 1.2 there is only one response
(finding 15); the docs said nothing about settled runs or a pendulum turning over the top.

## Reference values

Independent of the engine and its tests: closed forms (complete elliptic integral, Lindstedt,
harmonic balance, relaxation asymptotics), published results (Baker & Gollub, *Chaotic Dynamics*,
q = 2, ω = 2/3), and my own integrations in Python (SciPy DOP853 at RelTol 1e-10…1e-12, Radau at
1e-11 for Van der Pol, with my own right-hand sides, strobing, clustering, and Lyapunov exponent).
App values are the Summary (presets) and the engine's result, after the fixes unless marked.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Undamped Duffing, hardening α = 1, β = 1, from X = 1: period | 4.768022 (4 K(m)/√(α + βX²), m = βX²/(2(α + βX²)); quadrature and DOP853 agree to 1e-9) | 4.768022 (cycle period) | 6e-8 relative | ✓ |
| Hardening α = 1, β = 0.1, X = 1 | 6.060657 (same) | 6.060657 | 2e-8 | ✓ |
| Softening α = 1, β = −1, X = 0.5 | 6.978327 (same) | 6.978327 | 1e-8 | ✓ |
| Softening α = 1, β = −0.5, X = 1 | 8.008619 (same) | 8.008619 | 1e-8 | ✓ |
| Double well α = −1, β = 1, over the hump from X = 2; inside the well from X = 1.2 | 4.685680; 4.623905 (quadrature; DOP853) | 4.685667; 4.623905 | 3e-6; 1e-8 | ✓ (RK4 at the default step) |
| Weakly nonlinear β = 0.04, X = 0.5: frequency | 1.00375 (Lindstedt ω₀(1 + 3βX²/(8ω₀²))); exact 1.0037418 | 1.0037418 (2π / cycle period) | 8e-6 from Lindstedt, 0 from exact | ✓ |
| Undamped energy drift over 200 s (the cases above) | 0 | 1e-7 to 1.4e-5 relative | — | ✓ (RK4; the largest over the hump) |
| Dominant frequency (spectrum) of the same runs | 2π/T | within 0.1 % (e.g. 1.31795 vs 1.31778) | ≤ 1e-3 | ✓ (bin width 0.03 rad/s, parabolic peak) |
| Van der Pol μ = 0.1: amplitude, period | 2.000098, 6.287111 (Radau 1e-11); 2π(1 + μ²/16) = 6.28711 | 2.000017, 6.287106 | 8e-5, 5e-6 | ✓ |
| μ = 1 (preset): limit-cycle amplitude, period | 2.008620, 6.663287 (Radau; the literature's 2.00862, 6.66329) | 2.008623, 6.663287 | 3e-6, 1e-7 | ✓ |
| μ = 1: dominant frequency | 0.942956 (2π/T) | 0.943220 | 3e-4 relative | ✓ |
| μ = 2, 10, 20: period | 7.629874, 19.078370, 34.682323 | 7.629875, 19.078373, 34.682334 | < 4e-7 relative | ✓ |
| μ = 5 (preset): period, amplitude | 11.612231, 2.021508 (Radau) | 11.612231, 2.021508 | < 1e-6 | ✓ |
| μ = 50, default 60 samples: period, amplitude, maxima | 82.508334, 2.002956, one cycle; (3 − 2 ln 2)μ = 80.685, + 3·2.338 μ^(−1/3) = 82.589 | before: 82.4999, 2.0836, "2 different maxima"; after: 82.50842, 2.002957, one | after: 1e-6, 1e-6 | ✗ → fixed (finding 1); the asymptotic period within 0.1 % |
| μ = 50 at the minimum 8 samples per 2π: period | 82.508 | 82.880 | 0.45 % | accepted (finding 18) |
| Van der Pol entrainment (μ = 1, A = 1, ω = 1.1) | locked: one section point (−1.67162, 1.00772) (DOP853) | 1 distinct point, dominant 1.100015 | — | ✓ |
| Hardening resonance preset (δ = 0.1, α = 1, β = 0.1, A = 0.5, ω = 1.2): amplitude | 2.76875 (harmonic balance [(α − ω² + 3βa²/4)² + (δω)²] a² = A², one root at this ω); 2.78988 (DOP853) | 2.78988 | 0.8 % from harmonic balance, 3e-9 from DOP853 | ✓ (harmonic balance ignores the third harmonic) |
| Hardening: bistable band | 1.2165 < ω < 1.4005 (three roots of the cubic) | swept with continuation: jumps down between 1.40 and 1.45 going up, up between 1.25 and 1.20 coming down | — | ✓ (new test) |
| Hardening at ω = 1.3: upper and lower branch | 3.21526, 0.75772 (harmonic balance); 3.2485, 0.75790 (DOP853 with continuation) | 3.24848, 0.75790 | 1.0 %, 0.02 % | ✓ |
| Hardening preset: dominant frequency | ω = 1.2 | 1.200041 | 3e-5 | ✓ |
| Duffing double well (defaults): chaos | largest Lyapunov exponent 0.090 per time unit > 0 (DOP853, Benettin) | 151 distinct of 151 section points, "chaotic or quasi-periodic" | — | ✓ |
| Pendulum q = 2, ω = 2/3, A = 0.9 | period-1 (Baker & Gollub); section (−0.56023, 1.93359), Lyapunov −0.25 (DOP853) | 1 point at (−0.560228, 1.933586); dominant 0.666680 | 1e-6 | ✓ |
| A = 1.07 | period-2 (Baker & Gollub); (−0.3202, 1.9912), (−0.1467, 1.9246) (DOP853) | the same two points; ω/2 peak 0.053 beside ω's 1.77 | < 1e-4 | ✓ |
| A = 1.15, 1.5 | chaotic (Baker & Gollub); Lyapunov 0.109, 0.116 (DOP853) | 98 and 95 distinct of 101 | — | ✓ |
| A = 1.35, 1.45, 1.47 | period-1, 2, 4 (Baker & Gollub's windows; DOP853 agrees) | 1, 2, 4 | — | ✓ (new test) |
| First period doubling, period 4, chaos (continuation in A) | 1.0665, 1.0795, 1.0825 (DOP853 scan in steps of 0.001; literature ≈ 1.066, 1.079, 1.082) | — (a sweep starts each run from rest) | — | ✓ (lesson reworded, finding 16) |
| A = 1.08 from rest | period-3 (DOP853 from rest: 3 points over 100 and over 400 periods; it coexists with the period-4) | period-3 | — | ✓ |
| Pendulum spectrum peak (forced runs) | the drive, 2/3 rad/s; ω/3 at A = 1.08 | 0.66668 (period-1, 2), 0.66673 (chaos); 0.22232 at A = 1.08 | 2e-5 | ✓ |
| Period-1 at A = 0.9: steady amplitude | 2.4974 rad (θ stays within a turn) | 2.4974 | — | ✓ |
| A = 1.5 (rotating): steady amplitude | none (θ runs over 150 rad) | before: 55.71; 315 at A = 1.35–1.47; after: "— (turns over the top)" | — | ✗ → fixed (finding 5) |
| Free damped Duffing α = 1, β = 1, δ = 0.3 | settles to rest; damped period 2π/0.98869 = 6.35509 | before: "a periodic cycle", dominant frequency 0.989 from noise; after: "settles to rest", cycle period 6.35509 | 1e-9 | ✗ → fixed (finding 7) |
| Overdamped (δ = 5); double well from its bottom; constant force (ω = 0, A = 0.5) | at rest (x = 1.1915 for the constant force: x³ − x = 0.5) | before: "too short for a Poincaré section", "a periodic cycle"; after: "settles to rest", x = 1.1915 | — | ✗ → fixed (finding 7) |
| Softening runaway α = −1, β = −1 | unbounded | "The motion grew without bound at t = 4.398." | — | ✓ |
| Modes: double well at x = 1 | ωn = √(−2α) = 1.41421, ζ = δ/(2ωn) = 0.106066 | 1.41421, 0.106066 | < 1e-10 | ✓ |
| Modes: hardening at 0, δ = 0.3 | ωn = 1, ζ = 0.15, damped period 6.35509 | 1, 0.15, 6.35509 | < 1e-13 | ✓ |
| Modes: Van der Pol μ = 1; μ = 5 | μ/2 ± i√(1 − μ²/4) = 0.5 ± 0.866i; (μ ± √(μ² − 4))/2 = 4.7913, 0.2087 | 0.5 ± 0.866i (ζ = −0.5, Unstable); Growing 4.7913, 0.2087 | 0 | ✓ |
| Modes: pendulum q = 2 | ωn = 1, ζ = 1/(2q) = 0.25 | 1, 0.25 | 1e-13 | ✓ |
| Lesson: limit-cycle amplitude "about 2"; check 1.99–2.03 | 2.00862 | 2.00862 | — | ✓ |
| Lesson: period-1 at 0.9, period-2 at 1.07 with "a peak at ω/2", chaos at 1.5 going over the top | as above | as above | — | ✓ |
| Lesson: "Change the start by 0.001 rad and the motion soon differs completely" | Lyapunov 0.116: 10⁻³ grows to order 1 in about 60 s, 6 drive periods | — | — | ✓ |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.01–0.09 s headless; every
Summary number reaches the metrics; every exported column has its units (time s, x unitless or
θ rad, velocity 1/s or rad/s, the transient flag) and no NaN or Inf; a second solve gives the
identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs; undo and redo; a
scenario round trip keeps every input; CSV (4 columns), MAT, plot, and report exports (the report
has every Summary row and 8 images); a 10-frame GIF; a sweep over δ, a 2 × 2 map, a 6-sample
Monte Carlo study, and a short optimization of the distinct Poincaré points over δ; Modes shows
the well's Oscillation mode; theme and text-size switches keep the result. Before the fix of
finding 2 the MAT export warned "Cannot load an object of class 'listener'" when read back; after
it, no warnings. A run in the app takes 0.5–4 s, the slowest being the first (MATLAB's plotting
warm-up, K5).

### Tests

`tests/sims/nonlinear` (18: 11 engine, 7 in the app; 8 of them new or extended),
`PluginConformanceTest` for the plugin (14), `TestLessons` for "The route to chaos" (1),
`TestLessonChecks` (7), and `ArchitectureTest` (10): 50 passed, 0 failed, none excluded.
`codeIssues` on the engine, the plugin, and both test files: 0. No shared code changed. The
showcase image and thumbnails were made again (`dlab.dev.generateImages(Ids="nonlinear")`).

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (gaps closed: findings 12, 15)
- [x] Numbers: defaults, every preset, and edge cases (μ from 0.1 to 50, hardening and softening
  springs, the double well's hump, free damped and overdamped runs, a rotating pendulum, a
  constant force, a runaway softening spring) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (added, finding 13), visibility rules (δ, α, β only
  for Duffing, μ for Van der Pol, q for the pendulum; the duration in forcing periods when
  forced, in seconds when free); presets load what they say
- [x] Outputs: every tab readable in both themes and at Larger text (177 screenshots, before and
  after the fixes); the animation at 0, ½, and the end agrees with the plots (period-1 pendulum
  at θ = −0.560 rad at both strobe times, as in the section)
- [x] Summary and exports: Summary, plots, and CSV agree; units everywhere; the report is complete
- [x] Analysis: Sweep (and the bifurcation diagram), Map, Optimize, Uncertainty run cleanly; Modes
  against hand values (well √2 rad/s, ζ = 0.1061; Van der Pol μ = 1: 0.5 ± 0.866i, ζ = −0.5;
  μ = 5: 4.791 and 0.2087, both growing; pendulum ζ = 1/(2q) = 0.25)
- [x] Teaching: the lesson passes, and its statements and numbers agree with the reference values
  (the bifurcation step reworded, finding 16)
- [x] Behaviour: readable errors (unknown model, negative damping, too many samples, divergence);
  Cancel through the progress callback (covered by the suite); results survive theme and
  text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | A free oscillation's maxima were interpolated across a whole output sample. After a relaxation oscillation's fast jump that is far too coarse: μ = 50 at the default 60 samples gave a limit-cycle amplitude of 2.084 (true 2.0030) and "2 different maxima" for a single cycle; μ = 20 at 8 samples 1.956. | The interval holding a maximum is integrated again in fine RK4 substeps (at least 32, step · rate ≤ 0.05) before the Hermite and Newton search: 2.002957 and one cycle. | `testVanDerPolPeriodsSmallAndLargeMu` |
| 2 | Exports | The potential V(x) captured the whole input struct, progress callback included, so a saved MAT result carried the app's objects; reading it back warned "Cannot load an object of class 'listener'". | V captures only α and β; no warnings in the exports check since. | `testPotentialHoldsOnlyItsCoefficients` |
| 3 | Outputs | The Poincaré map of a periodic motion zoomed into its rounding noise: a period-1 point became a line of 101 dots on an axis 10⁻¹³ wide with overlapping 14-digit ticks (pendulum period-1, hardening resonance, entrainment, both Van der Pol presets); period-2's two points sat in the corners. | Axis limits at least a tenth of the motion's size on each axis, centred on the points. | `sectionAndPotentialStayReadable` |
| 4 | Outputs | The pendulum's Potential tab spanned the unwrapped angle (−60 … 100 rad at A = 1.5: 25 humps; 4 at A = 1.07), and its y-label said V(x). | One turn, θ wrapped to (−π, π] for the curve and the ball; y-label "V(θ) = 1 − cos θ". | `sectionAndPotentialStayReadable` |
| 5 | Summary | A pendulum that turns over the top showed a "Steady amplitude" of 55.7 rad (A = 1.5) or 315 rad (the running orbits at A = 1.35–1.47), with no unit. | No amplitude when θ covers more than a turn after the transient: "— (turns over the top)"; unit rad for the pendulum. (A = 1.07, which swings 0.035 rad past the inverted position and falls back, keeps its 2.68 rad: my first version of the fix hid it, caught in the re-captured Summary.) | `testPendulumPeriodDoubling`, `sectionAndPotentialStayReadable` |
| 6 | Summary | "Poincaré points" had "distinct; > 32: chaotic" in its Units column, and its value (1) disagreed with the map's title ("101 points"). | Renamed "Distinct Poincaré points", no units; the threshold is in the run note and the docs; the lesson's checks follow. | `TestNonlinearPlugin`, `TestLessons` |
| 7 | Behaviour | A free damped run that had settled was called "a periodic cycle" (δ = 0.3; also a constant force) or "too short for a Poincaré section" (overdamped, the double well from its bottom), and its "Dominant frequency" (0.0138 or 0.989 rad/s) was read from rounding noise. | Motion after the transient below 10⁻⁶ of the run's size: "settles to rest", dominant frequency "— (at rest)". | `testSettlesToRest`, `freeDampedMotionSettlesToRest` |
| 8 | Behaviour | A free pendulum turning over and over (no maxima of θ) was "too short for a Poincaré section". | "turns over the top (θ has no maxima)". | — (the flag is tested in `testPendulumPeriodDoubling`) |
| 9 | Outputs | The spectrum's "ω/3" and "ω/2" labels ran into each other ("ω/3ω/2") for the pendulum (ω = 2/3 on a 0–5 axis). | ω/3's label sits to the left of its line. | — (layout) |
| 10 | Outputs | The time-series and phase-portrait legends ("best" location) sat on the data (entrainment's time series, the chaotic phase portraits). | One row above the axes. | — (layout) |
| 11 | Exports | The pendulum's export called θ "x" with no unit and θ' "1/s". | "theta" in rad, velocity in rad/s for the pendulum. | `sectionAndPotentialStayReadable` |
| 12 | Physics (docs) | The docs called the equations dimensionless, while the inputs, axes, Summary, and export use s and rad/s; `about()` said nothing about units. | Docs and `about()`: time in seconds, Van der Pol's and the pendulum's natural frequency scaled to 1 rad/s, the Duffing's √α; x in any unit, θ in rad. | — |
| 13 | Inputs | δ, ω, x0, x0', and both durations had no tooltip; that ω = 0 with A ≠ 0 is a constant force was not said. | Tooltips added (A: a torque for the pendulum; ω = 0: a constant force; durations in forcing periods or seconds). | — |
| 14 | Behaviour | Unforced runs had no sample limit: 10⁵ s at 1000 samples per 2π is 1.6·10⁷ samples (about 400 MB) before any message. | The same 2·10⁶ limit as forced runs, with a readable error. | `testRejectsBadInput` |
| 15 | Docs | The hardening preset was "on the upper branch, just below the jump", but at ω = 1.2 harmonic balance has a single response; the bistable band is 1.2165–1.4005. | The docs describe it as near the top of a peak that leans to higher ω and give the band; a new test sweeps with continuation and checks both jumps and both branches. | `testHardeningHysteresisMatchesHarmonicBalance` |
| 16 | Teaching | The bifurcation step said "a split into two near A = 1.07, more splits", but every sweep run starts from rest and at A = 1.08 lands on a coexisting period-3 motion (found also by my own integration), not period-4. | The text gives the doubling, chaos within about 0.02, the windows near 1.35, 1.45, 1.47, and explains coexisting motions. | `TestLessons` |
| 17 | Docs | Modes: the docs listed Oscillation, Settling, Unstable (saddle), but Van der Pol with μ ≥ 2 shows two "Growing" modes. | The docs list Growing and say what Van der Pol's rest state shows. | — |
| 18 | Numbers | At μ = 50 with the minimum 8 samples per 2π, the period is 0.45 % long (82.88 vs 82.51): the RK4 step is chosen at the start of each output interval, too long for the fast jump. | Accepted: the default 60 samples gives 10⁻⁶, and 8 is the lower bound of a numerics input; re-evaluating the rate at every substep was tried and did not change the results at the default samples. | — |
| 19 | Outputs (shared) | At Larger text the playback time "26.2 / 26.2 min" is cut to "26.2 / 26.2 m…"; the double well's chaotic preset shows only 151 section points (a sparse attractor). | Accepted: the playback bar is shared code and still readable; more points need a longer run (Duration). | — |
