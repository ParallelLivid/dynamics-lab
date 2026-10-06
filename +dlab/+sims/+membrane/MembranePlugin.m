classdef MembranePlugin < dlab.core.TimeDomainPlugin
    %MEMBRANEPLUGIN Vibrating membrane: square, rectangular, and circular
    %   drums, their modes and nodal lines (Chladni patterns), and why a
    %   drum's overtones are not harmonic. Solved by modes
    %   (simulateMembrane), exact in time.

    properties (Constant)
        Id = "membrane"
        Title = "Vibrating Membrane"
        Category = "Continuum"
        Summary = "Square and circular drums: 2-D modes, nodal lines, Bessel zeros, and where to strike."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        PlaySeconds = 20
        TilesShown = 9
        ModesListed = 20
        Views = ["Surface" "Heatmap"]
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
        ViewMode (1,1) string = "Surface"
        ViewDropdown
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isRect = @(p) p.shape == "rectangle";
            isCircle = @(p) p.shape == "circle";
            notMode = @(p) p.initial ~= "mode";
            specs = [
                P("shape", Label="Shape", Type="choice", Default="rectangle", Choices=["rectangle" "circle"], ...
                    ChoiceLabels=["Rectangle" "Circle"], Group="Membrane", ...
                    Description="Fixed along its whole edge.")
                P("a", Label="Width a", Units="m", Default=0.5, Min=0.01, Max=100, Group="Membrane", VisibleWhen=isRect, ...
                    Description="The rectangle's side along x.")
                P("b", Label="Height b", Units="m", Default=0.5, Min=0.01, Max=100, Group="Membrane", VisibleWhen=isRect, ...
                    Description="The rectangle's side along y.")
                P("R", Label="Radius R", Units="m", Default=0.33, Min=0.005, Max=50, Group="Membrane", ...
                    VisibleWhen=isCircle, Description="The circular drum's radius.")
                P("tension", Label="Tension", Units="N/m", Default=2000, Min=1e-3, Max=1e7, Group="Membrane", ...
                    Description="Tension per unit length of edge. A timpani head is about 2000–5000 N/m.")
                P("rho", Label="Areal density", Units="kg/m²", Default=0.25, Min=1e-5, Max=1e4, Group="Membrane", ...
                    DisplayFormat="%.4g", Description="Mass per area. Wave speed c = √(T/ρ).")
                P("zeta", Label="Damping ratio", Units="%", Default=0.2, Min=0, Max=50, Group="Membrane", ...
                    Description="The same damping ratio for every mode.")
                P("initial", Label="Start", Type="choice", Default="strike", Choices=["strike" "pluck" "mode"], ...
                    ChoiceLabels=["Strike" "Pluck" "One mode"], Group="Excitation", ...
                    Description="A strike gives a small Gaussian patch a speed (a drumstick); a pluck " + ...
                    "displaces it and lets go; One mode starts in a single mode shape.")
                P("height", Label="Amplitude", Units="m/s or m", Default=1, Min=-100, Max=100, Group="Excitation", ...
                    DisplayFormat="%.4g", Description="Speed of a strike; displacement of a pluck or mode.")
                P("strikeX", Label="Position x", Units="× width", Default=0.3, Min=0, Max=1, Group="Excitation", ...
                    VisibleWhen=notMode, Description="Across the width (for a circle, the diameter: 0.5 is the centre).")
                P("strikeY", Label="Position y", Units="× height", Default=0.37, Min=0, Max=1, Group="Excitation", ...
                    VisibleWhen=notMode, Description="Up the height (for a circle, the diameter: 0.5 is the centre).")
                P("width", Label="Width", Units="× size", Default=0.06, Min=0.005, Max=0.5, Group="Excitation", ...
                    VisibleWhen=notMode, Description="Of the Gaussian, as a fraction of the longer side or the diameter.")
                P("modeM", Label="Mode m", Type="integer", Default=2, Min=0, Max=40, Group="Excitation", ...
                    VisibleWhen=@(p) p.initial == "mode", ...
                    Description="Rectangle: half-waves across the width (≥ 1). Circle: nodal diameters (≥ 0).")
                P("modeN", Label="Mode n", Type="integer", Default=1, Min=1, Max=40, Group="Excitation", ...
                    VisibleWhen=@(p) p.initial == "mode", ...
                    Description="Rectangle: half-waves up the height. Circle: nodal circles, counting the rim.")
                P("grid", Label="Grid size", Type="integer", Default=40, Min=8, Max=160, Group="Numerics", ...
                    Description="Grid intervals across the longer side (a circle: across the diameter, as rings " + ...
                    "and 4× as many angles). Halving the spacing cuts frequency errors about 4×.")
                P("modes", Label="Modes kept", Type="integer", Default=60, Min=1, Max=200, Group="Numerics", ...
                    Description="The lowest modes, found with eigs on the sparse Laplacian. A narrow strike " + ...
                    "needs many to capture its energy.")
                P("tspan", Label="Duration", Units="s", Default=0.2, Min=1e-5, Max=1e3, Group="Simulation", ...
                    MarksCustom=false, DisplayFormat="%.4g", Description="How long to follow the motion.")
                P("dtOut", Label="Output step", Units="s", Default=2e-4, Min=1e-7, Max=10, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Time between the stored samples. The motion is exact " + ...
                    "at each; the spectrum reaches half the sampling rate.")
                P("probeX", Label="Probe x", Units="× width", Default=0.72, Min=0, Max=1, Group="Simulation", ...
                    Description="Where the Probe tab records the motion (like a microphone close to the head).")
                P("probeY", Label="Probe y", Units="× height", Default=0.22, Min=0, Max=1, Group="Simulation", ...
                    Description="Up the height (for a circle, the diameter: 0.5 is the centre).")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Square drum struck off-centre", "Values", struct());
            list(end+1) = struct("Name", "Rectangle 2:1", "Values", struct("a", 0.8, "b", 0.4, ...
                "strikeX", 0.3, "strikeY", 0.37));
            list(end+1) = struct("Name", "Circular drum struck at the centre", "Values", struct( ...
                "shape", "circle", "strikeX", 0.5, "strikeY", 0.5));
            list(end+1) = struct("Name", "Circular drum struck off-centre", "Values", struct( ...
                "shape", "circle", "strikeX", 0.8, "strikeY", 0.55));
            list(end+1) = struct("Name", "Single mode (2,1) on the circular drum", "Values", struct( ...
                "shape", "circle", "initial", "mode", "modeM", 2, "modeN", 1, "height", 0.002, "zeta", 0));
            list(end+1) = struct("Name", "Damped strike", "Values", struct( ...
                "shape", "circle", "strikeX", 0.75, "strikeY", 0.5, "zeta", 3, "tspan", 0.1, "dtOut", 1e-4));
        end

        function result = solve(obj, p)
            q = struct("shape", char(p.shape), "a", p.a, "b", p.b, "R", p.R, "tension", p.tension, ...
                "rho", p.rho, "grid", p.grid, "modes", p.modes, "initial", char(p.initial), ...
                "height", p.height, "position", [p.strikeX p.strikeY], "width", p.width, ...
                "mode", [p.modeM p.modeN], "zeta", p.zeta / 100, "tspan", p.tspan, "dtOut", p.dtOut, ...
                "probe", [p.probeX p.probeY], "progressFcn", obj.progressMonitor());
            result = dlab.sims.membrane.simulateMembrane(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Mode shapes" "Frequencies" "Mode content" "Probe" "Energy"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.shapes = dlab.ui.axesIn(containers{"Mode shapes"}, t, ...
                Title="Mode shapes and nodal lines (Chladni patterns)");
            grid = uigridlayout(containers{"Frequencies"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                RowHeight={"2x", "1x"}, BackgroundColor=t.AxesBackground);
            obj.Ax.ratios = dlab.ui.axesIn(grid, t, Row=1, Title="Overtones: f / f₁", XLabel="Mode", ...
                YLabel="f / f₁");
            obj.Ax.errors = dlab.ui.axesIn(grid, t, Row=2, Title="Grid frequency error vs the exact value", ...
                XLabel="Mode", YLabel="Error (%)");
            obj.Ax.content = dlab.ui.axesIn(containers{"Mode content"}, t, Title="Energy in each mode", ...
                XLabel="Mode (m, n)", YLabel="Share of energy (%)");
            grid = uigridlayout(containers{"Probe"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.probe = dlab.ui.axesIn(grid, t, Row=1, Title="Motion at the probe", XLabel="Time (s)", ...
                YLabel="Displacement (m)");
            obj.Ax.spectrum = dlab.ui.axesIn(grid, t, Row=2, Title="Spectrum at the probe", ...
                XLabel="Frequency (Hz)", YLabel="Amplitude (m)");
            obj.Ax.energy = dlab.ui.axesIn(containers{"Energy"}, t, Title="Energy", XLabel="Time (s)", ...
                YLabel="Energy (J)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Displacement", XLabel="x (m)", YLabel="y (m)", ...
                ZLabel="u (m)");
            obj.Anim = struct("axes", ax);
        end

        function buildPlaybackControls(obj, parent, theme)
            parent.ColumnWidth = {"fit", 100};
            dlab.ui.label(parent, "View", theme, Role="muted");
            obj.ViewDropdown = uidropdown(parent, Items=obj.Views, Value=obj.ViewMode, ...
                BackgroundColor=theme.SurfaceRaised, FontColor=theme.Text, Tag="dlab.membrane.view", ...
                ValueChangedFcn=@(src, ~) obj.setViewMode(src.Value));
        end

        function setViewMode(obj, mode)
            %SETVIEWMODE Show the animation as a 3-D surface or a heatmap from above.
            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["Surface" "Heatmap"])}
            end
            obj.ViewMode = mode;
            if ~isempty(obj.ViewDropdown) && isvalid(obj.ViewDropdown)
                obj.ViewDropdown.Value = mode;
            end
            if isfield(obj.Anim, "axes") && isvalid(obj.Anim.axes)
                applyView(obj.Anim.axes, mode);
            end
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            obj.drawShapes(r);
            obj.drawFrequencies(r);
            obj.drawContent(r);

            ax = obj.Ax.probe;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.probe, Color=t.series(3), LineWidth=1.2);
            hold(ax, "off");
            title(ax, sprintf("Motion at (%.3g, %.3g) m", r.probeXY(1), r.probeXY(2)));
            ax = obj.Ax.spectrum;
            dlab.ui.clearAxes(ax);
            [frequency, amplitude] = dlab.physics.amplitudeSpectrum(r.t, r.probe);
            plot(ax, frequency, amplitude, Color=t.series(3), LineWidth=1.2);
            if ~isempty(frequency)
                top = r.frequencies(r.distinct & r.frequencies <= frequency(end));
                for f = reshape(top(1:min(end, 12)), 1, [])
                    xline(ax, f, ":", Color=t.TextMuted, HandleVisibility="off");
                end
                xlim(ax, [0 max(min(frequency(end), 8 * r.frequencies(1)), eps)]);
            end
            hold(ax, "off");

            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.KE, Color=t.series(1), LineWidth=1.4, DisplayName="Kinetic");
            plot(ax, r.t, r.PE, Color=t.series(2), LineWidth=1.4, DisplayName="Potential");
            plot(ax, r.t, r.E, "--", Color=t.Text, LineWidth=1.8, DisplayName="Total");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.energy, run.Result.t, run.Result.E, run);
                dlab.ui.overlayLine(obj.Ax.probe, run.Result.t, run.Result.probe, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            colorbar(obj.Ax.shapes, "off");
            if isfield(obj.Anim, "axes")
                delete(allchild(obj.Anim.axes));
                colorbar(obj.Anim.axes, "off");
            end
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, r)
            % Slow motion: a whole run (a fraction of a second) in about 20 s.
            rate = r.t(end) / obj.PlaySeconds;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "surface")
                return
            end
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            q = r.Q(:, k) + fraction * (r.Q(:, next) - r.Q(:, k));
            Z = reshape(r.plotShapes * q, size(r.plotX));
            a = obj.Anim;
            set(a.surface, ZData=Z, CData=Z);
            probe = r.probe(k) + fraction * (r.probe(next) - r.probe(k));
            set(a.probe, ZData=probe);
            a.readout.String = sprintf("t = %.4g s   u(probe) = %+.3g mm", simTime, 1000 * probe);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.probe, r.KE, r.PE, r.E, ...
                VariableNames=["time" "probe_displacement" "kinetic_energy" "potential_energy" "total_energy"]);
            T.Properties.VariableUnits = ["s" "m" "J" "J" "J"];
        end

        function T = summaryTable(~, r)
            names = strings(0, 1);
            values = zeros(0, 1);
            units = strings(0, 1);
            d = find(r.distinct);
            f = r.frequencies(d);
            add("Fundamental frequency", f(1), "Hz");
            if numel(f) >= 2
                add("f2 / f1", f(2) / f(1), "");
            end
            add("Exact fundamental", r.analytic(d(1)), "Hz");
            add("Fundamental error", 100 * (f(1) - r.analytic(d(1))) / r.analytic(d(1)), "%");
            first = d(1:min(end, 9));
            add("Largest error, first 9 modes", 100 * max(abs(r.frequencies(first) - r.analytic(first)) ./ r.analytic(first)), "%");
            add("Wave speed", r.c, "m/s");
            add("Modes kept", numel(r.frequencies), "");
            add("Grid nodes", r.nodes, "");
            add("Initial energy", r.E(1), "J");
            if r.E(1) > 0
                add("Energy captured by the modes kept", r.captured, "%");
                add("Energy remaining at the end", 100 * r.E(end) / r.E(1), "%");
                [~, dominant] = max(r.modalEnergy);
                add("Dominant mode frequency", r.frequencies(dominant), "Hz");
                if isfinite(r.axisymmetric)
                    share = r.axisymmetric;
                    if share < 1e-9
                        share = 0;              % none excited: rounding noise only
                    end
                    add("Energy in axisymmetric modes", share, "%");
                end
            end
            T = table(names, values, units, VariableNames=["Quantity" "Value" "Units"]);

            function add(name, value, unit)
                names(end+1, 1) = name;
                values(end+1, 1) = value;
                units(end+1, 1) = unit;
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Square drum struck off-centre", "Tab", "Mode shapes", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Membrane:  ρ ∂²u/∂t² = T ∇²u,  u = 0 on the edge   (wave speed c = √(T/ρ))."
                "Rectangle a × b:  f_mn = (c/2) √((m/a)² + (n/b)²).   Circle of radius R:  " + ...
                "f_mn = c j_mn / (2π R), with j_mn the n-th zero of the Bessel function J_m."
                ""
                "The membrane is discretized by finite differences: the 5-point Laplacian on a square " + ...
                "grid for a rectangle, and a polar grid (rings and angles, finite volumes) for a circle. " + ...
                "The lowest modes come from eigs on the sparse matrix, and the motion is their sum, exact " + ...
                "in time, each decaying with the damping ratio. Halving the grid spacing cuts the " + ...
                "frequency errors about four times."
                ""
                "Unlike a string, a drum's overtones are not whole multiples of the fundamental: a square " + ...
                "drum's go 1 : 1.58 : 2 : 2.24, a circular drum's 1 : 1.59 : 2.14 : 2.30. The nodal lines " + ...
                "(lines that never move) are the Chladni patterns. A strike on a nodal line cannot excite " + ...
                "that mode: at the centre of a circular drum only the axisymmetric modes (m = 0) ring."
            ], newline);
        end
    end

    methods (Access = private)
        function drawShapes(obj, r)
            % The first distinct modes in a 3 × 3 grid of tiles, with their nodal lines.
            t = obj.Theme;
            ax = obj.Ax.shapes;
            dlab.ui.clearAxes(ax);
            shown = find(r.distinct, obj.TilesShown);
            f1 = r.frequencies(shown(1));
            X = r.plotX;
            Y = r.plotY;
            spanX = max(X(:)) - min(X(:));
            spanY = max(Y(:)) - min(Y(:));
            gapX = 0.12 * spanX;
            gapY = 0.12 * spanY + 0.12 * max(spanX, spanY);
            for q = 1:numel(shown)
                j = shown(q);
                ox = mod(q - 1, 3) * (spanX + gapX);
                oy = -floor((q - 1) / 3) * (spanY + gapY);
                Z = reshape(r.plotShapes(:, j), size(X));
                Z = Z / max(abs(Z(:)));
                surface(ax, X + ox, Y + oy, zeros(size(Z)), Z, EdgeColor="none", FaceColor="interp", ...
                    HandleVisibility="off");
                [lx, ly] = nodalLines(r, j);
                plot(ax, lx + ox, ly + oy, Color=t.Text, LineWidth=1.4, HandleVisibility="off");
                plot(ax, r.outline(1, :) + ox, r.outline(2, :) + oy, Color=t.TextMuted, LineWidth=1.2);
                text(ax, ox + (min(X(:)) + max(X(:))) / 2, oy + max(Y(:)) + 0.03 * max(spanX, spanY), ...
                    sprintf("(%d,%d)  %.4g Hz  ×%.3f", r.labels(j, 1), r.labels(j, 2), r.frequencies(j), ...
                    r.frequencies(j) / f1), HorizontalAlignment="center", VerticalAlignment="bottom", ...
                    Color=t.Text, FontSize=t.FontSize.sm);
            end
            hold(ax, "off");
            colormap(ax, t.divergingMap());
            clim(ax, [-1 1]);
            tiles = numel(shown);
            columns = min(tiles, 3);
            rowsShown = ceil(tiles / 3);
            margin = 0.03 * max(spanX, spanY);
            axis(ax, "equal");
            set(ax, XLim=[min(X(:)) - margin, max(X(:)) + (columns - 1) * (spanX + gapX) + margin], ...
                YLim=[min(Y(:)) - (rowsShown - 1) * (spanY + gapY) - margin, max(Y(:)) + 0.16 * max(spanX, spanY)]);
            ax.XAxis.Visible = "off";
            ax.YAxis.Visible = "off";
            ax.XGrid = "off";
            ax.YGrid = "off";
        end

        function drawFrequencies(obj, r)
            t = obj.Theme;
            d = find(r.distinct, obj.ModesListed);
            count = numel(d);
            f1 = r.frequencies(d(1));
            ax = obj.Ax.ratios;
            dlab.ui.clearAxes(ax);
            plot(ax, 1:count, 1:count, "--", Color=t.TextMuted, LineWidth=1.2, ...
                DisplayName="A string: 1, 2, 3, …");
            plot(ax, 1:count, r.analytic(d) / r.analytic(d(1)), "o", MarkerSize=9, Color=t.series(2), ...
                LineWidth=1.4, DisplayName="Exact");
            plot(ax, 1:count, r.frequencies(d) / f1, ".", MarkerSize=18, Color=t.series(1), ...
                DisplayName="Grid (eigs)");
            text(ax, 1:count, r.frequencies(d) / f1, "  " + modeNames(r.labels(d, :)), ...
                FontSize=t.FontSize.sm, Color=t.TextMuted, Rotation=90, VerticalAlignment="middle", ...
                HorizontalAlignment="left");
            hold(ax, "off");
            xlim(ax, [0.5 count + 0.5]);
            ylim(ax, [0 1.3 * max(r.frequencies(d) / f1) + 0.3]);     % the string's line runs off the top
            dlab.ui.legend(ax, t, "Location", "southeast");
            title(ax, sprintf("Overtones: f / f₁   (f₁ = %.4g Hz; f₂ / f₁ = %.4f)", f1, ...
                r.frequencies(d(min(2, end))) / f1));

            ax = obj.Ax.errors;
            dlab.ui.clearAxes(ax);
            errors = 100 * (r.frequencies(d) - r.analytic(d)) ./ r.analytic(d);
            bar(ax, 1:count, errors, FaceColor=t.series(1), EdgeColor="none");
            hold(ax, "off");
            xlim(ax, [0.5 count + 0.5]);
            set(ax, XTick=1:count, XTickLabel=modeNames(r.labels(d, :)), XTickLabelRotation=45);
            title(ax, sprintf("Grid frequency error vs the exact value  (h = %.3g m, %d nodes)", r.h, r.nodes));
        end

        function drawContent(obj, r)
            t = obj.Theme;
            ax = obj.Ax.content;
            dlab.ui.clearAxes(ax);
            [labels, ~, which] = unique(r.labels, "rows", "stable");
            share = accumarray(which, r.modalEnergy);
            share = 100 * share / max(sum(share), realmin);
            count = min(size(labels, 1), obj.ModesListed);
            x = (1:count)';
            share = share(1:count);
            labels = labels(1:count, :);
            if r.shape == "circle"
                axisymmetric = labels(:, 1) == 0;
                if any(~axisymmetric)
                    bar(ax, x(~axisymmetric), share(~axisymmetric), 0.7, FaceColor=t.series(1), ...
                        EdgeColor="none", DisplayName="m ≥ 1 (nodal diameters)");
                end
                if any(axisymmetric)
                    bar(ax, x(axisymmetric), share(axisymmetric), 0.7, FaceColor=t.series(2), ...
                        EdgeColor="none", DisplayName="m = 0 (axisymmetric)");
                end
                dlab.ui.legend(ax, t, "Location", "northeast");
            else
                bar(ax, x, share, 0.7, FaceColor=t.series(1), EdgeColor="none");
            end
            hold(ax, "off");
            xlim(ax, [0.4 count + 0.6]);
            set(ax, XTick=x, XTickLabel=modeNames(labels), XTickLabelRotation=45);
            title(ax, sprintf("Energy in each mode  (the %d modes kept hold %.3g %% of the start's energy)", ...
                numel(r.frequencies), r.captured));
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            colorbar(ax, "off");
            limit = max(r.maxDisplacement, eps);
            Z = zeros(size(r.plotX));
            a = obj.Anim;
            a.surface = surface(ax, r.plotX, r.plotY, Z, Z, EdgeColor=t.Grid, EdgeAlpha=0.25, FaceColor="interp");
            plot3(ax, r.outline(1, :), r.outline(2, :), zeros(1, size(r.outline, 2)), Color=t.TextMuted, ...
                LineWidth=1.5);
            if params.initial ~= "mode"
                plot3(ax, r.startXY(1), r.startXY(2), 0, "+", MarkerSize=10, LineWidth=1.6, Color=t.Text);
            end
            a.probe = plot3(ax, r.probeXY(1), r.probeXY(2), 0, "o", MarkerSize=7, ...
                MarkerFaceColor=t.series(3), MarkerEdgeColor=t.Text);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            colormap(ax, t.divergingMap());
            clim(ax, [-limit limit]);
            c = colorbar(ax, Color=t.AxesForeground);
            c.Label.String = "Displacement (m)";
            span = max(max(r.plotX(:)) - min(r.plotX(:)), max(r.plotY(:)) - min(r.plotY(:)));
            set(ax, XLim=[min(r.plotX(:)) max(r.plotX(:))], YLim=[min(r.plotY(:)) max(r.plotY(:))], ...
                ZLim=[-1.05 1.05] * limit, DataAspectRatio=[1 1 limit / (0.3 * span)]);
            applyView(ax, obj.ViewMode);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function applyView(ax, mode)
if mode == "Heatmap"
    view(ax, 2);
else
    view(ax, -35, 32);
end
end

function [x, y] = nodalLines(r, j)
% The exact nodal lines of mode j, NaN-separated. (Contours of the grid
% shape broke where two lines cross.) Rectangle (m, n): x = i a/m, y = k b/n.
% Circle (m, n): the shape is J_m(j_mn r/R) cos mθ, or sin mθ for the second
% of a pair; diameters where that vanishes, circles at r = R j_mi / j_mn.
m = r.labels(j, 1);
n = r.labels(j, 2);
[x, y] = deal(zeros(1, 0));
if r.shape == "circle"
    R = r.params.R;
    paired = j > 1 && isequal(r.labels(j - 1, :), r.labels(j, :));
    for k = 0:2 * m - 1
        angle = (k + 0.5) * pi / m;                 % cos mθ = 0
        if paired
            angle = k * pi / m;                     % sin mθ = 0
        end
        if angle < pi                               % each diameter once
            x = [x, R * cos(angle) * [-1 1], NaN]; %#ok<AGROW>
            y = [y, R * sin(angle) * [-1 1], NaN]; %#ok<AGROW>
        end
    end
    zeros_ = besselZeros(m, n);
    ring = linspace(0, 2 * pi, 181);
    for i = 1:n - 1
        x = [x, R * zeros_(i) / zeros_(n) * cos(ring), NaN]; %#ok<AGROW>
        y = [y, R * zeros_(i) / zeros_(n) * sin(ring), NaN]; %#ok<AGROW>
    end
else
    a = r.params.a;
    b = r.params.b;
    for i = 1:m - 1
        x = [x, i * a / m * [1 1], NaN]; %#ok<AGROW>
        y = [y, 0 b, NaN]; %#ok<AGROW>
    end
    for k = 1:n - 1
        x = [x, 0 a, NaN]; %#ok<AGROW>
        y = [y, k * b / n * [1 1], NaN]; %#ok<AGROW>
    end
end
end

function z = besselZeros(m, count)
% The first COUNT positive zeros of J_m (scan, then fzero).
z = zeros(1, count);
found = 0;
x = 0.1;
f = besselj(m, x);
while found < count
    next = besselj(m, x + 0.1);
    if sign(next) ~= sign(f) && next ~= 0
        found = found + 1;
        z(found) = fzero(@(s) besselj(m, s), [x x + 0.1]);
    end
    x = x + 0.1;
    f = next;
end
end

function names = modeNames(labels)
names = compose("(%d,%d)", labels(:, 1), labels(:, 2));
end
