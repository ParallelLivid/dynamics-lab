# Nonlinear Oscillators

Three classic nonlinear oscillators, forced or free: limit cycles, jumps in a resonance curve,
period doubling, and chaos, read from phase portraits, Poincaré sections, and spectra.

## Models

| Model | Equation | Inputs |
|---|---|---|
| Duffing | x'' + δ x' + α x + β x³ = A cos ωt | δ, α, β |
| Van der Pol | x'' − μ (1 − x²) x' + x = A cos ωt | μ |
| Driven damped pendulum | θ'' + θ'/q + sin θ = A cos ωt | q |

All three share the forcing (A, ω; A = 0 turns it off, ω = 0 makes it a constant force) and the
start (x0, x0'). Time is in seconds, with the natural frequency of the Van der Pol oscillator and
the pendulum scaled to 1 rad/s (the Duffing's small-swing frequency is √α for α > 0); x is in
whatever unit the coefficients suit, θ in radians (0 hanging straight down).

**Integration:** the classical fourth-order Runge–Kutta method, with as many substeps between
output samples as the local time scale needs (each step at most 0.1 of it: the stiffness of the
spring, the damping, the drive frequency, and for the pendulum its rate of turning). The output
samples fall exactly on multiples of the drive period, so the stroboscopic section needs no
interpolation. Undamped energy is conserved to a few parts per million over hundreds of periods.

**Poincaré section:** when forced, the state once per drive period after the transient (θ
wrapped to (−π, π]); when free, the state at each maximum of x (where x' crosses zero from above:
the sample interval holding it is integrated again in fine steps, so the sharp maximum right after
a relaxation oscillation's jump is found too, then cubic Hermite interpolation and Newton's
method). The section points are clustered (tolerance 10⁻³ of the motion's size, θ on the circle):
one cluster is a period-1 motion, two period-2, and more than 32 is reported as chaotic (or
quasi-periodic). A free, damped run whose motion after the transient is below 10⁻⁶ of its size
is reported as settled to rest.

**Spectrum:** the amplitude spectrum of x after the transient (of θ' for the pendulum, whose
angle drifts when it goes over the top), with a Hann window and the peak refined by a parabola.

## Inputs

| Group | Inputs |
|---|---|
| Model | Model; δ, α, β (Duffing); μ (Van der Pol); q (pendulum) |
| Forcing | Amplitude A, frequency ω (rad/s) |
| Start | x0 (θ0), x0' (θ0') |
| Simulation | Duration in forcing periods (forced) or seconds (free); transient left out (%) |
| Numerics | Samples per period (per 2π s when free) |

**Presets:** a chaotic Duffing double well (δ = 0.3, α = −1, β = 1, A = 0.5, ω = 1.2), a
hardening Duffing resonance (δ = 0.1, α = 1, β = 0.1, A = 0.5, ω = 1.2: near the top of a peak
that leans to higher frequencies, amplitude 2.79; between ω ≈ 1.22 and 1.40 a large and a small
response coexist, and which one a run finds depends on its start), the Van der Pol limit cycle
(μ = 1), relaxation oscillations (μ = 5), entrainment (Van der Pol locked to the drive), and the
driven pendulum (q = 2, ω = 2/3) at A = 0.9 (period-1), 1.07 (period-2), and 1.5 (chaos).

## Outputs

- **Animation:** Duffing as a ball rolling in its potential well; Van der Pol as a point
  tracing the phase plane with a trail; the pendulum swinging, with an arrow for the drive.
- **Time series** (the transient greyed), **Phase portrait** (with the Poincaré points),
  **Poincaré map** (coloured by time; at least a tenth of the motion's size on each axis, so a
  periodic orbit shows as separate dots), **Spectrum** (log scale; ω, ω/2, and ω/3 marked), and
  **Potential** (V(x) with the ball; for the pendulum one turn, θ wrapped; Van der Pol has none).
- **Modes:** the free system linearized at rest (x = 0; for a Duffing double well, the bottom of
  the well on the side of x0; the pendulum hanging down). Modes are named Oscillation, Settling,
  Growing, or Unstable (saddle), as at the top of a double well's hump. Van der Pol's rest state
  is unstable: an Oscillation with damping ratio −μ/2 for μ < 2, two Growing modes for μ ≥ 2.
- **Summary:** the number of distinct Poincaré points (more than 32: chaotic or quasi-periodic),
  their largest spread, the steady amplitude ((max − min)/2 after the transient; none for a
  pendulum that turns over the top, its angle running on by more than a turn), the dominant
  frequency (none once a free run has settled), the forcing frequency, the limit-cycle amplitude
  and cycle period (free), and the energy at the end (Duffing and pendulum).
- **Export:** time (s), x (θ in rad for the pendulum), velocity (1/s; rad/s), and whether each
  sample is after the transient.
- **Sweeps:** "Poincaré x" (or θ) is a set-valued result: sweep A and plot it (all values) to draw
  a bifurcation diagram.

## Reference results (asserted by the tests)

Independent values from closed forms and separate high-accuracy integrations (see
[the verification sheet](../verification/nonlinear.md)).

| Check | Value |
|---|---:|
| Van der Pol μ = 1, free | limit-cycle amplitude 2.0086 ± 0.001, period 6.6633 ± 0.001 |
| Van der Pol μ = 0.1 | amplitude 2.000 ± 0.002; period 2π(1 + μ²/16) ± 10⁻⁴ |
| Van der Pol μ = 5; μ = 50 | period 11.61223, amplitude 2.02151; period 82.5083 (10⁻⁵), amplitude 2.00296, within 0.2 % of (3 − 2 ln 2)μ + 7.01 μ^(−1/3) |
| Undamped Duffing, from rest at X | period 4 K(m)/√(α + βX²), m = βX²/(2(α + βX²)), to 5·10⁻⁶ (hardening, softening, over the double well's hump); ω = 1 + 3βX²/8 for β = 0.04, X = 0.5 |
| Duffing β = 0, δ = 0, x0 = 0.01 | dominant frequency √α within 0.1 %; energy constant to 10⁻⁵ |
| Linear oscillator, forced | one section point exactly at the drive periods; amplitude 1 / \|α − ω² + iδω\| (10⁻⁴) |
| Pendulum q = 2, ω = 2/3 (Baker & Gollub) | A = 0.9: period-1; 1.07: period-2; 1.15 and 1.5: chaotic; 1.35, 1.45, 1.47: period-1, 2, 4 |
| Duffing δ = 0.1, α = 1, β = 0.1, A = 0.5, ω = 1.0 … 2.0 | from rest, the amplitude drops by more than half between neighbouring ω; swept with each run starting where the last ended, it jumps down between 1.40 and 1.45 going up and up between 1.25 and 1.20 coming down, as harmonic balance predicts (1.4005, 1.2165) |

## Lesson

**The route to chaos** shows a limit cycle, then the driven pendulum at period-1, period-2, and
chaos, and ends with a 121-run sweep of A that draws the bifurcation diagram.
