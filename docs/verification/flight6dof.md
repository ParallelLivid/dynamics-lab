# 6DOF Flight — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/flight6dof/index.html` (331 pictures before findings 5 and 6: every
preset in the dark theme and four in the light theme; the full capture ran past its 29-minute
limit, so the rest were taken by hand: `after-*.png`, 20 pictures after the fixes, in the light
theme and at Larger text, of straight flight, the Dutch-roll excitation, the loop, the crosswind,
the phugoid and an autopilot turn; run
`dlab.dev.captureVerification("flight6dof")` to make them again)

## Model as implemented

**Engine** (`dynamics.m`, `simulate6dof.m`, `trim6dof.m`): a rigid body in body axes over a flat,
non-rotating north-east-down frame.

- Forces: lift ½ρV²S·CL along [sin α, 0, −cos α] (perpendicular to the chordwise flow), drag
  −½ρV²S·CD along the air-relative velocity, gravity m·9.81, thrust Tmax·throttle along body x.
  CL = cos²β · CLmax·tanh(CLα·αₑ/CLmax) and CD = CD₀ + cos²β·CDα²·αₑ², with αₑ = 60° tanh(α/60°)
  and cos²β = (u² + w²)/V² (the chordwise share of the flow). ρ is the ISA's.
- Moments, as angular accelerations: ṗ = (Kctrl·aileron + (Iy − Iz)qr)/Ix − damp_p·p − roll_β·β,
  q̇ = (Kctrl·elevator + (Iz − Ix)pr)/Iy − damp_q·q − pitch_α·cos²β·(αₑ − α_trim),
  ṙ = (Kctrl·rudder + (Ix − Iy)pq)/Iz − damp_r·r + yaw_β·β. The stability and damping terms do
  not scale with the dynamic pressure, as a real aircraft's do (finding 3).
- Kinematics: u̇ = F/m + r v − q w (and the other two), Euler-angle rates or q̇ = ½ q ⊗ [0; ω]
  (default) with a norm correction, and the NED velocity R(φ, θ, ψ)·[u v w].
- Wind: steady, uniform or with a 1/7 power law; the aerodynamics use the air-relative velocity.
- Autopilot (`autopilotLaw.m`): the altitude, heading and airspeed holds of the docs, with
  integrals inside capture bands and while unsaturated.
- `ode45` (RelTol 10⁻⁴ by default, MaxStep 0.1 s), stopped at the ground, the airspeed limit, the
  pitch limit (Euler only) or the wall-clock limit.

**Against the docs page and `about()`:** `about()` said "12 states … Euler angles" (the default is
a quaternion, 13 states) and that the controls are "held constant for the whole run" (they can be
schedules) (finding 2); the docs did not say that the stability terms ignore airspeed (finding 3).

## Reference values

Independent of the engine: my own copy of the model written from the docs (Euler angles, my own
ISA density, scipy DOP853 at RelTol 10⁻¹¹), trim by `fsolve`, and the modes from my own
finite-difference Jacobian; hand calculations for the trim balance and the crosswind.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Trim at 20 m/s, 100 m (by hand) | lift 9.491 N + thrust's vertical part 0.319 N = 9.81 N; drag 12.216 N = thrust's forward part | — | — | ✓ |
| … by `fsolve` | α 0.02610448073618 rad (1.49568°), throttle 0.6109817547824, pitch torque 5·10⁻¹¹ | the preset: 0.0261044803493, 0.6109817636934 | 4·10⁻¹² rad; 1.5·10⁻⁸ (my ISA constants) | ✓ |
| Straight flight, 20 s | 100.000000 m, 20.000000 m/s, 400.000003 m | 100, 20, 400 | 0 | ✓ |
| Glide, 20 s (no pitch stiffness, no thrust) | 69.9945 m, 6.9866 m/s, 150.1559 m | 69.99452, 6.986611, 150.1559 | 0 | ✓ |
| Crosswind 10 m/s from the west, 20 s | ground speed √(20² + 10²) = 22.3607 m/s; drift 10 × 20 = 200 m; crab −atan(10/20) = −26.565° | 22.36068, 200, −26.56505 | 0 | ✓ |
| Modes about the 20 m/s trim | Dutch roll −1.01979 ± 1.93662i (3.24441 s, ζ 0.4659); roll subsidence −1.5 (0.66667 s); spiral −0.0711945 (14.046 s); short period −18.3737 (0.054426 s); longitudinal −0.0562582, −1.11179, −2.429 (no oscillation); heading 0 | −1.02 ± 1.937i (3.2444 s, 0.46593); −1.5; −0.07119 (14.046 s); −18.37 (0.054425 s); −0.05626, −1.112, −2.429; 0 | 0 | ✓ |
| Phugoid preset (CD₀ 0.02, 23 m/s on the 20 m/s attitude, not trimmed) | phugoid −0.13556 ± 0.197406i: 31.8287 s, ζ 0.5661; Dutch roll 3.35742 s; altitude 104.89 m at 11.86 s, then down to 87.850 m at 120 s with no second swing | 31.829 s, 0.56608 (with the not-an-equilibrium note); 3.3574 s; 87.85043 m | 0 | ✓ (finding 4) |
| Excite: phugoid, trimmed at 23 m/s | α 0.02025731, throttle 0.16114799; phugoid 38.5549 s, ζ 0.6363; Lanchester's π√2·V/g would be 10.4 s | 38.555 s, 0.63627; identified 41.33 s, ζ 0.669 (7 %, the docs allow 10 %) | 0 | ✓ |
| Identification (Excite presets) | Dutch roll 3.244 s; roll subsidence 0.667 s; spiral 14.05 s | 3.2453 s, ζ 0.4698; 0.6687 s; 14.006 s | < 0.3 % | ✓ |
| Autopilot presets | climb to 150 m; turn to 90° holding 100 m and 20 m/s; a pitch pulse ridden out | 150.0024 m, 20.0003 m/s; 90.0000°, 99.950 m, 19.998 m/s; 99.99992 m, 22.99999 m/s | within the docs' tolerances | ✓ |
| Lesson numbers | level at 100 m; trimmed at 24 m/s with less α (1.038° against 1.496°); "both longitudinal modes heavily damped"; Dutch roll about 3.2 s, identified about 3.24 s; phugoid about 32 s | as stated | — | ✓ (finding 4) |

## Automatic checks

From `captureVerification`: every preset solves in under 1.1 s headless; every Summary number
reaches the metrics; every exported column has its units (the controls and the quaternion are
dimensionless); no non-finite values; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (16 presets; slowest 15.3 s, the first run while
MATLAB warms up; median 4.4 s); undo and redo of u₀; a scenario round trip; CSV (24 columns), MAT,
plot and report exports (12 images); a 10-frame GIF; a sweep of u₀; a map of u₀ and w₀;
uncertainty; a short optimization; Modes (8 named modes) and Bode; theme and text-size switches
keep the result.

### Tests

`tests/sims/flight6dof` (new: `inputsExplainThemselves`, `phugoidPresetSwingsOnce`,
`steadyTracesAreInsideTheirPlots`), `PluginConformanceTest` for `Flight6dofPlugin`, `TestLessons`
for its lesson, and `ArchitectureTest`: 73 passed, 0 failed. None excluded. `codeIssues` on every
touched file: 0.

## Checklist

- [x] Physics: forces, moments, kinematics (Euler and quaternion), wind and the autopilot laws
  checked against the docs; the trim balance by hand
- [x] Numbers: the presets, trim, crosswind and every mode against my own model, to every digit
  shown
- [x] Inputs: labels, units and ranges; a tooltip on every input (finding 1); the choices fit
  (finding 5); the wind inputs appear only with wind, the pitch limit only with Euler angles
- [x] Outputs: every tab of every preset in the dark theme, a subset in the light theme and at
  Larger text; the animation's readout agrees with the plots; steady traces inside their plots
  (finding 6); the Mode ID fits and tables readable
- [x] Summary and exports: units in the units column; text rows (termination, identified mode)
  as text
- [x] Analysis: Modes against my own Jacobian; mode identification within its stated
  tolerances; Sweep, Map, Optimize, Uncertainty run
- [x] Teaching: every number checked; the phugoid step corrected (finding 4)
- [x] Behaviour: early stops (ground, airspeed, pitch, wall clock) reported in the status bar;
  Trim and Tune explain what they cannot do

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | 47 inputs had no tooltip (the initial state, the rudder, the aircraft, stability and solver settings, several autopilot gains), and the stiffness terms had no units. | Tooltips on every input; "Pitch stiffness" in 1/s², with what it means. | `inputsExplainThemselves` |
| 2 | Docs | `about()` said "Rigid-body flight model with 12 states … Euler angles" although the default attitude is a quaternion (13 states), and that the controls are "held constant for the whole run", contradicting its own later paragraph on schedules. | Both corrected. | `inputsExplainThemselves` |
| 3 | Physics | The docs did not say that the stability and damping terms are angular accelerations that stay the same at every airspeed (a real aircraft's grow with the dynamic pressure): an approximation the checklist does not allow to go unstated. It is why the phugoid is heavily damped and four times slower than Lanchester's estimate. | The docs give the three moment equations and say so; so does `about()`; the tooltips say "the same at every airspeed". | — (documentation) |
| 4 | Teaching | The phugoid step said to "compare the phugoid period on the Analyze ▸ Modes tab with the oscillation on the Altitude tab", and its success "the same rhythm as the altitude plot". With ζ 0.57 there is no oscillation to compare: the altitude rises once to 104.9 m and then only sinks. | The step says what happens (one swing up, then a slow descent) and why (heavily damped; this model's pitch stiffness does not grow with speed). | `phugoidPresetSwingsOnce`, `TestLessons` |
| 5 | Inputs | Choices were longer than their fields: "Same at every height" / "Stronger with height", "Relative to the air" / "Relative to the ground", "Quaternion (no pitch limit)" / "Euler angles (legacy)", "Automatic (from the excitation)", "Roll subsidence". | "Uniform" / "Power law", "Initial velocity relative to: The air / The ground", "Quaternion" / "Euler", "Automatic" … "Roll", with the detail in the tooltips. | `inputsExplainThemselves` |
| 6 | Outputs | A steady trace lay on the frame of its plot: in straight flight the airspeed (20 m/s on a 0–20 axis), α and θ (1.4957° on a 0–1.5 axis). | The airspeed, altitude, angle, rate, air-data and control plots have padded limits. | `steadyTracesAreInsideTheirPlots` |
| 7 | Outputs | In straight flight the body-rate plot stretched round-off (10⁻¹⁰ rad/s) over its whole height (found with the quadrotor's finding 4). | The angle and rate plots show at least 0.1° and 0.01 rad/s. | `steadyTracesAreInsideTheirPlots` |

Accepted:
- **A teaching model, as the docs say**: normalized control torques, no control-surface or
  propeller modelling, gravity 9.81 m/s².
