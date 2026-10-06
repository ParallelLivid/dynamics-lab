# Three-Body Problem

Two models: a small body moving near two primaries on circular orbits (the circular restricted
three-body problem, with its Lagrange points and zero-velocity curves), and the general problem of
2 to 8 bodies under their mutual gravity (choreographies and chaos).

## Models

**Restricted (CR3BP).** Units: the primaries' separation, their total mass, and 1/(their angular
rate), so G = 1 and the primaries go round in 2π. In the frame rotating with them, the primaries
sit at (−μ, 0) (mass 1 − μ) and (1 − μ, 0) (mass μ):

```text
ẍ − 2ẏ = ∂Ω/∂x,   ÿ + 2ẋ = ∂Ω/∂y,   z̈ = ∂Ω/∂z,     Ω = ½(x² + y²) + (1 − μ)/r₁ + μ/r₂
C = 2Ω − v²   (the Jacobi constant, conserved)
```

Systems: Earth–Moon (μ = 0.01215058, 384 400 km, 27.32 days per orbit), Sun–Earth
(μ = 3.0035 × 10⁻⁶), Sun–Jupiter (μ = 9.5388 × 10⁻⁴), or a custom mass ratio. For the real
systems the primaries have their physical radii, and hitting one ends the run; distances and the
duration are also given in km and days.

The **Lagrange points** L1–L3 solve the collinear equation (`fzero`, bracketed); L4 and L5 are at
(½ − μ, ±√3/2). The **forbidden region** is where 2Ω < C (a body there would need a negative
kinetic energy); its edge is the zero-velocity curve.

**N bodies** (G = 1): `r̈_i = Σ_j m_j (r_j − r_i) / (|r_j − r_i|² + ε²)^(3/2)`, with an optional
softening length ε, the bodies entered as a table (mass, position, velocity).

Both are integrated with `ode113` (relative and absolute tolerances 10⁻¹²).

## Inputs

| Group | Inputs |
|---|---|
| Model | Restricted or N bodies; primaries and the custom mass ratio |
| Start (rotating frame) | x₀, y₀, z₀, ẋ₀, ẏ₀, ż₀ |
| Bodies | The bodies table (2–8 rows: m, x, y, z, vx, vy, vz), softening |
| Simulation | Duration and output step (time units: 2π is one orbit of the primaries); the Lagrange point for the Modes tab |
| Display | Animation frame (rotating or inertial), shade the forbidden region, show the Lagrange points |

**Presets:** the Arenstorf orbit (the default; μ = 0.012277471, period 17.065), a tadpole orbit
around Earth–Moon L4, a planar Lyapunov orbit around L1 (found by differential correction:
x₀ = 0.8234, ẏ₀ = 0.126232, period 5.4858, twice the half-period 2.7429 the correction finds), a path through the L1 neck to the Moon, a Sun–Jupiter
Trojan, the figure-8 choreography, Lagrange's equilateral triangle (three equal masses, which
eventually break up), and the Pythagorean three-body problem (masses 3, 4, 5 at rest).

## Outputs

- **Animation:** the primaries and the body with a trail, in the rotating or inertial frame; or
  all N bodies, sized by mass^(1/3), with trails. A whole run plays in 20 s.
- Restricted: **Trajectory** (rotating frame, primaries, Lagrange points, the forbidden region
  shaded and the zero-velocity curve at C₀), **Inertial view**, **Jacobi constant** (drift on log
  axes), and **Distances** to each primary.
- N bodies: **Trajectories**, **Energy and momentum** (drift), and pairwise **Distances**.
- **Modes** (restricted): the exact linearization at rest at the chosen Lagrange point (from the
  second derivatives of Ω). Modes are a saddle (its growing and its decaying direction), In-plane
  oscillation (growing or decaying beyond Routh's mass ratio 0.0385 at L4/L5), or Out-of-plane
  oscillation. Rates and periods are in the model's time units (for Earth–Moon one time unit is
  4.348 days, a sidereal month over 2π).
- **Summary:** the Jacobi constant and its drift, the closest approach to each primary (also in
  km), the return error (how far the final state is from the start), C at L1 and L2, the x of
  L1–L3, and the duration in days; for N bodies the energy, momentum, and angular momentum drift,
  the closest approach, and the return error.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Earth–Moon L1, L2, L3 | x = 0.836915, 1.155682, −1.005063 |
| Arenstorf orbit, one period | returns within 10⁻⁶ |
| Jacobi constant over 10 Arenstorf periods | drift < 10⁻¹⁰ |
| Exact Jacobian | matches finite differences of the equations |
| L4, Earth–Moon / μ = 0.05; L1 | all oscillations / a growing mode; one unstable real eigenvalue |
| Figure-8 (Chenciner–Montgomery), one period 6.32591398 | returns within 10⁻⁵; energy, momentum, angular momentum drift < 10⁻⁹ |
| A path into the Moon | ends on the Moon's surface |

## Lesson

**Lagrange points and forbidden regions** finds L1's saddle, closes the L1 neck by lowering the
energy, shows that L4 is stable for the Earth–Moon system but not for μ = 0.05, and runs the
Arenstorf orbit.
