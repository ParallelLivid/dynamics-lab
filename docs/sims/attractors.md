# Strange Attractors

Three classic chaotic flows in three dimensions: the Lorenz butterfly, Rössler's one-winged
band, and Chua's double scroll. A twin trajectory shows sensitive dependence on the start, the
largest Lyapunov exponent measures it, and the successive maxima give a return map and
bifurcation diagrams.

## Models

| System | Equations | Inputs |
|---|---|---|
| Lorenz | x' = σ(y − x), y' = x(ρ − z) − y, z' = xy − βz | σ, ρ, β |
| Rössler | x' = −y − z, y' = x + ay, z' = b + z(x − c) | a, b, c |
| Chua's circuit | x' = α(y − x − f(x)), y' = x − y + z, z' = −βy, with f(x) = m1·x + ½(m0 − m1)(\|x + 1\| − \|x − 1\|) | α, β, m0, m1 |

The equations are dimensionless: time is in the model's own time units, and x, y, z have no
units. In Lorenz's convection model σ is the Prandtl number, ρ the Rayleigh number over its value
at the onset of convection, and β a geometric factor of the cell.

**Integration:** `ode45` (relative tolerance 10⁻¹⁰) on nine states at once: the trajectory, the
twin (started `delta` away in x), and the tangent vector v' = J(x) v.

**Lyapunov exponent:** Benettin's method. The tangent vector is renormalized every 10 time units
and the logarithms of its growth are summed; after the transient, λ is their total over the
elapsed time. λ > 0 is chaos, λ ≈ 0 a periodic orbit, λ < 0 a fixed point; within ±0.01 it is
taken as zero (a finite run's estimate is no better). The running estimate is drawn from 2 time
units after the transient (before that it divides by almost nothing). The twins show the same thing
to the eye, but their distance saturates at the size of the attractor, so the exponent is not
taken from them.

**Maxima:** the successive maxima of z (Lorenz) or x (Rössler, Chua) after the transient, located
by the solver's event detection (where the variable's rate falls through zero), so they do not
depend on the output step. They are clustered with a tolerance of 10⁻³ of the attractor's size (at
least 10⁻³): one cluster is a simple cycle, two a period-2 cycle, and more than 32 is reported as
chaotic. A run that ends at rest on an equilibrium is reported as settled instead.

**Equilibria:** Lorenz: the origin and, for ρ > 1, C± = (±√(β(ρ − 1)), ±√(β(ρ − 1)), ρ − 1).
Rössler: x = (c ± √(c² − 4ab))/2, y = −x/a, z = x/a (none when c² < 4ab). Chua: the origin and,
when k = (m1 − m0)/(m1 + 1) ≥ 1, ±(k, 0, −k) (for k < 1 the outer pieces of the diode have no
equilibrium).

## Inputs

| Group | Inputs |
|---|---|
| System | System; σ, ρ, β (Lorenz); a, b, c (Rössler); α, β, m0, m1 (Chua) |
| Start | x0, y0, z0; twin offset in x (default 10⁻⁸) |
| Simulation | Duration; transient left out (%) |
| Numerics | Output step |

**Presets:** the Lorenz butterfly (ρ = 28), a fixed point below the Hopf point (ρ = 14), a
periodic window (ρ = 160, with the first half of the run left out: the motion is chaotic for a
while before it settles on the cycle), Rössler at c = 2.5 (period-1), 3.5 (period-2), and 5.7
(chaos), and Chua's double scroll.

## Outputs

- **Animation:** the trajectory in 3-D with a trail, and its twin in a second colour; drag to
  rotate. The readout shows the distance between them.
- **Attractor** (3-D, with the equilibria), **Time series** (x, y, z), **Sensitivity** (the
  twins' distance on a log scale with a line of slope λ, ∝ e^{λt}, placed through the part where
  the distance grows exponentially; and the running estimate of λ), and
  **Return map** (each maximum against the previous one, coloured by time).
- **Modes:** the system linearized at the equilibrium it circles (Lorenz C+, Rössler's inner
  equilibrium, Chua's P+ at the centre of a scroll, or the origin when there is no P±). Modes are
  named stable/unstable spiral or direction. Rössler with c² < 4ab has no equilibrium, and no
  Modes.
- **Summary:** the largest Lyapunov exponent, the Lyapunov time 1/λ (when λ > 0.01), the number
  of distinct maxima, the attractor's size (the largest range of x, y, or z after the transient),
  whether the run settled, when the twins came 10 % of that size apart, and the number of
  equilibria.
- **Sweeps:** "Maxima of z" (or x) is a set-valued result: sweep ρ or c and plot it (all values)
  for a bifurcation diagram.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Lorenz σ = 10, ρ = 28, β = 8/3, 1000 time units | λ = 0.9056 ± 0.02 (Sprott 2003) |
| Lorenz ρ = 14 | settles exactly on C+ = (√(8/3·13), √(8/3·13), 13); λ < 0 |
| Rössler a = b = 0.2 | c = 2.5, 3.5, 4.0: 1, 2, 4 distinct maxima (period doubling); c = 5.7: λ = 0.0714 ± 0.01 |
| Chua α = 15.6, β = 28, m0 = −1.143, m1 = −0.714, 1000 time units | equilibria at 0 and ±(1.5, 0, −1.5); both scrolls visited; λ = 0.43 ± 0.03 (independent integration, [verification sheet](../verification/attractors.md)) |
| Lorenz maxima of z from (1, 1, 1) | the first twelve agree with an independent integration to 10⁻⁶ at output steps 0.01, 0.05, and 0.2 |
| Lorenz ρ = 160, second half of 60 time units | a cycle with two maxima of z, 188.6584 and 216.6342; λ ≈ 0 |
| A centre (Rössler with a = b = 0) | λ = 0 within 10⁻³: the tangent method, not the twins |

## Lesson

**The butterfly effect** runs the Lorenz butterfly, follows two runs started 10⁻⁸ apart, reads
the Lyapunov exponent, drops ρ below the Hopf point to a fixed point, and ends with Rössler's
first period doubling.
