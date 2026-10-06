# Inverted Pendulum on a Cart — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/cartpole/index.html` (146 pictures before the fixes; 74 more after
them, `after-*.png`, for the dark and light themes and Larger text, including the loop-gain and
disturbance-to-angle Bode plots; run `dlab.dev.captureVerification("cartpole")` to make them again)

## Model as implemented

**Plant** (`dynamics.m`): a cart (mass M, viscous friction b) on a horizontal track carrying a
pole on a free pivot. θ is measured from upright, positive leaning toward +x; x is the cart's
position. l is the pivot to the pole's centre of mass; I is the pole's inertia about its centre:
m (2l)²/12 for a uniform rod (2l long), 0 for a point mass on a massless rod. With
D = (M + m)(I + m l²) − m² l² cos² θ and F the total horizontal force on the cart:

    ẍ  = [(I + m l²)(F − b ẋ + m l θ'² sin θ) − m² l² g sin θ cos θ] / D
    θ'' = [(M + m) m g l sin θ − m l cos θ (F − b ẋ + m l θ'² sin θ)] / D

This is Lagrange's equations with T = ½(M + m)ẋ² + m l cos θ ẋ θ' + ½(I + m l²)θ'² and
V = m g l cos θ, solved for the accelerations (checked symbolically and at 400 random states).

**Control** (`simulateCartPole.m`): none (F = 0); PID on the angle with a cart PD loop,
F = Kp θ + Ki ∫θ dt + Kd θ' + Kx (x − x_ref) + Kv ẋ (θ in rad; ∫θ is a fifth state); or LQR,
F = −K (s − [x_ref 0 0 0]) with K from `dlab.physics.lqr` on the upright linearization, Q =
diag(qx, qẋ, qθ, qθ'), R = r. The motor's force is clipped to ±Fmax; the disturbance schedule is
added after the clip. x_ref is a schedule, kept on the track.

**Integration:** `ode45`, RelTol 10⁻⁸, AbsTol 10⁻¹⁰, MaxStep 0.01 s, with events at the end stops
(|x| = track/2) and at a fall (|θ| = 90°), which ends the run unless "Keep going after the pole
falls" is on (then the fall time is only recorded).

**Linear model** (`linearModel.m`): A, B of the plant at upright rest; Modes and Bode use the
closed loop with the chosen controller (with ∫θ when Ki ≠ 0), ignoring the force limit. The loop
gain is broken at the cart force: L(s) = K (sI − A)⁻¹ B for LQR, and the PID law's transfer function
times the plant's for PID.

**Against the docs page and `about()`:** the equations, signs, controllers and stops matched, but
neither said what l and I are, which matters for the rod (l is half its length; finding 14). The
docs page has been rewritten from the code: the model, the controllers, why Ki adds a neutral
mode, why LQR needs qx > 0, the outputs, the Bode tab and its negative gain margin, and the
lessons (finding 17).

## Reference values

Independent of the engine and its tests: my own equations of motion (mass-matrix form), Jacobian,
Riccati solution (the Hamiltonian's stable eigenvectors, base MATLAB), characteristic polynomials,
loop transfer functions written out from A, B and K, and a separate integration for the
energy and the weak-motor run. Defaults: M = 1 kg, m = 0.1 kg, l = 0.5 m, uniform rod,
b = 0.1 N·s/m, g = 9.81, 5° start, LQR with Q = diag(10, 1, 100, 1), r = 0.1, Fmax = 20 N.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Equations of motion, rod and point mass | Lagrange in mass-matrix form, 400 random states | `dynamics.m` | 8.5·10⁻¹⁶ relative | ✓ |
| Linearization A, B (rod / point) | my Jacobian | `linearModel.m` | 1.8·10⁻¹⁵ / 1.1·10⁻¹⁶ | ✓ |
| Topple rate, rod, b = 0 | √((M+m) m g l / ((M+m)(I+ml²) − m²l²)) = 3.973878 1/s | 3.973878 | 0 | ✓ |
| … with b = 0.1 | eig(A) = 3.970628 1/s | 3.970628 (Summary 3.97063) | 0 | ✓ |
| … point mass, b = 0 / 0.1 | 4.645643 / 4.641187 1/s | the same | 0 | ✓ |
| Other open-loop modes (rod, b = 0.1) | 0, −0.090906, −3.977283 | Modes: Cart drift 0, Settling −0.09091, −3.977 | 0 | ✓ |
| LQR gain, rod | K = [−10 −12.234618 −78.106704 −18.676700] (Hamiltonian) | the same | 9.7·10⁻¹⁶ relative | ✓ |
| … closed-loop poles | −1.3436216 ± 0.9895201i, −6.4029305 ± 3.2496520i | the same; ζ 0.8052, 0.8917 | 0 | ✓ |
| LQR gain, point mass | K = [−10 −11.724012 −72.156306 −14.737184] | the same | 2.5·10⁻¹⁵ | ✓ |
| LQR guarantee \|1 + L(jω)\| ≥ 1 | min over ω: 1.00000016 (rod), 1.00000025 (point) | — | — | ✓ |
| LQR loop gain, rod: phase margin | 65.196° at 15.1168 rad/s | 65.194° at 15.1168 | 0.002° | ✓ |
| … gain margin | phase rises through −180° at 3.2944 rad/s, \|L\| = 3.427: −10.70 dB (the gain may fall to 0.29; the poles of k K are stable for k > 0.29) | NaN ("unlimited") before; −10.699 dB at 3.2945 after | — | ✗ → ✓ (finding 1) |
| LQR loop gain, point mass | PM 66.006° at 17.406 rad/s; GM −10.860 dB at 3.5115 | 66.004°; −10.860 dB after | 0.002° | ✓ |
| PID [Kp Ki Kd Kx Kv] = [40 0 8 1 2] (PID + cart loop): poles | −0.33404 ± 0.54403i, −4.59279 ± 3.75917i (characteristic polynomial) | the same | 10⁻⁷ | ✓ |
| … loop gain | PM 58.066° at 9.5393; GM −9.048 dB at 1.5673 | 58.066°; −9.048 dB after (NaN before) | 0 | ✓ (finding 1) |
| PID [40 1 8 0 0] (balances, cart drifts) | poles 0, 0, −0.00065060, −5.90211 ± 2.81109i | 0, 3.2·10⁻¹⁵, … before; 0, 0, … after | rounding | ✗ → ✓ (finding 5) |
| PID [40 0 8 0 0] (PD on the angle only) | an unstable pole at +0.033279 1/s (the cart runs away) | +0.0333, but no warning before | — | ✗ → ✓ (finding 6) |
| No control, no friction, 30° start, 10 s | E conserved (E₀ = 0.42479 J); horizontal momentum 0; the pole swings past hanging | max \|ΔE\|/E₀ 3.2·10⁻⁹ (rod), 7.5·10⁻⁹ (point); \|p_x\| ≤ 2.4·10⁻⁹ | — | ✓ |
| Falls without control (5°, b = 0.1) | falls at 0.9238 s (my integration) | 0.92 s, run ends at 90° | 0 | ✓ |
| Weak motor: 2 N, 10° | end stop at 1.57413 s with θ = −43.832°, saturated 98.1 % (my integration) | 1.5741 s, −43.832°, 98.10 % | 10⁻⁵ s | ✓ |
| Least force that catches a 10° tilt | 2.8123 N (bisection) | lesson said "about 3 N", then "about 2.8 N" (2.8 N falls) | — | ✗ → ✓ (findings 15, 19) |
| 3 N / 4 N settling | 2.50 s / 1.25 s | the same | 0 | ✓ (lesson numbers) |
| LQR reference step of 1 m | backs away 6.95 cm first; overshoot 1.68 %; within 1° by 3.7 s | the same | — | ✓ |
| r = 10 | Max \|F\| 2.69 N (< 4, the lesson's check), settling 1.70 s | the same | — | ✓ |
| Optimize lesson: qx = 0.1, r = 2.5 | 0.47 s, 2.43 N, excursion 0.454 m, 0.167 m off at 8 s | "about 0.47 s, 2.4 N, 0.45 m, 0.16 m" | rounding | ✓ |
| qx = 0 | (A, Q) has the cart's position as an undetectable neutral mode: no stabilizing Riccati solution | an unreadable solver error before; input must be > 0 now | — | ✗ → ✓ (finding 2) |

## Automatic checks

From `captureVerification`: every preset solves in 0.03–0.29 s headless; every Summary number
reaches the metrics; every exported column has its units, with no non-finite values; a second
solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass after the fixes: every preset loads and runs (slowest 8.7 s for the first run
while MATLAB warms up, median 2.4 s); undo and redo; a scenario round trip; CSV (9 columns, all
with units), MAT, plot, and report exports (8 images); a 10-frame GIF; a sweep over M, an M × m
map, a 6-sample Monte Carlo study, a short optimization of the settling time; Modes (two
oscillations) and Bode; theme and text-size switches keep the result.

### Tests

`tests/sims/cartpole` (23: 14 engine, 9 in the app; new: `testEquationsMatchLagrange`,
`testUnstablePoleAndLqrAgainstHandValues`, `testPidPolesMatchTheCharacteristicPolynomial`,
`testEnergyAndMomentumWithoutControl`, `testWeakMotorSaturates`, `testRejectsZeroPositionWeight`,
`summaryNeverShowsNaN`, `neutralPoleReadsZero`, `unstableLoopIsFlagged`,
`inputsFitAndExplainThemselves`), `PluginConformanceTest` for the plugin (14), `TestLessons` for
both cart-pole lessons (2), `TestLessonChecks` (7), `TestFrequencyResponse` (11; the cart-pole LQR
test now checks the phase and gain margins against the hand values), `ArchitectureTest` (10), and,
because the shared `FrequencyResponse` and `FrequencyPanel` changed, the other simulators with a
loop gain: `tests/sims/dcmotor` (26) and `tests/sims/flight6dof` (45). All passed, none excluded.
`codeIssues` on every touched file: 0. The showcase window changed, so
`dlab.dev.generateImages(Ids="cartpole")` made its thumbnails and docs image again.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (now both say what l and I are)
- [x] Numbers: defaults, every preset, and edge cases (no control, no friction, qx = 0, a weak
  motor, the least force that works, a point mass) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (on every input now), visibility rules (PID or LQR
  gains; the force limit and the target only with a controller); presets load what their names say
- [x] Outputs: every tab readable in both themes and at Larger text; the animation's cart, pole,
  force arrow and readout agree with the plots at the same time
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere; no NaN shown; the
  report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes and Bode (closed loops and
  the loop gain) against hand values
- [x] Teaching: every lesson statement and number checked (findings 15, 16, 19)
- [x] Behaviour: readable errors (qx = 0); Cancel; run times under 0.3 s; nothing left behind on
  preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Analysis (shared) | The loop gain around the unstable plant starts near −270° and its phase **rises** through −180° below the crossover; only falling crossings were looked for, so the gain margin read "unlimited" (LQR: really −10.70 dB at 3.294 rad/s, the amount the gain may fall). | `FrequencyResponse` finds crossings either way and takes the one nearest 0 dB; the Bode note says "the gain may fall by 10.7 dB, not rise". The DC motor and 6DOF tests pass unchanged. | `TestFrequencyResponse` (cart-pole LQR: PM 65.196°, GM −10.699 dB at 3.2944 rad/s) |
| 2 | Inputs | qx = 0 was accepted, and the solve failed with the Riccati solver's message. | qx must be positive (the tooltip says why); the engine's own error explains it. | `testRejectsZeroPositionWeight` |
| 3 | Summary | A run that fell or hit an end stop showed "Settling time NaN". | "— (the pole fell)" / "— (the cart hit the end stop)". | `summaryNeverShowsNaN` |
| 4 | Summary | Without a controller the Summary showed a "Slowest closed-loop pole" (the open loop's) and a "Final x error" against a target that does not exist. | Both rows only with a controller. | `summaryNeverShowsNaN` |
| 5 | Summary, Gains | PID on the angle: the slowest closed-loop pole read 3.16·10⁻¹⁵ (rounding around a pole at 0), in the Summary and the poles list. | Read as 0 in both. | `neutralPoleReadsZero` |
| 6 | Behaviour | An unstable linear closed loop (PD on the angle alone: +0.0333 1/s) gave no warning. | The status line warns, with the pole. | `unstableLoopIsFlagged` |
| 7 | Outputs | With no controller the Angle and position tab drew a "Target" line. | Only with a controller. | screenshots |
| 8 | Outputs | The track-end lines lay on the frame of the cart-position plot. | Padded limits: they sit inside. | screenshots |
| 9 | Outputs | After a fall the force plot kept an empty strip to the full duration; with no controller it showed a flat "Applied" line with no explanation. | Tight time limits; the title says "(no controller)". | screenshots |
| 10 | Outputs | The phase portrait's start marker was cut in half by the frame. | Padded limits. | screenshots |
| 11 | Outputs | The Gains and poles text ran past its box at Larger text, and for PID did not give the law. | Shorter lines; the PID law written out. | screenshots |
| 12 | Inputs | Choice labels were too long for their fields ("Uniform rod (l…", "PID on the an…"). | "Uniform rod" / "Point mass", "None" / "PID" / "LQR"; the tooltips explain. | `inputsFitAndExplainThemselves` |
| 13 | Inputs | Most inputs had no tooltip; the pivot input did not say l is half a rod's length; the force limit showed without a controller. | Tooltips on every input; "Pivot to pole centre of mass"; Fmax only with a controller. | `inputsFitAndExplainThemselves` |
| 14 | Physics | `about()` did not define l or I. | Added. | — |
| 15 | Teaching | The balancing lesson said the 2 N motor "cannot catch the pole" (it catches it, overshoots, and hits the end stop) and that "about 3 N is enough"; the Modes step called the −4.0 mode "the pole falling the other way back up". | Rewritten from the runs: the end stop, the least force, 3 N → 2.5 s and 4 N → 1.25 s; the four modes named correctly. | `TestLessons` |
| 16 | Teaching | The optimize lesson's "0.15 m before" did not say before what. | "0.15 m with r ≈ 0.29 alone, 0.13 m at the defaults". | `TestLessons` |
| 17 | Docs | The docs page did not cover l and I, the neutral mode from Ki, qx > 0, the Bode tab, the Summary's dashes, or the export. | Rewritten from the code. | — |
| 18 | Outputs | With no controller the force plot still shaded the "Motor limit ±Fmax" band (the input is hidden then). | The band only with a controller. | `inputsFitAndExplainThemselves` |
| 19 | Teaching | The lesson and docs then said "about 2.8 N is the least that works"; 2.8 N lets the pole fall (the least is 2.81 N). | "2.81 N is the least (2.8 N is just too little)"; the test checks 2.8 N falls. | `testWeakMotorSaturates` |

Accepted: the settling time is quantized to the output step (0.01 s), so it is flat in steps
of 0.01 s for an optimizer; the lessons' searches still reach the stated optima (`TestLessons`).
