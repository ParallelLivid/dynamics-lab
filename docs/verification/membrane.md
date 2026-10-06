# Vibrating Membrane — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/membrane/index.html` (138 pictures before the fixes; `after-*.png`
after them: the circular and square drums' mode shapes, the probe, and the 2:1 rectangle at
Larger text in the light theme; run `dlab.dev.captureVerification("membrane")` to make them again)

## Model as implemented

**Rectangle** (`simulateMembrane.m`): the 5-point Laplacian on the interior nodes, node areas
h_x h_y, so the symmetric form W^(−½) S W^(−½) has orthonormal eigenvectors and φ = W^(−½)ψ/√ρ is
mass-normalized. Its eigenvalues are known exactly, (4/h_x²) sin²(mπh_x/2a) + (4/h_y²)
sin²(nπh_y/2b), which gives an independent check of the whole eigen-solve and labelling pipeline.
Degenerate pairs are replaced by the pure sine products.

**Circle:** polar finite volumes, rings at r_i = (i − ½)Δr with the rim at R = (N_r + ½)Δr, 4N_r
angles; the flux through r = 0 vanishes, so there is no singular centre node; checked by hand
that the radial and angular fluxes and the volumes (r Δr Δθ, exact for the first ring) are as the
comment says. Modes are labelled by their angular Fourier content; cos/sin pairs are rotated to
pure cos mθ and sin mθ.

**Time and energy:** each mode's damped free response, exact at every output time; the start's
full energy is computed on the grid (½ Σ M v² for a strike, ½ T uᵀ S u for a pluck) so "captured"
is the kept modes' share of it.

**Against the docs page and `about()`:** they match (the square's 1 : 1.58 : 2 : 2.24 and the
circle's 1 : 1.59 : 2.14 : 2.30 checked).

## Reference values

Independent of the engine: the continuum modes (sines; Bessel functions with scipy's `jn_zeros`),
the 5-point grid's closed-form eigenvalues, and the strike's projection on the exact modes by
quadrature (separable 1-D integrals for the rectangle, a 1500 × 1440 polar grid for the circle);
each mode's damped energy at the end in closed form. T = 2000 N/m, ρ = 0.25 kg/m², c = 89.4427 m/s.

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Square 0.5 m, grid 40: frequencies | exact (1,1) 126.4911, (2,1) 200, (2,2) 252.9822 Hz; 5-point grid 126.4586, 199.8253, 252.7222, 282.2471 | 126.4586, 199.8253, 252.722, 282.247; exact 126.4911 | 0 (grid values) | ✓ |
| … errors | fundamental −0.0257 %; largest of the first nine 0.38804 %; f₂/f₁ 1.58016 | −0.0257, 0.38804, 1.580164 | 0 | ✓ |
| … strike 1 m/s at (0.3, 0.37), width 0.03 m | energy ½ρ∫v² = 176.7146 µJ; the 60 lowest modes 80.513 %; dominant (2,1) 199.8 Hz; 14.806 % left after 0.2 s | 176.7146 (grid), 80.513, 199.8253, 14.806 | 0 | ✓ |
| Rectangle 0.8 × 0.4 | grid f₁ 124.8908 (exact 125); f₂/f₁ 1.26472; largest error 0.56686 %; energy 452.3893 µJ, 95.45 % kept; 23.20 % left | 124.8908, 125, 1.264716, 0.56686, 452.3893, 95.53, 23.18 | 10⁻³ (kept modes: grid vs continuum) | ✓ |
| Circle R 0.33 m, grid 40 | j01 c/2πR = 103.7373 Hz; ratios 1.5933, 2.1355, 2.2954, 2.6531 | 103.6675 (−0.067 %), 1.592936; distinct (1,1) 165.14, (2,1) 221.21, (0,2) 237.38, (3,1) 274.55 | ≤ 0.75 % (grid 40), 0.19 % (grid 80) | ✓ (second order) |
| … struck at the centre | all energy axisymmetric; kept 86.17 %; dominant (0,3); 20.48 % left | 100 %, 86.14, (0,3) 370.5 Hz, 20.68; energy 273.0 µJ for 265.3 (grid 80: 267.2) | +2.9 % energy on grid 40, +0.7 % on 80 | ✓ (accepted: grid quadrature of a 2.5-ring bump) |
| … struck off-centre (0.8, 0.55) | energy 307.9075 µJ; 86.98 % kept; 8.629 % axisymmetric; dominant (1,1); 19.57 % left | 307.9075 (grid), 86.94, 8.6335, 165.1 Hz, 19.72 | 10⁻³ | ✓ |
| Single mode (2,1), 2 mm | f = c j21/2πR = 221.536 Hz; E = ½ρω²∫u² = 80.782 mJ; no other mode | 221.208 (−0.15 %), 80.798; axisymmetric 3.7·10⁻³⁰ % | 2·10⁻⁴ | ✓ (finding 3: the 10⁻³⁰) |
| Damped strike, ζ 3 %, 0.1 s | 0.136 % left; 10.76 % axisymmetric | 0.1388, 10.93 | grid | ✓ |
| Lesson numbers | √(5/2) = 1.58, then 2, 2.24, 2.55; about 200 Hz for (2,1); j11/j01 = 1.593, 2.14, 2.30, 2.65; axisymmetric 1 : 2.30 : 3.60 : 4.90; off-centre mostly m ≥ 1 | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.15 s headless; every Summary number
reaches the metrics; every exported column has its units; no non-finite values; a second solve
gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 7.6 s for the first run while MATLAB warms
up, median 1.8 s); undo and redo of a; a scenario round trip; CSV, MAT, plot and report exports
(7 images); a 10-frame GIF; a sweep of a; a map of a × b; uncertainty of a ± 2 %; a short
optimization of the fundamental over a; theme and text-size switches keep the result.

### Tests

`tests/sims/membrane` (new: `inputsFitAndExplainThemselves`, `nodalLinesAreExact`; the drawing
test now asserts no contours): 21 passed, 0 failed. None excluded. `codeIssues` on every touched
file: 0.

## Checklist

- [x] Physics: the 5-point and polar finite-volume operators, mass normalization, labelling and
  pair rotation, modal time response and energies checked by hand; docs and `about()` match
- [x] Numbers: every preset against the exact grid eigenvalues, Bessel zeros, and projections
- [x] Inputs: labels, units, ranges, tooltips (added for six, finding 2), visibility (a and b or
  R; position and width only for strike and pluck; m and n only for one mode)
- [x] Outputs: every tab readable in both themes and at Larger text; nodal lines exact (finding 1);
  the animation agrees with the probe
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere (finding 4)
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on a and b; no Modes or Bode tab
- [x] Teaching: every lesson statement and number checked (all right)
- [x] Behaviour: readable errors (a mode not among those kept, a strike outside the drum);
  nothing left behind on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Outputs | The Chladni patterns were contours of the grid shapes, which break where nodal lines cross: a gap at the centre of the circle's (1,1), jogs where the (1,2) and (2,2) diameters meet their circles, a kink in the square's (2,2), (2,3), (3,2) crosses. | The nodal lines are drawn exactly: x = i a/m and y = k b/n for a rectangle; for a circle the diameters where cos mθ (or sin mθ) vanishes and the circles at r = R j_mi / j_mn. | `nodalLinesAreExact`, `everyTabIsDrawn` |
| 2 | Inputs | "Strike (initial …" and "Pluck (displaced …" were cut off; a, b, R, the duration, the output step and probe y had no tooltip. | "Strike", "Pluck", "One mode" (the tooltip explains them); tooltips added. | `inputsFitAndExplainThemselves` |
| 3 | Summary | A single non-axisymmetric mode showed "Energy in axisymmetric modes 3.67e−30 %". | Below 10⁻⁹ % it reads 0. | `nodalLinesAreExact` |
| 4 | Outputs | The probe spectrum's axis read "Amplitude" with no units. | "Amplitude (m)". | — |

Accepted:
- **Cancel waits for the eigenvalue solve** (a known limitation): `eigs` cannot report
  progress or stop. It is under 0.5 s at the defaults and up to 5.4 s at the largest grid (160,
  200 modes, 25 000 nodes); Cancel acts as soon as it returns.
- **A strike at the centre of the circle carries 2.9 % more energy on grid 40 than the continuum**
  (0.7 % on grid 80): the bump is 2.5 rings wide and the grid's quadrature of it converges at
  second order. The shares and the captured percentage use the grid's own total.
- **"Amplitude (m/s or m)"**: a speed for a strike, a displacement otherwise; the tooltip says so
  (as in the Vibrating String).
