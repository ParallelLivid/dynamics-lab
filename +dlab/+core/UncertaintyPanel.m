classdef UncertaintyPanel < handle
    %UNCERTAINTYPANEL The "Uncertainty" tab: give some inputs a tolerance,
    %   solve once per random sample about the inputs on the left, and show
    %   the spread of any key result and which inputs drive it. The
    %   simulator view runs the study as a busy task (cancellable) and
    %   hands the outcome back with show().
    %
    %   Samples [ 100 ]  Seed [ 1 ]   Spread: ± half-width or σ …   [▶ Run Monte Carlo]
    %   ┌ Vary │ Input │ Distribution │ Spread │ % ┐  (one row per numeric input)
    %   Show [Range ▾]        100 runs · 2 failed · R² 0.97      [Export CSV…]
    %   ┌ histogram with nominal, mean, 5–95 % band ┐┌ share of variance ┐

    events
        RunRequested      % the view starts the study (or cancels a running one)
        ExportRequested
    end

    properties (SetAccess = private)
        Grid
        Table                  % one row per input: Vary, Input, Distribution, Spread, %
        SamplesField
        SeedField
        RunButton
        QuantityDropdown
        ExportButton
        NoteLabel
        PlotGrid               % both axes (what Export plot saves)
        HistogramAxes
        SensitivityAxes
        Result = []            % last dlab.core.MonteCarlo result struct
        Quantity (1,1) string = ""
    end

    properties (Access = private)
        Theme
        Specs
        GetParams
    end

    properties (Constant, Access = private)
        DefaultPercent = 5      % starting tolerance: ± 5 % of the value
        PoorFit = 0.7           % below this R², the shares are flagged as rough
    end

    methods
        function obj = UncertaintyPanel(parent, specs, getParams, theme, saved)
            %UNCERTAINTYPANEL GETPARAMS returns the inputs currently on the left.
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
            obj.Grid = uigridlayout(parent, [4 1], RowHeight={30, 132, 30, "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);

            bar = uigridlayout(obj.Grid, [1 6], ColumnWidth={"fit", 70, "fit", 80, "1x", 160}, ...
                RowHeight={26}, Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            dlab.ui.label(bar, "Samples", t, Role="muted");
            obj.SamplesField = numberField(bar, t, "dlab.uncertainty.samples");
            set(obj.SamplesField, Limits=[2 dlab.core.MonteCarlo.MaxSamples], RoundFractionalValues="on", ...
                Value=dlab.core.MonteCarlo.DefaultSamples, ...
                Tooltip=sprintf("Runs about the inputs on the left (2 to %d)", dlab.core.MonteCarlo.MaxSamples));
            dlab.ui.label(bar, "Seed", t, Role="muted");
            obj.SeedField = numberField(bar, t, "dlab.uncertainty.seed");
            set(obj.SeedField, Limits=[0 dlab.core.MonteCarlo.MaxSeed], RoundFractionalValues="on", Value=1, ...
                Tooltip="The same seed always draws the same samples");
            dlab.ui.label(bar, "Spread: ± half-width (uniform) or σ (normal), in % of the value when % is ticked.", ...
                t, Role="muted", Tag="dlab.uncertainty.hint");
            obj.RunButton = dlab.ui.button(bar, "▶  Run Monte Carlo", t, Kind="primary", ...
                Tag="dlab.uncertainty.run", Tooltip="Solve once per sample (Esc cancels)", ...
                Callback=@(~, ~) notify(obj, "RunRequested"));

            obj.Table = uitable(obj.Grid, RowName={}, Tag="dlab.uncertainty.inputs", ...
                ColumnName={'Vary', 'Input', 'Distribution', 'Spread', '%'}, ...
                ColumnFormat={'logical', 'char', {'uniform', 'normal'}, 'numeric', 'logical'}, ...
                ColumnEditable=[true false true true true], ColumnWidth={45, 'auto', 100, 90, 40}, ...
                Data=obj.defaultRows(), FontSize=t.FontSize.sm + 1, BackgroundColor=t.SurfaceRaised, ...
                ForegroundColor=t.Text, CellEditCallback=@(~, event) obj.onEdit(event));

            bar2 = uigridlayout(obj.Grid, [1 4], ColumnWidth={"fit", 260, "1x", 110}, RowHeight={26}, ...
                Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            dlab.ui.label(bar2, "Show", t, Role="muted");
            obj.QuantityDropdown = uidropdown(bar2, Items={'–'}, Enable="off", BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.uncertainty.quantity", ...
                ValueChangedFcn=@(src, ~) obj.chooseQuantity(src.Value));
            obj.NoteLabel = dlab.ui.label(bar2, "Other inputs are taken as set on the left.", t, ...
                Role="muted", HorizontalAlignment="right", Tag="dlab.uncertainty.note");
            obj.ExportButton = dlab.ui.button(bar2, "Export CSV…", t, Tag="dlab.uncertainty.export", ...
                Callback=@(~, ~) notify(obj, "ExportRequested"));
            obj.ExportButton.Enable = "off";

            obj.PlotGrid = uigridlayout(obj.Grid, [1 2], ColumnWidth={"3x", "2x"}, Padding=0, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.HistogramAxes = dlab.ui.axesIn(obj.PlotGrid, t, Column=1);
            obj.HistogramAxes.Tag = "dlab.uncertainty.histogram";
            obj.SensitivityAxes = dlab.ui.axesIn(obj.PlotGrid, t, Column=2, Title="What drives it");
            obj.SensitivityAxes.Tag = "dlab.uncertainty.sensitivity";
            title(obj.HistogramAxes, "Tick inputs to vary, then press Run Monte Carlo.");

            if isempty(obj.Specs)
                set([obj.SamplesField obj.SeedField obj.RunButton], Enable="off");
                obj.Table.Enable = "off";
                title(obj.HistogramAxes, "This simulator has no numeric inputs to vary.");
            elseif ~isempty(saved)
                obj.restore(saved);
            end
        end

        function [tolerances, samples, seed] = request(obj)
            %REQUEST The tolerances (dlab.core.MonteCarlo.tolerance table),
            %   sample count, and seed the user asked for.
            data = obj.Table.Data;
            if isempty(data)
                error("dlab:montecarlo:none", "This simulator has no numeric inputs to vary.");
            end
            vary = [data{:, 1}]';
            if ~any(vary)
                error("dlab:montecarlo:none", "Tick at least one input to vary.");
            end
            tolerances = dlab.core.MonteCarlo.tolerance([obj.Specs(vary).Name], ...
                Kind=string(data(vary, 3))', Spread=[data{vary, 4}], Relative=[data{vary, 5}]);
            dlab.core.MonteCarlo.validate(obj.Specs, obj.GetParams(), tolerances);   % readable errors now
            dlab.core.SweepPanel.requireUsed(obj.Specs, [obj.Specs(vary).Name], obj.GetParams());
            samples = obj.SamplesField.Value;
            seed = obj.SeedField.Value;
        end

        function configure(obj, tolerances, options)
            %CONFIGURE Set up a study (lessons use this); it is not run.
            %   TOLERANCES is a dlab.core.MonteCarlo.tolerance table; other
            %   inputs are not varied.
            arguments
                obj
                tolerances table
                options.Samples (1,1) double = obj.SamplesField.Value
                options.Seed (1,1) double = obj.SeedField.Value
            end
            names = [obj.Specs.Name];
            data = obj.Table.Data;
            data(:, 1) = {false};
            for k = 1:height(tolerances)
                row = find(names == string(tolerances.Name(k)), 1);
                if isempty(row)
                    error("dlab:montecarlo:parameter", "There is no input ""%s"" to vary.", tolerances.Name(k));
                end
                data(row, [1 3 4 5]) = {true, char(tolerances.Kind(k)), double(tolerances.Spread(k)), ...
                    logical(tolerances.Relative(k))};
            end
            obj.Table.Data = data;
            obj.SamplesField.Value = options.Samples;
            obj.SeedField.Value = options.Seed;
        end

        function show(obj, R)
            %SHOW Plot a finished study.
            obj.Result = R;
            if isempty(R.Quantities)
                obj.QuantityDropdown.Items = {'–'};
                obj.QuantityDropdown.Enable = "off";
            else
                items = R.Quantities;
                hasUnits = R.QuantityUnits ~= "";
                items(hasUnits) = items(hasUnits) + " (" + R.QuantityUnits(hasUnits) + ")";
                set(obj.QuantityDropdown, Items=items, ItemsData=R.Quantities, Enable="on");
                if ~ismember(obj.Quantity, R.Quantities)
                    obj.Quantity = R.Quantities(1);
                end
                obj.QuantityDropdown.Value = obj.Quantity;
            end
            obj.ExportButton.Enable = "on";
            obj.draw();
        end

        function setRunning(obj, running)
            %SETRUNNING The run button doubles as Cancel while it runs.
            t = obj.Theme;
            if running
                set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger);
            else
                set(obj.RunButton, Text="▶  Run Monte Carlo", BackgroundColor=t.Accent, FontColor=t.OnAccent);
            end
        end

        function chooseQuantity(obj, quantity)
            obj.Quantity = string(quantity);
            if ismember(obj.Quantity, string(obj.QuantityDropdown.ItemsData))
                obj.QuantityDropdown.Value = obj.Quantity;
            end
            obj.draw();
        end

        function state = snapshot(obj)
            data = obj.Table.Data;
            names = strings(1, 0);
            if ~isempty(obj.Specs)
                names = [obj.Specs.Name];
            end
            state = struct("Names", names, "Rows", {data}, "Samples", obj.SamplesField.Value, ...
                "Seed", obj.SeedField.Value, "Quantity", obj.Quantity, "Result", {obj.Result});
        end
    end

    methods (Access = private)
        function data = defaultRows(obj)
            % Not varied; ± 5 % uniform, or ± 1 in the input's units when
            % its value is 0 (a percentage of 0 is no spread).
            n = numel(obj.Specs);
            data = cell(n, 5);
            params = [];
            if n > 0
                params = obj.GetParams();
            end
            for k = 1:n
                spec = obj.Specs(k);
                value = 0;
                if isfield(params, spec.Name)
                    value = double(params.(spec.Name));
                end
                spread = obj.DefaultPercent;
                relative = value ~= 0;
                if ~relative
                    spread = 1;
                end
                data(k, :) = {false, char(dlab.ui.withUnits(spec.Label, spec.Units)), 'uniform', spread, relative};
            end
        end

        function onEdit(obj, event)
            % A bad spread is undone; changing a tolerance ticks Vary.
            row = event.Indices(1);
            column = event.Indices(2);
            data = obj.Table.Data;
            if column == 4 && ~(isnumeric(event.NewData) && isscalar(event.NewData) && ...
                    isfinite(event.NewData) && event.NewData >= 0)
                data{row, 4} = event.PreviousData;
                obj.Table.Data = data;
                return
            end
            if column > 2 && ~data{row, 1}
                data{row, 1} = true;
                obj.Table.Data = data;
            end
        end

        function restore(obj, saved)
            names = [obj.Specs.Name];
            data = obj.Table.Data;
            for k = 1:numel(saved.Names)
                row = find(names == saved.Names(k), 1);
                if ~isempty(row)
                    data(row, [1 3 4 5]) = saved.Rows(k, [1 3 4 5]);
                end
            end
            obj.Table.Data = data;
            obj.SamplesField.Value = saved.Samples;
            obj.SeedField.Value = saved.Seed;
            obj.Quantity = saved.Quantity;
            if ~isempty(saved.Result)
                obj.show(saved.Result);
            end
        end

        function draw(obj)
            R = obj.Result;
            hist = obj.HistogramAxes;
            sens = obj.SensitivityAxes;
            dlab.ui.clearAxes(hist);
            dlab.ui.clearAxes(sens);
            set([hist sens], XLimMode="auto", YLimMode="auto", YTickMode="auto", YTickLabelMode="auto", ...
                YDir="normal");
            xlabel(hist, "");
            ylabel(hist, "");
            xlabel(sens, "");
            if isempty(R) || isempty(R.Quantities)
                title(hist, "No numeric results to show.");
                title(sens, "");
                obj.NoteLabel.Text = obj.note(R, NaN);
                return
            end
            k = find(R.Quantities == obj.Quantity, 1);
            obj.drawHistogram(R, k);
            obj.drawSensitivity(R, k);
            obj.NoteLabel.Text = obj.note(R, R.RSquared(k));
        end

        function drawHistogram(obj, R, k)
            % Counts per bin, with the 5–95 % band, the nominal, and the mean.
            t = obj.Theme;
            ax = obj.HistogramAxes;
            y = R.Data(:, k);
            y = y(isfinite(y));
            xlabel(ax, dlab.ui.withUnits(R.Quantities(k), R.QuantityUnits(k)));
            ylabel(ax, "Runs");
            if isempty(y)
                title(ax, "No run solved.");
                return
            end
            [counts, edges] = histcounts(y, max(5, min(40, ceil(sqrt(numel(y))))));
            top = max(counts) * 1.12;
            hold(ax, "on");
            patch(ax, [R.P05(k) R.P95(k) R.P95(k) R.P05(k)], [0 0 top top], t.Accent, FaceAlpha=0.14, ...
                EdgeColor="none", Tag="dlab.uncertainty.band");
            bar(ax, (edges(1:end-1) + edges(2:end)) / 2, counts, 1, FaceColor=t.series(1), ...
                EdgeColor=t.AxesBackground, Tag="dlab.uncertainty.bars");
            if isfinite(R.Nominal(k))
                xline(ax, R.Nominal(k), "--", "nominal", Color=t.series(2), LineWidth=1.5, ...
                    LabelVerticalAlignment="top", LabelHorizontalAlignment="left", ...
                    LabelOrientation="horizontal", Tag="dlab.uncertainty.nominal");
            end
            % Labels on either side, so they stay apart when the lines meet.
            xline(ax, R.Mean(k), "-", "mean", Color=t.series(3), LineWidth=1.5, ...
                LabelVerticalAlignment="top", LabelHorizontalAlignment="right", ...
                LabelOrientation="horizontal", Tag="dlab.uncertainty.mean");
            hold(ax, "off");
            ylim(ax, [0 top]);
            span = edges(end) - edges(1);
            low = min([edges(1), R.Nominal(k)]);
            high = max([edges(end), R.Nominal(k)]);
            xlim(ax, [low high] + [-1 1] * max(0.03 * span, eps(max(abs([low high])))));
            title(ax, sprintf("%s · mean %.4g · σ %.3g · 90 %% in [%.4g, %.4g]", R.Quantities(k), ...
                R.Mean(k), R.Std(k), R.P05(k), R.P95(k)));
        end

        function drawSensitivity(obj, R, k)
            % Each varied input's share of the variance, largest first.
            t = obj.Theme;
            ax = obj.SensitivityAxes;
            shares = 100 * R.Sensitivity(:, k);
            if all(isnan(shares))
                title(ax, "No spread to explain.");
                return
            end
            [shares, order] = sort(shares, "descend");
            color = t.series(1);
            if R.RSquared(k) < obj.PoorFit
                color = t.Warning;            % the linear picture is poor
            end
            m = numel(shares);
            hold(ax, "on");
            barh(ax, 1:m, shares, 0.6, FaceColor=color, EdgeColor="none", Tag="dlab.uncertainty.shares");
            for j = 1:m
                text(ax, shares(j), j, sprintf("  %.0f %%", shares(j)), Color=t.Text, ...
                    VerticalAlignment="middle", FontSize=t.FontSize.sm);
            end
            hold(ax, "off");
            set(ax, YDir="reverse", YTick=1:m, YTickLabel=cellstr(R.Labels(order)), ...
                YLim=[0.4 m + 0.6], XLim=[0 118]);
            xlabel(ax, "Share of variance (%)");
            if R.RSquared(k) < obj.PoorFit
                title(ax, sprintf("What drives it (R² %.2f: rough)", R.RSquared(k)));
            else
                title(ax, sprintf("What drives it (R² %.2f)", R.RSquared(k)));
            end
        end

        function text = note(~, R, rSquared)
            % "100 runs · 2 failed · 3 samples clipped to the input's range · R² 0.97"
            if isempty(R)
                text = "Other inputs are taken as set on the left.";
                return
            end
            n = size(R.Samples, 1);
            text = sprintf("%d runs", n);
            if R.Cancelled
                text = text + sprintf(" of %d · cancelled", R.Requested);
            end
            failed = nnz(R.Errors ~= "");
            if failed > 0
                text = text + sprintf(" · %d failed", failed);
            end
            if R.NominalError ~= ""
                text = text + " · the nominal run failed";
            end
            clipped = sum(R.Clipped);
            if clipped == 1
                text = text + " · 1 sample clipped to the input's range";
            elseif clipped > 1
                text = text + sprintf(" · %d samples clipped to the input's range", clipped);
            end
            if isfinite(rSquared)
                text = text + sprintf(" · R² %.2f", rSquared);
            end
        end
    end
end

function field = numberField(parent, t, tag)
field = uieditfield(parent, "numeric", ValueDisplayFormat="%.6g", HorizontalAlignment="right", ...
    BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag=tag);
end
