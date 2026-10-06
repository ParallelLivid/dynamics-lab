classdef OptimizePanel < handle
    %OPTIMIZEPANEL The "Optimize" tab: find the inputs (up to three, each
    %   in a range) that maximize or minimize a key result, optionally
    %   keeping another result below or above a limit. The simulator view
    %   runs the search (dlab.core.Optimizer) as a busy task (cancellable)
    %   and hands the outcome back with show(); "Apply best inputs" asks
    %   the view to set them (ApplyRequested, with the inputs in Chosen).
    %
    %   Vary [Launch angle ▾] from [0 ] to [90]   [Maximize ▾] [Range (m)           ▾]
    %   and  [–            ▾] from [  ] to [  ]   ☐ subject to [Maximum height (m) ▾] [≤▾] [40]
    %   and  [–            ▾] from [  ] to [  ]   [▶ Optimize] [Apply best inputs]
    %   Best: Launch angle = 34.08 deg → Range 236.5 m (35 runs) · meets Maximum height ≤ 40 m
    %   ┌ the result against the input (one input) or against run number ─────┐
    %
    %   The results to choose from come from the last solve: the view
    %   passes Plugin.metrics(result) to setMetrics after every run.

    events
        RunRequested      % the view starts the search (or cancels a running one)
        ApplyRequested    % "Apply best inputs": Chosen holds them
    end

    properties (SetAccess = private)
        Grid
        Axes
        InputDropdowns              % one per slot; slots after the first can be "–"
        FromFields
        ToFields
        GoalDropdown
        MetricDropdown
        ConstraintCheckbox
        ConstraintMetricDropdown
        ConstraintTypeDropdown
        ConstraintValueField
        RunButton
        ApplyButton
        NoteLabel
        Result = []                 % last dlab.core.Optimizer result struct
        Metrics = strings(1, 0)     % results offered (Plugin.metrics Quantity)
        MetricUnits = strings(1, 0)
        Metric (1,1) string = ""
        ConstraintMetric (1,1) string = ""
        Chosen = struct()           % the best inputs (ApplyRequested)
    end

    properties (Access = private)
        Theme
        Specs
        GetParams
        Running (1,1) logical = false
    end

    properties (Constant)
        Slots = 3
    end

    properties (Constant, Access = private)
        None = "-"                  % key of the "–" input (never a valid input name)
        Hint = "Searches each input within its range (whole numbers for integer inputs). " + ...
            "Other inputs are taken as set on the left."
    end

    methods
        function obj = OptimizePanel(parent, specs, getParams, theme, saved)
            %OPTIMIZEPANEL GETPARAMS returns the inputs currently on the left.
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
            obj.Grid = uigridlayout(parent, [3 1], RowHeight={"fit", 22, "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);

            bar = uigridlayout(obj.Grid, [3 11], RowHeight={26, 26, 26}, ...
                ColumnWidth={"fit", 170, "fit", 75, "fit", 75, 6, 110, 190, 45, 75}, ...
                Padding=[t.Spacing.sm 4 t.Spacing.sm 4], ColumnSpacing=t.Spacing.sm, RowSpacing=t.Spacing.xs, ...
                BackgroundColor=t.Surface);
            labels = [obj.Specs.Label];
            names = [obj.Specs.Name];
            obj.InputDropdowns = gobjects(1, obj.Slots);
            obj.FromFields = gobjects(1, obj.Slots);
            obj.ToFields = gobjects(1, obj.Slots);
            for slot = 1:obj.Slots
                prefix = "and";
                items = ["–" labels];
                keys = [obj.None names];
                if slot == 1 && ~isempty(names)
                    [prefix, items, keys] = deal("Vary", labels, names);
                end
                place(dlab.ui.label(bar, prefix, t, Role="muted"), slot, 1);
                obj.InputDropdowns(slot) = place(uidropdown(bar, Items=items, ItemsData=keys, ...
                    BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.optimize.input" + slot, ...
                    ValueChangedFcn=@(~, ~) obj.chooseInput(slot)), slot, 2);
                place(dlab.ui.label(bar, "from", t, Role="muted"), slot, 3);
                obj.FromFields(slot) = place(numberField(bar, t, "dlab.optimize.from" + slot), slot, 4);
                place(dlab.ui.label(bar, "to", t, Role="muted"), slot, 5);
                obj.ToFields(slot) = place(numberField(bar, t, "dlab.optimize.to" + slot), slot, 6);
            end

            obj.GoalDropdown = place(uidropdown(bar, Items=["Maximize" "Minimize"], ...
                ItemsData=["maximize" "minimize"], BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                Tag="dlab.optimize.goal"), 1, 8);
            obj.MetricDropdown = place(uidropdown(bar, Items={'–'}, Enable="off", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.optimize.metric", ...
                ValueChangedFcn=@(src, ~) obj.chooseMetric(src.Value)), 1, [9 11]);
            obj.ConstraintCheckbox = place(uicheckbox(bar, Text="subject to", FontColor=t.Text, ...
                Tag="dlab.optimize.constrain", Tooltip="Keep another result below or above a limit", ...
                ValueChangedFcn=@(~, ~) obj.refreshEnable()), 2, 8);
            obj.ConstraintMetricDropdown = place(uidropdown(bar, Items={'–'}, Enable="off", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.optimize.constraintMetric", ...
                ValueChangedFcn=@(src, ~) obj.chooseConstraintMetric(src.Value)), 2, 9);
            obj.ConstraintTypeDropdown = place(uidropdown(bar, Items=["≤" "≥"], ItemsData=["<=" ">="], ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.optimize.constraintType"), 2, 10);
            obj.ConstraintValueField = place(numberField(bar, t, "dlab.optimize.constraintValue"), 2, 11);
            obj.RunButton = place(dlab.ui.button(bar, "▶  Optimize", t, Kind="primary", Tag="dlab.optimize.run", ...
                Tooltip="Search for the best inputs (Esc cancels)", ...
                Callback=@(~, ~) notify(obj, "RunRequested")), 3, 8);
            obj.ApplyButton = place(dlab.ui.button(bar, "Apply best inputs", t, Tag="dlab.optimize.apply", ...
                Tooltip="Set the inputs on the left to the best ones found", ...
                Callback=@(~, ~) obj.apply()), 3, 9);
            obj.ApplyButton.Enable = "off";

            obj.NoteLabel = dlab.ui.label(obj.Grid, obj.Hint, t, Role="muted", Tag="dlab.optimize.note");
            obj.NoteLabel.Layout.Row = 2;
            obj.Axes = dlab.ui.axesIn(obj.Grid, t);
            obj.Axes.Layout.Row = 3;
            obj.Axes.Tag = "dlab.optimize.axes";
            title(obj.Axes, "Choose inputs and a result, then press Optimize.");

            if isempty(obj.Specs)
                set([obj.InputDropdowns obj.FromFields obj.ToFields obj.GoalDropdown obj.ConstraintCheckbox ...
                    obj.RunButton], Enable="off");
                obj.NoteLabel.Text = "";
                title(obj.Axes, "This simulator has no numeric inputs to optimize.");
                return
            end
            used = dlab.core.SweepPanel.usedNames(obj.Specs, getParams());
            if ~isempty(used)
                obj.InputDropdowns(1).Value = used(1);
            end
            for slot = 1:obj.Slots
                obj.chooseInput(slot);
            end
            if ~isempty(saved)
                obj.restore(saved);
            end
            obj.refreshEnable();
        end

        function setMetrics(obj, T)
            %SETMETRICS Offer the results in T (Plugin.metrics: Quantity,
            %   Units), keeping the current choices when still offered.
            names = reshape(string(T.Quantity), 1, []);
            units = reshape(string(T.Units), 1, []);
            [obj.Metrics, keep] = unique(names, "stable");
            obj.MetricUnits = units(keep);
            if isempty(obj.Metrics)
                set([obj.MetricDropdown obj.ConstraintMetricDropdown], Items={'–'}, ItemsData={});
            else
                if ~ismember(obj.Metric, obj.Metrics)
                    obj.Metric = obj.Metrics(1);
                end
                if ~ismember(obj.ConstraintMetric, obj.Metrics)
                    obj.ConstraintMetric = obj.Metrics(min(2, end));
                end
                items = dlab.ui.withUnits(obj.Metrics, obj.MetricUnits);
                set(obj.MetricDropdown, Items=items, ItemsData=obj.Metrics, Value=obj.Metric);
                set(obj.ConstraintMetricDropdown, Items=items, ItemsData=obj.Metrics, Value=obj.ConstraintMetric);
            end
            obj.refreshEnable();
        end

        function job = request(obj)
            %REQUEST What the user asked for: Inputs (names), Bounds (n×2),
            %   Metric, Goal, and Constraint (struct or []), as
            %   dlab.core.Optimizer.run takes them. Errors with a readable
            %   message when something is missing or out of range.
            if isempty(obj.Specs)
                error("dlab:optimize:inputs", "This simulator has no numeric inputs to optimize.");
            end
            if isempty(obj.Metrics)
                error("dlab:optimize:metrics", "Run the simulation once so the Optimize tab can list its results.");
            end
            slots = find(obj.inputKeys() ~= obj.None);
            names = obj.inputKeys();
            names = names(slots);
            if numel(unique(names)) < numel(names)
                error("dlab:optimize:inputs", "Choose each input to vary only once.");
            end
            bounds = zeros(numel(slots), 2);
            for k = 1:numel(slots)
                bounds(k, :) = [obj.FromFields(slots(k)).Value obj.ToFields(slots(k)).Value];
                dlab.core.Optimizer.searchRange(dlab.core.ParamSpec.find(obj.Specs, names(k)), ...
                    bounds(k, 1), bounds(k, 2));     % errors when out of range
            end
            dlab.core.SweepPanel.requireUsed(obj.Specs, names, obj.GetParams());
            constraint = [];
            if obj.ConstraintCheckbox.Value
                constraint = struct("Metric", obj.ConstraintMetric, ...
                    "Type", string(obj.ConstraintTypeDropdown.Value), "Value", obj.ConstraintValueField.Value);
            end
            job = struct("Inputs", names, "Bounds", bounds, "Metric", obj.Metric, ...
                "Goal", string(obj.GoalDropdown.Value), "Constraint", constraint);
        end

        function configure(obj, names, metric, options)
            %CONFIGURE Set up a search (lessons use this); it is not run.
            %   NAMES are the inputs to vary; options Goal, Bounds (one row
            %   per input; default each input's range), and Constraint.
            arguments
                obj
                names (1,:) string
                metric (1,1) string
                options.Goal (1,1) string {mustBeMember(options.Goal, ["maximize" "minimize"])} = "maximize"
                options.Bounds double = []
                options.Constraint = []
            end
            if isempty(names) || numel(names) > obj.Slots
                error("dlab:optimize:inputs", "Choose 1 to %d inputs to vary.", obj.Slots);
            end
            for slot = 1:obj.Slots
                key = obj.None;
                if slot <= numel(names)
                    key = names(slot);
                    if ~ismember(key, [obj.Specs.Name])
                        error("dlab:optimize:inputs", "There is no input ""%s"" to optimize.", key);
                    end
                end
                obj.InputDropdowns(slot).Value = key;
                obj.chooseInput(slot);
                if slot <= numel(names) && ~isempty(options.Bounds)
                    obj.FromFields(slot).Value = options.Bounds(slot, 1);
                    obj.ToFields(slot).Value = options.Bounds(slot, 2);
                end
            end
            obj.GoalDropdown.Value = options.Goal;
            obj.chooseMetric(metric);
            c = options.Constraint;
            obj.ConstraintCheckbox.Value = ~isempty(c);
            if ~isempty(c)
                obj.chooseConstraintMetric(c.Metric);
                obj.ConstraintTypeDropdown.Value = replace(string(c.Type), ["≤" "≥"], ["<=" ">="]);
                obj.ConstraintValueField.Value = c.Value;
            end
            obj.refreshEnable();
        end

        function show(obj, R)
            %SHOW Plot a finished search and note its best point.
            obj.Result = R;
            t = obj.Theme;
            obj.NoteLabel.Text = R.Message;
            obj.NoteLabel.FontColor = t.TextMuted;
            if all(isnan(R.Best)) || ~R.Satisfied
                obj.NoteLabel.FontColor = t.Warning;
            end
            obj.refreshEnable();
            obj.draw();
        end

        function setRunning(obj, running)
            %SETRUNNING The Optimize button doubles as Cancel while it runs.
            t = obj.Theme;
            obj.Running = running;
            if running
                set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger);
            else
                set(obj.RunButton, Text="▶  Optimize", BackgroundColor=t.Accent, FontColor=t.OnAccent);
            end
            obj.refreshEnable();
        end

        function apply(obj)
            %APPLY Ask the view to set the best inputs found.
            R = obj.Result;
            if isempty(R) || any(isnan(R.Best))
                return
            end
            obj.Chosen = cell2struct(num2cell(R.Best(:)), cellstr(R.Inputs(:)), 1);
            notify(obj, "ApplyRequested");
        end

        function chooseMetric(obj, metric)
            obj.Metric = string(metric);
            if ismember(obj.Metric, obj.Metrics)
                obj.MetricDropdown.Value = obj.Metric;
            end
        end

        function chooseConstraintMetric(obj, metric)
            obj.ConstraintMetric = string(metric);
            if ismember(obj.ConstraintMetric, obj.Metrics)
                obj.ConstraintMetricDropdown.Value = obj.ConstraintMetric;
            end
        end

        function state = snapshot(obj)
            state = struct("Inputs", obj.inputKeys(), "From", [obj.FromFields.Value], ...
                "To", [obj.ToFields.Value], "Goal", string(obj.GoalDropdown.Value), "Metric", obj.Metric, ...
                "Constrained", obj.ConstraintCheckbox.Value, "ConstraintMetric", obj.ConstraintMetric, ...
                "ConstraintType", string(obj.ConstraintTypeDropdown.Value), ...
                "ConstraintValue", obj.ConstraintValueField.Value, "Metrics", obj.Metrics, ...
                "MetricUnits", obj.MetricUnits, "Result", {obj.Result});
        end
    end

    methods (Access = private)
        function keys = inputKeys(obj)
            keys = strings(1, obj.Slots);
            for slot = 1:obj.Slots
                keys(slot) = string(obj.InputDropdowns(slot).Value);
            end
        end

        function chooseInput(obj, slot)
            %CHOOSEINPUT Fill the slot's range with the input's allowed
            %   range (unlimited sides around its current value).
            key = string(obj.InputDropdowns(slot).Value);
            if key ~= obj.None
                spec = dlab.core.ParamSpec.find(obj.Specs, key);
                params = obj.GetParams();
                range = dlab.core.Optimizer.defaultRange(spec, double(params.(key)));
                obj.FromFields(slot).Value = range(1);
                obj.ToFields(slot).Value = range(2);
            end
            obj.refreshEnable();
        end

        function refreshEnable(obj)
            if isempty(obj.Specs)
                return
            end
            idle = ~obj.Running;
            used = obj.inputKeys() ~= obj.None;
            for slot = 1:obj.Slots
                set([obj.FromFields(slot) obj.ToFields(slot)], Enable=onOff(idle && used(slot)));
            end
            set([obj.InputDropdowns obj.GoalDropdown obj.ConstraintCheckbox], Enable=onOff(idle));
            hasMetrics = ~isempty(obj.Metrics);
            obj.MetricDropdown.Enable = onOff(idle && hasMetrics);
            set([obj.ConstraintMetricDropdown obj.ConstraintTypeDropdown obj.ConstraintValueField], ...
                Enable=onOff(idle && hasMetrics && obj.ConstraintCheckbox.Value));
            R = obj.Result;
            obj.ApplyButton.Enable = onOff(idle && ~isempty(R) && ~any(isnan(R.Best)));
        end

        function restore(obj, saved)
            obj.Metric = saved.Metric;
            obj.ConstraintMetric = saved.ConstraintMetric;
            obj.setMetrics(table(saved.Metrics(:), saved.MetricUnits(:), VariableNames=["Quantity" "Units"]));
            for slot = 1:obj.Slots
                dropdown = obj.InputDropdowns(slot);
                if ismember(saved.Inputs(slot), string(dropdown.ItemsData))
                    dropdown.Value = saved.Inputs(slot);
                    obj.chooseInput(slot);
                    if saved.Inputs(slot) ~= obj.None
                        obj.FromFields(slot).Value = saved.From(slot);
                        obj.ToFields(slot).Value = saved.To(slot);
                    end
                end
            end
            obj.GoalDropdown.Value = saved.Goal;
            obj.ConstraintCheckbox.Value = saved.Constrained;
            obj.ConstraintTypeDropdown.Value = saved.ConstraintType;
            obj.ConstraintValueField.Value = saved.ConstraintValue;
            if ~isempty(saved.Result)
                obj.show(saved.Result);
            end
        end

        function draw(obj)
            %DRAW One input: the result at every input value tried. More:
            %   the result at each run, with the best so far (convergence).
            t = obj.Theme;
            R = obj.Result;
            ax = obj.Axes;
            dlab.ui.clearAxes(ax);
            E = R.Evaluations;
            ran = E.Error == "";
            if ~any(ran)
                title(ax, "No run of the search finished: see the note above.");
                return
            end
            n = numel(R.Inputs);
            oneInput = n == 1;
            if oneInput
                x = E{:, 1};
                xlabel(ax, dlab.ui.withUnits(R.Labels, R.Units));
                title(ax, R.Metric + " vs " + R.Labels + ": every run of the search");
            else
                x = (1:height(E))';
                xlabel(ax, "Run");
                title(ax, R.Metric + " at each run of the search");
            end
            ylabel(ax, dlab.ui.withUnits(R.Metric, R.MetricUnits));
            y = E.Metric;
            met = ran & E.Feasible;
            missed = ran & ~E.Feasible;
            hold(ax, "on");
            line(ax, x(met), y(met), LineStyle="none", Marker="o", MarkerSize=5, Color=t.series(1), ...
                MarkerFaceColor=t.series(1), DisplayName="Runs", Tag="dlab.optimize.runs");
            if any(missed)
                line(ax, x(missed), y(missed), LineStyle="none", Marker="o", MarkerSize=5, Color=t.Warning, ...
                    DisplayName="Runs that miss the constraint", Tag="dlab.optimize.missed");
            end
            if ~oneInput && any(met)
                line(ax, x, runningBest(y, met, R.Goal), Color=t.series(2), LineWidth=1.5, ...
                    DisplayName="Best so far", Tag="dlab.optimize.progress");
            end
            if ~any(isnan(R.Best))
                if oneInput
                    at = R.Best;
                else
                    at = find(all(E{:, 1:n} == R.Best, 2), 1);
                end
                line(ax, at, R.BestMetric, LineStyle="none", Marker="o", MarkerSize=11, LineWidth=1.5, ...
                    Color=t.series(2), DisplayName="Best", Tag="dlab.optimize.best");
                align = "left";
                if at > mean(xlim(ax))
                    align = "right";            % keep the label inside the plot
                end
                text(ax, at, R.BestMetric, sprintf("  best %.4g  ", R.BestMetric), Color=t.series(2), ...
                    VerticalAlignment="bottom", HorizontalAlignment=align, FontSize=t.FontSize.sm + 1);
            end
            hold(ax, "off");
            if any(missed) || ~oneInput
                dlab.ui.legend(ax, t, "Location", "best");
            end
        end
    end
end

function control = place(control, row, column)
control.Layout.Row = row;
control.Layout.Column = column;
end

function field = numberField(parent, t, tag)
field = uieditfield(parent, "numeric", ValueDisplayFormat="%.6g", HorizontalAlignment="right", ...
    BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag=tag);
end

function state = onOff(tf)
state = matlab.lang.OnOffSwitchState(tf);
end

function best = runningBest(y, ok, goal)
% The best result so far at each run, counting only runs that met the
% constraint (NaN before the first).
y(~ok) = NaN;
if goal == "maximize"
    best = cummax(y, "omitnan");
else
    best = cummin(y, "omitnan");
end
first = find(ok, 1);
best(1:first - 1) = NaN;
end
