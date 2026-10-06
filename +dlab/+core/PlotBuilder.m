classdef PlotBuilder < handle
    %PLOTBUILDER The "Custom plot" tab: any two numeric columns of the
    %   result's export table against each other. Kept runs (compare mode)
    %   are drawn faintly behind the current run. With measured data
    %   (setMeasured) and time on X, a measured column is drawn as markers.
    %
    %   X [time (s) ▾]   Y [angle (deg) ▾]   Measured [angle ▾]
    %   ┌──────────────────────────────┐
    %   │            plot              │
    %   └──────────────────────────────┘

    properties (SetAccess = private)
        Grid
        Axes
        XDropdown
        YDropdown
        MeasuredDropdown
        Selection struct = struct("X", "", "Y", "", "Measured", "")
        Measured = []          % dlab.core.MeasuredData.read struct, or []
    end

    properties (Access = private)
        Theme
        Table = table.empty
        MeasuredChosen (1,1) logical = false   % the user picked a measured column (or None)
        Runs = struct("Table", {}, "Label", {}, "Color", {})
    end

    methods
        function obj = PlotBuilder(parent, theme, selection)
            arguments
                parent
                theme (1,1) dlab.ui.Theme
                selection = []
            end
            t = theme;
            obj.Theme = t;
            if ~isempty(selection)
                for field = string(fieldnames(selection))'
                    obj.Selection.(field) = string(selection.(field));   % older snapshots lack Measured
                end
            end
            obj.Grid = uigridlayout(parent, [2 1], RowHeight={30, "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            bar = uigridlayout(obj.Grid, [1 7], ColumnWidth={"fit", 200, "fit", 200, "fit", 160, "1x"}, ...
                RowHeight={26}, Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            dlab.ui.label(bar, "X", t, Role="muted");
            obj.XDropdown = uidropdown(bar, Items={'–'}, BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                Tag="dlab.customplot.x", Enable="off", ValueChangedFcn=@(src, ~) obj.choose("X", src.Value));
            dlab.ui.label(bar, "Y", t, Role="muted");
            obj.YDropdown = uidropdown(bar, Items={'–'}, BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                Tag="dlab.customplot.y", Enable="off", ValueChangedFcn=@(src, ~) obj.choose("Y", src.Value));
            dlab.ui.label(bar, "Measured", t, Role="muted");
            obj.MeasuredDropdown = uidropdown(bar, Items={'None'}, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.customplot.measured", Enable="off", ...
                Tooltip="Measured data (import it in the Fit tab), drawn as markers when X is time", ...
                ValueChangedFcn=@(src, ~) obj.choose("Measured", src.Value));
            hint = dlab.ui.label(bar, "Kept runs are drawn faintly.", t, Role="muted");
            hint.HorizontalAlignment = "right";
            obj.Axes = dlab.ui.axesIn(obj.Grid, t);
            obj.Axes.Layout.Row = 2;
            obj.Axes.Tag = "dlab.customplot.axes";
            title(obj.Axes, "Run the simulation to plot its results.");
        end

        function show(obj, T, runs)
            %SHOW Offer T's numeric columns and draw the current choice.
            %   RUNS: struct array (Table, Label, Color) of kept runs.
            arguments
                obj
                T table
                runs = struct("Table", {}, "Label", {}, "Color", {})
            end
            obj.Table = T;
            obj.Runs = runs;
            names = numericColumns(T);
            if isempty(names)
                obj.clear();
                title(obj.Axes, "This result has no numeric columns to plot.");
                return
            end
            units = columnUnits(T, names);
            items = names;
            items(units ~= "") = names(units ~= "") + " (" + units(units ~= "") + ")";
            for axis = ["X" "Y"]
                dropdown = obj.(axis + "Dropdown");
                set(dropdown, Items=items, ItemsData=names, Enable="on");
                if ~ismember(obj.Selection.(axis), names)
                    obj.Selection.(axis) = names(min(1 + (axis == "Y"), numel(names)));
                end
                dropdown.Value = obj.Selection.(axis);
            end
            obj.matchMeasured();
            obj.draw();
        end

        function setMeasured(obj, D)
            %SETMEASURED Offer the columns of measured data D (from
            %   dlab.core.MeasuredData.read); the one named like Y is
            %   shown until the user picks another (or None).
            obj.Measured = D;
            obj.MeasuredChosen = false;
            columns = D.Columns;
            items = dlab.ui.withUnits(columns, D.Units);
            set(obj.MeasuredDropdown, Items=["None" items], ItemsData=["" columns], Enable="on");
            if ~ismember(obj.Selection.Measured, columns)
                obj.Selection.Measured = "";
            end
            obj.matchMeasured();
            obj.draw();
        end

        function clearMeasured(obj)
            obj.Measured = [];
            obj.Selection.Measured = "";
            set(obj.MeasuredDropdown, Items={'None'}, ItemsData={}, Enable="off");
            obj.draw();
        end

        function clear(obj)
            obj.Table = table.empty;
            obj.Runs = struct("Table", {}, "Label", {}, "Color", {});
            dlab.ui.clearAxes(obj.Axes);
            set([obj.XDropdown obj.YDropdown], Items={'–'}, Enable="off");
            xlabel(obj.Axes, "");
            ylabel(obj.Axes, "");
            title(obj.Axes, "Run the simulation to plot its results.");
        end

        function choose(obj, axis, name)
            %CHOOSE Select column NAME for AXIS ("X", "Y", or "Measured",
            %   a measured column or "" for none) and redraw.
            obj.Selection.(axis) = string(name);
            obj.(axis + "Dropdown").Value = string(name);
            obj.MeasuredChosen = obj.MeasuredChosen || axis == "Measured";
            obj.draw();
        end
    end

    methods (Access = private)
        function matchMeasured(obj)
            %MATCHMEASURED Until the user picks one, the measured column
            %   named like Y is shown.
            if isempty(obj.Measured)
                return
            end
            if ~obj.MeasuredChosen && obj.Selection.Measured == "" && ismember(obj.Selection.Y, obj.Measured.Columns)
                obj.Selection.Measured = obj.Selection.Y;
            end
            obj.MeasuredDropdown.Value = obj.Selection.Measured;
        end

        function draw(obj)
            t = obj.Theme;
            ax = obj.Axes;
            if width(obj.Table) == 0
                return             % nothing to draw on until a result is shown
            end
            dlab.ui.clearAxes(ax);
            x = obj.Selection.X;
            y = obj.Selection.Y;
            for k = 1:numel(obj.Runs)
                R = obj.Runs(k).Table;
                if all(ismember([x y], string(R.Properties.VariableNames)))
                    plot(ax, R.(x), R.(y), Color=[obj.Runs(k).Color 0.45], LineWidth=1.2, ...
                        DisplayName=obj.Runs(k).Label);
                end
            end
            plot(ax, obj.Table.(x), obj.Table.(y), Color=t.series(1), LineWidth=1.6, DisplayName="Current run");
            units = columnUnits(obj.Table, [x y]);
            measured = obj.drawMeasured(units(2));
            hold(ax, "off");
            xlabel(ax, dlab.ui.withUnits(x, units(1)));
            ylabel(ax, dlab.ui.withUnits(y, units(2)));
            title(ax, y + " vs " + x, Interpreter="none");
            set([ax.XLabel ax.YLabel], Interpreter="none");
            ylim(ax, "auto");
            showFlatAsFlat(ax, obj.Table.(y));
            if ~isempty(obj.Runs) || measured
                dlab.ui.legend(ax, t, "Location", "best", "Interpreter", "none");
            end
        end

        function drawn = drawMeasured(obj, unit)
            %DRAWMEASURED The chosen measured column as markers, in the Y
            %   column's unit when it converts, when X is time.
            drawn = false;
            D = obj.Measured;
            name = obj.Selection.Measured;
            timeName = dlab.core.MeasuredData.timeVariable(obj.Table);
            if isempty(D) || name == "" || ~ismember(name, D.Columns) || timeName == "" ...
                    || obj.Selection.X ~= timeName
                return
            end
            [time, value, measuredUnit] = dlab.core.MeasuredData.column(D, name);
            if unit ~= "" && measuredUnit ~= "" && unit ~= measuredUnit
                try
                    value = dlab.physics.convertUnits(value, measuredUnit, unit);
                catch
                    name = name + " (" + measuredUnit + ")";   % drawn as given, unit shown
                end
            end
            t = obj.Theme;
            plot(obj.Axes, time, value, LineStyle="none", Marker="o", MarkerSize=4, Color=t.Text, ...
                DisplayName="Measured: " + name, Tag="dlab.customplot.measuredData");
            drawn = true;
        end
    end
end

function names = numericColumns(T)
names = strings(1, 0);
for name = string(T.Properties.VariableNames)
    value = T.(name);
    if (isnumeric(value) || islogical(value)) && isreal(value) && size(value, 2) == 1
        names(end+1) = name; %#ok<AGROW>
    end
end
end

function units = columnUnits(T, names)
units = strings(size(names));
all = string(T.Properties.VariableUnits);
if isempty(all)
    return
end
for k = 1:numel(names)
    units(k) = all(string(T.Properties.VariableNames) == names(k));
end
end

function showFlatAsFlat(ax, values)
% A column that varies only by rounding (a conserved energy, say) is drawn
% flat, with limits ±5 % about its value, rather than zoomed into the noise.
values = values(isfinite(values));
if isempty(values) || ~isnumeric(values)
    return
end
scale = max(abs(values));
if scale > 0 && max(values) - min(values) <= 1e-9 * scale
    ylim(ax, mean(values) + [-1 1] * 0.05 * scale);
end
end
