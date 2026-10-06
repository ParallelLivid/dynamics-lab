# Orbital Maneuvers

Plan and fly impulsive maneuvers between circular orbits: Hohmann and bi-elliptic transfers,
plane changes (alone or combined with a transfer), phasing for a rendezvous, and custom burn
lists. The Δv budget compares the alternatives.

## Model

`planManeuver` works out the burns analytically from the vis-viva equation
`v = √(μ (2/r − 1/a))`; `propagateBurns` then flies them: two-body coasting with `ode45`
(relative tolerance 10⁻¹¹), and each burn changes the velocity instantly by its Δv in the local
frame (prograde along v, normal along r × v, radial outward). A burn waits for its trigger: a time
after the previous burn, or the n-th periapsis, apoapsis, ascending node, or descending node after
it, located by ode45 events (r·v = 0 or z = 0, with direction). The start is a circular orbit at
its ascending node (on +x).

| Maneuver | Plan |
|---|---|
| Hohmann | a prograde burn at the start, and one at the far apsis of the half ellipse |
| Bi-elliptic | out to r_b, then a burn there to bring the periapsis to r₂, and a burn at r₂ to circularize |
| Plane change | a pure plane change at the node: Δv = 2 v sin(Δi/2) |
| Hohmann with plane change | each Hohmann burn also turns the plane; the split of Δi between them minimizes the total (`fminbnd`) |
| Phasing | a phasing orbit with period (2πk − Δθ)/(k n) for k revolutions, then back: catches a target Δθ ahead |
| Custom | the burns table: trigger, time or occurrence, and Δv components (m/s) |

The central bodies' μ and radii come from `dlab.physics.bodyConstants`.

## Inputs

| Group | Inputs |
|---|---|
| Mission | Central body (Earth, Moon, Mars, Venus, Mercury, Jupiter), maneuver (Hohmann, bi-elliptic, plane, combined, phasing, custom) |
| Orbits | Starting altitude and inclination; target altitude; intermediate apoapsis (bi-elliptic); inclination change; target phase and phasing revolutions |
| Burns | The custom burns table |
| Simulation | Coast after the last burn (orbits), output step |

**Presets:** LEO (300 km) to GEO by Hohmann (the default), LEO to GEO from Cape Canaveral's 28.5°
with the plane change combined, bi-elliptic beating Hohmann (r₂ = 20 r₁), phasing to catch a
target 30° ahead in GEO, a transfer to the Moon's distance, and a Hohmann transfer around Mars.

## Outputs

- **Animation** (3-D, a whole run in about 20 s): the body, the planned path dotted, the
  spacecraft and its trail, the target (phasing), and a flash at each burn.
- **Transfer:** the path in the starting orbit's plane, coloured by leg, with each burn's Δv as
  an arrow and its size. **3-D view:** the same in space.
- **Δv budget:** Δv per burn and the total, and the alternatives (Hohmann, bi-elliptic when the
  intermediate apoapsis lies beyond both orbits, Hohmann plus a separate plane change at the top,
  and the optimally combined plane change).
- **Altitude and speed**, and **Elements** (a, e, i over time), with the burns marked.
- **Summary:** Δv per burn, the total (planned and flown), the transfer time, the final a, e, and
  i against the plan, the Hohmann Δv, the bi-elliptic saving (positive when bi-elliptic is
  cheaper; only when its apoapsis lies beyond both orbits), the combined-plane-change saving and
  split, and the rendezvous miss (phasing).

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| LEO 300 km → GEO 35 786 km (Earth, radius 6371 km) | Δv₁ = 2.4277, Δv₂ = 1.4676, total 3.8952 km/s; 5.27 h |
| Hohmann flown | final a within 10⁻⁶ of r₂, e < 10⁻⁶; second burn half an ellipse after the first |
| Hohmann vs bi-elliptic | Hohmann cheaper at r₂/r₁ = 5 and 11; bi-elliptic cheaper at 16 and 30 |
| Plane change 28.5° at GEO | 2 · 3.0747 · sin 14.25° = 1.5137 km/s; final inclination within 10⁻⁸° |
| Combined plane change from 28.5° | cheaper than separate; final inclination 0 within 10⁻⁶° |
| Phasing 30° in GEO, one revolution | rendezvous within 1 km |
| Custom burns | the apoapsis burn happens at an apsis |

## Lesson

**Getting to geostationary orbit** builds the Δv budget to GEO: the Hohmann transfer, the cost of
a plane change in low orbit, combining it with the transfer, a sweep that finds where bi-elliptic
transfers win, and phasing for a rendezvous.
