# Mass-Spring — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/massspring/index.html` (104 pictures; run
`dlab.dev.captureVerification("massspring")` to make them again)

## Model as implemented

**Single mass** (`MassSpringPhysics.m`, `solve_single`): x is the displacement from equilibrium
(the unstretched spring), positive to the right.

    m x'' + c x' + k x = F(t),   F(t) = F₀ cos(ωf t + φ)   or a force profile (step, pulse, …)

- SI units throughout (kg, N/m, N·s/m, m, s, N). The damper is viscous (force −c v).
- KE = ½ m v², PE = ½ k x², E = KE + PE; spring force −k x; a = (F − c v − k x)/m.
- ωn = √(k/m), ζ = c / (2√(mk)), ωd = ωn √(1 − ζ²) (0 when ζ ≥ 1). The type is "Undamped"
  (ζ = 0), "Under-damped", "Critically damped" (|ζ − 1| ≤ 10⁻¹⁰), or "Over-damped".
- The Frequency response tab plots the classic steady state for r = ω/ωn from 0 to 4:
  X / X_st = 1 / √((1 − r²)² + (2ζr)²), X_st = F₀/k, and the lag atan2(2ζr, 1 − r²).

**Coupled masses** (`solve_coupled`): springs k₁ (left wall–m₁), k₂ (m₁–m₂), k₃ (m₂–right
wall); dampers c₁ and c₂ from each mass to its own wall; the force F(t) = F₀ cos(ωf t) (or a
profile) acts on m₁.

    m₁ x₁'' = F(t) − c₁ x₁' − k₁ x₁ − k₂ (x₁ − x₂)
    m₂ x₂'' =      − c₂ x₂' − k₃ x₂ + k₂ (x₁ − x₂)

- The Summary's mode frequencies are √eig(K, M), K = [k₁+k₂, −k₂; −k₂, k₂+k₃], M = diag(m₁, m₂)
  (undamped).
- **Collisions.** Physical centres q₁ = −s/2 + x₁, q₂ = s/2 + x₂ (s, the equilibrium separation).
  Gaps: x₁ + w ≥ 0 (left wall), w − x₂ ≥ 0 (right wall), s + x₂ − x₁ − g ≥ 0 (masses), with w
  the wall clearance and g the contact gap (centre distance at contact; the blocks are drawn g
  wide). Terminal events stop `ode45` at each contact; the impulse problem is solved as a small
  linear complementarity problem over all touching contacts: Newton restitution on the closing
  normal speeds (after = −e × before), impulses ≥ 0, no contact left closing. Momentum is kept.
  Hence a wall impact keeps e² of the mass's kinetic energy and a mass–mass impact loses
  ½ μ (1 − e²) v_rel², μ = m₁m₂/(m₁+m₂). After an impact the contact set is separated by 10⁻⁸ m
  (0 when e = 0). Resting contact (gap and normal speed within 10⁻⁹) is held by unilateral
  reactions while the forces push inward, again by enumerating the active sets.
- **Solver.** `ode45`, RelTol = AbsTol = 10⁻⁹, sampled at the output step and ending exactly at
  the duration. With a force profile or collisions the step is limited to the output step (a
  short pulse or a contact cannot fall between steps). Stiff runs (a real decay rate over
  10⁴ / duration) use `ode15s` (finding 11).
- **Linearization** (Modes, Bode): the same equations with the force as the input, about
  x = 0 (contacts ignored). Bode output names carry units (N in, m and m/s out).

**Against the docs page and `about()`:** the equations, signs, units and contact rules match.
The docs page did not list the full Summary, the Bode tab, the solver, or the impact energy
rules; it does now (finding 14).

## Reference values

Independent of the engine and its tests: closed forms worked out separately (a Python script
for the closed forms; least-squares fits of the app's own time histories for the steady state),
compared with the app's numbers (Summary, metrics, Frequency response tab, Modes, Bode). m = 1,
k = 10, c = 0.5 unless stated.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Defaults: ωn | 3.16228 rad/s (√(k/m)) | 3.16228 | 0 | ✓ |
| Defaults: ζ | 0.0790569 (c / 2√(mk)) | 0.0790569 | 0 | ✓ |
| Defaults: ωd | 3.15238 rad/s (ωn√(1 − ζ²)) | 3.15238 | 0 | ✓ |
| Defaults: damped period | 1.993156 s (2π/ωd) | 1.993156 s (mean up-crossing interval of x(t)) | 6e-9 | ✓ |
| Defaults: logarithmic decrement | 0.498289 (2πζ/√(1 − ζ²)) | 0.498289 (successive maxima) | 1e-7 | ✓ |
| Defaults: x(t) over 20 s | e^(−ζωn t)(cos ωd t + (ζωn/ωd) sin ωd t) | — | max 8e-10 m | ✓ |
| Defaults: final energy E(20) | 2.34660e-4 J (closed form) | 2.34660e-4 J | 6e-11 | ✓ |
| Defaults: energy dissipated | 4.999765 J (∫ c v² dt from the app's v) | E₀ − E(20) = 4.999765 J | 9e-9 | ✓ |
| Forced near resonance (x₀ = 0.5, F₀ = 2 N, ωf = 3): x, v at 7.99 s | −0.6253114 m, 2.4226746 m/s (particular + homogeneous closed form) | −0.6253114, 2.4226746 | 1e-10, 4e-9 | ✓ |
| Forced near resonance: magnification | 5.547002 (r = 0.94868) | 5.547002 | 0 | ✓ |
| Forced near resonance: peak \|x\|, E(8) | 1.013950 m, 4.879829 J | 1.013950, 4.879829 | 7e-10, 6e-9 | ✓ |
| Steady state X/X_st, r = 0, 0.5, 0.9, 1, 1.5, 2, 3 | 1, 1.325987, 4.212627, 6.324555, 0.785977, 0.331497, 0.124781 (magnification factor) | identical to 6 digits (tail fit of x after 100 s; Summary; tab curve) | < 1e-6 | ✓ |
| Steady-state lag, same r | 0, 6.0173°, 36.8318°, 90°, 169.2566°, 173.9827°, 176.6068° (atan2(2ζr, 1 − r²)) | identical to 4 decimals | < 1e-4° | ✓ |
| Forced, r = 1: energy budget | E(T) − E₀ = ∫F v − ∫c v² = 7.999992 J | 8.000000 J | 8e-6 (trapezoid rule) | ✓ |
| Undamped resonance (c = 0, ωf = ωn, from rest): x(20) | 2.542472 m (F₀ t sin(ωt)/(2mω)) | 2.542472 m | 3e-9 | ✓ (Summary showed "Inf": finding 2) |
| Critically damped: ζ, x(1 s) | 1, 0.1761860 m ((x₀ + ωn x₀ t) e^(−ωn t)) | 1, 0.1761860 | 7e-12 | ✓ |
| Heavily damped, c = 10⁵: x(20) | 0.998002 m (over-damped closed form) | 0.998002 m | < 1e-7 | ✓ (solve 0.06 s, was 23 s: finding 11) |
| Beating: modes | √10 = 3.16228, √11 = 3.31662 rad/s | 3.16228, 3.31662 | 0 | ✓ |
| Beating: x₁(t), peak x₂, energy | ½(cos ω₁t + cos ω₂t); 0.999328 m; E = 5.25 J constant | max error 1e-8 m; 0.999328; drift 1e-7 J | — | ✓ (energy fully transferred after π/(ω₂ − ω₁) = 20.35 s) |
| Coupled defaults (m₂ = 1.5, k = 8, 4, 6): modes | 2.262071, 3.680992 rad/s (det(K − ω²M) = 0) | 2.262071, 3.680992 | 2e-11 | ✓ |
| Coupled defaults: Modes tab | eigenvalues −0.10920 ± 2.25963i, −0.14080 ± 3.67797i (own 4×4 A) | same; in phase, out of phase | — | ✓ (Modes' ωn is \|λ\| = 2.2623, 3.6807, damped) |
| Coupled defaults: energy dissipated | 5.973506 J (∫ (c₁v₁² + c₂v₂²) dt) | 5.973506 J | 2e-8 | ✓ |
| Free impact (e = 0.75): impact time | 0.916667 s ((1.5 − 0.4)/1.2 m/s) | 0.916667 s | 0 | ✓ |
| Free impact: velocities after | −0.46, 0.44 m/s (momentum + restitution) | −0.46, 0.44 | 4e-16 | ✓ |
| Free impact: energy lost | 0.189 J (½ μ (1 − e²) v_rel², μ = 0.6 kg) | 0.189 J | 3e-16 | ✓ |
| Free impact: final energy, peaks | 0.251 J; 0.7333, 0.55 m; one impact (next wall contact after 5.4 s) | 0.251; 0.7333, 0.55; 1 | 8e-9 | ✓ |
| Wall impact, e = 0.6, 0.5 m at 1 m/s | t = 0.5 s; KE after/before = e² = 0.36 | 0.5 s; 0.36 | 1e-16 | ✓ |
| Springs + dampers + impacts (e = 0.7, 4 impacts, wall and pair) | per impact: the formulas above; E₀ − E(T) = damping work 32.242 J + impacts 34.738 J = 66.980 J | each within 6e-7 J; 66.980 J | 4e-6 | ✓ |
| e = 1, undamped, 67 impacts: energy | constant | drift 2.3e-5 J of 67 J | 3.5e-7 relative | ✓ (separation nudge, event tolerance) |
| e = 0 (Free impact): after the impact | common velocity 0.08 m/s; masses stay together | 0.08; gap error 2e-14 m | — | ✓ |
| Bode, Force → x at ω = 0.1, 1, 3, √10, 5, 30 | 1 / (k − mω² + icω) | magnitude and phase | 4e-16 relative, 7e-14° | ✓ |
| Bode, Force → v | iω / (k − mω² + icω) | | 3e-16 | ✓ |
| Bode: DC gain, resonance | 0.1 m/N (1/k); peak 0.634441 at 3.14245 rad/s (1/(2kζ√(1 − ζ²)) at ωn√(1 − 2ζ²)) | 0.1; 0.634344 at 3.13806 | 0.015 %, 0.14 % | ✓ (the 600-point grid: finding 15) |
| Bode, coupled: Force on m₁ → x₁, x₂ | (k₂ + k₃ − m₂ω² + ic₂ω)/D and k₂/D (Cramer's rule) | | 1e-15 | ✓ |
| Bode, coupled: DC gains | 0.0961538, 0.0384615 m/N | same | 0 | ✓ |
| Lesson "Resonance", step 1 | 5.547 (in 5–6, "about 5.5") | 5.547 | — | ✓ |
| Lesson "Resonance", step 2 (ωf = 3.16) | 6.3289 (> 6.2; 1/(2ζ) = 6.3246, "≈ 6.3") | 6.3289 | — | ✓ |
| Lesson "Resonance", step 3 | magnification < 2 needs ζ > 0.25, c > 1.581; solution c = 2 gives 1.581 | 1.581 | — | ✓ |
| Lesson "A pendulum is a spring", step 2 | k = m g / L = 19.62 N/m, ωn = 3.1321 rad/s, period 2.006 s | 3.1321 | — | ✓ |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.07–0.27 s headless
(Defaults was 1.23 s before finding 11); every Summary number reaches the metrics; every exported
column has its units (8 columns single, 14 coupled, whose last is the text "event") and no NaN or
Inf; a second solve gives the identical
result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs; undo and redo; a
scenario round trip keeps every input; CSV (units on all 8 columns), MAT, plot, and report exports
(the report has every Summary row and 9 images); a 10-frame GIF; a 3-run sweep, a 2 × 2 map, a
6-sample Monte Carlo study, and a short optimization (ωn over m), all without errors; Modes shows
the Oscillation mode; Bode shows Force → x; theme and text-size switches keep the result. A run
in the app takes 2–9 s on this machine; profiling shows the solve is now 0.1–0.4 s of it, the rest
being the shared view (rebuilding the output tabs when the mode changes, the playback starting,
redrawing); the pendulum shows the same on the same machine (noted under K5).

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
- [x] Numbers: defaults, every preset, and edge cases (c = 0 at resonance, ζ = 1, ζ ≫ 1, k = 0,
  e = 0, e = 1, simultaneous and resting contacts) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (added where missing), visibility rules (forcing and
  collision details appear only when ticked; single and coupled inputs never together); presets
  load what they say (Critically damped gives ζ = 1 exactly; Beating has c = 0 and weak k₂; Free
  impact has no springs or dampers)
- [x] Outputs: every tab readable in both themes and at Larger text (104 screenshots, before and
  after the fixes); the animation's x, v, and F labels agree with the Kinematics plots at the
  same time
- [x] Summary and exports: Summary, plots, and CSV agree; units everywhere; the report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes and Bode against hand values
- [x] Teaching: both lessons that use Mass-Spring pass, and their statements and numbers agree
  with the reference values
- [x] Behaviour: readable errors (overlapping start, contact gap ≥ separation); Cancel is covered
  by the suite (TestShell); results survive theme and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | The damping type ("Under-damped") sat in the Units column of "Damping ratio ζ", so the metrics, sweep and map axes, and the report gave the ratio that "unit". | Its own text row, "Damping"; ζ has no units. | `summaryDescribesDamping` |
| 2 | Summary | Undamped forcing at ωn showed "Magnification at ωf  Inf", and called ζ = 0 "Under-damped"; the tab's forcing marker (at infinity) was not drawn. | "∞ (undamped resonance: the swing grows without limit)"; type "Undamped"; the marker sits at the top edge. | `undampedResonanceShowsInfinityNotInf`, `undampedIsNamedUndamped` |
| 3 | Summary | Critically and over-damped runs showed "Damped frequency ωd  0 (0 Hz)". | "0 (no oscillation)" (the metric stays 0). | `summaryDescribesDamping` |
| 4 | Outputs | The animation's floor line ran through the dampers, which hung below it, and the mass floated above the floor. | The spring and the damper both run from the wall to the mass's side, the damper below the spring; the mass rides on the floor. | `animationDrawsOnlyTheElementsPresent` |
| 5 | Outputs | Springs and dampers were drawn when their stiffness or damping is 0: Free impact showed the free masses joined by springs, Beating showed dampers it does not have. | Only the elements present are drawn. | `animationDrawsOnlyTheElementsPresent`, `geometryListsTheSpringsAndDampersPresent` |
| 6 | Outputs | A forced mass showed no force; the velocity label ("v = 0.52") and the coupled position labels had no units; the coupled mass labels did not follow the text size. | A force arrow labelled "F = … N"; units on every label; `t.scaled`. | `animationShowsTheForce` |
| 7 | Outputs | Phase portraits used tight limits: Free impact's v₁ = 0.8 m/s path lay on the top border (invisible) and start markers were clipped. | Padded limits. | `phasePortraitsShowTheirEdges` |
| 8 | Outputs | The Energy legend ("best") covered the energy peaks in Beating. | Head room above the curves (kept runs included) and a one-line legend at the top. | `energyLegendLeavesTheCurvesClear` |
| 9 | Analysis | Bode's input and output lists had no units. | "Force (N)", "x (m)", "v (m/s)" (coupled likewise). | `bodeTabShowsTheForcedResponse`, `bodeMatchesTheReceptance` |
| 10 | Outputs | The Frequency response tab's "Phase angle" ran 0 to +180° while Bode shows 0 to −180° for the same response. | Titled "Phase lag of x behind the force", axis "Phase lag (deg)". | — (wording) |
| 11 | Behaviour | Every run stepped no further than the output step (20 000 steps for the defaults, 1.2 s), and heavy damping was stiff for `ode45` (c = 10⁵: 23 s; 10⁶: minutes). | The step limit only with a force profile or collisions; `ode15s` when a real decay rate exceeds 10⁴/duration. Defaults 0.27 s, c = 10⁵ 0.06 s; golden values unchanged within 1e-8. | `heavyDampingSolvesQuicklyAndAccurately`, `freeResponseMatchesDampedOscillator`, `forcedSingleMatchesExampleCsv` |
| 12 | Behaviour | A contact gap at least the equilibrium separation gave "coll_eq_sep must be greater than coll_gap." in the status bar. | "The equilibrium separation must be greater than the mass–mass contact gap." | `geometryErrorIsReadable` |
| 13 | Inputs | Wall clearance (whose meaning is not obvious), c, x₀, k₁–k₃, c₁–c₂, x₁ and the output step had no tooltips. | Tooltips added (what each spring and damper connects; clearance = free travel toward the wall). | — (wording) |
| 14 | Docs | The docs page listed only part of the Summary, and nothing about Bode, the solver, or the energy an impact loses. | Rewritten Outputs section, a Solver paragraph, impact energy rules, and more reference rows (all asserted by tests). | the new physics tests |
| 15 | Analysis | Bode reads its resonance from a 600-point grid: 0.6343 at 3.138 rad/s against the exact 0.63444 at 3.1425 rad/s. | Accepted: 0.015 % and 0.14 %, the grid's resolution (shared code). | — |
| 16 | Analysis | Modes gives the coupled natural frequencies as \|λ\| of the damped system (3.6807 rad/s), the Summary the undamped ones (3.6810 rad/s). | Accepted: both are right for what they are; the docs page now says so. | — |
| 17 | Behaviour | A run in the app takes 2–9 s, mostly in the shared view (tabs rebuilt on a mode change, playback start, redraws). | Accepted here: shared code, the same for the pendulum on this machine (K5). | — |
