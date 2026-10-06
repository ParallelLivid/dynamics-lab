# Rigid-Body Rotation — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/rigidbody/index.html` (160 pictures before the fixes and 159 after;
run `dlab.dev.captureVerification("rigidbody")` to make them again)

## Model as implemented

**Equations** (`simulateRigidBody.m`), SI units, body axes = principal axes:

    I ω' = (I ω) × ω + τ                Euler's equations, I = diag(I₁, I₂, I₃)
    q'   = ½ q ⊗ [0; ω] + (1 − ‖q‖²) q   attitude quaternion, scalar first, body → world

- **Free body:** τ = 0; I about the centre of mass, each inertia at most the sum of the other two
  (checked). The start quaternion turns the body so that L = R I ω points along world +z (for
  L = 0, the identity).
- **Heavy symmetric top:** pivot at the origin, z up, centre of mass at l along body z;
  I = diag(I_t, I_t, I_s) about the pivot; τ = [0 0 l] × (Rᵀ [0 0 −m g]) in body axes. The start
  is R = R_x(θ₀) (Z-X-Z Euler angles with φ = ψ = 0) and ω = (θ', φ' sin θ₀, ω₃): the body rates of
  Z-X-Z angles at ψ = 0, with ω₃ the spin input (constant, since I₁ = I₂ and τ₃ = 0). Energy
  ½ Σ I_i ω_i² + m g l cos θ; L is about the pivot, in world axes.
- **Euler angles** from R: θ = acos R₃₃, φ = atan2(R₁₃, −R₂₃), ψ = atan2(R₃₁, R₃₂) (checked
  against R = R_z(φ) R_x(θ) R_z(ψ) by hand), φ and ψ unwrapped. Precession rate: least-squares
  slope of φ(t) over the run; nutation amplitude: half the range of θ.
- **Integration:** `ode113`, RelTol 1e-11, AbsTol 1e-13 · max(|ω₀|, 10⁻⁶), sampled at the output
  step; the quaternion is normalized afterwards and its norm error before that reported.
- **Flips** (since finding 2): turnovers of the intermediate axis (by inertia) relative to L, from
  a component along L̂ above ½ to below −½ or back; the time is where it crossed zero (linear
  interpolation). No intermediate axis when two inertias are equal.
- **Modes:** the Jacobian of ω ↦ (Iω × ω)/I at steady spin about the spin axis (the chosen one, or
  since finding 8 the body axis nearest L), at the start's rate about it.

**Against the docs page and `about()`:** the equations, frames, signs and the top's start match.
Differences, now closed: the docs said flips were "the sign changes of body axis 2's component
along L" (they used ±½ thresholds, and axis 2 need not be the intermediate one: findings 2, 17);
the docs did not say that I_t is about the pivot through the parallel-axis theorem or that only
m g l matters (finding 16).

## Reference values

Independent of the engine and its tests: closed forms, Landau & Lifshitz (*Mechanics*, §37) for
the free body's elliptic-function solution, Goldstein (*Classical Mechanics*, §5.7) for the heavy
top, and my own integrations in Python: the free body by SciPy DOP853 (RelTol 1e-12) on Euler's
equations with a **rotation matrix** R' = R [ω]ₓ (no quaternion), the top in **Euler angles**
(Lagrange's equation for θ with the conserved p_φ = I_t φ' sin²θ + I_s ω₃ cos θ and p_ψ = I_s ω₃),
which shares nothing with the engine. App values are the Summary, Modes, and the engine's result.
Old defaults I = 1, 2, 3 unless said; after finding 1 the defaults are I = 1, 2, 2.5.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Tennis racket, I = 1, 2, 3, ω = (0.001, 10, 0.001): ω(t) | ω(2) = (−8.2587465806, −5.638537569, 4.7681896314), ω(10) = (−0.058973739, −9.9998261534, 0.0340582926) (my integration) | (−8.258746581, −5.638537569, 4.768189631), (−0.05897373979, −9.999826153, 0.03405829309) | 4e-7 over the run (near the separatrix every 1e-12 grows by e^{5.8 t}) | ✓ |
| … time between flips | 2K(k)/rate = 3.550725 s, k² = 1 − 2·10⁻⁸ (Landau & Lifshitz; 1 − k² computed as (I₃ − I₁)(L² − 2EI₂)/((I₃ − I₂)(L² − 2EI₁)) to avoid cancellation); my zero crossings 1.889415, 5.440140, 8.990865 s | 3.55073 s; crossings 1.889414, 5.440140, 8.990866 | 7e-7 s | ✓ |
| … conservation | E, L constant; L = (0, 0, 20.00000025) | energy 1.5e-11, \|L\| 7.6e-12 relative; L_x, L_y within 1e-9 of 0 | — | ✓ |
| … attitude | R orthonormal, det R = 1, ‖q‖ = 1 | ‖q‖ − 1 before normalizing ≤ 7e-12; det R − 1 ≤ 2e-15; ‖RᵀR − I‖ ≤ 2e-15; axis z-components agree with my rotation matrix to 4e-8 | — | ✓ |
| Modes at the intermediate axis | λ = ±ω √((I₂ − I₁)(I₃ − I₂)/(I₁ I₃)) = ±5.773503 (I = 1, 2, 3), ±4.472136 s⁻¹ (1, 2, 2.5) | ±5.7735, ±4.4721; the −λ was "Tumble (unstable)" with "Stable" beside it, now "Tumble (decaying)"; ωn showed "5.7740" | 1e-9 | ✓ (findings 7, 18) |
| Modes at the major / minor axis (presets) | wobble ω √((I₃ − I₁)(I₃ − I₂)/(I₁ I₂)) = 10, ω √((I₂ − I₁)(I₃ − I₁)/(I₂ I₃)) = 5.773503 rad/s (I = 1, 2, 3); 6.123724, 5.477226 (1, 2, 2.5) | 10, 5.7735; 6.1237, 5.4772 | 1e-9 | ✓ |
| … the nonlinear wobble period | polhode period 4K(k)/rate = 0.628319 s (major), 1.088334 s (minor) | my integration's ω₁/ω₃ zero crossings give the same to 1e-12; the app's ω curves agree with mine to 4e-13 (major), 1.3e-11 (minor) | — | ✓ |
| Polhode | the intersection of Σ I_i ω_i² = 2E and Σ I_i² ω_i² = L² (in L space: the sphere \|L\| = L and the ellipsoid Σ L_i²/I_i = 2E) | the curve lies on both drawn ellipsoids; E and \|L\| drift ≤ 1.5e-11 | — | ✓ |
| Symmetric body I = 2, 2, 3, ω = (0.5, 0, 4): body cone | ω₁ + iω₂ turns at (I₃ − I₁) ω₃ / I₁ = 2 rad/s; ω₃ = 4 constant | 2.0000000 (fit); Modes wobble 2 rad/s; ω₃ = 4 to 1e-9 | 1e-9 | ✓ |
| … space cone | axis 3 turns about L at \|L\|/I₁ = 12.041595/2 = 6.020797 rad/s, at a fixed 4.7636° from L (cos = I₃ω₃/\|L\|) | 6.0207972894; 4.7636° | 1e-11 | ✓ |
| Default top (200 rad/s, 30°, m g l = 0.1962 J) | steady precession roots of I_t cos θ Ω² − I_s ω₃ Ω + m g l = 0: 5.578843 (slow), 40.609178 (fast); gyroscopic 4.905; started at rest: mean precession 5.4815 (10 s), nutation amplitude 5.0961°, largest tilt 40.192° | (steady row new, finding 6) 5.57884; started at the fast root: precession 40.609, nutation 4.7e-9° | 1e-8 | ✓ |
| Fast top (400 rad/s) | mean precession 2.51998, nutation amplitude 0.953868°, largest tilt 31.9077°; steady slow root 2.52132; gyroscopic 2.4525 | 2.51998, 0.953868°, 31.9077°; 2.52132 (new row); θ(t) and φ(t) agree with mine to 2.5e-12 and 7.9e-12 rad | 1e-6 | ✓ |
| … nutation frequency | fast-top estimate I_s ω₃/I_t = 80 rad/s (period 0.0785 s); my integration 75.70 rad/s (0.083002 s); at 200, 400, 800 rad/s mine is 22 %, 5.4 %, 1.3 % below the estimate (an error falling as 1/ω₃²) | θ maxima 0.08305 s apart (output step 0.005 s); 0.08300 at 0.0005 s | 6e-5 s | ✓ |
| Looping nutation (80 rad/s, φ'₀ = −3) | mean precession 8.42257, amplitude 43.4225°, largest tilt 116.845°; no steady precession at 30° (ω₃ < 2√(I_t m g l cos θ)/I_s = 130.3 rad/s); gyroscopic 12.26 (meaningless here) | 8.42257, 43.4225°, 116.845°; θ, φ agree with mine to 2e-9 rad; steady: "none: too slow at this tilt" | 1e-7 | ✓ (finding 6) |
| Sleeping top (300 rad/s, 2°) | upright stability limit 2√(I_t m g l)/I_s = 140.07 rad/s; mean precession 3.47117, amplitude 0.130782°, largest tilt 2.26156° | 3.47117, 0.130782°, 2.26156° | < 1e-6 | ✓ |
| … below the limit (100 rad/s) | falls to 88.92° | 88.923° | — | ✓ |
| Top hanging (tilt 179°) | steady slow root (cos θ < 0) 2 m g l/(I_s ω₃ + √D) = 4.4175 | mean precession 4.4177 | 5e-5 | ✓ |
| Conservation, every top preset | E, L_z, L₃ = I_s ω₃ constant | ≤ 1.2e-14, 5.1e-11, 2.4e-15 relative (L₃ exactly 0 where τ₃ = 0 and I₁ = I₂ make ω₃' = 0) | — | ✓ |
| I = 2, 1, 2.5, ω = (10, 0.001, 0.001) (axis 1 intermediate) | tumbles: my integration's ω₁ crosses zero at 2.15633, 7.11461 s | before: "Flips 0"; after: 2 flips at 2.15633, 7.11461 | 1e-6 | ✗ → fixed (finding 2) |
| I = 2, 2, 3 spun about axis 1 | λ = 0 (triple): neutral, ω drifts round the 1–2 plane | before "Spin axis stable 1"; after "neutral (equal inertias)", no flips | — | ✗ → fixed (finding 3) |
| Top with no spin | gyroscopic estimate undefined | before "Inf"; after "— (no spin)" | — | ✗ → fixed (finding 5) |
| Lesson: growth rate | 10 √(1 · 0.5/2.5) = 4.472 s⁻¹ (was 5.774 at I = 1, 2, 3) | text "4.5 per second" | — | ✓ |
| Lesson: flips | every 4.958 s (2K/rate at I = 1, 2, 2.5) | text "every 5 s"; 4 flips in the 20 s preset | — | ✓ |
| Lesson: fast top | m g l/(I_s ω₃) = 0.1962/0.08 = 2.4525 rad/s | text 2.45; app mean 2.520, steady 2.521 (text now says so) | — | ✓ |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.02–0.5 s headless (the
fast top is the slowest); every Summary number reaches the metrics (the text rows, "yes"/"no",
"neutral", "none: too slow at this tilt", "— (no spin)", are left out on purpose); every exported
column has its units entry (time s, ω rad/s, L kg·m²/s, energy J; the quaternion is
dimensionless) and no NaN or Inf; a second solve gives the identical result. The longest allowed
run (10⁴ s at 0.01 s, 10⁶ samples) solves in 26 s with an energy drift of 9·10⁻¹⁰; 1000 rad/s
keeps L fixed to 10⁻⁹ relative.

### In the app (`dlab.dev.checkBehaviour`)

Before the fixes the Sweep (1 of 3 runs), Map (2 of 4) and Uncertainty steps failed: they vary
I₁ by ±10 % or ±2 %, and below I₁ = 1 the old default body was impossible (finding 1). After the
fixes all eleven pass: every preset loads and runs; undo and redo; a scenario round trip keeps
every input; CSV (12 columns), MAT, plot, and report exports (the report has every Summary row
and 8 images); a 10-frame GIF; a sweep over I₁ (0.9–1.1), an I₁ × I₂ map, a 6-sample Monte
Carlo study, and a short optimization; Modes shows the Spin (neutral), Tumble (unstable) and
Tumble (decaying); theme and text-size switches keep the result. A run in the app takes 2–9 s,
the slowest the first (MATLAB's plotting warm-up, K5).

### Tests

`tests/sims/rigidbody` (22: 12 engine, 10 in the app; 13 of them new), `PluginConformanceTest`
for the plugin (14), `TestLessons` for "The tennis racket theorem" (1), `TestLessonChecks` (7),
and `ArchitectureTest` (10): 54 passed, 0 failed, none excluded. `codeIssues` on the engine, the
plugin, both test files, and `ModesPanel.m`: 0. Shared code changed: `+dlab/+core/ModesPanel.m`
(findings 18, 19), so the tests of every simulator with Modes were run as well (pendulum,
mass-spring, nonlinear, attractors, cart-pole, DC motor, quarter-car, handling, three-body,
attitude, 6DOF, quadrotor) with `TestShell`: 183 + 116 passed, 0 failed, none excluded. The
showcase changed (the new body, mid-flip at 2.8 s), so `dlab.dev.generateImages(Ids="rigidbody")`
made its thumbnails and docs image again.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (the Euler-angle extraction and the top's initial body rates checked by hand; docs closed:
  findings 16, 17)
- [x] Numbers: defaults, every preset, and edge cases (permuted and equal inertias, a sphere, no
  spin, 1000 rad/s, a 10⁴ s run, a top upright, hanging at 179°, with no spin, below the sleeping
  limit, at both steady-precession roots, with I_t < m l²) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (added, finding 15), visibility rules (free: I₁–I₃,
  ω₁–ω₃, spin axis; top: m, l, I_s, I_t, g, spin, tilt, rates); presets load what they say
- [x] Outputs: every tab readable in both themes and at Larger text (before and after the fixes);
  the animation's axis trail and the Axis trace show the same path, and its |ω| readout matches
  the Angular velocity plot (10 rad/s throughout the torque-free racket)
- [x] Summary and exports: Summary, plots, and CSV agree; units hold units only (finding 4); the
  report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly on the inertias (they failed before,
  finding 1); Modes against the hand values above
- [x] Teaching: the lesson passes, and its statements and numbers agree with the reference values
  (numbers updated with the new body, finding 1)
- [x] Behaviour: readable errors (impossible inertias, I_s > 2 I_t, unknown model, bad duration);
  Cancel through the progress callback (covered by the suite); results survive theme and text-size
  switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | The default body I = 1, 2, 3 sat exactly on the triangle inequality (I₃ = I₁ + I₂: a plate of zero thickness). The animation was a flat one-coloured sheet, and any sweep, map, or uncertainty study that lowered I₁ or I₂ or raised I₃ failed ("No real body has these inertias"; `checkBehaviour`: Sweep, Map, Uncertainty failed). | Defaults I = 1, 2, 2.5 (a 1 : 0.65 : 0.38 box); the tennis racket preset runs 20 s (flips 4.958 s apart, 4 of them); lesson, docs, and tests follow. | `defaultBodyIsARealBox`, `tennisRacketFlips` |
| 2 | Numbers | Flips were counted for body axis 2 only. With the intermediate inertia on another axis (I = 2, 1, 2.5 spun about axis 1) the body tumbled but the Summary said "Flips 0". | The intermediate axis by inertia; none when two inertias are equal. | `testIntermediateAxisNeedNotBeAxis2`, `summaryRowsSayWhatTheyMean` |
| 3 | Physics | "Spin axis stable" was 1 whenever the axis had the largest or smallest inertia, also when another inertia equals it (a symmetric body spun about a transverse axis, a sphere): such a spin is only neutral (λ = 0), and drifts. | "neutral (equal inertias)". | `summaryRowsSayWhatTheyMean` |
| 4 | Summary | "Spin axis stable" showed 0/1 with "yes = 1" in the Units column. | "yes"/"no"/"neutral" text; the metric keeps 1/0 for the lesson and sweeps. | `summaryRowsSayWhatTheyMean` |
| 5 | Summary | A top with no spin showed "Gyroscopic estimate … Inf" and drew a line at infinity. | "— (no spin)", no line. | `summaryRowsSayWhatTheyMean` |
| 6 | Numbers | The only reference for the top's precession was the fast-top estimate m g l/(I_s ω₃): 12 % below the true mean at the default 200 rad/s, and meaningless for the looping preset, which spins too slowly (80 < 130 rad/s) to precess steadily at all at 30°. | New Summary row and plot line: the steady rate, the slow root of I_t cos θ Ω² − I_s ω₃ Ω + m g l = 0 (or "none: too slow at this tilt"); docs give the sleeping and steady limits. | `steadyPrecessionIsTheSlowRoot`, `testFastSteadyPrecessionHasNoNutation` |
| 7 | Analysis | Modes at the intermediate axis listed both real eigenvalues as "Tumble (unstable)", the negative one with "Stable" beside it. | The negative one is "Tumble (decaying)", the saddle's other direction. | `intermediateAxisTumbles` |
| 8 | Inputs | The automatic spin axis was the largest ω component, not the axis the motion is about: ω = (0, 5, 4.5) with I = 1, 2, 2.5 has L = (0, 10, 11.25), a wobble about axis 3, but was analysed as spin about axis 2. | Auto is the body axis nearest L (largest \|I_k ω_k\|); label "Spin axis" with a tooltip (it also picks the traced axis). | `autoSpinAxisIsTheOneNearestL` |
| 9 | Outputs | The looping-nutation top dips to 117°, but the animation drew it on a floor at its tip's height: the cone went through the floor. | A top whose rim would dip below its tip stands on a post, the floor lower down (as the pendulum's ceiling). | `floorOnlyWhenTheTopStaysAboveIt` |
| 10 | Outputs | The top's axle (an unused vertex in the rim patch) was never drawn, so the axis trail floated above the cone. | The axle is drawn and turns with the top. | — (layout) |
| 11 | Outputs | In the light theme the L and ω arrows were magenta and purple, hard to tell apart. | L in the text colour. | — (colour) |
| 12 | Outputs | The polhode axes had no units. | ω₁, ω₂, ω₃ (rad/s). | — (layout) |
| 13 | Outputs | The precession plot's legend ("best") sat on the φ' curve. | One row above the axes. | — (layout) |
| 14 | Inputs | At Larger text the choices were cut off ("Free bod…", "The large…"). | "Free body"/"Spinning top", "Auto"/"Axis 1–3". | — (layout) |
| 15 | Inputs | Only three inputs had tooltips; nothing said that I_t is about the pivot (centre-of-mass inertia + m l²), that ω₃ is the constant spin component, or what the tilt is measured from. | Tooltips on every input but gravity, duration, and step. | — |
| 16 | Physics | Nothing checked the top's inertias: I_s > 2 I_t is no body. Nor is I_t < m l², but the motion depends on m, g, l only through m g l, so such inputs still describe a real top (with a smaller m l² at the same m g l). | I_s > 2 I_t is rejected with a readable message; the other accepted, and the tooltip and docs say only m g l matters. | `testRejectsBadInput` |
| 17 | Docs | The docs described flips as "the sign changes of body axis 2's component along L" and gave I = 1, 2, 3 references; the lesson's 5.8 s⁻¹, "every 3.6 s". | Docs page rewritten from the code (flips, steady precession, limits, references from my integrations); lesson numbers updated. | `TestLessons` |
| 18 | Analysis (all simulators) | The Modes table rounded to four significant digits and `uitable` then printed four decimals: ωn "5.7740" for 5.7735. | Shared `ModesPanel`: `shortG` columns show "5.774". | `TestShell` (and every Modes test, see Tests) |
| 19 | Outputs (all simulators) | At Larger text the Modes table kept its 23 px rows and hid its third row behind a scroll bar. | Shared `ModesPanel`: the table's height grows with the text size. | — (layout) |
| 20 | Numbers | A large wobble about the major axis (ω = (0, 5, 4) with I = 1, 2, 3: the intermediate axis swings to 50° from L and back past −L) counts 14 "flips". | Accepted: by the definition (within 60° of L, then of −L) the intermediate axis does turn over; the docs and the code say what a flip is. | — |
| 21 | Outputs | The cone is rotationally symmetric, so the top's spin itself cannot be seen in the animation (only precession and nutation). | Accepted: at 200–400 rad/s a mark on the rim would alias at any frame rate. | — |
