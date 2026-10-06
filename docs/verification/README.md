# Verifying the simulators

Before anything is shared, every simulator is checked by hand as well as by its tests, one at a
time. This folder holds one sheet per simulator: what
was checked, against which independent values, what was found, how it was fixed, and the
sign-off.

## How a simulator is verified

1. **Preparation.** Run `dlab.dev.captureVerification("<id>")`. It solves every preset, checks
   that the Summary's numbers reach the metrics, that every exported column has units and finite
   values, and that a second solve gives the same result. It then saves the whole window with
   every output tab, the Summary, the animation at its start, middle, and end, and the Custom
   plot, Modes, and Bode tools: for every preset in both themes, and for the defaults at the
   largest text size. Everything lands in `verification/<id>/` (not in git), with an
   `index.html` to browse it. The sheet then sets the model as the engine implements it beside
   the docs page, and works out **reference values independently** of the engine and its tests
   (closed forms, published results, hand calculations), and compares them with the app's.
2. **Hands-on review.** Work through the simulator with the sheet's checklist. Write each
   finding in the sheet's Findings table, however small.
3. **Fixes.** Each finding is fixed (with a test where a test could have caught it) or
   explicitly accepted, and the sheet records which.
4. **Sign-off.** The sheet's Status line is set to verified, with the date.

## Adding a simulator

The first verification pass found 273 problems in 27 simulators, most of them the same few kinds. A new simulator is
verified before it is called done, and the build now catches those kinds by itself.

**Checked by the build** (`buildtool`; see [adding-a-simulator.md](../adding-a-simulator.md)):

| What | Where | First pass found |
|---|---|---|
| A tooltip on every input | `PluginConformanceTest/inputsHaveTooltips` | about 40 findings, over 100 inputs |
| Choice labels that fit their field | `PluginConformanceTest/choicesFitTheirFields` | about 23 |
| Units only in the Summary's units column, text rows as text, at every preset | `PluginConformanceTest/defaultsAndEveryPresetSolve` | about 14 |
| Plots that read at every preset: no round-off stretched over a steady value, no labels over each other | `PluginConformanceTest/plotsReadAtEveryPreset` (and `dlab.ui.padLimits` in the view) | about 33 |
| A verification sheet with independent reference values, and a test that asserts one (`% Independent reference: <source>`) | `ArchitectureTest/everySimulatorIsCheckedAgainstIndependentValues` | real bugs that the simulators' own tests confirmed |
| Every number a lesson states, as a claim checked against its solution's run | `TestLessons` (`claims`, [lessons.md](../lessons.md)) | about 22 |

**Done by the author** (the build cannot judge these):

1. Work out reference values independently of the engine (closed forms, published results, hand
   calculations, a separate integration in another language), for the defaults, **every preset**,
   and the edge cases, and compare them with the app. Mark at least one test that asserts them.
2. Run `dlab.dev.captureVerification("<id>")` and look at every picture of every preset, in both
   themes and at Larger text: what a picture shows (a label in the wrong place, an animation that
   disagrees with a plot, a run that ends oddly) is what the tests miss.
3. Take every number in the lesson and the docs page from the reference values, and give the
   lesson's numbers as claims.
4. Fill in the sheet (`dlab.dev.newSimulator` writes one in review), fix or accept each finding,
   and sign off in its Status line.

## Sheet template

```markdown
# <Title> — verification

Status: in review | verified (date)
Screenshots: verification/<id>/index.html (run dlab.dev.captureVerification("<id>") to make them)

## Model as implemented
Equations, units, signs, frames, assumptions, read from the engine; differences from the docs page.

## Reference values
| Case | Independent value (source) | App | Difference | Verdict |

## Automatic checks
The table from captureVerification (solve time, Summary vs metrics, export units and values,
determinism), with anything that needs a note.

## Checklist
- [ ] Physics: equations, units, signs, frames, assumptions match the docs page and about()
- [ ] Numbers: defaults, every preset, and edge cases against the reference values
- [ ] Inputs: labels, units, ranges, tooltips, visibility rules; presets load what they say
- [ ] Outputs: every tab readable in both themes and at Larger text; animation agrees with plots
- [ ] Summary and exports: Summary, plots, and CSV agree; units everywhere; the report is complete
- [ ] Analysis: Sweep, Map, Optimize, Uncertainty, Fit sensible; Modes and Bode against hand values
- [ ] Teaching: every lesson statement and number is right (each number a claim); checks pass for the stated reason
- [ ] Behaviour: readable errors; Cancel; run time; nothing left behind on preset/theme/size changes

## Findings
| # | Area | Finding | Resolution | Test |
```

The build requires the "Reference values" table to have at least one row and the "Findings"
section to exist.
