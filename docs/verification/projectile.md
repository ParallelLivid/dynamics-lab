# Projectile Motion — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/projectile/index.html` (143 pictures, taken before and again after the
fixes; run `dlab.dev.captureVerification("projectile")` to make them again)

## Model as implemented

**Point mass** (`projectile_physics.m`, model `point`): x downrange, y up from the ground (y = 0),
θ above the horizontal (0–90°), launched from height h₀.

    x = v₀ cos θ · t,   y = h₀ + v₀ sin θ · t − g t² / 2

- Exact: samples every `dt`, the last one at the impact time t = (v₀ sin θ + √(v₀² sin²θ + 2 g h₀)) / g,
  where y is set to 0. Apex at t = v₀ sin θ / g (0 when launched level). Wind, density, and spin
  do not apply (their inputs are hidden).
- A launch from the ground that is not upward (h₀ = 0, θ = 0, or v₀ = 0) is not airborne: one
  sample, flight time 0.

**With drag** (model `sphere`): quadratic drag on the velocity relative to the air.

    dv/dt = g − (ρ(y) Cd A / 2m) |v − w(y)| (v − w(y)),   A = π r² (or the frontal area given)

- w is a horizontal wind (+ downrange), uniform or w·(max(y, 0.1 m) / 10 m)^(1/7) (the boundary
  layer); ρ is constant or `dlab.physics.atmosphere(site altitude + max(y, 0))` (the 1976
  standard, layers to 86 km, geometric altitude taken as geopotential).
- No buoyancy, no added mass, constant Cd, flat ground, uniform gravity.
- `ode45` (RelTol 1e-8, AbsTol 1e-10, MaxStep `dt`, Refine 1), or `ode15s` when
  (ρ Cd A / 2m)·max(v₀, 1)·dt > 1. Events: ground contact y = 0 descending (terminal; the launch
  contact from y = 0 is ignored), apex vy = 0 descending. The impact state is the event's, with
  y set to exactly 0. A 3600 s and 250 000-sample safety limit give readable errors.

**Spin** (with drag only): ω = (2π/60)(0, −sidespin, backspin) rad/s in (x, y, z), z to the right
looking downrange (x̂ × ŷ = ẑ: right-handed). The flight becomes 3-D:

    F_M = ½ ρ A C_L |v − w|² (ω̂ × û),   û = (v − w)/|v − w|
    C_L = 1.5 S (S < 0.1),  0.09 + 0.6 S (S ≥ 0.1),   S = r|ω| / |v − w|

- The fit is Sawicki, Hubbard and Stronge (Am. J. Phys. 71, 2003), checked: continuous at S = 0.1
  (0.15). r = √(A/π) when the size is an area. Spin rate constant (no decay). Without spin the
  2-D equations run unchanged (identical samples).
- Signs by the right-hand rule: backspin ω = +ẑ gives ẑ × x̂ = +ŷ (lift); topspin ω = −ẑ gives −ŷ (dip);
  sidespin +1 gives ω = −ŷ and −ŷ × x̂ = +ẑ (to the right).

**Optimal angle** (`optimalAngle.m`): point mass θ* = atan(v₀ / √(v₀² + 2 g h₀)),
R* = v₀ √(v₀² + 2 g h₀) / g (exact); with drag the range at 5°, 10°, …, 85°, then `fminbnd`
(golden section with parabolic steps) within ±5° of the best, TolX 0.01°. The plugin reuses the
search while only θ changes.

**Against the docs page and `about()`:** they match, with these gaps, now closed: neither said the
spin parameter uses the air-relative speed or how r follows from an area; `about()` did not say
"no buoyancy" while the air-density tooltip offered water (finding 11); the docs did not describe
the top view's orientation.

## Reference values

Independent of the engine and its tests: closed forms, the 1976 standard atmosphere computed
separately, and my own integrations in Python (SciPy DOP853 at RelTol = AbsTol = 1e-12 with my own
right-hand side, and a fixed-step RK4 for the short Magnus checks). g = 9.81 m/s². App values are
the Summary (all presets) and the engine's result.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Defaults (50 m/s, 45°): flight time, range, max height | 7.20802 s, 254.842 m, 63.7105 m (2v₀ sin θ / g, v₀² sin 2θ / g, v₀² sin²θ / 2g) | 7.20802, 254.842, 63.7105 | < 1e-9 | ✓ |
| Defaults: optimal angle | 45° (flat ground) | 45 | 0 | ✓ |
| Cliff launch (15° from 100 m): time, range, max height, impact speed | 6.02315 s, 290.896 m, 108.536 m, 66.7982 m/s (√(v₀² + 2gh₀)) | 6.02315, 290.896, 108.536, 66.7982 | < 1e-5 | ✓ |
| Cliff launch: optimal angle, its range | 36.8157°, 340.460 m (atan(v/√(v² + 2gh)), v√(v² + 2gh)/g) | 36.8157, 340.46 | < 1e-4 | ✓ |
| Moon (g = 1.62): time, range, height | 43.6486 s, 1543.21 m, 385.802 m | 43.6486, 1543.21, 385.802 | < 1e-4 | ✓ |
| Shot put (13.7 m/s, 37°, 2.1 m): range; optimum | 20.8496 m; 42.1619°, 21.1284 m | 20.8496; 42.1619, 21.1284 | < 1e-4 | ✓ |
| Drag example (60°): time, range, height, impact speed, angle | 7.88153 s, 152.292 m, 76.3164 m, 38.1718 m/s, −66.8417° (DOP853) | 7.88153, 152.292, 76.3164, 38.1718, −66.8417 | < 1e-5 | ✓ |
| Drag example: optimal angle, range | 42.3239°, 180.332 m (bounded search on my integration, 1e-4°) | 42.3249, 180.332 | 0.001° | ✓ (the search's 0.01° tolerance) |
| Terminal velocity, default ball | 65.8700 m/s (√(2mg / (ρ Cd A))) | — | — | ✓ |
| Dropped from 3000 m: time, impact speed | 50.19845 s, 65.86995 m/s ((v_t/g) arccosh(e^(gh/v_t²)), v_t √(1 − e^(−2gh/v_t²))) | 50.19845, 65.86995 | < 1e-6 | ✓ (99.9999 % of v_t) |
| Baseball (45 m/s, 35°, Cd 0.35): time, range, impact speed | 4.48293 s, 110.581 m, 26.1071 m/s | 4.48293, 110.581, 26.1071 | < 1e-5 | ✓ |
| Baseball: optimal angle | 39.9804° | 39.9792 | 0.001° | ✓ |
| ISA density at 0, 1, 1.609, 2, 5, 8, 11 km | 1.22500, 1.11164, 1.04665, 1.00649, 0.73612, 0.52517, 0.36392 kg/m³ (my own 1976 layers at geopotential altitude, which is what the 1976 table lists by geopotential height; by geometric height the table gives 1.1117, 1.0066, 0.73643, 0.52579, 0.36480) | the same to 5 digits | < 1e-5 | ✓ (geometric vs geopotential: finding 16) |
| Baseball in Denver (ISA, 1609 m): range; optimum | 117.438 m; 40.4984° (DOP853 with my ISA) | 117.438; 40.4992 | < 1e-3 | ✓ (6.1 % further than ISA sea level, 110.645 m) |
| Golf ball (70 m/s, 12°, Cd 0.25): range with wind −8, 0, +8 m/s | 117.678, 128.486, 139.100 m (relative velocity in the drag) | 117.678, 128.486, 139.100 | < 1e-5 | ✓ (headwind shorter, tailwind longer) |
| Golf into the headwind: wind drift; optimum | −10.808 m; 33.8970° | −10.8078; 33.8966 | < 1e-3 | ✓ |
| Golf, boundary-layer headwind −8 m/s: range | 118.797 m | 118.797 | 1e-5 | ✓ (calmer near the ground: less loss) |
| Magnus at launch, golf, 2800 rpm | S = 0.08943, C_L = 0.1341 (1.5 S), a = 12.56 m/s² up and back (⊥ v) | S 0.0894307, C_L 0.134146 | < 1e-6 | ✓ |
| Golf drive with backspin: position at 0.5 s | (31.5037, 6.3907) m (RK4) | (31.5036, 6.3907) | 1e-4 m | ✓ (linear interpolation between samples) |
| Golf with backspin: time, range, height; optimum | 5.82135 s, 216.596 m, 22.3592 m; 22.8952° | 5.82135, 216.596, 22.3592; 22.8947 | < 1e-3 | ✓ (vs 121.6 m without spin) |
| Curveball (−2000 rpm sidespin): z at 0.3 s | −0.20613 m (RK4; hand ½at² with a = 4.82 m/s²: −0.217) | −0.20618 | 5e-5 m | ✓ (to the left, as the sign says) |
| Curveball: range, lateral deflection, S, C_L | 22.2664 m, −1.00648 m, 0.21901, 0.22141 | 22.2664, −1.00648, 0.219014, 0.221408 | < 1e-5 | ✓ |
| Curveball +2000 rpm into a 5 m/s headwind: lateral; S at launch | +1.20206 m; S = 0.19164 (air-relative 39.99 m/s) | +1.20206; S 0.21901 before the fix, 0.19164 after | — | ✗ → fixed (finding 8) |
| Topspin tennis drive: time, range, height, impact speed | 0.646271 s, 16.1398 m, 1.43700 m, 21.8218 m/s | 0.646271, 16.1398, 1.437, 21.8218 | < 1e-5 | ✓ (dips: shorter than without spin) |
| Straight up (90°) | range 0 | 2.2e-14 m before the fix, 0 after | — | ✗ → fixed (finding 9) |
| Lesson: R at 50 m/s, 45° | 254.8 m | 254.842 | — | ✓ |
| Lesson: best angle with drag "about 42°", "about 42.3°"; ≥ 180 m within about ±1.9° of it | 42.32°, 180.33 m | 42.32 | — | ✓ |
| Lesson map with drag: best 232 m; ridge 45° at 10–30 m/s, 42.5° at 40–60 m/s (2.5° grid) | 232.44 m; true optima 44.9, 44.5, 43.9, 43.1, 42.3, 41.5° | 232.44 (in the lesson's check) | — | ✓ |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.001–0.87 s headless (the
longest, Baseball in Denver, includes the optimal-angle search with the standard atmosphere);
every Summary number reaches the metrics; every exported column has its units (5 columns, 7 with
sidespin) and no NaN or Inf; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass, before and after the fixes: every preset loads and runs; undo and redo; a
scenario round trip keeps every input; CSV (units on all 5 columns), MAT, plot, and report exports
(the report has every Summary row and 4 images); a 10-frame GIF; a sweep over v₀, a 2 × 2 map, a
6-sample Monte Carlo study, and a short optimization (flight time over v₀: 7.879 s at 54.66 m/s,
which is 2v₀ sin 45°/g at that speed), all without errors; no Modes tab (nothing to linearize);
theme and text-size switches keep the result. A run in the app takes 1–6 s (median 1.6 s), the
slowest being the drag presets whose optimal-angle search adds about 30 solves; the first run
pays MATLAB's plotting warm-up (K5).

### Tests

`tests/sims/projectile` (47, 12 of them new), `PluginConformanceTest` for the plugin (14),
`TestLessons` for both Projectile lessons (2), and `ArchitectureTest`: 73 passed, 0 failed, none
excluded. The core suites that drive the projectile (Analysis, EngineProgress, LessonWriter, Map,
MonteCarlo, OptimizePanel, Optimizer, RunReport, Scripting): 105 passed. `codeIssues` on the
simulator and its tests: 0. No shared code changed (only the `.gitignore` line of finding 17). The showcase image and thumbnails were made
again (`dlab.dev.generateImages(Ids="projectile")`).

## Checklist

- [x] Physics: equations, units, signs (right-hand rule for the spin), frames, assumptions match
  the docs page and `about()` (gaps closed: findings 8, 11, 13)
- [x] Numbers: defaults, every preset, and edge cases (90°, ground launch at 0°, a long drop to
  terminal velocity, headwind and tailwind, ISA from 0 to 11 km) against the reference values
- [x] Inputs: labels, units, ranges, tooltips, visibility rules (drag, air and spin inputs only
  with drag; radius or area; air density or site altitude; wind profile only with wind); presets
  load what they say (the Denver preset uses ISA at 1609 m; the curveball has only sidespin)
- [x] Outputs: every tab readable in both themes and at Larger text (143 screenshots, before and
  after the fixes); the readout agrees with the plots and the Summary at the same time (apex
  y = 63.71 m at 3.60 s in the defaults)
- [x] Summary and exports: Summary, plots, and CSV agree; units everywhere (z and vz exported
  with sidespin); the report is complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly; the optimal-angle search agrees
  with an independent search to 0.001°; no Modes or Bode (no equilibrium to linearize about)
- [x] Teaching: both Projectile lessons pass, and their statements and numbers agree with the
  reference values
- [x] Behaviour: readable errors (time and sample limits, no impact); Cancel stops the
  optimal-angle search (`testOptimalAngleSearchCanBeCancelled`) and the solver (progress
  callback); results survive theme and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Outputs | With wind, the "wind ← 8.0 m/s" label sat in the Trajectory's top-right corner, hidden behind the legend. | The wind is the readout's last line, "wind 8.0 m/s ← headwind" (or "→ tailwind"). | `windIsReadNotHiddenBehindTheLegend` |
| 2 | Outputs | The readout and legend overlapped the top of the arc (the defaults' apex at Larger text), and with equal axes a flat throw (curveball, tennis drive) was a thin strip with the readout written over the trajectory. | Head room: the y-limit is 1.35 × the highest arc, and with equal axes at least 0.3 × the x-limit. | `trajectoryLeavesRoomForTheReadout` |
| 3 | Outputs | The Top view was a mirror image: it plotted "to the right" upward with downrange to the right, which is the view from below; a ball curving left went down the screen. Its "straight line" (z = 0) lay on the axes' edge, its label hidden. | z points down the screen (a true view from above); padded limits keep the straight line inside. | `sidewaysFlightIsShownEverywhere` |
| 4 | Outputs | With sidespin, the Position and Velocity tabs and the readout showed no sideways motion (only the export and the Top view had z and vz). | z and vz curves and readout values whenever the flight leaves the vertical plane. | `sidewaysFlightIsShownEverywhere` |
| 5 | Outputs | The "Ground" label sat at the launch point, under the ball at the start. | At the right end of the ground line, beyond every landing point (the x-limit is 1.1 × the longest range). | — (layout) |
| 6 | Summary | The Units column held explanations: "deg (below horizontal < 0)", "m (+ right)", "rω/v", which the Sweep, Map and report use as units. | Units only ("deg", "m", none); the sign goes in the name, "Lateral deflection (+ to the right)", "Spin parameter S = rω/v at launch". | `summaryUnitsAreUnits` |
| 7 | Summary | "Maximum speed" ignored the sideways velocity that "Impact speed" includes (a curveball dropped from a height reported a maximum below its impact speed). | Both use |v| in 3-D. | `maximumSpeedCountsSidewaysMotion` |
| 8 | Physics | The Summary's spin parameter and lift coefficient at launch used the launch speed, while the engine uses the speed relative to the air: into a 5 m/s headwind S read 0.219 instead of 0.192. | The engine returns S and C_L at launch from the air-relative speed; the plugin's copy of the fit is gone. | `testSpinParameterUsesTheAirRelativeSpeed` |
| 9 | Numbers | Straight up (θ = 90°) gave a range of 2.2e-14 m (cos(π/2) is not 0 in floating point), shown as "2.2e-14". | `cosd`/`sind`: exactly 0. | `testVerticalLaunchLandsWhereItStarted` |
| 10 | Inputs | Three choice lists were cut off in the 118 px field at normal text size: "Sphere with d…", "Standard atm…", "Same at ever…" / "Stronger wi…". | "With drag", "Standard (ISA)", "Uniform" / "Boundary layer", with tooltips that explain them; lessons and docs follow. | — (layout) |
| 11 | Inputs | The air-density tooltip offered "water ≈ 1000", but buoyancy is not modelled (for the default 1 kg, 5 cm ball it would be half its weight); `about()` did not list the assumption. | Tooltip: buoyancy is not modelled, so not for water; `about()` adds "no buoyancy"; the docs page says so. | — (wording) |
| 12 | Teaching | Both lessons called the default ball "a 5 cm, 1 kg ball"; 5 cm is its radius (10 cm across). | "a sphere of 5 cm radius and 1 kg". | `TestLessons` |
| 13 | Docs | The docs page did not say how r follows from a frontal area, how ω̂ × v̂ scales for sidespin, that the atmosphere takes altitude as geopotential, the terminal velocity, or the top view's orientation, and had no reference rows for wind, ISA, the long drop, or the Magnus force. | Added, each reference row asserted by a new test. | the new physics tests |
| 14 | Docs | `about()` called the drag search "golden-section refinement"; it is `fminbnd` (golden section with parabolic steps). | Reworded. | — (wording) |
| 15 | Physics | The curveball preset breaks 1.0 m over 22 m, more than a typical pitch (about 0.3–0.5 m over 17 m): the baseball C_L fit at S = 0.22 and spin that is all sidespin (no gyro component). | Accepted: the model is as documented and cited; the preset shows the effect clearly. | — |
| 16 | Physics | `dlab.physics.atmosphere` takes geometric altitude as geopotential: density 0.005 % low at Denver, 0.12 % at 8 km, 0.24 % at 11 km. | Accepted: shared code, documented there, negligible for a projectile. | — |
| 17 | Repository | `.gitignore`'s `verification/` (for the screenshots) also matched `docs/verification/`, so none of the verification sheets would be committed. | `/verification/`: only the screenshots folder at the root. | — |
