# Quarter-Car Suspension

One corner of a car driving over a speed bump, a pothole, a kerb, wavy or rough road: how the
suspension trades ride comfort (body acceleration) against road holding (tire load).

## Model

```text
m_s z_s'' = −k_s (z_s − z_u) − c_s (z_s' − z_u')
m_u z_u'' =  k_s (z_s − z_u) + c_s (z_s' − z_u') + F − W
F = W − k_t (z_u − z_r) − c_t (z_u' − z_r')        the tire load (F ≥ 0 with lift-off)
```

The body (sprung mass m_s, a quarter of the car) rides on the suspension spring k_s and damper
c_s above the wheel (unsprung mass m_u), which rides on the tire (k_t, c_t). Heights are measured
from rest, W = (m_s + m_u) g is the static tire load, and the wheel meets the road height z_r at
distance s = V t. With **Tire can leave the road** on, the tire can push but not pull, so the
wheel lifts off when its load reaches zero; with it off the tire may pull the road (a negative
load), which the status line and the Summary point out.

The equations are integrated with the classical fourth-order Runge–Kutta method at a fixed step
that resolves the road's features and the fastest mode (and divides the output step); the road
is known in advance, so it is evaluated once for all steps. At most 2 million output samples and
5 million steps.

**Roads:** a bump or pothole (half sine of the given height and length), a kerb (a 5 cm
raised-cosine ramp), a wavy road (sine of the given amplitude and wavelength), or a rough road
following ISO 8608: displacement PSD `G(n) = G(n₀) (n / n₀)⁻²` with n₀ = 0.1 cycles/m and
`G(n₀) = 16 · 4^(k−1) × 10⁻⁶ m³` for classes A–H, built from 200 cosines at log-spaced spatial
frequencies (0.011–2.83 cycles/m) with phases from a fixed generator, so each seed is one
reproducible stretch of road. Every road is flat up to **Distance to the feature**.

**Linear analysis:** the undamped natural frequencies in the Summary come from `K φ = ω² M φ`
(1.238 and 11.81 Hz for the defaults). The Modes tab gives the damped modes' natural frequencies
|λ| (7.899 and 73.09 rad/s, 1.257 and 11.63 Hz), so the two differ a little.

## Inputs

| Group | Inputs |
|---|---|
| Car | Body mass (quarter), wheel mass, suspension spring, damper, tire stiffness, tire damping |
| Road | Speed (km/h), road type; height (cm), length, wavelength, ISO class, seed (as the type needs); distance to the feature; tire can leave the road |
| Simulation | Duration, output step |

**Presets:** a passenger car over a speed bump at 20 km/h (6 cm, 1 m long), a stiff sports car,
a heavy soft truck, worn dampers, a rough road (ISO class D at 80 km/h), and wheel-hop resonance
(1 cm waves 1.5 m apart at 64 km/h, which the wheel meets at its hop frequency).

## Outputs

- **Animation** (half speed): the road scrolls under a fixed car; the wheel rolls, and the tire
  spring, suspension spring, damper, and body move with the solution. The wheel turns red when it
  leaves the road.
- **Body and wheel** (heights over time, with the road under the tire), **Body acceleration**
  (with ± RMS lines), **Suspension travel and tire load** (with the static load; lift-off marked),
  and **Road profile**.
- **Bode** (in Analyze): the linear response to road height, in hertz: body height (the
  transmissibility), body acceleration, suspension travel, and tire deflection (times k_t, the
  dynamic tire load when the tire has no damping), with the body-bounce and wheel-hop frequencies
  marked, and the road's excitation frequency V/λ for a wavy road.
- **Modes:** the 4-state linear model at rest; each mode is named Body bounce or Wheel hop by
  which mass carries most of its kinetic energy.
- **Summary:** RMS and peak body acceleration, maximum suspension travel, RMS dynamic tire load
  over the static load, minimum tire load, whether the wheel left the road and for how long (and how
  long the tire pulled the road, when lift-off is off), the undamped body-bounce and wheel-hop
  frequencies, the suspension damping ratio ζ = c_s / 2√(k_s m_s), and the static load. RMS values
  are over the whole run, the flat road before the feature included, so compare runs of the same
  duration. The acceleration is unweighted (ISO 2631's comfort weighting is not applied).
- **Export:** time, distance, road, body and wheel heights (m), body acceleration, suspension
  travel, and tire load, each with its units.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Natural frequencies (m_s 300, m_u 40, k_s 20 000, k_t 200 000) | roots of det(K − ω²M) = 0 to 10⁻¹⁰: 1.238 and 11.81 Hz |
| Body response at 0.1 Hz | 1 within 1 % (the body follows slow road changes) |
| Steady 1 cm sine at 1 Hz | body amplitude equals the frequency response within 0.5 % |
| 6 cm bump at 10 vs 60 km/h | peak body acceleration more than doubles |
| Same bump at 80 km/h | the wheel lifts off (the tire load never goes below 0; without lift-off it does) |
| Rough road, class C | band-averaged PSD slope −2 ± 0.2, G(0.1) = 256 × 10⁻⁶ m³ within 15 %; the same seed gives the same road |

## Lesson

**Comfort or grip: tuning a suspension** finds the two natural frequencies, drives over the speed
bump faster, sweeps the damper (comfort is best near ζ = 0.17, road holding near 0.24), and shows
worn dampers and wheel-hop resonance lifting the wheel off the road.
