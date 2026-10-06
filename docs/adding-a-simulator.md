# Adding a simulator to Dynamics Lab

Plugin API **v1.2**. Changes since v1.0 only add optional hooks and fields with defaults, so
existing plugins never break; [plugin-api.md](plugin-api.md) lists every hook with the version that
added it. The latest additions are typed summary rows (`Format`, `Display`), the Bode tab's
linearization inputs (`G`, `U0`, `H`), and a control loop to break for margins (`Loop`).

Every simulator gets these from the shell without extra code: undo/redo, keyboard shortcuts,
Cancel, the Custom plot, Sweep, Map, Optimize, Uncertainty, and Fit tabs, animation export, the
HTML run report, and lessons. The analysis tabs read your `metrics` (and `exportTable` for Fit),
so give summary rows numeric values. The hooks below make them richer.

There are two reference implementations:

| Kind | Example | Read it for |
|---|---|---|
| Time-domain | [`+dlab/+sims/+pendulum/PendulumPlugin.m`](../+dlab/+sims/+pendulum/PendulumPlugin.m) | Standard parameter panel, plots, animation, presets |
| Static | [`+dlab/+sims/+truss/TrussPlugin.m`](../+dlab/+sims/+truss/TrussPlugin.m) | A custom input editor (`TrussInputs`), input preview, inputs that aren't specs |

## Quick start

```matlab
dlab.dev.newSimulator("doublependulum", "Double Pendulum")                  % time-domain
dlab.dev.newSimulator("beam", "Beam Deflection", Kind="static", Category="Structural")
```

This generates everything the build asks of a simulator, around a placeholder model (exponential
decay, or a parabola for static plugins), so the whole suite passes before any physics is written:

| File | What it is |
|---|---|
| `+dlab/+sims/+<id>/<Name>Plugin.m` | The plugin: the required methods plus a preset, typed summary rows (`Format`, `Display`), `overlayRuns`, `showcase`, `about`, and progress reporting from `solve` |
| `+dlab/+sims/+<id>/simulate<Name>.m` | The placeholder engine |
| `tests/sims/<id>/test_simulate<Name>.m` | Engine tests with golden values, one marked as an independent reference |
| `tests/sims/<id>/Test<Name>Plugin.m` | An app test, tagged `ui` |
| `docs/sims/<id>.md` | The docs page |
| `resources/lessons/<id>-intro.json` | A one-step lesson (a `run` check, its solution, and a claim) |
| `resources/thumbnails/<id>-dark.png`, `-light.png` | Placeholder Home thumbnails |
| `docs/verification/<id>.md` | The verification sheet, in review, with the placeholder's reference value |

It also adds the plugin to the registry and a row to the README's simulator table, under its
category (`Register=false` prints both instead), so it appears on the main menu at once. Then
replace the placeholder model and rewrite each of these for it, run `buildtool images` for real
thumbnails, and work through the checklist.

## Checklist

1. Create `+dlab/+sims/+<id>/` (`<id>` = lowercase letters/digits) and put the engine there.
   The engine must not depend on Dynamics Lab. It throws, or returns an error, for bad input.
   Inside the package, calls to sibling files must be qualified: `dlab.sims.<id>.helper(...)`.
2. Create `<Name>Plugin.m` in that folder, subclassing `dlab.core.TimeDomainPlugin` or
   `dlab.core.StaticPlugin`.
3. Add one line to [`+dlab/+sims/registry.m`](../+dlab/+sims/registry.m).
4. Add `tests/sims/<id>/` with engine tests and **golden values** (known-correct numbers). At
   least one test asserts a value worked out **independently** of the engine (a closed form, a
   published result, a hand calculation, or a separate integration) and says so on its first line:
   `% Independent reference: <source>`. Golden values taken from the engine's own output only
   pin down what it does today.
5. Add a docs page `docs/sims/<id>.md`, a row in the README's simulator table, a lesson in
   `resources/lessons/` (every number its text states is a `claim`: [lessons.md](lessons.md)),
   and thumbnails (`buildtool images`).
6. Give every input a `Description` (its tooltip), keep choice labels short enough for their
   field, and keep the Summary's units column for units.
7. Run `buildtool`. `PluginConformanceTest` checks your plugin automatically, and
   `ArchitectureTest` checks the rules below.
8. Verify it before calling it done: [verification/README.md](verification/README.md), "Adding a
   simulator". The sheet `docs/verification/<id>.md` records the independent values and what was
   found.

## The contract

### Required (every plugin)

| Member | Purpose |
|---|---|
| `Id`, `Title`, `Category`, `Summary`, `SchemaVersion` | Constant properties. `Category` groups the Home cards. Bump `SchemaVersion` when parameter names or meanings change, and implement `migrate`. |
| `parameters()` | Column of `dlab.core.ParamSpec` (below). |
| `solve(params)` | Run the engine and return its result unchanged. Throw for bad input; the message goes to the status bar, so make it readable. |
| `outputTabs(params)` | Plot tab titles. Don't use the shell's titles (Animation, Summary, Runs, Analyze, and the analysis tools inside it: Custom plot, Sweep, Map, Optimize, Uncertainty, Fit, Modes, Bode; see `SimulatorView.ShellTabs`). |
| `buildOutputs(containers, theme)` | `containers{"Title"}` is an empty `uigridlayout` per tab. Create axes and graphics here **once**, and store `theme`. |
| `showResult(result, params)` | Update the graphics (set `XData`/`YData`; don't recreate axes). |
| `clearResult()` | Blank the outputs. |
| `exportTable(result)` | A `table` with `VariableUnits` set, used for CSV export. |

### Time-domain plugins add

| Member | Purpose |
|---|---|
| `timeVector(result)` | Ascending column of sample times. |
| `buildAnimation(parent, theme)` | Create the animation graphics. |
| `drawFrame(simTime)` | Called up to 30× per second. Only move existing objects. Use `dlab.core.frameAt(t, simTime)` to find the sample. |

#### The animation, insets, and export

`parent` is a one-cell grid. **Export animation** (MP4 or GIF, `dlab.core.AnimationExporter`)
calls `drawFrame` for each frame and records every axes in that grid from the screen. With one
axes the frame is its plot box. With more (a side view, an inset) it is the screen area covering
all of them, titles and tick labels included, so they appear in the video as laid out on screen.
Anything you want in the video must therefore be drawn in an axes inside `parent`: a `uilabel` or
other control is not recorded.

For an inset over a corner of the main view, give the grid overlapping cells: the main axes spans
all of them and the inset takes one, created after the main axes so that it is drawn on top.
Spacecraft Attitude Control puts its wheel-momentum bars in the lower left:

```matlab
grid = uigridlayout(parent, [2 2], Padding=0, RowSpacing=0, ColumnSpacing=0, ...
    RowHeight={'1x', 160}, ColumnWidth={190, '1x'}, BackgroundColor=theme.AxesBackground);
ax = dlab.ui.axesIn(grid, theme, Title="Spacecraft attitude", Row=[1 2], Column=[1 2]);
wheels = dlab.ui.axesIn(grid, theme, Row=2, Column=1);    % the inset, on top
```

Side-by-side axes work the same way in separate cells (Gravity Assist's view around the
Sun). Keep the axes in one grid layout, as here: given any axes in a grid, the exporter records
that whole grid. To hide an inset for some runs, delete its children, clear its title, and set its
`Visible` to `"off"`.

### Optional hooks (with defaults)

| Hook | Use it for |
|---|---|
| `presets()` | `struct("Name", ..., "Values", partialParams)` array. Values merge over the defaults. |
| `summaryTable(result)` | `Quantity` / `Value` / `Units` table. Returning any rows makes the shell add a Summary tab. |
| `metrics(result)` | Numeric key results (`Quantity`, `Value` as double, `Units`) for sweeps, the Runs tab, and lesson checks. The default keeps the summary rows whose value is a number: give `summaryTable` numeric `Value`s with a `Format` (and `Display` for text rows) rather than overriding this. |
| `distributions(result)` | Results with many values per run, for sweeps: a table of `Quantity`, `Values` (a cell of double columns), and `Units`. The Sweep tab can plot every value at each swept input, which is how a bifurcation diagram is made from Poincaré points, and `dlab.sweep` returns them in `T.Properties.UserData.Sets`. |
| `overlayRuns(runs)` | Draw earlier runs faintly for **Keep previous runs**. `runs` is a struct array (`Result`, `Params`, `Label`, `Color`); draw with `dlab.ui.overlayLine(ax, x, y, run)`, which tags the lines so the shell can clear them. Implementing it is what makes the checkbox appear. |
| `linearization(params)` | The model near an equilibrium, for the **Modes** tab: a struct with `F` (`@(x) dx/dt` at constant inputs), `X0`, `StateNames`, `Reference` (a phrase such as `"hanging straight down"`), and optionally `Classify` (`@(lambda, V)` mode names) and `Scale`. Return `[]` when there is none. Implementing it adds the tab. To add the **Bode** tab too, give the model inputs: `G` (`@(x, u)` dx/dt with inputs `u`), `U0` (the nominal inputs, so that `F(x) == G(x, U0)`), and `InputNames`; optionally `H` (`@(x, u)` the outputs) with `OutputNames` (without `H` the outputs are the states), and `InputUnits` / `OutputUnits` to label them. The tab shows the gain and phase from any input to any output, with the DC gain, resonance, and bandwidth (`dlab.core.FrequencyResponse`). For a controlled model, add `Loop`: the loop broken where the controller's output enters the plant (`G` and `H` for the opened loop, with a signal `u` injected there and `H` the signal that comes back, plus `X0`, `U0`, and a `Name`); the tab then offers the loop gain with its gain and phase margins (DC Motor Servo and the cart-pole do). `Markers` mark frequencies of interest and `FrequencyUnits` (`"Hz"`) sets the axis (the quarter car does both). |
| `onParamChanged(name, params)` | Coupled inputs (for example, picking a planet sets the step). Return the adjusted params. |
| `buildExtraControls(parent, theme)` | Controls below the parameters. |
| `requestInputs(changes, label)` | *Not a hook: a method to call.* Set inputs from your own controls, for example a "Use optimal angle" button. `changes` is a partial params struct. The view validates it and applies it as one undo step that marks results stale, like an edit. |
| `currentInputs()`, `reportStatus(message, level)` | *Methods to call.* The inputs on screen (for a button that computes from them, like a trim), and a status-bar message (e.g. why it could not). |
| `buildPlaybackControls(parent, theme)` | Controls inside the playback bar (time-domain plugins). |
| `playbackRate(result)` | Simulated seconds per wall-clock second at 1× (default 1 = real time). Orbit returns `duration / 20`, so hours of orbit play in about 20 s. |
| `buildInputs(parent, params, theme)` | Replace the generated panel entirely (see below). |
| `previewInputs(params)` | Static plugins: draw the unsolved model on every edit. |
| `defaultParams()` | Override when params include fields that aren't specs (Truss's model tables). |
| `paramsToJson` / `paramsFromJson` | Shape fixes for scenario files (for example, `jsondecode` turns a one-row matrix into a vector). |
| `migrate(params, fromVersion)` | Upgrade older scenario files. |
| `resultNote(result)` | A note added to the status after Run, plus its colour (e.g. `"ended early: ground contact"`, `"warning"`). |
| `about()` | Model description shown by the ? button. |
| `showcase()` | Preset, tab, and playback time for the Home thumbnail and README screenshot (`buildtool images`). |
| `RunLabel` | Set in the constructor (Truss uses `"Solve"`). |

### Progress and Cancel

Long solves should report progress, because that is also how **Cancel** (and Esc) reaches the
engine. Hand `obj.progressMonitor()` to the engine. The engine calls it as
`stop = progressFcn(fraction)` (a value from 0 to 1, or `NaN` if unknown) and stops when it
returns `true`. For an ODE solver that is one `OutputFcn`, made by `dlab.physics.odeProgress`
from the solver's time span:

```matlab
% in the plugin
p.progressFcn = obj.progressMonitor();
result = dlab.sims.myid.simulate(p);
result.params = rmfield(result.params, "progressFcn");   % keep results free of callbacks

% in the engine
options = odeset(options, "OutputFcn", dlab.physics.odeProgress(p.progressFcn, tspan));
```

Report as often as is convenient (every step is fine): `Plugin.progress` passes a report on to
the window only when the fraction has grown by 1 % or 50 ms have passed. A report still costs
a few microseconds, so a loop whose steps take only that long reports every few percent.

If a solve is cancelled, the shell discards whatever it returns, and any error it throws, so a
partial result needs no special handling. The engine still depends only on base MATLAB: it
receives a plain function handle.

## `ParamSpec` quick reference

```matlab
P = @dlab.core.ParamSpec;
P("L", Label="Length", Units="m", Default=1, Min=0.1, Max=10, Group="Pendulum", ...
    Description="Shown as the tooltip, with the allowed range appended.")
P("model", Type="choice", Choices=["point" "drag"], ChoiceLabels=["Point mass" "With drag"])
P("Cd", Default=0.47, VisibleWhen=@(p) p.model == "drag")   % hidden rows take no space
P("n", Type="integer", Min=1)
P("tspan", Label="Duration", MarksCustom=false)   % editing keeps the preset name
P("labels", Type="logical", Display=true)         % redraws; never makes results stale
P("tol", Group="Solver", Advanced=true)           % its group starts collapsed
P("u", Type="schedule", Default=0, Min=-1, Max=1)  % can change during the run
P("stages", Type="table", MinRows=1, MaxRows=3, Columns=[       % a list of rows
    dlab.core.TableColumn("mass", Label="Mass", Units="kg", Min=0, Default=100)
    dlab.core.TableColumn("kind", Type="choice", Choices=["solid" "liquid"])])
```

A `table` input's value is a MATLAB `table` with the columns in order (`double` for numeric
columns, `logical`, and `string` for choices). Presets and scripts may give a numeric matrix
(without choice columns), a struct array, or a table. The panel shows an editable grid with
"+ Row" and "Delete selected"; scenario files store it as an array of row objects. Tables are
never swept.

A `schedule` input is a constant, step, pulse, doublet, ramp, sine, or custom points. Its value
is a struct; a plain number (in a preset or an old scenario file) means a constant. Give the
engine a function of time:

```matlab
u = dlab.core.Schedule.toFunction(p.u, [-1 1]);   % @(t) value, clipped to [-1, 1]
```

Store the schedule (not the function) in your result if you keep inputs there. The 6DOF
controls and the Mass-Spring force profiles are worked examples.

Inputs, outputs, and analysis also work from code: `dlab.run`, `dlab.sweep`, and
`dlab.simulators` take any registered simulator.

## Shared physics

`+dlab/+physics` holds code that more than one model needs, because plugins can't import each
other: `atmosphere` (ISA 1976), `rotx`/`roty`/`rotz`, `eulerToDcm`, `eulerRates`,
`Quaternion`, `kep2cart`/`cart2kep`, `gravity` (point mass and J2), `bodyConstants`,
`convertUnits`, `jacobian`, `care` and `lqr` (Riccati equation and LQR gains, as the Control
System Toolbox is not available), `modalResponse` (free response of a linear system), and
`fitDampedResponse` (poles of a measured response), `thermosphereDensity` (Earth's air density
from the ground to 1000 km, for orbital drag), `uniformSequence` (reproducible random numbers
from a seed), `amplitudeSpectrum` (one-sided, Hann-windowed, with a refined peak), and
`sectionLibrary` (structural materials and cross-sections). `atmosphere(h, Extended=true)`
continues above 86 km. It depends on base MATLAB only, so engines may use it.

## Shared drawing

`dlab.ui.Schematic` returns the coordinates of mechanical symbols in any orientation: `spring`,
`damper`, `hatch` (ground), `circle`, `wheel`, `rect`, `arrow`, `discs` (many particles as one
patch), and the 3-D `box3` and `cone3`. It draws nothing, so build your lines and patches once and
update their data each frame. (Mass-Spring keeps its own horizontal `Schematic`, which its tests
pin down.) For heatmaps and colored speeds, use `theme.sequentialMap(n)` or
`theme.divergingMap(n)` rather than built-in colormaps.

`dlab.ui.NodeDragger` lets the user drag the points of a model on an axes. It previews each move
through your callback and commits once on release, so a drag is one undo step. Truss uses it,
committing through its editor; a standard-panel plugin commits with `requestInputs`.

Worked examples of the newer pieces: the Frame solver (`+dlab/+sims/+frame`) uses table inputs,
`NodeDragger`, and `requestInputs` together; Nonlinear Oscillators uses `distributions` for
bifurcation sweeps; the Quarter-Car and Cart-Pole animations are built from `Schematic`; Rocket
and Maneuvers use table and schedule inputs side by side.

## Custom input panels

`buildInputs` may return any handle object with:

- `Grid`, the root `uigridlayout`, placed at `Layout.Row = 1` of the given parent
- `values()`, which returns the full params struct
- `setValues(params)`, which updates silently, without firing events
- `setEnabled(tf)`
- a `ValueChanged` event with `dlab.core.ParamChangedData`; `Name` may be a non-spec input such as `"nodes"`
- optionally, a `StatusMessage` event with `dlab.core.StatusData`, which the view shows in the status bar

Embedding a `dlab.core.ParamPanel` for the scalar specs and forwarding its `ValueChanged` event is
the easiest route (`TrussInputs` does this).

## Rules enforced by tests

- **Colors come from the theme.** Use `theme.series(k)`, `theme.Accent`, `theme.Text`, and so on.
  No RGB literals or named colors appear in plugin, core, or UI code. Physical data colors in
  engines (for example, planet colors) are allowed.
- **Plugins are independent.** A plugin never references another `dlab.sims.*` package, and the
  framework never references a plugin except through `registry.m`. Shared code goes in
  `+dlab/+physics`, which depends on nothing else.
- **Every `*Plugin.m` is registered**, and every registry entry has a file.
- **Every test file loads.** A broken test file would otherwise be skipped silently.
- In conformance, **defaults and every preset solve**, scenario files round-trip losslessly,
  and the plugin builds and draws headless in both themes. Metrics are finite numbers,
  linearizations (if any) analyze, and overlays (if any) draw.
- **Every input has a tooltip** (`Description`), and **every choice label fits its field** (about
  85 px of text at the normal size: "Crank–Nicolson" fits, "Single pendulum" does not). Put the
  detail in the tooltip.
- **The Summary keeps units in the units column**, for every preset: no "relative" or "yes = 1"
  there (write "Energy drift (relative)", and yes/no in `Display`); a value that is not finite is
  shown as text in `Display`; a name does not repeat its units ("Duration (s)" in s).
- **Every preset's plots read**: drawn as the app draws them, no plot's y axis spans only
  round-off on a steady value (give it `dlab.ui.minimumSpan`), and no two labels print over each
  other. The view pads the y limits of 2-D plots (`dlab.ui.padLimits`), so a steady trace does not
  lie on the frame.
- **Every simulator is checked against independent values**: it has a verification sheet with a
  reference table, and a test marked `% Independent reference:`.
- **Every lesson claim holds**: `TestLessons` checks each step's `claims` after its solution.

## Tips

- Build graphics once in `buildOutputs` and update them in `showResult`. Labels and legends then
  survive re-runs, and theme switches come for free (the shell rebuilds the whole view).
- Downsample long results for plots (Pendulum caps them at 5,000 points), but animate from the
  full data.
- Avoid MATLAB `TestCase` method names in test helpers (for example, `run`). The file would be
  skipped, and `ArchitectureTest` would flag it.
