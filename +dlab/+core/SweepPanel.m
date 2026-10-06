classdef SweepPanel < handle
    %SWEEPPANEL The "Sweep" tab: vary one input over a range and plot any
    %   key result against it. The simulator view runs the sweep as a busy
    %   task (cancellable) and hands the outcome back with show().
    %
    %   Vary [Launch angle ▾]  from [ 5 ]  to [ 85 ]  steps [ 17 ]  ☐ Log   [▶ Run sweep]
    %   Plot [Range ▾]                       17 runs · inputs as set on the left [Export CSV…]
    %   ┌───────────────────────────────────────────────────────────────────────────────┐

    events
        RunRequested      % the view starts the sweep (or cancels a running one)
        ExportRequested
    end

    properties (SetAccess = private)
        Grid
        Axes
        ParamDropdown
        FromField
        ToField
        StepsField
        LogCheckbox
        RunButton
        MetricDropdown
        ExportButton
        NoteLabel
        Result = []            % last dlab.core.Sweep result struct
        Metric (1,1) string = ""
    end

    properties (Access = private)
        Theme
        Specs
        GetParams
    end

    properties (Constant, Access = private)
        SetPrefix = "set:"      % dropdown keys of set-valued results
    end

    methods
        function obj = SweepPanel(parent, specs, getParams, theme, saved)
            %SWEEPPANEL GETPARAMS returns the inputs currently on the left.
            arguments
                parent
                specs (:,1) dlab.core.ParamSpec
                getParams (1,1) function_handle
                theme (1,1) dlab.ui.Theme
                saved = []
            end
            t = theme;
            obj.Theme = t;
            obj.GetParams = getParams;
            obj.Specs = dlab.core.SweepPanel.sweepable(specs);
            obj.Grid = uigridlayout(parent, [3 1], RowHeight={30, 30, "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);

            bar = uigridlayout(obj.Grid, [1 10], ...
                ColumnWidth={"fit", 200, "fit", 90, "fit", 90, "fit", 60, "fit", 120}, RowHeight={26}, ...
                Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            dlab.ui.label(bar, "Vary", t, Role="muted");
            obj.ParamDropdown = uidropdown(bar, Items=[obj.Specs.Label], ItemsData=[obj.Specs.Name], ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.sweep.parameter", ...
                ValueChangedFcn=@(~, ~) obj.suggestRange());
            dlab.ui.label(bar, "from", t, Role="muted");
            obj.FromField = numberField(bar, t, "dlab.sweep.from");
            dlab.ui.label(bar, "to", t, Role="muted");
            obj.ToField = numberField(bar, t, "dlab.sweep.to");
            dlab.ui.label(bar, "steps", t, Role="muted");
            obj.StepsField = numberField(bar, t, "dlab.sweep.steps");
            set(obj.StepsField, Limits=[2 dlab.core.Sweep.MaxSteps], RoundFractionalValues="on", Value=11);
            obj.LogCheckbox = uicheckbox(bar, Text="Log", FontColor=t.Text, Tag="dlab.sweep.log", ...
                Tooltip="Space the values evenly on a logarithmic scale (positive limits only)");
            obj.RunButton = dlab.ui.button(bar, "▶  Run sweep", t, Kind="primary", Tag="dlab.sweep.run", ...
                Tooltip="Solve once per value (Esc cancels)", Callback=@(~, ~) notify(obj, "RunRequested"));

            bar2 = uigridlayout(obj.Grid, [1 4], ColumnWidth={"fit", 260, "1x", 110}, RowHeight={26}, ...
                Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            dlab.ui.label(bar2, "Plot", t, Role="muted");
            obj.MetricDropdown = uidropdown(bar2, Items={'–'}, Enable="off", BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.sweep.metric", ValueChangedFcn=@(src, ~) obj.chooseMetric(src.Value));
            obj.NoteLabel = dlab.ui.label(bar2, "Other inputs are taken as set on the left.", t, ...
                Role="muted", HorizontalAlignment="right", Tag="dlab.sweep.note");
            obj.ExportButton = dlab.ui.button(bar2, "Export CSV…", t, Tag="dlab.sweep.export", ...
                Callback=@(~, ~) notify(obj, "ExportRequested"));
            obj.ExportButton.Enable = "off";

            obj.Axes = dlab.ui.axesIn(obj.Grid, t);
            obj.Axes.Layout.Row = 3;
            obj.Axes.Tag = "dlab.sweep.axes";
            title(obj.Axes, "Choose an input and a range, then press Run sweep.");

            if isempty(obj.Specs)
                set([obj.ParamDropdown obj.FromField obj.ToField obj.StepsField obj.LogCheckbox obj.RunButton], ...
                    Enable="off");
                title(obj.Axes, "This simulator has no numeric inputs to sweep.");
            elseif ~isempty(saved)
                obj.restore(saved);
            else
                used = dlab.core.SweepPanel.usedNames(obj.Specs, getParams());
                if ~isempty(used)
                    obj.ParamDropdown.Value = used(1);
                end
                obj.suggestRange();
            end
        end

        function [name, values] = request(obj)
            %REQUEST The input and values the user asked for.
            name = string(obj.ParamDropdown.Value);
            dlab.core.SweepPanel.requireUsed(obj.Specs, name, obj.GetParams());
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            values = dlab.core.Sweep.range(obj.FromField.Value, obj.ToField.Value, obj.StepsField.Value, ...
                Log=obj.LogCheckbox.Value, Integer=spec.Type == "integer");
            for value = values'
                [~, ok, message] = spec.coerce(value);
                if ~ok
                    error("dlab:sweep:range", "%s %s.", spec.Label, message);
                end
            end
        end

        function configure(obj, name, from, to, steps, log)
            %CONFIGURE Set up a sweep (lessons use this); it is not run.
            arguments
                obj
                name (1,1) string
                from (1,1) double
                to (1,1) double
                steps (1,1) double
                log (1,1) logical = false
            end
            if ~ismember(name, string(obj.ParamDropdown.ItemsData))
                error("dlab:sweep:parameter", "There is no input ""%s"" to sweep.", name);
            end
            obj.ParamDropdown.Value = name;
            obj.FromField.Value = from;
            obj.ToField.Value = to;
            obj.StepsField.Value = steps;
            obj.LogCheckbox.Value = log;
        end

        function show(obj, S)
            %SHOW Plot a finished sweep.
            obj.Result = S;
            [items, keys] = plottable(S);
            if isempty(keys)
                obj.MetricDropdown.Items = {'–'};
                obj.MetricDropdown.Enable = "off";
            else
                set(obj.MetricDropdown, Items=items, ItemsData=keys, Enable="on");
                if ~ismember(obj.Metric, keys)
                    obj.Metric = keys(1);
                end
                obj.MetricDropdown.Value = obj.Metric;
            end
            obj.ExportButton.Enable = "on";
            failed = nnz(S.Errors ~= "");
            note = sprintf("%d runs", numel(S.Values));
            if failed > 0
                note = note + sprintf(" · %d failed (see the CSV)", failed);
            end
            if S.Cancelled
                note = note + " · cancelled";
            end
            obj.NoteLabel.Text = note + " · other inputs as set when it ran";
            obj.draw();
        end

        function setRunning(obj, running)
            %SETRUNNING The sweep's button doubles as Cancel while it runs.
            t = obj.Theme;
            if running
                set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger);
            else
                set(obj.RunButton, Text="▶  Run sweep", BackgroundColor=t.Accent, FontColor=t.OnAccent);
            end
        end

        function chooseMetric(obj, quantity)
            obj.Metric = string(quantity);
            obj.draw();
        end

        function state = snapshot(obj)
            state = struct("Parameter", string(obj.ParamDropdown.Value), "From", obj.FromField.Value, ...
                "To", obj.ToField.Value, "Steps", obj.StepsField.Value, "Log", obj.LogCheckbox.Value, ...
                "Metric", obj.Metric, "Result", {obj.Result});
            if isempty(obj.Specs)
                state.Parameter = "";
            end
        end
    end

    methods (Static)
        function specs = sweepable(specs)
            %SWEEPABLE Numeric model inputs (not presentation settings).
            specs = specs(ismember([specs.Type], ["double" "integer"]) & ~[specs.Display]);
        end

        function names = usedNames(specs, params)
            %USEDNAMES Names of the SPECS shown for PARAMS. A hidden input
            %   (the column's E with a library material) is not used, so
            %   varying it changes nothing.
            names = strings(1, 0);
            for spec = specs(:)'
                if spec.isVisible(params)
                    names(end+1) = spec.Name; %#ok<AGROW>
                end
            end
        end

        function requireUsed(specs, names, params)
            %REQUIREUSED A readable error when an input to vary is hidden.
            for name = reshape(string(names), 1, [])
                spec = dlab.core.ParamSpec.find(specs, name);
                if ~spec.isVisible(params)
                    error("dlab:analysis:unused", "%s is not used with the inputs set on the left, " + ...
                        "so varying it would change nothing.", spec.Label);
                end
            end
        end

        function range = suggestedRange(spec, value)
            %SUGGESTEDRANGE Half to one and a half times VALUE, kept inside
            %   the input's allowed range (whole numbers for integers).
            if value == 0
                range = [-1 1];
            else
                range = sort([0.5 1.5] * value);
            end
            low = spec.Min;
            high = spec.Max;
            span = max(abs(range(2) - range(1)), 1);
            if ~spec.MinInclusive
                low = low + 1e-3 * span;
            end
            if ~spec.MaxInclusive
                high = high - 1e-3 * span;
            end
            range = min(max(range, low), high);
            if spec.Type == "integer"
                range = [ceil(range(1)) floor(range(2))];
            end
        end
    end

    methods (Access = private)
        function drawCloud(obj, S, name)
            %DRAWCLOUD Every value of a set-valued result at each swept
            %   value (a bifurcation diagram for Poincaré points).
            t = obj.Theme;
            ax = obj.Axes;
            column = find(S.SetNames == name, 1);
            counts = cellfun(@numel, S.SetData(:, column));
            x = repelem(S.Values, counts);
            y = vertcat(S.SetData{:, column});
            line(ax, x, y, LineStyle="none", Marker=".", MarkerSize=5, Color=t.series(1), ...
                Tag="dlab.sweep.cloud");
            ax.XScale = "linear";
            xlabel(ax, dlab.ui.withUnits(S.Label, S.Units));
            ylabel(ax, dlab.ui.withUnits(name, S.SetUnits(column)));
            title(ax, name + " (all values) vs " + S.Label);
            if ~isempty(S.Values)
                span = max(S.Values) - min(S.Values);
                xlim(ax, [min(S.Values) max(S.Values)] + [-1 1] * max(eps, 0.02 * span));
            end
        end

        function suggestRange(obj)
            spec = dlab.core.ParamSpec.find(obj.Specs, string(obj.ParamDropdown.Value));
            params = obj.GetParams();
            range = dlab.core.SweepPanel.suggestedRange(spec, params.(spec.Name));
            obj.FromField.Value = range(1);
            obj.ToField.Value = range(2);
            obj.LogCheckbox.Value = false;
        end

        function restore(obj, saved)
            if ismember(saved.Parameter, string(obj.ParamDropdown.ItemsData))
                obj.ParamDropdown.Value = saved.Parameter;
                obj.FromField.Value = saved.From;
                obj.ToField.Value = saved.To;
                obj.StepsField.Value = saved.Steps;
                obj.LogCheckbox.Value = saved.Log;
            else
                obj.suggestRange();
            end
            obj.Metric = saved.Metric;
            if ~isempty(saved.Result)
                obj.show(saved.Result);
            end
        end

        function draw(obj)
            t = obj.Theme;
            S = obj.Result;
            ax = obj.Axes;
            delete(allchild(ax));
            [~, keys] = plottable(S);
            if isempty(S) || isempty(keys)
                title(ax, "No numeric results to plot.");
                return
            end
            if startsWith(obj.Metric, obj.SetPrefix)
                obj.drawCloud(S, extractAfter(obj.Metric, obj.SetPrefix));
                return
            end
            column = find(S.Quantities == obj.Metric, 1);
            y = S.Data(:, column);
            plot(ax, S.Values, y, "-o", Color=t.series(1), MarkerFaceColor=t.series(1), ...
                MarkerSize=5, LineWidth=1.5);
            ax.XScale = "linear";
            if all(S.Values > 0) && numel(S.Values) > 2 && ...
                    abs(std(diff(log(S.Values)))) < 1e-9 && abs(std(diff(S.Values))) > 1e-9
                ax.XScale = "log";          % log-spaced sweeps read best on a log axis
            end
            xlabel(ax, dlab.ui.withUnits(S.Label, S.Units));
            ylabel(ax, dlab.ui.withUnits(S.Quantities(column), S.QuantityUnits(column)));
            title(ax, S.Quantities(column) + " vs " + S.Label);
            [best, at] = max(y);
            if isfinite(best)
                hold(ax, "on");
                plot(ax, S.Values(at), best, "o", MarkerSize=10, LineWidth=1.5, Color=t.series(2), ...
                    Tag="dlab.sweep.max");
                align = "left";
                if at > numel(S.Values) / 2
                    align = "right";            % keep the label inside the plot
                end
                text(ax, S.Values(at), best, sprintf("  max %.4g at %.4g  ", best, S.Values(at)), ...
                    Color=t.series(2), VerticalAlignment="bottom", HorizontalAlignment=align, ...
                    FontSize=t.FontSize.sm + 1);
                hold(ax, "off");
            end
        end
    end
end

function field = numberField(parent, t, tag)
field = uieditfield(parent, "numeric", ValueDisplayFormat="%.6g", HorizontalAlignment="right", ...
    BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag=tag);
end

function [items, keys] = plottable(S)
% Dropdown labels and keys: each quantity, then each set-valued result.
items = strings(1, 0);
keys = strings(1, 0);
if isempty(S)
    return
end
items = dlab.ui.withUnits(S.Quantities, S.QuantityUnits);
keys = S.Quantities;
if isfield(S, "SetNames") && ~isempty(S.SetNames)
    setItems = S.SetNames + " (all values)";
    hasUnits = S.SetUnits ~= "";
    setItems(hasUnits) = S.SetNames(hasUnits) + " (" + S.SetUnits(hasUnits) + ", all values)";
    items = [items setItems];
    keys = [keys "set:" + S.SetNames];
end
end
