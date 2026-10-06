classdef ModesPanel < handle
    %MODESPANEL The "Modes" tab: eigenvalues of the model linearized
    %   about a reference state (Plugin.linearization), as a table and a
    %   pole plot. Filled for the inputs of each run.
    %
    %   Linearized about: hanging straight down.
    %   ┌ Mode │ Eigenvalue │ ωn │ ζ │ Period │ τ │ Stability ┐
    %   ┌ pole plot (s-plane) ───────────────────────────────┐

    properties (SetAccess = private)
        Grid
        Table
        Axes
        NoteLabel
        Analysis = []          % dlab.core.Linearization.analyze output
    end

    properties (Access = private)
        Theme
    end

    methods
        function obj = ModesPanel(parent, theme)
            t = theme;
            obj.Theme = t;
            obj.Grid = uigridlayout(parent, [3 1], RowHeight={"fit", 60, "1x"}, Padding=[t.Spacing.sm 0 0 0], ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.NoteLabel = dlab.ui.label(obj.Grid, "Run the simulation to see its modes.", t, ...
                Role="muted", WordWrap="on", Tag="dlab.modes.note");
            obj.Table = uitable(obj.Grid, RowName={}, Data={}, Tag="dlab.modes.table", ...
                ColumnName={'Mode', 'Eigenvalue (1/s)', 'ωn (rad/s)', 'ζ', 'Period (s)', 'Time constant (s)', 'Stability'}, ...
                ColumnWidth={'auto', 'auto', 'fit', 'fit', 'fit', 'fit', 'fit'}, ...
                ColumnFormat={'char', 'char', 'shortG', 'shortG', 'shortG', 'shortG', 'char'}, ...  % 5.774, not 5.7740
                FontSize=t.FontSize.md, BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text);
            obj.Axes = dlab.ui.axesIn(obj.Grid, t, Title="Poles (s-plane)", XLabel="Real (1/s)", ...
                YLabel="Imaginary (rad/s)");
            obj.Axes.Layout.Row = 3;
            obj.Axes.Tag = "dlab.modes.axes";
        end

        function show(obj, lin)
            %SHOW Analyze LIN (a Plugin.linearization struct) and display it;
            %   [] means the model has no linearization for these inputs.
            if isempty(lin)
                obj.clear("This configuration has no linearization (for example, contacts or a " + ...
                    "trajectory with no equilibrium).");
                return
            end
            L = dlab.core.Linearization.analyze(lin);
            obj.Analysis = L;
            note = "Linearized about " + L.Reference + ".";
            if ~L.IsEquilibrium
                note = note + sprintf("  This state is not an equilibrium (|f(x₀)| = %.3g), " + ...
                    "so the modes describe the motion only near it.", L.Residual);
            end
            obj.NoteLabel.Text = note;
            obj.NoteLabel.FontColor = obj.Theme.TextMuted;
            if ~L.IsEquilibrium
                obj.NoteLabel.FontColor = obj.Theme.Warning;
            end

            M = L.Modes;
            u = string(M.Properties.VariableUnits);
            obj.Table.ColumnName = cellstr(["Mode", "Eigenvalue (" + u(2) + ")", "ωn (" + u(4) + ")", "ζ", ...
                "Period (" + u(7) + ")", "Time constant (" + u(8) + ")", "Stability"]);
            obj.Axes.XLabel.String = "Real (" + u(2) + ")";
            obj.Axes.YLabel.String = "Imaginary (" + u(4) + ")";
            obj.Grid.RowHeight{2} = round(obj.Theme.scaled(min(34 + 23 * height(M), 260)));  % the table, then the plot
            obj.Table.Data = [cellstr(M.Mode), cellstr(M.Eigenvalue), cells(M.NaturalFrequency), ...
                cells(M.DampingRatio), cells(M.Period), cells(M.TimeConstant), cellstr(M.Stability)];
            removeStyle(obj.Table);
            for k = 1:height(M)
                switch M.Stability(k)
                    case "Unstable"
                        addStyle(obj.Table, uistyle(FontColor=obj.Theme.Danger), "cell", [k 7]);
                    case "Stable"
                        addStyle(obj.Table, uistyle(FontColor=obj.Theme.Success), "cell", [k 7]);
                end
            end
            obj.drawPoles(L);
        end

        function clear(obj, note)
            arguments
                obj
                note (1,1) string = "Run the simulation to see its modes."
            end
            obj.Analysis = [];
            obj.Table.Data = {};
            obj.Grid.RowHeight{2} = 60;
            delete(allchild(obj.Axes));
            obj.NoteLabel.Text = note;
            obj.NoteLabel.FontColor = obj.Theme.TextMuted;
        end
    end

    methods (Access = private)
        function drawPoles(obj, L)
            t = obj.Theme;
            ax = obj.Axes;
            delete(allchild(ax));
            lambda = [L.Eigenvalues; conj(L.Eigenvalues(imag(L.Eigenvalues) > 0))];
            extent = max([abs(real(lambda)); abs(imag(lambda)); 1e-3]) * 1.25;
            hold(ax, "on");
            patch(ax, [0 extent extent 0], [-extent -extent extent extent], t.Danger, ...
                FaceAlpha=0.07, EdgeColor="none", HandleVisibility="off");
            xline(ax, 0, Color=t.Grid, HandleVisibility="off");
            yline(ax, 0, Color=t.Grid, HandleVisibility="off");
            stable = real(lambda) < 0;
            plot(ax, real(lambda(stable)), imag(lambda(stable)), "x", MarkerSize=11, LineWidth=2, ...
                Color=t.Success, DisplayName="Stable");
            plot(ax, real(lambda(~stable)), imag(lambda(~stable)), "x", MarkerSize=11, LineWidth=2, ...
                Color=t.Danger, DisplayName="Neutral or unstable");
            hold(ax, "off");
            set(ax, XLim=[-extent extent], YLim=[-extent extent]);
            text(ax, 0.98, 0.98, "unstable side", Units="normalized", HorizontalAlignment="right", ...
                VerticalAlignment="top", Color=t.Danger, FontSize=t.FontSize.sm);
        end
    end
end

function c = cells(values)
% Four significant digits; blank where a quantity does not apply.
c = num2cell(round(values, 4, "significant"));
c(isnan(values)) = {[]};
end
