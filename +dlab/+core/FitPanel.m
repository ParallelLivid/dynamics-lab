classdef FitPanel < handle
    %FITPANEL The "Fit" tab: import measured data and adjust up to three
    %   inputs so a simulated column matches a measured one. The simulator
    %   view opens the file dialog, runs the fit as a busy task
    %   (cancellable), and hands the outcome back with show().
    %
    %   [Import CSV…] ringdown.csv · 91 points    Compare [x (m) ▾] with [position (m) ▾]
    %   Fit [Damping c ▾] [(none) ▾] [(none) ▾]          [▶ Fit] [Apply fitted inputs]
    %   Fitted Damping c = 0.212 ± 0.004 N·s/m · RMS 0.031 → 0.004 m · 61 runs
    %   ┌ measured (markers), simulated at the start and at the best ─────────────┐
    %   ┌ residuals at the best ──────────────────────────────────────────────────┐

    events
        ImportRequested   % the view asks for a CSV file and calls load()
        RunRequested      % the view starts the fit (or cancels a running one)
        ApplyRequested    % the view sets the fitted inputs (Result.Inputs, Result.Best)
    end

    properties (SetAccess = private)
        Grid
        PlotGrid               % the two axes (what Export plot saves)
        Axes
        ResidualAxes
        ImportButton
        DataLabel
        MeasuredDropdown
        SimulatedDropdown
        InputDropdowns         % one per input that can be fitted
        RunButton
        ApplyButton
        NoteLabel
        Data = []              % dlab.core.MeasuredData.read struct
        Result = []            % dlab.core.MeasuredData.fit struct
        Columns (1,:) string = strings(1, 0)        % simulated columns on offer
        ColumnUnits (1,:) string = strings(1, 0)
    end

    properties (Access = private)
        Theme
        Specs
    end

    properties (Constant)
        MaxInputs = 3           % dropdowns shown (the engine takes up to 4)
    end

    methods
        function obj = FitPanel(parent, specs, getParams, theme, saved)
            %FITPANEL GETPARAMS returns the inputs currently on the left.
            arguments
                parent
                specs (:,1) dlab.core.ParamSpec
                getParams (1,1) function_handle
                theme (1,1) dlab.ui.Theme
                saved = []
            end
            t = theme;
            obj.Theme = t;
            obj.Specs = specs(ismember([specs.Type], "double") & ~[specs.Display]);
            obj.Grid = uigridlayout(parent, [4 1], RowHeight={30, 30, "fit", "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);

            bar = uigridlayout(obj.Grid, [1 6], ColumnWidth={110, "1x", "fit", 180, "fit", 180}, ...
                RowHeight={26}, Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            obj.ImportButton = dlab.ui.button(bar, "Import CSV…", t, Tag="dlab.fit.import", ...
                Tooltip="A CSV with a header row: time, then measured columns", ...
                Callback=@(~, ~) notify(obj, "ImportRequested"));
            obj.DataLabel = dlab.ui.label(bar, "No measured data yet.", t, Role="muted", Tag="dlab.fit.data");
            dlab.ui.label(bar, "Compare", t, Role="muted");
            obj.MeasuredDropdown = uidropdown(bar, Items={'–'}, Enable="off", BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.fit.measured", ValueChangedFcn=@(~, ~) obj.matchColumns());
            dlab.ui.label(bar, "with", t, Role="muted");
            obj.SimulatedDropdown = uidropdown(bar, Items={'Run once to list results'}, Enable="off", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.fit.simulated", ...
                ValueChangedFcn=@(~, ~) obj.draw());

            bar2 = uigridlayout(obj.Grid, [1 7], ColumnWidth={"fit", 170, 170, 170, "1x", 110, 150}, ...
                RowHeight={26}, Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            dlab.ui.label(bar2, "Fit", t, Role="muted");
            names = [obj.Specs.Name];
            first = firstVisible(obj.Specs, getParams());
            obj.InputDropdowns = gobjects(1, obj.MaxInputs);
            for k = 1:obj.MaxInputs
                obj.InputDropdowns(k) = uidropdown(bar2, Items=["(none)" obj.Specs.Label], ...
                    ItemsData=["" names], BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                    Tag="dlab.fit.input" + k);
            end
            if first ~= ""
                obj.InputDropdowns(1).Value = first;
            end
            uilabel(bar2, Text="");
            obj.RunButton = dlab.ui.button(bar2, "▶  Fit", t, Kind="primary", Tag="dlab.fit.run", ...
                Tooltip="Adjust the chosen inputs to match the data (Esc cancels)", ...
                Callback=@(~, ~) notify(obj, "RunRequested"));
            obj.ApplyButton = dlab.ui.button(bar2, "Apply fitted inputs", t, Tag="dlab.fit.apply", ...
                Tooltip="Set the fitted values on the left", Callback=@(~, ~) notify(obj, "ApplyRequested"));
            obj.ApplyButton.Enable = "off";

            obj.NoteLabel = dlab.ui.label(obj.Grid, "Import a CSV of measured data, choose the columns " + ...
                "to compare and the inputs to adjust, then press Fit.", t, Role="muted", WordWrap="on", ...
                Tag="dlab.fit.note");
            obj.PlotGrid = uigridlayout(obj.Grid, [2 1], RowHeight={"2x", "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Axes = dlab.ui.axesIn(obj.PlotGrid, t, Title="Measured and simulated", Row=1);
            obj.Axes.Tag = "dlab.fit.axes";
            obj.ResidualAxes = dlab.ui.axesIn(obj.PlotGrid, t, XLabel="Time (s)", YLabel="Residual", Row=2);
            obj.ResidualAxes.Tag = "dlab.fit.residuals";

            if isempty(obj.Specs)
                set([obj.InputDropdowns obj.RunButton], Enable="off");
                obj.NoteLabel.Text = "This simulator has no real-valued inputs to fit.";
            end
            if ~isempty(saved)
                obj.restore(saved);
            end
        end

        function load(obj, D)
            %LOAD Show measured data D (dlab.core.MeasuredData.read); an
            %   earlier fit is cleared.
            obj.Data = D;
            obj.Result = [];
            obj.ApplyButton.Enable = "off";
            text = sprintf("%s · %d rows", D.Name, numel(D.Time));
            if D.Dropped > 0
                text = text + sprintf(" · %d dropped", D.Dropped);
            end
            if D.Sorted
                text = text + " · sorted by time";
            end
            obj.DataLabel.Text = text;
            obj.DataLabel.Tooltip = D.File;
            items = dlab.ui.withUnits(D.Columns, D.Units);
            keepChoice(obj.MeasuredDropdown, items, D.Columns);
            obj.NoteLabel.Text = "Choose the inputs to adjust, then press Fit.";
            obj.matchColumns();
        end

        function setTable(obj, T)
            %SETTABLE Offer the numeric columns of export table T (the
            %   current result) to compare with; time itself is left out.
            timeName = dlab.core.MeasuredData.timeVariable(T);
            names = strings(1, 0);
            units = strings(1, 0);
            allUnits = string(T.Properties.VariableUnits);
            for k = 1:width(T)
                name = string(T.Properties.VariableNames{k});
                value = T.(name);
                if timeName ~= "" && name ~= timeName && isnumeric(value) && isreal(value) && size(value, 2) == 1
                    names(end+1) = name; %#ok<AGROW>
                    if numel(allUnits) == width(T)
                        units(end+1) = allUnits(k); %#ok<AGROW>
                    else
                        units(end+1) = ""; %#ok<AGROW>
                    end
                end
            end
            obj.Columns = names;
            obj.ColumnUnits = units;
            if isempty(names)
                set(obj.SimulatedDropdown, Items={'No time series to compare'}, ItemsData={}, Enable="off");
                return
            end
            items = names;
            items(units ~= "") = names(units ~= "") + " (" + units(units ~= "") + ")";
            keepChoice(obj.SimulatedDropdown, items, names);
            obj.matchColumns();
        end

        function asked = request(obj)
            %REQUEST What the user asked for: Inputs (names) and Mapping
            %   (Measured, Simulated) for dlab.core.MeasuredData.fit.
            if isempty(obj.Data)
                error("dlab:fit:noData", "Import a CSV of measured data first.");
            end
            if isempty(obj.Columns)
                error("dlab:fit:noColumns", "Run the simulation once, so the fit knows its result columns.");
            end
            inputs = strings(1, 0);
            for dropdown = obj.InputDropdowns
                if string(dropdown.Value) ~= ""
                    inputs(end+1) = string(dropdown.Value); %#ok<AGROW>
                end
            end
            inputs = unique(inputs, "stable");
            if isempty(inputs)
                error("dlab:fit:noInputs", "Choose at least one input to fit.");
            end
            asked = struct("Inputs", inputs, "Mapping", struct("Measured", string(obj.MeasuredDropdown.Value), ...
                "Simulated", string(obj.SimulatedDropdown.Value)));
        end

        function configure(obj, measured, simulated, inputs)
            %CONFIGURE Choose the columns and inputs (lessons use this);
            %   the fit is not run.
            arguments
                obj
                measured (1,1) string
                simulated (1,1) string
                inputs (1,:) string
            end
            if ~isempty(obj.Data)
                choose(obj.MeasuredDropdown, measured, "measured column");
            end
            if ~isempty(obj.Columns)
                choose(obj.SimulatedDropdown, simulated, "result column");
            end
            if numel(inputs) > obj.MaxInputs
                error("dlab:fit:inputs", "The Fit tab adjusts up to %d inputs.", obj.MaxInputs);
            end
            for k = 1:obj.MaxInputs
                if k <= numel(inputs)
                    choose(obj.InputDropdowns(k), inputs(k), "input to fit");
                else
                    obj.InputDropdowns(k).Value = "";
                end
            end
            obj.draw();
        end

        function show(obj, R)
            %SHOW Plot a finished fit.
            obj.Result = R;
            obj.NoteLabel.Text = dlab.core.MeasuredData.describe(R) + ". " + R.Message;
            moved = isfinite(R.BestRMS) && any(R.Best ~= R.Start);
            obj.ApplyButton.Enable = matlab.lang.OnOffSwitchState(moved);
            obj.draw();
        end

        function setRunning(obj, running)
            %SETRUNNING The Fit button doubles as Cancel while it runs.
            t = obj.Theme;
            if running
                set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger);
            else
                set(obj.RunButton, Text="▶  Fit", BackgroundColor=t.Accent, FontColor=t.OnAccent);
            end
        end

        function state = snapshot(obj)
            state = struct("Data", {obj.Data}, "Columns", obj.Columns, "ColumnUnits", obj.ColumnUnits, ...
                "Measured", string(obj.MeasuredDropdown.Value), ...
                "Simulated", string(obj.SimulatedDropdown.Value), ...
                "Inputs", string({obj.InputDropdowns.Value}), "Result", {obj.Result});
        end
    end

    methods (Access = private)
        function restore(obj, saved)
            if ~isempty(saved.Data)
                obj.load(saved.Data);
                if ismember(saved.Measured, string(obj.MeasuredDropdown.ItemsData))
                    obj.MeasuredDropdown.Value = saved.Measured;
                end
            end
            if ~isempty(saved.Columns)
                items = dlab.ui.withUnits(saved.Columns, saved.ColumnUnits);
                obj.Columns = saved.Columns;
                obj.ColumnUnits = saved.ColumnUnits;
                keepChoice(obj.SimulatedDropdown, items, saved.Columns);
                if ismember(saved.Simulated, saved.Columns)
                    obj.SimulatedDropdown.Value = saved.Simulated;
                end
            end
            for k = 1:min(numel(saved.Inputs), obj.MaxInputs)
                if ismember(saved.Inputs(k), string(obj.InputDropdowns(k).ItemsData))
                    obj.InputDropdowns(k).Value = saved.Inputs(k);
                end
            end
            if ~isempty(saved.Result)
                obj.show(saved.Result);
            else
                obj.draw();
            end
        end

        function matchColumns(obj)
            %MATCHCOLUMNS Pick the result column named like the measured
            %   one, when there is one, and redraw.
            if ~isempty(obj.Data) && ~isempty(obj.Columns)
                measured = string(obj.MeasuredDropdown.Value);
                if ismember(measured, obj.Columns)
                    obj.SimulatedDropdown.Value = measured;
                end
            end
            obj.draw();
        end

        function draw(obj)
            %DRAW The measured column; after a fit of these columns, the
            %   simulation at the start and at the best, and the residuals.
            t = obj.Theme;
            ax = obj.Axes;
            res = obj.ResidualAxes;
            dlab.ui.clearAxes(ax);
            dlab.ui.clearAxes(res);
            if isempty(obj.Data)
                title(ax, "Measured and simulated");
                return
            end
            name = string(obj.MeasuredDropdown.Value);
            [time, value, unit] = dlab.core.MeasuredData.column(obj.Data, name);
            R = obj.Result;
            current = ~isempty(R) && R.Measured.Name == name && R.Simulated.Name == string(obj.SimulatedDropdown.Value);
            hold(ax, "on");
            if current
                time = R.Measured.Time;
                value = R.Measured.Value;
                unit = R.ValueUnits;
                if ~isempty(R.Simulated.StartTime)
                    plot(ax, R.Simulated.StartTime, R.Simulated.Start, "--", Color=t.TextMuted, ...
                        LineWidth=1.2, DisplayName="Start", Tag="dlab.fit.start");
                end
                if ~isempty(R.Simulated.BestTime)
                    plot(ax, R.Simulated.BestTime, R.Simulated.Best, Color=t.series(1), LineWidth=1.6, ...
                        DisplayName="Best fit", Tag="dlab.fit.best");
                end
            end
            plot(ax, time, value, LineStyle="none", Marker="o", MarkerSize=4, Color=t.Text, ...
                DisplayName="Measured: " + name, Tag="dlab.fit.measuredData");
            hold(ax, "off");
            title(ax, "Measured " + name, Interpreter="none");
            ylabel(ax, dlab.ui.withUnits(name, unit), Interpreter="none");
            span = [min(time) max(time)];
            if current
                dlab.ui.legend(ax, t, "Location", "best", "Interpreter", "none");
                title(ax, "Measured " + name + " and simulated " + R.Simulated.Name, Interpreter="none");
                line(res, R.Residuals.Time, R.Residuals.Value, LineStyle="none", Marker=".", MarkerSize=8, ...
                    Color=t.series(1), Tag="dlab.fit.residual");
                yline(res, 0, Color=t.TextMuted);
                title(res, "Residuals at the best fit (measured − simulated)");
                ylabel(res, dlab.ui.withUnits("Residual", unit));
            else
                title(res, "Residuals appear after a fit.");
                ylabel(res, "Residual");
            end
            if span(2) > span(1)
                xlim(ax, span);
                xlim(res, span);
            end
        end
    end
end

function name = firstVisible(specs, params)
% The first input shown on the left for PARAMS (fitting a hidden one does nothing).
name = "";
for spec = specs'
    try
        visible = spec.VisibleWhen(params);
    catch
        visible = false;
    end
    if visible
        name = spec.Name;
        return
    end
end
end

function keepChoice(dropdown, items, keys)
% Offer ITEMS (keys KEYS), keeping the current choice when it is still offered.
previous = "";
if ~isempty(dropdown.ItemsData)
    previous = string(dropdown.Value);
end
set(dropdown, Items=items, ItemsData=keys, Enable="on");
if ismember(previous, keys)
    dropdown.Value = previous;
end
end

function choose(dropdown, key, what)
if ~ismember(key, string(dropdown.ItemsData))
    error("dlab:fit:choice", "There is no %s ""%s"".", what, key);
end
dropdown.Value = key;
end
