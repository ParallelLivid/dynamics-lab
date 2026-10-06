# Heat in a Plate

Transient heat conduction in a rectangular plate, solved on a 2-D grid with the explicit (FTCS)
or the ADI (Peaceman–Rachford) scheme. It shows a hot spot spreading, why the explicit scheme's
stability limit in 2-D is half the 1-D one, how ADI takes large steps, and fixed-temperature,
heat-flux, and convection edges with an exact energy balance.

## Model

```text
ρ c ∂T/∂t = k (∂²T/∂x² + ∂²T/∂y²) + q        on 0 ≤ x ≤ a, 0 ≤ y ≤ b,   α = k / (ρ c)
```

The plate's faces are insulated, so heat flows in its plane and enters or leaves through the four
edges; the thickness only scales energies (J) and powers (W). The grid has nx × ny nodes, edges
included (Δx = a / (nx − 1), Δy = b / (ny − 1)), and the Laplacian is the 5-point stencil.

| Scheme | Step | Stability | Accuracy |
|---|---|---|---|
| Explicit (FTCS) | T ← T + r_x (T_W − 2T + T_E) + r_y (T_S − 2T + T_N) | only when r_x + r_y ≤ ½ (r ≤ ¼ on a square grid) | first order in time |
| ADI (Peaceman–Rachford) | two half steps, implicit along x then along y: one tridiagonal solve per grid line | always | second order in time |

with r_x = α Δt / Δx² and r_y = α Δt / Δy². The time step is given directly or through
r = α Δt / Δx², and is shortened slightly, if needed, so the run ends exactly at the duration.

**Stability:** the plate's grid modes are products of 1-D modes, with decay rates
λ = −(μx + μy) from the eigenvalues μ of the 1-D operators. Explicit multiplies each mode by
g = 1 − λΔt per step, so it is stable while λ_max Δt ≤ 2; the summary gives this exact largest
step for the grid and edges (r = ¼ exactly for insulated edges, a little more for fixed ones).
ADI multiplies a mode by g = (1 + ½Δt μx)(1 + ½Δt μy) / ((1 − ½Δt μx)(1 − ½Δt μy)), always |g| < 1, but for very large steps
the shortest wavelengths get g ≈ −1 and ring. An explicit run that grows past a thousand times
its starting temperature scale stops and is reported as unstable (orange status).

**Edges:** each of the four is a fixed temperature (Dirichlet), a heat flux into the plate
(Neumann; 0 W/m² is insulated), or convection to a fluid at T∞ (Robin: flux = h (T∞ − T)).
Flux and convection edges mirror a ghost node across the edge; where two fixed edges meet, the
corner takes their average.

**Energy balance:** the stored heat ρ c d ∬T dA (trapezoidal node areas, which the ghost-node
operators conserve exactly) is compared with the heat in through the edges plus the heat from
the source. Heat through a fixed edge is what keeps its nodes at temperature. Both schemes close
the balance to rounding.

**Exact solution:** a separable start sin(mπx/a) sin(nπy/b) on a base temperature T0, inside four
edges fixed at T0 with no source, keeps its shape and decays as
exp(−α π² (m²/a² + n²/b²) t).

## Inputs

| Group | Inputs |
|---|---|
| Plate | Material (copper, aluminium, steel, glass, or custom k, ρ, c), width a, height b, thickness |
| Edges | For each edge: type, and its temperature, heat flux, or h and fluid temperature |
| Initial temperature | Uniform, hot spot, separable mode, or hot edge; base temperature, amplitude, spot position, width, mode numbers m and n, which edge |
| Heat source | None, uniform, or a spot heater; strength (peak, W/m³), position, width |
| Numerics | Scheme, nodes along x and y, set the step by r or by Δt |
| Simulation | Duration, output step (at most about 400 fields are kept), probe position |

**Presets:** hot spot spreading (ADI, r = ½), separable mode decay (explicit, r = 0.2, with the
exact solution), cooling fin edge (an aluminium strip held at 100 °C at one end, convection with
h = 200 W/m²/K elsewhere), insulated plate with a heater, explicit at the limit (r = ¼),
explicit past the limit (r = 0.3, unstable), and ADI with a large step (r = 5).

## Outputs

- **Animation:** the temperature field as a heatmap, or as a 3-D surface (View, in the playback
  bar), with the probe. A whole run plays in about 15 s.
- **Temperature field:** six snapshots on one colour scale with contours (the probe and the
  centre line are marked on the last). A separable mode with m or n above 1 uses a diverging
  scale about T0.
- **Probes:** temperature along the centre line y = b/2 at the snapshot times, and the probe,
  centre, mean, and maximum temperatures over time.
- **Energy:** the change in stored heat, the heat in through the edges, the heat from the source,
  and their sum.
- **Stability:** the growth factor per step of every grid mode against λΔt, with the exact
  e^{−λΔt} and the lines g = ±1 (growing modes in red); below it, the decay of the mode against
  the exact solution, or, for other starts, how fast the field is still changing.
- **Summary:** the scheme, r, r_x + r_y, the explicit limit (0.5), the time step and the largest
  stable explicit step, stable (yes/no), final maximum, minimum, and mean temperature, the probe
  temperature, the diffusivity, the energy balance error, heat in through the edges and
  generated, the time to steady state (within 1 % of a steady final field), and for the mode the
  decay rate, the exact rate, their difference, and the largest error against the exact solution.
- The export lists the probe, centre, mean, maximum and minimum temperatures, and the energies at
  every output time.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| (1, 1) mode, all edges at 0, fixed r = 0.2 | error falls 4× (3.8–4.2) per halving of h, explicit and ADI |
| Mode decay rate | λ = α π² (m²/a² + n²/b²), grid value within 0.2 % on 41 × 21 |
| Explicit, checkerboard mode, square grid | g = 1 − 8r sin²((n−2)π/2(n−1)) per step (10⁻⁹); \|g\| < 1 at r = ¼, grows at r = 0.26 |
| Largest stable explicit step, n × n square grid | fixed edges r = 1/(4 sin²((n−2)π/2(n−1))), just over ¼; insulated edges exactly ¼ |
| ADI at r = 5 | g = ((1 − 2rs)/(1 + 2rs))² per step (10⁻⁹); stable |
| Insulated plate | energy conserved to 10⁻¹² (both schemes) |
| Convection edges, fixed edges, flux, and a heater | stored heat = edges + source to 10⁻⁹ |
| Uniform source, insulated | mean temperature rises at q/ρc exactly |
| Two opposite edges fixed at 100 °C and 0 °C, the others insulated | steady field linear in x (10⁻⁹) |
| Fixed edge and a convection edge (h = 20, k = 5, T∞ = 10 °C) | T(a) = T∞ + (T₀ − T∞)(1/h)/(a/k + 1/h) (10⁻⁹) |
| Cooling fin preset | tip within 1 % of the fin equation 1/(cosh mL + (h/mk) sinh mL), m² = 2h/(kb) |
| Heater preset | heat generated = q π w² d t (10⁻³) |

## Lesson

**Heat in two dimensions** spreads a hot spot, runs the explicit scheme at r = ¼ (the 2-D limit,
against ½ in 1-D), pushes it to r = 0.3 to blow up, and then lets ADI run stably at r = 5.
