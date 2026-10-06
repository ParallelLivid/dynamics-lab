# 1-D Heat Conduction

Heat spreading along a rod or through a wall, solved on a grid with a choice of time-stepping
scheme. It shows the explicit scheme's stability limit, the accuracy of implicit schemes, and
fixed-temperature, heat-flux, and convection boundaries, including end temperatures that change
during the run (a daily cycle).

## Model

```text
ρ c ∂T/∂t = k ∂²T/∂x² + q        on 0 ≤ x ≤ L,   α = k / (ρ c)
```

The rod is divided into N nodes, ends included (Δx = L / (N − 1)), and the second derivative is
replaced by `(T[i−1] − 2T[i] + T[i+1]) / Δx²` (the method of lines). Time stepping uses the
θ-method:

| Scheme | θ | Stability | Accuracy in time |
|---|---|---|---|
| Explicit (FTCS) | 0 | only when r = α Δt / Δx² ≤ ½ | first order |
| Implicit (backward Euler) | 1 | always | first order |
| Crank–Nicolson | ½ | always | second order |

The time step is shortened slightly, if needed, so the run ends exactly at the duration.

**Ends:** a fixed temperature (Dirichlet; it can change during the run, e.g. a sine), a heat flux
into the rod (Neumann; 0 W/m² is insulated), or convection to a fluid at T∞ (Robin: flux =
h (T∞ − T)). Flux and convection ends mirror a ghost node across the end.

**Stability:** an explicit run with r > ½ grows its shortest-wavelength error every step; when the
temperatures exceed a thousand times their starting scale, the run stops and is reported as
unstable (orange status).

**Exact solution:** with fixed, constant end temperatures, no source, and a sine start, the
temperature is the straight line between the ends plus `A sin(nπx/L) exp(−α (nπ/L)² t)`, which
can be drawn dashed on the profile and gives the "Max error vs exact".

## Inputs

| Group | Inputs |
|---|---|
| Rod | Material (copper, aluminium, steel, brick, water, or custom k, ρ, c), length, heat source |
| Ends | For each end: type, and its temperature (a schedule), heat flux, or h and fluid temperature |
| Initial temperature | Uniform, step (hotter left of the position), sine mode, or hot spot; base temperature, amplitude, mode, position, width |
| Numerics | Scheme, grid nodes, time step |
| Simulation | Duration, output step |
| Display | Show the exact solution |

**Presets:** cooling bar (sine mode), explicit at the stability limit (r = 0.5), explicit beyond
it (r = 0.55), hot spot spreading (insulated ends), daily temperature cycle in a brick wall, and a
rod heated at one end and cooled at the other.

## Outputs

- **Animation:** the temperature profile over a strip colored by temperature, with the exact
  solution when known. A whole run plays in about 15 s.
- **Temperature profile** (start, five snapshots, and the end), **Space-time** (a heatmap of
  temperature over position and time), **Probes** (temperature at L/4, L/2, and 3L/4), and
  **Energy** (change in stored heat against the heat that came in through the ends and from the
  source). The heat in is summed with the scheme's own time weights, and at a fixed-temperature
  end it includes the heat that changes the end's half cell, so the two curves agree to rounding
  at every time, for every scheme.
- **Summary:** the mesh Fourier number r, stable (1/0), the stability limit (explicit), the
  diffusivity, final extremes, the time to reach 95 % of the final state, the energy balance error,
  the error against the exact solution, and, for a varying end temperature, the surface swing and
  the ratio of the mid-point swing to it.
- The export lists the temperature at every node and output time (one row each).

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Explicit, sine mode: decay per step | exactly g = 1 − 4r sin²(πΔx/2L) (to 10⁻¹⁰) |
| Order in time against the semi-discrete solution | Crank–Nicolson 2.0, backward Euler 1.0 (±0.1) |
| Explicit, r = 0.55 / 0.5 | unstable / stable |
| Steady state, 100 °C and 0 °C ends | a straight line (10⁻⁶) |
| Steady state, 100 °C end and convection (h = 25, T∞ = 20 °C), copper | T(L) = 20 + 80·(1/h)/(L/k + 1/h) (10⁻⁴) |
| Insulated ends | energy conserved to 10⁻¹²; with a heat flux, stored heat = heat in |
| Brick wall, 30 cm, daily ±10 °C | mid-wall swing ≈ 0.27 of the surface's |
