classdef ParamPanel < handle
    %PARAMPANEL Input panel generated from a plugin's ParamSpec list.
    %   One collapsible section per Group (Advanced groups start
    %   collapsed), one row per parameter: label with units and a field
    %   whose limits come from the spec. Rows hidden by VisibleWhen take
    %   no space. Every field is tagged "dlab.param.<name>".
    %
    %   User edits fire ValueChanged (ParamChangedData). setValues updates
    %   the fields programmatically without firing it.
    %
    %   A "schedule" parameter is a shape dropdown followed by the rows its
    %   shape needs (value, amplitude, start, duration, period, or points),
    %   tagged "dlab.param.<name>.<field>".
    %
    %   A "table" parameter is its label, an editable uitable (tagged
    %   "dlab.param.<name>"), and "+ Row" / "Delete selected" buttons
    %   ("dlab.param.<name>.add" / ".delete"). Rejected edits are undone
    %   and explained through StatusMessage. Its columns share the panel's
    %   width (setWidth) by how wide their headings and values are; when
    %   they cannot all fit, the table scrolls sideways.

    events
        ValueChanged
        StatusMessage    % dlab.core.StatusData (rejected table edits)
    end

    properties (SetAccess = private)
        Grid        % root uigridlayout (scrollable)
        Specs       % ParamSpec column
        Width (1,1) double = 340    % the panel's width in pixels (setWidth)
    end

    properties (Access = private)
        Tokens
        Current struct              % current values
        Fields                      % dictionary name -> {component}
        Labels                      % dictionary name -> {uilabel or []}
        Rows                        % dictionary name -> row index
        Groups struct               % Name, Row, Header, Collapsed, Members
        Schedules                   % dictionary name -> {struct(Rows, Labels, Fields)}
        TableParts                  % dictionary name -> {struct(Rows, Buttons)}
    end

    properties (Constant, Access = private)
        HeaderHeight = 30
        TableVisibleRows = 8        % taller tables scroll
        TableHeaderHeight = 27      % a uitable's column headings (they do not follow FontSize)
        TableScrollbar = 17         % its scroll bars
    end

    methods
        function obj = ParamPanel(parent, specs, values, tokens)
            arguments
                parent
                specs (:,1) dlab.core.ParamSpec
                values (1,1) struct
                tokens (1,1) dlab.ui.Theme
            end
            obj.Specs = specs;
            obj.Tokens = tokens;
            obj.Current = dlab.core.ParamSpec.validateAll(specs, values);
            obj.Fields = dictionary(string.empty, cell.empty);
            obj.Labels = dictionary(string.empty, cell.empty);
            obj.Rows = dictionary(string.empty, double.empty);
            obj.Schedules = dictionary(string.empty, cell.empty);
            obj.TableParts = dictionary(string.empty, cell.empty);
            obj.build(parent);
            obj.refreshLayout();
        end

        function values = values(obj)
            values = obj.Current;
        end

        function setWidth(obj, width)
            %SETWIDTH The panel is WIDTH pixels wide: fit the tables to it.
            obj.Width = width;
            for name = keys(obj.TableParts)'
                obj.fitTable(name);
            end
            obj.refreshLayout();
        end

        function setValues(obj, params)
            %SETVALUES Show PARAMS (validated) without firing ValueChanged.
            params = dlab.core.ParamSpec.validateAll(obj.Specs, params);
            for spec = obj.Specs'
                value = params.(spec.Name);
                field = obj.Fields{spec.Name};
                if spec.Type == "schedule"
                    obj.showSchedule(spec.Name, value);
                elseif spec.Type == "table"
                    field.Data = dlab.core.TableColumn.toCell(value);
                    obj.fitTable(spec.Name);
                else
                    field.Value = value;
                end
            end
            obj.Current = params;
            obj.refreshLayout();
        end

        function setEnabled(obj, enabled)
            state = matlab.lang.OnOffSwitchState(enabled);
            for name = keys(obj.Fields)'
                field = obj.Fields{name};
                field.Enable = char(state);     % uitable (table inputs) rejects OnOffSwitchState
            end
            for name = keys(obj.Schedules)'
                parts = obj.Schedules{name};
                set(parts.Fields, Enable=state);
            end
            for name = keys(obj.TableParts)'
                parts = obj.TableParts{name};
                set(findall(parts.Buttons, Type="uibutton"), Enable=state);
            end
        end

        function setGroupCollapsed(obj, groupName, collapsed)
            k = find([obj.Groups.Name] == groupName, 1);
            assert(~isempty(k), "dlab:panel:unknownGroup", "No group ""%s"".", groupName);
            obj.Groups(k).Collapsed = collapsed;
            obj.refreshLayout();
        end

        function tf = isRowShown(obj, name)
            %ISROWSHOWN Whether parameter NAME currently occupies space.
            tf = obj.Grid.RowHeight{obj.Rows(name)} > 0;
        end

        function tf = isGroupShown(obj, groupName)
            %ISGROUPSHOWN Whether GROUPNAME's header is shown.
            k = find([obj.Groups.Name] == groupName, 1);
            tf = obj.Grid.RowHeight{obj.Groups(k).Row} > 0;
        end

        function refreshLayout(obj)
            %REFRESHLAYOUT Re-apply collapse state and VisibleWhen rules.
            heights = obj.Grid.RowHeight;
            for g = 1:numel(obj.Groups)
                group = obj.Groups(g);
                arrow = "▾ ";
                if group.Collapsed
                    arrow = "▸ ";
                end
                group.Header.Text = arrow + upper(group.Name);
                % A group whose rows are all hidden by VisibleWhen disappears.
                anyVisible = false;
                for name = group.Members
                    anyVisible = anyVisible || dlab.core.ParamSpec.find(obj.Specs, name).isVisible(obj.Current);
                end
                group.Header.Visible = anyVisible;
                if anyVisible
                    heights{group.Row} = obj.HeaderHeight;
                else
                    heights{group.Row} = 0;
                end
                for name = group.Members
                    spec = dlab.core.ParamSpec.find(obj.Specs, name);
                    shown = ~group.Collapsed && spec.isVisible(obj.Current);
                    row = obj.Rows(name);
                    if shown
                        heights{row} = obj.Tokens.ControlHeight;
                    else
                        heights{row} = 0;
                    end
                    field = obj.Fields{name};
                    field.Visible = shown;
                    lbl = obj.Labels{name};
                    if ~isempty(lbl)
                        lbl.Visible = shown;
                    end
                    if spec.Type == "schedule"
                        heights = obj.layoutSchedule(spec, shown, heights);
                    elseif spec.Type == "table"
                        heights = obj.layoutTable(spec, shown, heights);
                    end
                end
            end
            obj.Grid.RowHeight = heights;
        end
    end

    methods (Access = private)
        function build(obj, parent)
            t = obj.Tokens;
            groupNames = dlab.core.ParamSpec.groupsOf(obj.Specs);
            subRows = numel(dlab.core.Schedule.Fields);
            nRows = numel(groupNames) + numel(obj.Specs) + subRows * nnz([obj.Specs.Type] == "schedule") ...
                + 2 * nnz([obj.Specs.Type] == "table");
            obj.Grid = uigridlayout(parent, [nRows 2], ...
                ColumnWidth={"1x", 118}, RowHeight=repmat({obj.Tokens.ControlHeight}, 1, nRows), ...
                RowSpacing=t.Spacing.xs, ColumnSpacing=t.Spacing.sm, ...
                Padding=[t.Spacing.md t.Spacing.sm t.Spacing.md t.Spacing.md], ...
                Scrollable="on", BackgroundColor=t.Surface);

            row = 0;
            obj.Groups = struct("Name", {}, "Row", {}, "Header", {}, "Collapsed", {}, "Members", {});
            for groupName = groupNames
                row = row + 1;
                members = obj.Specs([obj.Specs.Group] == groupName);
                header = uibutton(obj.Grid, "push", Text=groupName, ...
                    HorizontalAlignment="left", FontWeight="bold", FontSize=t.FontSize.sm, ...
                    BackgroundColor=t.Surface, FontColor=t.TextMuted, ...
                    Tag="dlab.group." + groupName, ...
                    ButtonPushedFcn=@(~, ~) obj.toggleGroup(groupName));
                header.Layout.Row = row;
                header.Layout.Column = [1 2];
                obj.Grid.RowHeight{row} = obj.HeaderHeight;
                obj.Groups(end+1) = struct("Name", groupName, "Row", row, "Header", header, ...
                    "Collapsed", any([members.Advanced]), "Members", [members.Name]);
                for spec = members'
                    row = row + 1;
                    obj.Rows(spec.Name) = row;
                    obj.buildRow(spec, row);
                    if spec.Type == "schedule"
                        row = row + subRows;
                    elseif spec.Type == "table"
                        row = row + 2;
                    end
                end
            end
        end

        function buildRow(obj, spec, row)
            t = obj.Tokens;
            value = obj.Current.(spec.Name);
            tag = "dlab.param." + spec.Name;
            tip = spec.tooltip();
            changed = @(src, ~) obj.onFieldChanged(spec.Name, src.Value);

            if spec.Type == "table"
                obj.buildTableRows(spec, row);
                return
            end

            if spec.Type == "logical"
                field = uicheckbox(obj.Grid, Text=spec.displayLabel(), Value=value, ...
                    FontColor=t.Text, FontSize=t.FontSize.md, Tooltip=tip, Tag=tag, ...
                    ValueChangedFcn=changed);
                field.Layout.Row = row;
                field.Layout.Column = [1 2];
                obj.Labels(spec.Name) = {[]};
                obj.Fields(spec.Name) = {field};
                return
            end

            lbl = dlab.ui.label(obj.Grid, spec.displayLabel(), t, Tooltip=tip);
            lbl.Layout.Row = row;
            lbl.Layout.Column = 1;

            if spec.Type == "schedule"
                field = uidropdown(obj.Grid, Items=dlab.core.Schedule.ShapeLabels, ...
                    ItemsData=dlab.core.Schedule.Shapes, Value=value.shape, ...
                    ValueChangedFcn=@(~, ~) obj.onScheduleChanged(spec.Name));
            elseif spec.Type == "choice"
                field = uidropdown(obj.Grid, Items=spec.ChoiceLabels, ItemsData=spec.Choices, ...
                    Value=value, ValueChangedFcn=changed);
            else
                field = uieditfield(obj.Grid, "numeric", Value=value, ...
                    Limits=[spec.Min spec.Max], ...
                    LowerLimitInclusive=spec.MinInclusive, UpperLimitInclusive=spec.MaxInclusive, ...
                    RoundFractionalValues=spec.Type == "integer", ...
                    ValueDisplayFormat=spec.DisplayFormat, HorizontalAlignment="right", ...
                    ValueChangedFcn=changed);
            end
            set(field, BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                FontSize=t.FontSize.md, Tooltip=tip, Tag=tag);
            field.Layout.Row = row;
            field.Layout.Column = 2;
            obj.Labels(spec.Name) = {lbl};
            obj.Fields(spec.Name) = {field};
            if spec.Type == "schedule"
                obj.buildScheduleRows(spec, row);
            end
        end

        % ----------------------------------------------------------- tables
        function buildTableRows(obj, spec, row)
            %BUILDTABLEROWS Label (ROW), uitable (ROW + 1), buttons (ROW + 2).
            t = obj.Tokens;
            tip = spec.tooltip();
            tag = "dlab.param." + spec.Name;
            lbl = dlab.ui.label(obj.Grid, spec.displayLabel(), t, Tooltip=tip);
            lbl.Layout.Row = row;
            lbl.Layout.Column = [1 2];

            columns = spec.Columns;
            formats = cell(1, numel(columns));
            for k = 1:numel(columns)
                switch columns(k).Type
                    case "choice"
                        formats{k} = cellstr(columns(k).Choices);
                    case "logical"
                        formats{k} = 'logical';
                    otherwise
                        formats{k} = 'shortG';      % 3 and 3.25, not 3.0000 and 3.2500
                end
            end
            headers = arrayfun(@(c) c.header(), columns);
            field = uitable(obj.Grid, ColumnName=cellstr(headers), RowName='numbered', ...
                ColumnFormat=formats, ColumnEditable=true(1, numel(columns)), ...
                Data=dlab.core.TableColumn.toCell(obj.Current.(spec.Name)), ...
                SelectionType="row", Multiselect="on", FontSize=t.FontSize.sm + 1, ...
                BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, Tooltip=tip, Tag=tag, ...
                CellEditCallback=@(~, ~) obj.onTableEdited(spec.Name));
            field.Layout.Row = row + 1;
            field.Layout.Column = [1 2];

            buttons = uigridlayout(obj.Grid, [1 3], ColumnWidth={"fit", "fit", "1x"}, ...
                RowHeight={obj.Tokens.ControlHeight - 2}, Padding=0, ColumnSpacing=t.Spacing.xs, ...
                BackgroundColor=t.Surface);
            buttons.Layout.Row = row + 2;
            buttons.Layout.Column = [1 2];
            dlab.ui.button(buttons, "+ Row", t, Tag=tag + ".add", Tooltip="Add a row of default values", ...
                Callback=@(~, ~) obj.addTableRow(spec.Name));
            dlab.ui.button(buttons, "Delete selected", t, Tag=tag + ".delete", ...
                Tooltip="Delete the selected rows", Callback=@(~, ~) obj.deleteTableRows(spec.Name));

            obj.Labels(spec.Name) = {lbl};
            obj.Fields(spec.Name) = {field};
            obj.TableParts(spec.Name) = {struct("Rows", row + [1 2], "Buttons", buttons, "Scrolls", false)};
            obj.fitTable(spec.Name);
        end

        function fitTable(obj, name)
            %FITTABLE Share the panel's width among a table's columns by how
            %   much each needs (its heading or its widest value); if they
            %   need more than there is, give each what it needs and let the
            %   table scroll sideways.
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            field = obj.Fields{name};
            parts = obj.TableParts{name};
            needed = reshape(arrayfun(@columnWidth, spec.Columns), 1, []);
            for k = 1:numel(spec.Columns)
                values = obj.Current.(name){:, k};
                needed(k) = max(needed(k), valuesWidth(spec.Columns(k), values, field.FontSize));
            end
            rows = height(obj.Current.(name));
            numbers = 14 + 7 * numel(num2str(max(rows, 1)));             % the row numbers
            available = obj.Width - sum(obj.Grid.Padding([1 3])) - 16 ...   % the panel's own scroll bar
                - numbers - obj.TableScrollbar * (rows > obj.TableVisibleRows) - 4;
            parts.Scrolls = sum(needed) > available;
            if parts.Scrolls
                field.ColumnWidth = num2cell(needed);
            else
                field.ColumnWidth = cellstr(string(needed) + "x");
            end
            obj.TableParts(name) = {parts};
        end

        function heights = layoutTable(obj, spec, shown, heights)
            %LAYOUTTABLE Size the table to its rows (it scrolls past a few),
            %   at the text size (the rows grow with the font), with room
            %   for the scroll bar a wide table needs.
            parts = obj.TableParts{spec.Name};
            visibleRows = min(max(height(obj.Current.(spec.Name)), 1), obj.TableVisibleRows);
            heights{parts.Rows(1)} = shown * (obj.TableHeaderHeight + ceil(visibleRows * ...
                dlab.ui.tableRowHeight(obj.Fields{spec.Name}.FontSize)) + obj.TableScrollbar * parts.Scrolls + 3);
            heights{parts.Rows(2)} = shown * obj.Tokens.ControlHeight;
            parts.Buttons.Visible = shown;
        end

        function onTableEdited(obj, name)
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            field = obj.Fields{name};
            [value, ok, message] = spec.coerce(field.Data);
            if ~ok
                field.Data = dlab.core.TableColumn.toCell(obj.Current.(name));
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    spec.Label + ": " + message + "; the edit was undone.", "warning"));
                return
            end
            obj.setTable(name, value);
        end

        function addTableRow(obj, name)
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            old = obj.Current.(name);
            if height(old) >= spec.MaxRows
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    sprintf("%s: at most %d rows.", spec.Label, spec.MaxRows), "warning"));
                return
            end
            obj.setTable(name, [old; spec.defaultRow()]);
        end

        function deleteTableRows(obj, name)
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            old = obj.Current.(name);
            rows = unique(obj.Fields{name}.Selection);
            rows = rows(rows >= 1 & rows <= height(old));
            if isempty(rows)
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    "Select rows in the " + spec.Label + " table, then press Delete selected.", "warning"));
                return
            end
            if height(old) - numel(rows) < spec.MinRows
                notify(obj, "StatusMessage", dlab.core.StatusData( ...
                    sprintf("%s: at least %d rows.", spec.Label, spec.MinRows), "warning"));
                return
            end
            value = old;
            value(rows, :) = [];
            obj.setTable(name, value);
        end

        function setTable(obj, name, value)
            old = obj.Current.(name);
            obj.Current.(name) = value;
            obj.Fields{name}.Data = dlab.core.TableColumn.toCell(value);
            obj.fitTable(name);
            obj.refreshLayout();
            if ~isequaln(old, value)
                notify(obj, "ValueChanged", dlab.core.ParamChangedData(name, old, value));
            end
        end

        % -------------------------------------------------------- schedules
        function buildScheduleRows(obj, spec, row)
            t = obj.Tokens;
            names = dlab.core.Schedule.Fields;
            parts = struct("Rows", row + (1:numel(names)), "Labels", gobjects(1, numel(names)), ...
                "Fields", gobjects(1, numel(names)));
            for k = 1:numel(names)
                lbl = dlab.ui.label(obj.Grid, "", t, Role="muted");
                lbl.Layout.Row = row + k;
                lbl.Layout.Column = 1;
                tag = "dlab.param." + spec.Name + "." + names(k);
                callback = @(~, ~) obj.onScheduleChanged(spec.Name);
                if names(k) == "points"
                    field = uieditfield(obj.Grid, "text", Placeholder="t value; t value; …", ...
                        Tooltip="Time (s) and value pairs, separated by semicolons; straight lines between them.", ...
                        ValueChangedFcn=callback);
                else
                    format = "%.6g";
                    if ismember(names(k), ["value" "amplitude"])
                        format = spec.DisplayFormat;    % in the input's own units
                    end
                    field = uieditfield(obj.Grid, "numeric", ValueDisplayFormat=format, ...
                        HorizontalAlignment="right", ValueChangedFcn=callback);
                    switch names(k)
                        case "value"
                            set(field, Limits=[spec.Min spec.Max], LowerLimitInclusive=spec.MinInclusive, ...
                                UpperLimitInclusive=spec.MaxInclusive);
                        case "start"
                            field.Limits = [0 Inf];
                        case {"width" "period"}
                            set(field, Limits=[0 Inf], LowerLimitInclusive=false);
                    end
                end
                set(field, BackgroundColor=t.SurfaceRaised, FontColor=t.Text, FontSize=t.FontSize.md, Tag=tag);
                field.Layout.Row = row + k;
                field.Layout.Column = 2;
                parts.Labels(k) = lbl;
                parts.Fields(k) = field;
            end
            obj.Schedules(spec.Name) = {parts};
            obj.showSchedule(spec.Name, obj.Current.(spec.Name));
        end

        function showSchedule(obj, name, s)
            obj.Fields{name}.Value = s.shape;
            parts = obj.Schedules{name};
            names = dlab.core.Schedule.Fields;
            for k = 1:numel(names) - 1
                parts.Fields(k).Value = s.(names(k));
            end
            parts.Fields(end).Value = dlab.core.Schedule.formatPoints(s.points);
        end

        function onScheduleChanged(obj, name)
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            parts = obj.Schedules{name};
            names = dlab.core.Schedule.Fields;
            old = obj.Current.(name);
            s = old;
            s.shape = string(obj.Fields{name}.Value);
            for k = 1:numel(names) - 1
                s.(names(k)) = parts.Fields(k).Value;
            end
            [points, ok] = dlab.core.Schedule.parsePoints(parts.Fields(end).Value);
            if ok
                s.points = points;
            end
            if s.shape == "points" && isempty(s.points)
                s.points = [0 s.value; s.start s.value + s.amplitude];   % a starting table to edit
            end
            [s, ok] = spec.coerce(s);
            if ~ok
                obj.showSchedule(name, old);
                return
            end
            obj.Current.(name) = s;
            obj.showSchedule(name, s);
            obj.refreshLayout();
            notify(obj, "ValueChanged", dlab.core.ParamChangedData(name, old, s));
        end

        function heights = layoutSchedule(obj, spec, shown, heights)
            %LAYOUTSCHEDULE Show the rows the current shape uses, labelled for it.
            s = obj.Current.(spec.Name);
            parts = obj.Schedules{spec.Name};
            used = scheduleRows(s.shape);
            labels = scheduleLabels(s.shape, spec.Units);
            for k = 1:numel(parts.Rows)
                visible = shown && used(k);
                heights{parts.Rows(k)} = visible * obj.Tokens.ControlHeight;
                set([parts.Labels(k) parts.Fields(k)], Visible=visible);
                parts.Labels(k).Text = "      " + labels(k);
            end
        end

        function onFieldChanged(obj, name, newValue)
            spec = dlab.core.ParamSpec.find(obj.Specs, name);
            [newValue, ok] = spec.coerce(newValue);
            if ~ok
                % The field's own limits normally prevent this; restore.
                field = obj.Fields{name};
                field.Value = obj.Current.(name);
                return
            end
            oldValue = obj.Current.(name);
            obj.Current.(name) = newValue;
            obj.refreshLayout();
            notify(obj, "ValueChanged", dlab.core.ParamChangedData(name, oldValue, newValue));
        end

        function toggleGroup(obj, groupName)
            k = find([obj.Groups.Name] == groupName, 1);
            obj.setGroupCollapsed(groupName, ~obj.Groups(k).Collapsed);
        end
    end
end

function used = scheduleRows(shape)
% Which of value, amplitude, start, width, period, points a shape uses.
switch shape
    case "constant"
        used = [1 0 0 0 0 0];
    case "step"
        used = [1 1 1 0 0 0];
    case {"pulse" "doublet" "ramp"}
        used = [1 1 1 1 0 0];
    case "sine"
        used = [1 1 1 0 1 0];
    otherwise
        used = [0 0 0 0 0 1];
end
used = logical(used);
end

function labels = scheduleLabels(shape, units)
value = "Initial value";
amplitude = "Amplitude";
width = "Lasts";
switch shape
    case "constant"
        value = "Value";
    case "sine"
        value = "Mean";
    case "step"
        amplitude = "Step size";
    case "ramp"
        amplitude = "Change";
        width = "Ramp time";
    case "doublet"
        width = "Each half lasts";
end
labels = [value, amplitude, "Starts at", width, "Period", "Points (t value; …)"];
if units ~= ""
    labels(1:2) = labels(1:2) + " (" + units + ")";
end
labels(3:5) = labels(3:5) + " (s)";
end

function width = columnWidth(column)
% Pixels a table column's heading needs (headings are bold, about 12 px,
% whatever the table's font size).
width = ceil(7.2 * strlength(column.header())) + 14;
end

function width = valuesWidth(column, values, fontSize)
% Pixels a table column's widest value needs at FONTSIZE.
switch column.Type
    case "logical"
        width = 34;
        return
    case "choice"
        texts = string(column.Choices);
        extra = 30;                         % the drop-down arrow
    otherwise
        texts = compose("%.5g", double(values));   % as the shortG format shows them
        extra = 14;
end
if isempty(texts)
    texts = "0";
end
width = ceil(0.62 * fontSize * max(strlength(texts))) + extra;
end
