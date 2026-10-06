# Spacecraft Attitude Control — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/attitude/index.html` (160 pictures, before findings 4 and 5;
`after-*.png` after them: the three-axis slew's animation in both themes, the hold's torques and
animation, the bang-bang torques; run `dlab.dev.captureVerification("attitude")` to make them
again). The showcase image was made again (`dlab.dev.generateImages(Ids="attitude")`).

## Model as implemented

**Engine** (`simulateAttitude.m`): a rigid body with principal inertias I and a reaction wheel on
each body axis.

- I ω̇ = −ω × (I ω + h) − τ_w + τ_thr + τ_d, ḣ = τ_w, q̇ = ½ q ⊗ [0; ω] (scalar-first quaternion,
  body to world), with a normalization term. I derived the wheel form from d/dt(Iω + h) +
  ω × (Iω + h) = τ_ext: it matches.
- Wheels: each gives at most ±τ_max and holds at most ±h_max; a wheel at its limit cannot take
  more momentum outward (events find the moments exactly).
- PD: τ = −Kp · 2 sign(q_e0) q_e,vec − Kd ω with q_e = q_target⁻¹ ⊗ q, per radian for small
  errors; detumble τ = −Kd ω; hold = PD to the start attitude.
- Bang-bang: about the eigenaxis e, α = thrust / max_i(I_i |e_i| + θ |(e × I e)_i|) so that the
  gyroscopic torque at the peak rate (ω² = θα) also fits; t = 2√(θ/α), 2√(θI/τ) about a principal
  axis; the thrusters supply I α e + ω × (Iω + h). I checked the bound by hand.
- Dumping: an axis fires its thrusters against its wheel from 80 % (input) down to 10 %.
- `ode45`, RelTol 10⁻¹⁰, segment by segment between events.

**Against the docs page and `about()`:** they match (the docs said "wheels saturated (1/0)";
it reads yes or no).

## Reference values

Independent of the engine: my own rigid body with wheels (scipy DOP853, RelTol 10⁻¹¹), with
quaternion products, the 3-2-1 Euler conversion, the PD law and the wheel limits written out
afresh; closed forms for the bang-bang slew and the Bode bandwidth.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| 90° yaw slew (PD, the default: Kp 0.5, Kd 7, I_z 50, ζ 0.7) | within 0.1° at 107.732 s; overshoot 3.891 %; peak rate 3.58615 °/s; z wheel 3.1295 N·m·s; wheel torque at its 0.2 N·m limit for 0–13.3 s | 107.7317; 3.891213; 3.586146; 3.129503 (52.16 %); 0–13.2 s (0.1 s samples) | 0 | ✓ |
| … with Kd 10 (the lesson) | 97.714 s, no overshoot, at the limit for 0–10.6 s, 2.5763 N·m·s | 97.7145; 0; 0–10.5 s; 2.576251 | 0 | ✓ |
| Large three-axis slew (to 60°, −40°, 120°) | eigenaxis angle 150.0023°; within 0.1° at 113.176 s; peak rate 5.31751 °/s; 3.71674 N·m·s | 150.0023; 113.1763; 5.31751; 3.716737 | 0 | ✓ |
| Bang-bang 90° about z, 1 N·m | T = 2√(θ I/τ) = 17.72454 s; α = 1/50 rad/s² = 1.145916 °/s²; within 0.1° at T − √(2 · 0.1°/α) = 17.3068 s; peak rate √(θα) = 10.155 °/s; impulse τT = 17.7245 N·m·s | 17.72454; 1.145916; 17.30713; 10.14135 (the largest 0.05 s sample); 17.72454 | 0 | ✓ |
| Detumble from (3, −2, 4) °/s, Kd 7 | |ω| 1.84506, 0.10365, 0.0011 °/s at 10, 30, 60 s; wheels end at (1.428112, −1.608787, 3.46034) N·m·s; largest angle 45.5967° | 1.8451, 0.10365, 0.0011; (1.42811, −1.60879, 3.46034); 45.59669 | 0 | ✓ |
| Hold against (0.002, 0, 0.01) N·m, Kp 1, Kd 10 | z wheel full (6 N·m·s) at h_max/τ_d = 600 s; then the body turns: 124.59° at 750 s (½ (0.01/50) 150² = 2.25 rad = 129° for a free body); x wheel −1.17439 at the end | 600 s; 124.5901°; −1.17439 | 0 | ✓ |
| … with dumping | from 80 % (4.8 N·m·s, near 480 s) the 0.02 N·m thrusters net −0.01 N·m: 2.1 N·m·s at 750 s; impulse 0.02 × 270 = 5.4 N·m·s | 2.09994; 5.4; one dump | 0 | ✓ |
| Free tumble about the intermediate axis | energy and inertial momentum constant; it turns over (ω_y changes sign) | drift 6·10⁻¹⁵ and 2.7·10⁻¹³; 179.9975° from the start | — | ✓ |
| Bode, torque about x → roll error (defaults) | DC gain 1/Kp = 2 rad/(N·m); ωn = √(Kp/I_x) = 0.1291 rad/s, ζ = 0.904: −3 dB at 0.0958 rad/s | 2; 0.0955 rad/s | 0.3 % (frequency grid) | ✓ |
| Lesson numbers | 3.5 N·m·s left in the z wheel (3.46); ζ = 0.7 about z; Kd 10: no overshoot, under 100 s, at the limit for the first ten seconds; 2√(π/2 · 50/1) ≈ 17.7 s, "about six times faster" (107.7/17.3 = 6.2); 0.01 N·m fills 6 N·m·s in 600 s | as stated | — | ✓ (finding 2) |

## Automatic checks

From `captureVerification`: every preset solves in under 1.2 s headless; every Summary number
reaches the metrics; every exported column has its units (the quaternion's are dimensionless); no
non-finite values; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 18.1 s for the free tumble, the first run
while MATLAB warms up; median 4.6 s); undo and redo of I_x; a scenario round trip; CSV (21
columns), MAT, plot and report exports (9 images); a 10-frame GIF; a sweep of I_x; a map of I_x
and I_y; uncertainty; a short optimization of the slew time over I_x; Modes (yaw, pitch and roll
oscillations) and Bode; theme and text-size switches keep the result. The plot export printed a
warning from inside MATLAB's `exportgraphics` ("Invalid or deleted object" in an asyncio
channel); the file was written, and the same warning appears for other simulators.

### Tests

`tests/sims/attitude` (new: `testSlewMatchesAnIndependentIntegration`,
`torquesAndBodyAreVisible`; earlier the same day `inputsFitAndExplainThemselves`),
`PluginConformanceTest` for `AttitudePlugin`, `TestLessons` for its lesson, and
`ArchitectureTest`: 45 passed, 0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: Euler's equations with wheel momentum, the quaternion kinematics, the PD and
  bang-bang laws (the gyroscopic bound), the limits and dumping checked by hand
- [x] Numbers: every preset against my own integration, to every digit shown; bang-bang, the
  saturation time and the Bode bandwidth by formula
- [x] Inputs: labels, units, ranges, tooltips on every input (finding 1); visibility by mode
- [x] Outputs: every tab of every preset in both themes and at Larger text; the animation's
  wheel bars agree with the Wheel momentum tab; findings 4 and 5
- [x] Summary and exports: units in the units column; "Wheels saturated" in words
- [x] Analysis: Modes (ωn = √(Kp/I), ζ = Kd/(2√(Kp I)) per axis) and Bode by hand; Sweep, Map,
  Optimize and Uncertainty on the inertias give sensible results
- [x] Teaching: every number checked; two corrected earlier the same day (finding 2)
- [x] Behaviour: readable errors (impossible inertias, bad limits); saturation is reported in the
  status bar

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | (Earlier the same day.) The mode choices were cut off ("Slew: thrusters, bang-bang", "Hold against a disturbance"), and nine inputs had no tooltip. | "Free", "Detumble", "PD slew", "Bang-bang", "Hold", explained in the tooltip; tooltips added. | `inputsFitAndExplainThemselves` |
| 2 | Teaching | (Earlier the same day.) "The wheels are at their 0.2 N·m limit for much of the slew": with Kd 10 it is the first 10.6 s of 98; "about five times faster": 6.2 times. | "for the first ten seconds, which caps how fast the slew can start"; "about six times". | `TestLessons` |
| 3 | Exports | The result's relative energy and momentum drift divided by a start value of zero outside free mode: 4·10³⁰⁶ in the MAT export (the Summary shows them only in free mode). | NaN when the start value is 0. | `testSlewMatchesAnIndependentIntegration` |
| 4 | Outputs | The body was drawn in the palette's lime (already known to be loud), and the green y axis all but vanished against it. | A neutral body (the theme's border grey) under the blue panels; the showcase image made again. | `torquesAndBodyAreVisible` |
| 5 | Outputs | On the Torques tab a constant torque at the plot's limit lay on its edge: the hold's 0.01 N·m disturbance and the bang-bang ±1 N·m thrust were hidden in the frame. | The thruster and disturbance plot has padded limits. | `torquesAndBodyAreVisible` |

Accepted:
- **Cancel takes 0.2–0.4 s** (a known limitation): the outputs are built for every sample
  reached before the stop, which keeps a cancelled run's plots complete.
- **3-2-1 Euler angles** in the plots and inputs are singular at ±90° pitch (gimbal lock); the
  engine works in quaternions, so only the angle plot is affected; the docs now say so.
