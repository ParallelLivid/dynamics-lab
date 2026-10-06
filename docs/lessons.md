# Writing lessons

A lesson walks a learner through one simulator, a step at a time. It opens in a column on the
right of the simulator, with the step's text, a **Load this setup** button, a **Check** button
that gives feedback, and Back/Next. Progress is remembered between sessions, and on the Home screen
each lesson is a button beside its simulator's **Open** button, showing the learner's progress
(the title and summary are in its tooltip).

Lessons are JSON files, so you can write one without touching any code. The quickest way is
from the app: set up a simulator the way a step should start, run it, and choose **Export ▸ Save
as lesson step…**. Give the step a title and some text, and optionally pick a key result to
check (within a tolerance you choose); the current inputs become the step's setup. Steps collect
into a lesson of your own, which appears on the Home screen at once. Edit the file afterwards to
add questions or the other checks below.

Lesson files live in two places:

- `resources/lessons/*.json` are shipped with the app (at least one per simulator).
- `Documents\DynamicsLab\lessons\*.json` are your own. They appear next to the shipped ones.

A file that can't be read is skipped. The tests check that every shipped lesson loads and can
be completed.

## Example

```json
{
  "format": "dynamicslab-lesson",
  "formatVersion": 1,
  "id": "projectile-best-angle",
  "title": "The best launch angle",
  "simulator": "projectile",
  "order": 3,
  "summary": "Find the angle that throws furthest, then see how air resistance changes the answer.",
  "steps": [
    {
      "title": "Which angle goes furthest?",
      "text": "Sweep the launch angle and plot Range. The peak is marked.",
      "setup": {
        "preset": "Defaults",
        "sweep": { "parameter": "theta", "from": 5, "to": 85, "steps": 17 },
        "tab": "Sweep"
      },
      "check": { "kind": "sweep", "parameter": "theta", "minRuns": 15,
                 "success": "45°, as sin(2θ) predicts." },
      "solution": { "sweep": true }
    }
  ]
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `format`, `formatVersion` | yes | `"dynamicslab-lesson"` and `1` |
| `id` | yes | Unique id; also the file name by convention |
| `title`, `summary` | title | Shown in the Home lesson button's tooltip (and found by Home search) and at the top of the lesson |
| `simulator` | yes | The simulator `Id` (`dlab.simulators()` lists them). Lessons for simulators that aren't available are hidden. |
| `order` | no | Order of a simulator's lesson buttons on its Home card (default 100) |
| `steps` | yes | One or more steps |

### Step

| Field | Required | Meaning |
|---|---|---|
| `title`, `text` | yes | `\n` starts a new line |
| `simulator` | no | Run this step in another simulator: the lesson moves there (and back), so one lesson can compare models |
| `setup` | no | What **Load this setup** does (below). One undo step: Ctrl+Z reverts it. |
| `check` | no | What **Check** tests (below). Without it, the step is just reading. |
| `solution` | with a check or claims | Never shown. Tests apply it and require the check to pass. |
| `claims` | when the step states numbers | Never shown. The numbers the step's `text` and `success` state, checked by the tests after the solution has run (below). |

### Setup

All fields are optional and applied in this order:

| Field | Effect |
|---|---|
| `preset` | Start from a built-in preset (or `"Defaults"`) instead of the current inputs |
| `params` | Input values by name, e.g. `{ "theta": 30, "model": "sphere" }`. Schedules can be numbers or schedule objects. |
| `keepRuns` | Tick or untick **Keep previous runs** |
| `sweep` | Fill in the Sweep tab: `parameter`, `from`, `to`, `steps`, optional `log` (it is not run) |
| `map` | Fill in the Map tab: `x` and `y`, each with `name`, `from`, `to`, `steps`, optional `log` |
| `optimize` | Fill in the Optimize tab: `inputs`, `metric`, optional `goal` (`"maximize"` or `"minimize"`), `bounds` (one `[from, to]` per input), `constraint` (`metric`, `type` `"<="` or `">="`, `value`) |
| `uncertainty` | Fill in the Uncertainty tab: `inputs` (each `name`, `spread`, optional `kind` `"uniform"`/`"normal"`, `relative`), optional `samples`, `seed` |
| `bode` | Show `input` → `output` on the Bode tab after the next run |
| `measured` | Import measured data for the Fit tab and the Custom plot: a CSV in `resources/data` (by name) or a path |
| `fit` | Fill in the Fit tab: `measured` and `simulated` column names, `inputs` to fit |
| `tab` | Select an output tab, e.g. `"Modes"` (the Summary and Runs tabs exist only after a run) |

### Checks

Every check may add `hint` (shown when it fails) and `success` (shown when it passes).

| `kind` | Passes when | Fields |
|---|---|---|
| `run` | Results are up to date with the inputs | — |
| `metric` | Up-to-date results, and a key result is in range | `quantity` (as on the Summary tab), `min`, `max` |
| `input` | An input has a value | `name`, then `min`/`max`, or `value` (choices), or `shape` (schedules); for a table input, `min`/`max` count its rows |
| `sweep` | The last sweep varied this input, with enough successful runs | `parameter`, `minRuns` (default 2) |
| `map` | The last map varied these two inputs, with enough successful runs | `x`, `y` (either order), `minRuns` (default 4), optional `quantity` with `min`/`max` on its largest value |
| `optimize` | A finished search varied these inputs (and met its limit, if any) | `inputs`, optional `metric`; optional `input` with `min`/`max` on its best value, or `min`/`max` on the best result |
| `uncertainty` | A Monte Carlo study with enough runs | `minRuns` (default 20), optional `inputs` that must be varied, optional `quantity` with `statistic` (`Mean`, `Std`, `P05`, `P95`, `Min`, `Max`; default `Std`) and `min`/`max` |
| `modes` | Up-to-date results, and the Modes tab lists this mode | `mode`, optional `quantity` (`Period`, `NaturalFrequency`, `DampingRatio`, `TimeConstant`) with `min`/`max` |
| `fit` | A finished fit of these inputs | `inputs`; optional `input` with `min`/`max` on its fitted value, or `min`/`max` on the RMS misfit |
| `bode` | Up-to-date results, and the Bode tab shows this response | optional `input`, `output`, and `quantity` (`DCGain`, `PeakGain`, `PeakFrequency`, `Bandwidth`, `PhaseMargin`, `GainMargin`) with `min`/`max` |
| `choice` | The learner picked the right option (shown as buttons under the text) | `options` (a list of answers), `answer` (the number of the right one, from 1) |
| `runs` | Enough earlier runs are kept | `min` (default 1) |
| `all` | Every check in `checks` passes; the first failure is reported | `checks` |

The failure messages explain what's missing (for example "Range is 220.7 m; aim for at least
250 m."), so a `hint` only needs to add the next idea to try.

### Solution

| Field | Effect |
|---|---|
| `params` | Inputs to set (as in a setup) |
| `keepRuns` | Tick Keep previous runs first |
| `run` / `runs` | Press Run once, or this many times |
| `sweep`, `map`, `optimize`, `uncertainty`, `fit` | Run what that tab is set up to do (`true`) |
| `answer` | Pick this option of a `choice` |

### Claims

A check decides whether the learner has done the step; a claim makes sure the step's words are
true. Every number a step states ("about 52 g against the formula's 50 g", "it settles in about
2 s instead of 3.3 s") gets a claim, checked against the run the solution makes. A claim is
written like a check, usually `metric` or `modes`, with `value` and a relative `tolerance`
(default 0.01) in place of `min` and `max`:

```json
"claims": [
  { "kind": "metric", "quantity": "Peak deceleration", "value": 52.48, "tolerance": 0.01 },
  { "kind": "modes", "mode": "Dutch roll", "quantity": "Period", "value": 3.244 },
  { "kind": "metric", "quantity": "Return error", "max": 1e-6 }
]
```

Take each claim's value from an independent calculation (the simulator's verification sheet),
not from a run of the simulator: a claim checks the simulator as well as the text. Make the
solution do what the text describes ("try −5.5°" needs a solution at −5.5°). Numbers about runs
the solution does not make (a comparison with another setting) belong in the text of a step that
makes that run, or are left out.

## Tips

- Find the numbers for checks with `dlab.run` and `dlab.sweep`, for example
  `dlab.sweep("projectile", "theta", 30:50, model="sphere")`.
- Allow some slack in `min`/`max`, so that a learner who gets close passes. Claims can be tight:
  they check the solution's run, not the learner's.
- Test a new lesson with `buildtool test`. The lesson test works through every shipped lesson
  with its solutions.
