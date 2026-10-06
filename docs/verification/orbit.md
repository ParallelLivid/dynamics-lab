# Orbital Mechanics — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/orbit/index.html` (144 pictures before the fixes; `after-*.png` after
them: the geostationary ground track and Summary, the re-entry's Perturbations tab, and the
sun-synchronous orbit at Larger text in the light theme; run `dlab.dev.captureVerification("orbit")`
to make them again)

## Model as implemented

**Dynamics** (`simulateOrbit.m`): r'' = −μr/|r|³ with `ode45` (RelTol 10⁻¹⁰, AbsTol 10⁻¹²),
stopped by an event at the surface. Optional J2, the gradient of μJ2R²(3 sin²φ − 1)/(2r³) about
the spin axis (the frame's z turned by the axial tilt about y), and drag −½ρ(C_d A/m)|v_rel|v_rel
with v_rel against an atmosphere turning with the Earth and ρ from Vallado's Table 8-4 (every one
of its 28 bands checked against the book). With J2 the energy includes its potential and the
conserved momentum is the component along the spin axis.

**Frame:** a body-centred inertial frame whose XY plane is not the equator: the equator is tilted
by the axial tilt about Y (Earth 23.44°, so the frame is ecliptic-like). Elements can be measured
from either; the ground track uses the spin rate and tilt.

**Constants** (`bodyConstants.m`): μ, radii, spin rates, tilts, J2, orbits and speeds of the ten
bodies checked against the NASA fact sheets and the published J2 values. The radius is the mean
radius (equatorial at 1 bar for the giants), and it was also J2's reference radius, though Earth's
J2 = 1.08263·10⁻³ is defined with 6378.137 km (finding 2).

**Against the docs page and `about()`:** they match, except the docs said the mean radius is the
reference radius by design (now corrected).

## Reference values

Independent of the engine: Kepler's third law and the vis-viva energy, the hyperbolic Kepler
equation e sinh F − F = M (solved here), the first-order J2 secular rates, and my own drag
integration (scipy RK45, rtol 10⁻¹⁰, Vallado's table typed in separately, the atmosphere turning
about the tilted spin axis). μ = 398600.4418 km³/s².

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Defaults: a 6778 km, e 0.01 | T = 2π√(a³/μ) = 92.5576 min; altitudes 339.22 and 474.78 km | 92.558, 339.22, 474.778 | 0 | ✓ |
| Geostationary | T = 1436.06 min (a sidereal day, 86164 s); a point over the equator | 1436.06 min; before: a figure-eight to ±23.4° latitude | — | ✗ → ✓ (finding 1) |
| Molniya, a 26600 km, e 0.74 | T = 719.5851 min; altitudes 545 and 39913 km | 719.5851, 545, 39912.99 | 0 | ✓ |
| Escape: 7000 km, 12 km/s | ε = 15.05708 km²/s², a = −13236.31 km, e = 1.528848, v∞ = 5.4876 km/s; r(24 h) = 513596.6 km | −13236.31, 1.528848, 507225.6 km altitude (513596.6 km) | 0 | ✓ |
| Sun-synchronous, 700 km | cos i = −Ω̇☉/(1.5 n J2 (R/a)²): 98.1589° with R = 6378.137 (98.1773° with the mean radius) | before 98.177; after 98.159; theory rate 0.98566 °/day (the Sun 0.985647) | — | ✓ (finding 2) |
| … its momentum drift | conserved to the tolerance | before 2.6·10¹⁰; after 1.1·10⁻¹⁰ | — | ✗ → ✓ (finding 3) |
| J2 node rate, 6778 km circular, 51.6° | −1.5 n J2 (R/a)² cos i = −5.00269 °/day (−4.99150 with 6371 km) | theory −5.002692 (after); measured −5.026 | 0 (theory) | ✓ |
| Molniya with J2 at 63.435° | node −0.14698 °/day; periapsis −5.9·10⁻⁷ °/day (frozen) | theory −0.14698; measured −0.14559, periapsis −8.4·10⁻⁵ | measured vs first order | ✓ |
| Drag re-entry from 250 km, 51.6°, C_d A/m = 0.044 m²/kg | my integration: surface reached after 2.6241 days (42.29 periods) | 2.624108 days | 10⁻⁵ | ✓ |
| Lesson numbers | 92.6 min; 2^1.5 = 2.83 → 262 min; a sidereal day (a point); half a sidereal day | as stated (the point after finding 1) | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 2 s headless; every Summary number
reaches the metrics; every exported column has its units; no non-finite values; a second solve
gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs; undo, a scenario round trip, the exports and the
report; a GIF; Sweep, Map, Uncertainty and a short optimization; theme and text-size switches
keep the result.

### Tests

`tests/sims/orbit` (new: `geostationaryStaysOverOnePoint`, `j2UsesItsReferenceRadius`,
`inputsFitAndExplainThemselves`; the sun-synchronous test now expects 98.159° and a small
momentum drift), and for the shared changes to `cart2kep` and `bodyConstants` the physics tests
and the maneuvers, flyby, entry and rocket tests: 198 passed, 0 failed (the one failure on the
first run was the old 98.177°, updated); after the input fixes `TestOrbitPlugin` again (19), with
the maneuvers tests and `TestLessons`: 76 passed, 0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: two-body, J2 and drag terms, the rotating atmosphere, the frame and its tilt,
  and the constants checked by hand; J2's reference radius fixed (finding 2)
- [x] Numbers: every preset against Kepler, vis-viva, hyperbolic Kepler, J2 theory, and my own
  drag integration
- [x] Inputs: labels, units, ranges, tooltips (added for 18, finding 6), visibility (custom body,
  elements or position and velocity, drag inputs only for Earth); bodies load their orbits
- [x] Outputs: every tab readable in both themes and at Larger text; the re-entry plot (finding 5)
- [x] Summary and exports: angles and noise (finding 4); units everywhere
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on a and e; no Modes or Bode
- [x] Teaching: every lesson number checked; the geostationary step now true (finding 1)
- [x] Behaviour: readable errors (inside the body, too many points); an open trajectory says so;
  nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | The Geostationary and Molniya presets set their inclinations from the frame, which is tilted 23.44° to Earth's equator: the "geostationary" orbit was inclined 23.44° and its ground track a figure-eight from −23.4° to +23.4° (the lesson promised "a single point"), and Molniya's 63.4° was not to the equator. | Both are measured from the equator, as their definitions are. | `geostationaryStaysOverOnePoint` |
| 2 | Physics | J2 used the mean radius, 6371 km, as its reference radius, but Earth's J2 is defined with 6378.137 km: J2 effects were 0.22 % weak (the sun-synchronous inclination 98.177° for 98.159°). | `bodyConstants` gives each body's J2 reference radius (the equatorial radius), used by the orbit, its energy, and the J2 theory rows. | `j2UsesItsReferenceRadius`, `sunSynchronousPresetPrecesses` |
| 3 | Summary | With J2 the momentum drift was divided by max(h_z0, eps); a retrograde orbit has h_z < 0, so the sun-synchronous preset reported a "Max relative angular-momentum drift" of 2.6·10¹⁰ (and a polar orbit, h_z = 0, would too). | Relative to \|h\| at the start: 1.1·10⁻¹⁰. | `sunSynchronousPresetPrecesses` |
| 4 | Summary | Angles of 0 showed as 360 ("RAAN 360 deg", "True anomaly 360 deg": `mod` of a tiny negative angle rounds to 2π), and rounding noise showed as numbers (e = 2.3·10⁻¹⁶, ν = 3.4·10⁻¹² deg, lowest altitude −1.7·10⁻¹¹ km). | `cart2kep` wraps such angles to 0 (shared with the maneuvers and flyby); the Summary shows noise as 0. | `geostationaryStaysOverOnePoint` |
| 5 | Outputs | After a re-entry, the Perturbations tab's axes were set by the last minutes (the osculating a − R fell to −3200 km, the node swung 75°), which flattened the 2.6 days of decay into a line at the top. | After a re-entry the axes follow the flight above 100 km. | screenshots |
| 6 | Inputs | "Orbital eleme…" and "The frame (X…" were cut off, and 18 inputs had no tooltip. | "Elements" / "r and v", "Frame" / "Equator"; tooltips (what a is measured from, retrograde inclinations, the custom body's role as J2 radius). | `inputsFitAndExplainThemselves` |

Accepted:
- **Measured J2 drifts differ from first-order theory by about 0.5 %** (sun-synchronous 0.990
  against 0.9857 °/day): the theory uses the starting osculating elements, which differ from the
  mean elements by J2's short-period terms. The sun-synchronous orbit drifts 1.6° a year from the
  Sun's direction as a result.
- **The default orbit and the bodies' default orbits are measured from the frame** (documented as
  the default); the presets that are defined by the equator now use it.
- **At Larger text the Summary cuts off the surface-data credit** ("NASA Blue Marble Next
  Generation (publi…"); it is in the docs and the report.
