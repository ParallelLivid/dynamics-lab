classdef TrussInputs < handle
    %TRUSSINPUTS Model editor for the truss plugin (a custom input panel).
    %   Nodes / Members / Sections / Forces / Supports tables with add and
    %   delete, plus the standard ParamPanel for the scalar settings.
    %   Implements the custom-input contract documented in
    %   dlab.core.Plugin.buildInputs.
    %
    %   Members are [node1 node2 section]; sections are rows of
    %   dlab.physics.sectionLibrary ([material shape E yield D t A I]).
    %   Picking a material fills in E and the yield stress, and picking a
    %   shape computes A and I from D and t; typing E or the yield stress
    %   makes the material custom, and typing A or I the shape.

    events
        ValueChanged     % dlab.core.ParamChangedData (Name = "nodes", "members", ...)
        StatusMessage    % dlab.core.StatusData
    end

    properties (SetAccess = private)
        Grid
        Model struct         % nodes, members, sections, forces, supports
        Panel                % dlab.core.ParamPanel for the scalar specs
        Tables struct = struct()
        Enabled (1,1) logical = true   % false while the view is busy
    end

    properties (Access = private)
        Tokens
        Fields struct = struct()
        PanelListener
    end

    properties (Constant)
        SupportNames = ["Pin (X + Y fixed)" "Roller – X fixed" "Roller – Y fixed"]
        ModelFields = ["nodes" "members" "sections" "forces" "supports"]
    end

    methods
        function obj = TrussInputs(parent, specs, params, tokens)
            t = tokens;
            obj.Tokens = t;
            obj.Model = dlab.sims.truss.TrussInputs.normalize(params);
            obj.Grid = uigridlayout(parent, [3 1], RowHeight={"1x", "fit", 30}, ...
                Padding=[t.Spacing.md t.Spacing.sm t.Spacing.md t.Spacing.sm], ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            obj.Grid.Layout.Row = 1;

            tabs = uitabgroup(obj.Grid, Tag="dlab.truss.tabs");
            obj.buildNodesTab(tabs);
            obj.buildMembersTab(tabs);
            obj.buildSectionsTab(tabs);
            obj.buildForcesTab(tabs);
            obj.buildSupportsTab(tabs);

            obj.Panel = dlab.core.ParamPanel(obj.Grid, specs, params, t);
            obj.Panel.Grid.Scrollable = "off";
            obj.PanelListener = listener(obj.Panel, "ValueChanged", @(~, evt) notify(obj, "ValueChanged", evt));

            dlab.ui.button(obj.Grid, "Clear model", t, Kind="secondary", Tag="dlab.truss.clear", ...
                Tooltip="Remove every node, member, force, and support", ...
                Callback=@(~, ~) obj.guard(@() obj.clearModel()));
            obj.refreshTables();
        end

        function params = values(obj)
            params = obj.Panel.values();
            for field = obj.ModelFields
                params.(field) = obj.Model.(field);
            end
        end

        function setValues(obj, params)
            obj.Panel.setValues(params);
            obj.Model = dlab.sims.truss.TrussInputs.normalize(params);
            obj.refreshTables();
        end

        function setEnabled(obj, enabled)
            obj.Enabled = enabled;
            obj.Panel.setEnabled(enabled);
            state = char(matlab.lang.OnOffSwitchState(enabled));   % uitable wants 'on'/'off'
            set(findall(obj.Grid, Type="uibutton"), Enable=state);
            set(findall(obj.Grid, Type="uitable"), Enable=state);
        end

        % ------------------------------------------------------- edit actions
        function addNode(obj, x, y)
            obj.Model.nodes(end+1, :) = [x y];
            obj.changed("nodes", sprintf("Node %s added at (%.4g, %.4g) m.", ...
                dlab.sims.truss.nodeLabel(size(obj.Model.nodes, 1)), x, y));
        end

        function moveNode(obj, node, x, y)
            %MOVENODE Move NODE to (x, y), e.g. after a drag on the canvas.
            node = round(node);
            if ~obj.isNode(node)
                error("dlab:truss:node", "There is no node %d to move.", node);
            end
            obj.Model.nodes(node, :) = [x y];
            obj.changed("nodes", sprintf("Node %s moved to (%.4g, %.4g) m.", ...
                dlab.sims.truss.nodeLabel(node), x, y));
        end

        function addMember(obj, n1, n2)
            n1 = round(n1); n2 = round(n2);
            if ~obj.isNode(n1) || ~obj.isNode(n2)
                error("dlab:truss:node", "Member endpoints must be existing nodes (1–%d).", size(obj.Model.nodes, 1));
            end
            if n1 == n2
                error("dlab:truss:node", "A member must connect two different nodes.");
            end
            section = 1;
            if ~isempty(obj.Model.members)
                section = obj.Model.members(end, 3);       % like the member before it
            end
            obj.Model.members(end+1, :) = [n1 n2 section];
            obj.changed("members", "Member " + memberName(obj.Model, size(obj.Model.members, 1)) + " added.");
        end

        function addSection(obj)
            %ADDSECTION A copy of the last section, to edit.
            obj.Model.sections(end+1, :) = obj.Model.sections(end, :);
            obj.changed("sections", sprintf("Section S%d added (a copy of S%d): set its material and size.", ...
                size(obj.Model.sections, 1), size(obj.Model.sections, 1) - 1));
        end

        function setMemberSection(obj, members, section)
            %SETMEMBERSECTION Give MEMBERS (row indices) section SECTION.
            if ~(section >= 1 && section <= size(obj.Model.sections, 1) && section == round(section))
                error("dlab:truss:section", "There is no section S%g.", section);
            end
            obj.Model.members(members, 3) = section;
            obj.changed("members", sprintf("%d member(s) now use section S%d.", numel(members), section));
        end

        function editSection(obj, row, column, value)
            %EDITSECTION Apply an edit to the sections table (COLUMN counts
            %   from Material, after the section name).
            lib = dlab.physics.sectionLibrary();
            s = obj.Model.sections(row, :);
            switch column
                case 1                                  % material: fills E and yield
                    k = find(lib.MaterialLabels == string(value), 1);
                    s(1) = k;
                    if lib.MaterialNames(k) ~= "custom"
                        s(3:4) = [lib.E(k) lib.Yield(k)];
                    end
                case {2, 3}                             % E or yield: a custom material
                    if ~(isnumeric(value) && isscalar(value) && value > 0 && isfinite(value))
                        error("dlab:truss:section", "E and the yield stress must be positive.");
                    end
                    s(column + 1) = value;
                    s(1) = find(lib.MaterialNames == "custom");
                case 4                                  % shape: computes A and I
                    s(2) = find(lib.ShapeLabels == string(value), 1);
                    if lib.ShapeNames(s(2)) ~= "custom"
                        if ~(s(5) > 0)
                            s(5:6) = [100 5];           % a starting size, mm
                        end
                        s = withShape(s, lib);
                    end
                case {5, 6}                             % D or t
                    if ~(isnumeric(value) && isscalar(value) && value >= 0 && isfinite(value))
                        error("dlab:truss:section", "Sizes must be zero or positive (mm).");
                    end
                    s(column) = value;
                    if lib.ShapeNames(s(2)) ~= "custom"
                        s = withShape(s, lib);
                    end
                otherwise                               % A or I: a custom shape
                    if ~(isnumeric(value) && isscalar(value) && value > 0 && isfinite(value))
                        error("dlab:truss:section", "A and I must be positive.");
                    end
                    s(column) = value;
                    s(2) = find(lib.ShapeNames == "custom");
            end
            obj.Model.sections(row, :) = s;
            obj.changed("sections", "");
        end

        function addForce(obj, node, fx, fy)
            node = round(node);
            if ~obj.isNode(node)
                error("dlab:truss:node", "Forces must act on an existing node (1–%d).", size(obj.Model.nodes, 1));
            end
            obj.Model.forces(end+1, :) = [node fx fy];
            obj.changed("forces", sprintf("Force added at node %s: Fx = %.4g N, Fy = %.4g N.", ...
                dlab.sims.truss.nodeLabel(node), fx, fy));
        end

        function addSupport(obj, node, type)
            node = round(node);
            if ~obj.isNode(node)
                error("dlab:truss:node", "Supports must be at an existing node (1–%d).", size(obj.Model.nodes, 1));
            end
            obj.Model.supports(obj.Model.supports(:, 1) == node, :) = [];   % one support per node
            obj.Model.supports(end+1, :) = [node type];
            obj.changed("supports", "Support added at node " + dlab.sims.truss.nodeLabel(node) + ...
                " (" + obj.SupportNames(type) + ").");
        end

        function deleteRows(obj, kind, rows)
            if isempty(rows)
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    "Select rows in the table, then press Delete.", "warning"));
                return
            end
            try
                obj.Model = dlab.sims.truss.TrussInputs.removeRows(obj.Model, kind, rows);
            catch ME
                notify(obj, "StatusMessage", dlab.core.StatusData(string(ME.message), "warning"));
                return
            end
            obj.changed(kind, sprintf("Deleted %d row(s).", numel(unique(rows))));
        end

        function clearModel(obj)
            obj.Model = dlab.sims.truss.TrussInputs.normalize(struct());
            obj.changed("nodes", "Model cleared.");
        end

        function editCell(obj, kind, row, column, value)
            %EDITCELL Apply a table edit, rejecting values that would make
            %   the model invalid (the table is then restored).
            if kind == "sections"
                try
                    obj.editSection(row, column, value);
                catch ME
                    obj.refreshTables();
                    notify(obj, "StatusMessage", dlab.core.StatusData(string(ME.message) + ...
                        " The section is unchanged.", "warning"));
                end
                return
            end
            ok = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
            if ok && kind == "members" && column == 3
                value = round(value);
                ok = value >= 1 && value <= size(obj.Model.sections, 1);
            elseif ok && kind == "members"
                value = round(value);
                other = obj.Model.members(row, 3 - column);
                ok = obj.isNode(value) && value ~= other;
            end
            if ~ok
                obj.refreshTables();
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    "That value was rejected; the model is unchanged.", "warning"));
                return
            end
            switch kind
                case "nodes",   obj.Model.nodes(row, column) = value;
                case "members", obj.Model.members(row, column) = value;
                case "forces",  obj.Model.forces(row, column + 1) = value;
            end
            obj.changed(kind, "");
        end
    end

    methods (Static)
        function model = normalize(params)
            %NORMALIZE Model arrays with fixed column counts, also for
            %   empty or single-row data (as jsondecode returns them).
            columns = struct("nodes", 2, "members", 3, "sections", 8, "forces", 3, "supports", 2);
            model = struct();
            for field = dlab.sims.truss.TrussInputs.ModelFields
                value = [];
                if isfield(params, field)
                    value = double(params.(field));
                end
                if isempty(value)
                    value = zeros(0, columns.(field));
                elseif isvector(value) && any(numel(value) == [columns.(field), 2 * (field == "members")])
                    value = reshape(value, 1, []);
                end
                model.(field) = value;
            end
            % Members without a section (older models) use section 1.
            if size(model.members, 2) == 2
                model.members(:, 3) = 1;
            end
            if isempty(model.sections)
                model.sections = dlab.physics.sectionLibrary().Default;
            end
        end

        function model = removeRows(model, kind, rows)
            %REMOVEROWS Delete table rows; deleting nodes also removes the
            %   members, forces, and supports that use them and renumbers
            %   the rest. A section still used by a member, or the last
            %   one, cannot be deleted.
            rows = sort(unique(rows), "descend");
            if kind == "sections"
                used = intersect(rows, model.members(:, 3));
                if ~isempty(used)
                    error("dlab:truss:section", "Section S%d is used by members: give them another section first.", used(1));
                end
                if numel(rows) >= size(model.sections, 1)
                    error("dlab:truss:section", "Keep at least one section.");
                end
            end
            for r = rows(:)'
                switch kind
                    case "nodes"
                        model.nodes(r, :) = [];
                        ends = model.members(:, 1:2);
                        model.members(any(ends == r, 2), :) = [];
                        ends = model.members(:, 1:2);
                        ends(ends > r) = ends(ends > r) - 1;
                        model.members(:, 1:2) = ends;
                        for field = ["forces" "supports"]
                            m = model.(field);
                            m(m(:, 1) == r, :) = [];
                            m(m(:, 1) > r, 1) = m(m(:, 1) > r, 1) - 1;
                            model.(field) = m;
                        end
                    case "sections"
                        model.sections(r, :) = [];
                        model.members(model.members(:, 3) > r, 3) = model.members(model.members(:, 3) > r, 3) - 1;
                    otherwise
                        model.(kind)(r, :) = [];
                end
            end
        end
    end

    methods (Access = private)
        function buildNodesTab(obj, tabs)
            [grid, add] = obj.newTab(tabs, "Nodes", 2);
            obj.Fields.nodeX = obj.numberField(add, "nodeX", "X (m)", 0, 1);
            obj.Fields.nodeY = obj.numberField(add, "nodeY", "Y (m)", 0, 3);
            obj.addButton(add, 5, "Add node", @() obj.addNode(obj.Fields.nodeX.Value, obj.Fields.nodeY.Value));
            obj.Tables.nodes = obj.newTable(grid, "nodes", ["Node" "X (m)" "Y (m)"], [false true true]);
            obj.deleteButton(grid, "nodes");
        end

        function buildMembersTab(obj, tabs)
            [grid, add] = obj.newTab(tabs, "Members", 2);
            obj.Fields.member1 = obj.numberField(add, "member1", "From", 1, 1, [1 Inf]);
            obj.Fields.member2 = obj.numberField(add, "member2", "To", 2, 3, [1 Inf]);
            obj.addButton(add, 5, "Add member", @() obj.addMember(obj.Fields.member1.Value, obj.Fields.member2.Value));
            obj.Tables.members = obj.newTable(grid, "members", ["Member" "Node 1" "Node 2" "Section"], ...
                [false true true true]);
            obj.Tables.members.Tooltip = "Section: a row of the Sections tab (S1, S2, …).";
            obj.deleteButton(grid, "members");
        end

        function buildSectionsTab(obj, tabs)
            t = obj.Tokens;
            lib = dlab.physics.sectionLibrary();
            [grid, add] = obj.newTab(tabs, "Sections", 1);
            note = dlab.ui.label(add, "Material and shape for each member (Members › Section).", t, Role="muted");
            note.Layout.Column = [1 4];
            obj.addButton(add, 5, "Add section", @() obj.addSection());
            columns = ["Section" "Material" "E (GPa)" "Yield (MPa)" "Shape" "D (mm)" "t (mm)" "A (cm²)" "I (cm⁴)"];
            formats = [{[]}, {cellstr(lib.MaterialLabels)}, {'shortG'}, {'shortG'}, {cellstr(lib.ShapeLabels)}, ...
                repmat({'shortG'}, 1, 4)];
            obj.Tables.sections = uitable(grid, ColumnName=cellstr(columns), ColumnEditable=[false true(1, 8)], ...
                RowName={}, ColumnFormat=formats, SelectionType="row", Multiselect="on", FontSize=t.FontSize.md, ...
                BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, Tag="dlab.truss.table.sections", ...
                Tooltip="Picking a material fills in E and the yield stress; picking a shape computes A and I " + ...
                "from D (outer size) and t (wall). Typing E, yield, A, or I makes them custom. I is about the " + ...
                "weakest axis: the one the member buckles about.", ...
                CellEditCallback=@(~, evt) obj.guard(@() obj.editCell("sections", ...
                    evt.Indices(1), evt.Indices(2) - 1, evt.NewData)));
            obj.deleteButton(grid, "sections");
        end

        function buildForcesTab(obj, tabs)
            [grid, add] = obj.newTab(tabs, "Forces", 2);
            obj.Fields.forceNode = obj.numberField(add, "forceNode", "Node", 1, 1, [1 Inf]);
            obj.Fields.forceX = obj.numberField(add, "forceX", "Fx (N)", 0, 3);
            obj.Fields.forceY = obj.numberField(add, "forceY", "Fy (N)", -10000, 1, [-Inf Inf], 2);
            obj.addButton(add, [3 5], "Add force", @() obj.addForce(obj.Fields.forceNode.Value, ...
                obj.Fields.forceX.Value, obj.Fields.forceY.Value), 2);
            obj.Tables.forces = obj.newTable(grid, "forces", ["Node" "Fx (N)" "Fy (N)"], [false true true]);
            obj.deleteButton(grid, "forces");
        end

        function buildSupportsTab(obj, tabs)
            [grid, add] = obj.newTab(tabs, "Supports", 2);
            obj.Fields.supportNode = obj.numberField(add, "supportNode", "Node", 1, 1, [1 Inf]);
            lbl = dlab.ui.label(add, "Type", obj.Tokens, Role="muted");
            lbl.Layout.Row = 1; lbl.Layout.Column = 3;
            obj.Fields.supportType = uidropdown(add, Items=obj.SupportNames, ItemsData=1:3, Value=1, ...
                BackgroundColor=obj.Tokens.SurfaceRaised, FontColor=obj.Tokens.Text, ...
                Tag="dlab.truss.supportType");
            obj.Fields.supportType.Layout.Row = 1;
            obj.Fields.supportType.Layout.Column = [4 5];
            obj.addButton(add, [1 5], "Add support", @() obj.addSupport(obj.Fields.supportNode.Value, ...
                obj.Fields.supportType.Value), 2);
            obj.Tables.supports = obj.newTable(grid, "supports", ["Node" "Type"], [false false]);
            obj.deleteButton(grid, "supports");
        end

        function [grid, add] = newTab(obj, tabs, title, addRows)
            t = obj.Tokens;
            tab = uitab(tabs, Title=title, BackgroundColor=t.Surface, ForegroundColor=t.Text, ...
                Tag="dlab.truss.tab." + lower(title));
            grid = uigridlayout(tab, [3 1], RowHeight={"fit", "1x", 28}, ...
                Padding=[t.Spacing.sm t.Spacing.sm t.Spacing.sm t.Spacing.sm], ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            add = uigridlayout(grid, [addRows 5], ColumnWidth={"fit", "1x", "fit", "1x", "fit"}, ...
                RowHeight=repmat({t.ControlHeight}, 1, addRows), Padding=0, ...
                ColumnSpacing=t.Spacing.xs, RowSpacing=t.Spacing.xs, BackgroundColor=t.Surface);
        end

        function field = numberField(obj, parent, name, label, value, column, limits, row)
            arguments
                obj
                parent
                name (1,1) string
                label (1,1) string
                value (1,1) double
                column (1,1) double
                limits (1,2) double = [-Inf Inf]
                row (1,1) double = 1
            end
            lbl = dlab.ui.label(parent, label, obj.Tokens, Role="muted");
            lbl.Layout.Row = row; lbl.Layout.Column = column;
            field = uieditfield(parent, "numeric", Value=value, Limits=limits, ValueDisplayFormat="%.6g", ...
                BackgroundColor=obj.Tokens.SurfaceRaised, FontColor=obj.Tokens.Text, ...
                Tag="dlab.truss." + name);
            field.Layout.Row = row; field.Layout.Column = column + 1;
        end

        function addButton(obj, parent, column, text, action, row)
            arguments
                obj
                parent
                column
                text (1,1) string
                action function_handle
                row (1,1) double = 1
            end
            b = dlab.ui.button(parent, "+ " + extractBefore(text, " ") , obj.Tokens, Kind="primary", ...
                Tag="dlab.truss." + lower(strrep(text, " ", "")), Tooltip=text, ...
                Callback=@(~, ~) obj.guard(action));
            b.Layout.Row = row;
            b.Layout.Column = column;
        end

        function tbl = newTable(obj, parent, kind, columns, editable)
            t = obj.Tokens;
            formats = repmat({'shortG'}, 1, numel(columns));
            formats(~editable) = {[]};       % label columns keep their text
            tbl = uitable(parent, ColumnName=cellstr(columns), ColumnEditable=editable, RowName={}, ...
                ColumnFormat=formats, ...
                SelectionType="row", Multiselect="on", FontSize=t.FontSize.md, ...
                BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, ...
                Tag="dlab.truss.table." + kind, ...
                CellEditCallback=@(~, evt) obj.guard(@() obj.editCell(kind, ...
                    evt.Indices(1), evt.Indices(2) - 1, evt.NewData)));
        end

        function deleteButton(obj, parent, kind)
            dlab.ui.button(parent, "Delete selected", obj.Tokens, Kind="secondary", ...
                Tag="dlab.truss.delete." + kind, ...
                Callback=@(~, ~) obj.guard(@() obj.deleteRows(kind, obj.Tables.(kind).Selection)));
        end

        function refreshTables(obj)
            % Cell data (not table) so the explicit column headers stay.
            m = obj.Model;
            names = strings(size(m.nodes, 1), 1);
            for k = 1:numel(names)
                names(k) = dlab.sims.truss.nodeLabel(k);
            end
            obj.Tables.nodes.Data = [cellstr(names), num2cell(m.nodes)];
            memberNames = strings(size(m.members, 1), 1);
            for k = 1:numel(memberNames)
                memberNames(k) = memberName(m, k);
            end
            obj.Tables.members.Data = [cellstr(memberNames), num2cell(m.members)];
            lib = dlab.physics.sectionLibrary();
            sections = m.sections;
            obj.Tables.sections.Data = [cellstr("S" + (1:size(sections, 1))'), ...
                cellstr(reshape(lib.MaterialLabels(sections(:, 1)), [], 1)), num2cell(sections(:, 3:4)), ...
                cellstr(reshape(lib.ShapeLabels(sections(:, 2)), [], 1)), num2cell(sections(:, 5:8))];
            obj.Tables.forces.Data = num2cell(m.forces);
            obj.Tables.supports.Data = [num2cell(m.supports(:, 1)), ...
                cellstr(reshape(obj.SupportNames(m.supports(:, 2)), [], 1))];
        end

        function changed(obj, kind, message)
            obj.refreshTables();
            notify(obj, "ValueChanged", dlab.core.ParamChangedData(kind, [], obj.Model.(kind)));
            if message ~= ""
                notify(obj, "StatusMessage", dlab.core.StatusData(message));
            end
        end

        function tf = isNode(obj, index)
            tf = index >= 1 && index <= size(obj.Model.nodes, 1) && index == round(index);
        end

        function guard(obj, action)
            %GUARD Turn editor errors into status-bar messages.
            try
                action();
            catch ME
                notify(obj, "StatusMessage", dlab.core.StatusData(string(ME.message), "error"));
            end
        end
    end
end

function s = withShape(s, lib)
% A and I from the shape and its sizes; invalid sizes are rejected.
[A, I] = lib.properties(s(2), s(5), s(6));
if ~(A > 0 && I > 0)
    error("dlab:truss:section", "That size does not make a %s (the wall must be less than half the size).", ...
        lower(lib.ShapeLabels(s(2))));
end
s(7:8) = [A I];
end

function name = memberName(model, k)
name = dlab.sims.truss.nodeLabel(model.members(k, 1)) + "-" + dlab.sims.truss.nodeLabel(model.members(k, 2));
end
