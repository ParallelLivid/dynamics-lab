# Orbital Maneuvers — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/maneuvers/index.html` (135 pictures before the fixes; `after-*.png`
after them: the lunar transfer's Δv budget and Summary, and the inputs at Larger text in the
light theme; run `dlab.dev.captureVerification("maneuvers")` to make them again)

## Model as implemented

**Planning** (`planManeuver.m`): vis-viva speeds for Hohmann (burns at the start and the far
apsis) and bi-elliptic transfers (out to r_b, raise the periapsis there, circularize at r₂);
a pure plane change at the node, Δv = v[cos Δi − 1, sin Δi, 0] in (prograde, normal, radial);
a combined transfer whose two burns also turn the plane, each Δv from the law of cosines, the
split chosen by `fminbnd` (the second turn has the opposite sign, because the far apsis is the
descending node); phasing with a period (2πk − Δθ)/(kn) for k laps. I derived the phasing period
and the combined burns' components independently and they agree.

**Flying** (`propagateBurns.m`): two-body `ode45` (RelTol 10⁻¹¹) between impulsive burns, each
waiting for its trigger (a time, or the n-th apsis or node, found by event functions on r·v and
z), applied in the local frame (prograde along v, normal along r × v, radial completing it,
outward on a circle).

**Against the docs page and `about()`:** they match.

## Reference values

Independent of the engine: vis-viva and the law of cosines written out here; the combined
transfer's best split found by a dense scan (2·10⁶ points) instead of `fminbnd`; the phasing orbit
from Kepler's third law. μ = 398600.4418 km³/s², R = 6371 km.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| LEO 300 km → GEO (Hohmann) | Δv 2.427654 + 1.467573 = 3.895227 km/s; 5.27275 h | 2.427654, 1.467573, 3.895227; 5.272747 h; flown 3.895227, final a within 4·10⁻¹¹, e 4·10⁻¹² | 0 | ✓ |
| … bi-elliptic via 100 000 km | 4.272962 km/s (a saving of −0.37774) | −0.3777351 | 0 | ✓ |
| Combined from 28.5° | best split 2.19835° at the first burn, total 4.23379 km/s; all at the top 4.258407; separate 5.409031 | −2.198351° (turning down), 4.23379; combined saving 1.175241 = 5.409031 − 4.23379 | 0 | ✓ |
| Bi-elliptic, r₂ = 20 r₁, r_b = 40 r₁ | 4.063068 km/s against Hohmann 4.133416: 70.35 m/s cheaper; 193.65 h | 3.067689 + 0.727985 + 0.267393 = 4.063068; saving 0.0703478; 193.6534 h | 0 | ✓ |
| Phasing 30° ahead in GEO, one lap | period 21.9343 h, a 39781.15 km, 2 × 93.2353 = 186.471 m/s; perigee at 31034 km | 93.23532 each, 21.93433 h; rendezvous miss 8.6·10⁻⁷ km | 0 | ✓ |
| Lunar distance, 384 400 km | 3.938403 km/s, 4.9797 days | 3.938403, 119.5135 h | 0 | ✓ |
| Mars 300 → 17 032 km | 1.674334 km/s, 5.5816 h (areostationary radius 20 428 km) | 1.674334, 5.581614 h | 0 | ✓ |
| Plane change 10° at 300 km | 2 v sin 5° = 1.347409 km/s | 1.347409; final i 38.5° | 0 | ✓ |
| Lesson numbers | 3.895 (2.428 + 1.468, 5.3 h); 28.5° in LEO 3.805 km/s; combined 4.23, 0.34 more, 26.3° at the top; the crossover between 11.94 and 15.58; a rendezvous within 1 km | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.4 s headless; every Summary number
reaches the metrics; every exported column has its units (the eccentricity is dimensionless); no
non-finite values; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 14.8 s for the first run while MATLAB warms
up, median 4.2 s); undo and redo of the starting altitude; a scenario round trip; CSV, MAT, plot
and report exports (7 images); a 10-frame GIF; a sweep of the starting altitude; a map of the two
altitudes; uncertainty; a short optimization of burn 1; theme and text-size switches keep the
result.

### Tests

`tests/sims/maneuvers` (new: `inputsFitAndExplainThemselves`, `noBiellipticInsideTheTarget`) with
`TestOrbitPlugin` and `TestLessons`: 76 passed, 0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: vis-viva, the burn frames, the combined split, phasing, and the event triggers
  checked by hand; docs and `about()` match
- [x] Numbers: every preset and a plane change against the references; every flown orbit ends on
  its target
- [x] Inputs: labels, units, ranges, tooltips (added for seven, finding 3), visibility by maneuver
- [x] Outputs: every tab readable in both themes and at Larger text; burns marked
- [x] Summary and exports: units only in the units column (finding 2); the alternatives
  (finding 1)
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on the altitudes; the lesson's
  bi-elliptic sweep
- [x] Teaching: every lesson number checked (all right)
- [x] Behaviour: readable errors (below the surface, an intermediate apoapsis inside the orbits,
  a phasing orbit into the ground, a trigger that never comes); nothing left behind

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Summary | When the intermediate apoapsis lies inside the target (the lunar transfer: 100 000 km against 384 400 km) there is no bi-elliptic transfer, but the planner clamped r_b to r₂ and reported its Hohmann: "Bi-elliptic saving 0 km/s", and an Alternatives bar equal to the Hohmann's. | No bi-elliptic alternative then: no row and no bar. | `noBiellipticInsideTheTarget` |
| 2 | Summary | "Final a error" had "relative" in the units column. | "Final a error (relative)", no units. | `noBiellipticInsideTheTarget`, `hohmannToGeo` |
| 3 | Inputs | The maneuver choices were cut off ("Hohmann tra…", "Hohmann with plane change"), and seven inputs had no tooltip. | "Hohmann", "Bi-elliptic", "Plane", "Combined", "Phasing", "Custom", explained in the tooltip; tooltips for the body, inclinations, target altitude, revolutions, coasting and the output step. | `inputsFitAndExplainThemselves` |

Accepted:
- **The Elements tab's three plots are not exactly aligned** (the y tick labels differ in width);
  each reads correctly.
- **The tiny final eccentricity and inclination errors** (10⁻¹² and 10⁻¹⁰) are shown as numbers:
  they report how closely the flown orbit meets the plan.
