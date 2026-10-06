# Quarter-Car Suspension — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/quartercar/index.html` (129 pictures before the fixes; `after-*.png`
after them: the Summary, the tire load and the animation in both themes and at Larger text, the
lift-off-off case, and the Bode tab; run `dlab.dev.captureVerification("quartercar")` to make
them again)

## Model as implemented

**Car** (`simulateQuarterCar.m`): a body (sprung mass m_s) on a spring k_s and damper c_s above a
wheel (unsprung mass m_u) on a tire (k_t, c_t), heights measured from static equilibrium, upward
positive. W = (m_s + m_u) g is the static tire load.

    m_s z_s'' = −k_s (z_s − z_u) − c_s (z_s' − z_u')
    m_u z_u'' =  k_s (z_s − z_u) + c_s (z_s' − z_u') + F − W
    F = W − k_t (z_u − z_r) − c_t (z_u' − z_r')        (F ≥ 0 with lift-off)

The wheel meets the road height z_r(s) at s = V t; z_r' = V dz_r/ds.

**Roads** (`roadProfile.m`): bump or pothole, a half sine of height h over length ℓ; kerb, a
raised-cosine ramp over 5 cm; sine, from the start distance; random, ISO 8608: 200 cosines at
log-spaced spatial frequencies 0.011–2.83 cycles/m with amplitudes √(2 G(n) Δn),
G(n) = G(n₀)(n/n₀)⁻², n₀ = 0.1 cycles/m, G(n₀) = 16·4^(k−1)·10⁻⁶ m³ (the geometric means of
classes A–H in the standard), phases from a seeded sequence, shifted to start at 0. All checked
against the standard's values and by integrating each road's slope (`testRoadSlopes`).

**Integration:** classical Runge–Kutta at a fixed step h = min(feature length/(20 V), 0.15/|λ|max,
output step), dividing every output interval, the road evaluated at the stage times. Since this
round: at most 2 million output samples and 5 million steps, each refused with a message that
names the cause.

**Linear model** (plugin `linearization`): state [z_s, ż_s, z_u, w] with w = ż_u − (c_t/m_u) z_r so
that the road height enters without its rate (checked by hand: ẇ has no ż_r term); outputs body
height, body acceleration, travel, tire deflection. Summary frequencies: the undamped
eig(K, M); Modes: the damped modes' |λ|.

**Against the docs page and `about()`:** both wrote "F − m g" with m undefined (finding 9); the docs
described an internal frequency response no one sees, and did not say that the RMS values cover
the whole run (finding 14). Otherwise they match.

## Reference values

Independent of the engine and its tests: my own model in Python (scipy `solve_ivp`, RK45,
rtol 10⁻¹⁰, steps ≤ 0.2 ms, my own road functions, sampled on the same 2 ms grid), closed forms
for the natural frequencies and the frequency response, and the ISO 8608 band integral.
Defaults: m_s = 300 kg, m_u = 40 kg, k_s = 20 kN/m, c_s = 1500 N·s/m, k_t = 200 kN/m, c_t = 0, a
6 cm, 1 m bump 2 m ahead at 20 km/h, 3 s.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Undamped frequencies | 1.238330, 11.809820 Hz (roots of det(K − ω²M)) | 1.23833, 11.8098 | 0 | ✓ |
| Damped modes | −2.11635 ± 7.61027i, −19.13365 ± 70.54219i (eig of my A) | the same; ω_n 7.8991, 73.091 rad/s; ζ 0.2679, 0.2618 | 0 | ✓ |
| Damping ratio | c_s / 2√(k_s m_s) = 0.306186 | 0.306186 | 0 | ✓ |
| Defaults: RMS / peak body acceleration | 1.37178 / 7.89139 m/s² | 1.37178 / 7.8914 | 10⁻⁶ | ✓ |
| … travel, RMS dynamic tire load / W, minimum load | 4.87182 cm, 0.144333, 849.348 N | 4.87183, 0.144333, 849.343 | 6·10⁻⁶ | ✓ |
| Sports car (40 km/h) | 3.27048, 23.2815, 4.26990 cm, 0.324957; off the road 0.126 s | 3.27048, 23.2815, 4.2699, 0.324955; 0.126 s | 10⁻⁵ | ✓ |
| Truck | 1.46179, 8.14780, 6.50756 cm, 0.147733, min 7927.79 N | 1.4618, 8.1478, 6.50757, 0.147733, 7927.77 | 10⁻⁵ | ✓ |
| Worn dampers (40 km/h) | 1.54740, 6.74779, 8.57492 cm, 0.424141; off 0.174 s | 1.54683, 6.74779, 8.57478, 0.424027; 0.172 s | 4·10⁻⁴ | ✓ (accepted: fixed steps across the lift-off kinks; one 2 ms sample of air time) |
| Resonance: wheel hop (64 km/h) | 4.38524, 6.37164, 1.73203 cm, 0.821496; off 0.830 s | 4.3853, 6.3732, 1.73245, 0.821503; 0.83 s | 2·10⁻⁴ | ✓ |
| … road frequency | 64/3.6 / 1.5 = 11.85 Hz, next to the wheel hop at 11.81 | Bode marker | — | ✓ |
| Same at 30 km/h | no lift-off, min load 2273.0 N, RMS 0.16705 | 2272.98 N, 0.16705 | 0 | ✓ |
| Defaults at 40 km/h | peak 12.0248 m/s², off the road 0.050 s | 12.0248, 0.05 s | 0 | ✓ (finding 5) |
| Defaults at 80 km/h, lift-off off | min load −9263.7 N (the tire pulls), 0.03 s | −9263.05 N; said "the wheel left the road … no grip while airborne" | 7·10⁻⁵ | ✗ → ✓ (finding 2) |
| 10 cm kerb, 5 s | both masses end 0.1000 m higher; off the road 0.042 s | 0.10000, 0.10000; 0.042 s | 0 | ✓ |
| Damper sweep (20 km/h bump) | RMS acceleration least at c_s = 842 N·s/m (ζ 0.172); RMS tire load least at 1165 (ζ 0.238) | lesson said "both best around 1000–1500, ζ 0.2–0.3" | — | ✗ → ✓ (finding 6) |
| Bode road → body | DC 1; peak 2.23446 at 1.18930 Hz; −3 dB at 2.12100 Hz | 2.234 at 1.182 Hz before (the grid point), 1.1893 after; 2.121 | 0.6 % before | ✗ → ✓ (finding 13) |
| Bode at 1 Hz | body 1.97737, travel 1.05923, tire deflection 0.12519 | steady 1 cm sine at 1 Hz: amplitude within 0.5 % (test) | — | ✓ |
| ISO class D road | band RMS √(G₀ n₀² (1/0.011 − 1/2.83)) = 3.045 cm | 3.087 cm over 5 km of seed 1 | 1.4 % (one sample of road) | ✓ |
| Lesson: 1 m bump at 20 → 40 km/h | peak 7.89 → 12.02 m/s² | "about 8 to 12" | — | ✓ |
| Lesson: worn dampers at 40 km/h | off the road 0.172 s against 0.050 s healthy; RMS tire load 0.424 against 0.220 | lesson said the worn car hops off (true) as if the healthy one did not | — | ✗ → ✓ (finding 7) |

## Automatic checks

From `captureVerification`: every preset solves in 0.01–0.56 s headless; every Summary number
reaches the metrics; every exported column has its units, with no non-finite values; a second
solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs (slowest 8.1 s for the
first run while MATLAB warms up, median 0.9 s); undo and redo; a scenario round trip; CSV (8
columns, all with units), MAT, plot, and report exports (8 images); a 10-frame GIF; a sweep over
m_s, an m_s × m_u map, a 6-sample Monte Carlo study, a short optimization of the RMS acceleration;
Modes (Body bounce, Wheel hop) and Bode; theme and text-size switches keep the result.

### Tests

`tests/sims/quartercar` (new: `testRejectsTooManySamples`, `testAgainstAnIndependentIntegration`,
`testWithoutLiftoffTheTirePullsInstead`, `testKerbRaisesTheCar`, `summaryReadsYesOrNo`,
`pullingTireIsNotCalledAirborne`, `inputsFitAndExplainThemselves`), `PluginConformanceTest` for the
plugin, `TestLessons` for the lesson, `TestFrequencyResponse` (new `peakIsExactOnTheDefaultGrid`),
and `ArchitectureTest`: 56 passed, 0 failed. Because the shared `FrequencyResponse` changed, every
other simulator with a Bode tab was run too: `tests/sims` for attitude, cartpole, dcmotor,
handling, massspring, quadrotor, with `TestLessonChecks` and their lessons: 151 passed, 0 failed.
None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
- [x] Numbers: defaults, every preset, and edge cases (lift-off on and off, a kerb, higher speeds,
  a wavy road off resonance, a long rough road) against the reference values
- [x] Inputs: labels, units, ranges, tooltips (added for 8 inputs), visibility rules (length for
  bump and pothole, wavelength for sine, class and seed for rough); presets load what their names say
- [x] Outputs: every tab readable in both themes and at Larger text; the animation's body, wheel,
  springs and readout agree with the plots at the same time
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere; no NaN shown; the
  report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; Modes and Bode against hand values
- [x] Teaching: every lesson statement and number checked (findings 4–8)
- [x] Behaviour: readable errors; Cancel; run times under 0.6 s; nothing left behind on preset,
  theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | "Wheel left the road" read "1 · yes = 1"; how long was only in the status line. | "yes"/"no", and a "Time off the road" row (s). | `summaryReadsYesOrNo` |
| 2 | Physics, wording | With lift-off off, a negative tire load (the tire pulling the road) was reported as "the wheel left the road … no grip while airborne", the wheel turned red and the plot marked it off the road, though the model keeps it on. | The engine tells lifting off (`airborne`) from pulling (`pulling`); the status line says the tire pulled the road and that a real wheel would lift off; a Summary row gives how long; the tire plot marks "Tire pulling the road". | `testWithoutLiftoffTheTirePullsInstead`, `pullingTireIsNotCalledAirborne` |
| 3 | Summary | The body-bounce frequency (1.238 Hz, undamped) disagreed with the Modes tab (7.899 rad/s = 1.257 Hz, damped) with no explanation. | "Body bounce / Wheel hop frequency (undamped)"; the docs explain the difference. | `speedBumpStaysOnTheRoad` |
| 4 | Teaching | Step 1 said "1.24 Hz is 7.8 rad/s" while the Modes tab, where it sends you, shows 7.9. | Explains that Modes includes the damping (7.9 rad/s, 1.26 Hz) and the Summary is undamped. | `TestLessons` |
| 5 | Teaching | At 40 km/h the healthy car's wheel leaves the road for 0.05 s, unmentioned while the status line warns. | Said in the step's result. | `TestLessons` |
| 6 | Teaching | "Both measures are best somewhere around 1000–1500 N·s/m, ζ about 0.2–0.3": comfort is best at 842 N·s/m (ζ 0.17), road holding at 1165 (ζ 0.24). | Both optima given, and why cars sit near 0.3. | reference only |
| 7 | Teaching | The worn-damper step implied that worn dampers are what lift the wheel at 40 km/h; the healthy car lifts too. | Compares them: 0.17 s against 0.05 s off the road, RMS tire load 0.42 against 0.22. | `TestLessons` |
| 8 | Teaching | "The Road line sits on the wheel-hop peak" (it is beside the marker, the tire peak is at 12.4 Hz); "barely disturb" was vague. | "Next to the wheel-hop marker, near the top of the peak"; at 30 km/h 5.6 Hz, a fifth of the tire-load swing. | `TestLessons` |
| 9 | Physics | `about()` and the docs wrote "F − m g" with m undefined. | W = (m_s + m_u) g, defined. | — |
| 10 | Inputs | Eight inputs (k_s, c_s, k_t, c_t, speed, road, duration, output step) had no tooltip. | Tooltips with typical values and meanings. | `inputsFitAndExplainThemselves` |
| 11 | Inputs | "Rough (ISO 8…" was cut off in its field, and "A (very good)" / "E (very poor)" would be. | "Rough (ISO)", "Kerb (step)", "A (v. good)", "E (v. poor)"; the tooltips spell them out. | `inputsFitAndExplainThemselves` |
| 12 | Behaviour | 600 s at a 10 µs output step (6·10⁷ samples) failed with "soften the tire and damper", which would not help. | More than 2 million samples is refused with a message about the output step; the step-count message names the road's features when they are the cause. | `testRejectsTooManySamples` |
| 13 | Analysis (shared) | The Bode resonance was the best point of a grid about 1 % apart: 1.182 Hz for 1.1893. | Refined by golden section between the grid's neighbours on the exact response, for every simulator; 151 tests of the six others pass. | `peakIsExactOnTheDefaultGrid` |
| 14 | Docs | The docs described an internal frequency response no one sees, did not say the RMS values cover the whole run (the flat road included) and are unweighted, or describe the export. | Rewritten. | — |

Accepted:
- **RMS over the whole run.** The flat road before a bump lowers the RMS values, so runs of
  different durations are not comparable; the docs and the duration's tooltip say so. A window
  around the feature would hide the after-ringing that the comparison is about.
- **Worn dampers, 4·10⁻⁴.** The fixed-step integrator crosses the lift-off kinks within a step;
  the difference to an adaptive solver is 0.04 % in the RMS and one 2 ms sample of air time.
- **The animation is a schematic:** the tire spring is drawn beside the wheel, and the wheel
  overlaps the road when the tire is compressed.
