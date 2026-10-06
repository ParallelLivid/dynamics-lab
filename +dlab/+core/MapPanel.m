classdef MapPanel < handle
    %MAPPANEL The "Map" tab: vary two inputs over a grid and show any key
    %   result as a heat map. The simulator view runs the map as a busy
    %   task (cancellable) and hands the outcome back with show(). Clicking
    %   a cell asks the view to use that cell's two inputs.
    %
    %   X [Launch speed ▾]  from [10]  to [50]  steps [9]  ☐ Log
    %   Y [Launch angle ▾]  from [15]  to [75]  steps [13] ☐ Log      [▶ Run map]
    %   Show [Range ▾]                 117 runs · click a cell to use it [Export CSV…]
    %   ┌ heat map ─────────────────────────────────────────────────────────────┐

    events
        RunRequested      % the view starts the map (or cancels a running one)
        ExportRequested
        ApplyRequested    % a cell was clicked: Chosen holds its inputs
    end

    properties (SetAccess = private)
        Grid
        Axes
        XDropdown
        YDropdown
        XFrom
        XTo
        XSteps
        XLog
        YFrom
        YTo
        YSteps
        YLog
        RunButton
        QuantityDropdown
        ExportButton
        NoteLabel
        Result = []            % last dlab.core.Map result struct
        Quantity (1,1) string = ""
        Chosen = struct()      % the clicked cell's inputs (ApplyRequested)
    end

    properties (Access = private)
        Theme
        Specs
        GetParams
    end

    methods
        function obj = MapPanel(parent, specs, getParams, theme, saved)
            %MAPPANEL GETPARAMS returns the inputs currently on the left.
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
            obj.Grid = uigridlayout(parent, [4 1], RowHeight={30, 30, 30, "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);
            labels = [obj.Specs.Label];
            names = [obj.Specs.Name];
            [obj.XDropdown, obj.XFrom, obj.XTo, obj.XSteps, obj.XLog] = obj.axisRow("X", labels, names, false);
            [obj.YDropdown, obj.YFrom, obj.YTo, obj.YSteps, obj.YLog] = obj.axisRow("Y", labels, names, true);

            bar = uigridlayout(obj.Grid, [1 4], ColumnWidth={"fit", 260, "1x", 110}, RowHeight={26}, ...
                Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            dlab.ui.label(bar, "Show", t, Role="muted");
            obj.QuantityDropdown = uidropdown(bar, Items={'–'}, Enable="off", BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.map.quantity", ValueChangedFcn=@(src, ~) obj.chooseQuantity(src.Value));
            obj.NoteLabel = dlab.ui.label(bar, "Other inputs are taken as set on the left.", t, ...
                Role="muted", HorizontalAlignment="right", Tag="dlab.map.note");
            obj.ExportButton = dlab.ui.button(bar, "Export CSV…", t, Tag="dlab.map.export", ...
                Callback=@(~, ~) notify(obj, "ExportRequested"));
            obj.ExportButton.Enable = "off";

            obj.Axes = dlab.ui.axesIn(obj.Grid, t);
            obj.Axes.Layout.Row = 4;
            obj.Axes.Tag = "dlab.map.axes";
            title(obj.Axes, "Choose two inputs and their ranges, then press Run map.");

            if numel(obj.Specs) < 2
                set([obj.XDropdown obj.YDropdown obj.XFrom obj.XTo obj.XSteps obj.XLog obj.YFrom ...
                    obj.YTo obj.YSteps obj.YLog obj.RunButton], Enable="off");
                title(obj.Axes, "A map needs two numeric inputs; this simulator has fewer.");
            elseif ~isempty(saved)
                obj.restore(saved);
            else
                used = dlab.core.SweepPanel.usedNames(obj.Specs, getParams());
                if numel(used) >= 2
                    obj.XDropdown.Value = used(1);
                    obj.YDropdown.Value = used(2);
                end
                obj.suggestRange("X");
                obj.suggestRange("Y");
            end
        end

        function [xName, xValues, yName, yValues] = request(obj)
            %REQUEST The two inputs and their values the user asked for.
            [xName, xValues] = obj.axisRequest(obj.XDropdown, obj.XFrom, obj.XTo, obj.XSteps, obj.XLog);
            [yName, yValues] = obj.axisRequest(obj.YDropdown, obj.YFrom, obj.YTo, obj.YSteps, obj.YLog);
            if xName == yName
                error("dlab:map:sameInput", "Choose two different inputs for a map.");
            end
            dlab.core.SweepPanel.requireUsed(obj.Specs, [xName yName], obj.GetParams());
            if numel(xValues) * numel(yValues) > dlab.core.Map.MaxPoints
                error("dlab:map:steps", "%d × %d is %d runs; a map takes at most %d.", numel(xValues), ...
                    numel(yValues), numel(xValues) * numel(yValues), dlab.core.Map.MaxPoints);
            end
        end

        function configure(obj, x, y)
            %CONFIGURE Set up a map (lessons use this); it is not run. X and
            %   Y are structs with Name, From, To, Steps, and optionally Log.
            arguments
                obj
                x (1,1) struct
                y (1,1) struct
            end
            obj.setAxis(obj.XDropdown, obj.XFrom, obj.XTo, obj.XSteps, obj.XLog, x);
            obj.setAxis(obj.YDropdown, obj.YFrom, obj.YTo, obj.YSteps, obj.YLog, y);
        end

        function show(obj, M)
            %SHOW Draw a finished map.
            obj.Result = M;
            [items, keys] = mappable(M);
            if isempty(keys)
                obj.QuantityDropdown.Items = {'–'};
                obj.QuantityDropdown.Enable = "off";
            else
                set(obj.QuantityDropdown, Items=items, ItemsData=keys, Enable="on");
                if ~ismember(obj.Quantity, keys)
                    obj.Quantity = keys(1);
                end
                obj.QuantityDropdown.Value = obj.Quantity;
            end
            obj.ExportButton.Enable = "on";
            failed = nnz(M.Errors ~= "");
            note = sprintf("%d runs", numel(M.Errors));
            if failed > 0
                note = note + sprintf(" · %d failed (blank; see the CSV)", failed);
            end
            if M.Cancelled
                note = note + " · cancelled";
            end
            obj.NoteLabel.Text = note + " · click a cell to use its inputs";
            obj.draw();
        end

        function setRunning(obj, running)
            %SETRUNNING The map's button doubles as Cancel while it runs.
            t = obj.Theme;
            if running
                set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger);
            else
                set(obj.RunButton, Text="▶  Run map", BackgroundColor=t.Accent, FontColor=t.OnAccent);
            end
        end

        function chooseQuantity(obj, quantity)
            obj.Quantity = string(quantity);
            obj.draw();
        end

        function choose(obj, x, y)
            %CHOOSE Ask the view to use the grid point nearest (X, Y).
            M = obj.Result;
            if isempty(M)
                return
            end
            [~, i] = min(abs(M.XValues - x));
            [~, j] = min(abs(M.YValues - y));
            obj.Chosen = struct(M.Parameters(1), M.XValues(i), M.Parameters(2), M.YValues(j));
            notify(obj, "ApplyRequested");
        end

        function state = snapshot(obj)
            state = struct("X", axisState(obj.XDropdown, obj.XFrom, obj.XTo, obj.XSteps, obj.XLog), ...
                "Y", axisState(obj.YDropdown, obj.YFrom, obj.YTo, obj.YSteps, obj.YLog), ...
                "Quantity", obj.Quantity, "Result", {obj.Result});
            if numel(obj.Specs) < 2
                state.X.Name = "";
            end
        end
    end

    methods (Access = private)
        function [dropdown, from, to, steps, log] = axisRow(obj, letter, labels, names, last)
            t = obj.Theme;
            tag = "dlab.map." + lower(letter);
            columns = {"fit", 200, "fit", 90, "fit", 90, "fit", 60, "fit", "1x"};
            if last
                columns{end} = 120;
            end
            bar = uigridlayout(obj.Grid, [1 10], ColumnWidth=columns, RowHeight={26}, ...
                Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            dlab.ui.label(bar, letter, t, Role="muted");
            dropdown = uidropdown(bar, Items=labels, ItemsData=names, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag=tag + ".parameter", ValueChangedFcn=@(~, ~) obj.suggestRange(letter));
            if last && numel(names) > 1
                dropdown.Value = names(2);
            end
            dlab.ui.label(bar, "from", t, Role="muted");
            from = numberField(bar, t, tag + ".from");
            dlab.ui.label(bar, "to", t, Role="muted");
            to = numberField(bar, t, tag + ".to");
            dlab.ui.label(bar, "steps", t, Role="muted");
            steps = numberField(bar, t, tag + ".steps");
            set(steps, Limits=[2 floor(sqrt(dlab.core.Map.MaxPoints))], RoundFractionalValues="on", Value=11);
            log = uicheckbox(bar, Text="Log", FontColor=t.Text, Tag=tag + ".log", ...
                Tooltip="Space the values evenly on a logarithmic scale (positive limits only)");
            if last
                obj.RunButton = dlab.ui.button(bar, "▶  Run map", t, Kind="primary", Tag="dlab.map.run", ...
                    Tooltip="Solve once per grid point (Esc cancels)", Callback=@(~, ~) notify(obj, "RunRequested"));
            end
        end

        function [name, values] = axisRequest(obj, dropdown, from, to, steps, log)
            name = string(dropdown.Value);
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            values = dlab.core.Sweep.range(from.Value, to.Value, steps.Value, Log=log.Value, ...
                Integer=spec.Type == "integer");
            for value = values'
                [~, ok, message] = spec.coerce(value);
                if ~ok
                    error("dlab:map:range", "%s %s.", spec.Label, message);
                end
            end
        end

        function setAxis(~, dropdown, from, to, steps, log, s)
            if ~ismember(s.Name, string(dropdown.ItemsData))
                error("dlab:map:parameter", "There is no input ""%s"" to map.", s.Name);
            end
            dropdown.Value = s.Name;
            from.Value = s.From;
            to.Value = s.To;
            steps.Value = s.Steps;
            log.Value = isfield(s, "Log") && s.Log;
        end

        function suggestRange(obj, letter)
            if letter == "X"
                controls = {obj.XDropdown, obj.XFrom, obj.XTo, obj.XLog};
            else
                controls = {obj.YDropdown, obj.YFrom, obj.YTo, obj.YLog};
            end
            spec = dlab.core.ParamSpec.find(obj.Specs, string(controls{1}.Value));
            params = obj.GetParams();
            range = dlab.core.SweepPanel.suggestedRange(spec, params.(spec.Name));
            controls{2}.Value = range(1);
            controls{3}.Value = range(2);
            controls{4}.Value = false;
        end

        function restore(obj, saved)
            names = string(obj.XDropdown.ItemsData);
            if ismember(saved.X.Name, names) && ismember(saved.Y.Name, names)
                obj.configure(saved.X, saved.Y);
            else
                obj.suggestRange("X");
                obj.suggestRange("Y");
            end
            obj.Quantity = saved.Quantity;
            if ~isempty(saved.Result)
                obj.show(saved.Result);
            end
        end

        function draw(obj)
            t = obj.Theme;
            M = obj.Result;
            ax = obj.Axes;
            dlab.ui.clearAxes(ax);
            colorbar(ax, "off");
            [~, keys] = mappable(M);
            if isempty(M) || isempty(keys)
                title(ax, "No numeric results to map.");
                return
            end
            [z, label, units] = dlab.core.Map.layer(M, obj.Quantity);
            [xEdges, xLog] = edgesOf(M.XValues);
            [yEdges, yLog] = edgesOf(M.YValues);
            % A surface with one flat face per grid point (padded: the last
            % row and column of CData are not drawn); NaN faces stay blank.
            c = z;
            c(end+1, :) = NaN;
            c(:, end+1) = NaN;
            surface(ax, xEdges, yEdges, zeros(size(c)), c, EdgeColor="none", FaceColor="flat", ...
                Tag="dlab.map.cells", ButtonDownFcn=@(~, event) obj.choose(event.IntersectionPoint(1), ...
                event.IntersectionPoint(2)));
            colormap(ax, t.sequentialMap(256));
            bar = colorbar(ax, Color=t.AxesForeground);
            bar.Label.String = dlab.ui.withUnits(label, units);
            finite = z(isfinite(z));
            if ~isempty(finite) && max(finite) > min(finite)
                clim(ax, [min(finite) max(finite)]);
            end
            set(ax, XScale=scaleOf(xLog), YScale=scaleOf(yLog), Layer="top", ...
                XLim=xEdges([1 end]), YLim=yEdges([1 end]));
            view(ax, 2);
            xlabel(ax, dlab.ui.withUnits(M.Labels(1), M.Units(1)));
            ylabel(ax, dlab.ui.withUnits(M.Labels(2), M.Units(2)));
            title(ax, label + " over " + M.Labels(1) + " and " + M.Labels(2));
            [best, at] = max(z(:));
            if isfinite(best)
                [j, i] = ind2sub(size(z), at);
                hold(ax, "on");
                plot3(ax, M.XValues(i), M.YValues(j), 1, "o", MarkerSize=10, LineWidth=1.5, ...
                    Color=t.series(2), Tag="dlab.map.max", HitTest="off");
                text(ax, M.XValues(i), M.YValues(j), 1, sprintf("  max %.4g", best), Color=t.series(2), ...
                    FontSize=t.FontSize.sm + 1, VerticalAlignment="bottom", HitTest="off");
                hold(ax, "off");
            end
        end
    end
end

function field = numberField(parent, t, tag)
field = uieditfield(parent, "numeric", ValueDisplayFormat="%.6g", HorizontalAlignment="right", ...
    BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag=tag);
end

function s = axisState(dropdown, from, to, steps, log)
s = struct("Name", string(dropdown.Value), "From", from.Value, "To", to.Value, ...
    "Steps", steps.Value, "Log", log.Value);
end

function [edges, isLog] = edgesOf(values)
% Cell edges halfway between grid values (geometrically for log spacing),
% extended half a step past each end.
values = values(:)';
isLog = all(values > 0) && numel(values) > 2 && abs(std(diff(log(values)))) < 1e-9 && ...
    abs(std(diff(values))) > 1e-9;
if isLog
    edges = exp(edgesOf(log(values)));
    return
end
middles = (values(1:end-1) + values(2:end)) / 2;
edges = [values(1) - (middles(1) - values(1)), middles, values(end) + (values(end) - middles(end))];
end

function s = scaleOf(isLog)
s = "linear";
if isLog
    s = "log";
end
end

function [items, keys] = mappable(M)
% Dropdown labels and keys: each quantity, then each set-valued result's
% number of distinct values.
items = strings(1, 0);
keys = strings(1, 0);
if isempty(M)
    return
end
items = M.Quantities;
hasUnits = M.QuantityUnits ~= "";
items(hasUnits) = items(hasUnits) + " (" + M.QuantityUnits(hasUnits) + ")";
keys = M.Quantities;
if ~isempty(M.SetNames)
    items = [items M.SetNames + " (number of distinct values)"];
    keys = [keys M.SetNames];
end
end
