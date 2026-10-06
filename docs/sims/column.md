# Column Buckling

A slender column of length L under an axial load P: Euler's buckling load for four end
conditions, the squash load it competes with, an imperfect (bowed) column and the load at which
it first yields, a Southwell plot, and the elastica, which follows the perfect column far past
buckling. This is a static solver, with no time axis or playback.

## Model

**Euler buckling.** A straight, elastic column can bend sideways at

```text
P_cr = π² E I / (K L)²
```

with the effective length factor K = 1 (pinned–pinned), 2 (fixed–free), 0.699 (fixed–pinned;
exactly π/β with tan β = β, β = 4.4934), or 0.5 (fixed–fixed). The mode shapes, with x/L from the
fixed base: sin πx, 1 − cos(πx/2), β(1 − cos βx) − βx + sin βx, and (1 − cos 2πx)/2. The squash
load is A σy; a perfect column fails at the smaller of the two. They are equal at the limiting
slenderness K L / r = π √(E/σy) (r = √(I/A)): about 89 for A36 steel.

**Imperfection.** A bow e0 in the shape of the buckling mode grows under load to

```text
δ = e0 / (1 − P/P_cr)
```

exact for every end condition when the bow is affine to the mode. The largest bending moment is
m P δ, with m = 1 for pinned–pinned and fixed–free, 1/2 for fixed–fixed, and EI·max|φ''| / P_cr
≈ 0.733 for fixed–pinned. The largest stress is σ = P/A + m P δ c / I (c the outer half-size), and
the load at first yield solves σ = σy (the Perry–Robertson formula, the sine-bow form of the
secant formula): with η = m e0 c A / I and σcr = P_cr/A,

```text
P/A = [σcr(1 + η) + σy − √((σcr(1 + η) + σy)² − 4 σy σcr)] / 2
```

This is the governing failure load; with e0 = 0 it is min(P_cr, A σy).

**Southwell plot.** "Measured" deflections Δ = δ − e0 at eight loads up to the smaller of
0.9 P_cr and first yield follow the amplification law (with optional random scatter). Plotted
as Δ/P against Δ they lie on the line Δ/P = Δ/P_cr + e0/P_cr, so the fitted slope gives P_cr and
the intercept e0, without loading the column to collapse.

**Elastica.** An inextensible, perfect pinned–pinned column with θ(s) the angle of its centreline
to the line of the load:

```text
θ'' + (P/EI) sin θ = 0,   θ(0) = α,  θ'(0) = 0,   x' = cos θ,  w' = sin θ
```

solved by shooting: `fzero` finds the end rotation α at which `ode45`, started at the end, first
reaches θ = 0 exactly at mid-length (that distance grows with α, so the root is unique). Below
P_cr the only shape is straight. Fixed–free and fixed–fixed columns are pieces of the same
periodic curve of length K L (a half, and two halves around a full wave), so they are solved
exactly too; fixed–pinned is not (its end reaction tilts the line of thrust). Past
P ≈ 2.18 P_cr (end rotation 130.7°) the elastica's ends pass each other: the curve goes on, but a
real column and its supports cannot follow it, and the app says so.

**Scope:** linear elasticity, no plasticity or residual stress, no design-code factors, and no
self-weight. The elastica past yield is the perfect elastic column: a metal one would have
yielded long before, as the stress check shows.

## Inputs

| Group | Inputs |
|---|---|
| Column | End conditions (pin–pin, fixed–free, fixed–pin, fixed–fixed; base first); length L (m) |
| Material | Steel A36 (200 GPa, 250 MPa), aluminium 6061-T6 (69 GPa, 276 MPa), timber C24 (11 GPa, 21 MPa), or custom E and yield stress |
| Section | Round tube, solid rod, square box, square bar (outer size D and wall t, mm), or custom A (cm²), I (cm⁴), and c (mm) |
| Load | Axial load P (kN), or the ratio P / P_cr |
| Imperfection | Initial bow e0 (mm); the Southwell scatter (%) |
| Analysis | Imperfect (small deflection of the bowed column) or Elastica (large deflection of the perfect column) |
| Display | Deflection scale (0 = automatic; the elastica is drawn to true scale) |

**Presets:** a pinned 3 m steel tube 60 × 4 mm under 40 kN (the default), a 6 m aluminium
flagpole (fixed–free), a fixed–fixed 100 mm timber post (yield governs), a slender aluminium
rod (K L / r = 400), an imperfect column at 95 % of P_cr, and the elastica at 2 P_cr.

## Outputs

- **Deflected shape:** the column upright with its supports and load, the initial bow and the
  bowed column (lateral deflection scaled), or the elastica to true scale.
- **Load–deflection:** the imperfect column's hyperbola, approaching P_cr, against the perfect
  column's path: straight up to P_cr, then the elastica, rising slowly past it.
- **Southwell plot:** the measured points and the fitted line, with the recovered P_cr and e0.
- **Stress check:** the largest stress against the load for both, the yield stress, P_cr, the
  squash load, and the first-yield point.
- **Column curve:** failure stress against slenderness: Euler's hyperbola, the yield plateau, and
  the first-yield curve for the same e0/L, with this column marked.
- **End conditions:** the four mode shapes side by side with their K and P_cr; drawn while editing.
- **Summary:** P_cr, K, the effective length, r, the slenderness and its limit, the squash load,
  whether buckling governs (yes, 1) or yield (no, 0) for the perfect column, the failure load
  (first yield, with the bow), the load and P/P_cr, the utilization P / failure load, the largest
  deflection, the amplification 1 / (1 − P/P_cr) (imperfect analysis), the largest stress and its
  ratio to yield, the elastica's end rotation (at the quarter points for fixed–fixed) and end
  shortening (elastica analysis), and the Southwell P_cr from the fitted slope and its error.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Euler loads, all four end conditions | π² EI/(KL)², fixed–pinned β² EI/L² with tan β = β (10⁻⁹) |
| Elastica, α = 5° … 170° | P/P_cr = (2K(k)/π)², k = sin(α/2), `ellipke` (10⁻⁴); shooting recovers α (10⁻⁴); crest 2k/(π√(P/P_cr)); chord 2E(k)/K(k) − 1 (Timoshenko & Gere §2.7) |
| Elastica, fixed–free and fixed–fixed | tip deflection = the pinned crest of length 2L; mid-height = two crests of length L/2 |
| Imperfection, all end conditions | δ = e0/(1 − P/P_cr) (10⁻¹²); σ = σy at the first-yield load (10⁻⁹) |
| Pinned bowed column | δ against a `bvp4c` solution of EI w'' + P w = EI w0'' (10⁻⁵) |
| Moment factors m | 1, 1, 0.733, 1/2 against finite differences of the mode shapes (10⁻³) |
| Perfect column | failure load = min(P_cr, A σy); limit π √(E/σy) |
| Southwell plot | slope recovers P_cr and e0 within 1 % (exact points), 10 % with 3 % scatter |
| Default tube in the app | P_cr = 60.81 kN; fixed–free ¼, fixed–fixed 4×, fixed–pinned (β/π)² × |

## Lesson

**Why columns buckle** doubles the length to quarter the Euler load, fixes both ends to
quadruple it, shows a stocky timber post crushing before it buckles, amplifies a bow twenty
times at 95 % of P_cr, and ends with the elastica at twice P_cr: a buckled column still carries
load.
