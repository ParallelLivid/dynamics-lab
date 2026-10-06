classdef Schedule
    %SCHEDULE Time-varying inputs: the value of a ParamSpec of Type
    %   "schedule". A schedule is a struct with fields
    %
    %     shape      "constant" | "step" | "pulse" | "doublet" | "ramp" | "sine" | "points"
    %     value      level before the change (the constant value; a sine's mean)
    %     amplitude  size of the change
    %     start      time the change begins (s)
    %     width      pulse length, each half of a doublet, or ramp time (s)
    %     period     sine period (s)
    %     points     N×2 [t value] table, linearly interpolated (shape "points")
    %
    %   Plugins hand engines a plain function of time:
    %
    %       u = dlab.core.Schedule.toFunction(params.elevator, [-1 1]);
    %       u(2.5)          % the input at t = 2.5 s, clipped to [-1, 1]
    %
    %   A plain number is accepted wherever a schedule is, as a constant,
    %   so older scenario files and presets keep working.

    properties (Constant)
        Shapes = ["constant" "step" "pulse" "doublet" "ramp" "sine" "points"]
        ShapeLabels = ["Constant" "Step" "Pulse" "Doublet" "Ramp" "Sine wave" "Custom points"]
        Fields = ["value" "amplitude" "start" "width" "period" "points"]
    end

    methods (Static)
        function s = make(shape, options)
            %MAKE A schedule; unspecified fields take neutral defaults.
            %   s = dlab.core.Schedule.make("step", Value=0, Amplitude=2, Start=1)
            arguments
                shape (1,1) string {mustBeMember(shape, ["constant" "step" "pulse" "doublet" "ramp" "sine" "points"])}
                options.Value (1,1) double = 0
                options.Amplitude (1,1) double = 0
                options.Start (1,1) double = 1
                options.Width (1,1) double = 1
                options.Period (1,1) double = 2
                options.Points (:,2) double = zeros(0, 2)
            end
            s = struct("shape", shape, "value", options.Value, "amplitude", options.Amplitude, ...
                "start", options.Start, "width", options.Width, "period", options.Period, ...
                "points", options.Points);
        end

        function [s, ok, message] = normalize(value)
            %NORMALIZE A complete schedule from a number, a schedule, or
            %   what jsondecode returns for one. OK is false (with a
            %   MESSAGE) when VALUE cannot be read as a schedule.
            ok = true;
            message = "";
            if (isnumeric(value) || islogical(value)) && isscalar(value) && isreal(value)
                s = dlab.core.Schedule.make("constant", Value=double(value));
            elseif isstruct(value) && isscalar(value) && isfield(value, "shape")
                s = dlab.core.Schedule.make("constant");
                shape = string(value.shape);
                if ~isscalar(shape) || ~ismember(shape, dlab.core.Schedule.Shapes)
                    [ok, message] = deal(false, "has an unknown shape");
                    return
                end
                s.shape = shape;
                for name = ["value" "amplitude" "start" "width" "period"]
                    if isfield(value, name)
                        number = value.(name);
                        if ~(isnumeric(number) && isscalar(number) && isreal(number) && isfinite(number))
                            [ok, message] = deal(false, "has an invalid " + name);
                            return
                        end
                        s.(name) = double(number);
                    end
                end
                if isfield(value, "points") && ~isempty(value.points)
                    points = double(value.points);
                    if isvector(points) && numel(points) == 2
                        points = reshape(points, 1, 2);       % jsondecode gives one row as a vector
                    end
                    if size(points, 2) ~= 2 || ~all(isfinite(points), "all")
                        [ok, message] = deal(false, "points must be finite [time value] pairs");
                        return
                    end
                    s.points = points;
                end
            else
                [ok, message] = deal(false, "must be a number or a schedule");
                s = dlab.core.Schedule.make("constant");
            end
            if ok
                [ok, message] = check(s);
            end
        end

        function v = evaluate(s, t)
            %EVALUATE The schedule's value at times T (any size).
            v = s.value + zeros(size(t));
            after = t >= s.start;
            switch s.shape
                case "step"
                    v(after) = s.value + s.amplitude;
                case "pulse"
                    v(after & t < s.start + s.width) = s.value + s.amplitude;
                case "doublet"
                    v(after & t < s.start + s.width) = s.value + s.amplitude;
                    v(t >= s.start + s.width & t < s.start + 2 * s.width) = s.value - s.amplitude;
                case "ramp"
                    fraction = min(max((t - s.start) / s.width, 0), 1);
                    v = s.value + s.amplitude * fraction;
                case "sine"
                    v(after) = s.value + s.amplitude * sin(2 * pi * (t(after) - s.start) / s.period);
                case "points"
                    if isempty(s.points)
                        return
                    end
                    [times, order] = sort(s.points(:, 1));
                    values = s.points(order, 2);
                    if numel(times) == 1
                        v(:) = values;
                    else
                        v = interp1(times, values, min(max(t, times(1)), times(end)), "linear");
                    end
            end
        end

        function fcn = toFunction(s, limits)
            %TOFUNCTION @(t) value, clipped to LIMITS ([min max]), for engines.
            %   Vectorized for every shape: u(t) has the size of t.
            arguments
                s
                limits (1,2) double = [-Inf Inf]
            end
            s = dlab.core.Schedule.normalize(s);
            if s.shape == "constant"
                constant = min(max(s.value, limits(1)), limits(2));
                fcn = @(t) constant + zeros(size(t));
            else
                fcn = @(t) min(max(dlab.core.Schedule.evaluate(s, t), limits(1)), limits(2));
            end
        end

        function text = describe(s, units)
            %DESCRIBE One line, e.g. "step from 0 to 0.3 at 2 s".
            arguments
                s
                units (1,1) string = ""
            end
            s = dlab.core.Schedule.normalize(s);
            u = "";
            if units ~= ""
                u = " " + units;
            end
            g = @(x) string(sprintf("%.4g", x));
            switch s.shape
                case "constant"
                    text = "constant " + g(s.value) + u;
                case "step"
                    text = "step from " + g(s.value) + " to " + g(s.value + s.amplitude) + u + " at " + g(s.start) + " s";
                case "pulse"
                    text = "pulse of " + g(s.amplitude) + u + " from " + g(s.start) + " s for " + g(s.width) + " s";
                case "doublet"
                    text = "doublet ±" + g(s.amplitude) + u + " from " + g(s.start) + " s, " + g(s.width) + " s each way";
                case "ramp"
                    text = "ramp from " + g(s.value) + " to " + g(s.value + s.amplitude) + u + " over " + ...
                        g(s.width) + " s from " + g(s.start) + " s";
                case "sine"
                    text = "sine " + g(s.value) + " ± " + g(s.amplitude) + u + ", period " + g(s.period) + ...
                        " s, from " + g(s.start) + " s";
                otherwise
                    text = sprintf("%d points", size(s.points, 1));
            end
        end

        function [points, ok] = parsePoints(text)
            %PARSEPOINTS "0 0; 2 1; 4 0" (time value pairs) as an N×2 matrix.
            points = zeros(0, 2);
            ok = true;
            text = strtrim(string(text));
            if text == ""
                return
            end
            rows = strtrim(split(text, ";"));
            rows(rows == "") = [];
            for row = rows'
                numbers = str2double(split(regexprep(row, "[,\s]+", " ")));
                if numel(numbers) ~= 2 || any(isnan(numbers))
                    ok = false;
                    points = zeros(0, 2);
                    return
                end
                points(end+1, :) = numbers'; %#ok<AGROW>
            end
        end

        function text = formatPoints(points)
            %FORMATPOINTS Inverse of parsePoints.
            if isempty(points)
                text = "";
            else
                text = strjoin(compose("%g %g", points), "; ");
            end
        end
    end
end

function [ok, message] = check(s)
ok = true;
message = "";
if s.start < 0
    [ok, message] = deal(false, "start time must not be negative");
elseif ismember(s.shape, ["pulse" "doublet" "ramp"]) && s.width <= 0
    [ok, message] = deal(false, "duration must be positive");
elseif s.shape == "sine" && s.period <= 0
    [ok, message] = deal(false, "period must be positive");
elseif s.shape == "points" && isempty(s.points)
    [ok, message] = deal(false, "needs at least one [time value] point");
end
end
