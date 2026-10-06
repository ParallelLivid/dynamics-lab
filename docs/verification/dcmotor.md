# DC Motor Servo — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/dcmotor/index.html` (145 pictures before the fixes; 56 more after them,
for the light theme, the Position P preset and Larger text, including the loop-gain and
voltage-to-angle Bode plots; run `dlab.dev.captureVerification("dcmotor")` to make them again)

## Model as implemented

**Motor** (`dynamics.m`, `simulateDcMotor.m`): a permanent-magnet DC motor, SI units inside the
engine (the plugin converts L from mH and the references from rpm and degrees, and back for
display). θ and ω are positive counter-clockwise; the load torque τ opposes positive rotation.

    L di/dt = V − R i − K ω          (armature)
    J dω/dt = K i − b ω − τ_load      (rotor; J includes the load)
    dθ/dt   = ω

- K is both the back-EMF constant (V·s/rad) and the torque constant (N·m/A), equal in SI units.
- L = 0 removes the current from the state: i = (V − K ω)/R. The speed's voltage step is then
  first order with τ = J R/(K² + b R) and gain K/(K² + b R); with L > 0 the motor has the two
  poles of (J s + b)(L s + R) + K² = 0.

**Controller** (`rhsAll`): V_cmd from the mode, then V = clip(V_cmd, ±Vmax).

| Mode | V_cmd | Integral z |
|---|---|---|
| Open loop | the voltage schedule | not used |
| Speed | Kp e + Ki z, e = ω_ref − ω | z' = e |
| Position | Kp e + Ki z − Kd ω, e = θ_ref − θ | z' = e |

The derivative acts on the measured speed (no kick at a reference step). Clamping anti-windup
sets z' = 0 while |V_cmd| > Vmax and e·V_cmd > 0 (Ki ≥ 0, so Ki e then pushes further into
saturation). The motor always starts at rest (i = ω = θ = z = 0).

**Integration:** classical fourth-order Runge–Kutta with a fixed step h that divides every output
interval and is at most 0.2/|λ|max over the motor's own poles (the saturated loop) and the linear
closed loop; the command and the load are evaluated at the stage times. More than 5·10⁶ steps is
refused ("set the inductance to 0"). Since this round the energy ∫ V i dt is a fifth state
integrated with the motion, and more than 2·10⁶ output samples is refused.

**Linear model** (`linearModel.m`): A, B of the motor with x = [i ω θ] (or [ω θ]); the closed loop
Acl with z appended when Ki ≠ 0 (and θ dropped under speed control); τ_mech, τ_elec = L/R, the
steady speed per volt. The voltage limit is ignored.

**Step metrics** (`stepResponse.m`): for a step command, over [t_step, end of run or a later load
change], as MATLAB's `stepinfo` measures them: from y(t_step) to the last sample (not the
theoretical final value); rise 10–90 %, time to 63.2 %, overshoot past the last sample, 2 %
settling, interpolated between samples.

**Modes and Bode** (plugin): the motor alone at rest, inputs [V; τ], outputs [ω; θ]. Under a
controller the loop is broken at the motor voltage: inject u, and what returns is the
controller's output with the reference at zero, −Kp y − Kd ω + Ki z. The loop gain is therefore
L(s) = (Kp + Kd s + Ki/s) θ(s)/V(s) under position control (derivative on the measurement gives
the same loop as on the error; only the reference path differs) and (Kp + Ki/s) ω(s)/V(s) under
speed control, with θ/V = K/(s[(J s + b)(L s + R) + K²]) and ω/V = s θ/V.

**Against the docs page and `about()`:** the equations, signs, controller and anti-windup match.
The docs page did not describe the loop gain and its margins, the second lesson, the export, or
how the step metrics are measured; it does now (finding 16).

## Reference values

Independent of the engine and its tests: closed forms, and step responses and a nonlinear
simulation of my own in Python (scipy `signal.step` of the transfer functions on a 1 µs grid;
`solve_ivp` RK45 at rtol 10⁻¹¹ with the saturation and the clamping written out separately),
compared with the app's Summary, Modes and Bode numbers. Default motor: R = 2 Ω, L = 5 mH,
K = 0.1 V·s/rad, J = 10⁻³ kg·m², b = 10⁻⁴ N·m·s/rad.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| τ_mech | 0.196078 s (J R/(K² + b R)) | 0.196078 s | 0 | ✓ |
| Steady speed per volt | 9.80392 rad/s/V = 93.62 rpm/V (K/(K² + b R)) | Bode DC 9.80392; Poles 93.62 rpm/V | 0 | ✓ |
| Motor poles, L = 5 mH | −394.9346, −5.165412 (roots of (Js+b)(Ls+R)+K²) | Modes −394.9, −5.165 (τ 0.1936 s) | 1e-12 | ✓ |
| Open loop, 12 V step: speed at 1.2 s | 1120.451 rpm (two-pole step response) | 1120.452 rpm | 1e-6 relative | ✓ |
| … rise 10–90 % / time to 63 % / 2 % settling (to the last sample) | 0.420839 / 0.195260 / 0.736127 s | 0.420842 / 0.195177 / 0.736053 s | ≤ 0.08 ms | ✓ (1 ms samples) |
| … time to 63 % of the true final speed | 0.19615 s | — | — | the Summary measures to the last sample, as `stepinfo` (docs say so) |
| Bode V → ω bandwidth | 5.1523 rad/s (−3.000 dB; half power, −3.010 dB: 5.1645) | 5.1525 rad/s | 4e-5 relative | ✓ (MATLAB's `bandwidth` convention) |
| Bode τ → ω DC gain | −196.078 rad/s per N·m (−R/(K² + b R)) | −196.078 | 0 | ✓ |
| Bode V → θ | DC gain ∞, phase from −90° to −270° | ∞, −90.6° to −269.4° | — | ✓ |
| Position P (Kp = 5): closed-loop poles | −395.582, −2.25896 ± 15.7381i (s D(s) + K Kp) | the same | 1e-7 | ✓ |
| … damping of the pair | ζ = 0.142078 | 0.142078 | 0 | ✓ |
| … overshoot (full third order) | 64.909 % (formula from the pair: 63.70 %) | 64.911 % | 0.002 | ✓ |
| … rise / settling / peak time | 0.071633 s / 1.85038 s / 0.2022 s | 0.071635 / 1.85036 / 0.202 s | < 0.1 ms | ✓ |
| … error at 2 s (still ringing) | 0.686° (my simulation) | 0.687° | 1e-3° | ✓ (finding 3) |
| Position P, L = 0 | ω_n = 15.8114 rad/s, ζ = 0.161276, overshoot 59.85 %, t_p = π/ω_d = 0.20133 s | tests: within 0.2 %, one sample | — | ✓ |
| Position PD (defaults): poles | −362.934, −18.5832 ± 14.3433i (ζ = 0.79162) | the same, ζ 0.791624 | 1e-7 | ✓ |
| … overshoot / rise / settling | 1.70348 % / 0.103967 s / 0.160109 s | 1.70347 % / 0.103972 / 0.160025 s | ≤ 0.08 ms | ✓ |
| … peak voltage at the step | 15.708 V (Kp × 90° in rad) | 15.708 V | 0 | ✓ |
| Lesson: PD with Kp = 5, Kd = 0.4 | ζ = 0.799 (0.794 at L = 0), overshoot 1.54 % | passes (< 5 %) | — | ✓ |
| Speed PI (preset): poles | −379.321, −10.3894 ± 7.0879i (ζ = 0.82607) | the same | 1e-7 | ✓ |
| … overshoot / settling / error at 1 s | 7.6931 % / 0.39697 s / 0.01877 rpm | 7.6930 % / 0.39689 s / 0.01873 rpm | sampling | ✓ |
| Speed P only (Ki = 0): steady error | 152.239 rpm (r/(1 + G Kp)) | 152.239 rpm | 1e-6 | ✓ |
| PD holding 0° under a 0.1 N·m load | 11.4592° (τ R/(K Kp)), i = τ/K = 1 A | 11.4592°, 1.000 A | 1e-6 | ✓ |
| … with Ki = 50 (preset) | error 8.82·10⁻⁵° at 1.5 s, peak 9.60° (my simulation) | 8.81·10⁻⁵° | — | ✓ |
| Windup, 360° at 12 V, no anti-windup | overshoot 48.6145 %, 0.143 s saturated (my nonlinear simulation) | 48.6147 %, 0.143 s | 2e-4 | ✓ |
| … clamping | 13.4514 %, 0.098 s | 13.4633 % (13.4514 % at a 10 µs output step) | 0.012 points | ✓ (finding 18) |
| Energy, defaults | supply = ½ J ω² + ½ L i² + ∫ (R i² + b ω²) dt = 1.82369 J (at 10 µs) | 1.82178 J before, 1.82369 J after | −0.1 % before | ✗ → ✓ (finding 6) |
| Loop gain, position P | PM 16.193° at 15.4924 rad/s; GM 18.236 dB at √((K² + b R)/(J L)) = 45.1664 rad/s | 16.194° at 15.4926; 18.235 dB at 45.1664 | 0.001° | ✓ |
| Loop gain, position PD (defaults) | PM 67.447° at 33.432 rad/s; phase → −180° asymptotically, GM unlimited | 67.447° at 33.434; "unlimited" | 0.002 rad/s | ✓ |
| Loop gain, speed PI (preset) | PM 73.920° at 16.871 rad/s, GM unlimited | 73.92° at 16.8715 | 0 | ✓ |
| Loop gain, PID (Ki = 50, presets) | PM 64.795° at 31.608 rad/s | 64.793° | 0.002° | ✓ |
| Loop gain, PID with Ki = 60 | PM 64.12° at 31.205 rad/s (phase starts at −180.09°) | 424.12° before, 64.12° after | 360° | ✗ → ✓ (finding 1) |
| Lesson numbers | 1123 rpm at 12 V, pole −5.17, electrical −395, 11.5°, 9.8 rad/s/V, J doubled: τ 0.392 s, bandwidth 2.56 rad/s | as stated ("about 1120", "about 2.6") | — | ✓ (after findings 12–15) |

## Automatic checks

From `captureVerification` (before the fixes): every preset solves in 0.02–0.14 s headless; every
Summary number reaches the metrics; every exported column has its units; a second solve gives the
identical result. One failure: the open-loop export had 2402 NaN values (the reference and error
columns, finding 5); after the fix the open-loop table has 11 columns, all finite.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs (slowest 6.1 s in the app
for the first run while MATLAB warms up, median 2.7 s); undo and redo; a scenario round trip;
CSV (13 columns, all with units), MAT, plot, and report exports (8 images); a 10-frame GIF; a
sweep over R, an R × L map, a 6-sample Monte Carlo study, a short optimization of the rise time;
Modes (Shaft angle, Mechanical, Electrical) and Bode; theme and text-size switches keep the result.

### Tests

`tests/sims/dcmotor` (26: 14 engine, 12 in the app; new or extended: `testEnergyBalance`,
`testRejectsBadInput`, `exportsWithUnits`, `summaryNeverShowsNaN`, `dampingIsTheLeastDampedPole`,
`unstableLoopIsFlagged`, `inputsFitAndExplainThemselves`), `PluginConformanceTest` for the plugin
(14), `TestLessons` for both DC motor lessons (2), `TestLessonChecks` (7), `TestFrequencyResponse`
(11, new `loopPhaseStartsOnItsIntegratorsBranch`; the cart-pole LQR test now also checks that its
margin is below 180°), `ArchitectureTest` (10), and, because the shared `FrequencyResponse`
changed, the other simulators with a loop gain: `tests/sims/cartpole` (13) and
`tests/sims/flight6dof` (45). 128 passed, 0 failed, none excluded. `codeIssues` on the engine, the
plugin, `FrequencyResponse.m` and the three test files: 0. The showcase window changed (the
Control and Anti-windup labels), so `dlab.dev.generateImages(Ids="dcmotor")` made its thumbnails
and docs image again.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (the derivative on the measurement, the clamping condition and the loop broken at the voltage
  checked by hand)
- [x] Numbers: defaults, every preset, and edge cases (L = 0, no gain, an unstable PID, 10⁹
  samples, a stiff Kd) against the reference values
- [x] Inputs: labels, units (gains act on rad and rad/s, references in ° and rpm), ranges,
  tooltips (added for R, J, b, Control, Anti-windup, both references, duration, output step),
  visibility rules (speed or position gains, anti-windup only in closed loop); presets load what
  their names say
- [x] Outputs: every tab readable in both themes and at Larger text (before and after the fixes);
  the animation's pointer, reference marker, bars and readout agree with the plots at the same
  time; the load arrow turns against positive rotation and the shaft gives way the same way
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere; no NaN shown; the
  report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes and Bode (motor alone and
  loop gain, with margins) against hand values
- [x] Teaching: both lessons' checks pass, and their statements and numbers agree with the
  reference values (findings 12–15)
- [x] Behaviour: readable errors (too many samples, too stiff, bad inputs); Cancel (covered by
  `testCancelStopsEarly`); results survive theme and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Analysis (shared) | The loop gain's phase margin came out 360° too large when the loop's phase starts just below −180°: position PID with Ki ≥ 52 V/(rad·s) on the default motor gave 424.7° (true 64.7°), because `unwrap(angle(·))` started on the +180° branch. The cart-pole's LQR and PID + cart loops (phase from +89.5°) reported 425.2° and 418.1° (true 65.2° and 58.1°); its test "PM ≥ 60°" passed for the wrong reason. | `FrequencyResponse`: a loop gain's phase starts on the branch between −315° and 45° (0, −90, −180 or −270° for zero to three integrators). Only loop gains change; cart-pole and 6DOF tests rerun. | `loopPhaseStartsOnItsIntegratorsBranch`, `cartPoleLqrKeepsItsGuaranteedMargins` |
| 2 | Summary | With no motion (Kp = Kd = 0, or a speed loop with no gains) the four step rows showed "NaN". | "— (no change after the step)", left out of the metrics. | `summaryNeverShowsNaN` |
| 3 | Summary | "Steady-state error" was the error at the end of the run: the P preset, still ringing at 2 s, showed 0.69° for a type-1 loop whose steady-state error is zero (the Bode lesson says so). | Renamed "Final error"; the docs say it is the steady-state error only once settled; the lesson check uses the new name. | `positionPDSettlesQuickly`, `TestLessons` |
| 4 | Summary | "Dominant damping ratio" was the slowest pole's: the PID presets showed ζ = 1 (a real pole at −10.41) next to 13–49 % overshoot, with a pair at −13.39 ± 9.24i (ζ = 0.823) nearly as slow. | "Lowest damping ratio": the least damped closed-loop pole (a free integrator at 0 left out); negative when unstable. Same in the Poles text. | `dampingIsTheLeastDampedPole` |
| 5 | Exports | The open-loop CSV carried reference and error columns that were all NaN (2402 values). | Left out in open loop. | `exportsWithUnits` |
| 6 | Numbers | The energy used was a trapezoid sum over the 1 ms samples: 0.1 % low at the defaults (1.8218 instead of 1.8237 J), where the current rises in 2.5 ms. | ∫ V i dt is a fifth state integrated with the motion; the same at any output step. | `testEnergyBalance` |
| 7 | Behaviour | Duration and output step are limited separately (1000 s, 1 µs), so a run could ask for 10⁹ samples and run out of memory. | Refused above 2 million samples, with a readable message; the tooltip says so. | `testRejectsBadInput` |
| 8 | Behaviour | An unstable linear closed loop (say Ki = 5000) gave no warning: only "Lowest damping ratio −0.37" and a positive slowest pole. | The status line warns "the linear closed loop is unstable (a pole at +21.6 1/s)". | `unstableLoopIsFlagged` |
| 9 | Inputs | The Control and Anti-windup choices were cut off at both text sizes ("Position contr…", "Clamping (ho…"). | Labels "Open loop", "Speed", "Position", "None", "Clamping"; the explanations moved to the tooltips. | `inputsFitAndExplainThemselves` |
| 10 | Inputs | R, J, b, Control, Anti-windup, the speed and angle references, the duration and the output step had no tooltip (that the gains act on rad and rad/s while the references are in rpm and ° was said nowhere). | Tooltips added. | `inputsFitAndExplainThemselves` |
| 11 | Outputs | At Larger text the Poles tab's text wrapped in mid-unit ("V·s/rad", "0.1961 / s"), and it named the mode by its internal id ("Control: position"). | Shorter lines, one gain per line; "Control: position (P, PD, PID)". | — (layout; screenshots) |
| 12 | Teaching | Bode lesson: "the gain falls 20 dB per decade with up to 90° of lag. That is a first-order system" while the plot's phase goes on to −180° (the electrical pole near 395 rad/s); and "the bandwidth, 5.15 rad/s, is 1/τ = 5.10 rad/s". | Says the bandwidth is close to 1/τ, and that past the electrical pole the inductance adds another 20 dB per decade and 90°. | `TestLessons` |
| 13 | Teaching | Bode lesson: "above the bandwidth it falls 40 dB per decade" for voltage → angle, which has no bandwidth (the tab shows none). | "above 1/τ (about 5 rad/s)". | `TestLessons` |
| 14 | Teaching | Servo lesson: "the command saturates for about a tenth of a second"; the Summary shows 0.143 s. | "about 0.14 s". | `TestLessons` |
| 15 | Teaching, docs | "About 64 % overshoot from ζ ≈ 0.14": the run overshoots 64.9 %; the formula from the pair gives 63.7 %. | "About 65 %", with the formula's 64 % and the electrical pole's part; docs page too. | `positionPOvershootFollowsTheDampingRatio` |
| 16 | Docs | The docs page did not mention the loop gain and its margins, the second lesson, the export, the sample limit, or that the step metrics are measured to the last sample. | Added (Bode, Summary, Export, Integration, Lessons sections; two loop-margin rows in the reference table). | — |
| 17 | Analysis | The bandwidth is read at exactly −3 dB (5.152 rad/s), not at half power (−3.01 dB, 5.165 rad/s). | Accepted: it is MATLAB's `bandwidth` convention, and 0.24 % apart; shared by every simulator. | — |
| 18 | Numbers | With clamping, the windup preset's overshoot is 13.463 % at the 1 ms output step and 13.451 % converged (my simulation and the app at 10 µs): the clamp switches inside a Runge–Kutta step. | Accepted: 0.012 points, far below anything the lesson or docs state (13 %, 13.5 %). | `testWindupAndClamping` |
| 19 | Summary | The step metrics are measured to the last sample, not to the final value: the open loop's time to 63 % reads 0.1952 s, the time constant to the true final speed 0.1961 s. | Accepted: the `stepinfo` convention, needed when no final value is known (saturation, a load); the docs page now says so. | — |
| 20 | Outputs | In open loop the Tracking error plot is empty. | Accepted: its title says "no reference in open loop", and the tab's power plot is still useful. | — |
