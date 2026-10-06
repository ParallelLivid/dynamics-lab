# Quadrotor — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/quadrotor/index.html` (145 pictures before the fixes; `after-*.png`
after them: the tilt recovery's position and attitude, the default's Modes, animation and rotor
thrusts at Larger text in the light theme, the motor failure in the light theme, the aggressive
gains at Larger text; run `dlab.dev.captureVerification("quadrotor")` to make them again)

## Model as implemented

**Airframe** (`airframe.m`, `mixer.m`): the X configuration, body x forward, y left, z up, rotors
at (±d, ±d), d = L/√2. Thrust Tᵢ = kf Ωᵢ² along body z, drag torque c Tᵢ (c = km/kf). I derived
the allocation from τ = Σ rᵢ × (0, 0, Tᵢ) = Σ (yᵢ Tᵢ, −xᵢ Tᵢ, 0) and the reaction to each motor's
drag torque (a clockwise rotor, 1 and 3, yaws the body anticlockwise, +c Tᵢ):
A = [1 1 1 1; d −d −d d; −d −d d d; c −c c −c], as coded. The mixer inverts A and, when a rotor
would leave 0…Tmax, gives up yaw first, then the collective, roll and pitch last, as the docs say.

**Dynamics** (`closedLoop.m`): 20 states. m v̇ = R ẑ ΣTᵢ − m g ẑ − kd |v − w| (v − w); I ω̇ = τ −
ω × Iω; q̇ = ½ q ⊗ [0; ω]; rotor speeds lag their commands, Ω̇ = (√(T_cmd/kf) − Ω)/τ; a failed rotor's
thrust and torque scale by the fraction it keeps. `ode45` (RelTol 10⁻⁸, MaxStep 0.01 s), stopped
at the ground ("crashed" above the crash speed).

**Controller:** position PID per unit mass (integrals inside the capture band and their limit),
F = m(a + g ẑ) with F_z ≥ 0.1 m g and at most the tilt limit, body z along F with the nose at the
setpoint yaw; attitude τ = ω × Iω + I(−Kr · 2 q_e,vec − Kw ω), so each axis is θ̈ + Kw θ̇ + Kr θ =
Kr θ_target behind the rotor lag. The *attitude* controller takes roll and pitch commands; *off*
holds every rotor at a fixed thrust.

**Linearization** (`hoverLinearization.m`): the closed loop at hover in reduced attitude
coordinates (no quaternion constraint).

**Against the docs page and `about()`:** they match; the docs did not say that the tilt limit
bounds the command only (finding 5).

## Reference values

Independent of the engine: my own quadrotor written from the docs page (scipy RK45 at RelTol
10⁻⁸, MaxStep 0.01 s, sampled every 0.02 s as here), with the airframe, rotor lag, drag, the
cascade, the anti-windup and the mixer's priorities written afresh and my own quaternion code;
its hover Jacobian by finite differences; hand calculations for hover.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Hover (1 kg, 6 N rotors) | m g / 4 = 2.4525 N per rotor; √(m g / (4 kf)) = 495.2 rad/s = 4729.07 rpm; thrust-to-weight 24/9.81 = 2.4465 | 2.4525; 4729.072; 2.446483 | 0 | ✓ |
| Hover, 1.5 kg (the lesson) | 3.67875 N; T/W 1.631 | 3.67875; 1.630989 | 0 | ✓ |
| Recover from a 20° tilt, 5 s | final error 0.04122 m; peak rotor 2.9082 N; height 3.0032 m | 0.04121782; 2.908238; 3.003178 | 0 | ✓ |
| Height step 3 → 6 m | settles (5 %) in 1.68 s, overshoot 2.487 %, peak 4.9432 N, never saturated | 1.68; 2.486763; 4.943245; 0 s | 0 | ✓ |
| Crosswind gust 7 m/s | tilt 6.5245°; peak 2.4782 N; final error 0.06142 m | 6.524538; 2.478173; 0.06142133 | 0 | ✓ |
| Rotor 1 stops at 2 s | yaw rate up to 370.76 °/s; tilt 123.85°; mixer saturated 1.5 s; crashes at 3.62 s at 12.06 m/s | 370.7634; 123.8519; 1.500069; 3.62 s, 12.05723 m/s | 0 | ✓ |
| … keeping half its thrust (the lesson) | flies on: 9.6494 m at 8 s, yaw rate 15.425 °/s, drifts 2.812 m | 9.649408; 15.42509; 2.812215 | 0 | ✓ |
| Aggressive gains (2 m step) | tilt 48.007° (the 30° limit bounds the command); overshoot 65.73 %; settles in 8.56 s | 48.00673; 65.72578; 8.56 | 0 | ✓ (finding 5) |
| Saturated climb 3 → 20 m, 3.5 N rotors | saturated 2.38 s; settles in 3.28 s; T/W 14/9.81 = 1.427; climb acceleration (4 Tmax − m g)/m = 4.19 m/s² | 2.38; 3.28; 1.427115 | 0 | ✓ |
| … with 6 N rotors (the lesson) | saturated 1.00 s; settles in 2.00 s; overshoot 3.648 % | 1; 2; 3.648186 | 0 | ✓ |
| Closed loop at hover (box mission's first waypoint) | eigenvalues −0.1400; −0.3623 (×2); −0.6383 (×2); −1.6386 ± 1.1378i; −2.0022 (×2); −2.8121 ± 1.7085i; −8.9063 (×2); −10.712 ± 15.312i (×2); −27.709; −29.916 | the same, to the digits shown | 0 | ✓ (finding 3: names) |
| Lesson numbers | 1.5 × 9.81/4 = 3.68 N, T/W 2.4 → 1.6; "more than 2 s at full thrust"; 4.2 m/s²; "about 2 s instead of 3.3 s"; "hundreds of degrees per second … crashes"; half thrust: "a slow turn … it drifts, but it flies" | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 1.2 s headless; every Summary number
reaches the metrics; every exported column has its units (the quaternion and the saturation flag
are dimensionless); no non-finite values; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (8 presets; slowest 12.4 s, the first run while
MATLAB warms up; median 4.9 s); undo and redo of the cruise speed; a scenario round trip; CSV
(30 columns), MAT, plot and report exports (8 images); a 10-frame GIF; a sweep of the cruise
speed; a map of cruise speed and tilt limit; uncertainty; a short optimization; Modes (15 modes)
and Bode; theme and text-size switches keep the result.

### Tests

`tests/sims/quadrotor` (new: `inputsFitAndExplainThemselves`, `presetsMatchAnIndependentClosedLoop`,
`roundOffIsDrawnFlat`), `PluginConformanceTest` for `QuadrotorPlugin`, `TestLessons` for its lesson,
and `ArchitectureTest`, run together with the 6DOF tests: 107 tests, 106 passed; the one failure
was the new `roundOffIsDrawnFlat` itself (it matched the Analyze tab's custom plot too), which
passes now that it looks only in the Position and Attitude tabs. None excluded. `codeIssues` on
every touched file: 0. The whole suite was run again at the end (`buildtool ptest`): 1407 tests,
0 failed, 0 errors.

## Checklist

- [x] Physics: the allocation matrix derived by hand, the dynamics, rotor lag, drag, the cascade
  and the mixer's priorities checked against the docs
- [x] Numbers: every preset and the lesson's cases against my own closed loop, to every digit
  shown; hover by hand; the hover eigenvalues against my own Jacobian
- [x] Inputs: labels, units, ranges, tooltips on every input (finding 2), choices that fit
  (finding 1), visibility by mission and controller
- [x] Outputs: every tab of every preset in both themes and at Larger text; the animation's rotor
  colours and readout agree with the Rotor thrusts tab; round-off drawn flat (finding 4)
- [x] Summary and exports: units in the units column; text rows as text
- [x] Analysis: Modes (named by axis, finding 3) and Bode (DC gain 1 from each setpoint, asserted
  by the tests); Sweep, Map, Optimize and Uncertainty run
- [x] Teaching: every lesson number checked
- [x] Behaviour: readable errors (bad gains, a start below ground, unknown rotor); a crash and a
  landing end the run with a note

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | Choices were cut off: "Setpoints (hover, steps)", "Cascaded position control", "Attitude commands + height hold", "Off: rotors at a fixed thrust", "2 (front-right)". | "Setpoints" / "Waypoints", "Position" / "Attitude" / "Off", rotors "1"–"4", explained in the tooltips (the rotor's place and spin). | `inputsFitAndExplainThemselves` |
| 2 | Inputs | 27 inputs had no tooltip (the setpoints, the start, several gains, the inertias, gravity, the failure time, the duration and step). | Tooltips. | `inputsFitAndExplainThemselves` |
| 3 | Analysis | Five modes were all "Integral (slow)", without saying which loop: the slowest modes are dominated by the integral states (∫e ≈ e/|λ| when |λ| < 1). | "Height integral (slow)" (−0.14) and "Horizontal integral (slow)" (−0.3623, −0.6383, twice each); the docs say so. | `presetsMatchAnIndependentClosedLoop` |
| 4 | Outputs | After the 20° roll the x and yaw plots stretched round-off (10⁻¹⁶) over their whole height, a wiggle with a tiny exponent label. | Position plots show at least 2 cm and angle plots at least 0.2°; real motions keep their own scale. | `roundOffIsDrawnFlat` |
| 5 | Docs | The docs did not say that the tilt limit bounds only the command: the aggressive-gains preset tilts to 48° with a 30° limit (its lightly damped attitude loop overshoots). | Said in the docs' controller description. | `presetsMatchAnIndependentClosedLoop` |

Accepted:
- **The box mission reports no settling time**: its setpoint reaches the last waypoint at 13.5 s
  (1.5 s up, four 2 s sides, a 1 s hold at each corner) and the quadrotor is still 4.5 cm off at
  20 s, outside the settling band (5 % of the last move, at least 2 cm); the Summary leaves the
  row out, as the docs say ("where they apply").
- **A run selects the Animation tab** when its events are processed; a script that selects another
  tab straight after `run()` must call `drawnow` first (users always do, between clicks; lessons
  select their tab after the run).
