# Gravity Assist — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/flyby/index.html` (before the fixes; run
`dlab.dev.captureVerification("flyby")` to make them again)

## Model as implemented

**Planet frame** (`simulateFlyby.m`): the hyperbola with e = 1 + r_p v∞²/μ, |a| = μ/v∞², turning
angle δ = 2 asin(1/e), impact parameter b = r_p √(1 + 2μ/(r_p v∞²)), started on the analytic
hyperbola (hyperbolic Kepler equation solved by Newton's method) and integrated with `ode113`
(RelTol 10⁻¹²) through periapsis. The measured turn uses each end's osculating asymptote, so the
finite start distance adds no bias. The side ("behind" or "ahead") picks the rotation sense
whose Δv points along or against the planet's motion.

**Sun frame (patched conic):** the planet on a circular orbit at V_p = √(μ_Sun/a), at (0, −a)
moving along +x; heliocentric velocities V_p + v∞ before and after; heliocentric orbits from
vis-viva and the eccentricity vector. The energy change equals V_p·Δv, which I derived (|v∞| is
the same before and after).

**Constants** (`planetData.m`, from `bodyConstants`): μ, radii and semi-major axes checked against
the NASA fact sheets; the circular speed agrees with the tabulated mean speed within 1.1 %
(Mercury) as documented. The AU is the IAU 2012 value.

**Against the docs page and `about()`:** they match.

## Reference values

Independent of the engine: the hyperbola and the patched conic written out from the textbook
formulas (the turned v∞ chosen by the sign of its component along V_p, the heliocentric orbit from
its own vis-viva and eccentricity).

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Jupiter, v∞ 10.7 km/s at −120°, 277 400 km, behind (Voyager 1-like) | e 1.315303, δ 98.977968°, Δv 16.2700 km/s, v_p 28.9950; heliocentric 12.0524 → 23.3620 (+11.3096) km/s; ΔE +200.261; perihelion–aphelion 1.0216–8.0449 AU → 5.1011 AU, e 2.1778 (unbound) | 1.315303, 98.97797 (integrated 98.97797), 16.27002, 28.99504; 12.05239 → 23.36198 (+11.30959); +200.261; 1.021594–8.044936 → 5.101116, 2.177798; planet-frame speed change −1.2·10⁻¹¹ km/s | 0 | ✓ |
| Venus, 6.6 km/s at −77°, 284 km, behind (Cassini-like) | δ 65.458332°, Δv 7.1368; 37.0673 → 41.5080 (+4.4408); 0.6495–0.9950 → 0.7221–1.7086 AU | 65.45833, 7.136826; 37.06726 → 41.50803; 0.6495148–0.995011 → 0.7220705–1.70858 | 0 | ✓ |
| Earth, 8.8 km/s at −100°, 960 km (Galileo-like) | δ 48.723474°, Δv 7.2599; 29.5557 → 35.9513; aphelion 1.2741 → 2.7391 AU | 48.72347, 7.259933; 29.55569 → 35.95126; 1.274071 → 2.739114 | 0 | ✓ |
| Venus, ahead | −7.0097 km/s; ΔE −235.264; 0.4046–0.7405 AU | −7.009737; −235.2636; 0.4046383–0.7404763 | 0 | ✓ |
| Close Jupiter pass, 6.6 km/s at −148°, 4000 km | e 1.025957, δ 154.168353°, Δv 12.8660; 8.2388 → 19.6313 km/s, unbound | 1.025957, 154.1684, 12.86603; 8.238759 → 19.63127 | 0 | ✓ |
| Mars, 4.2 km/s at −125°, 300 km | δ 46.767190°, Δv 3.3338; 21.9903 → 25.3211 km/s; 1.0046–1.6015 → 1.3722–2.0189 AU | 46.76719, 3.333835; 21.99027 → 25.32109; 1.004599–1.601548 → 1.372238–2.018853 | 0 | ✓ |
| Spheres of influence | a (μ/μ_Sun)^(2/5): Jupiter 4.821·10⁷, Venus 6.163·10⁵, Earth 9.246·10⁵, Mars 5.773·10⁵ km | the same | 0 | ✓ |
| Lesson numbers | 277 000 km; zero speed change; 12.05 → 23.36, past the 18.5 km/s escape speed (√2 · 13.06); over 125° at 50 000 km (128.6°); 0.70–1.27 → 2.74 AU; Jupiter slows by 722 kg × 15.34 km/s / 1.898·10²⁷ kg = 5.8·10⁻²¹ m/s | the lesson said "about 10⁻²¹" | — | ✗ → ✓ (finding 2) |

## Automatic checks

From `captureVerification`: every preset solves in under 0.1 s headless; every Summary number
reaches the metrics; every exported column has its units; no non-finite values (an unbound
aphelion is shown as "unbound: leaves the Sun"); a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs; undo; a scenario round trip; the exports and the
report; a GIF; Sweep, Map, Uncertainty and a short optimization; theme and text-size switches
keep the result.

### Tests

`tests/sims/flyby` (new: `inputsFitAndExplainThemselves`; `displayOptions` now changes the
display during playback), `PluginConformanceTest` for `FlybyPlugin`, `TestLessons` for its lesson,
and `ArchitectureTest`: all pass, together with the three-body and attractor tests (108 passed,
0 failed). None excluded. `codeIssues` on every touched file: 0. After the shared fix (finding 3)
the whole suite was run (`buildtool ptest`): 1401 tests, 0 failed, 0 errors.

## Checklist

- [x] Physics: the hyperbola, the measured turn, the side, the patched conic and ΔE = V_p·Δv
  checked by hand; docs and `about()` match
- [x] Numbers: every preset against my own patched conic, to every digit shown
- [x] Inputs: labels, units, ranges, tooltips (added for two, finding 1)
- [x] Outputs: every tab readable in both themes and at Larger text; the velocity diagram and the
  asymptotes agree with the numbers
- [x] Summary and exports: units everywhere; an unbound orbit is said in words
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on v∞ and the altitude
- [x] Teaching: every lesson number checked; one corrected (finding 2)
- [x] Behaviour: readable errors (periapsis outside the sphere of influence, negative altitude);
  the "either side loses speed" warning; nothing left behind; display options during playback
  (finding 3)

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Inputs | The pass choices were cut off ("Behind the pl…", "Ahead of the …"), and the planet and the inset had no tooltip. | "Behind" / "Ahead", with gaining and losing speed in the tooltip; tooltips added. | `inputsFitAndExplainThemselves` |
| 2 | Teaching | "Jupiter pays with the same momentum, which slows it by about 10⁻²¹ m/s": for Voyager's 722 kg it is 5.8·10⁻²¹ m/s (722 kg × 15.34 km/s along Jupiter's motion / 1.898·10²⁷ kg), nearer 10⁻²⁰. | "for Voyager's 722 kg it slows by about 6 × 10⁻²¹ m/s". | `TestLessons` |
| 3 | Behaviour (shared) | Changing a display option (sphere of influence, inset) while the animation played gave dozens of "Invalid or deleted object" warnings: the playback timer fired inside the plugin's `plot` calls while it rebuilt the animation, and drew on the handles it had just deleted. Every simulator whose display options redraw the animation could do this. | `SimulatorView` draws no frames while a plugin's `showResult` runs (`showPluginResult`). | `displayOptions` (six display changes during playback: 542 warnings without the fix, none with it) |

Accepted:
- **The planet's orbit is a circle** at the semi-major axis (within 1.1 % of the mean speed, as
  documented), and the flyby is planar.
