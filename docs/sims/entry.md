# Atmospheric Entry

A capsule coming home: the deceleration pulse, stagnation-point heating, skipping back out of
the atmosphere, and the narrow entry corridor between the two. A ballistic entry in an exponential
atmosphere reproduces the classic Allen–Eggers solution.

## Model

Planar flight over a spherical, non-rotating Earth (μ = 398 600.4418 km³/s², R = 6371 km, from
`dlab.physics.bodyConstants`). States: altitude h, speed V, flight-path angle γ (negative when
descending), and downrange s along the surface:

```text
dV/dt   = −D/m − g sin γ
V dγ/dt = L/m − (g − V²/r) cos γ
dh/dt   = V sin γ
ds/dt   = (R/r) V cos γ
```

with r = R + h, g = μ/r², D/m = ρV²/(2β), β = m/(C_D S) the ballistic coefficient, and
L/m = (L/D)(D/m) cos σ for the bank angle σ (0 lift up, 180° lift down). Only cos σ enters a
planar model, so a bank reversal (σ → −σ) changes nothing except during the roll.

- **Atmosphere:** standard (`dlab.physics.thermosphereDensity`, CIRA-72 bands from Vallado) or
  exponential ρ = 1.225 e^(−h/H) with the scale height H (default 7.2 km).
- **Heating:** Sutton–Graves at the stagnation point, q̇ = k √(ρ/r_n) V³ with
  k = 1.7415 × 10⁻⁴ (SI) and the nose radius r_n; the heat load ∫ q̇ dt is integrated with the
  trajectory.
- **Deceleration:** the aerodynamic load |L + D|/m = (D/m) √(1 + (L/D)²), in g (what the crew
  feels).
- **Energy:** lift does no work, so V²/2 − μ/r falls by exactly the drag work ∫ (D/m) V dt, which
  is integrated too (the summary's "Energy dissipated").
- **Stops:** the ground, parachute deploy (the Mach number, from the ISA speed of sound, extended
  above 86 km, falls below the chosen value), a skip-out (climbing back above the entry altitude),
  or the time limit.

**Integration:** `ode45` (relative tolerance 10⁻⁹) with terminal events for the stops. The peaks
of deceleration, heating, and dynamic pressure are refined by a parabola through three samples.

**Allen–Eggers** (ballistic, γ constant, no gravity, exponential atmosphere):

```text
V(h)  = V_E exp(−ρ(h) H / (2 β sin|γ_E|))
a_max = V_E² sin|γ_E| / (2 e H),  where ρ = β sin|γ_E| / H
```

The peak does not depend on β, only its altitude does. The engine has `gravity` and `curvature`
switches (tests only) under which it reduces exactly to these assumptions.

## Inputs

| Group | Inputs |
|---|---|
| Entry | Entry speed, flight-path angle (−90° to 0°), entry altitude (default 120 km) |
| Vehicle | Ballistic coefficient m/(C_D S), L/D, bank angle (schedule), nose radius |
| Atmosphere | Standard or exponential; scale height (exponential) |
| Stop | Stop at parachute deploy; deploy below Mach (default 0.8) |
| Simulation | Time limit, output step |

**Presets:** an Apollo-like lunar return (11 km/s, −6.5°, β = 350 kg/m², L/D 0.3, lift up until
80 s, then rolled to 90°; the default), a Soyuz-like ballistic return from the ISS (7.6 km/s,
−1.5°, about 9 g), a steep ballistic entry (−15°, over 40 g), a ballistic entry in the
exponential atmosphere for the Allen–Eggers comparison (7.5 km/s, −20°, β = 300 kg/m²), a shallow
skip-out (−4.5°, lift up), and a corridor pair with the lunar-return bank schedule: too shallow
(−5.6°, skips) and too steep (−7.4°, 11.5 g).

## Outputs

- **Animation:** the capsule along its path over the curved Earth (true scale), heat shield first,
  with a glow and wake that grow with the heating rate, the entry interface, and a readout of time,
  altitude, speed, Mach, g, and q̇.
- **Altitude–velocity** (with the peak deceleration and peak heating, and the Allen–Eggers curve
  for the exponential atmosphere), **Deceleration** (g against time, with the Allen–Eggers peak for
  ballistic exponential runs), **Heating** (q̇ in W/cm² and the heat load in kJ/cm²),
  **Dynamic pressure**, and **Trajectory** (altitude against downrange, and γ against time).
- **Summary:** peak deceleration and its altitude, peak heating rate and its altitude, heat load,
  peak dynamic pressure, flight time, downrange, final speed and altitude, energy dissipated, and
  whether the capsule skipped out. Ballistic runs (L/D = 0) add the ballistic estimate of the peak
  deceleration, the Allen–Eggers formula with the scale height H, for comparison. Lifting runs
  leave it out: lift holds the capsule high and the formula no longer applies. Even for a ballistic
  run it is only an estimate: at a shallow angle gravity and the Earth's curvature steepen the path,
  so a Soyuz-like −1.5° entry pulls about 9 g against the formula's 4 g.
- **Keep previous runs** overlays the altitude–velocity map, deceleration, heating, and trajectory.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Allen–Eggers V(h), exponential atmosphere, no gravity, flat Earth (7.5 km/s −20° β 300; 11 km/s −45° β 100; 6 km/s −8° β 1000) | within 10⁻⁴ |
| Allen–Eggers peak deceleration, same cases | within 10⁻³; altitude within 0.01 H |
| 7.5 km/s, −20°, β = 300 kg/m², H = 7.2 km | 50.118 g at 32.07 km |
| No gravity over a round Earth | the path is a straight line (1 m); γ at the ground = −acos((R + h_E) cos γ_E / R) |
| Energy V²/2 − μ/r + drag work | constant to 10⁻⁷ of the entry kinetic energy |
| Soyuz-like ballistic (7.6 km/s, −1.5°, β = 400) | 8–11 g; L/D 0.3 at least halves it, with a larger heat load |
| Peak deceleration at −2°, −5°, −10°, −20° | increasing |
| Lunar return at −4.5°, lift up | skips out above 10 km/s |
| Lunar-return default | captured, 5–9 g, stops at Mach 0.8 |
| Sutton–Graves | q̇ = k √(ρ/r_n) V³ exactly; heat load = ∫ q̇ dt (10⁻⁴); 4× the nose radius halves q̇ |

## Lesson

**Coming home** compares a ballistic peak deceleration with the Allen–Eggers formula, steepens the
entry to show the load growing with sin|γ|, adds lift to a Soyuz-like capsule to cut its load from
9 g to 3 g, makes a lunar return too shallow so that it skips out, and finds an angle inside the
corridor (about −5.7° to −7.1° with this bank schedule) that neither skips nor exceeds 10 g.
