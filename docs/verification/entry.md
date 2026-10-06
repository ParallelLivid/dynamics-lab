# Atmospheric Entry — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/entry/index.html` (156 pictures, after the fixes; the fixes changed no
picture; run `dlab.dev.captureVerification("entry")` to make them again)

## Model as implemented

**Engine** (`simulateEntry.m`): planar flight over a spherical, non-rotating Earth (μ and R from
`dlab.physics.bodyConstants`: 398 600.4418 km³/s², 6371 km). States h, V, γ, downrange s, the heat
load and the drag work:

- dV/dt = −D/m − g sin γ; V dγ/dt = L/m − (g − V²/r) cos γ; dh/dt = V sin γ; ds/dt = (R/r) V cos γ
  (the textbook planar equations, Vinh), with D/m = ρV²/(2β), L/m = (L/D)(D/m) cos σ, g = μ/r².
- Sutton–Graves q̇ = 1.7415·10⁻⁴ √(ρ/r_n) V³ W/m² (the published constant for Earth air).
- The load |L + D|/m = (D/m) √(1 + (L/D)²), in g₀.
- Atmosphere: the standard one is `dlab.physics.thermosphereDensity` (Vallado's exponential bands
  of CIRA-72); the exponential one 1.225 e^(−h/H). The speed of sound for the parachute Mach
  number is the ISA's (extended above 86 km).
- Stops: the ground, the parachute Mach number (crossing downward), a skip-out (climbing back
  through the entry altitude + 1 m), the time limit. `ode45`, RelTol 10⁻⁹.
- Peaks refined by a parabola through three samples; the energy V²/2 − μ/r plus the drag work is
  conserved (lift does no work), which I checked: it closes to 10⁻⁹ of the entry kinetic energy in
  every case below.

**Against the docs page and `about()`:** they match.

## Reference values

Independent of the engine: my own integration (scipy DOP853, RelTol 10⁻¹¹) of the same planar
equations, with Vallado's Table 8-4 (CIRA-72) written out from the book, my own ISA for the speed
of sound, and Allen and Eggers' closed form. Matching to every digit also confirms the engine's
density table.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Apollo-like lunar return (default: 11 km/s, −6.5°, β 350, L/D 0.3, lift up then 90° at 80 s) | 7.01721 g at 56.374 km; q̇ 169.428 W/cm² at 57.843 km; heat load 14.8675 kJ/cm²; q 23.0696 kPa; chute at 307.858 s, 14.638 km, 236.056 m/s; 1814.52 km downrange | 7.017205 at 56.3743; 169.4277 at 57.84301; 14.86749; 23.06958; 307.8582 s, 14.63817 km, 236.0556 m/s; 1814.524 | 0 | ✓ |
| Soyuz-like ballistic (7.6 km/s, −1.5°, β 400) | 9.44861 g at 37.121 km; 90.5872 W/cm²; 9.62382 kJ/cm²; 37.0637 kPa; 379.92 s; 2174.32 km. Allen–Eggers 3.93884 g | 9.448606 at 37.12117; 90.58725; 9.62382; 37.06367; 379.9202; 2174.316; 3.938842 | 0 | ✓ |
| Steep ballistic (−15°) | 42.5877 g at 30.643 km; 222.552 W/cm²; 4.10117 kJ/cm²; 167.057 kPa; 93.7719 s; Allen–Eggers 38.9445 g | 42.5875 at 30.64007; 222.5555; 4.10117; 167.0563; 93.77194; 38.94447 | 5·10⁻⁶ (peak refinement) | ✓ |
| Allen–Eggers preset (exponential, 7.5 km/s, −20°, β 300) | 52.479 g at 31.874 km (formula 50.1183 g: the difference is gravity); 321.613 W/cm²; 154.393 kPa; 74.056 s | 52.47902 at 31.87371; 321.6129; 154.393; 74.05598; 50.11833 | 0 | ✓ |
| Shallow skip-out (−4.5°, lift up) | skips at 184.268 s at 10 801.2 m/s; peak 0.346603 g at 80.0 km | 184.2683 s, 10 801.24 m/s; 0.3465913 at 79.99867 | 0 | ✓ |
| Corridor: too shallow (−5.6°) | skips at 398.5 s at 7993.63 m/s; 3.33629 g | 398.4997, 7993.627; 3.336292 | 0 | ✓ |
| Corridor: too steep (−7.4°) | 11.4803 g at 51.409 km; 203.587 W/cm²; 13.5233 kJ/cm² | 11.48025 at 51.40994; 203.587; 13.52329 | 0 | ✓ |
| The corridor's edges (lesson) | −5.5° skips at 8585.5 m/s; −5.6° skips; −5.7° stays in (8.768 g, heat load 21.707 kJ/cm², 547 s); −7.1° 9.961 g; −7.2° 10.465 g | the same to every digit shown | 0 | ✓ (finding 4) |
| Lesson numbers | −40°: 97.73 g (formula 94.19, "close to a hundred"); Soyuz with L/D 0.3: 2.863 g ("about 3 g instead of 9"), heat load 13.84 > 9.62, 3182 km > 2174; corridor −5.7° to −7.1°, "about 1.4° wide" | 97.72827; 2.862634, 13.83967, 3181.505; as stated | 0 | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.1 s headless; every Summary number
reaches the metrics; every exported column has its units (the Mach number dimensionless); no
non-finite values; a second solve gives the identical result. Halving the output step changes
nothing beyond the sixth digit (the peaks are refined between samples): 7.01721 g at 0.05 s
against 7.017205 at 0.5 s.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 9.3 s, the first run while MATLAB warms up;
median 2.5 s); undo and redo of the entry speed; a scenario round trip; CSV, MAT, plot and report
exports (7 images); a 10-frame GIF; a sweep of the entry speed (12 results); a map of entry speed
and angle; uncertainty; a short optimization of the peak deceleration over the entry speed;
theme and text-size switches keep the result. (No Modes tab: an entry has no equilibrium.)

### Tests

`tests/sims/entry` (new: `inputsFitAndExplainThemselves`, `skipOutStartsShallowerThanMinus5Point6`,
which also checks the corridor's shallow edge), `PluginConformanceTest` for `EntryPlugin`,
`TestLessons` for its lesson, and `ArchitectureTest`, run together with the attitude tests: 80
passed, 0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: the equations, the heating constant, the load, the stops, and the energy balance
  checked by hand; the docs and `about()` match
- [x] Numbers: every preset and the corridor's edges against my own integration, to every digit
  shown; the Allen–Eggers estimate by hand
- [x] Inputs: labels, units, ranges; the atmosphere choices fit and every input has a tooltip
  (finding 2); the scale height shows only for the exponential atmosphere
- [x] Outputs: every tab of every preset in both themes and at Larger text; the animation's
  readout agrees with the plots; the Allen–Eggers curve and line where they apply
- [x] Summary and exports: units in the units column, "Skipped out" in words (finding 1)
- [x] Analysis: Sweep, Map, Optimize and Uncertainty on the entry speed and angle give smooth,
  sensible results
- [x] Teaching: every number checked; two statements corrected (findings 3 and 4)
- [x] Behaviour: readable errors (a climbing entry, negative L/D, bad atmosphere); skip-out,
  parachute and ground end the run with a note

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | "Skipped out" had "yes = 1" in the units column. | No units; the value reads "yes" or "no". | `skipOutStartsShallowerThanMinus5Point6` |
| 2 | Inputs | The atmosphere choices were cut off ("Standard (CIRA-72 bands)", "Exponential ρ₀ e^(−h/H)"), and four inputs had no tooltip. | "Standard" / "Exponential", explained in the tooltip; tooltips added. | `inputsFitAndExplainThemselves` |
| 3 | Teaching | The skip-out step said "make the entry angle shallower than −6°" and "skipped out: still near 10 km/s". With the lesson's bank schedule −5.7° to −6° stay in, −5.6° is the first to skip, and −5.5° leaves at 8.6 km/s. (Corrected earlier the same day to "shallower than −5.6°", which still excluded −5.6° itself.) | "−5.6° or shallower (try −5.5°)"; "back above the entry altitude still at 8.6 km/s". | `skipOutStartsShallowerThanMinus5Point6`, `TestLessons` |
| 4 | Teaching | The corridor step said "near its shallow edge the peak g is low": at −5.7° it is 8.8 g against 7.0 g at −6.5°, because the capsule climbs back toward space and then falls in steeply once its lift is rolled away. | "the peak is not gentle either … (about 9 g at −5.7°, against 7 g at −6.5°)"; the long flight and highest heat load stay. | `skipOutStartsShallowerThanMinus5Point6` |

Accepted:
- **The ballistic estimate for the standard atmosphere uses the scale height input** (7.2 km by
  default), which is hidden unless the exponential atmosphere is chosen. The docs say the row is
  the Allen–Eggers formula with H and only an estimate (Soyuz: 9.4 g against 3.9 g); putting H
  in the row's name would make the metric's name change with an input.
- **Labels on the Altitude–velocity map** for peak g and peak heating sit close together when the
  two peaks coincide (the shallow skip-out); they stack above and below the point and stay
  readable.
