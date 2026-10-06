classdef TableColumn
    %TABLECOLUMN One column of a "table" parameter (ParamSpec Type="table").
    %
    %       C = @dlab.core.TableColumn;
    %       P("stages", Label="Stages", Type="table", MinRows=1, MaxRows=3, Columns=[
    %           C("dry", Label="Dry mass", Units="t", Min=0, MinInclusive=false, Default=4)
    %           C("isp", Label="Isp", Units="s", Min=1, Default=300)
    %           C("kind", Label="Type", Type="choice", Choices=["solid" "liquid"])
    %       ], Default=...)
    %
    %   A table parameter's value is a MATLAB table with these columns in
    %   this order: double for "double"/"integer" columns, logical for
    %   "logical", and string for "choice". toTable also accepts what
    %   presets, scripts, scenario files, and the table editor produce: a
    %   numeric matrix (no choice columns), a struct array (jsondecode), a
    %   cell array (uitable data), or [] for no rows.

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
    end

    methods
        function obj = TableColumn(name, options)
            arguments
                name (1,1) string {mustBeValidVariableName}
                options.Label (1,1) string = ""
                options.Units (1,1) string = ""
                options.Type (1,1) string {mustBeMember(options.Type, ["double" "integer" "logical" "choice"])} = "double"
                options.Default = []
                options.Min (1,1) double = -Inf
                options.Max (1,1) double = Inf
                options.MinInclusive (1,1) logical = true
                options.MaxInclusive (1,1) logical = true
                options.Choices (1,:) string = string.empty(1, 0)
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
            assert(obj.Type ~= "choice" || ~isempty(obj.Choices), "dlab:spec:noChoices", ...
                "Choice column ""%s"" needs Choices.", name);
            default = options.Default;
            if isempty(default)
                switch obj.Type
                    case "logical"
                        default = false;
                    case "choice"
                        default = obj.Choices(1);
                    otherwise
                        default = min(max(0, obj.Min), obj.Max);
                end
            end
            [value, ok, message] = obj.coerce({default});
            assert(ok, "dlab:spec:badDefault", "Default for column ""%s"": %s", name, message);
            obj.Default = value;
        end

        function text = header(obj)
            %HEADER Column heading with units, e.g. "Dry mass (t)".
            text = obj.Label;
            if obj.Units ~= ""
                text = text + " (" + obj.Units + ")";
            end
        end

        function [values, ok, message] = coerce(obj, cells)
            %COERCE Typed column vector from a cell column; OK is false
            %   with a user-facing MESSAGE naming the first bad row.
            ok = true;
            message = "";
            n = numel(cells);
            switch obj.Type
                case {"double", "integer"}
                    values = zeros(n, 1);
                case "logical"
                    values = false(n, 1);
                otherwise
                    values = strings(n, 1);
            end
            for r = 1:n
                v = cells{r};
                switch obj.Type
                    case {"double", "integer"}
                        good = (isnumeric(v) || islogical(v)) && isscalar(v) && isreal(v) && isfinite(double(v));
                        reason = "must be a number";
                        if good
                            v = double(v);
                            reason = "must be in " + obj.rangeText();
                            good = ~(v < obj.Min || (~obj.MinInclusive && v == obj.Min) ...
                                || v > obj.Max || (~obj.MaxInclusive && v == obj.Max));
                            if good && obj.Type == "integer" && v ~= round(v)
                                [good, reason] = deal(false, "must be a whole number");
                            end
                        end
                    case "logical"
                        good = (islogical(v) || isnumeric(v)) && isscalar(v) && ismember(double(v), [0 1]);
                        reason = "must be true or false";
                        if good
                            v = logical(v);
                        end
                    otherwise
                        good = (ischar(v) || (isstring(v) && isscalar(v))) && ismember(string(v), obj.Choices);
                        reason = "must be one of: " + strjoin(obj.Choices, ", ");
                        if good
                            v = string(v);
                        end
                end
                if ~good
                    ok = false;
                    message = sprintf("%s %s (row %d)", obj.Label, reason, r);
                    return
                end
                values(r) = v;
            end
        end

        function text = rangeText(obj)
            %RANGETEXT Allowed range, e.g. "(0, ∞) t".
            % An infinite bound is never reached: always an open end.
            leftBracket = "[";  if ~obj.MinInclusive || isinf(obj.Min), leftBracket = "("; end
            rightBracket = "]";  if ~obj.MaxInclusive || isinf(obj.Max), rightBracket = ")"; end
            text = leftBracket + bound(obj.Min) + ", " + bound(obj.Max) + rightBracket;
            if obj.Units ~= ""
                text = text + " " + obj.Units;
            end
        end
    end

    methods (Static)
        function [T, ok, message] = toTable(columns, value)
            %TOTABLE The table for VALUE with COLUMNS, or OK false and why.
            names = [columns.Name];
            n = numel(columns);
            ok = true;
            message = "";
            T = [];
            if istable(value)
                have = string(value.Properties.VariableNames);
                missing = setdiff(names, have, "stable");
                if ~isempty(missing)
                    [ok, message] = deal(false, "is missing the column " + missing(1));
                    return
                end
                cells = cell(height(value), n);
                for k = 1:n
                    cells(:, k) = asCells(value.(names(k)));
                end
            elseif isstruct(value)
                missing = setdiff(names, string(fieldnames(value)), "stable");
                if ~isempty(missing)
                    [ok, message] = deal(false, "is missing the column " + missing(1));
                    return
                end
                cells = cell(numel(value), n);
                for k = 1:n
                    cells(:, k) = reshape({value.(names(k))}, [], 1);
                end
            elseif iscell(value) && (isempty(value) || size(value, 2) == n)
                cells = reshape(value, [], n);
            elseif (isnumeric(value) || islogical(value)) && isempty(value)
                cells = cell(0, n);
            elseif (isnumeric(value) || islogical(value)) && ismatrix(value) && size(value, 2) == n
                cells = num2cell(double(value));
            else
                [ok, message] = deal(false, sprintf("must be a table with %d columns (%s)", n, strjoin(names, ", ")));
                return
            end
            data = cell(1, n);
            for k = 1:n
                [data{k}, ok, message] = columns(k).coerce(cells(:, k));
                if ~ok
                    return
                end
            end
            T = table(data{:}, VariableNames=cellstr(names));
        end

        function C = toCell(T)
            %TOCELL Cell data for a uitable (choices as char, for popups).
            C = cell(height(T), width(T));
            for k = 1:width(T)
                values = T.(k);
                if isstring(values)
                    C(:, k) = cellstr(values);
                else
                    C(:, k) = num2cell(values);
                end
            end
        end
    end
end

function cells = asCells(values)
if iscell(values)
    cells = values(:);
elseif ischar(values)
    cells = cellstr(values);
else
    cells = num2cell(values(:));
end
end

function text = bound(value)
if isinf(value) && value < 0
    text = "−∞";
elseif isinf(value)
    text = "∞";
else
    text = string(sprintf("%g", value));
end
end
