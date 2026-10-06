# Rocket Ascent — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/rocket/index.html` (168 pictures, taken after findings 1–5 and before
7–9; `after-*.png` after those: the heavy launcher's trajectory, "Too shallow"'s dynamic pressure,
and the sounding rocket's orbit, trajectory and acceleration; the default at Larger text in the
light theme; run `dlab.dev.captureVerification("rocket")` to make them
again)

## Model as implemented

**Engine** (`simulateAscent.m`): planar flight in an inertial frame with the Earth's centre at
the origin and the pad at (0, R), R = 6371 km, μ = 3.986004418·10¹⁴ m³/s². States: position,
velocity, mass, and four running integrals (gravity, drag and steering losses, and ∫ T/m dt).

- Gravity −μ r/|r|³. Thrust T = throttle·T_vac − p(h)·A_e with A_e = T_vac (1 − Isp_sl/Isp_vac)/p₀,
  so that full throttle at sea level gives T_vac Isp_sl/Isp_vac; ṁ = throttle·T_vac/(g₀ Isp_vac).
- Drag ½ρ|v_air| v_air C_d(M) A, against the air-relative velocity v_air = v − ω×r. The Earth turns
  clockwise in this frame (the pad moves along +x), so ω×r = ω(y, −x) and v_air = (vx − ωy, vy + ωx),
  as coded; ω = 7.2921150·10⁻⁵ cos(latitude), the component of the Earth's spin normal to the
  plane of a due-east launch, which is exact for that plane. The out-of-plane wind is neglected
  (stated: planar).
- C_d(M): 0.30 subsonic, 0.45 at Mach 1, 0.60 at 1.2, falling to 0.22 at Mach 10, times the drag
  scale. Atmosphere `dlab.physics.atmosphere` (ISA, extended above 86 km).
- Guidance: vertical to the pitch-over altitude, a 5 s linear pitch-over to the kick angle, then
  thrust along v_air (gravity turn); past the top of a suborbital arc, thrust horizontally. Upper
  stages with a finite target control their climb rate (pitch from the vertical acceleration
  needed, limited to −0.3…0.95 of the thrust acceleration). A pitch program overrides both.
- Δv budget along v̂: d|v|/dt = (T/m) t̂·v̂ + g·v̂ + (D/m)·v̂, so ∫ T/m dt = Δ|v| + gravity + drag +
  steering losses exactly; Tsiolkovsky minus ∫ T/m dt is the back-pressure loss. I derived this
  and it is what the code integrates.
- Events: burnout (mass reaches the stage's empty mass), impact (h = −1 m), cutoff (apoapsis, or
  under the climb guidance the semi-major axis, reaches the target), the pitch-over, and the
  apoapsis (r·v crossing zero downward) after a cutoff. The circularization is an impulsive burn to
  √(μ/r) along the horizontal, limited by the propellant left.
- `ode45`, RelTol 10⁻⁹, AbsTol 10⁻⁶, MaxStep max(dt, 0.05 s).

**Against the docs page and `about()`:** they match (the time limit and the acceleration row
were updated with findings 3 and 1).

## Reference values

Independent of the engine: my own vertical flight of the sounding rocket (scipy, RelTol 10⁻¹⁰,
with the ISA written out and the same C_d table), Tsiolkovsky by hand, two-body Kepler for the
coast, and published Saturn V figures for the heavy preset.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Sounding rocket (vertical, 1600 → 400 kg, Isp 260/230 s, 60 kN) | Tsiolkovsky 3534.67 m/s; burn 50.995 s; burnout 46.8178 km at 2668.50 m/s; gravity loss 498.702 m/s; apogee 434.98 km at 348.5 s; max-Q 130.7 kPa at 10.35 km (27.6 s); at burnout (59 992 N − 237 N drag)/400 kg = 15.2334 g | 3534.675; 50.995; 46.8178 at 2668.501; 498.7016; 434.9804; 130.6927 at 10.26 km (27.5 s: the 0.5 s sample); 15.2334 g (was 60.93) | 0 (max-Q: sampling) | ✓ (finding 1) |
| Small launcher (default), Tsiolkovsky | 533 t at lift-off (payload fraction 2.814 %); stage 1 4233.74 m/s; stage 2 6023.75 m/s if burnt out | 2.814259 %; 4233.74; 5504.44 at cutoff (it keeps 18 t for the circularization) | 0 | ✓ |
| … orbit | cutoff state r = (2046.0, 6243.4) km, v = (7405.5, −2415.9) m/s: a 6571.0 km (the 200 km circle's energy), e 0.0013474, apoapsis 208.854 km, reached 1414.8 s later at t = 1999.88 s; circular speed there 7783.25 m/s | apoapsis event at 1999.877 s at 208.854 km; circularized to 208.854 × 208.854 km, 7783.25 m/s | 0 | ✓ |
| … with the Earth's rotation | ω R cos 28.5° = 408.281 m/s | 408.2814 | 0 | ✓ |
| Δv budget (every preset and the extra cases) | ∫ T/m dt = Δ|v| + the three losses | closes to 7·10⁻⁹ m/s or better | — | ✓ |
| Heavy (Saturn V-like) | five F-1s: 7770 kN vacuum each (38 850 kN), Isp 263/304 s; J-2s of about 1033 kN vacuum (S-II 5 × 1033, S-IVB 1033), Isp 421 s; lift-off 2934 t, T/W 1.16 (Saturn V: about 1.15); S-IC cutoff at about 67 km and 162 s, near 2.4 km/s relative to the Earth (Apollo 11, approximately); parking orbit 185 km | 38 700 kN, 263/304; 5100, 1000 kN, 421; 2934 t; stage 1 burnout 2.48 km/s at 74 km at 166 s; 185 × 188 km before the fix, 188 km circular after it | approximate, as named | ✓ (finding 3) |
| One stage only (the lesson) | the first stage carries 400 of 492 t of propellant | no orbit (perigee −4343 km) | — | ✓ (finding 5: "nearly all") |
| Max-Q, kick 5°, full throttle; with the bucket | — | 37.45 kPa; bucket 23.06 kPa (−38 %), still in orbit | — | ✓ lesson "37 kPa", "about 40 %" |
| Lesson numbers | 9.81 × 260 × ln 4 = 3535; about 9.8 m/s of gravity loss per second of vertical climb (498.7/51.0 = 9.78); max-Q about 11 km, a minute in | 3534.7; 11.04 km at 62 s | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 2.2 s headless; every Summary number
reaches the metrics; every exported column has its units; no non-finite values; a second solve
gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 13.2 s, the first run while MATLAB warms
up; median 6.1 s); undo and redo of the payload; a scenario round trip; CSV (10 columns, the Mach
number dimensionless), MAT, plot and report exports (9 images); a 10-frame GIF; a sweep of the
payload (19 results); a map of payload and diameter; uncertainty; a short optimization of max-Q
over the payload; theme and text-size switches keep the result. (No Modes tab: the ascent has no
equilibrium.)

### Tests

`tests/sims/rocket` (new: `testBurnoutKeepsTheBurningMass`, `testCoastGoesOnToTheApoapsis`,
`maxQMarkersFollowTheClimb`, `eventLabelsDoNotOverlap`; extended: `throttleBucket`,
`soundingRocketMatchesAVerticalFlight`), `PluginConformanceTest` for `RocketPlugin`, `TestLessons`
for its lesson, and `ArchitectureTest`: 41 passed, 0 failed. None excluded. `codeIssues` on every
touched file: 0.

## Checklist

- [x] Physics: the equations, the air-relative velocity's sign for this frame, the nozzle
  back-pressure, the budget identity, the events, and the circularization checked by hand
- [x] Numbers: the sounding rocket against my own flight to every digit shown; Tsiolkovsky, the
  coast to the apoapsis, the rotation gain by hand; the heavy preset against Saturn V
- [x] Inputs: labels, units, ranges, tooltips on every input
- [x] Outputs: every tab of every preset in both themes and at Larger text; the animation's
  readout agrees with the plots; overlapping and clipped event labels fixed (finding 7); the orbit
  tab after an impact (finding 8)
- [x] Summary and exports: units everywhere; the acceleration and max-Q rows say what they cover
- [x] Analysis: Sweep, Map, Optimize and Uncertainty on the payload and diameter give smooth,
  sensible results (max-Q rises slowly with payload: a heavier rocket climbs more slowly)
- [x] Teaching: every lesson number checked; one wording corrected (finding 5)
- [x] Behaviour: readable errors (bad stages); impact, cutoff and time limit end the run with a note

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | "Max acceleration" was wrong in every preset: at each burnout the sample was recomputed with the stage still thrusting but its dry mass already gone (the sounding rocket: 60 kN on the 100 kg payload, 60.9 g, against 15.23 g). | The engine keeps the last burning sample and adds the separated one at the same time. | `testBurnoutKeepsTheBurningMass`, `soundingRocketMatchesAVerticalFlight` |
| 2 | Summary | Flights that fall back reported their re-entry as the ascent's largest acceleration (13.9 g on the way down for "Too steep"; a climb-only window would have missed "Too shallow"'s stage-1 burnout, after its highest point). | "Max acceleration under thrust": the largest sensed acceleration while an engine burns. | `soundingRocketMatchesAVerticalFlight` |
| 3 | Behaviour | "Circularize at the apoapsis" silently did nothing when the apoapsis came after the time limit: the throttle-bucket and heavy presets stayed in 163 × 237 and 182 × 188 km orbits (the default made it with 0.12 s to spare). | After a cutoff the coast always goes on to the apoapsis (at most one orbit); the tooltip and docs say so. | `testCoastGoesOnToTheApoapsis`, `throttleBucket` |
| 4 | Outputs | The Trajectory and Dynamic-pressure tabs marked the whole flight's max-Q (496 kPa on the sounding rocket's fall), while the Summary gave the climb's (130.7 kPa). | The plots mark the Summary's point. | `maxQMarkersFollowTheClimb`, `throttleBucket` |
| 5 | Teaching | "even though it has nearly all the propellant": the first stage has 400 of 492 t. | "most of the propellant (400 of 492 t)". | `TestLessons` |
| 6 | Inputs | (Earlier the same day) six inputs had no tooltip. | Tooltips. | `inputsExplainThemselves` |
| 7 | Outputs | On the Trajectory tab, events a few seconds apart printed over each other ("Stage 2 burnout" on "Stage 3 ignition", "Apoapsis" on "Circularization burn"), the last label ran off the right edge, and "Max-Q" sat on "Stage 1 ignition" for the vertical flight. | Events within 5 s, or at the same point of the plot (a vertical flight lands where it took off), share one label ("Stage 2 burnout, stage 3 ignition", "Stage 1 ignition, impact"); labels near the right edge go to the left; "Max-Q" is labelled on the left. | `eventLabelsDoNotOverlap` |
| 8 | Outputs | After an impact the Orbit tab said "Perigee −6371 km, apogee 2 km" and drew the conic of the state at the ground (the Summary already hid them). | "No orbit: it fell back to the ground", no conic. | `maxQMarkersFollowTheClimb` |
| 9 | Summary | The climb-only max-Q (a rule added earlier the same day, before this sheet) stopped at the highest point even when the engine was still burning: "Too shallow" reported 129 kPa at the top while its plot rose to 1 MPa in the powered dive. | Max-Q up to the highest point or the last engine burn, whichever is later. | `maxQMarkersFollowTheClimb` |

Accepted:
- **Planar, due-east launch**: the out-of-plane wind of the Earth's rotation and the change of
  inclination are left out, as the docs say.
- **"Burn everything" with the default launcher crashes** at 8.8 km/s: its second stage, flying a
  gravity turn with T/W 0.64, passes its top at 226 km and is still thrusting horizontally on the
  way down; at burnout (100 km, −5.1°) its perigee is 19 km below the surface. Physically right
  for that guidance, which is why the presets use the climb control.
