# Rocket Ascent

A multi-stage rocket from the pad toward orbit, in the plane of its trajectory over a spherical
Earth: the gravity turn, max-Q and the throttle bucket, staging, and a Δv budget that shows where
the rocket equation's Δv goes.

## Model

States (inertial, Earth's centre at the origin, the pad at (0, R)): position, velocity, mass, and
four running integrals for the Δv budget.

- **Gravity** −μ r/|r|³ (μ = 3.986 × 10¹⁴ m³/s², R = 6371 km).
- **Thrust** T(h) = throttle · T_vac − p(h) A_e, with the nozzle exit area A_e from the
  sea-level and vacuum Isp; the propellant flow is throttle · T_vac / (g₀ Isp_vac).
- **Drag** ½ ρ v_rel² C_d(M) A against the air-relative velocity, with a generic slender-rocket
  C_d(Mach) (0.3 subsonic, 0.6 just above Mach 1, 0.25 at Mach 5) times the drag scale. ρ, p,
  and the speed of sound come from `dlab.physics.atmosphere` (ISA, extended above 86 km). With
  **Launch east with the Earth's rotation**, the rocket starts with the ground's eastward speed
  ω R cos(latitude) and the air turns with the Earth.
- **Guidance:** straight up to the pitch-over altitude, a pitch-over by the given angle over 5 s,
  then a **gravity turn** (thrust along the air-relative velocity). With a target orbit, the upper
  stages instead control their climb rate toward the target altitude, pitching just enough to
  approach it while the rest of the thrust builds horizontal speed. A **pitch program** (a
  schedule of the flight-path angle) can replace all of this.
- **Staging:** each stage burns until its propellant is gone, is dropped, and the next ignites
  after its coast delay. The last stage cuts off at the target orbit (when the apoapsis reaches the
  target, or, under the upper-stage guidance, when the orbital energy matches a circular orbit at
  the target altitude); an optional impulsive **circularization** burn at the apoapsis uses the
  propellant that stage has left. The run also ends on hitting the ground or at the time limit,
  except that after a cutoff the coast always goes on to the apoapsis (at most one orbit).

**Δv budget.** Along the inertial velocity v̂, d|v|/dt is the thrust acceleration minus the three loss rates below, exactly, so

```text
∫ T/m dt = Δ|v| + gravity loss + drag loss + steering loss
gravity loss = −∫ g·v̂ dt,  drag loss = −∫ (D/m)·v̂ dt,  steering loss = ∫ (T/m)(1 − t̂·v̂) dt
```

closes to integration accuracy, and Tsiolkovsky's ideal g₀ Isp_vac ln(m₀/m_f) minus ∫ T/m dt is
the back-pressure loss (thrust lost to the atmosphere's pressure on the nozzle). With the Earth's
rotation on, the inertial velocity starts eastward, so an early vertical climb also counts as
steering loss; that is why the rotation is off in the presets.

## Inputs

| Group | Inputs |
|---|---|
| Vehicle | Stages table (dry mass, propellant, vacuum thrust, vacuum and sea-level Isp, coast before ignition; 1–3 rows), payload, diameter, drag scale |
| Guidance | Pitch-over altitude and angle; or a pitch program (flight-path angle schedule) |
| Mission | Cut off at the target orbit, target altitude, circularize; launch east with the Earth's rotation, latitude |
| Throttle | Throttle schedule (0–1) |
| Simulation | Time limit, output step |

**Presets:** a sounding rocket (straight up and back down), a small two-stage launcher to a
200 km orbit (the default), a three-stage heavy launcher (Saturn V-like, approximate), too steep
(a gravity-loss demo), too shallow (a drag-loss demo), and a max-Q throttle bucket.

## Outputs

- **Animation:** the rocket along its path over the curved Earth, with its plume while
  thrusting, a flash at each staging event, and a readout of time, altitude, speed, q, and stage.
- **Trajectory** (altitude against downrange, with the events and max-Q), **Altitude and speed**
  (inertial and air-relative, and Mach), **Dynamic pressure** (with max-Q), **Acceleration**
  (sensed, in g), **Mass and staging**, **Δv budget** (ideal Δv per stage beside where it went:
  achieved, gravity, drag, steering, and back-pressure losses; the orbital speed at cutoff), and
  **Orbit** (the conic after cutoff; none after a fall back to the ground). Events a few seconds
  apart share one label ("Stage 1 burnout, stage 2 ignition").
- **Summary:** max-Q of the ascent (value, altitude, time; up to the highest point or the last
  engine burn, whichever is later, so a flight that falls back unpowered does not report its fall;
  the plots mark the same point), the largest sensed
  acceleration under thrust (a fall back into the air can decelerate harder), the highest altitude, each stage's
  burnout altitude and speed, the ideal Δv, the four losses, the Earth-rotation gain, the achieved
  Δv, the circularization Δv, perigee and apogee (not after an impact; a perigee below the
  surface is called suborbital), whether an orbit was reached (yes or no: perigee above 120 km),
  and the payload fraction.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| No gravity, no drag, vacuum Isp, vertical | achieved Δv = Tsiolkovsky (10⁻⁸) |
| Vertical, no drag | burnout speed = Tsiolkovsky − ∫ g dt (0.1 %) |
| Two-stage launcher | budget closes to 10⁻⁶; mass drops by the dry mass at staging; perigee > 150 km; max-Q at 8–15 km; gravity loss 1.0–1.8 km/s |
| Throttle bucket | max-Q at least 10 % lower |
| Extended atmosphere | density and pressure continuous at 86 km |

## Lesson

**Rocket to orbit** checks the rocket equation on a sounding rocket, sweeps the pitch-over angle
to trade gravity against drag losses, finds max-Q, lowers it with a throttle bucket, and shows
why one stage cannot reach orbit.
