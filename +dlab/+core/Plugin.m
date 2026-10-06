classdef (Abstract) Plugin < handle
    %PLUGIN Contract every Dynamics Lab simulator implements.
    %   Subclass dlab.core.TimeDomainPlugin (simulations with playback) or
    %   dlab.core.StaticPlugin (solvers without a time axis), then add one
    %   line to dlab.sims.registry. See docs/adding-a-simulator.md.
    %
    %   Lifecycle, driven by dlab.core.SimulatorView:
    %     1. constructor            cheap; must NOT create UI (Home reads metadata)
    %     2. buildOutputs           once per view; create axes in the given tabs
    %     3. solve -> showResult    on every Run
    %     4. clearResult            on Reset
    %     5. delete                 when the view closes
    %
    %   Plugins read every color from the theme passed to buildOutputs;
    %   RGB literals are rejected by tests/ArchitectureTest.m.

    properties (Abstract, Constant)
        Id            % string: stable key ("pendulum"); scenarios, session, thumbnails
        Title         % string: display name ("Pendulum")
        Category      % string: Home-screen group ("Mechanics", "Aerospace", "Structural")
        Summary       % string: one line for the Home card
        SchemaVersion % double: bump when parameter names or meanings change
    end

    properties (SetAccess = protected)
        Theme  % dlab.ui.Theme passed to buildOutputs
    end

    properties
        RunLabel (1,1) string = "Run"
    end

    properties (Hidden)
        ProgressFcn = []   % set by the shell while solving: @(fraction) stop
        InputsFcn = []     % set by the view: @() current params (see currentInputs)
        BusyFcn = []       % set by the view: @() true while it runs a task (see canRequestInputs)
    end

    properties (Access = private)
        % What progress last passed on to ProgressFcn (see progress).
        LastReported = struct("Fcn", {[]}, "Fraction", -Inf, "Time", [], "Stop", false)
    end

    events
        InputsRequested   % dlab.core.InputsRequestData, from requestInputs
        StatusMessage     % dlab.core.StatusData, from reportStatus
    end

    methods (Abstract)
        specs = parameters(obj)
        %PARAMETERS Column vector of dlab.core.ParamSpec.

        result = solve(obj, params)
        %SOLVE Run the engine. Throw (any identifier) for invalid input;
        %   the message is shown to the user in the status bar.

        titles = outputTabs(obj, params)
        %OUTPUTTABS Titles of the plot tabs, in order (string row). Not
        %   including "Animation" (time-domain plugins get it automatically)
        %   or "Summary" (added when summaryTable returns rows).

        buildOutputs(obj, containers, theme)
        %BUILDOUTPUTS Create graphics. CONTAINERS is a dictionary mapping
        %   each outputTabs title to an empty uigridlayout ([1 1]).
        %   Store THEME (obj.Theme = theme) for later drawing.

        showResult(obj, result, params)
        %SHOWRESULT Draw RESULT into the graphics built by buildOutputs.

        clearResult(obj)
        %CLEARRESULT Blank every output.

        T = exportTable(obj, result)
        %EXPORTTABLE Result samples as a table with VariableUnits set.
    end

    methods
        function list = presets(~)
            %PRESETS Built-in presets: struct array with fields Name and
            %   Values (a partial params struct merged over the defaults).
            list = struct("Name", {}, "Values", {});
        end

        function params = onParamChanged(~, ~, params)
            %ONPARAMCHANGED Adjust coupled parameters after NAME changed
            %   (e.g. picking a planet sets a sensible output step).
        end

        function panel = buildInputs(~, ~, ~, ~)
            %BUILDINPUTS(obj, parent, params, theme) Return a custom input
            %   UI, or [] to let the shell build the standard ParamPanel
            %   from parameters(). A custom panel must offer what ParamPanel
            %   does: values(), setValues(params), setEnabled(tf), a Grid
            %   property, and a ValueChanged event (ParamChangedData).
            panel = [];
        end

        function buildExtraControls(~, ~, ~)
            %BUILDEXTRACONTROLS Optional controls below the parameters
            %   (parent is a uigridlayout; leave it empty to hide the slot).
        end

        function T = summaryTable(~, ~)
            %SUMMARYTABLE Key results: table with Quantity, Value, Units.
            %   Rows make the shell add a "Summary" tab. Value is best a
            %   number (metrics then reads it at full precision). Two
            %   optional columns control how the Summary shows it: Format,
            %   a printf format per row (e.g. "%.2f"), and Display, text
            %   that replaces the value outright (for rows with no number,
            %   such as "Termination", give Value NaN). Rows without either
            %   are shown with "%.6g".
            T = table.empty;
        end

        function T = metrics(obj, result)
            %METRICS Numeric key results: table with Quantity, Value
            %   (double), and Units. Parameter sweeps plot these, and the
            %   Runs tab and lessons compare them. The default keeps the
            %   summaryTable rows whose value is a plain number.
            T = obj.summaryTable(result);
            if isempty(T) || height(T) == 0
                T = table(strings(0, 1), zeros(0, 1), strings(0, 1), ...
                    VariableNames=["Quantity" "Value" "Units"]);
                return
            end
            values = T.Value;
            if iscell(values)
                values = cellfun(@numberOf, values);
            elseif ~isnumeric(values)
                values = str2double(string(values));
            end
            keep = isfinite(values);
            T = table(string(T.Quantity(keep)), double(values(keep)), string(T.Units(keep)), ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function D = distributions(~, ~)
            %DISTRIBUTIONS(obj, result) Results with many values per run,
            %   for sweeps: a table with Quantity (string), Values (cell of
            %   double columns), and Units. A sweep plots every value at
            %   each swept input (e.g. all Poincaré points: a bifurcation
            %   diagram). Empty by default.
            D = table(strings(0, 1), cell(0, 1), strings(0, 1), VariableNames=["Quantity" "Values" "Units"]);
        end

        function overlayRuns(~, ~)
            %OVERLAYRUNS(obj, runs) Draw earlier runs faintly over the
            %   current result, for "Keep previous runs". RUNS is a struct
            %   array (Result, Params, Label, Color). Tag every object
            %   "dlab.overlay" (dlab.ui.overlayLine does): the view deletes
            %   them before each redraw. Implementing this method is what
            %   makes the "Keep previous runs" option appear.
        end

        function lin = linearization(~, ~)
            %LINEARIZATION(obj, params) The model near an equilibrium, for
            %   the Modes tab: a struct with
            %     F           @(x) dx/dt at constant inputs (column in, column out)
            %     X0          reference state (column)
            %     StateNames  string row, one per state
            %     Reference   one line describing X0 ("hanging straight down")
            %     Classify    optional @(lambda, V) string labels per eigenvalue
            %     Scale       optional typical state magnitudes (finite-difference steps)
            %     TimeUnit    optional unit of the model's time when it is not
            %                 seconds, as a singular word ("time unit" for a
            %                 dimensionless model): rates per "time unit",
            %                 periods in "time units"
            %   and, for the Bode tab (dlab.core.FrequencyResponse), inputs:
            %     G           @(x, u) dx/dt with inputs u, so that F(x) == G(x, U0)
            %     U0          nominal inputs (column)
            %     InputNames  string row, one per input
            %     H           optional @(x, u) outputs (the states when absent)
            %     OutputNames string row, one per output (with H)
            %     InputUnits, OutputUnits  optional string rows (labels)
            %     Loop        optional control loop to break for margins (see
            %                 dlab.core.FrequencyResponse); Markers and
            %                 FrequencyUnits optional, for the plot
            %   Return [] when the model has no meaningful linearization for
            %   PARAMS. Implementing this method adds the Modes tab; giving G
            %   adds the Bode tab.
            lin = [];
        end

        function requestInputs(obj, changes, label)
            %REQUESTINPUTS Ask the view to set some inputs, for example
            %   from a button in buildExtraControls ("Use optimal angle").
            %   CHANGES is a partial params struct. The view applies it
            %   like user edits (onParamChanged runs for each changed
            %   input, then the requested values win), validates it, and
            %   records one undo step that marks results stale; LABEL
            %   names the action in the status bar.
            %   Nothing happens when no view is listening (scripting).
            arguments
                obj
                changes (1,1) struct
                label (1,1) string = "Inputs"
            end
            notify(obj, "InputsRequested", dlab.core.InputsRequestData(changes, label));
        end

        function tf = canRequestInputs(obj)
            %CANREQUESTINPUTS False while the view is busy (a run or a
            %   sweep), when requestInputs would be refused; e.g. to
            %   disable dragging on a canvas. True without a view.
            tf = isempty(obj.BusyFcn) || ~obj.BusyFcn();
        end

        function params = currentInputs(obj)
            %CURRENTINPUTS The inputs on screen (for plugin buttons that
            %   compute from them, like a trim); defaults without a view.
            if isempty(obj.InputsFcn)
                params = obj.defaultParams();
            else
                params = obj.InputsFcn();
            end
        end

        function reportStatus(obj, message, level)
            %REPORTSTATUS Show MESSAGE in the status bar (LEVEL "info",
            %   "success", "warning", or "error"), e.g. why a plugin
            %   button could not do its job.
            arguments
                obj
                message (1,1) string
                level (1,1) string = "info"
            end
            notify(obj, "StatusMessage", dlab.core.StatusData(message, level));
        end

        function stop = progress(obj, fraction)
            %PROGRESS Report solve progress to the shell (FRACTION in 0–1,
            %   NaN when unknown). Returns true once the user has cancelled;
            %   the engine should then stop (an ODE OutputFcn returns it).
            %   Engines may call this on every step: a report is passed on
            %   only when the fraction has grown by 1 %, 50 ms have passed,
            %   or the run is done; in between, the last answer is returned.
            stop = false;
            if isempty(obj.ProgressFcn)
                return
            end
            last = obj.LastReported;
            % A new run (another handle, or the fraction starting over)
            % forgets the last run's answer, so a cancel does not carry over.
            if ~isequal(last.Fcn, obj.ProgressFcn) || isempty(last.Time) || fraction < last.Fraction
                last = struct("Fcn", {obj.ProgressFcn}, "Fraction", -Inf, "Time", tic, "Stop", false);
            elseif ~(fraction >= 1 || fraction >= last.Fraction + 0.01 || toc(last.Time) >= 0.05)
                stop = last.Stop;
                return
            end
            last.Stop = logical(obj.ProgressFcn(fraction));
            last.Time = tic;
            if isfinite(fraction)
                last.Fraction = fraction;
            end
            obj.LastReported = last;
            stop = last.Stop;
        end

        function fcn = progressMonitor(obj)
            %PROGRESSMONITOR @(fraction) stop, to hand to an engine.
            fcn = @(fraction) obj.progress(fraction);
        end

        function [note, level] = resultNote(~, ~)
            %RESULTNOTE Short note appended to the status after a run, e.g.
            %   "ended early: ground contact". LEVEL "success" | "info" |
            %   "warning" colours the whole status line.
            note = "";
            level = "success";
        end

        function params = migrate(~, params, ~)
            %MIGRATE Upgrade params from an older SchemaVersion.
        end

        function json = paramsToJson(~, params)
            %PARAMSTOJSON Params as stored in scenario files.
            json = params;
        end

        function params = paramsFromJson(~, json)
            %PARAMSFROMJSON Inverse of paramsToJson, before validation.
            params = json;
        end

        function scene = showcase(obj)
            %SHOWCASE The view used for the Home thumbnail and README
            %   screenshot: Preset ("" = defaults), Tab (output tab title,
            %   or "Animation"), and Time (playback position; NaN = middle).
            tabs = obj.outputTabs(obj.defaultParams());
            scene = struct("Preset", "", "Tab", tabs(1), "Time", NaN);
        end

        function text = about(obj)
            %ABOUT Model description for the About dialog.
            text = obj.Summary;
        end

        function kind = kind(~)
            kind = "static";
        end

        function params = defaultParams(obj)
            params = dlab.core.ParamSpec.defaults(obj.parameters());
        end

        function params = presetParams(obj, name)
            %PRESETPARAMS Defaults with the named preset merged over them.
            params = obj.defaultParams();
            list = obj.presets();
            match = list(string({list.Name}) == name);
            if isempty(match)
                error("dlab:unknownPreset", "Unknown preset ""%s"".", name);
            end
            for field = string(fieldnames(match.Values))'
                params.(field) = match.Values.(field);
            end
            params = dlab.core.ParamSpec.validateAll(obj.parameters(), params);
        end

        function tf = implements(obj, method)
            %IMPLEMENTS Whether this plugin overrides the optional hook
            %   METHOD (e.g. "overlayRuns") rather than inheriting the default.
            arguments
                obj
                method (1,1) string
            end
            info = findobj(metaclass(obj).MethodList, "Name", method);
            tf = ~isempty(info) && ~startsWith(info(1).DefiningClass.Name, "dlab.core.");
        end
    end
end

function value = numberOf(cellValue)
% A summary cell as a number (NaN for text).
if isnumeric(cellValue) && isscalar(cellValue)
    value = double(cellValue);
else
    value = str2double(string(cellValue));
end
end
