# 1-D Heat Conduction — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/heat/index.html` (123 pictures before the fixes; `after-*.png` after
them: the brick wall's energy balance, Summary and probes, the hot spot's Summary, and a
Crank–Nicolson hot spot at Larger text in the light theme; run `dlab.dev.captureVerification("heat")`
to make them again)

## Model as implemented

**Scheme** (`simulateHeat.m`): the method of lines on N nodes with the θ-method (explicit θ = 0,
implicit 1, Crank–Nicolson ½); the step is shortened to land on the duration. Flux and
convection ends use a mirrored ghost node: the end row is (2T₂ − 2T₁)/Δx² plus 2/(kΔx) times the
flux (for convection −2h/(kΔx) T₁ and 2h T∞/(kΔx)), which I checked is the half-cell balance
ρc Δx/2 dT₁/dt = k(T₂ − T₁)/Δx + flux + q Δx/2. Fixed ends are set directly. A run that grows past
10³ times its starting scale stops as unstable.

**Energy:** stored heat ρc ∫T with trapezoidal weights, which is exactly the scheme's conserved
quantity. The heat in was summed with trapezoidal time weights (right only for Crank–Nicolson)
and, at a fixed end, as the flux into the first interior node, leaving out the heat that changes
the end's own half cell (finding 1).

**Exact solution:** the straight line between constant fixed ends plus A sin(nπx/L)
exp(−α(nπ/L)²t), shown when it applies.

**Against the docs page and `about()`:** they match; the docs now say how the balance is summed.

## Reference values

Independent of the engine: the discrete Fourier analysis of the schemes (the 3-point Laplacian's
eigenvalue (4α/Δx²) sin²(πΔx/2L) and each scheme's amplification factor), eigenfunction series of
the continuum problems (sine, cosine, and the Robin eigenvalues of k β cos βL + h sin βL = 0, which
I solved), and the exact periodic solution of the slab, T̂'' = (iω/α) T̂.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Copper | α = 401 / (8960 · 385) = 1.162454·10⁻⁴ m²/s; r = 0.2906134 | the same | 0 | ✓ |
| Cooling bar (defaults, CN, Δt 1 s): peak at 1800 s | continuum 26.34008 °C; Crank–Nicolson discrete 26.34438 | 26.34438; max error vs exact 0.00605 | 0 (discrete) | ✓ |
| … time to 95 % | 1542.1 s (continuum), so the 1560 s output | 1560 | 0 | ✓ |
| Explicit at the limit | Δt = 0.5 Δx²/α = 1.7205 s, shortened to 1.7176 (900 s / 524): r = 0.49915; highest mode × −0.998 per step | r 0.4991452, stable | 0 | ✓ |
| … beyond the limit | r = 0.5495; highest mode × −1.198 per step: blows up | unstable at 247.7 s | — | ✓ |
| Hot spot, insulated, 1200 s | cosine series: max 27.146, min 27.0337, mean 27.08982 °C | 27.14636, 27.03327 | 10⁻⁴ | ✓ |
| Aluminium rod, 100 °C end, convection h 500 to 20 °C | steady T(L) = 100 − 80 Bi/(1 + Bi) = 76.26113 °C (Bi = 0.42194); series at 600 s: T(L) = 75.6021 °C; τ₁ = 126.0 s; 95 % at 360 s | 75.60195; 360 s | 10⁻⁵ | ✓ |
| Uniform source 10⁶ W/m³, insulated, 600 s | ΔT = q t/ρc = 173.9332 °C | 193.9332 (from 20) | 0 | ✓ |
| Brick wall, 0.3 m, outer face 15 ± 10 °C daily, inside h 8 to 20 °C | exact periodic: mid-wall swing ratio 0.267826; lag 5.19 h; penetration depth √(2α/ω) = 0.113 m | 0.26735 (3 days), 0.26727 (10 days) | −0.2 % (grid 31, Δt 600 s) | ✓ |
| … energy balance during the run | stored change = heat in at every time | off by 7.56·10⁴ J/m² mid-day = ρc Δx/2 × 10 °C (5.1 %); closed only on whole days | ✗ → 10⁻¹¹ % | ✗ → ✓ (finding 1) |
| Explicit and implicit balance | exact for every scheme (the scheme conserves) | "Energy balance error" 0.027 % (r 0.5), 0.079 % (explicit r 0.4), 0.057 % (implicit) | ✗ → 10⁻¹¹ % | ✗ → ✓ (finding 1) |
| Lesson: CN error vs Δt (sweep) | second order: × 4 per halving | on 51 nodes, 5–80 s: 0.0060, 0.0058, 0.0052, 0.0028, 0.0063 (the grid's error throughout); on 401 nodes, 10–160 s: 0.00011, 0.00071, 0.0031, 0.0123, 0.0454 (× 3.7, 3.9, 4.4, then the grid) | — | ✗ → ✓ (finding 3) |
| Lesson numbers | hundredths of a degree (0.006); blow-up past ½; a quarter of the swing (0.27) | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.2 s headless; every Summary number
reaches the metrics; the export (time, x, temperature, one row each) has its units; no non-finite
values except the unstable preset's last profile, which is reported as unstable; a second solve
gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs; undo and redo of L; a scenario round trip; CSV, MAT,
plot and report exports (6 images); a 10-frame GIF; a sweep of L; a map of L × T0; uncertainty of
L ± 2 %; a short optimization over L; theme and text-size switches keep the result.

### Tests

`tests/sims/heat` (new: `testEnergyBalanceClosesAtEveryTime`, `inputsFitAndExplainThemselves`,
`wallSwingMatchesThePeriodicSolution`; the hot-spot test now asserts no swing rows), `TestLessons`
and `TestLessonChecks`: 63 passed, 0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: the θ-method, ghost-node ends, and the energy accounting checked by hand
  (finding 1); docs and `about()` match
- [x] Numbers: every preset against discrete Fourier analysis, eigenfunction series, and the
  periodic slab
- [x] Inputs: labels, units, ranges, tooltips (added for 13, finding 4), visibility (custom k, ρ, c;
  each end's values by type; the shape inputs by start); materials fill their properties
- [x] Outputs: every tab readable in both themes and at Larger text; the animation agrees with
  the profile and probes
- [x] Summary and exports: swing rows only for a cycling end (finding 2); units everywhere
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on L, T0 and Δt; no Modes or Bode
- [x] Teaching: every lesson number checked; the accuracy step fixed (finding 3)
- [x] Behaviour: an unstable run stops with a readable warning; too many steps are refused;
  nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Numbers | The heat in was summed with trapezoidal time weights whatever the scheme, so explicit and implicit runs showed a 0.03–0.08 % "energy balance error" although the scheme conserves exactly; and at a fixed-temperature end it left out the heat that changes the end's half cell, so the brick wall's two Energy curves were 5 % apart mid-day and met only on whole days. | The heat in uses the scheme's θ weights, and a fixed end adds its half cell's change (less the source there): the balance closes to 10⁻¹¹ at every time, for every scheme. | `testEnergyBalanceClosesAtEveryTime`, `wallSwingMatchesThePeriodicSolution` |
| 2 | Summary | "Surface temperature swing" and "Swing ratio (middle / surface)" appeared for any run whose left end changed over the last third: the insulated hot spot read 0.28 °C and a ratio of 1.000034, a heated insulated rod 52 °C and 1. | Only when a fixed end follows a changing schedule (that end's swing). | `insulatedRodKeepsItsHeat` |
| 3 | Teaching | The accuracy step said the Crank–Nicolson error "falls about 4× each time the step halves" over a sweep of Δt from 5 to 80 s, but on 51 nodes the grid's error (0.006 °C) dominates that whole range: the sweep showed a flat line with a dip. | The step uses 401 nodes and Δt from 10 to 160 s, where the error falls 3.7–4.4× per halving until the grid takes over at 10 s. | `TestLessons` |
| 4 | Inputs | Choices were cut off ("Fixed temper…", "Heat flux (0 = …", "Implicit (backw…"), and 13 inputs had no tooltip. | "Fixed T" / "Heat flux" / "Convection", "Explicit" / "Implicit" / "Crank–Nicolson", "Step" for the hot left part; tooltips (insulated is flux 0; the schemes' orders; the step's adjustment). | `inputsFitAndExplainThemselves` |

Accepted:
- **"Crank–Nicolson" is cut to "Crank–Ni…" at Larger text** (it fits at normal size); its name is
  what the lesson and the docs use.
- **An unstable run's Summary lists its final extremes** (±140 000 °C): the status line and the
  profile title say it went unstable, and the numbers show how far.
- **Time axes are in seconds** even for the three-day wall run (the playback readout gives hours).
