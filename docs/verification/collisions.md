# Billiards and Gas Collisions — verification

Status: **verified** (3 October 2026)
Screenshots: `verification/collisions/index.html` (141 pictures before the fixes and 127 (fewer tabs: the gas statistics only for a gas) after;
run `dlab.dev.captureVerification("collisions")` to make them again)

## Model as implemented

**Engine** (`simulateCollisions.m`): N smooth hard discs (no friction, no spin) of radius r_i and
mass m_i in a W × H box with its corner at the origin, SI units. Event-driven, no time step:

- **Prediction.** For disc i and each other disc j, with Δr = r_j − r_i, Δv = v_j − v_i,
  σ = r_i + r_j, b = Δr·Δv: if b < 0 and b² − |Δv|² (|Δr|² − σ²) ≥ 0, contact at
  t = (−b − √disc) / |Δv|² (clamped at 0). Walls: the linear time until x = r_i or W − r_i (and
  y). Periodic: the nearest image and its eight neighbours (since this round in one vectorised
  step; the same numbers), and crossing an edge is an event that moves the disc to the other
  side. Each disc caches its earliest event and partner; after an event the involved discs and
  every disc whose partner was one of them are predicted again (a disc that would now meet an
  involved disc earlier is found by the involved disc's own prediction).
- **Collision.** Normal n̂ along the line of centres, approach speed u = (v_i − v_j)·n̂ > 0,
  impulse J = (1 + e) μ u with μ = m_i m_j / (m_i + m_j); v_i −= J n̂ / m_i, v_j += J n̂ / m_j.
  Approaches slower than 10⁻⁶ of the starting RMS speed are elastic (guard against inelastic
  collapse). Wall: v_n → −e_w v_n, impulse m (1 + e_w) |v_n|, summed for the pressure.
- **Samples** are taken between events at the output step by straight-line motion; the run stops
  at the event limit (default 200 000) with a warning. Recorded: x, y, vx, vy, KE = ½ Σ m v²,
  |P|, the event log (time, i, j or wall code, J), the wall impulse, and (new) the velocities just
  after the first disc–disc collision.

**Starts** (`initialState.m`): billiards (16 balls, the rack's apex at 0.72 W, 0.001 r gaps; cue
at 0.25 W; a real 8-ft table 2.24 × 1.12 m and 57.15 mm, 0.17 kg balls in the preset); two balls
(the target offset by Off-centre × r across the motion); a cradle (five balls 2r(1 + 10⁻⁹) apart,
the first 6r back); a gas in shuffled grid cells with random directions, all speeds v0 or
Rayleigh speeds (since this round scaled so that mean v² = v0² exactly); an optional tracer at the
centre.

**Analysis** (plugin): kT = mean ½ m v² per gas disc over the second half (2-D equipartition);
KS distance of the pooled second-half speeds from the 2-D Maxwell–Boltzmann
f(v) = (m v / kT) e^(−m v²/2kT); packing η = Σ π r² / (W H); ideal N kT / (W H); Henderson
Z = (1 + η²/8)/(1 − η)²; measured pressure = wall impulse / (2 (W + H) × time) (since this round
over the second half); the tracer's time-averaged MSD (since this round up to T/8, relative to the
centre of mass in a periodic box, D from a line 4 D t + c over the later half of the lags).

**Against the docs page and `about()`:** the equations, the impulse, the guard and the outputs
matched. Not stated before (now in the docs): no friction or pockets, where the rack and cue
stand, what the off-centre hit measures, that the "jittered grid" is jittered only by the room a
cell leaves (0.6 mm for the defaults), the pressure's finite-box offset, the diffusion
coefficient's uncertainty. `about()` claimed MSD = 4 D t without "at long times" and "with no
walls" (finding 3).

## Reference values

Independent of the engine and its tests: closed forms; Henderson (1975) for the hard-disc
equation of state; the Enskog collision frequency; Haff's law; kinetic theory for the Brownian
friction; and **my own event-driven simulation in Python** (a full pair-time matrix with the
numerically stable root c / (−b + √disc), collisions applied in the centre-of-mass frame by
reversing the normal components; nothing shared with the engine). I also **replayed every event
log** of the app (all presets, a periodic gas and an elastic break): from the app's own state at
each sample I move the discs to each logged event, check that the pair touches (or the disc the
wall), that no pair comes closer than r_i + r_j in between (the analytic minimum along the
straight paths), apply my collision rule, and compare the impulse and the next sample.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Two balls, equal masses, offset 1 r (line of centres 30°) | v₁ = (0.25, −0.4330127019), v₂ = (0.75, 0.4330127019): 90° apart, speeds 0.5, 0.866 (closed form: v₂ along n̂ with 2 m₁/(m₁+m₂) u; my simulation the same) | (0.25, −0.43301270189222), (0.75, 0.43301270189222); Summary (new) 0.5, 0.866 m/s, 90° | 1e-16 | ✓ |
| … time of the collision | 1 − 0.2 cos 30° = 0.826795 s | 0.8268 s | 0 | ✓ |
| Glancing, offset 1.9 r | v₁ = (0.9025, −0.2966374049), v₂ = (0.0975, 0.2966374049), deflection −18.1949° | (0.902499999999999, −0.296637404923925), … | 1e-15 | ✓ |
| Head-on, offset 0 | ball 1 stops, ball 2 takes 1 m/s | (0, 0), (1, 0); Summary "— (one ball stops)" (was not shown) | 0 | ✓ |
| Unequal masses 1 : 3, offset 1 r | v₁ = (−0.125, −0.6495190528), v₂ = (0.375, 0.2165063509); lab deflection tan θ₁ = sin χ/(cos χ + m₁/m₂), χ = 120°: −100.8934° | (−0.124999999999999, −0.649519052838329), (0.375, 0.21650635094611) | 1e-15 | ✓ |
| Unequal masses 3 : 1 | v₁ = (0.625, −0.2165063509), v₂ = (1.125, 0.6495190528); θ₁ = −19.1066° | (0.625, −0.21650635094611), (1.125, 0.649519052838329) | 1e-15 | ✓ |
| Inelastic, e = 0.6, masses 1 : 3 | v₂ = 1.6 · ¼ · cos 30° n̂ = (0.3, 0.1732050808), v₁ = (0.1, −0.5196152423) | (0.100000000000001, −0.519615242270663), (0.3, 0.173205080756888) | 1e-15 | ✓ |
| Wall, e_w = 0.7, v = (3, −2), m = 2 | hit at t = 0.4/3, v → (−2.1, −2), impulse 10.2 N·s | the same | 1e-15 | ✓ |
| Event ordering, every run (63 to 65 048 events) | no overlap: min (distance − σ) ≥ 0 between all events; each logged pair in contact; each wall hit at the wall | min gap −6·10⁻¹⁵ m; contact error ≤ 7·10⁻¹⁵ m; wall ≤ 4·10⁻¹⁵ m; impulses agree to 9·10⁻¹³; my state at every sample equals the app's to 10⁻¹⁵ m, 7·10⁻¹⁴ in velocity; no disc past a wall at any sample | rounding | ✓ |
| Momentum and energy, elastic (defaults, dense, Brownian, periodic, elastic break) | conserved exactly | KE drift 1.0–4.0·10⁻¹⁵; periodic momentum drift 9·10⁻¹⁷ (2·10⁻¹⁶ Brownian) | rounding | ✓ |
| Billiards break (e = 0.95, e_w = 0.8), 6 s | energy lost = Σ ½ μ u² (1 − e²) + Σ ½ m v_n² (1 − e_w²) over the 123 events = 4.98093992929008 J (my replay) | KE drop 4.98093992929009 J (91.56 %) | 4e-15 J | ✓ |
| … elastic (e = e_w = 1) | 5.44 J kept (½ · 0.17 · 8²) | drift 1.1·10⁻¹⁵ | — | ✓ |
| Newton's cradle | equal masses, e = 1: each collision swaps the velocities, so ball 5 leaves at 1 m/s at t = 0.6 s, meets the wall at 2.1 s, and ball 1 leaves backwards at 3.6 s | the same (8 collisions, 1 wall hit) | 1e-12 | ✓ |
| Maxwell, defaults (relaxed from equal speeds) | 2-D MB with kT = 0.5 J; on snapshots 1 s apart (1100 speeds, about 12 collisions per disc between them): KS D = 0.025, p = 0.51; χ² = 12.2 on 10 dof, p = 0.27; finite-N microcanonical f ∝ v (1 − m v²/2E)^(N−2): p = 0.62 | pooled KS distance 0.0082 | — | ✓ |
| Maxwell, dense gas | (same test) KS p = 0.92, χ² p = 0.77 | 0.0065 | — | ✓ |
| Maxwell, Brownian gas; periodic gas | KS p = 0.76; 0.93 | 0.0055; 0.0080 | — | ✓ |
| Equipartition | ⟨½ m v²⟩ = kT per disc in 2-D: kT = KE / N = 0.5 J (defaults) | 0.5 J | 0 | ✓ |
| Collision rate, defaults | Enskog N ω / 2, ω = n 2σ √(π kT/m) g(σ), g = (Z − 1)/2η = 1.236: 620 /s | 630 /s (12 608 in 20 s) | +1.7 % (the walls' strip raises the density) | ✓ |
| Collision rate, dense | g = 2.246: 5629 /s | 5801 /s | +3.1 % | ✓ |
| Pressure, bulk (my periodic simulation, virial P A = N kT + Σ σ J / 2t) | Henderson Z = 1.3107 (η = 0.1257), 2.7637 (η = 0.3927) | — | mine 1.3090 (200 s), 2.7550 (100 s): 0.1 %, 0.3 % | ✓ (Henderson right) |
| Pressure, defaults (100 discs, walls) | my simulation of the same box (200 s): P / P_ideal = 1.3711; Henderson 1.3107 | 1.369; Henderson 1.311 | 0.2 % from mine; +4.5 % from Henderson | ✓ (finding 13) |
| … the wall offset shrinks with r / L | mine at η = 0.126: +4.6 % (r = 0.02), +1.2 % (r = 0.005, 1600 discs); at η = 0.196: +3.2 % (r = 0.0125), +1.6 % (r = 0.00625); at η = 0.393: +7.2 % (r = 0.025), +3.6 % (r = 0.0125) | — | — | ✓ |
| Pressure, dense gas (200 discs) | mine (100 s) 2.9633; Henderson 2.7637 | 2.972 (2.960 before the Maxwell scaling) | 0.3 % from mine | ✓ |
| Pressure, inelastic cooling | P / P_ideal near Henderson, 1.31 (a cooling gas stays close to its equation of state) | before 5.408; after 1.364 | — | ✗ → fixed (finding 1) |
| Inelastic cooling, energy lost in 10 s | Haff's law T = T₀/(1 + t/t₀)², t₀ = 4 / ((1 − e²) ω₀) with ω₀ = 12.61 /s from the elastic run (each collision loses (1 − e²) kT on average in 2-D): t₀ = 1.670 s, 97.95 % | 97.93 %; KE(t) within 1–5 % of the law at 1, 2, 5, 10 s | 0.02 % | ✓ |
| Brownian, D | my 1500 s periodic simulation of the preset's gas, relative to the centre of mass: D = 0.00759 at kT = 0.450, i.e. 0.00799 m²/s at the app's kT = 0.498 (D ∝ √kT exactly for hard discs); OU fit τ = 1.35 s. Kinetic theory (dilute, infinite gas: γ = 2 n R_c √(2π m kT)) D₀ = 0.0123, τ = 1.23 s | before (walls, 30 s, fit through 0): 0.0056; after (periodic, 60 s): seed 1 0.0030, 16 seeds mean 0.00746 (sd 0.0036, so ±0.0009 on the mean; range 0.0030–0.0155) | — | ✗ → fixed (findings 2, 3); one tracer scatters by ±50 % |
| … estimator bias (my 1500 s trajectory cut into 60 s pieces) | true 0.00757 | old fit through 0 to T/4: −13 %; to T/4 through 0 on 30 s with walls: worse (the box); new line over T/16–T/8: −2 % (scatter ±39 %) | — | ✓ |
| Brownian, equipartition with conserved momentum | tracer KE in the CM frame = kT (1 − M/M_tot) = 0.75 kT | mine 0.739 kT; app 0.67 in one 60 s run (about ±20 % from 45 velocity-relaxation times) | — | ✓ |
| Maxwell start, 150 discs | kT = ½ m v0² = 0.5 J (what the docs promised) | before 0.422 J (a sample of 150); after 0.4977 J over the second half (0.5 at the start) | — | ✗ → fixed (finding 9) |
| Lesson numbers | 90°; P / P_ideal ≈ 3 (2.97); Haff ≈ 98 %; e = 0.9 loses 1 − e² = 19 % of the approach energy | text before: "lost 10 % at a time" | — | ✗ → fixed (finding 11) |

## Automatic checks

From `captureVerification` (after the fixes): every preset solves in 0.01–3.3 s headless, the
Brownian preset (now periodic, 60 s, 63 000 collisions) in 9.6 s; every Summary number reaches
the metrics (the text rows "— (no motion)", "— (one ball stops)", "none (the balls miss)",
"— (run too short)" are left out on purpose); every exported column has its units entry (time s,
KE J, |P| kg·m/s, wall impulse N·s) and no NaN or Inf; a second solve gives the identical result.
The periodic prediction was vectorised over the nine images (finding 15): the same collisions
(6165 in the periodic gas, 12 608 in the defaults) and identical results, 1.8 times faster.

### In the app (`dlab.dev.checkBehaviour`)

After the fixes all eleven pass: every preset loads and runs (slowest the Brownian preset, 11 s in
the app, median 4 s); undo and redo; a scenario round trip keeps every input; CSV (4 columns, all
with units), MAT, plot, and report exports (the report has every Summary row and 6 images); a
10-frame GIF; a sweep over N (99–101), an N × radius map, a 6-sample Monte Carlo study, and a short
optimization; no Modes tab (none applies); theme and text-size switches keep the result. Before
the fixes they passed as well (the Brownian preset then took 8 s in the app).

### Tests

`tests/sims/collisions` (21: 14 engine, 7 in the app; 8 of them new: `testObliqueClosedForm`,
`testWallReflectionWithRestitution`, `testNoOverlapsAndNothingLeavesTheBox`,
`testEnergyLostAddsUpOverTheEvents`, `testMaxwellStartHasTheMeanEnergyOfV0`,
`twoBallsLeaveAtRightAngles`, `inelasticGasPressureMatchesItsTemperature`,
`axesAndSummaryStayReadable`; `denseGasPressure` and `brownianTracer` tightened),
`PluginConformanceTest` for the plugin (14), `TestLessons` for "From collisions to temperature"
(1), `TestLessonChecks` (7), and `ArchitectureTest` (10): 53 passed, 0 failed, none excluded.
`codeIssues` on the engine, `initialState`, the plugin and both test files: 0. No shared code was
changed. The showcase view changed (the readout above the box), so
`dlab.dev.generateImages(Ids="collisions")` made its thumbnails and docs image again.

Not fixed here, because it lies in shared code: the Analyze ▸ Custom plot of a conserved quantity
(kinetic energy against time) still zooms into its rounding noise with 14-digit ticks, as the
Energy tab did before finding 6. It affects every simulator's Custom plot and is left for a shared
fix.

## Checklist

- [x] Physics: equations, units, signs, frames, assumptions match the docs page and `about()`
  (the impulse, the restitution guard, the 2-D equipartition and Maxwell form checked by hand; the
  docs now say what was missing)
- [x] Numbers: defaults, every preset, and edge cases (head-on, glancing, unequal masses,
  inelastic, wall restitution, no motion, balls that miss, a periodic gas, a dense gas, a very
  short tracer run) against the reference values; every event of every preset replayed
- [x] Inputs: labels, units, ranges, tooltips (added for the start, restitutions, speed, seed,
  cue direction, edges), visibility rules (gas, billiards, two-ball and tracer inputs appear only
  when they apply); presets load what they say
- [x] Outputs: every tab readable in both themes and at Larger text (before and after the fixes);
  the animation's KE readout matches the energy plot; the tracer's trail matches its path
- [x] Summary and exports: Summary, plots, and CSV agree; units hold units only; the report is
  complete
- [x] Analysis: Sweep, Map, Optimize, Uncertainty run cleanly on N and the radius; no Modes or
  Bode (none apply to hard-disc collisions)
- [x] Teaching: the lesson's five checks pass, and its statements and numbers agree with the
  reference values (findings 10–12)
- [x] Behaviour: readable errors (overlaps, a box too small for N discs, too many samples);
  Cancel every 500 events (covered by the suite); results survive theme and text-size switches

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | The inelastic gas's "Pressure ratio P / P_ideal" was 5.41: the pressure averaged the whole run (hot at first) but kT only the second half. | Pressure over the second half, the same as kT: 1.36 (Henderson 1.31). | `inelasticGasPressureMatchesItsTemperature` |
| 2 | Numbers | The Brownian preset's D (0.0056 m²/s) came from MSD = 4 D t fitted through the origin up to a quarter of a 30 s run in a 1 m box: the curve's ballistic start (τ ≈ 1.3 s) and the walls (the tracer had crossed the box: the MSD bent over after 6 s) both pulled it down. | The preset is a periodic box run for 60 s; the MSD goes to T/8 and D is the slope of a line 4 D t + c over the later half of the lags (−2 % bias on my 1500 s trajectory, against −13 % for the old fit). | `brownianTracer` |
| 3 | Physics | In a periodic box the total momentum is conserved and random (|P| ≈ 12 kg·m/s for the preset): the whole gas drifts at P/M, which the tracer's MSD would show as a ballistic V² t². | The MSD is measured relative to the centre of mass; docs and `about()` say MSD ∝ t holds at long times and without walls, and that the tracer's own energy is kT (1 − M/M_total). | `brownianTracer` |
| 4 | Summary | The two-ball Summary had nothing about the collision: the lesson said the balls "leave at right angles" but checked only the energy drift. | Rows: time of the collision, both speeds after, the angle between the paths ("— (one ball stops)" head-on, "none" if they miss); the engine records the velocities after the first collision; the lesson checks 90°. | `twoBallsLeaveAtRightAngles`, `testObliqueClosedForm` |
| 5 | Outputs | The Speed distribution (with a Maxwell curve and kT) and the Pressure tab (measured against the ideal gas and Henderson) were shown for 2, 5 and 16 balls. | Both only for a gas. | `twoBallsLeaveAtRightAngles` |
| 6 | Outputs | A conserved kinetic energy filled its axes with rounding noise (ticks "50.000000000005"); the two-ball and cradle plots had a negative KE axis. | KE, \|P\| and the MSD axes start at zero. | `axesAndSummaryStayReadable` |
| 7 | Outputs | With all speeds equal at the start, the start's histogram (a spike of 10 s/m) squashed the second half's histogram and the Maxwell curve into the bottom tenth. | The axis fits the histogram and the curve; the start's spike is labelled "peak off the scale". | `axesAndSummaryStayReadable` |
| 8 | Outputs | The animation's readout (t, KE) sat on the box's top wall, behind the top row of discs. | Head room above the box. | `axesAndSummaryStayReadable` |
| 9 | Inputs | A Maxwell start drew N random speeds, so its kT missed ½ m v0² by about 1/√N (0.422 J instead of 0.5 J for the Brownian preset), though the docs said "the same mean energy". | Speeds scaled so that mean v² = v0² exactly; the Speed tooltip says v0 is the RMS speed there. | `testMaxwellStartHasTheMeanEnergyOfV0` |
| 10 | Teaching | "What Robert Brown saw pollen grains do": Brown watched particles from inside pollen grains (the grains themselves are too big to jiggle visibly). "Einstein used this to count molecules": Einstein proposed it, Perrin did it. | Corrected. | `TestLessons` |
| 11 | Teaching | Inelastic cooling: "lost 10 % at a time in each collision" — e = 0.9 keeps 0.9 of the approach speed, so a collision loses 1 − e² = 19 % of the energy of that approach (and on average (1 − e²) kT). "The slow discs start to clump together" is not seen in this 100-disc box in 10 s. | The right numbers, Haff's law, and clustering "in a larger box, given time". | `TestLessons` |
| 12 | Teaching | The pressure step passed at P / P_ideal > 1.2 and said "close to Henderson"; the dense gas gives 2.97 against Henderson's 2.76. | Check 2.5–3.3; the text says why the discs push harder and that the small box adds a few percent. | `TestLessonChecks` |
| 13 | Numbers | The measured wall pressure is 4.5 % (defaults) and 7 % (dense) above Henderson. My own simulations show this is the walls of a small box (an offset in proportion to r / L: 1.2 % with 1600 smaller discs), not an error. | Accepted, with the numbers in the docs; the test allows 12 %. | `denseGasPressure` |
| 14 | Summary | A gas at rest showed "KS distance from Maxwell NaN" and "Pressure ratio 0"; a tracer run under 9 samples "Diffusion coefficient NaN". | "— (no motion)", "— (run too short)". | `axesAndSummaryStayReadable` |
| 15 | Behaviour | The periodic preset (now Brownian) took 16.7 s to solve: the nine images were checked in a loop for every prediction. | One vectorised step: identical results, 9.6 s. | `testPeriodicConservesMomentum`, `testReproducible` |
| 16 | Outputs | With colour by speed, the slowest discs (the colour map's end nearest the background) almost vanished: in the inelastic preset's last frame all discs were dark navy on dark navy (and pale blue on white). | A thin border round every disc. | — (colour) |
| 17 | Outputs | At Larger text the pressure bars' labels ran together ("MeasuredIdeal gasHenderson"). | Horizontal bars, labels on the side. | — (layout) |
| 18 | Inputs | The choice labels were cut off even at normal size ("Gas (many di…", "All equal (wat…", "Newton's cra…", "Maxwell (alre…"). | Short labels ("Gas", "All equal", "Maxwell", "Periodic"); the explanations moved to tooltips. | — (layout) |
| 19 | Inputs | Most inputs had no tooltip; the Speed tooltip said "every disc's speed" also for the Maxwell start; `initialState` described the offset as "half a radius per unit". | Tooltips for the start, both restitutions, speed, seed, cue direction, edges; the comment corrected. | — |
| 20 | Outputs | In a periodic box the tracer's path and trail drew lines across the box where it wrapped, and the box edge looked like a wall. | The path breaks where it wraps; the periodic box is dashed. | `brownianTracer` |
| 21 | Numbers | One tracer in one 60 s run gives D only to about ±50 % (16 seeds: 0.0030 to 0.0155 m²/s, mean 0.0075 against my 0.0080). | Accepted: it is the physics of a single Brownian particle; the docs and the lesson say so ("try another seed"). | — |
| 22 | Physics | No friction or rolling: the billiard balls never stop and there are no pockets; the rack's apex is at 0.72 of the table, not the foot spot (0.75). | Accepted: a hard-disc model; the docs now say so. | — |
