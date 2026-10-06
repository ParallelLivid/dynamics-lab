classdef FramePlugin < dlab.core.StaticPlugin
    %FRAMEPLUGIN 2-D frames and beams: deflections, reactions, and the
    %   bending moment, shear, and axial force diagrams, by the direct
    %   stiffness method (frame_engine). The model is entered in tables,
    %   and nodes can be dragged on the Model canvas.

    properties (Constant)
        Id = "frame"
        Title = "2-D Frame and Beam Solver"
        Category = "Structural"
        Summary = "Beams and rigid frames: deflected shape, bending moment, shear, and axial force diagrams."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        DiagramNames = ["Bending moment" "Shear force" "Axial force"]
        DiagramKeys = ["M" "V" "N"]
        SupportTypes = ["fixed" "pin" "rollerx" "rollery"]
    end

    properties (Access = private)
        Ax struct = struct()
        Tables struct = struct()
        Dragger             % dlab.ui.NodeDragger on the Model canvas
        Drawn struct = struct("params", [], "nodes", zeros(0, 2), "markers", gobjects(0), ...
            "lines", gobjects(0), "elements", zeros(0, 2), "readout", gobjects(0))
    end

    methods
        function specs = parameters(obj)
            P = @dlab.core.ParamSpec;
            C = @dlab.core.TableColumn;
            specs = [
                P("nodes", Label="Nodes", Type="table", Group="Geometry", MinRows=2, MaxRows=40, ...
                    Description="Node A is the first row. Drag nodes on the Model tab.", Columns=[
                        C("x", Label="x", Units="m", Default=0)
                        C("y", Label="y", Units="m", Default=0)
                    ], Default=table([0; 4], [0; 0], VariableNames=["x" "y"]))
                P("elements", Label="Elements", Type="table", Group="Geometry", MinRows=1, MaxRows=60, ...
                    Description="Each element joins two nodes (by row number: 1 is A). E, A, and I default to " + ...
                    "steel and an IPE 300; a hinge releases the moment at that end.", Columns=[
                        C("n1", Label="Start node", Type="integer", Min=1, Default=1)
                        C("n2", Label="End node", Type="integer", Min=1, Default=2)
                        C("E", Label="E", Units="GPa", Min=0, MinInclusive=false, Default=200)
                        C("A", Label="A", Units="cm²", Min=0, MinInclusive=false, Default=53.8)
                        C("I", Label="I", Units="cm⁴", Min=0, MinInclusive=false, Default=8356)
                        C("releaseStart", Label="Hinge at start", Type="logical", Default=false)
                        C("releaseEnd", Label="Hinge at end", Type="logical", Default=false)
                    ], Default=table(1, 2, 200, 53.8, 8356, false, false, VariableNames=["n1" "n2" "E" "A" "I" ...
                        "releaseStart" "releaseEnd"]))
                P("supports", Label="Supports", Type="table", Group="Supports and loads", MinRows=1, MaxRows=40, ...
                    Description="fixed: holds x, y, and rotation; pin: x and y; rollerx: moves along x " + ...
                    "(holds y); rollery: moves along y (holds x).", Columns=[
                        C("node", Label="Node", Type="integer", Min=1, Default=1)
                        C("type", Label="Type", Type="choice", Choices=obj.SupportTypes)
                    ], Default=table(1, "fixed", VariableNames=["node" "type"]))
                P("nodeLoads", Label="Node loads", Type="table", Group="Supports and loads", MinRows=0, MaxRows=40, ...
                    Description="Forces along x (right) and y (up), and a moment M, positive anticlockwise.", Columns=[
                        C("node", Label="Node", Type="integer", Min=1, Default=1)
                        C("Fx", Label="Fx", Units="kN", Default=0)
                        C("Fy", Label="Fy", Units="kN", Default=0)
                        C("M", Label="M", Units="kN·m", Default=0)
                    ], Default=table(2, 0, -10, 0, VariableNames=["node" "Fx" "Fy" "M"]))
                P("elementLoads", Label="Element loads", Type="table", Group="Supports and loads", MinRows=0, ...
                    MaxRows=60, Description="Uniform: kN/m along the element (projected: per horizontal or " + ...
                    "vertical length). Point: kN at a (m) from the element's start.", Columns=[
                        C("element", Label="Element", Type="integer", Min=1, Default=1)
                        C("kind", Label="Kind", Type="choice", Choices=["uniform" "point"])
                        C("direction", Label="Direction", Type="choice", Choices=["global" "local" "projected"])
                        C("wx", Label="x part", Units="kN/m or kN", Default=0)
                        C("wy", Label="y part", Units="kN/m or kN", Default=-5)
                        C("a", Label="a (point)", Units="m", Min=0, Default=0)
                    ], Default=emptyElementLoads())
                P("deflectionScale", Label="Deflection scale", Units="×", Default=0, Min=0, Max=1e6, Group="Display", ...
                    Display=true, Description="0: automatic (the largest displacement drawn at a tenth of the frame).")
                P("showDiagramValues", Label="Label the diagrams", Type="logical", Default=true, Group="Display", ...
                    Display=true, Description="Each element's largest value, and the nodes' displacements.")
                P("showLabels", Label="Show node and element labels", Type="logical", Default=true, Group="Display", ...
                    Display=true, Description="Node letters and element numbers on the Model tab.")
                P("snap", Label="Drag snap", Units="m", Default=0.5, Min=0, Max=100, Group="Display", Display=true, ...
                    Description="Dragged nodes snap to this grid (0: off).")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Cantilever with tip load", "Values", struct());
            udl = @(elements, w, direction) table(elements(:), repmat("uniform", numel(elements), 1), ...
                repmat(string(direction), numel(elements), 1), zeros(numel(elements), 1), ...
                w * ones(numel(elements), 1), zeros(numel(elements), 1), ...
                VariableNames=["element" "kind" "direction" "wx" "wy" "a"]);
            members = @(pairs) table(pairs(:, 1), pairs(:, 2), 200 * ones(size(pairs, 1), 1), ...
                53.8 * ones(size(pairs, 1), 1), 8356 * ones(size(pairs, 1), 1), false(size(pairs, 1), 1), ...
                false(size(pairs, 1), 1), VariableNames=["n1" "n2" "E" "A" "I" "releaseStart" "releaseEnd"]);
            supports = @(nodes, types) table(nodes(:), types(:), VariableNames=["node" "type"]);
            noNodeLoads = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), VariableNames=["node" "Fx" "Fy" "M"]);
            xy = @(points) table(points(:, 1), points(:, 2), VariableNames=["x" "y"]);

            list(end+1) = struct("Name", "Simply supported beam (UDL)", "Values", struct( ...
                "nodes", xy([0 0; 6 0]), "elements", members([1 2]), ...
                "supports", supports([1 2], ["pin" "rollerx"]), "nodeLoads", noNodeLoads, ...
                "elementLoads", udl(1, -5, "global")));
            list(end+1) = struct("Name", "Fixed-end beam", "Values", struct( ...
                "nodes", xy([0 0; 3 0; 6 0]), "elements", members([1 2; 2 3]), ...
                "supports", supports([1 3], ["fixed" "fixed"]), "nodeLoads", noNodeLoads, ...
                "elementLoads", udl([1 2], -5, "global")));
            list(end+1) = struct("Name", "Propped cantilever", "Values", struct( ...
                "nodes", xy([0 0; 5 0]), "elements", members([1 2]), ...
                "supports", supports([1 2], ["fixed" "rollerx"]), "nodeLoads", noNodeLoads, ...
                "elementLoads", udl(1, -4, "global")));
            list(end+1) = struct("Name", "Continuous beam (3 spans)", "Values", struct( ...
                "nodes", xy([0 0; 5 0; 10 0; 15 0]), "elements", members([1 2; 2 3; 3 4]), ...
                "supports", supports(1:4, ["pin" "rollerx" "rollerx" "rollerx"]), "nodeLoads", noNodeLoads, ...
                "elementLoads", udl(1:3, -5, "global")));
            list(end+1) = struct("Name", "Portal frame (wind load)", "Values", struct( ...
                "nodes", xy([0 0; 0 4; 6 4; 6 0]), "elements", members([1 2; 2 3; 3 4]), ...
                "supports", supports([1 4], ["fixed" "fixed"]), ...
                "nodeLoads", table(2, 10, 0, 0, VariableNames=["node" "Fx" "Fy" "M"]), ...
                "elementLoads", udl(2, -10, "global")));
            list(end+1) = struct("Name", "Gable frame (snow load)", "Values", struct( ...
                "nodes", xy([0 0; 0 4; 4 5.5; 8 4; 8 0]), "elements", members([1 2; 2 3; 3 4; 4 5]), ...
                "supports", supports([1 5], ["pin" "pin"]), "nodeLoads", noNodeLoads, ...
                "elementLoads", udl([2 3], -2, "projected")));
        end

        function result = solve(obj, p)
            result = dlab.sims.frame.frame_engine(obj.toModel(p));
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Model" "Deflected shape" "Bending moment" "Shear force" "Axial force" "Results"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.model = dlab.ui.axesIn(containers{"Model"}, t, XLabel="x (m)", YLabel="y (m)");
            disableDefaultInteractivity(obj.Ax.model);
            obj.Dragger = dlab.ui.NodeDragger(obj.Ax.model, Nodes=@() obj.Drawn.nodes, ...
                OnMove=@(k, xy) obj.previewMove(k, xy), OnCommit=@(k, xy) obj.commitMove(k, xy), ...
                OnCancel=@() obj.drawModel(obj.Drawn.params), Snap=@() obj.snapStep(), ...
                Enabled=@() obj.canRequestInputs());
            obj.Ax.deflection = dlab.ui.axesIn(containers{"Deflected shape"}, t, XLabel="x (m)", YLabel="y (m)");
            for k = 1:3
                obj.Ax.(obj.DiagramKeys(k)) = dlab.ui.axesIn(containers{obj.DiagramNames(k)}, t, ...
                    XLabel="x (m)", YLabel="y (m)");
            end
            grid = uigridlayout(containers{"Results"}, [3 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Tables.nodes = resultTable(grid, 1, ["Node" "ux (mm)" "uy (mm)" "θ (mrad)"], t);
            obj.Tables.reactions = resultTable(grid, 2, ["Node" "Direction" "Reaction (kN or kN·m)"], t);
            obj.Tables.elements = resultTable(grid, 3, ["Element" "N1 (kN)" "V1 (kN)" "M1 (kN·m)" "N2 (kN)" ...
                "V2 (kN)" "M2 (kN·m)"], t);
        end

        function previewInputs(obj, params)
            obj.drawModel(params);
        end

        function showResult(obj, r, params)
            obj.drawModel(params);
            model = obj.toModel(params);
            obj.drawDeflection(r, model, params);
            for k = 1:3
                obj.drawDiagram(r, model, params, obj.DiagramKeys(k), obj.DiagramNames(k));
            end
            n = size(model.nodes, 1);
            d = r.displacements;
            obj.Tables.nodes.Data = [cellstr(nodeNames(1:n)), num2cell(round(1e3 * d, 4))];
            directions = ["Fx" "Fy" "M"];
            obj.Tables.reactions.Data = [cellstr(nodeNames(r.reactions(:, 1))), ...
                cellstr(directions(r.reactions(:, 2))'), num2cell(round(r.reactions(:, 3) / 1e3, 4))];
            obj.Tables.elements.Data = [cellstr(string(1:numel(r.diagrams))'), num2cell(round(r.endForces / 1e3, 4))];
        end

        function clearResult(obj)
            for name = ["deflection" "M" "V" "N"]
                delete(allchild(obj.Ax.(name)));
            end
            for name = string(fieldnames(obj.Tables))'
                obj.Tables.(name).Data = {};
            end
        end

        function dragNode(obj, node, xy)
            %DRAGNODE Drag a node as the mouse would (for tests and scripts).
            obj.Dragger.dragProgrammatic(node, xy);
        end

        function T = exportTable(~, r)
            n = size(r.displacements, 1);
            T = table(nodeNames(1:n), r.displacements(:, 1), r.displacements(:, 2), r.displacements(:, 3), ...
                VariableNames=["node" "ux" "uy" "rotation"]);
            T.Properties.VariableUnits = ["" "m" "m" "rad"];
        end

        function T = summaryTable(~, r)
            m = r.maxima;
            rows = {
                "Max |M|", abs(m.moment) / 1e3, "kN·m"
                "Max |M| element", m.momentElement, ""
                "Max |M| position (from the element start)", m.momentX, "m"
                "Max |V|", m.shear / 1e3, "kN"
                "Max |N|", m.axial / 1e3, "kN"
                "Max displacement", 1e3 * m.displacement, "mm"
                "Equilibrium residual (relative)", r.residual, ""
                "Degree of indeterminacy", r.indeterminacy, ""
            };
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Portal frame (wind load)", "Tab", "Bending moment", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Euler–Bernoulli beam-column elements with three degrees of freedom per node (u, v, θ): " + ...
                "the 6 × 6 element stiffness (EA/L for stretching, 12EI/L³, 6EI/L², 4EI/L, 2EI/L for " + ...
                "bending), turned into global axes and assembled. Element loads enter as their " + ...
                "consistent (fixed-end) nodal loads; hinges are condensed out."
                ""
                "The diagrams are exact for uniform and point loads, and so is the deflected shape: the " + ...
                "Hermite interpolation of the end displacements plus the fixed-end beam's own deflection " + ...
                "under the span load."
                ""
                "Sign conventions: N positive in tension; M positive sagging, drawn on the tension side."
            ], newline);
        end
    end

    methods (Access = private)
        function m = toModel(obj, p)
            %TOMODEL The engine's model (SI units) from the input tables.
            specs = obj.parameters();
            cols = @(name) specs(arrayfun(@(s) s.Name == name, specs)).Columns;
            nodes = dlab.core.TableColumn.toTable(cols("nodes"), p.nodes);
            elements = dlab.core.TableColumn.toTable(cols("elements"), p.elements);
            supports = dlab.core.TableColumn.toTable(cols("supports"), p.supports);
            nodeLoads = dlab.core.TableColumn.toTable(cols("nodeLoads"), p.nodeLoads);
            elementLoads = dlab.core.TableColumn.toTable(cols("elementLoads"), p.elementLoads);
            m.nodes = [nodes.x, nodes.y];
            m.elements = struct('n1', num2cell(elements.n1), 'n2', num2cell(elements.n2), ...
                'E', num2cell(elements.E * 1e9), 'A', num2cell(elements.A * 1e-4), 'I', num2cell(elements.I * 1e-8), ...
                'releaseStart', num2cell(elements.releaseStart), 'releaseEnd', num2cell(elements.releaseEnd));
            m.supports = struct('node', num2cell(supports.node), 'type', cellstr(supports.type));
            m.nodeLoads = [nodeLoads.node, 1e3 * [nodeLoads.Fx, nodeLoads.Fy, nodeLoads.M]];
            m.elementLoads = struct('element', num2cell(elementLoads.element), 'kind', cellstr(elementLoads.kind), ...
                'direction', cellstr(elementLoads.direction), 'wx', num2cell(1e3 * elementLoads.wx), ...
                'wy', num2cell(1e3 * elementLoads.wy), 'a', num2cell(elementLoads.a));
            if isempty(m.supports)
                m.supports = struct('node', {}, 'type', {});
            end
        end

        function step = snapStep(obj)
            step = 0;
            if isstruct(obj.Drawn.params) && isfield(obj.Drawn.params, "snap")
                step = obj.Drawn.params.snap;
            end
        end

        function drawModel(obj, params)
            %DRAWMODEL Elements, supports, loads, and labels; nodes draggable.
            t = obj.Theme;
            ax = obj.Ax.model;
            delete(allchild(ax));
            hold(ax, "on");
            try
                model = obj.toModel(params);
            catch err
                title(ax, "The model is incomplete: " + string(err.message));
                hold(ax, "off");
                return
            end
            nodes = model.nodes;
            pairs = [[model.elements.n1]', [model.elements.n2]'];
            valid = all(pairs >= 1 & pairs <= size(nodes, 1), 2);
            obj.Drawn = struct("params", params, "nodes", nodes, "markers", gobjects(0), ...
                "lines", gobjects(size(pairs, 1), 1), "elements", pairs, "readout", gobjects(0));
            [span, symbol] = viewOf(ax, nodes);
            for e = find(valid)'
                obj.Drawn.lines(e) = plot(ax, nodes(pairs(e, :), 1), nodes(pairs(e, :), 2), Color=t.AxesForeground, ...
                    LineWidth=3);
                drawHinges(ax, nodes, pairs(e, :), [model.elements(e).releaseStart model.elements(e).releaseEnd], ...
                    symbol, t);
                if params.showLabels
                    middle = mean(nodes(pairs(e, :), :), 1);
                    text(ax, middle(1), middle(2), "  " + e, Color=t.TextMuted, FontSize=t.scaled(9), ...
                        VerticalAlignment="top", PickableParts="none");
                end
            end
            for s = model.supports'
                if s.node >= 1 && s.node <= size(nodes, 1)
                    drawSupport(ax, nodes(s.node, :), s.type, symbol, t.series(3));
                end
            end
            drawLoads(ax, model, nodes, pairs, valid, span, t);
            markers = plot(ax, nodes(:, 1), nodes(:, 2), "o", LineStyle="none", MarkerSize=9, ...
                MarkerFaceColor=t.series(6), MarkerEdgeColor=t.AxesBackground, Tag="dlab.frame.nodes");
            obj.Dragger.attach(markers);
            obj.Drawn.markers = markers;
            if params.showLabels
                text(ax, nodes(:, 1), nodes(:, 2), "  " + nodeNames(1:size(nodes, 1)), Color=t.series(6), ...
                    FontSize=t.scaled(10), FontWeight="bold", VerticalAlignment="bottom", PickableParts="none");
            end
            obj.Drawn.readout = text(ax, NaN, NaN, "", Color=t.Text, FontName=t.MonoFont, FontSize=t.scaled(9), ...
                VerticalAlignment="top", PickableParts="none");
            hold(ax, "off");
            title(ax, "Drag a node to move it");
        end

        function previewMove(obj, k, xy)
            d = obj.Drawn;
            d.nodes(k, :) = xy;
            obj.Drawn.nodes = d.nodes;
            set(d.markers, XData=d.nodes(:, 1), YData=d.nodes(:, 2));
            for e = find(any(d.elements == k, 2))'
                if isgraphics(d.lines(e))
                    set(d.lines(e), XData=d.nodes(d.elements(e, :), 1), YData=d.nodes(d.elements(e, :), 2));
                end
            end
            set(d.readout, Position=[xy 0], String=sprintf("  %s (%.4g, %.4g)", nodeNames(k), xy(1), xy(2)));
        end

        function commitMove(obj, k, xy)
            %COMMITMOVE One input change (one undo step) with the moved node.
            params = obj.currentInputs();
            specs = obj.parameters();
            columns = specs(arrayfun(@(s) s.Name == "nodes", specs)).Columns;
            nodes = dlab.core.TableColumn.toTable(columns, params.nodes);
            nodes.x(k) = xy(1);
            nodes.y(k) = xy(2);
            obj.requestInputs(struct("nodes", nodes), "Move node " + nodeNames(k));
            % A refused or invalid move leaves the inputs as they were (an
            % applied one has redrawn the model): put the drawing back.
            shown = dlab.core.TableColumn.toTable(columns, obj.currentInputs().nodes);
            if ~isequal([shown.x(k) shown.y(k)], xy(:)')
                obj.drawModel(obj.Drawn.params);
            end
        end

        function drawDeflection(obj, r, model, params)
            t = obj.Theme;
            ax = obj.Ax.deflection;
            delete(allchild(ax));
            hold(ax, "on");
            [span, ~] = viewOf(ax, model.nodes);
            scale = params.deflectionScale;
            if scale == 0
                scale = 0.1 * span / max(r.maxima.displacement, realmin);
            end
            for e = 1:numel(r.diagrams)
                p = r.diagrams(e).points;
                plot(ax, p(:, 1), p(:, 2), ":", Color=t.TextMuted, LineWidth=1.5);
                plot(ax, p(:, 1) + scale * p(:, 3), p(:, 2) + scale * p(:, 4), Color=t.series(1), LineWidth=2.4);
            end
            moved = model.nodes + scale * r.displacements(:, 1:2);
            plot(ax, moved(:, 1), moved(:, 2), "o", MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            if params.showDiagramValues
                shown = 1e3 * r.displacements(:, 1:2);
                shown(abs(shown) < 1e-9 * max(abs(shown(:)))) = 0;     % rounding, not movement
                labels = compose("  %s: %.3g, %.3g mm", nodeNames(1:size(moved, 1)), shown(:, 1), shown(:, 2));
                text(ax, moved(:, 1), moved(:, 2), labels, Color=t.Text, FontSize=t.scaled(8.5), VerticalAlignment="bottom");
            end
            hold(ax, "off");
            title(ax, sprintf("Deflected shape (× %.3g)", scale));
        end

        function drawDiagram(obj, r, model, params, key, name)
            % Each element's diagram drawn across it: positive in series(4),
            % negative in series(1); bending moment on the tension side.
            t = obj.Theme;
            ax = obj.Ax.(key);
            delete(allchild(ax));
            hold(ax, "on");
            [span, ~] = viewOf(ax, model.nodes);
            values = arrayfun(@(d) max(abs(d.(key))), r.diagrams);
            scale = 0.15 * span / max([values(:); realmin]);
            side = 1;
            if key == "M"
                side = -1;                      % sagging (positive) drawn below: the tension side
            end
            units = struct("M", "kN·m", "V", "kN", "N", "kN");
            labelled = zeros(0, 2);             % where values are written already
            for e = 1:numel(r.diagrams)
                d = r.diagrams(e);
                base = d.points(:, 1:2);
                ends = model.nodes([model.elements(e).n1 model.elements(e).n2], :);
                along = (ends(2, :) - ends(1, :)) / norm(ends(2, :) - ends(1, :));
                across = [-along(2) along(1)];
                value = d.(key);
                plot(ax, ends(:, 1), ends(:, 2), Color=t.AxesForeground, LineWidth=2);
                for part = [1 -1]
                    v = max(part * value, 0) * part;
                    if any(v ~= 0)
                        offset = base + side * scale * v .* across;
                        color = t.series(4);
                        if part < 0
                            color = t.series(1);
                        end
                        patch(ax, [base(:, 1); flipud(offset(:, 1))], [base(:, 2); flipud(offset(:, 2))], color, ...
                            FaceAlpha=0.45, EdgeColor=color);
                    end
                end
                if params.showDiagramValues && max(abs(value)) > 1e-9 * max(values)
                    [~, k] = max(abs(value));
                    at = base(k, :) + side * scale * value(k) * across;
                    % Two elements meeting at a support often share their largest
                    % value there: write it once (a continuous beam printed
                    % "−12.5" twice on the same spot).
                    if ~any(vecnorm(labelled - at, 2, 2) < 1e-6 * span)
                        text(ax, at(1), at(2), sprintf(" %.3g", value(k) / 1e3), Color=t.Text, ...
                            FontSize=t.scaled(8.5));
                        labelled(end+1, :) = at; %#ok<AGROW>
                    end
                end
            end
            hold(ax, "off");
            title(ax, sprintf("%s (%s)", name, units.(key)));
        end
    end
end

% ---------------------------------------------------------------- helpers
function T = emptyElementLoads()
T = table(zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["element" "kind" "direction" "wx" "wy" "a"]);
end

function names = nodeNames(indices)
indices = indices(:);
names = strings(numel(indices), 1);
for k = 1:numel(indices)
    i = indices(k);
    names(k) = string(char('A' + mod(i - 1, 26)));
    if i > 26
        names(k) = names(k) + floor((i - 1) / 26);
    end
end
end

function [span, symbol] = viewOf(ax, nodes)
low = min(nodes, [], 1);
high = max(nodes, [], 1);
span = max([high - low, 1]);
centre = (low + high) / 2;
half = span / 2 + 0.25 * span;
set(ax, XLim=centre(1) + [-half half], YLim=centre(2) + [-half half], DataAspectRatio=[1 1 1]);
symbol = 0.04 * span;
end

function tbl = resultTable(parent, row, columns, t)
tbl = uitable(parent, ColumnName=cellstr(columns), RowName={}, FontSize=t.FontSize.md, ...
    BackgroundColor=t.Surface, ForegroundColor=t.Text);
tbl.Layout.Row = row;
end

function drawHinges(ax, nodes, pair, released, d, t)
for k = 1:2
    if released(k)
        other = nodes(pair(3 - k), :);
        here = nodes(pair(k), :);
        at = here + 1.4 * d * (other - here) / norm(other - here);
        [x, y] = dlab.ui.Schematic.circle(at, 0.5 * d, 24);
        patch(ax, x, y, t.AxesBackground, EdgeColor=t.Text, LineWidth=1.3);
    end
end
end

function drawSupport(ax, p, type, d, color)
switch type
    case "fixed"
        [x, y] = dlab.ui.Schematic.hatch(p + [-1.6 * d 0], p + [1.6 * d 0], 6, 0.8 * d);
        plot(ax, x, y, Color=color, LineWidth=2);
    case "pin"
        plot(ax, p(1) + d * [-1 0 1 -1], p(2) + d * [-1.8 0 -1.8 -1.8], Color=color, LineWidth=2);
        [x, y] = dlab.ui.Schematic.hatch(p + [-1.4 * d -1.8 * d], p + [1.4 * d -1.8 * d], 5, 0.6 * d);
        plot(ax, x, y, Color=color, LineWidth=1.2);
    case "rollerx"
        plot(ax, p(1) + d * [-1 0 1 -1], p(2) + d * [-1.5 0 -1.5 -1.5], Color=color, LineWidth=2);
        [cx, cy] = dlab.ui.Schematic.circle(p + [0 -1.85 * d], 0.3 * d, 20);
        plot(ax, cx, cy, Color=color, LineWidth=1.2);
        plot(ax, p(1) + 1.4 * d * [-1 1], p(2) - 2.2 * d * [1 1], Color=color, LineWidth=1.5);
    otherwise   % rollery: a wall on the left
        plot(ax, p(1) + d * [0 -1.5 -1.5 0], p(2) + d * [0 1 -1 0], Color=color, LineWidth=2);
        [cx, cy] = dlab.ui.Schematic.circle(p + [-1.85 * d 0], 0.3 * d, 20);
        plot(ax, cx, cy, Color=color, LineWidth=1.2);
        plot(ax, p(1) - 2.2 * d * [1 1], p(2) + 1.4 * d * [-1 1], Color=color, LineWidth=1.5);
end
end

function drawLoads(ax, model, nodes, pairs, valid, span, t)
% Node loads as arrows (moments as a curved arrow label); element loads as
% rows of small arrows along the element.
color = t.series(2);
largest = max([abs(model.nodeLoads(:, 2:3)), 1e-12], [], "all");
arrow = 0.18 * span;
for k = 1:size(model.nodeLoads, 1)
    node = model.nodeLoads(k, 1);
    if node < 1 || node > size(nodes, 1)
        continue
    end
    p = nodes(node, :);
    f = model.nodeLoads(k, 2:3);
    if any(f ~= 0)
        delta = f / largest * arrow;
        quiver(ax, p(1) - delta(1), p(2) - delta(2), delta(1), delta(2), 0, Color=color, LineWidth=2.5, ...
            MaxHeadSize=0.6);
        text(ax, p(1) - 1.15 * delta(1), p(2) - 1.15 * delta(2), sprintf("%.3g kN", norm(f) / 1e3), ...
            Color=color, FontSize=t.scaled(9), HorizontalAlignment="center");
    end
    if model.nodeLoads(k, 4) ~= 0
        text(ax, p(1), p(2), sprintf("  ↺ %.3g kN·m", model.nodeLoads(k, 4) / 1e3), Color=color, FontSize=t.scaled(9), ...
            VerticalAlignment="top");
    end
end
loads = model.elementLoads;
for j = 1:numel(loads)
    e = loads(j).element;
    if e < 1 || e > numel(valid) || ~valid(e)
        continue
    end
    ends = nodes(pairs(e, :), :);
    L = norm(ends(2, :) - ends(1, :));
    along = (ends(2, :) - ends(1, :)) / L;
    across = [-along(2) along(1)];
    w = [loads(j).wx loads(j).wy];
    if strcmpi(loads(j).direction, "local")
        direction = w(1) * along + w(2) * across;
    else
        direction = w;
    end
    if norm(direction) == 0
        continue
    end
    direction = 0.08 * span * direction / norm(direction);
    if strcmpi(loads(j).kind, "point")
        at = ends(1, :) + loads(j).a * along;
        quiver(ax, at(1) - 2 * direction(1), at(2) - 2 * direction(2), 2 * direction(1), 2 * direction(2), 0, ...
            Color=color, LineWidth=2.2, MaxHeadSize=0.6);
        text(ax, at(1) - 2.3 * direction(1), at(2) - 2.3 * direction(2), sprintf("%.3g kN", norm(w) / 1e3), ...
            Color=color, FontSize=t.scaled(9), HorizontalAlignment="center");
    else
        s = linspace(0, L, 9)';
        tails = ends(1, :) + s * along - direction;
        quiver(ax, tails(:, 1), tails(:, 2), direction(1) * ones(9, 1), direction(2) * ones(9, 1), 0, ...
            Color=color, LineWidth=1.2, MaxHeadSize=0.4);
        plot(ax, tails([1 end], 1), tails([1 end], 2), Color=color, LineWidth=1.2);
        middle = mean(tails([1 end], :), 1) - 0.4 * direction;
        text(ax, middle(1), middle(2), sprintf("%.3g kN/m", norm(w) / 1e3), Color=color, FontSize=t.scaled(9), ...
            HorizontalAlignment="center");
    end
end
end
