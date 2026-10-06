# Changelog

Each release of Dynamics Lab. The newest is at the top, and its version matches `dlab.version`
(a test checks this). Version numbers follow semantic versioning: a minor version adds features
and keeps scenario files and plugin API v1 compatible.

## [1.4.0] — unreleased

### Highlights
- **27 simulators** (nine new: DC Motor Servo, Vehicle Handling, Gravity Assist, Atmospheric
  Entry, Spacecraft Attitude Control, Quadrotor, Column Buckling, Vibrating Membrane, and Heat in
  a Plate), each with a docs page, a lesson, and Home thumbnails.
- **One Analyze tab in every simulator** with eight tools: Custom plot, Sweep, and the new Map,
  Optimize, Uncertainty (Monte Carlo), Fit (to measured data), Modes, and Bode (with gain and
  phase margins for closed loops).
- **Every simulator verified** against independent reference values (closed forms, published
  results, separate calculations), one at a time, with a sheet each in
  [docs/verification](docs/verification/README.md). The pass found and fixed 273 problems
  (listed under Fixed), and the build now checks every simulator for the kinds it found most.
- **35 lessons** (six new), with lesson steps saved from the app, multiple-choice questions,
  checks on the new tools, and stated numbers checked by the tests.
- **A friendlier first run:** a welcome on Home, cards that fill the window, a Lessons ▾ menu
  on cards with several lessons, an HTML run report, a text-size setting, and a wider input
  panel for simulators with table inputs.
- **More than 1,400 tests**, run as five parallel parts locally (`buildtool ptest`) and in CI.

### Fixed
- Home: a card with four lessons (Pendulum) squeezed its Open button to a sliver; a simulator with
  several lessons now has one **Lessons (n) ▾** button whose menu lists them by title with your
  progress.
- Table inputs (waypoints, rocket stages, maneuver burns, frame members) showed numbers cut off
  ("3." for 3.25) and, at Larger text, sometimes no rows at all: values are shown compactly (3,
  3.25), the columns share the panel's width by what they need, and each table is as tall as its
  rows at every text size.
- The Summary tab's empty space below its rows was black; the table is now as tall as its rows,
  and its headings grow with the text size.
- 6DOF: a trimmed state showed six figures (19.9932 m/s, throttle 0.610982); its initial state
  and controls show four (19.99, 0.611), with the exact values kept.
- A test of animation export (`animationRecordsEveryAxesInTheGrid`) failed about one run in
  twenty-five: it recorded before a new inset had finished appearing on screen.
- Orbital maneuvers, the three-body problem, and several other features failed on MATLAB R2025b
  (event outputs from the ODE solvers, `uitable` values, string comparisons), and six test files
  had stopped loading, so their tests were silently skipped.
- Wave: a fine free–free beam lost its lowest flexible modes, and a "mode" start excited other
  modes. Frame: the degree of indeterminacy counted hinges at a pinned joint once too often.
  Cart-pole: "keep going after the pole falls" reported a fall at the end of the run. Rocket:
  duplicate burnout metrics. Heat: a 100 % energy-balance error for insulated rods. Rigid body:
  a wobble counted as flips. 6DOF: a sideways stall could stall the solver; the tuned Dutch-roll
  doublet departed from controlled flight.
- Mass-Spring (verified): the Summary no longer shows "Inf" at an undamped resonance or puts the
  damping type in the units column; the animation draws only the springs and dampers that are
  there, with the damper above the floor, and shows the external force; phase portraits and the
  Energy legend no longer hide data; Bode lists carry units; heavily damped runs solve in a
  fraction of a second instead of minutes, and the defaults about four times faster.
- Projectile (verified): the Top view was a mirror image (seen from below) and now looks down
  from above; the wind label no longer hides behind the legend (it is in the readout); flat throws
  and the readout no longer overlap the trajectory; sidespin shows z and vz in the plots and the
  readout; the spin parameter and lift coefficient at launch use the speed relative to the air;
  the maximum speed includes sideways motion; a vertical shot has a range of exactly 0; Summary
  units are units only; choice lists fit their fields ("With drag", "Standard (ISA)", "Uniform" /
  "Boundary layer"); the air-density tooltip no longer suggests water (buoyancy is not modelled).
- Nonlinear Oscillators (verified): the Poincaré map of a periodic motion no longer zooms into
  its rounding noise (a period-1 point looked like a line of 101 points with 14-digit ticks); a
  Van der Pol relaxation oscillation's maxima are found exactly (μ = 50 reported 2.08 and
  "2 different maxima" instead of 2.003 and one cycle); the pendulum's Potential tab shows one
  turn, and a pendulum that turns over the top has no "steady amplitude" of hundreds of radians;
  a free damped run says it settles to rest instead of "a periodic cycle", without a made-up
  dominant frequency; the Summary's count is "Distinct Poincaré points" with nothing but units in
  the units column; a saved MAT result no longer carries the app's progress callback (MATLAB warned
  when loading it); the pendulum's export has θ in rad and θ' in rad/s; legends sit above the plots and the
  spectrum's ω/2 and ω/3 labels no longer overlap; unforced runs have the same sample limit as
  forced ones; inputs have tooltips.
- Strange Attractors (verified): the maxima behind the return map and the distinct count are
  located exactly by the solver instead of a parabola through three samples (up to 4·10⁻³ off, and
  dependent on the output step); the "periodic window (ρ = 160)" preset leaves out its chaotic
  start and now shows the two-maximum cycle instead of "12 distinct maxima"; Chua's circuit no
  longer lists outer equilibria that do not exist (k ≤ −1), and its Modes are at the centre of a
  scroll (P+), not the origin; Rössler with no equilibrium has no Modes; the Sensitivity tab's
  e^{λt} line runs through the twins' growth, the log plot no longer drops to 10⁻³⁰⁸ when the
  twins coincide, and the running λ starts without a spike; a periodic orbit has no "Lyapunov
  time"; a cycle's return map is a dot, not a zoom into its convergence; Summary units are units
  only ("yes"/"no" for settled); ρ is the relative Rayleigh number, with a tooltip on where the
  chaos begins; the twin offset must be positive.
- Rigid-Body Rotation (verified): the default body (I = 1, 2, 3) was a flat plate of no thickness,
  so sweeps and studies of its inertias failed and the animation showed a flat sheet; it is now a
  box with I = 1, 2, 2.5 (the tennis racket preset runs 20 s and shows 4 flips, 4.96 s apart).
  Flips are counted for the intermediate axis whichever body axis it is (I = 2, 1, 2.5 reported no
  flips while tumbling); spin about an axis whose inertia equals another's is "neutral", not
  "stable"; the automatic spin axis is the one nearest L, not the largest ω component. The Summary
  says yes/no instead of "yes = 1", shows no "Inf" for a top without spin, and adds the exact
  steady precession rate (or says there is none); the tumble's decaying partner on the Modes tab
  is no longer called unstable. A top that dips below its tip stands on a post instead of going
  through the floor, and its axle is drawn; L and ω arrows differ in the light theme; the polhode
  axes have units; the precession legend no longer covers the curve; choice lists fit their fields
  at Larger text; every input has a tooltip; I_s above 2 I_t is rejected.
- Billiards and Gas Collisions (verified): the inelastic gas's pressure ratio compared a
  whole-run pressure with the second half's temperature (5.4 instead of 1.36); pressure and kT now
  come from the same half. The Brownian preset's diffusion coefficient was fitted through the
  origin over a box the tracer had already crossed (0.0056 m²/s, about 30 % low): the preset is now
  a periodic box run for 60 s, the MSD is measured relative to the drifting centre of mass, and D
  is the slope of the straight part (the docs say how uncertain one tracer is). The two-ball
  Summary shows both speeds after the collision and the angle between the paths (90° for equal
  masses), which the lesson now checks. The speed distribution and pressure appear only for a gas
  (they compared 2 to 16 balls with Maxwell and an ideal gas); a conserved kinetic energy is no
  longer zoomed into its rounding noise (14-digit ticks), the starting speeds' spike no longer
  squashes the histogram, the animation's readout no longer sits on the box's top wall, slow discs
  keep an outline against the background, and the pressure bars' labels no longer run together at
  Larger text. A Maxwell start has exactly the mean energy ½ m v0² (a 150-disc sample was 16 % low);
  a gas at rest shows no "NaN"; choice lists fit their fields; the lesson says Brown saw particles
  from pollen grains (not the grains), credits Perrin, and gives the right energy loss per
  collision (1 − e² = 19 % of the approach energy, not 10 %).
- DC Motor Servo (verified): the loop gain's phase margin came out 360° too large (424° instead
  of 65°) when the phase starts just below −180°, as for position PID with Ki above about
  51 V/(rad·s); the loop phase now starts on its integrators' branch, which also corrects the
  cart-pole's LQR and PID + cart margins (425° and 418° instead of 65° and 58°). The Summary no
  longer shows "NaN" when the motor does not move; "Steady-state error" is now "Final error" (a P
  servo still ringing at the end showed 0.69° for a loop with no steady error); the damping ratio
  is that of the least damped closed-loop pole (the PID presets showed ζ = 1 next to 13–49 %
  overshoot); an unstable linear loop is flagged. The energy used is integrated with the motion
  (it was 0.1 % low); the open-loop CSV no longer has reference and error columns full of NaN; a
  run asking for more than 2 million samples is refused instead of running out of memory. The
  Control and Anti-windup choices fit their fields, every input has a tooltip, and the Poles
  tab's text no longer wraps at Larger text. Lessons: the P servo overshoots 65 % (not 64 %),
  windup saturates for 0.14 s, and the Bode lesson explains why the speed's phase ends at −180°.
- Inverted Pendulum on a Cart (verified): the loop gain's gain margin read "unlimited"; around the
  unstable plant the phase rises through −180°, and the margin is now found there (LQR: −10.7 dB,
  the amount the gain may fall, against LQR's guaranteed −6 dB), in the shared Bode code for every
  simulator. An LQR position weight of 0 is refused with an explanation instead of the Riccati
  solver's error. The Summary shows why there is no settling time (the pole fell, the cart hit the
  end stop) instead of "NaN", drops the closed-loop pole and target error when there is no
  controller, and reads a pole at 0 as 0 (not 3·10⁻¹⁵); an unstable linear closed loop is flagged.
  Without a controller there is no target line, force-limit band or force-limit input; the track
  ends, the start marker and the force plot after a fall are no longer cut off by the frame; the
  Gains and poles text fits at Larger text and gives the PID law. The choice lists fit their
  fields, every input has a tooltip, and the inputs and `about()` say that l is half a rod's
  length. Lessons: the 2 N motor catches the pole but hits the end stop, 2.81 N is the least that
  works (not "about 3 N"), and the four open-loop modes are named correctly.
- Quarter-Car Suspension (verified): with "Tire can leave the road" off, a negative tire load
  was reported as the wheel leaving the road; the status line, the Summary and the tire plot now
  say the tire pulled the road. The Summary says yes/no and how long the wheel was off the road,
  and its body-bounce and wheel-hop frequencies are marked undamped (the Modes tab's include the
  damping). A run of more than 2 million samples is refused instead of filling memory. Every
  input has a tooltip, and the road and class choices fit their fields. Lessons: comfort and road
  holding have different best dampers (ζ 0.17 and 0.24, not "both 0.2–0.3"), the healthy car also
  leaves the road briefly at 40 km/h, and worn dampers keep it off three times as long.
- Bode (all simulators): the resonance is found between the frequency grid's points (the quarter
  car's showed 1.182 Hz for 1.189 Hz).
- Vehicle Handling (verified): the Summary says yes/no for "Linear model stable" and "Spun out";
  a spin with linear tyres says its forces are not physical (the 120 km/h preset peaked at 6.4 g).
  The tyre-model choices and the cornering-stiffness labels fit, every input has a tooltip, and
  the Bode tab has units. Lesson: the oversteer step asks for 100 km/h or more (at 98 km/h the
  spin comes after the 6 s run, so the step could not be passed).
- Modes (all simulators): values show their four significant digits (5.774, not 5.7740), and the
  table grows with the text size instead of hiding its last row.
- Sweep, Map, Optimize, and Uncertainty (all simulators) no longer start on, or run with, an
  input the other inputs hide: the column's Map opened on L × E, and E is used only for a custom
  material, so the map was flat. Choosing one says why.
- Column Buckling (verified): the Summary keeps units in the units column, says yes/no for
  "Buckling governs", shows the elastica rows only for the elastica, and shows the Southwell
  error of exact points as 0. Past 2.18 P_cr the elastica warns that its ends pass each other.
  The choices fit their fields and every input has a tooltip; the deflected shape's legend no
  longer covers the base support; with no bow the column curve's legend no longer reads
  "L/4503599627370496"; the elastica's curves are smooth. Lesson: the flagpole gets a quarter of
  the pinned column's load, not of the fixed–fixed one's.
- Vibrating String and Beam (verified): a plucked beam starts from its static deflection under a
  point load, not a string's triangle. The kink's bending energy grew with the mesh: the ruler
  started with 1.07 J for a true 11.5 mJ, spread over every mode, and named mode 18 dominant; it
  now holds 97 % in mode 1. A beam's starting slopes are exact (a bump had 1.6 % too much
  energy). The choices fit, every input has a tooltip, a mode with a node at the start reads 0 %,
  the Mode content labels fit, and the spectrum has units.
- Vibrating Membrane (verified): the Chladni patterns' nodal lines are drawn exactly (contours of
  the grid shapes broke where lines cross: a gap at the centre of the circle's (1,1) mode, jogs
  in (1,2) and (2,2)). The start choices fit, every input has a tooltip, a single mode reads 0 %
  axisymmetric (not 3.7e−30 %), and the spectrum has units.
- 1-D Heat Conduction (verified): the energy balance closes at every time for every scheme. The
  heat in used trapezoidal time weights whatever the scheme (0.03–0.08 % "errors" for explicit
  and implicit runs) and left out a fixed end's half cell (the brick wall's curves were 5 % apart
  mid-day). The swing rows appear only for a cycling end temperature (the insulated hot spot
  showed a "swing ratio" of 1). The choices fit and every input has a tooltip. Lesson: the
  accuracy sweep uses a fine grid, where the second-order fall it describes can be seen.
- Heat in a Plate (verified): the choices fit their fields, every input has a tooltip, and the
  Temperature field's colour-bar label is no longer cut off at Larger text. Lesson:
  at large ADI steps a pattern fine along one direction rings (×−0.79 per step at r = 5), but a
  checkerboard is multiplied by +0.67 and barely decays, rather than both ringing.
- Orbital Mechanics (verified): the Geostationary and Molniya presets are measured from the
  equator (from the frame, 23.44° to it, the "geostationary" track was a figure-eight to ±23.4°);
  J2 uses its reference radius, Earth's 6378.137 km (`dlab.physics.bodyConstants` now gives each
  body's), so J2 effects are no longer 0.22 % weak (the sun-synchronous inclination is 98.159°);
  a retrograde J2 orbit's momentum drift no longer reads 2.6e10; angles of 0 no longer show as
  360° (`dlab.physics.cart2kep`) and rounding noise shows as 0; after a re-entry the
  Perturbations tab follows the flight above 100 km instead of the final plunge. The choices fit
  and every input has a tooltip.
- Orbital Maneuvers (verified): no bi-elliptic alternative (Summary row or bar) when its
  apoapsis lies inside the target orbit (the lunar transfer showed a "saving" of 0); "Final a
  error (relative)" keeps units out of the units column; the maneuver choices fit and every input
  has a tooltip; phasing's two burns, at the same point, share one label instead of printing over
  each other.
- Gravity Assist (verified): the lesson's figure for how much Jupiter slows (6 × 10⁻²¹ m/s for
  Voyager's 722 kg); the pass choices fit and every input has a tooltip. Changing a display option
  while the animation plays no longer floods the Command Window with "Invalid or deleted object"
  warnings, in any simulator (no frames are drawn while a result is redrawn).
- Three-Body Problem (verified): the Modes tab names a saddle's growing and decaying directions
  (both were "Saddle (unstable)", one marked Stable), and its rates and periods are in the model's
  time units, not seconds (also Strange Attractors), with round-off real parts shown as 0. The
  Lagrange-triangle preset runs long enough to break up; the lesson's Lyapunov run is long enough
  to unravel; the docs give the Lyapunov period (5.4858, not the half period); Summary units stay
  in the units column; the choices fit and every input has a tooltip.
- Rocket Ascent (verified): the maximum acceleration was computed at each burnout with the empty
  stage already dropped (60.9 g instead of 15.2 g for the sounding rocket); it is now the largest
  acceleration under thrust. Max-Q covers the ascent (to the highest point or the last burn), and
  the plots mark the same point. "Circularize at the apoapsis" no longer silently does nothing
  when the apoapsis comes after the time limit. Event labels no longer print over each other, and
  the Orbit tab no longer draws an "orbit" through the impact point. Every input has a tooltip.
- Atmospheric Entry (verified): the lesson's skip-out and corridor statements match the
  simulator (−5.6° or shallower skips, at 8.6 km/s from −5.5°; the corridor's shallow edge still
  pulls about 9 g); "Skipped out" reads yes or no; the atmosphere choices fit and every input has
  a tooltip.
- Spacecraft Attitude Control (verified): the spacecraft is drawn in a neutral grey (the lime hid
  the green y axis); a constant thruster or disturbance torque is no longer hidden on the edge of
  its plot; the exported drift is undefined (not 4 × 10³⁰⁶) for a run that starts at rest; the
  lesson's numbers match the simulator; the mode choices fit and every input has a tooltip.
- 6DOF Flight (verified): the lesson's phugoid step describes what the run shows (one swing up,
  then a slow descent: this model's phugoid is heavily damped) instead of an oscillation to
  compare; the docs and the description say that the stability and damping terms do not change
  with airspeed, and `about()` no longer calls the default model "12 states, Euler angles" or its
  controls "held constant"; steady traces are no longer drawn on the edge of their plots, and
  round-off is no longer stretched into a wiggle; the choices fit and every input has a tooltip.
- Earlier simulators, caught by the new checks: tooltips on the 59 inputs of Pendulum,
  Mass-Spring, Projectile, Strange Attractors, Rigid-Body Rotation, Billiards and Gas, and Truss
  that had none; shorter choices where they were cut off (Pendulum's "Single" / "Double",
  Mass-Spring's "Two masses" and force shapes, Nonlinear's "Pendulum"); drift rows with
  "(relative)" in the name instead of the units column (Billiards and Gas, Rigid-Body); Orbital
  Mechanics' two-body elements drawn flat instead of as round-off; Frame and Beam writes a value
  shared by two elements once.
- Quadrotor (verified): the Modes tab says which loop each slow integral mode belongs to (height
  or horizontal) instead of five "Integral (slow)"; round-off after a pure roll is drawn flat; the
  docs say the tilt limit bounds the command (a lightly damped loop can overshoot it); the choices
  fit and every input has a tooltip.

### Added
- Nine new simulators: DC Motor Servo, Vehicle Handling, Gravity Assist, Atmospheric Entry,
  Spacecraft Attitude Control, Quadrotor, Column Buckling, Vibrating Membrane, and Heat in a
  Plate, each with a docs page, thumbnails, and a lesson (27 simulators in all).
- Three ways to get it, listed under "Try it" in the README: an Open in MATLAB Online button,
  an installable toolbox (`buildtool toolbox` makes `DynamicsLab.mltbx`; pushing a version tag
  attaches it to the GitHub release), and the standalone Windows installer.
- Analysis tabs that work in every simulator:
  - **Map**: a result as a heat map over two inputs; click a cell to use its inputs.
  - **Optimize**: the inputs (up to three) that maximize or minimize a result, optionally with a
    limit on another result.
  - **Uncertainty**: a seeded Monte Carlo study of inputs with tolerances: each result's spread
    and which input drives it.
  - **Fit**: fit inputs to measured data imported from CSV, which the Custom plot can also draw.
  - **Bode**: gain and phase from any input to any output, with resonance and bandwidth, for
    models whose linearization has inputs (Mass-Spring, DC motor, Inverted Pendulum on a Cart,
    Quarter-Car, Vehicle Handling, Spacecraft Attitude, Quadrotor); for controlled models (DC
    motor, cart-pole) the loop gain with its gain and phase margins; marked frequencies and a
    hertz axis where they help (the quarter car).
  - All of them sit in one **Analyze** tab, beside the simulator's own plots.
- **Export ▸ Report (HTML)**: one page with a run's inputs, Summary, and plots.
- Lessons: **Save as lesson step…** builds a lesson from the app; multiple-choice questions;
  checks on maps, optimization, uncertainty, fitting, and the Bode tab; steps that move to
  another simulator to compare models; shipped measured data to fit. Six new lessons use them
  (35 in all), among them measuring a pendulum's damping from a measured swing.
- A text-size setting (**Aa** in the header), a series palette that stays readable with
  colour-blind vision, and Home opening with the search box focused.
- Each simulator reopens on the tab and analysis set-ups it was left with, also after a restart.
- [docs/plugin-api.md](docs/plugin-api.md): plugin API v1.2, every hook and the version that
  added it (v1.2 adds the linearization's `Loop`, `Markers`, and `FrequencyUnits`).
- Animation export records every axes of an animation, insets included (Spacecraft Attitude's
  wheel momentum now sits in an inset).
- `buildtool ptest` runs the suite as five parts in parallel MATLAB sessions (CI runs the same
  parts side by side); `dlab.dev.newSimulator` creates everything a new simulator needs to pass
  the build (docs page, README row, lesson, thumbnails).
- Truss **Strength scale**, a multiplier on every member's yield stress and buckling load, so the
  Uncertainty tab can scatter strength as well as load; the Uncertain loads lesson compares them.
- Strange Attractors (Lorenz, Rössler, Chua), with Lyapunov exponents and return maps.
- Projectile spin (the Magnus force: backspin, topspin, and curveballs in 3-D).
- Orbit J2 oblateness and atmospheric drag, with elements measured from the equator.
- Truss sections per member, a yield and buckling check with utilization and safety factor, and
  a load scale.
- A 6DOF autopilot: altitude, heading, and airspeed hold.
- Lessons sit beside each simulator's Open button on Home (a **Lessons ▾** menu when there are
  several); every simulator has a thumbnail.
- A welcome on Home the first time the app opens: what Dynamics Lab is and a button that starts
  the first lesson. **Got it** hides it; the About dialog on Home can show it again.
- **Wider ▸ / ◂ Narrower** below the inputs: simulators with table inputs open with a wider input
  panel, and any simulator can switch (remembered for each one).
- `buildtool fasttest` (the tests that open no windows), `buildtool discover` (fails on a test
  file that does not load), checks that every simulator has a docs page, README row, and
  thumbnails, and continuous integration on every push.
- Summary rows can carry full-precision numbers with a display format (`Format`, `Display`
  columns), so sweeps and lessons read exact values.
- Checks that keep the problems the verification pass found from coming back, for every simulator, present and
  future: a tooltip on every input; choice labels measured against their field; the Summary's
  units column for units only, at every preset; every preset's plots free of round-off stretched
  over a steady value and of labels printed over each other; a verification sheet with
  independent reference values and a test marked `% Independent reference:` for each simulator.
  `dlab.dev.newSimulator` generates a scaffold that meets them, with a verification sheet, and
  docs/verification/README.md says what "done" means for a new simulator.
- Lesson **claims**: the numbers a step states, checked by the tests against the run its solution
  makes (docs/lessons.md). The seven aerospace lessons state theirs as claims.
- `dlab.ui.minimumSpan` (round-off drawn as the flat line it is) and `dlab.ui.padLimits`, which
  the view applies after every result so that a steady trace no longer lies on a plot's frame.

### Changed
- An infinite bound now shows as open, e.g. "(0, ∞)".
- The quarter car's own "Frequency response" tab is retired in favour of Bode.
- Entry shows the Allen–Eggers peak deceleration only for ballistic runs, as an estimate.
- Shared code replaces copies in the simulators: axes clearing and time labels (`dlab.ui`),
  section properties, spectra, quaternion algebra, ODE progress reporting, and planet orbits
  (`dlab.physics`); the atmosphere gives the speed of sound above 86 km. Plugin font sizes
  follow the text-size setting. Progress reports cost the solver far less (the view no longer
  redraws in full on each one).
- The Map, Optimize, Uncertainty, and Fit panels are built when their tab is first shown, so a
  simulator opens faster.
- The Truss summary names the governing member in its own row rather than in the units column.
- Home cards fill the window: as many columns as fit (three at the smallest window, four at the
  default size), reflowing as the window is resized.
- Home thumbnails show the plot alone (no tick labels, titles, or legends, which were unreadable at
  card size) with heavier lines; Nonlinear Oscillators shows the Duffing double well's phase
  portrait.
- The README screenshots are taken before the thumbnail is exported, so they no longer show
  "Exported …" in the status bar.

## [1.3.0] — 2026-10-01

Eleven new simulators and their lessons: Nonlinear Oscillators, Rigid-Body Rotation, Billiards and
Gas Collisions, Inverted Pendulum on a Cart, Quarter-Car Suspension, Orbital Maneuvers, the
Three-Body Problem, Rocket Ascent, the 2-D Frame and Beam Solver, the Vibrating String and Beam,
and 1-D Heat Conduction; the double pendulum inside Pendulum; Projectile wind, air density, and the
optimal angle; Orbit surfaces and relief; 6DOF doublets, mode identification, wind, and
quaternion attitude; Truss node dragging; set-valued sweeps; table inputs; five Home categories.

## [1.1.0] — 2026-10-01

The expansion features: the shared physics library, the scripting API, cancel and progress,
keyboard shortcuts, undo and redo, the Custom plot, Sweep, and Modes tabs, keeping previous runs
in every simulator, animation export, time-varying inputs, Home search and recent work, and
guided lessons. Fixed the 6DOF air density.

## [1.0.0] — 2026-10-01

Six simulators in one app (Pendulum, Mass-Spring, Projectile Motion, Orbital Mechanics, 6DOF
Flight, and the 2-D Truss Solver), documented and covered by 251 tests.
