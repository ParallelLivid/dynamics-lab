# Vibrating String and Beam

A plucked or struck string, or a beam, vibrating in its natural modes: standing waves,
harmonics, and how the pluck point and the supports decide which modes sound.

## Model

```text
String:  ρ ∂²u/∂t² = T ∂²u/∂x²         c = √(T/ρ),  f_n = n c / 2L (both ends fixed)
Beam:    ρA ∂²u/∂t² = −EI ∂⁴u/∂x⁴      ω_n = (β_n L)² √(EI/ρA) / L²
```

The length is divided into finite elements: linear elements for a string (with the average of the
consistent and lumped mass matrices, which makes its frequencies fourth-order accurate), and
Hermite cubic elements with deflection and slope at each node for a beam. The natural modes come
from `K φ = ω² M φ` (`eig`). The motion is the sum of the modes, each solved exactly in time and
decaying with the same damping ratio ζ, so undamped energy is conserved to rounding.

**Supports:** a string has both ends fixed, or one fixed and one free. A beam is pinned–pinned
(β_n L = nπ: overtones 1 : 4 : 9), a cantilever (1.875, 4.694, …: 1 : 6.27 : 17.5),
clamped–clamped, or free–free (4.730, …), which also has two rigid-body modes; a free bar's
drift and spin are left out, as if it rested on soft supports.

**Start:** a pluck, a strike (a Gaussian initial velocity), a single mode, or a Gaussian bump. A
plucked string starts as a triangle with its peak at the pluck point (with a free end, a ramp):
the shape a string takes when pulled aside at one point. A plucked beam starts from its static
deflection under a point load at the pluck point (for a free bar, its elastic deflection about its
rigid-body motion), solved from the same finite elements; a beam cannot hold a string's kink. A
start at a node of a mode cannot excite that mode. A strike or bump narrower than about three
elements is not fully resolved: the struck string's 200 elements give 2 % less energy than 800.

## Inputs

| Group | Inputs |
|---|---|
| Medium | String or beam, length; tension and mass per length, or EI and mass per length; ends (both fixed, fixed–free) or supports (pinned, cantilever, clamped, free–free); damping ratio (%) |
| Excitation | Pluck, strike, one mode, or bump; amplitude (m, or m/s for a strike), position and width (× L), mode number |
| Numerics | Elements (4–800) |
| Simulation | Duration, output step, probe position |
| Display | Mode shapes shown |

**Presets:** guitar string (plucked near the bridge, about 263 Hz), pluck at the middle, a single
mode n = 3, a struck string, a cantilever beam (a 30 cm steel ruler, about 9 Hz), and a free–free
bar (an aluminium xylophone key, about 580 Hz).

## Outputs

- **Animation** (slow motion: a whole run in about 10 s): the displaced string or beam, its
  supports, and the probe.
- **Space-time** (displacement over position and time), **Mode content** (the share of energy in
  each mode, with its frequency), **Mode shapes**, **Energy** (kinetic, potential, total), and
  **Probe** (the motion at the probe position and its spectrum, with the mode frequencies marked).
- **Summary:** the fundamental, f2/f1 and f3/f1, the wave speed (string), the dominant mode,
  the energy share of modes 1–6, the energy remaining at the end, and the number of rigid-body
  modes.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| String, 65 cm, 70 N, 0.6 g/m, 200 elements: f₁ | c / 2L = 262.74 Hz (within 0.05 %); f_n / f₁ = n (0.1 %) |
| Pluck at L/2 / at L/5 | even modes / mode 5: less than 10⁻¹² of the energy |
| Undamped string after 2L/c | back to its starting shape within 1 % of the amplitude |
| Undamped energy | constant to 10⁻¹⁰ |
| Beam (EI = 2, ρA = 0.5, L = 1, 100 elements): pinned, cantilever, clamped, free | f₁ within 10⁻⁴; overtone ratios 1 : 4 : 9 and f₂/f₁ = 6.2669 (cantilever) |
| Plucked beam | energy P δ / 2 (cantilever 3 EI δ²/2a³, pinned 3 EI L δ²/2a²b²) on 30 and 120 elements (10⁻⁵); the ruler 97.3 % in mode 1; clamped and free bars the same on 50 and 200 elements |
| Gaussian bump on a clamped beam | energy EI/2 ∫ u''² dx = 0.0338395 J (10⁻⁴) |
