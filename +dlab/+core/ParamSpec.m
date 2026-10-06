classdef ParamSpec
    %PARAMSPEC Schema for one simulator parameter.
    %   A plugin's parameters() returns a column of these. The shell builds
    %   the input panel, tooltips, range checks, preset handling, and
    %   scenario loading from them.
    %
    %       P = @dlab.core.ParamSpec;
    %       specs = [
    %           P("L", Label="Length", Units="m", Default=1, Min=0, ...
    %               MinInclusive=false, Group="Physical", ...
    %               Description="Distance from pivot to bob centre.")
    %           P("model", Label="Model", Type="choice", Default="point", ...
    %               Choices=["point" "drag"], ChoiceLabels=["Point mass" "With drag"])
    %           P("Cd", Label="Drag coefficient", Default=0.47, Min=0, ...
    %               VisibleWhen=@(p) p.model == "drag")
    %           P("labels", Label="Show labels", Type="logical", Display=true)
    %           P("elevator", Label="Elevator", Type="schedule", Default=0, Min=-1, Max=1)
    %       ];
    %
    %   Type "schedule" is an input that can change during the run (step,
    %   pulse, doublet, ramp, sine, or custom points); its value is a
    %   dlab.core.Schedule struct, and a plain number means a constant.
    %
    %   Type "table" is a list of rows (rocket stages, frame members): its
    %   value is a MATLAB table whose Columns are dlab.core.TableColumn
    %   definitions, with MinRows and MaxRows limits. Tables are edited
    %   in place, saved in scenarios, and never swept.
    %
    %   Display=true marks a presentation-only setting: changing it redraws
    %   the current result instead of making it stale (and never switches
    %   the preset to "Custom").

    properties (SetAccess = immutable)
        Name (1,1) string
        Label (1,1) string
        Units (1,1) string
        Type (1,1) string
        Default
        Min (1,1) double
        Max (1,1) double
        MinInclusive (1,1) logical
        MaxInclusive (1,1) logical
        Choices (1,:) string
        ChoiceLabels (1,:) string
        Description (1,1) string
        Group (1,1) string
        Advanced (1,1) logical      % group starts collapsed
        VisibleWhen                 % function_handle: @(params) logical
        MarksCustom (1,1) logical   % editing switches the preset to "Custom"
        Display (1,1) logical       % presentation only: redraws, never makes results stale
        DisplayFormat (1,1) string  % numeric field ValueDisplayFormat
        Columns                     % dlab.core.TableColumn column (Type "table")
        MinRows (1,1) double        % Type "table": fewest rows allowed
        MaxRows (1,1) double        % Type "table": most rows allowed
    end

    properties (Constant)
        Types = ["double" "integer" "logical" "choice" "schedule" "table"]
    end

    methods
        function obj = ParamSpec(name, options)
            arguments
                name (1,1) string {mustBeValidVariableName}
                options.Label (1,1) string = ""
                options.Units (1,1) string = ""
                options.Type (1,1) string {mustBeMember(options.Type, ["double" "integer" "logical" "choice" "schedule" "table"])} = "double"
                options.Default = []
                options.Min (1,1) double = -Inf
                options.Max (1,1) double = Inf
                options.MinInclusive (1,1) logical = true
                options.MaxInclusive (1,1) logical = true
                options.Choices (1,:) string = string.empty(1, 0)
                options.ChoiceLabels (1,:) string = string.empty(1, 0)
                options.Description (1,1) string = ""
                options.Group (1,1) string = "Parameters"
                options.Advanced (1,1) logical = false
                options.VisibleWhen (1,1) function_handle = @(~) true
                options.MarksCustom (1,1) logical = true
                options.Display (1,1) logical = false
                options.DisplayFormat (1,1) string = "%.6g"
                options.Columns (:,1) dlab.core.TableColumn = dlab.core.TableColumn.empty(0, 1)
                options.MinRows (1,1) double {mustBeNonnegative, mustBeInteger} = 0
                options.MaxRows (1,1) double {mustBeNonnegative} = Inf
            end
            obj.Name = name;
            obj.Label = options.Label;
            if obj.Label == ""
                obj.Label = name;
            end
            obj.Units = options.Units;
            obj.Type = options.Type;
            obj.Min = options.Min;
            obj.Max = options.Max;
            obj.MinInclusive = options.MinInclusive;
            obj.MaxInclusive = options.MaxInclusive;
            obj.Choices = options.Choices;
            obj.ChoiceLabels = options.ChoiceLabels;
            if isempty(obj.ChoiceLabels)
                obj.ChoiceLabels = obj.Choices;
            end
            obj.Description = options.Description;
            obj.Group = options.Group;
            obj.Advanced = options.Advanced;
            obj.VisibleWhen = options.VisibleWhen;
            obj.Display = options.Display;
            obj.MarksCustom = options.MarksCustom && ~options.Display;
            obj.DisplayFormat = options.DisplayFormat;
            obj.Columns = options.Columns;
            obj.MinRows = options.MinRows;
            obj.MaxRows = options.MaxRows;
            if obj.Type == "table"
                assert(~isempty(obj.Columns), "dlab:spec:noColumns", ...
                    "Table parameter ""%s"" needs Columns.", name);
                assert(obj.MinRows <= obj.MaxRows, "dlab:spec:range", ...
                    "MinRows exceeds MaxRows for parameter ""%s"".", name);
            end

            if obj.Type == "choice"
                assert(~isempty(obj.Choices), "dlab:spec:noChoices", ...
                    "Choice parameter ""%s"" needs Choices.", name);
                assert(numel(obj.ChoiceLabels) == numel(obj.Choices), "dlab:spec:choiceLabels", ...
                    "ChoiceLabels for ""%s"" must match Choices in length.", name);
            end
            assert(obj.Min <= obj.Max, "dlab:spec:range", ...
                "Min exceeds Max for parameter ""%s"".", name);

            obj.Default = options.Default;
            if isempty(obj.Default)
                obj.Default = obj.fallbackDefault();
            end
            [obj.Default, ok, message] = obj.coerce(obj.Default);
            assert(ok, "dlab:spec:badDefault", "Default for ""%s"": %s", name, message);
        end

        function text = displayLabel(obj)
            %DISPLAYLABEL Label with units, e.g. "Length (m)".
            text = obj.Label;
            if obj.Units ~= ""
                text = text + " (" + obj.Units + ")";
            end
        end

        function text = tooltip(obj)
            %TOOLTIP Description plus the allowed range.
            parts = strings(0);
            if obj.Description ~= ""
                parts(end+1) = obj.Description;
            end
            range = obj.rangeText();
            if range ~= ""
                parts(end+1) = "Allowed: " + range;
            end
            if obj.Type == "schedule"
                parts(end+1) = "Choose how it changes during the run; values outside the range are clipped.";
            end
            if obj.Type == "table"
                parts(end+1) = obj.rowsText();
            end
            text = strjoin(parts, newline);
        end

        function text = rangeText(obj)
            %RANGETEXT Human-readable allowed range, "" when unbounded.
            text = "";
            if ~ismember(obj.Type, ["double" "integer" "schedule"]) || (isinf(obj.Min) && isinf(obj.Max))
                return
            end
            % An infinite bound is never reached: always an open end.
            lowerBracket = "[";  if ~obj.MinInclusive || isinf(obj.Min), lowerBracket = "("; end
            upperBracket = "]";  if ~obj.MaxInclusive || isinf(obj.Max), upperBracket = ")"; end
            text = lowerBracket + formatBound(obj.Min) + ", " + formatBound(obj.Max) + upperBracket;
            if obj.Units ~= ""
                text = text + " " + obj.Units;
            end
        end

        function text = rowsText(obj)
            %ROWSTEXT Allowed number of rows of a table, e.g. "1 to 3 rows".
            if isinf(obj.MaxRows)
                text = sprintf("At least %d row(s)", obj.MinRows);
            elseif obj.MinRows == obj.MaxRows
                text = sprintf("Exactly %d row(s)", obj.MinRows);
            else
                text = sprintf("%d to %d rows", obj.MinRows, obj.MaxRows);
            end
        end

        function row = defaultRow(obj)
            %DEFAULTROW A one-row table of the column defaults (Type "table").
            row = dlab.core.TableColumn.toTable(obj.Columns, {obj.Columns.Default});
        end

        function [value, ok, message] = coerce(obj, value)
            %COERCE Convert VALUE to this parameter's type and check it.
            %   Accepts what jsondecode produces (char for strings, double
            %   for numbers, logical for booleans). OK is false with a
            %   user-facing MESSAGE when the value cannot be accepted.
            ok = true;
            message = "";
            switch obj.Type
                case {"double", "integer"}
                    if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ~isreal(value)
                        [ok, message] = deal(false, "must be a real number");
                        return
                    end
                    value = double(value);
                    if ~isfinite(value)
                        [ok, message] = deal(false, "must be finite");
                    elseif obj.Type == "integer" && value ~= round(value)
                        [ok, message] = deal(false, "must be a whole number");
                    elseif value < obj.Min || (~obj.MinInclusive && value == obj.Min) ...
                            || value > obj.Max || (~obj.MaxInclusive && value == obj.Max)
                        [ok, message] = deal(false, "must be in " + obj.rangeText());
                    end
                case "logical"
                    if (islogical(value) || isnumeric(value)) && isscalar(value) && ismember(double(value), [0 1])
                        value = logical(value);
                    else
                        [ok, message] = deal(false, "must be true or false");
                    end
                case "choice"
                    if (ischar(value) || (isstring(value) && isscalar(value))) && ismember(string(value), obj.Choices)
                        value = string(value);
                    else
                        [ok, message] = deal(false, "must be one of: " + strjoin(obj.Choices, ", "));
                    end
                case "table"
                    [rows, ok, message] = dlab.core.TableColumn.toTable(obj.Columns, value);
                    if ok && (height(rows) < obj.MinRows || height(rows) > obj.MaxRows)
                        [ok, message] = deal(false, "needs " + lower(obj.rowsText()));
                    end
                    if ok
                        value = rows;
                    end
                case "schedule"
                    [value, ok, message] = dlab.core.Schedule.normalize(value);
                    if ok && (value.value < obj.Min || (~obj.MinInclusive && value.value == obj.Min) ...
                            || value.value > obj.Max || (~obj.MaxInclusive && value.value == obj.Max))
                        [ok, message] = deal(false, "starting value must be in " + obj.rangeText());
                    end
            end
        end

        function tf = isVisible(obj, params)
            %ISVISIBLE Evaluate VisibleWhen against the current params.
            tf = logical(obj.VisibleWhen(params));
        end
    end

    methods (Static)
        function params = defaults(specs)
            %DEFAULTS Struct of default values, one field per spec.
            params = struct();
            for spec = specs(:)'
                params.(spec.Name) = spec.Default;
            end
        end

        function params = validateAll(specs, params)
            %VALIDATEALL Coerce every field; throw dlab:invalidParameter
            %   listing every problem at once.
            problems = strings(0);
            for spec = specs(:)'
                if ~isfield(params, spec.Name)
                    problems(end+1) = spec.Label + " is missing"; %#ok<AGROW>
                    continue
                end
                [value, ok, message] = spec.coerce(params.(spec.Name));
                if ok
                    params.(spec.Name) = value;
                else
                    problems(end+1) = spec.Label + " " + message; %#ok<AGROW>
                end
            end
            if ~isempty(problems)
                error("dlab:invalidParameter", "%s.", strjoin(problems, "; "));
            end
        end

        function spec = find(specs, name)
            %FIND The spec named NAME, or error.
            match = specs([specs.Name] == name);
            assert(isscalar(match), "dlab:spec:unknown", "No parameter named ""%s"".", name);
            spec = match;
        end

        function groups = groupsOf(specs)
            %GROUPSOF Group names in first-appearance order.
            groups = unique([specs.Group], "stable");
        end
    end

    methods (Access = private)
        function value = fallbackDefault(obj)
            switch obj.Type
                case "logical"
                    value = false;
                case "choice"
                    value = obj.Choices(1);
                case "schedule"
                    value = dlab.core.Schedule.make("constant", Value=min(max(0, obj.Min), obj.Max));
                case "table"
                    value = repmat(obj.defaultRow(), obj.MinRows, 1);
                otherwise
                    value = min(max(0, obj.Min), obj.Max);
            end
        end
    end
end

function text = formatBound(value)
if isinf(value) && value < 0
    text = "−∞";
elseif isinf(value)
    text = "∞";
else
    text = string(sprintf("%g", value));
end
end
