# Rigid-Body Rotation

A body tumbling freely in space, or a heavy spinning top on a pivot: the intermediate-axis
(tennis racket) theorem, the polhode, precession, and nutation.

## Model

```text
I ω' = (I ω) × ω + τ          Euler's equations, body axes (I = diag(I₁, I₂, I₃))
q'   = ½ q ⊗ [0; ω]          attitude quaternion, body to world (scalar first)
```

- **Free body:** τ = 0, inertias about the centre of mass (each at most the sum of the other two).
  The body starts turned so that its angular momentum points along world z, so L stays vertical
  in the animation.
- **Spinning top:** a symmetric top on a pivot at the origin (z up), the centre of mass at
  distance l along the body z axis, I = diag(I_t, I_t, I_s) about the pivot (I_s at most 2 I_t),
  and `τ = [0 0 l] × (Rᵀ [0 0 −m g])`. The start is given by Z-X-Z Euler angles: tilt θ₀ from the
  upward vertical and the initial rates φ' (precession) and θ' (nutation), with the body spin ω₃
  (constant). The motion depends on m, g, and l only through m g l.

Integrated with `ode113` (relative tolerance 10⁻¹¹); the quaternion's norm is held at 1 by a small
correction term. Energy and |L| (or L_z and L₃ for the top) drift by less than 10⁻⁹.

**Flips** (free body) are turnovers of the intermediate axis (by inertia, whichever body axis it
is) relative to L: from within 60° of L to within 60° of −L, or back, so a small wobble is not a
flip. With two equal inertias there is no intermediate axis. The top's Euler angles come from the
rotation matrix (φ and ψ unwrapped); its precession rate is a straight-line fit of φ(t), and its
nutation amplitude is half the range of θ.

**Steady precession** of the top at the start tilt θ is the slow root of

```text
I_t cos θ Ω² − I_s ω₃ Ω + m g l = 0
```

which tends to the gyroscopic estimate m g l / (I_s ω₃) for a fast top. Below
ω₃ = 2 √(I_t m g l cos θ) / I_s there is none. Upright, the top is stable ("sleeps") above
ω₃ = 2 √(I_t m g l) / I_s (140 rad/s for the presets' top). A fast top nods (nutates) at about
I_s ω₃ / I_t.

## Inputs

| Group | Inputs |
|---|---|
| Body | Free body or spinning top; I₁, I₂, I₃ (free); mass, pivot to centre of mass, I_s, I_t about the pivot, gravity (top) |
| Start | ω₁, ω₂, ω₃ and the spin axis that Modes and the Axis trace use (auto: the body axis nearest L) (free); spin rate, tilt (°), initial precession and nutation rates (top) |
| Simulation | Duration, output step |

**Presets:** the tennis racket (I = 1, 2, 2.5 kg·m²; ω = [0.001 10 0.001] rad/s; 20 s), stable
spin about the major and minor axes, a symmetric body's free precession, a fast top (400 rad/s),
a top with looping nutation (80 rad/s, started precessing backwards; it dips below the
horizontal, so it is drawn on a stand), and a sleeping top (300 rad/s, 2° from upright, above its
stability limit).

## Outputs

- **Animation** (3-D, drag to rotate): a box with sides from the inertias
  (a_i ∝ √(I_j + I_k − I_i), faces coloured by axis), or a cone with its axle on the floor (on a
  stand when it would dip below its tip); the L arrow, the ω arrow, and a trail of the spin axis's
  tip.
- **Angular velocity** (body axes), **Angular momentum** (world axes; about the pivot for the top),
  **Conservation** (relative change of energy, |L| or L_z and L₃, and the quaternion norm, on log
  axes).
- **Polhode** (free body): ω in body axes on the energy ellipsoid Σ I_i ω_i² = 2E and the momentum
  ellipsoid Σ I_i² ω_i² = L²; the motion follows their intersection.
- **Nutation and precession** (top): the tilt θ(t), and φ'(t) with its mean, the steady rate, and
  the gyroscopic estimate.
- **Axis trace:** the spin axis's tip on the unit sphere.
- **Modes** (free body): the linearization about steady spin about the spin axis. Modes are a
  Wobble (stable), a Tumble (unstable) with its decaying partner, or the neutral Spin itself:
  spin about the intermediate axis tumbles.
- **Summary:** energy and momentum drift; flips, time between flips, the spin axis and whether
  spin about it is stable ("neutral" when another inertia equals it) (free); precession rate, the
  steady precession rate, the gyroscopic estimate, nutation amplitude, and largest tilt (top).

## Reference results (asserted by the tests)

Independent values: closed forms, and my own integrations (SciPy DOP853 with a rotation matrix for
the free body, and Lagrange's equations in Euler angles for the top).

| Check | Value |
|---|---:|
| Symmetric body (I = 2, 2, 3; ω = [0.5 0 4]) | ω₁ + iω₂ turns at (I₃ − I₁)/I₁ · ω₃ = 2 rad/s in the body; axis 3 turns about L at \|L\|/I₁ = 6.0208 rad/s (10⁻⁹) |
| Spin about the intermediate axis | Tumble with λ = ω √((I₂ − I₁)(I₃ − I₂)/(I₁ I₃)) = 4.472 s⁻¹ (10⁻⁸) |
| Spin about the major or minor axis | Wobble at ω √((I₃ − I₁)(I₃ − I₂)/(I₁ I₂)) = 6.124, ω √((I₂ − I₁)(I₃ − I₁)/(I₂ I₃)) = 5.477 rad/s |
| Tennis racket (I = 1, 2, 2.5; ω = [0.001 10 0.001]) | 4 flips in 20 s, 2K(k)/rate = 4.9583 s apart (10⁻⁴); L fixed in space to 10⁻⁹ |
| Fast top (400 rad/s, 30°) | steady rate 2.5213 rad/s; mean precession 2.5200 (gyroscopic 2.4525); nutation period 0.0830 s (I_s ω₃/I_t: 0.0785 s) |
| Looping nutation (80 rad/s, φ'₀ = −3 rad/s) | mean precession 8.4226 rad/s, nutation amplitude 43.42°, largest tilt 116.85° (10⁻⁵) |
| Top started at either steady precession rate | nutation < 10⁻⁶ rad |

## Lesson

**The tennis racket theorem** compares spin about the major, minor, and intermediate axes on
the Modes tab, shows the flips, and measures a top's precession.
