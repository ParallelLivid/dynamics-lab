# Pendulum — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/pendulum/index.html` (169 pictures; run
`dlab.dev.captureVerification("pendulum")` to make them again)

## Model as implemented

**Single pendulum** (`pendulum_solve.m`): a point bob on a massless rod, θ from straight down,
positive counter-clockwise.

    θ'' = −(b / (m L²)) θ' − (g / L) sin θ

- Damping is a torque −b θ' at the pivot (b in N·m·s), so the damping rate is b/(m L²).
- `ode45` at RelTol 1e-9, AbsTol 1e-11, or `ode15s` when the damping rate exceeds 20 √(g/L)
  (stiff). Samples are taken from the dense solution at the output step, ending exactly at the
  duration.
- Energies: KE = ½ m L² θ'², PE = m g L (1 − cos θ) (zero hanging). Bob at (L sin θ, −L cos θ).
- The small-angle comparison solves θ'' = −c θ' − (g/L) θ exactly from the same start.

**Double pendulum** (`double_pendulum_rhs.m`): two point bobs on massless rods, both angles from
straight down. Lagrange's equations M(θ) ω' = f(θ, ω), with damping b at the pivot (on ω₁) and at
the elbow (on ω₂ − ω₁, with the reaction on the upper rod). Integrated by `ode45` at RelTol 1e-10,
AbsTol 1e-12. A twin starts with θ₂ higher by δ. The Poincaré section records (θ₂, ω₂) when θ₁
passes 0 moving forward. The Lyapunov exponent uses Benettin's method (renormalise every
0.25 s from d₀ = 10⁻⁸).

**Against the docs page and `about()`:** both match. The equations, sign conventions, and damping
placement are as stated.

## Reference values

Independent of the engine and its tests: closed forms worked out separately and compared with the
app's own numbers (Summary, Modes). m = 1 kg, L = 1 m, g = 9.81 m/s².

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Undamped period, 5° | 2.00702 s (T = 4 K(sin²(θ₀/2)) / ω₀, complete elliptic integral) | 2.00702 s | 2e-9 | ✓ |
| Undamped period, 30° | 2.04099 s (same) | 2.04099 s | 1e-7 | ✓ |
| Undamped period, 170° | 4.89352 s (same) | 4.89352 s | 3e-7 | ✓ |
| Initial energy, 30° | 1.31429 J (m g L (1 − cos 30°)) | 1.31429 J | 9e-16 | ✓ |
| Energy lost in 15 s, defaults | 77.69 % (small-angle 1 − e^(−γt), γ = b/(mL²)) | 77.86 % | 0.17 % | ✓ (30° is not quite small) |
| Measured period, defaults (b = 0.1) | between 2.0063 s (damped, small angle) and 2.0410 s (exact, 30°) | 2.0234 s | — | ✓ (the swing decays during the run) |
| Modes: natural frequency | 3.13209 rad/s (√(g/L)) | 3.13209 rad/s | 3e-13 | ✓ |
| Modes: damping ratio, defaults | 0.0159638 (b / (2 m L² ω₀)) | 0.0159638 | 1e-15 | ✓ |
| Heavily damped (b = 3): period | 2.28517 s (2π / (ω₀ √(1 − ζ²)), ζ = 0.479) | 2.28525 s | 7e-5 | ✓ |
| Undamped, 30°: energy drift | 0 | 5e-9 relative | — | ✓ (solver tolerance) |
| Over the top: initial energy | 24.5 J (½ m L² ω₀², ω₀ = 7 rad/s) | 24.5 J | 0 | ✓ (exceeds 2 m g L = 19.62 J, so it goes over) |
| Double, normal mode in phase | 2.39720 rad/s (√((2 − √2) g/L), equal rods and bobs) | 2.39720 rad/s | 5e-14 | ✓ |
| Double, normal mode anti-phase | 5.78735 rad/s (√((2 + √2) g/L)) | 5.78735 rad/s | 4e-12 | ✓ |
| Double, chaotic, undamped: energy drift | 0 | 4e-10 relative | — | ✓ |
| Lesson "How long does a swing take?", 150° | 3.535 s (elliptic integral) | text says "about 3.5 s" | — | ✓ |

## Automatic checks

From `captureVerification` (headless): every preset solves in 0.05–0.25 s; every Summary
number reaches the metrics; every exported column has units and no NaN or Inf; a second solve
gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs; undo and redo; a scenario round trip keeps every
input; CSV (units on all 6 columns), MAT, plot, and report exports (the report has every Summary
row and 6 images); a 10-frame GIF; a 3-run sweep, a 2 × 2 map, a 6-sample Monte Carlo study, and
a short optimization, all without errors; Modes shows the Swing mode; theme and text-size
switches keep the result. In the app a run takes 0.7–2 s after the first; the first can take
several seconds while MATLAB warms up its plotting (noted under K5).

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
- [x] Numbers: defaults, every preset, and edge cases against the reference values (table above)
- [x] Inputs: labels, units, ranges, tooltips, visibility rules (double-pendulum inputs appear
  only for the double pendulum); presets load what they say
- [x] Outputs: every tab readable in both themes and at Larger text (169 screenshots); the
  animation's angle readout agrees with the Angle plot at the same time
- [x] Summary and exports: Summary, plots, and CSV agree; units everywhere; the report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes against hand values
- [x] Teaching: all four Pendulum lessons pass, and their statements and numbers agree with the
  reference values
- [x] Behaviour: no errors in any preset; Cancel is covered by the suite (TestShell); results
  survive theme and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Outputs | The animation drew a ceiling across the pivot's height; a pendulum swinging above the pivot (Over the top, Large swing, the double pendulum's chaotic runs) had its rod drawn through it. | The ceiling shows only when every bob stays below the pivot for the whole run; otherwise the pendulum turns on an axle (just the pivot). | `ceilingOnlyWhenTheBobStaysBelowThePivot` |
| 2 | Summary | Over the top showed "Period (measured) NaN s", and a peak angle of 863.66° with no explanation. | No period reads "— (no complete swings)" (and is left out of the metrics); a new row, "Passes over the top", counts the passes. | `overTheTopPresetRotates` |
| 3 | Outputs (all simulators) | At the Larger text size, the 340 px input column cut off choices ("Single pe…"). | The input and lesson columns widen with the text size. | — (layout) |
| 4 | Teaching (all lessons) | Lessons still said "the Sweep tab", "the Modes tab", though those tools are now inside Analyze. | 47 mentions now read "the Analyze ▸ Sweep tab" and so on; check messages say "(Analyze ▸ Sweep)". | `TestLessonChecks` |
| 5 | Outputs (all simulators) | Tab titles and table headers do not grow with the text size. | Accepted: MATLAB gives tabs and table headers no font size to set. | — |
