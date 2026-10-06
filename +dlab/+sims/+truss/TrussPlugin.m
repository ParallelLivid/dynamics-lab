classdef TrussPlugin < dlab.core.StaticPlugin
    %TRUSSPLUGIN Linear-elastic 2-D pin-jointed truss (direct stiffness method).
    %   The first static plugin and the first with a custom input panel
    %   (dlab.sims.truss.TrussInputs, a table editor for the model). Nodes
    %   can also be dragged on the Model canvas (dlab.ui.NodeDragger).

    properties (Constant)
        Id = "truss"
        Title = "2-D Truss Solver"
        Category = "Structural"
        Summary = "Member forces and deflections of pin-jointed trusses, and whether each member yields or buckles."
        SchemaVersion = 3       % 2: per-member sections replace the global E and A; 3: strength scale
    end

    properties (Constant, Access = private)
        ZeroForce = 1e-9     % |force| below this is reported as zero-force
    end

    properties (Access = private)
        Canvas
        ForceTable
        ReactionTable
        DisplacementTable
        Inputs              % the TrussInputs editor (drag edits go through it)
        Dragger             % dlab.ui.NodeDragger on the canvas
        Drawn struct = struct("params", [], "result", [], "nodes", zeros(0, 2), "members", zeros(0, 2), ...
            "memberLines", gobjects(0), "markers", gobjects(0), "labels", gobjects(0), "readout", gobjects(0))
        SnapStep (1,1) double = 0.5
    end

    methods
        function obj = TrussPlugin()
            obj.RunLabel = "Solve";
        end

        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            specs = [
                P("showNodeIds", Label="Node labels", Type="logical", Default=true, ...
                    Group="Display", Display=true, ...
                    Description="Show each node's number on the drawing.")
                P("showForceValues", Label="Member force values", Type="logical", Default=false, ...
                    Group="Display", Display=true, ...
                    Description="Off by default: labels overlap on dense trusses.")
                P("snap", Label="Snap dragged nodes to", Units="m", Default=0.5, Min=0, Max=10, ...
                    Group="Display", Display=true, ...
                    Description="Grid step for nodes dragged on the Model canvas (0 = no snapping).")
                P("loadScale", Label="Load scale", Units="×", Default=1, Min=0, Max=1000, Group="Loads and strength", ...
                    Description="Multiplies every load in the Forces table. The truss is linear, so the " + ...
                    "forces and utilizations grow in proportion: at the safety factor the first member " + ...
                    "reaches its limit.")
                P("strengthScale", Label="Strength scale", Units="×", Default=1, Min=0, MinInclusive=false, ...
                    Max=100, Group="Loads and strength", ...
                    Description="Multiplies every member's yield stress and buckling load in the strength " + ...
                    "check (the Sections table keeps its values), so the utilizations divide by it. " + ...
                    "Forces and displacements do not change.")
                P("colorBy", Label="Colour members by", Type="choice", Default="utilization", ...
                    Choices=["utilization" "force"], ChoiceLabels=["Utilization" "Force (T/C)"], ...
                    Group="Display", Display=true, Description="Utilization: each member's stress against " + ...
                    "its yield stress and, in compression, its force against its buckling load; 1 = at the limit. " + ...
                    "Force (T/C): red for tension, blue for compression.")
            ];
        end

        function params = defaultParams(obj)
            params = dlab.core.ParamSpec.defaults(obj.parameters());
            first = dlab.sims.truss.presetModels();
            params = mergeModel(params, dlab.sims.truss.TrussInputs.normalize(first(1).Model));   % with its sections
        end

        function list = presets(~)
            models = dlab.sims.truss.presetModels();
            list = struct("Name", {models.Name}, "Values", {models.Model});
        end

        function panel = buildInputs(obj, parent, params, theme)
            panel = dlab.sims.truss.TrussInputs(parent, obj.parameters(), params, theme);
            obj.Inputs = panel;
        end

        function dragNode(obj, node, xy)
            %DRAGNODE Drag NODE to XY as the mouse would (scripts and tests).
            obj.Dragger.dragProgrammatic(node, xy);
        end

        function params = paramsFromJson(~, json)
            params = json;
            model = dlab.sims.truss.TrussInputs.normalize(json);
            for field = string(fieldnames(model))'
                params.(field) = model.(field);
            end
        end

        function result = solve(obj, p)
            model = dlab.sims.truss.TrussInputs.normalize(p);
            sections = model.sections;
            index = model.members(:, 3);
            if any(index < 1 | index > size(sections, 1) | index ~= round(index))
                error("dlab:truss:solve", "Every member needs an existing section (S1–S%d).", size(sections, 1));
            end
            props = sections(index, :);
            model.members = model.members(:, 1:2);
            model.E = props(:, 3) * 1e9;              % GPa → Pa
            model.yieldStress = props(:, 4) * 1e6;    % MPa → Pa
            model.A = props(:, 7) * 1e-4;             % cm² → m²
            model.I = props(:, 8) * 1e-8;             % cm⁴ → m⁴
            if ~isempty(model.forces)
                model.forces(:, 2:3) = model.forces(:, 2:3) * p.loadScale;
            end
            result = dlab.sims.truss.truss_engine(model);
            if ~result.success
                error("dlab:truss:solve", "%s", result.error);
            end
            % The strength scale multiplies both capacities, so each ratio,
            % and the governing mode, scale together.
            result.criticalLoad = result.criticalLoad * p.strengthScale;
            result.eulerLoad = result.eulerLoad * p.strengthScale;
            result.utilization = result.utilization / p.strengthScale;
            % A zero-force member (rounding only) is governed by nothing.
            result.failureMode(abs(result.memberForces) <= obj.ZeroForce) = "";
            result.sectionIndex = index;
            result.members = model.members;          % node pairs, for the member names
        end

        function params = migrate(~, params, fromVersion)
            % Versions 1 and 2 had no strength scale: nominal strength.
            if fromVersion < 3 && ~isfield(params, "strengthScale")
                params.strengthScale = 1;
            end
            % Version 1 had one Young's modulus and area for every member:
            % they become section S1 (steel when E was steel's).
            if fromVersion < 2 && isfield(params, "E") && isfield(params, "A")
                lib = dlab.physics.sectionLibrary();
                area = params.A * 1e4;                % m² → cm²
                section = [find(lib.MaterialNames == "custom"), find(lib.ShapeNames == "custom"), ...
                    params.E / 1e9, 250, 0, 0, area, 0.882 * area^2];   % I like a thick steel tube
                if params.E == 200e9
                    section(1) = find(lib.MaterialNames == "steel");
                end
                params.sections = section;
                params = rmfield(params, ["E" "A"]);
            end
        end

        function titles = outputTabs(~, ~)
            titles = ["Model" "Member forces" "Reactions" "Displacements"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Canvas = dlab.ui.axesIn(containers{"Model"}, t, XLabel="x (m)", YLabel="y (m)");
            obj.Canvas.DataAspectRatio = [1 1 1];
            disableDefaultInteractivity(obj.Canvas);
            obj.Dragger = dlab.ui.NodeDragger(obj.Canvas, Nodes=@() obj.Drawn.nodes, ...
                OnMove=@(k, xy) obj.previewMove(k, xy), OnCommit=@(k, xy) obj.commitMove(k, xy), ...
                OnCancel=@() obj.draw(obj.Drawn.params, obj.Drawn.result), Snap=@() obj.SnapStep, ...
                Enabled=@() obj.canDrag());
            obj.ForceTable = resultTable(containers{"Member forces"}, ["Member" "Force (kN)" "State" ...
                "Section" "Stress (MPa)" "Utilization" "Governed by"], t, "dlab.truss.result.state");
            obj.ReactionTable = resultTable(containers{"Reactions"}, ["Node" "Direction" "Reaction (kN)"], t);
            obj.DisplacementTable = resultTable(containers{"Displacements"}, ["Node" "ux (mm)" "uy (mm)"], t);
        end

        function previewInputs(obj, params)
            obj.draw(params, []);
        end

        function showResult(obj, result, params)
            model = dlab.sims.truss.TrussInputs.normalize(params);
            obj.draw(params, result);
            names = memberNames(model);
            forces = result.memberForces;
            modes = result.failureMode;
            modes(result.utilization > 1) = upper(modes(result.utilization > 1)) + " — FAILS";
            obj.ForceTable.Data = [cellstr(names), num2cell(round(forces / 1000, 4)), cellstr(obj.states(forces)), ...
                cellstr("S" + model.members(:, 3)), num2cell(round(result.stress / 1e6, 3)), ...
                num2cell(round(result.utilization, 3)), cellstr(modes)];

            reactions = result.reactions;
            directions = ["X"; "Y"];
            obj.ReactionTable.Data = [cellstr(nodeNames(reactions(:, 1))), ...
                cellstr(directions(reactions(:, 2))), num2cell(round(reactions(:, 3) / 1000, 4))];

            nNodes = size(model.nodes, 1);
            U = reshape(result.U, 2, nNodes)' * 1000;
            obj.DisplacementTable.Data = [cellstr(nodeNames((1:nNodes)')), num2cell(round(U, 6))];
        end

        function clearResult(obj)
            obj.ForceTable.Data = {};
            obj.ReactionTable.Data = {};
            obj.DisplacementTable.Data = {};
        end

        function T = exportTable(obj, result)
            % Member forces and the strength check; the MAT export also
            % holds reactions and displacements. The Euler load is each
            % member's, whatever its force (it governs only in compression).
            n = numel(result.memberForces);
            names = (1:n)';
            if isfield(result, "members")
                names = memberNames(struct("members", result.members));
            end
            T = table(names, result.memberForces, obj.states(result.memberForces), result.stress, ...
                result.eulerLoad, result.utilization, result.failureMode, ...
                VariableNames=["member" "force" "state" "stress" "euler_load" "utilization" "governed_by"]);
            T.Properties.VariableUnits = ["" "N" "" "Pa" "N" "" ""];
        end

        function T = summaryTable(obj, result)
            % The results first (the analysis tools offer the first row
            % by default), the counts last.
            f = result.memberForces;
            maxTension = max([0; f(f > obj.ZeroForce)]);
            maxCompression = max([0; -f(f < -obj.ZeroForce)]);
            displacement = max(hypot(result.U(1:2:end), result.U(2:2:end))) * 1000;
            T = table(["Largest tension"; "Largest compression"; "Largest displacement"], ...
                [maxTension / 1000; maxCompression / 1000; displacement], ["kN"; "kN"; "mm"], ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Format = repmat("", height(T), 1);
            T.Display = repmat("", height(T), 1);
            if isfield(result, "utilization") && any(isfinite(result.utilization))
                [worst, k] = max(result.utilization);
                names = memberNames(struct("members", result.members));
                buckling = result.failureMode == "buckling" & result.utilization > 1;
                yielding = result.failureMode == "yield" & result.utilization > 1;
                strength = table(["Largest utilization"; "Safety factor"; "Members that fail"; ...
                    "Fail by buckling"; "Fail by yielding"], ...
                    [worst; 1 / worst; nnz(result.utilization > 1); nnz(buckling); nnz(yielding)], ...
                    ["" ; ""; ""; ""; ""], VariableNames=["Quantity" "Value" "Units"]);
                strength.Format = repmat("", height(strength), 1);
                strength.Display = repmat("", height(strength), 1);
                % The governing member is text: a Display row, so metrics
                % (sweeps, lessons) keep plain numbers. Members within
                % rounding of the largest share it.
                if worst > 0
                    tied = nnz(result.utilization >= worst * (1 - 1e-9));
                    governing = names(k) + " (" + result.failureMode(k) + ")";
                    if tied > 1
                        governing = governing + sprintf(" and %d more as high", tied - 1);
                    end
                else
                    strength.Display(strength.Quantity == "Safety factor") = "— (no load)";
                    governing = "— (no load)";
                end
                strength(end+1, :) = {"Governing member", NaN, "", "", governing};
                T = [T; strength];
            end
            counts = table(["Members"; "Degrees of freedom"], [numel(f); numel(result.U)], ["" ; ""], ...
                ["" ; ""], ["" ; ""], VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
            T = [T; counts];
        end

        function [note, level] = resultNote(~, result)
            level = "success";
            note = "";
            if isfield(result, "utilization") && any(result.utilization > 1)
                [note, level] = deal(sprintf("%d member(s) fail the strength check", ...
                    nnz(result.utilization > 1)), "warning");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Footbridge check (steel tubes)", "Tab", "Model", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Linear-elastic, pin-jointed 2-D truss solved with the direct stiffness method."
                ""
                "Positive member force is tension, negative is compression. Supports: pin " + ...
                "(X and Y fixed), roller fixing X, or roller fixing Y. Loads act at nodes. Each " + ...
                "member has a section (Sections tab): its material sets E and the yield stress, and " + ...
                "its shape and size set A and I. A determinate truss's forces do not depend on them; " + ...
                "an indeterminate one's do (stiffer members attract more load)."
                ""
                "Strength check: each member's stress N/A against its yield stress, and, in " + ...
                "compression, its force against the Euler buckling load of a pin-ended member, " + ...
                "P_cr = π² E I / L². The utilization is the larger ratio: above 1 the member fails. " + ...
                "The safety factor (1 / the largest utilization) is also the load multiplier at the " + ...
                "first failure, as the model is linear. The strength scale multiplies every " + ...
                "member's yield stress and buckling load, so the utilizations divide by it (scatter " + ...
                "in strength, for the Uncertainty tab). It is a check, not a failure simulation: a " + ...
                "failed member is not removed, and connections are not checked."
                ""
                "Edit the model in the Nodes, Members, Sections, Forces, and Supports tables on the left."
            ], newline);
        end
    end

    methods (Access = private)
        function previewMove(obj, k, xy)
            %PREVIEWMOVE Move node K's marker, label, and members while dragging.
            d = obj.Drawn;
            d.nodes(k, :) = xy;
            obj.Drawn.nodes = d.nodes;
            set(d.markers, XData=d.nodes(:, 1), YData=d.nodes(:, 2));
            for m = find(any(d.members == k, 2))'
                if isgraphics(d.memberLines(m))
                    set(d.memberLines(m), XData=d.nodes(d.members(m, :), 1), YData=d.nodes(d.members(m, :), 2));
                end
            end
            if numel(d.labels) >= k && isgraphics(d.labels(k))
                d.labels(k).Position(1:2) = xy;
            end
            set(d.readout, Position=[xy 0], String=sprintf("  %s (%.4g, %.4g)", ...
                dlab.sims.truss.nodeLabel(k), xy(1), xy(2)));
        end

        function commitMove(obj, k, xy)
            %COMMITMOVE Send the drag to the editor: one input change.
            if obj.canDrag()
                obj.Inputs.moveNode(k, xy(1), xy(2));
            else
                obj.draw(obj.Drawn.params, obj.Drawn.result);
            end
        end

        function tf = canDrag(obj)
            tf = ~isempty(obj.Inputs) && isvalid(obj.Inputs) && obj.Inputs.Enabled;
        end

        function states = states(obj, forces)
            states = repmat("Zero-force", numel(forces), 1);
            states(forces > obj.ZeroForce) = "Tension";
            states(forces < -obj.ZeroForce) = "Compression";
        end

        function draw(obj, params, result)
            %DRAW The model, coloured by member force once solved.
            t = obj.Theme;
            ax = obj.Canvas;
            cla(ax);
            model = dlab.sims.truss.TrussInputs.normalize(params);
            nodes = model.nodes;
            obj.Drawn = struct("params", params, "result", result, "nodes", nodes, "members", model.members(:, 1:2), ...
                "memberLines", gobjects(size(model.members, 1), 1), "markers", gobjects(0), ...
                "labels", gobjects(0), "readout", gobjects(0));
            if isfield(params, "snap")
                obj.SnapStep = params.snap;
            end
            if isempty(nodes)
                title(ax, "No nodes yet: add nodes in the Nodes table to begin.");
                return
            end
            solved = ~isempty(result) && numel(result.memberForces) == size(model.members, 1);

            % Square view around the model.
            low = min(nodes, [], 1);
            high = max(nodes, [], 1);
            span = max([high - low, 1]);
            centre = (low + high) / 2;
            half = span / 2 + 0.22 * span;
            set(ax, XLim=centre(1) + [-half half], YLim=centre(2) + [-half half]);
            symbol = 0.046 * span;

            hold(ax, "on");
            names = memberNames(model);
            byUtilization = solved && (~isfield(params, "colorBy") || params.colorBy == "utilization") && ...
                isfield(result, "utilization");
            map = t.sequentialMap(256);
            map = map(65:end, :);        % without the faintest quarter: unloaded members stay visible
            for k = 1:size(model.members, 1)
                ends = model.members(k, 1:2);
                if any(ends < 1 | ends > size(nodes, 1))
                    continue
                end
                [color, width] = deal(t.AxesForeground, 2);
                if byUtilization
                    u = result.utilization(k);
                    if u > 1
                        [color, width] = deal(t.Danger, 4);
                    elseif isfinite(u)
                        [color, width] = deal(map(1 + round((size(map, 1) - 1) * u), :), 3);
                    end
                elseif solved
                    force = result.memberForces(k);
                    if force > obj.ZeroForce
                        [color, width] = deal(t.series(4), 3);
                    elseif force < -obj.ZeroForce
                        [color, width] = deal(t.series(1), 3);
                    else
                        [color, width] = deal(t.TextMuted, 1.8);
                    end
                end
                obj.Drawn.memberLines(k) = plot(ax, nodes(ends, 1), nodes(ends, 2), "-", Color=color, LineWidth=width);
                if solved && params.showForceValues
                    middle = mean(nodes(ends, :), 1);
                    text(ax, middle(1), middle(2), names(k) + "  " + formatForce(result.memberForces(k)), ...
                        Color=t.Warning, FontSize=t.scaled(8.5), FontWeight="bold", Interpreter="none", ...
                        HorizontalAlignment="center", VerticalAlignment="bottom");
                end
            end

            for k = 1:size(model.supports, 1)
                node = model.supports(k, 1);
                if node >= 1 && node <= size(nodes, 1)
                    drawSupport(ax, nodes(node, :), model.supports(k, 2), symbol, t.series(3));
                end
            end

            if ~isempty(model.forces) && isfield(params, "loadScale")
                model.forces(:, 2:3) = model.forces(:, 2:3) * params.loadScale;   % as solved
            end
            if ~isempty(model.forces)
                largest = max(abs(model.forces(:, 2:3)), [], "all");
                scale = 0.18 * span / max(largest, 1e-12);
                for k = 1:size(model.forces, 1)
                    node = model.forces(k, 1);
                    load = model.forces(k, 2:3);
                    if node >= 1 && node <= size(nodes, 1) && any(abs(load) > 1e-12)
                        drawLoad(ax, nodes(node, :), load, scale, t.series(2), t);
                    end
                end
            end

            markers = plot(ax, nodes(:, 1), nodes(:, 2), "o", LineStyle="none", MarkerSize=10, LineWidth=1.3, ...
                MarkerFaceColor=t.series(6), MarkerEdgeColor=t.AxesBackground, Tag="dlab.truss.nodes");
            obj.Dragger.attach(markers);
            obj.Drawn.markers = markers;
            if params.showNodeIds
                obj.Drawn.labels = text(ax, nodes(:, 1), nodes(:, 2), "  " + nodeNames((1:size(nodes, 1))'), ...
                    Color=t.series(6), FontSize=t.scaled(10), FontWeight="bold", ...
                    VerticalAlignment="bottom", Interpreter="none", PickableParts="none");
            end
            obj.Drawn.readout = text(ax, NaN, NaN, "", Color=t.Text, FontName=t.MonoFont, FontSize=t.scaled(9), ...
                VerticalAlignment="top", PickableParts="none", Tag="dlab.truss.dragReadout");
            hold(ax, "off");

            heading = sprintf("%d nodes  |  %d members", size(nodes, 1), size(model.members, 1));
            if byUtilization
                colormap(ax, map);
                clim(ax, [0 1]);
                bar = colorbar(ax, Color=t.Text);
                bar.Label.String = "Utilization (thick, alarm colour: fails)";
                heading = heading + sprintf("  |  largest utilization %.2f", max(result.utilization));
            elseif solved
                heading = heading + "  |  solved  (red = tension, blue = compression)";
                colorbar(ax, "off");
            else
                colorbar(ax, "off");
            end
            title(ax, heading + "  |  drag a node to move it");
        end
    end
end

function params = mergeModel(params, model)
for field = string(fieldnames(model))'
    params.(field) = model.(field);
end
end

function names = nodeNames(indices)
names = strings(numel(indices), 1);
for k = 1:numel(indices)
    names(k) = dlab.sims.truss.nodeLabel(indices(k));
end
end

function names = memberNames(model)
names = strings(size(model.members, 1), 1);
for k = 1:numel(names)
    names(k) = dlab.sims.truss.nodeLabel(model.members(k, 1)) + "-" + ...
        dlab.sims.truss.nodeLabel(model.members(k, 2));
end
end

function tbl = resultTable(parent, columns, t, tag)
if nargin < 4
    tag = "dlab.truss.result." + lower(regexprep(columns(end), "\W.*", ""));
end
tbl = uitable(parent, ColumnName=cellstr(columns), RowName={}, Data={}, ...
    FontSize=t.FontSize.md, BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, Tag=tag);
end

function formatted = formatForce(f)
if abs(f) >= 1e6
    formatted = sprintf("%.4g MN", f / 1e6);
elseif abs(f) >= 1e3
    formatted = sprintf("%.4g kN", f / 1e3);
else
    formatted = sprintf("%.4g N", f);
end
end

function drawSupport(ax, p, type, d, color)
x = p(1); y = p(2);
circle = linspace(0, 2*pi, 28);
r = 0.18 * d;
switch type
    case 1   % pin: triangle with ground hatching
        plot(ax, [x-d x x+d x-d], [y-2*d y y-2*d y-2*d], "-", Color=color, LineWidth=2);
        for k = -2:2
            plot(ax, x + k*0.4*d + [0 -0.36*d], [y-2*d y-2.6*d], "-", Color=color, LineWidth=1.1);
        end
    case 2   % roller restraining X: wall on the left
        plot(ax, [x x], [y-1.4*d y+1.4*d], "-", Color=color, LineWidth=2.5);
        for k = -1:1
            plot(ax, x + 0.85*d + r*cos(circle), y + k*d + r*sin(circle), "-", Color=color, LineWidth=1.1);
            plot(ax, [x+2*r, x+0.85*d-r], [y+k*d, y+k*d], "-", Color=color, LineWidth=1.1);
        end
    case 3   % roller restraining Y: ground below
        plot(ax, [x-1.4*d x+1.4*d], [y y], "-", Color=color, LineWidth=2.5);
        for k = -1:1
            plot(ax, x + k*d + r*cos(circle), y - 0.85*d + r*sin(circle), "-", Color=color, LineWidth=1.1);
            plot(ax, [x+k*d, x+k*d], [y-2*r, y-0.85*d+r], "-", Color=color, LineWidth=1.1);
        end
        for k = -2:2
            plot(ax, x + k*0.4*d + [0 -0.36*d], [y-1.7*d y-2.3*d], "-", Color=color, LineWidth=1.1);
        end
end
end

function drawLoad(ax, p, load, scale, color, t)
delta = load * scale;
quiver(ax, p(1) - delta(1), p(2) - delta(2), delta(1), delta(2), 0, ...
    Color=color, LineWidth=2.8, MaxHeadSize=0.52);
fx = load(1); fy = load(2);
if abs(fx) > 10 * abs(fy)
    label = formatForce(fx);
elseif abs(fy) > 10 * abs(fx)
    label = formatForce(fy);
else
    label = formatForce(fx) + ", " + formatForce(fy);
end
text(ax, p(1) - 1.14 * delta(1), p(2) - 1.14 * delta(2), label, Color=color, FontSize=t.scaled(9), ...
    HorizontalAlignment="center", Interpreter="none");
end
