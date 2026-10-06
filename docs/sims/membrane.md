# Vibrating Membrane

A drum head: a stretched membrane with a fixed edge, square, rectangular, or circular. Its modes
come from a finite-difference Laplacian, their nodal lines are the Chladni patterns, and its
overtones, unlike a string's, are not whole multiples of the fundamental. Where the drum is struck
decides which modes ring.

## Model

```text
ρ ∂²u/∂t² = T ∇²u,   u = 0 on the edge,   c = √(T/ρ)

Rectangle a × b:   f_mn = (c/2) √((m/a)² + (n/b)²)        m, n = 1, 2, …
Circle, radius R:  f_mn = c j_mn / (2π R)                   j_mn: the n-th zero of J_m
```

T is the tension per unit length of edge (N/m) and ρ the areal density (kg/m²).

**Rectangle:** the 5-point Laplacian on the interior nodes of a grid with spacing h (the same in
both directions when the sides allow it). Its error is O(h²).

**Circle:** a polar grid rather than a square grid masked to the disc, which would have a
staircase edge and only first-order accuracy. Rings sit at r = (i − ½)Δr (the rim, r = R, is at
(N_r + ½)Δr) and there are 4 N_r equally spaced angles. The Laplacian is written as finite
volumes; the flux through r = 0 vanishes, so no node sits at the singular centre. Multiplied by
each node's area it is symmetric, and the scheme is second order. It also keeps the angular
modes exactly apart, so a centred strike excites only m = 0 to rounding.

**Modes:** the lowest N eigenpairs of the symmetric matrix W^(-½) S W^(-½) (S the
area-weighted −∇², W the node areas) from `eigs(…, "smallestabs")` on the sparse matrix, with a
fixed start vector so runs are reproducible. Modes are labelled (m, n): for a rectangle from the
discrete sine transform (half-waves along x and y), for a circle from the angular Fourier content
(m nodal diameters) and the order within each m (n nodal circles, the rim included). Degenerate
pairs are made pure: a square's (1,2) and (2,1) become the two sine products, and a circle's
pair becomes cos mθ and sin mθ. The exact value of every mode is shown beside the grid's;
Bessel zeros come from `fzero` on `besselj`.

**Motion:** the start is projected on the modes kept (mass-normalized, so the modal energies add
up to the total) and each mode is solved exactly in time, decaying with the same damping ratio ζ.
A strike is a Gaussian initial velocity, a pluck a Gaussian displacement, and One mode starts in a
single mode shape. A narrow strike puts energy into many modes; the Summary reports the share the
modes kept capture.

## Inputs

| Group | Inputs |
|---|---|
| Membrane | Shape (rectangle or circle); width a and height b, or radius R; tension (N/m); areal density (kg/m²); damping ratio (%) |
| Excitation | Strike, pluck, or one mode; amplitude (m/s for a strike, m otherwise); position x and y (fractions of the bounding box, so 0.5, 0.5 is a circle's centre) and Gaussian width; mode m and n |
| Numerics | Grid size (intervals across the longer side or the diameter, 8–160), modes kept (1–200) |
| Simulation | Duration, output step, probe position x and y |

**Presets:** a 0.5 m square drum struck off-centre (T = 2000 N/m, ρ = 0.25 kg/m², f₁ = 126 Hz),
a 2:1 rectangle, a 33 cm circular drum struck at the centre and off-centre (f₁ = 104 Hz), a single
mode (2,1) on the circular drum, and a damped strike (ζ = 3 %).

## Outputs

- **Animation** (slow motion: a whole run in about 20 s): the displaced membrane as a 3-D surface
  or, from the View menu in the playback bar, a heatmap from above, coloured by the theme's
  diverging map with symmetric limits. The strike point (+) and the probe are marked.
- **Mode shapes:** the first nine distinct modes, each with its nodal lines (drawn exactly: for a
  rectangle x = i a/m and y = k b/n, for a circle the diameters and the circles r = R j_mi / j_mn),
  (m, n), frequency, and ratio to the fundamental (Chladni patterns).
- **Frequencies:** f / f₁ of the first 20 modes from the grid and exact, against a string's
  harmonics 1, 2, 3, …, and the grid's error for each.
- **Mode content:** the share of the start's energy in each mode (for a circle, m = 0 modes in a
  second colour).
- **Probe:** the displacement at the grid point nearest the probe, and its spectrum with the mode
  frequencies marked. **Energy:** kinetic, potential, and total.
- **Summary:** the fundamental, f2 / f1, the exact fundamental and the error, the largest error of
  the first nine modes, the wave speed, modes kept, grid nodes, the initial energy, the share
  captured by the modes kept, the energy remaining at the end, the dominant mode's frequency, and
  (circle) the share in axisymmetric modes.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Rectangle 0.6 × 0.4 m, c = 31.6 m/s, grid 60 | order (1,1), (2,1), (1,2), (3,1), (2,2), (3,2), (4,1), (1,3); each within 0.4 % of (c/2)√((m/a)² + (n/b)²) |
| Unit square, grid 20 → 40 → 80 | errors of the lowest six fall 3.8–4.2× per halving of h; under 0.3 % at h = 1/40 |
| Square (1,2) and (2,1) | equal frequencies (10⁻⁹), ratio √(5/2) to f₁; each a pure product of sines |
| Strike on x = a/2 | modes with even m: less than 10⁻²⁰ of the energy |
| Circle R = 1, c = 1, grid 80 | j01 = 2.404826, j11 = 3.831706, j21 = 5.135622, j02 = 5.520078 (fzero within 10⁻⁶); f within 0.2 %, in that order |
| Circle, grid 20 → 40 → 80 | errors of the lowest five fall 3.5–4.5× per halving; under 2 % on the coarsest |
| Circle struck at the centre / off-centre | energy in m ≥ 1 modes below 10⁻²⁰ / axisymmetric share below 50 % |
| Undamped energy | constant to 10⁻¹⁰, equal to the sum of the modal energies |
| Single mode (2,1) on a circle | no other mode excited (10⁻²⁰); back to its start after 1/f₂₁ |
| One mode with ζ = 1 % | energy decays as e^(−2ζωt) (2 %) |
| App defaults (0.5 m square, T = 2000 N/m, ρ = 0.25 kg/m²) | f₁ = 126.5 Hz (0.1 %), f2 / f1 = √(5/2) (0.2 %) |
| App mode (2,1), R = 0.33 m | 221.5 Hz = c j21 / 2πR (0.5 %) |

## Lesson

**Why a drum is not a string** compares a square drum's overtones (1 : 1.58 : 2 : 2.24) with a
string's harmonics, starts the drum in mode (2,1) to show a nodal line, reads the circular drum's
Bessel-zero ratio j11 / j01 = 1.593, strikes the centre so that only axisymmetric modes ring, and
moves the strike out towards the rim.
