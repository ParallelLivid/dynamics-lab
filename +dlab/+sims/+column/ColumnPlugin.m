classdef ColumnPlugin < dlab.core.StaticPlugin
    %COLUMNPLUGIN Column buckling: the Euler load for four end conditions,
    %   an imperfect (bowed) column and its load at first yield, a
    %   Southwell plot, and the elastica far past buckling (column_engine).

    properties (Constant)
        Id = "column"
        Title = "Column Buckling"
        Category = "Structural"
        Summary = "Euler buckling loads, imperfect columns and first yield, the Southwell plot, and the elastica."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        EndConditions = ["pinned" "fixedfree" "fixedpinned" "fixedfixed"]
        EndLabels = ["Pin–pin" "Fixed–free" "Fixed–pin" "Fixed–fixed"]
        MaterialLabels = ["Steel" "Aluminium" "Timber" "Custom"]      % short enough for the field
        ShapeLabels = ["Round tube" "Solid rod" "Square box" "Square bar" "Custom"]
    end

    properties (Access = private)
        Ax struct = struct()
    end

    methods
        function obj = ColumnPlugin()
            obj.RunLabel = "Solve";
        end

        function specs = parameters(obj)
            P = @dlab.core.ParamSpec;
            lib = dlab.physics.sectionLibrary();
            isCustomMaterial = @(p) p.material == "custom";
            isCustomShape = @(p) p.shape == "custom";
            specs = [
                P("endCondition", Label="End conditions", Type="choice", Default="pinned", ...
                    Choices=obj.EndConditions, ChoiceLabels=obj.EndLabels, Group="Column", ...
                    Description="Base first. Pin–pin: K = 1. Fixed–free (a flagpole): K = 2. Fixed–pin: " + ...
                    "K = 0.699. Fixed–fixed: K = 0.5. The effective length K L is the length of the pinned " + ...
                    "column with the same buckling load.")
                P("L", Label="Length", Units="m", Default=3, Min=0.01, Max=500, MinInclusive=true, Group="Column", ...
                    Description="The column's length between its ends.")
                P("material", Label="Material", Type="choice", Default="steel", Choices=lib.MaterialNames, ...
                    ChoiceLabels=obj.MaterialLabels, Group="Material", ...
                    Description="Steel A36: E = 200 GPa, yield 250 MPa. Aluminium 6061-T6: 69 GPa, 276 MPa. " + ...
                    "Timber C24: 11 GPa, 21 MPa (compression along the grain). Custom: give E and the yield stress.")
                P("E", Label="Young's modulus E", Units="GPa", Default=200, Min=0, MinInclusive=false, Max=2000, ...
                    Group="Material", VisibleWhen=isCustomMaterial, Description="The custom material's stiffness.")
                P("yieldStress", Label="Yield stress", Units="MPa", Default=250, Min=0, MinInclusive=false, ...
                    Max=1e5, Group="Material", VisibleWhen=isCustomMaterial, ...
                    Description="The stress at which the custom material yields or crushes: the squash load is A σy.")
                P("shape", Label="Section", Type="choice", Default="tube", Choices=lib.ShapeNames, ...
                    ChoiceLabels=obj.ShapeLabels, Group="Section", ...
                    Description="A round tube or square box (outer size D, wall t), a solid round rod or " + ...
                    "square bar (size D), or a custom section given by A, I, and c.")
                P("D", Label="Outer size D", Units="mm", Default=60, Min=0, MinInclusive=false, Max=1e4, ...
                    Group="Section", VisibleWhen=@(p) ~isCustomShape(p), ...
                    Description="The diameter (round) or the width (square).")
                P("t", Label="Wall t", Units="mm", Default=4, Min=0, MinInclusive=false, Max=1e3, Group="Section", ...
                    VisibleWhen=@(p) ismember(p.shape, ["tube" "box"]), ...
                    Description="The wall thickness: less than half of D.")
                P("A", Label="Area A", Units="cm²", Default=7.037, Min=0, MinInclusive=false, Max=1e6, ...
                    Group="Section", VisibleWhen=isCustomShape, Description="The cross-section's area.")
                P("I", Label="Second moment I", Units="cm⁴", Default=27.73, Min=0, MinInclusive=false, Max=1e10, ...
                    Group="Section", VisibleWhen=isCustomShape, Description="About the weaker axis.")
                P("c", Label="Outer fibre c", Units="mm", Default=30, Min=0, MinInclusive=false, Max=1e4, ...
                    Group="Section", VisibleWhen=isCustomShape, ...
                    Description="Distance from the centroid to the most stressed fibre (half the depth).")
                P("loadMode", Label="Load given as", Type="choice", Default="load", Choices=["load" "ratio"], ...
                    ChoiceLabels=["Load P" "P / P_cr"], Group="Load", ...
                    Description="The axial load in kN, or as a fraction of this column's Euler load P_cr.")
                P("P", Label="Axial load P", Units="kN", Default=40, Min=0, Max=1e7, Group="Load", ...
                    VisibleWhen=@(p) p.loadMode == "load", ...
                    Description="The compressive load, along the line through the ends.")
                P("loadRatio", Label="Load ratio P/P_cr", Default=0.5, Min=0, Max=10, Group="Load", ...
                    VisibleWhen=@(p) p.loadMode == "ratio", ...
                    Description="The load as a fraction of P_cr: below 1 for the imperfect column, up to 10 " + ...
                    "for the elastica.")
                P("e0", Label="Initial bow e0", Units="mm", Default=3, Min=0, Max=1e4, Group="Imperfection", ...
                    Description="Amplitude of a bow in the shape of the buckling mode. L/1000 is a typical " + ...
                    "straightness tolerance for steel.")
                P("scatter", Label="Southwell scatter", Units="%", Default=0, Min=0, Max=50, Group="Imperfection", ...
                    Description="Random error added to the deflections ""measured"" for the Southwell plot.")
                P("analysis", Label="Analysis", Type="choice", Default="linear", Choices=["linear" "elastica"], ...
                    ChoiceLabels=["Imperfect" "Elastica"], Group="Analysis", ...
                    Description="Imperfect: the bowed column in small-deflection theory; the bow grows as " + ...
                    "e0 / (1 − P/P_cr). Elastica: the perfect column in large deflection, straight up to " + ...
                    "P_cr, then bending far (not for fixed–pin).")
                P("deflectionScale", Label="Deflection scale", Units="×", Default=0, Min=0, Max=1e6, ...
                    Group="Display", Display=true, VisibleWhen=@(p) p.analysis == "linear", ...
                    Description="0: automatic (the largest deflection drawn at a tenth of the length). " + ...
                    "The elastica is drawn to true scale.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Pinned steel tube", "Values", struct());
            list(end+1) = struct("Name", "Flagpole (fixed–free)", "Values", struct("endCondition", "fixedfree", ...
                "L", 6, "material", "aluminium", "shape", "tube", "D", 100, "t", 3, "P", 2, "e0", 6));
            list(end+1) = struct("Name", "Fixed–fixed timber post", "Values", struct("endCondition", "fixedfixed", ...
                "L", 3, "material", "timber", "shape", "bar", "D", 100, "P", 100, "e0", 3));
            list(end+1) = struct("Name", "Slender aluminium rod", "Values", struct("L", 2, "material", "aluminium", ...
                "shape", "rod", "D", 20, "loadMode", "ratio", "loadRatio", 0.8, "e0", 2));
            list(end+1) = struct("Name", "Imperfect column near P_cr", "Values", struct("loadMode", "ratio", ...
                "loadRatio", 0.95, "e0", 5, "scatter", 3));
            list(end+1) = struct("Name", "Elastica far past buckling", "Values", struct("L", 1, ...
                "material", "aluminium", "shape", "rod", "D", 10, "loadMode", "ratio", "loadRatio", 2, ...
                "e0", 0, "analysis", "elastica"));
        end

        function result = solve(obj, p)
            m = obj.toModel(p);
            m.progressFcn = obj.progressMonitor();
            result = dlab.sims.column.column_engine(m);   % its params leave out progressFcn
        end

        function titles = outputTabs(~, ~)
            titles = ["Deflected shape" "Load–deflection" "Southwell plot" "Stress check" "Column curve" ...
                "End conditions"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.shape = dlab.ui.axesIn(containers{"Deflected shape"}, t, XLabel="Lateral deflection (m)", ...
                YLabel="Height (m)");
            obj.Ax.load = dlab.ui.axesIn(containers{"Load–deflection"}, t, XLabel="Largest deflection δ (mm)", ...
                YLabel="Load P (kN)");
            obj.Ax.southwell = dlab.ui.axesIn(containers{"Southwell plot"}, t, ...
                XLabel="Δ: deflection grown from the initial bow (mm)", YLabel="Δ / P (mm/kN)");
            obj.Ax.stress = dlab.ui.axesIn(containers{"Stress check"}, t, XLabel="Load P (kN)", ...
                YLabel="Largest stress (MPa)");
            obj.Ax.curve = dlab.ui.axesIn(containers{"Column curve"}, t, XLabel="Slenderness K L / r", ...
                YLabel="Mean stress at failure P/A (MPa)");
            obj.Ax.modes = dlab.ui.axesIn(containers{"End conditions"}, t, YLabel="Height x / L");
            for ax = [obj.Ax.shape obj.Ax.modes]
                disableDefaultInteractivity(ax);
            end
        end

        function previewInputs(obj, params)
            obj.drawModes(params);
        end

        function showResult(obj, r, params)
            obj.drawModes(params);
            obj.drawShape(r, params);
            obj.drawLoadDeflection(r);
            obj.drawSouthwell(r);
            obj.drawStress(r);
            obj.drawColumnCurve(r);
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.load, 1e3 * r.curves.linearDeflection, r.curves.P / 1e3, run);
                if r.elastica.available
                    dlab.ui.overlayLine(obj.Ax.load, 1e3 * [0; r.elastica.curveDeflection], ...
                        [0; r.elastica.curveRatio * r.Pcr] / 1e3, run);
                end
                dlab.ui.overlayLine(obj.Ax.stress, r.curves.P / 1e3, clipTo(r.curves.linearStress / 1e6, ...
                    3 * r.params.yieldStress / 1e6), run);
                dlab.ui.overlayLine(obj.Ax.curve, r.columnCurve.slenderness, r.columnCurve.perry / 1e6, run);
            end
        end

        function clearResult(obj)
            for name = ["shape" "load" "southwell" "stress" "curve"]
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
                title(obj.Ax.(name), "");
            end
        end

        function T = exportTable(~, r)
            if r.params.analysis == "elastica" && r.elastica.available
                T = table(r.elastica.height, r.elastica.lateral, VariableNames=["height" "lateral"]);
                T.Properties.VariableUnits = ["m" "m"];
            else
                T = table(r.linear.height, r.linear.initial, r.linear.shape, ...
                    VariableNames=["height" "initialBow" "lateral"]);
                T.Properties.VariableUnits = ["m" "m" "m"];
            end
        end

        function T = summaryTable(~, r)
            fy = r.params.yieldStress;
            elastica = r.params.analysis == "elastica";
            rotation = "Elastica end rotation";
            if r.params.endCondition == "fixedfixed"
                rotation = "Elastica rotation at the quarter points";    % the fixed ends do not turn
            end
            swError = r.southwell.error;
            if abs(swError) < 1e-9
                swError = 0;                    % exact points: rounding noise only
            end
            rows = {
                "Critical load P_cr", r.Pcr / 1e3, "kN"
                "Effective length factor K", r.K, ""
                "Effective length K L", r.effectiveLength, "m"
                "Radius of gyration r", 1e3 * r.radiusOfGyration, "mm"
                "Slenderness K L / r", r.slenderness, ""
                "Limiting slenderness π√(E/σy)", r.limitingSlenderness, ""
                "Squash load A σy", r.squashLoad / 1e3, "kN"
                "Buckling governs", double(r.bucklingGoverns), ""
                "Failure load (first yield)", r.failureLoad / 1e3, "kN"
                "Applied load P", r.P / 1e3, "kN"
                "Load ratio P / P_cr", r.loadRatio, ""
                "Utilization P / failure load", r.utilization, ""
                "Largest deflection", 1e3 * r.deflection, "mm"
                "Amplification", r.linear.amplification, ""
                "Largest stress", r.maxStress / 1e6, "MPa"
                "Stress / yield", r.maxStress / fy, ""
                rotation, rad2deg(r.elastica.alpha), "deg"
                "Elastica end shortening", 1e3 * r.elastica.shortening, "mm"
                "Southwell P_cr (fitted)", r.southwell.Pcr / 1e3, "kN"
                "Southwell error", swError, "%"
            };
            values = cell2mat(rows(:, 2));
            names = string(rows(:, 1));
            keep = isfinite(values);
            if elastica
                keep(names == "Amplification") = false;
            else                                % the elastica belongs to the other analysis
                keep(startsWith(names, "Elastica")) = false;
            end
            T = table(names(keep), values(keep), string(rows(keep, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = strings(height(T), 1);
            governs = T.Quantity == "Buckling governs";
            T.Display(governs) = pick(r.bucklingGoverns, "yes (P_cr < A σy)", "no: yield (A σy < P_cr)");
        end

        function [note, level] = resultNote(~, r)
            level = "success";
            if r.params.analysis == "linear" && r.loadRatio >= 1
                note = "P ≥ P_cr: no bent equilibrium in small-deflection theory (try the elastica)";
                level = "warning";
            elseif r.params.analysis == "elastica" && r.elastica.shortening > r.params.L
                note = "past 2.18 P_cr the elastica's ends pass each other: a shape a real column " + ...
                    "and its supports cannot reach";
                level = "warning";
            elseif r.maxStress > r.params.yieldStress
                note = sprintf("past first yield (stress %.2f × yield)", r.maxStress / r.params.yieldStress);
                level = "warning";
            elseif r.bucklingGoverns
                note = "buckling governs";
            else
                note = "yield governs";
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Elastica far past buckling", "Tab", "Deflected shape", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "A straight, slender column of length L under an axial load P. Euler: P_cr = π² E I / (K L)², " + ...
                "with K = 1 (pinned–pinned), 2 (fixed–free), 0.699 (fixed–pinned), 0.5 (fixed–fixed). " + ...
                "A stocky column yields first (at the squash load A σy); a slender one buckles. They " + ...
                "cross at the slenderness K L / r = π √(E/σy)."
                ""
                "Imperfection: a bow e0 in the shape of the buckling mode grows to δ = e0 / (1 − P/P_cr). The " + ...
                "largest stress P/A + m P δ c / I reaches yield at the Perry–Robertson load (m = 1 for " + ...
                "pin–pin and fixed–free, 0.733 for fixed–pin, 1/2 for fixed–fixed). The Southwell plot of " + ...
                "Δ/P against Δ is a straight line of slope 1/P_cr."
                ""
                "Elastica: θ'' + (P/EI) sin θ = 0, solved by shooting with ode45. Past P_cr the perfect " + ...
                "column bends far, and the load still rises: P/P_cr = (2 K(k)/π)², k = sin(α/2)."
            ], newline);
        end
    end

    methods (Access = private)
        function m = toModel(~, p)
            %TOMODEL The engine's model (SI units) from the inputs.
            lib = dlab.physics.sectionLibrary();
            material = find(lib.MaterialNames == p.material);
            if p.material == "custom"
                [E, fy] = deal(p.E, p.yieldStress);
            else
                [E, fy] = deal(lib.E(material), lib.Yield(material));
            end
            if p.shape == "custom"
                [A, I, c] = deal(p.A, p.I, p.c);
            else
                [A, I, c] = lib.properties(p.shape, p.D, p.t);
                if isnan(A)
                    error("column:InvalidParameter", "The wall t must be less than half the outer size D.");
                end
            end
            m = struct("endCondition", p.endCondition, "L", p.L, "E", E * 1e9, "yieldStress", fy * 1e6, ...
                "A", A * 1e-4, "I", I * 1e-8, "c", c * 1e-3, "P", p.P * 1e3, "loadRatio", NaN, ...
                "e0", p.e0 * 1e-3, "analysis", p.analysis, "scatter", p.scatter / 100);
            if p.loadMode == "ratio"
                m.loadRatio = p.loadRatio;
            end
        end

        function drawModes(obj, params)
            %DRAWMODES The four end conditions side by side, the chosen one
            %   highlighted, with each buckling load.
            t = obj.Theme;
            ax = obj.Ax.modes;
            delete(allchild(ax));
            try
                m = obj.toModel(params);
            catch err
                title(ax, string(err.message));
                return
            end
            e = dlab.sims.column.eulerModes(m.E * m.I, m.L, 101);
            hold(ax, "on");
            gap = 1.5;
            d = 0.05;
            stretch = 0.55;                     % height drawn 1/0.55 times its width scale
            for k = 1:4
                x0 = (k - 1) * gap;
                chosen = e.names(k) == params.endCondition;
                color = t.TextMuted;
                width = 2;
                if chosen
                    color = t.series(1);
                    width = 3.5;
                end
                plot(ax, [x0 x0], [0 1], ":", Color=t.Grid, LineWidth=1);
                plot(ax, x0 + 0.3 * e.modes(:, k), e.x, Color=color, LineWidth=width);
                drawSupports(ax, e.names(k), [x0 0], [x0 + 0.3 * e.modes(end, k) 1], d * [1 stretch], t);
                labelColor = t.TextMuted;
                if chosen
                    labelColor = t.Text;
                end
                text(ax, x0, -0.14, sprintf("%s\nK = %.3g\nP_{cr} = %.4g kN", e.labels(k), e.K(k), ...
                    e.Pcr(k) / 1e3), Color=labelColor, FontSize=t.scaled(9.5), HorizontalAlignment="center", ...
                    VerticalAlignment="top", FontWeight=fontWeight(chosen));
            end
            hold(ax, "off");
            set(ax, XLim=[-0.6, 3 * gap + 0.9], YLim=[-0.55 1.15], DataAspectRatio=[1 stretch 1]);
            ax.XAxis.Visible = "off";
            set(ax, XGrid="off", YTick=0:0.5:1);
            title(ax, "Buckling modes: P_{cr} = π² E I / (K L)²");
        end

        function drawShape(obj, r, params)
            t = obj.Theme;
            ax = obj.Ax.shape;
            delete(allchild(ax));
            legend(ax, "off");
            hold(ax, "on");
            L = r.params.L;
            useElastica = r.params.analysis == "elastica";
            if useElastica
                scale = 1;
                lateral = r.elastica.lateral;
                height = r.elastica.height;
            else
                scale = params.deflectionScale;
                largest = max([abs(r.linear.deflection), r.params.e0]);
                if scale == 0
                    scale = 1;
                    if isfinite(largest) && largest > 0
                        scale = 0.1 * L / largest;
                    end
                end
                lateral = scale * r.linear.shape;
                height = r.linear.height;
            end
            plot(ax, [0 0], [0 L], ":", Color=t.TextMuted, LineWidth=1.5, DisplayName="Straight");
            if ~useElastica && r.params.e0 > 0
                plot(ax, scale * r.linear.initial, height, "--", Color=t.series(3), LineWidth=1.6, ...
                    DisplayName=sprintf("Initial bow e0 = %.3g mm", 1e3 * r.params.e0));
            end
            top = [0 L];
            if all(isfinite(lateral))
                plot(ax, lateral, height, Color=t.series(1), LineWidth=3, DisplayName="Loaded");
                top = [lateral(end) height(end)];
                [~, k] = max(abs(lateral));
                if abs(lateral(k)) > 0
                    plot(ax, lateral(k), height(k), "o", MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text, ...
                        HandleVisibility="off");
                    text(ax, lateral(k), height(k), sprintf("  δ = %.4g mm", 1e3 * r.deflection), ...
                        Color=t.Text, FontSize=t.scaled(9.5), HorizontalAlignment=sideOf(lateral(k)));
                end
            else
                text(ax, 0.05 * L, 0.5 * L, "  No bent equilibrium: P ≥ P_{cr}", Color=t.Danger, FontSize=t.scaled(10));
            end
            d = 0.035 * L;
            drawSupports(ax, r.params.endCondition, [0 0], top, d, t);
            arrow = 0.16 * L;
            quiver(ax, top(1), top(2) + arrow + 2 * d, 0, -arrow, 0, Color=t.series(2), LineWidth=2.5, ...
                MaxHeadSize=0.6, HandleVisibility="off");
            text(ax, top(1) + 0.5 * d, top(2) + 0.5 * arrow + 2 * d, sprintf("  P = %.4g kN", r.P / 1e3), ...
                Color=t.series(2), FontSize=t.scaled(10), HorizontalAlignment="left");
            hold(ax, "off");
            xs = [lateral(:); 0; top(1)];
            xs = xs(isfinite(xs));
            ys = [height(:); 0; L; top(2) + arrow + 4 * d];
            ys = ys(isfinite(ys));
            half = max([max(abs(xs)) * 1.15, 0.3 * L]);
            centre = (max(xs) + min(xs)) / 2;
            set(ax, XLim=centre + [-half half], YLim=[min(ys) - 0.08 * L, max(ys) + 0.04 * L], ...
                DataAspectRatio=[1 1 1]);
            dlab.ui.legend(ax, t, "Location", "northwest");   % southeast covered the base support
            if useElastica
                title(ax, sprintf("Elastica at P = %.3g P_{cr}, true scale", r.loadRatio));
                xlabel(ax, "Lateral deflection (m)");
            else
                title(ax, sprintf("Bowed column, lateral deflection × %.3g", scale));
                xlabel(ax, sprintf("Lateral deflection × %.3g (m)", scale));
            end
        end

        function drawLoadDeflection(obj, r)
            t = obj.Theme;
            ax = obj.Ax.load;
            delete(allchild(ax));
            legend(ax, "off");
            hold(ax, "on");
            Pcr = r.Pcr / 1e3;
            yline(ax, Pcr, "--", "P_{cr}", Color=t.TextMuted, LabelHorizontalAlignment="left", ...
                HandleVisibility="off");
            if r.params.e0 > 0                  % with no bow it is the straight column on the axis
                plot(ax, 1e3 * r.curves.linearDeflection, r.curves.P / 1e3, Color=t.series(1), LineWidth=2, ...
                    DisplayName=sprintf("Imperfect (e0 = %.3g mm), small deflection", 1e3 * r.params.e0));
            end
            extent = [5e3 * r.params.e0, 1e3 * r.linear.deflection];
            if r.elastica.available
                plot(ax, 1e3 * [0; r.elastica.curveDeflection], [0; r.elastica.curveRatio * Pcr], ...
                    Color=t.series(2), LineWidth=2, DisplayName="Perfect column, elastica");
            end
            if isfinite(r.deflection)
                plot(ax, 1e3 * r.deflection, r.P / 1e3, "o", MarkerSize=9, MarkerFaceColor=t.Accent, ...
                    MarkerEdgeColor=t.Text, DisplayName="This load");
                extent(end+1) = 1e3 * r.deflection;
            end
            if r.params.analysis == "elastica" && r.elastica.available
                extent(end+1) = 1e3 * max(0.1 * r.params.L, r.elastica.deflection);
            end
            hold(ax, "off");
            xMax = 1.3 * max([extent(isfinite(extent)), 1e3 * r.params.L / 100]);
            set(ax, XLim=[0 xMax], YLim=[0, 1.25 * max(r.P / 1e3, Pcr)]);
            dlab.ui.legend(ax, t, "Location", "southeast");
            title(ax, "Load against deflection");
        end

        function drawSouthwell(obj, r)
            t = obj.Theme;
            ax = obj.Ax.southwell;
            delete(allchild(ax));
            legend(ax, "off");
            sw = r.southwell;
            if ~sw.available
                title(ax, "The Southwell plot needs an initial bow e0 > 0");
                return
            end
            hold(ax, "on");
            delta = 1e3 * sw.delta;
            ratio = delta ./ (sw.P / 1e3);
            plot(ax, delta, ratio, "o", MarkerSize=8, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text, ...
                DisplayName="Measured");
            line = linspace(0, 1.1 * max(delta), 2);
            plot(ax, line, 1e3 * sw.slope * line + 1e6 * sw.intercept, Color=t.series(2), ...
                LineWidth=2, DisplayName=sprintf("Fit: slope 1/P_{cr}, P_{cr} = %.4g kN", sw.Pcr / 1e3));
            hold(ax, "off");
            set(ax, XLim=[0, 1.1 * max(delta)]);
            dlab.ui.legend(ax, t, "Location", "southeast");
            title(ax, sprintf("Southwell: P_{cr} = %.4g kN from the slope (exact %.4g kN), e0 = %.3g mm", ...
                sw.Pcr / 1e3, r.Pcr / 1e3, 1e3 * sw.e0));
        end

        function drawStress(obj, r)
            t = obj.Theme;
            ax = obj.Ax.stress;
            delete(allchild(ax));
            legend(ax, "off");
            hold(ax, "on");
            fy = r.params.yieldStress / 1e6;
            yline(ax, fy, "-", "Yield", Color=t.Danger, LineWidth=1.5, LabelHorizontalAlignment="left", ...
                HandleVisibility="off");
            xline(ax, r.Pcr / 1e3, "--", "P_{cr}", Color=t.TextMuted, HandleVisibility="off");
            xline(ax, r.squashLoad / 1e3, ":", "A σy", Color=t.TextMuted, HandleVisibility="off");
            limit = 3 * fy;                     % curves are cut off above this stress
            if isfinite(r.maxStress)
                limit = max(limit, 1.2 * r.maxStress / 1e6);
            end
            plot(ax, r.curves.P / 1e3, clipTo(r.curves.linearStress / 1e6, limit), Color=t.series(1), ...
                LineWidth=2, DisplayName="Imperfect, small deflection");
            if r.elastica.available
                P = [0; r.elastica.curveRatio * r.Pcr];
                stress = [0; r.elastica.curveStress];
                plot(ax, P / 1e3, clipTo(stress / 1e6, limit), Color=t.series(2), LineWidth=2, ...
                    DisplayName="Perfect column, elastica");
            end
            plot(ax, r.firstYieldLoad / 1e3, fy, "s", MarkerSize=9, ...
                MarkerFaceColor=t.series(4), MarkerEdgeColor=t.Text, ...
                DisplayName=sprintf("First yield at %.4g kN", r.firstYieldLoad / 1e3));
            if isfinite(r.maxStress)
                plot(ax, r.P / 1e3, r.maxStress / 1e6, "o", MarkerSize=9, MarkerFaceColor=t.Accent, ...
                    MarkerEdgeColor=t.Text, DisplayName="This load");
            end
            hold(ax, "off");
            xMax = 1.15 * max([r.P, min(r.Pcr, r.squashLoad), r.firstYieldLoad]) / 1e3;
            yMax = 1.5 * fy;
            if isfinite(r.maxStress)
                yMax = max(yMax, 1.1 * r.maxStress / 1e6);
            end
            set(ax, XLim=[0 xMax], YLim=[0 yMax]);
            dlab.ui.legend(ax, t, "Location", "northwest");
            title(ax, sprintf("Largest stress P/A + m P δ c / I: %.4g MPa (%.2f × yield)", r.maxStress / 1e6, ...
                r.maxStress / r.params.yieldStress));
        end

        function drawColumnCurve(obj, r)
            t = obj.Theme;
            ax = obj.Ax.curve;
            delete(allchild(ax));
            legend(ax, "off");
            hold(ax, "on");
            c = r.columnCurve;
            fy = r.params.yieldStress / 1e6;
            plot(ax, c.slenderness, clipTo(c.euler / 1e6, 2 * fy), "--", Color=t.series(2), LineWidth=1.6, ...
                DisplayName="Euler π² E / (K L / r)²");
            yline(ax, fy, "-", "Yield", Color=t.Danger, LineWidth=1.5, LabelHorizontalAlignment="right", ...
                HandleVisibility="off");
            xline(ax, r.limitingSlenderness, ":", sprintf("π√(E/σy) = %.0f", r.limitingSlenderness), Color=t.TextMuted, ...
                HandleVisibility="off");
            name = "Perfect column: the smaller of Euler and yield";
            if r.params.e0 > 0
                name = sprintf("First yield, bow e0 = L/%.0f", r.params.L / r.params.e0);
            end
            plot(ax, c.slenderness, c.perry / 1e6, Color=t.series(1), LineWidth=2.2, DisplayName=name);
            plot(ax, r.slenderness, r.failureLoad / r.params.A / 1e6, "o", MarkerSize=10, ...
                MarkerFaceColor=t.Accent, MarkerEdgeColor=t.Text, DisplayName="This column");
            hold(ax, "off");
            set(ax, XLim=[0 max(c.slenderness)], YLim=[0 1.3 * fy]);
            dlab.ui.legend(ax, t, "Location", "northeast");
            title(ax, "Short columns yield, long ones buckle");
        end
    end
end

% ---------------------------------------------------------------- helpers
function y = clipTo(y, limit)
y(y > limit) = NaN;
end

function value = pick(condition, yes, no)
value = no;
if condition
    value = yes;
end
end

function weight = fontWeight(bold)
weight = "normal";
if bold
    weight = "bold";
end
end

function side = sideOf(x)
side = "left";
if x < 0
    side = "right";
end
end

function drawSupports(ax, endCondition, base, top, d, t)
% Supports for a vertical column: base at BASE, the loaded end at TOP. D is
% the symbol size, or [width height] when the axes are not equal.
if isscalar(d)
    d = [d d];
end
[dx, dy] = deal(d(1), d(2));
color = t.series(3);
switch endCondition
    case "pinned"
        [baseKind, topKind] = deal("pin", "pin");
    case "fixedfree"
        [baseKind, topKind] = deal("fixed", "free");
    case "fixedpinned"
        [baseKind, topKind] = deal("fixed", "pin");
    otherwise
        [baseKind, topKind] = deal("fixed", "fixed");
end
for where = ["base" "top"]
    if where == "base"
        [p, kind, s] = deal(base, baseKind, -1);     % s: away from the column
    else
        [p, kind, s] = deal(top, topKind, 1);
    end
    switch kind
        case "pin"
            plot(ax, p(1) + dx * [-1 0 1 -1], p(2) + s * dy * [1.8 0 1.8 1.8], Color=color, LineWidth=2, ...
                HandleVisibility="off");
            [x, y] = hatchAt(p + [0 s * 1.8 * dy], s, 1.5 * dx, 0.6 * dy);
            plot(ax, x, y, Color=color, LineWidth=1.2, HandleVisibility="off");
        case "fixed"
            [x, y] = hatchAt(p, s, 1.7 * dx, 0.8 * dy);
            plot(ax, x, y, Color=color, LineWidth=2, HandleVisibility="off");
    end
end
end

function [x, y] = hatchAt(p, s, half, depth)
% A ground line through P with its ticks on side S (−1 below, +1 above).
if s < 0
    [x, y] = dlab.ui.Schematic.hatch(p - [half 0], p + [half 0], 6, depth);
else
    [x, y] = dlab.ui.Schematic.hatch(p + [half 0], p - [half 0], 6, depth);
end
end
