# Plugin API v1.2

The contract between a simulator and Dynamics Lab: what a plugin class must provide, the
optional hooks that make the shell do more, and the services the shell offers back. This page
lists the API; [adding-a-simulator.md](adding-a-simulator.md) explains how to use it with
examples.

**The definition is the test.** `tests/PluginConformanceTest.m` runs every registered plugin
through the contract (metadata, inputs, every preset solving, outputs drawing in both themes,
metrics, distributions, linearizations, scenario round trips, and a run inside the shell). A
plugin that passes it is a valid plugin; where this page and the test disagree, the test wins.

## Versions and compatibility

- **v1.0** (Dynamics Lab 1.0.0): the required methods and the first optional hooks.
- **v1.2** (after 1.4.0): optional linearization fields for the Bode tab: `Loop` (a control loop
  to break, for gain and phase margins), `Markers`, and `FrequencyUnits`.
- **v1.1** (Dynamics Lab 1.1.0 to 1.4.0): optional hooks only. Every v1.0 plugin is a valid v1.1
  plugin and gets the newer analysis tabs (Sweep, Map, Optimize, Uncertainty, Fit, Custom plot,
  run report) without changes.

The API grows only by optional hooks and optional fields, each with a default in
`dlab.core.Plugin`. A change that would break an existing plugin would make it v2.

## A plugin class

```matlab
classdef MyPlugin < dlab.core.TimeDomainPlugin     % or dlab.core.StaticPlugin
    properties (Constant)
        Id = "my"; Title = "My Simulator"; Category = "Mechanics"
        Summary = "One line for the Home card"; SchemaVersion = 1
    end
    ...
end
```

Register it in `+dlab/+sims/registry.m` (a test fails if a `+dlab/+sims/+<id>` package is
missing there). Plugins never refer to one another; shared physics goes in `+dlab/+physics`.

### Constant properties (required)

| Property | Meaning |
|---|---|
| `Id` | Stable key: scenarios, session files, thumbnails, lessons, `dlab.run` |
| `Title` | Display name |
| `Category` | Home group: Mechanics, Controls & Vehicles, Aerospace, Structural, Continuum |
| `Summary` | One line for the Home card |
| `SchemaVersion` | Bump when input names or meanings change (see `migrate`) |

`RunLabel` (default `"Run"`) may be set, e.g. `"Solve"` for static plugins.

### Required methods (v1.0)

| Method | Contract |
|---|---|
| `parameters()` | Column of `dlab.core.ParamSpec` (types double, integer, logical, choice, schedule, table) |
| `solve(params)` | The engine: plain inputs in, a result out. Throw on invalid input; the message reaches the user |
| `outputTabs(params)` | Plot tab titles (string row), not the shell's own (`SimulatorView.ShellTabs`) |
| `buildOutputs(containers, theme)` | Create graphics in each tab's empty grid; keep the theme |
| `showResult(result, params)` | Draw a result |
| `clearResult()` | Blank every output |
| `exportTable(result)` | The result as a table with `VariableUnits` (CSV export, Custom plot, Fit) |

Time-domain plugins (`dlab.core.TimeDomainPlugin`) also implement `timeVector(result)`,
`buildAnimation(parent, theme)`, and `drawFrame(simTime)` (update existing graphics; called up to
about 30 times a second).

### Optional hooks

| Hook | Since | What it adds |
|---|---|---|
| `summaryTable(result)` | 1.0 | The Summary tab: `Quantity`, `Value`, `Units`; since 1.4 optionally `Format` (printf) and `Display` (text rows, with `Value` NaN), so numbers stay numbers |
| `presets()` | 1.0 | Built-in scenarios: struct array `Name`, `Values` (partial params) |
| `onParamChanged(name, params)` | 1.0 | Keep coupled inputs consistent after an edit |
| `buildInputs(parent, params, theme)` | 1.0 | A custom input panel (Truss's model tables) |
| `buildExtraControls(parent, theme)` | 1.0 | Buttons under the inputs |
| `resultNote(result)` | 1.0 | A line and level for the status bar after a run |
| `migrate(params, fromVersion)` | 1.0 | Read scenarios saved with an older `SchemaVersion` |
| `paramsToJson(params)`, `paramsFromJson(json)` | 1.0 | Inputs that need converting for scenario files |
| `showcase()` | 1.0 | The Home thumbnail and README screenshot: `Preset`, `Tab`, `Time` |
| `about()` | 1.0 | The model's equations for the About dialog |
| `previewInputs(params)` (static plugins) | 1.0 | Draw the model while it is being edited |
| `buildPlaybackControls(parent, theme)`, `playbackRate(result)` (time-domain) | 1.0 | Controls in the playback bar; the playback speed |
| `metrics(result)` | 1.1 | Numeric key results for Sweep, Map, Optimize, Uncertainty, Runs, and lesson checks. The default reads the numeric summary rows, so usually leave it |
| `overlayRuns(runs)` | 1.1 | "Keep previous runs": draw earlier runs faintly (tag them `dlab.overlay`) |
| `linearization(params)` | 1.1 | The Modes tab: `F`, `X0`, `StateNames`, `Reference`, optional `Classify`, `Scale`. Since 1.4, `G`, `U0`, `InputNames` (and optional `H`, `OutputNames`, `InputUnits`, `OutputUnits`) add the **Bode** tab; `F(x)` must equal `G(x, U0)`. Since 1.2 (API): `Loop` (`G`, `X0`, `U0`, `H`, `Name`: the loop broken where `Name` enters; the tab adds the loop gain L = −H/u with its margins), `Markers` (`Frequency` in rad/s, `Label`), `FrequencyUnits` (`"rad/s"` or `"Hz"`) |
| `distributions(result)` | 1.3 | Results with many values per run (Poincaré points): sweeps plot them all; maps count the distinct values |

### Services the shell provides

| Method | Since | Use |
|---|---|---|
| `progress(fraction)` / `progressMonitor()` | 1.1 | Report progress from `solve`; returns true when the user cancels |
| `requestInputs(changes, label)` | 1.3 | Set inputs from the plugin (a button, a drag) as one undo step |
| `currentInputs()` | 1.3 | The inputs shown on the left |
| `reportStatus(message, level)` | 1.3 | A status-bar message |
| `canRequestInputs()` | 1.4 | False while a run or study is in progress |
| `implements(name)` | 1.1 | Whether a plugin overrides an optional hook |

## Rules the build enforces

- Colours only from the theme (`ArchitectureTest.colorsComeFromTheTheme`).
- Base MATLAB only, and code that works when compiled.
- No plugin refers to another simulator's package.
- Every registered simulator has a docs page in `docs/sims`, a README row, light and dark
  thumbnails, and at least one lesson.
- UI tests carry the `ui` tag, so `buildtool fasttest` stays fast.
