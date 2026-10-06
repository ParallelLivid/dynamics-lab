# Vibrating String and Beam — verification

Status: **verified** (4 October 2026)
Screenshots: `verification/wave/index.html` (98 pictures before the fixes; `after-*.png` after
them: the ruler's start, mode content and energy, the defaults' mode content, Summary and probe,
and the xylophone key at Larger text in the light theme; run
`dlab.dev.captureVerification("wave")` to make them again)

## Model as implemented

**Elements** (`simulateWave.m`): a string on linear elements, K = T/h [1 −1; −1 1] and the mass
the average of the consistent and lumped matrices, ρh [5 1; 1 5]/12; a beam on Hermite cubics
with the standard 12EI/h³ stiffness and ρAh/420 consistent mass (both checked against the
textbook forms). Supports remove degrees of freedom (a clamp both deflection and slope). Modes
from `eig(K, M)`, mass-normalized; a free bar's two lowest modes are its drift and spin, counted
from the supports, and dropped.

**Time:** each mode's damped free response, exact at every output time; KE = ½ Σ q̇², PE =
½ Σ ω² q², so undamped energy is constant. The modal energy is that of the start.

**Starts:** a string's pluck is a triangle (a ramp to a free end), which is exactly the shape of a
string pulled aside at one point. A beam's pluck was the same triangle (a ramp for a cantilever),
with the slopes from `gradient`: a kink a beam cannot hold, whose bending energy grows without
limit as the mesh is refined (finding 1). Strike and bump are Gaussians; a single mode uses the
mode's own deflections and slopes.

**Against the docs page and `about()`:** they match, apart from the beam pluck (now documented).

## Reference values

Independent of the engine: closed forms; for strings, sine modes with the start projected by
quadrature (2000 modes, 400 001 points) and each mode's damped energy at the end in closed form;
for beams, the exact mode shapes from the characteristic equations (which I solved here, written in
a form free of cosh − sinh cancellation, which my first attempt suffered from above mode 10),
projected the same way; energies directly as ½∫T u'² or ½∫EI u''² or ½∫ρA v².

| Case | Independent value (source) | App | Difference | Verdict |
|---|---|---|---|---|
| Guitar string, 65 cm, 70 N, 0.6 g/m | c = √(T/ρ) = 341.565 m/s; f₁ = c/2L = 262.7423 Hz; harmonics 2, 3 | 341.565, 262.7423, 2, 3 | 0 | ✓ |
| Defaults: pluck at 0.2 L, 3 mm | E₀ = T h²/2 (1/a + 1/(L − a)) = 3.028846 mJ; shares 43.771, 28.648, 12.733, 2.7357, 0, 1.2159 %; 73.359 % left at 0.02 s (ζ 0.2 %) | 3.028846; 43.758, 28.642, 12.731, 2.7357, 3.6·10⁻²⁵, 1.2164; 73.346 | 3·10⁻⁴ (shares of a truncated sum) | ✓ (finding 4: the 10⁻²⁵) |
| Guitar: pluck at 0.12 L | E₀ 4.589161 mJ; shares 26.017, 22.492, 17.465, 11.952, 6.946 %; 65.52 % left | 4.589161; 26.005, 22.483, 17.460, 11.950, 6.946; 65.50 | 10⁻³ | ✓ |
| … ζ 2 % (lesson) | 8.953 % left at 0.02 s | 8.949 | 0 | ✓ |
| Middle pluck | E₀ 1.938462 mJ; shares 81.073, 0, 9.008 %; even modes none | 1.938462; 81.059, 4·10⁻²⁶, 9.008 | 0 | ✓ |
| Single mode n = 3 | E = ρ L h² ω₃² / 4 = 21.5233 mJ, all of it in mode 3, none lost | 21.5194, 100 %, 100 % | −2·10⁻⁴ (the discrete mode) | ✓ |
| Struck string (2 m/s, 0.12 L, width 0.01 L) | E₀ = 9.776 µJ; shares 0.679, 2.345, 4.086, 4.954 %; 17.48 % left | 200 elements: 9.584, 0.693, 2.391; 800: 9.763, 0.680, 2.348, 4.092, 4.961; 17.50 | 2 % at 200 elements (the hammer is 2 elements wide) | ✓ (accepted, documented) |
| Fixed–free string, pluck at 0.2 L | f₁ = c/4L = 131.3712 Hz, ratios 3, 5; shares 38.711, 29.481, 16.215, 5.415 %; 78.06 % left | 131.3712, 3, 5; 38.701, 29.475, 16.213, 5.415; 78.05 | 10⁻⁴ | ✓ |
| Ruler: cantilever 0.3 m, EI 0.5, ρA 0.2355 | f = 9.059786, 56.77671, 158.9764, 311.5303 Hz; f₂/f₁ 6.266893 | 9.059786, 56.77671, 158.9765, 311.5306 | 10⁻⁶ | ✓ |
| … plucked 20 mm at 0.99 L (static deflection) | E₀ = 3 EI δ²/2a³ = 11.45122 mJ; shares 97.30, 2.310, 0.2759, 0.0670 %; 31.381 % left after 1 s (ζ 1 %) | before: 1.070 J at 60 elements, 0.474 at 30, 4.35 at 240, shares 1.4 % each, dominant mode 18–72; after: 11.45123 mJ, 97.305, 2.3095, 0.2759, 0.0670, 31.381 (60 or 240 elements) | ✗ → 10⁻⁶ | ✗ → ✓ (finding 1) |
| Xylophone key: free–free 0.3 m, EI 233, ρA 1.08 | f₁ = 4.73004² √(EI/ρA)/(2π L²) = 581.1302 Hz; 2.756539, 5.403918 | 581.1302, 2.756539, 5.403922 | 10⁻⁶ | ✓ |
| … struck 1 m/s at the middle, width 0.02 L | flexible energy ½∫ρA v² − drift = 3.85716 mJ; mode 1 0.2991 mJ | before 3.7631 (−2.4 %); after 3.8441 at 60 elements, 3.8571 at 240; mode 1 0.2991 | 10⁻⁵ at 240 | ✓ (finding 2) |
| Clamped beam, Gaussian bump 3 mm, width 0.1 L | E = ½∫EI u''² = 33.8395 mJ; shares 0.9696, 13.06, 33.55 % | before 34.390 (+1.6 %); after 33.8393, 0.9696, 13.064 | 5·10⁻⁶ | ✗ → ✓ (finding 2) |
| Lesson numbers | 263 Hz (262.7, c 342 m/s); mode 2 and mode 5 absent; f₂/f₁ = 6.27; under 50 % left with ζ 2 % (8.95 %) | as stated | — | ✓ |

## Automatic checks

From `captureVerification`: every preset solves in under 0.1 s headless; every Summary number
reaches the metrics; every exported column has its units (time, probe displacement, kinetic,
potential and total energy), with no non-finite values; a second solve gives the identical result.

### In the app (`dlab.dev.checkBehaviour`)

All eleven pass: every preset loads and runs (slowest 6.6 s for the first run while MATLAB warms
up, median 0.9 s); undo and redo of L; a scenario round trip; CSV, MAT, plot and report exports
(7 images); a 10-frame GIF; a sweep of L; a map of L × tension; uncertainty of L ± 2 %; a short
optimization of the fundamental over L; theme and text-size switches keep the result.

### Tests

`tests/sims/wave` (new: `testBeamPluckIsItsStaticDeflection`,
`testSmoothBeamStartHasItsBendingEnergy`, `inputsFitAndExplainThemselves`,
`rulerSoundsMostlyItsFundamental`, `nodesGiveExactlyNoEnergy`) and `TestLessons`: 59 passed,
0 failed. None excluded. `codeIssues` on every touched file: 0.

## Checklist

- [x] Physics: element matrices, supports, rigid-body modes, modal time response and energies
  checked by hand; the beam pluck fixed (finding 1); docs and `about()` match
- [x] Numbers: every preset, the fixed–free string, a clamped beam, and mesh convergence against
  the references
- [x] Inputs: labels, units, ranges, tooltips (added for 14 inputs, finding 3), visibility
  (string or beam properties, width only for strike and bump, mode number only for one mode)
- [x] Outputs: every tab readable in both themes and at Larger text (findings 3, 5, 6); the
  animation agrees with the space-time plot and the probe
- [x] Summary and exports: Summary, plots and CSV agree; units everywhere (finding 6)
- [x] Analysis: Sweep, Map, Optimize and Uncertainty sensible on L and the tension; no Modes or
  Bode tab (the Mode shapes tab lists the frequencies)
- [x] Teaching: every lesson number checked (all right)
- [x] Behaviour: readable errors (too many stored values, a pluck at an end); nothing left behind
  on preset, theme or size changes

## Findings

| # | Area | Finding | Resolution | Test |
|---|---|---|---|---|
| 1 | Physics | A plucked beam started from a string's triangle (for a cantilever, a ramp that left the clamp at a slope): a kink whose bending energy grows with the mesh. The ruler preset started with 1.07 J (0.47 J on 30 elements, 4.35 J on 240) for a true 11.5 mJ, spread its energy evenly over every mode (Mode content rose towards mode 20), and named mode 18 dominant. | A beam is plucked from its static deflection under a point load at the pluck point (K⁻¹F from the modes, so a free bar works too), scaled to the amplitude there: the ruler holds 97.3 % in mode 1, as the exact modes give, on any mesh. | `testBeamPluckIsItsStaticDeflection`, `rulerSoundsMostlyItsFundamental` |
| 2 | Numbers | A beam's starting slopes came from `gradient` of the nodal values: a smooth bump started with 1.6 % too much energy, a narrow strike 2.4 % too little. | Exact derivatives of the Gaussians. | `testSmoothBeamStartHasItsBendingEnergy` |
| 3 | Inputs | Choices were cut off ("Clamped – fr…", "Strike (initial …"; at Larger text "String (te…"), and 14 inputs had no tooltip. | "String" / "Beam", "Fixed–free", "Pinned" / "Cantilever" / "Clamped" / "Free–free", "Strike"; tooltips say what each is (the harmonics of each end condition, which end is clamped, the Gaussian's width). | `inputsFitAndExplainThemselves` |
| 4 | Summary | A mode with a node at the start showed "3.60002e−25 %". | Below 10⁻⁹ % it reads 0. | `nodesGiveExactlyNoEnergy` |
| 5 | Outputs | The tallest bar's frequency label ran off the top of Mode content ("262.7 H"). | Head room above the bars. | `nodesGiveExactlyNoEnergy` |
| 6 | Outputs | The probe spectrum's axis read "Amplitude" with no units. | "Amplitude (m)". | — |

Accepted:
- **"Amplitude (m or m/s)"**: one input is a displacement for a pluck, bump or mode and a speed
  for a strike; the label and tooltip say so. Splitting it would change saved scenarios.
- **A strike narrower than about three elements is under-resolved** (2 % of the struck string's
  energy at 200 elements); the docs now say so, and the Elements tooltip says more elements give
  accurate higher modes.
- **The probe spectrum of a 0.02 s run has 50 Hz resolution**: the peaks are broad because the
  record is short; a longer duration sharpens them.
