# Vehicle Handling — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/handling/index.html` (162 pictures, taken after the first round of
fixes; run `dlab.dev.captureVerification("handling")` to make them again)

## Model as implemented

**Car** (`dynamics.m`): the single-track (bicycle) model at constant forward speed V, states
v (lateral velocity, positive left) and r (yaw rate, positive turning left), δ the road-wheel angle:

    α_f = (v + a r)/V − δ          α_r = (v − b r)/V
    m (v' + V r) = F_f + F_r        I_z r' = a F_f − b F_r
    linear tyres F = −C α;  saturating F = −μ F_z tanh(C α / (μ F_z)),  F_zf = m g b/L,  F_zr = m g a/L

The path follows X' = V cos ψ − v sin ψ, Y' = V sin ψ + v cos ψ, ψ' = r. a_y = (F_f + F_r)/m, and
β = atan(v/V). Small angles: the front force is not resolved through δ, and the axle loads are
static (no load transfer). These are the textbook model's assumptions and the docs state them.

**Integration:** `ode45` (RelTol 10⁻⁸, AbsTol 10⁻¹⁰, steps ≤ min(0.02 s, output step)), stopped
by an event when |β| passes 30° (a spin).

**Linear model** (`linearModel.m`): A, B for [v; r] with linear tyres; K = (m/L)(b/C_f − a/C_r);
the steady yaw gain from −A⁻¹B; characteristic speed √(L/K) for K > 0, critical speed √(−L/K)
for K < 0. A, B, K, the steady gain from the 2 × 2 inverse, and both speeds were checked by hand
against the textbook forms.

**Against the docs page and `about()`:** they match. The docs said the lane change moves the car
"about 3.3 m"; it is 3.24 m (finding 8).

## Reference values

Independent of the engine and its tests: closed forms, and my own model in Python (scipy
`solve_ivp`, RK45, rtol 10⁻¹¹, steps ≤ 2 ms, the steering schedules written out by hand, the 30°
event). Family car: m = 1500 kg, I_z = 2500 kg·m², a = 1.1 m, b = 1.6 m, C_f = 80 kN/rad,
C_r = 110 kN/rad; oversteering car: a = 1.5, b = 1.2, C_f = 90, C_r = 75 kN/rad.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Understeer gradient, family car | (m/L)(b/C_f − a/C_r) = 0.0055556 rad/(m/s²) = 3.12262 °/g | 3.12262 | 0 | ✓ |
| Characteristic speed | √(L/K) = 22.0454 m/s = 79.3635 km/h | 79.3635 | 0 | ✓ |
| Steady yaw gain at 100 km/h | V/(L + K V²) = 3.975811 1/s | 3.97581 | 0 | ✓ |
| … at 80 km/h (lesson: V_char) | 4.082353 = V/(2L) at V_char (4.0827) | 4.08235 | 0 | ✓ |
| Poles at 100 km/h | −5.00448 ± 5.68561i, ζ 0.6607 | the same; ω_n 7.574, ζ 0.6607 | 0 | ✓ |
| Default 2° step at 100 km/h | peak a_y 0.40648 g (3.44 % above the final 0.39297 g), peak r 9.39797 °/s, peak β 0.82393°, heading at 6 s 43.57378° | 0.406478, 9.39797, 0.823928, 43.5738 | 10⁻⁶ | ✓ |
| Neutral car at 80 km/h | K = 0, r/δ = V/L = 8.230453; real poles −5.4, −5.9049 | 8.23045; Yaw and Sideslip modes | 0 | ✓ |
| Oversteering car | K = −0.0037037 rad/(m/s²) = −2.08175 °/g; V_crit = √(−L/K) = 27.000 m/s = 97.200 km/h | −2.08175, 97.2 | 0 | ✓ |
| … 70 km/h, 1° step | gain 14.960948 1/s; settles at 14.9592 °/s | 14.9592 | 0 | ✓ |
| … 120 km/h | unstable root +0.79181 1/s; spins (β = 30°) at 2.7415 s; peak a_y 6.35 g with linear tyres | spun at 2.74 s; 6.35704 g | 0 | ✓ (finding 6: the 6.3 g is flagged as unphysical) |
| … spin time just above V_crit | 98 km/h: 6.2858 s (after the 6 s run); 100 km/h: 5.2663 s | lesson accepted ≥ 98 km/h with "Spun out" required | — | ✗ → ✓ (finding 7) |
| Double lane change, 80 km/h | peak y 3.2431 m, back to y = 0.0000, heading 0.00004°, peak a_y 0.47297 g | 3.24 m, 0, 0, 0.473 g | 10⁻⁴ | ✓ (docs said 3.3 m: finding 8) |
| Tyre limit (saturating, ramp to 8° at 80 km/h) | peak a_y 0.86226 g at 6 s; α_f / α_r = 1.9546; peak β 3.82697° | 0.862257, 3.82697 | 10⁻⁶ | ✓ |
| … linear tyres at 8° | V²δ/(L + K V²) = 12.67 m/s² = 1.29 g (the lesson's "almost 1.3 g") | — | — | ✓ |
| … ramp to 15° | a_y 0.8996 g, never above μ g | test | — | ✓ |
| Slalom, 60 km/h | peak a_y 0.21441 g, peak r 7.80157 °/s | matches | 10⁻⁵ | ✓ |
| Bode, steering → yaw rate | DC gain r/δ = 3.975811; a_y/δ = V r/δ = 110.44 (m/s²)/rad | 3.976; DC gains asserted to 10⁻⁶ | 0 | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in 0.03–0.12 s headless; every Summary number
reaches the metrics; every exported column has its units, with no non-finite values; a second
solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 8.4 s for the first run while MATLAB warms
up, median 1.7 s); undo and redo; a scenario round trip; CSV (13 columns, all with units), MAT,
plot, and report exports (9 images); a 10-frame GIF; a sweep over m, an m × I_z map, a 6-sample
Monte Carlo study, a short optimization of the yaw gain; Modes (the yaw–sideslip oscillation)
and Bode; theme and text-size switches keep the result.

### Tests

`tests/sims/handling` (new: `testAgainstAnIndependentIntegration`,
`testSpinJustAboveTheCriticalSpeedIsSlow`, `summaryReadsYesOrNo`, `inputsFitAndExplainThemselves`),
`PluginConformanceTest` for the plugin, `TestLessons` for the lesson, and `ArchitectureTest`:
44 passed, 0 failed (the label check added afterwards passes on its own). None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
- [x] Numbers: defaults, every preset, and edge cases (neutral steer, just above the critical
  speed, the friction limit, 15° of steering) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (added for five), visibility (μ only with
  saturating tyres); presets load what their names say
- [x] Outputs: every tab readable in both themes and at Larger text; the animation's car, wheels,
  velocity and force arrows, and readout agree with the plots at the same time
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere; no NaN shown; the
  report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes and Bode against hand values
- [x] Teaching: every lesson statement and number checked (finding 7)
- [x] Behaviour: readable errors; Cancel; run times under 0.15 s; nothing left behind on preset,
  theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | "Linear model stable" and "Spun out" read "1 · yes = 1". | "yes"/"no", units column empty. | `summaryReadsYesOrNo` |
| 2 | Inputs | The tyre-model choices "Linear (F = −C α)" and "Saturating (friction limit μ F_z)" were cut off in their field. | "Linear" / "Saturating", with the formulas in the tooltip. | `inputsFitAndExplainThemselves` |
| 3 | Inputs | Mass, centre of mass to front axle, duration and output step had no tooltip. | Added. | `inputsFitAndExplainThemselves` |
| 4 | Inputs | "Front/Rear cornering stiffness (axle) (N/rad)" was cut off in the input panel. | "Front/Rear cornering stiffness"; "per axle" is in the tooltip. | `inputsFitAndExplainThemselves` |
| 5 | Analysis | The Bode tab showed no units for the steering input or the outputs. | rad, rad/s, m/s². | `inputsFitAndExplainThemselves` |
| 6 | Behaviour | The 120 km/h preset spins with linear tyres, and the Summary showed a peak lateral acceleration of 6.36 g with no comment. | The status line says linear tyres have no grip limit, so the forces near the end are not physical; the docs say so. | `summaryReadsYesOrNo` |
| 7 | Teaching | The oversteer step accepted any speed of 98 km/h or more but needed a spin; at 98 km/h the car spins at 6.29 s, after the 6 s run, so a learner who did as asked could not pass. | "100 km/h or more", with why (the spin builds slowly just above V_crit); the check asks for 100. | `testSpinJustAboveTheCriticalSpeedIsSlow`, `TestLessons` |
| 8 | Docs | "About 3.3 m to the left"; the lane change reaches 3.24 m. | "About 3.2 m". | — |

Accepted:
- **The lateral-acceleration plot** shows both ±μ g lines for saturating tyres, so a turn one way
  leaves half the plot empty; a slalom needs both.
- **a_y jumps at a steering step:** a step in δ changes the front slip angle at once, and so the
  front force. That is the model's (and the real car's, to first order) behaviour.
- **Static axle loads, small angles:** stated in the docs and `about()`.
