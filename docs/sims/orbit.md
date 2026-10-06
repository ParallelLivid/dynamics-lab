# Orbital Mechanics

Two-body orbits around the planets, the Moon, the Sun, or a custom body, optionally perturbed by
the body's oblateness (J2) and by drag in Earth's atmosphere. Outputs include the 3-D trajectory,
a ground track, element histories, conservation diagnostics, and an animation.

![Orbital mechanics](../images/orbit.png)

## Model

```text
r'' = −μ r / |r|³
```

The orbit is integrated with ode45 in a body-centred inertial frame. The body's equator is tilted
from the frame's XY plane by its axial tilt, about Y. The run stops if the trajectory reaches the
surface. Closed orbits run for the chosen number of periods. Open (escape) trajectories run for
24 hours.

**Perturbations** (Perturbations group, both off by default, which keeps the two-body equations
exactly):

- **J2 oblateness**, the gravity of the equatorial bulge, about the spin axis
  (`dlab.physics.gravity`; the reference radius is the equatorial radius the coefficient is
  defined with, Earth's 6378.137 km, not the 6371 km mean radius the body is drawn with). To first order it turns
  the orbit's plane and its ellipse at the secular rates

  ```text
  Ω̇ = −1.5 n J2 (R/p)² cos i          ω̇ = 0.75 n J2 (R/p)² (5 cos² i − 1)
  ```

  with i measured from the equator. A sun-synchronous orbit has Ω̇ = 360° per year (i ≈ 98° in
  low orbit); at i = 63.43° the perigee stays put (Molniya orbits). With J2 the energy includes
  the J2 potential and the angular momentum is taken about the spin axis; both are conserved.
- **Atmospheric drag** (Earth only), a = −½ ρ (Cd A/m) \|v_rel\| v_rel, with the air turning with
  the Earth. The density is Vallado's exponential model (*Fundamentals of Astrodynamics and
  Applications*, Table 8-4, from CIRA-72), ground to 1000 km, in `dlab.physics.thermosphereDensity`.
  It is a mean model: the real thermosphere varies several-fold with solar activity. Low orbits
  decay and re-enter (the run stops at the surface).

**Elements measured from** the frame's XY plane (the default) or the body's equator. J2 acts about
the spin axis, so sun-synchronous and frozen orbits are set from the equator. Switching converts
the current orbit; the Elements tab and the Summary use the same plane.

**Conventions and limits:**
- The interface uses km, km/s, s, and degrees.
- The ground track uses a fixed tilt toward +X and constant spin. It has no date or ephemeris, so
  it is illustrative, not operational.
- Beyond J2 and drag there is no higher-order gravity, third-body gravity, solar radiation
  pressure, thrust, or relativity.
- For equatorial orbits, RAAN is 0 and periapsis is measured from +X. For circular orbits, the
  argument of periapsis is 0 and the true anomaly is the orbital phase.
- The animation may enlarge a small body to 4 % of the trajectory size for visibility. The physics
  uses its true radius.

## Inputs

| Group | Inputs |
|---|---|
| Central body | Mercury … Neptune, the Moon, the Sun, or Custom. Picking a body loads its default orbit and output step. |
| Custom body | μ, radius, spin rate, axial tilt |
| Custom body | (also) J2 |
| Initial orbit | Either orbital elements (a, e, i, RAAN, ω, ν), measured from the frame or the equator, or position and velocity. Switching converts the current orbit. |
| Perturbations | J2 oblateness; atmospheric drag (Earth), drag coefficient, area-to-mass ratio |
| Integration | Duration (orbits), output step (at most 20,000 samples) |
| Solver tolerances | Relative and absolute (collapsed by default) |
| Display | Show the central body, body surface (map or plain), relief exaggeration and Surface-tab colors (Earth and Mars) |

**Presets:** geostationary and Molniya (both measured from the equator), and an escape
trajectory (all around Earth); a sun-synchronous orbit at 700 km with J2 (i = 98.159° from the
equator, 30 orbits); Molniya with J2 at the critical inclination (a frozen perigee); and a re-entry
by drag from 250 km.

## Outputs

- **Animation:** trail, velocity arrow, and a rotating body, viewed in 3D, 2D XY, 2D XZ, or 2D YZ
  (the selector is in the playback bar). In 3D the body is a globe with its surface map, turning
  with its spin and tilt. A whole run plays in about 20 s at 1×.
- **Orbit** (3-D), **Ground track** (over the body's map), **Surface**, **Elements** (all six
  over time), and **Diagnostics** (energy and angular-momentum drift).
- **Surface:** the body close up in body-fixed axes, with relief exaggerated (25× by default)
  and colored by the map or by elevation, the ground track, and the point under the spacecraft
  at the playback time.
- **Perturbations** (when J2 or drag is on): the node Ω and periapsis ω from the equator over
  time, with the J2 theory's lines, and the altitude and semi-major axis.
- **Summary:** the initial elements, period, altitude range, samples, drift, and outcome; for
  Earth and Mars, the lowest altitude above the terrain under the track; the surface data's
  source; with J2, the node (and, for eccentric orbits, periapsis) drift measured and from theory;
  with drag, the change in semi-major axis, the mean decay rate, and the time to re-entry.
- **Sweeps:** the period, the altitude range, and those perturbation results are numeric results
  (sweep the inclination and plot the node drift, for example).

## Surfaces

| Body | Map | Elevation |
|---|---|---|
| Earth | NASA Blue Marble Next Generation imagery | SRTM topography (degree-90 spherical-harmonic model), relative to sea level |
| Mars | colored from its topography | MOLA topography (degree 90), relative to the mean radius without the polar flattening |
| Jupiter, Saturn, Uranus, Neptune | procedural latitude bands | — |
| Venus | procedural cloud swirls | — |
| Mercury, the Moon, the Sun, Custom | procedural mottling from the catalog color | — |

The files are in `resources/bodies` (about 280 kB), listed in its `manifest.json`, and rebuilt by
`tools/build_body_textures.py` from public-domain sources: Blue Marble NG from the
`basemap-data` package, and the SRTMP and MarsTopo719 coefficient files from the SHTOOLS example
data (BSD-3-Clause). A missing file falls back to a procedural surface. Topography is used for
display and the terrain clearance only: the dynamics treat the body as a sphere of its mean
radius.

## Reference results (asserted by the tests)

Three periods each, relative tolerance 10⁻¹⁰, absolute tolerance 10⁻¹².

| Body | Period | Output step | Samples | Max relative energy drift |
|---|---:|---:|---:|---:|
| Earth | 92.558 min | 30 s | 557 | < 2 × 10⁻¹⁰ |
| Moon | 122.63 min | 10 s | 2,209 | < 2 × 10⁻¹⁰ |
| Sun | ≈ 365.26 days | 7,200 s | 13,151 | < 2 × 10⁻¹⁰ |

Earth's default orbit spans 339.22–474.78 km in altitude.

| Perturbation check | Value |
|---|---:|
| No perturbations | identical to the two-body model |
| J2, 700 km, i = 98.159° | node drift 360°/year within 1 %; energy (with J2) and spin-axis angular momentum conserved to 10⁻⁸ |
| J2, 1000 km, e = 0.1, i = 30° | node and periapsis drift within 2 % of first-order theory |
| J2 at i = 63.435° (Molniya) | periapsis drift below 10⁻³ °/day |
| Drag, circular polar 400 km, Cd·A/m = 0.022 m²/kg | da/dt within 2 % of King-Hele's −ρ (Cd A/m) √(μa) |
| Drag from 250 km, Cd·A/m = 0.044 m²/kg | re-enters after 2.6 ± 0.5 days |
