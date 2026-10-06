classdef MeasuredData
    %MEASUREDDATA Measured time series from a CSV file: drawn over the
    %   Custom plot, and fitted by adjusting inputs (the Fit tab).
    %
    %       D = dlab.core.MeasuredData.read("ringdown.csv");
    %       mapping = struct("Measured", "x", "Simulated", "position");
    %       R = dlab.core.MeasuredData.fit(plugin, params, D, mapping, ["c" "k"]);
    %       dlab.core.MeasuredData.describe(R)
    %
    %   The CSV has a header row of column names. The column named "time"
    %   or "t" (any case), else the first column, is time. A name may carry
    %   its unit, "x (mm)" or "x [mm]" (as Export CSV writes it), or a
    %   second header row may hold the units alone. Time is converted to
    %   seconds. Rows without a time or without any value are dropped and
    %   counted (Dropped); other empty cells stay NaN. Rows out of time
    %   order are sorted (Sorted is then true); repeated times are kept.
    %   Columns without a single number are left out. Commas, semicolons,
    %   or tabs separate the fields; quoted fields may not contain them.
    %
    %   D: File, Name, Time (column, s), Columns and Units (string rows),
    %   Values (numel(Time) × numel(Columns)), Dropped, Sorted.

    properties (Constant)
        MaxInputs = 4            % inputs one fit may adjust
        TimeNames = ["time" "t"] % export-table and CSV names of time
    end

    methods (Static)
        function D = read(file)
            %READ Measured data from a CSV file (see the class help).
            arguments
                file (1,1) string
            end
            [~, base, extension] = fileparts(file);
            name = base + extension;
            try
                lines = readlines(file, EmptyLineRule="skip");
            catch failure
                error("dlab:measured:read", "Could not read %s: %s", name, failure.message);
            end
            lines = strip(erase(lines, char(65279)));    % a byte-order mark, if any
            lines = lines(lines ~= "");
            if isempty(lines)
                error("dlab:measured:empty", "%s is empty.", name);
            end
            delimiter = delimiterOf(lines(1));
            [columns, units] = parseHeader(fields(lines(1), delimiter, []));
            m = numel(columns);
            if m < 2
                error("dlab:measured:columns", "%s needs a time column and at least one data column, " + ...
                    "separated by commas.", name);
            end
            first = 2;
            if numel(lines) >= 2
                second = fields(lines(2), delimiter, m);
                if all(isnan(str2double(second))) && any(second ~= "")
                    given = second ~= "";                 % a row of units under the names
                    units(given) = erase(second(given), ["(" ")" "[" "]"]);
                    first = 3;
                end
            end
            values = parseRows(lines(first:end), delimiter, m);
            values(~isfinite(values)) = NaN;
            if ~any(isfinite(values), "all")
                error("dlab:measured:noData", "%s has no numeric data under its header.", name);
            end

            timeColumn = find(ismember(lower(columns), dlab.core.MeasuredData.TimeNames), 1);
            if isempty(timeColumn)
                timeColumn = 1;
            end
            time = values(:, timeColumn);
            if units(timeColumn) ~= ""
                try
                    time = dlab.physics.convertUnits(time, units(timeColumn), "s");
                catch
                    error("dlab:measured:timeUnit", "%s: the time column's unit ""%s"" is not a unit of time.", ...
                        name, units(timeColumn));
                end
            end
            data = true(1, m);
            data(timeColumn) = false;
            data = data & any(~isnan(values), 1);
            if ~any(data)
                error("dlab:measured:noData", "%s has no numeric data besides time.", name);
            end
            values = values(:, data);
            keep = isfinite(time) & any(~isnan(values), 2);
            if nnz(keep) < 2
                error("dlab:measured:rows", "%s has fewer than two rows with a time and a value.", name);
            end
            time = time(keep);
            values = values(keep, :);
            sorted = any(diff(time) < 0);
            if sorted
                [time, order] = sort(time);
                values = values(order, :);
            end
            D = struct("File", file, "Name", name, "Time", time, "Columns", columns(data), ...
                "Units", units(data), "Values", values, "Dropped", numel(keep) - nnz(keep), "Sorted", sorted);
        end

        function [time, value, unit] = column(D, name)
            %COLUMN The finite samples of measured column NAME and its unit.
            j = find(D.Columns == string(name), 1);
            if isempty(j)
                error("dlab:measured:column", "%s has no column ""%s"".", D.Name, name);
            end
            value = D.Values(:, j);
            ok = isfinite(value);
            time = D.Time(ok);
            value = value(ok);
            unit = D.Units(j);
        end

        function name = timeVariable(T)
            %TIMEVARIABLE The time column of an export table ("time" or
            %   "t"), or "" when it has none.
            names = string(T.Properties.VariableNames);
            name = "";
            for candidate = dlab.core.MeasuredData.TimeNames
                if any(names == candidate)
                    name = candidate;
                    return
                end
            end
        end

        function [time, value, unit] = simulated(T, name, unit)
            %SIMULATED Column NAME of export table T against its time, with
            %   repeated instants (events) reduced to their last value, and
            %   converted to UNIT when given (the measured column's unit).
            arguments
                T table
                name (1,1) string
                unit (1,1) string = ""
            end
            timeName = dlab.core.MeasuredData.timeVariable(T);
            if timeName == ""
                error("dlab:measured:noTime", "This simulator's results have no time column " + ...
                    "to compare measured data with.");
            end
            if ~ismember(name, string(T.Properties.VariableNames)) || ~isnumeric(T.(name)) ...
                    || size(T.(name), 2) ~= 1
                error("dlab:measured:simulated", "The results have no numeric column ""%s"".", name);
            end
            time = double(T.(timeName));
            value = double(T.(name));
            if any(diff(time) < 0)
                error("dlab:measured:simulatedTime", "The results' %s column is not a single time " + ...
                    "series, so it cannot be compared with measured data.", timeName);
            end
            [time, last] = unique(time, "last");
            value = value(last);
            ok = isfinite(time) & isfinite(value);
            time = time(ok);
            value = value(ok);
            units = string(T.Properties.VariableUnits);
            simulatedUnit = "";
            if numel(units) == width(T)
                simulatedUnit = units(string(T.Properties.VariableNames) == name);
            end
            if unit ~= "" && simulatedUnit ~= "" && unit ~= simulatedUnit
                try
                    value = dlab.physics.convertUnits(value, simulatedUnit, unit);
                catch
                    error("dlab:measured:units", "The measured data is in %s but the simulated %s " + ...
                        "is in %s, and one cannot be converted to the other.", unit, name, simulatedUnit);
                end
            elseif unit == ""
                unit = simulatedUnit;
            end
        end

        function R = fit(plugin, params, D, mapping, inputs, options)
            %FIT Adjust INPUTS (1 to 4 real-valued inputs, the others as in
            %   PARAMS) so that the simulated column MAPPING.Simulated of
            %   the export table matches the measured column
            %   MAPPING.Measured of D, in the least-squares sense.
            %
            %   The simulation is interpolated onto the measured times
            %   inside its time span; points outside are left out and
            %   counted (Outside). fminsearch searches from the current
            %   values, through a transform that keeps each input inside
            %   its allowed range. A run that fails counts as an infinite
            %   misfit, so the search moves away from it.
            %
            %   Options: MaxEvaluations (default 120) limits the search;
            %   the error estimate then adds 2n + 1 runs for n inputs. Progress,
            %   @(fraction) stop, as in dlab.core.Sweep.runPoints; stopping
            %   returns the best inputs so far (Cancelled is true).
            %
            %   R: Inputs, Labels, Units, Start, Best, StandardErrors,
            %   StartRMS, BestRMS (in ValueUnits), Residuals (Time, Value:
            %   measured minus simulated at Best), Measured (Name, Time,
            %   Value), Simulated (Name, StartTime, Start, BestTime, Best),
            %   Used, Outside, Evaluations, Failed, Cancelled, Message.
            %   StandardErrors are approximate: from the Jacobian of the
            %   residuals at Best (central differences), assuming
            %   independent measurement noise of equal size; NaN when they
            %   cannot be estimated.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                D (1,1) struct
                mapping (1,1) struct
                inputs (1,:) string
                options.MaxEvaluations (1,1) double {mustBeInteger, mustBePositive} = 120
                options.Progress = []
            end
            inputs = unique(inputs, "stable");
            n = numel(inputs);
            if n < 1 || n > dlab.core.MeasuredData.MaxInputs
                error("dlab:measured:inputs", "A fit adjusts 1 to %d inputs.", dlab.core.MeasuredData.MaxInputs);
            end
            specs = plugin.parameters();
            bounds = zeros(n, 2);
            labels = strings(1, n);
            units = strings(1, n);
            start = zeros(1, n);
            for j = 1:n
                spec = dlab.core.Sweep.numericInput(specs, inputs(j));
                if spec.Type ~= "double"
                    error("dlab:measured:integer", "%s takes whole numbers, so it cannot be fitted.", spec.Label);
                end
                labels(j) = spec.Label;
                units(j) = spec.Units;
                bounds(j, :) = [spec.Min spec.Max];
                start(j) = params.(inputs(j));
            end
            [tMeasured, yMeasured, measuredUnit] = dlab.core.MeasuredData.column(D, mapping.Measured);
            if numel(tMeasured) < 2
                error("dlab:measured:rows", "The measured %s has fewer than two values.", mapping.Measured);
            end
            simulatedName = string(mapping.Simulated);
            map = boundedMap(bounds, start);
            limit = options.MaxEvaluations;
            total = limit + 2 * n + 1;

            count = 0;
            searchRuns = 0;
            failed = 0;
            firstFailure = "";
            stopRequested = false;
            valueUnit = measuredUnit;
            best = struct("X", map.Start, "RMS", Inf, "Time", [], "Value", [], "Inside", [], ...
                "Residual", []);
            startRun = best;

            previous = plugin.ProgressFcn;
            try
                search();
                searchRuns = count;
                errors = standardErrors();
            catch failure
                plugin.ProgressFcn = previous;
                rethrow(failure);
            end
            plugin.ProgressFcn = previous;

            R = struct("Inputs", inputs, "Labels", labels, "Units", units, "Start", map.Start, ...
                "Best", best.X, "StandardErrors", errors, "StartRMS", startRun.RMS, "BestRMS", best.RMS, ...
                "ValueUnits", valueUnit);
            R.Residuals = struct("Time", tMeasured(best.Inside), "Value", best.Residual);
            R.Measured = struct("Name", string(mapping.Measured), "Time", tMeasured, "Value", yMeasured);
            R.Simulated = struct("Name", simulatedName, "StartTime", startRun.Time, "Start", startRun.Value, ...
                "BestTime", best.Time, "Best", best.Value);
            R.Used = nnz(best.Inside);
            R.Outside = numel(tMeasured) - R.Used;
            if isempty(best.Inside)
                R.Outside = 0;
            end
            R.Evaluations = count;
            R.Failed = failed;
            R.Cancelled = stopRequested;
            R.Message = message();

            function search()
                % fminsearch over z, with z = 1 at the start (see boundedMap).
                settings = optimset(Display="off", MaxFunEvals=limit, MaxIter=20 * limit, TolX=1e-6, ...
                    TolFun=1e-10 * max(max(abs(yMeasured)), eps), OutputFcn=@(~, ~, ~) stopRequested);
                fminsearch(@objective, ones(1, n), settings);
            end

            function rms = objective(z)
                rms = Inf;
                if stopRequested || count >= limit
                    return
                end
                x = map.toX(z);
                [rms, trial] = evaluate(x);
                if count == 1
                    startRun = trial;
                end
                if rms < best.RMS
                    best = trial;
                end
            end

            function [rms, trial] = evaluate(x)
                % One solve at X: RMS misfit over the measured times inside
                % the simulated span (Inf when the run fails).
                trial = struct("X", x, "RMS", Inf, "Time", [], "Value", [], "Inside", [], "Residual", []);
                rms = Inf;
                T = solveRun(x);
                if isempty(T)
                    return
                end
                [trial.Time, trial.Value, valueUnit] = dlab.core.MeasuredData.simulated(T, simulatedName, measuredUnit);
                if numel(trial.Time) < 2
                    return
                end
                trial.Inside = tMeasured >= trial.Time(1) & tMeasured <= trial.Time(end);
                trial.Residual = yMeasured(trial.Inside) - interp1(trial.Time, trial.Value, tMeasured(trial.Inside));
                if ~isempty(trial.Residual)
                    rms = sqrt(mean(trial.Residual .^ 2));
                end
                trial.RMS = rms;
            end

            function T = solveRun(x)
                % The export table of one run, or [] when it failed or was stopped.
                T = [];
                count = count + 1;
                if ~isempty(options.Progress)
                    plugin.ProgressFcn = @(fraction) report(fraction);
                end
                if report(0)
                    return
                end
                try
                    result = dlab.core.Sweep.solveAt(plugin, params, inputs, x);
                    if ~stopRequested
                        T = plugin.exportTable(result);
                    end
                catch failure
                    if ~stopRequested
                        failed = failed + 1;
                        if firstFailure == ""
                            firstFailure = string(failure.message);
                        end
                    end
                end
            end

            function stop = report(fraction)
                % Overall progress: run COUNT of at most TOTAL.
                if isempty(options.Progress)
                    stop = false;
                    return
                end
                if ~isfinite(fraction)
                    fraction = 0;
                end
                stop = logical(options.Progress(min((count - 1 + fraction) / total, 1)));
                stopRequested = stopRequested || stop;
            end

            function se = standardErrors()
                % From J, the Jacobian of the residuals at Best: the
                % covariance s²(JᵀJ)⁻¹, s² the residual variance.
                se = nan(1, n);
                m = numel(best.Residual);
                if stopRequested || ~isfinite(best.RMS) || m <= n
                    return
                end
                try
                    J = dlab.physics.jacobian(@residualsAt, best.X(:), RelStep=1e-4, ...
                        Scale=max(abs(best.X(:)), 1e-6));
                catch
                    return
                end
                [~, triangle] = qr(J, 0);
                if any(~isfinite(J), "all") || rcond(triangle) < 1e-12
                    return
                end
                variance = sum(best.Residual .^ 2) / (m - n);
                inverse = triangle \ eye(n);
                se = sqrt(variance * sum(inverse .^ 2, 2))';
            end

            function r = residualsAt(x)
                % Simulated minus measured at Best's points (the negated
                % residual: same Jacobian up to sign, same errors).
                T = solveRun(x');
                if isempty(T)
                    error("dlab:measured:jacobian", "A run near the best fit failed.");
                end
                [time, value] = dlab.core.MeasuredData.simulated(T, simulatedName, measuredUnit);
                r = interp1(time, value, tMeasured(best.Inside)) - yMeasured(best.Inside);
                if any(~isfinite(r))
                    error("dlab:measured:jacobian", "A run near the best fit did not cover the data.");
                end
            end

            function text = message()
                if stopRequested
                    text = "Cancelled; the best inputs so far are shown.";
                elseif ~isfinite(best.RMS)
                    text = "No run matched the data";
                    if firstFailure ~= ""
                        text = text + ": " + firstFailure;
                    else
                        text = text + " (no measured time lies inside the simulated span).";
                    end
                    return
                elseif searchRuns >= limit
                    text = sprintf("Stopped at the limit of %d runs.", limit);
                else
                    text = "Converged.";
                end
                if failed == 1
                    text = text + " 1 run failed: " + firstFailure;
                elseif failed > 1
                    text = text + sprintf(" %d runs failed; the first: %s", failed, firstFailure);
                end
            end
        end

        function text = describe(R)
            %DESCRIBE One line: "Fitted Damping c = 0.212 ± 0.004 N·s/m ·
            %   RMS 0.031 → 0.004 m · 61 runs".
            parts = strings(1, numel(R.Inputs));
            for j = 1:numel(R.Inputs)
                parts(j) = R.Labels(j) + " = " + withError(R.Best(j), R.StandardErrors(j));
                if R.Units(j) ~= ""
                    parts(j) = parts(j) + " " + R.Units(j);
                end
            end
            text = "Fitted " + strjoin(parts, ", ");
            rms = sprintf("RMS %.3g → %.3g", R.StartRMS, R.BestRMS);
            if R.ValueUnits ~= ""
                rms = rms + " " + R.ValueUnits;
            end
            text = text + " · " + rms + sprintf(" · %d runs", R.Evaluations);
            if R.Outside > 0
                text = text + sprintf(" · %d points outside the simulated time", R.Outside);
            end
            if R.Failed > 0
                text = text + sprintf(" · %d failed", R.Failed);
            end
            if R.Cancelled
                text = text + " · cancelled";
            end
        end
    end
end

function delimiter = delimiterOf(header)
% Tab, then semicolon (spreadsheets in comma-decimal locales), else comma.
if contains(header, char(9))
    delimiter = char(9);
elseif contains(header, ";") && ~contains(header, ",")
    delimiter = ";";
else
    delimiter = ",";
end
end

function parts = fields(line, delimiter, m)
% The fields of one line, unquoted; padded or cut to M fields when given.
parts = strip(erase(split(line, delimiter), """"))';
if ~isempty(m)
    parts(end+1:m) = "";
    parts = parts(1:m);
end
end

function [names, units] = parseHeader(header)
% "x (mm)" and "x [mm]" carry a unit; a plain name has none.
names = header;
units = strings(size(header));
for k = 1:numel(header)
    tokens = regexp(header(k), "^(.*?)\s*[\(\[]([^\(\)\[\]]*)[\)\]]$", "tokens", "once");
    if ~isempty(tokens) && strip(tokens(1)) ~= ""
        names(k) = strip(tokens(1));
        units(k) = strip(tokens(2));
    end
    if names(k) == ""
        names(k) = "column " + k;
    end
end
names = matlab.lang.makeUniqueStrings(names);
end

function values = parseRows(lines, delimiter, m)
% Numbers in M columns; lines with the same field count are split together.
values = nan(numel(lines), m);
counts = count(lines, delimiter) + 1;
for c = unique(counts)'
    rows = find(counts == c);
    parts = split(lines(rows), delimiter);
    if isscalar(rows)
        parts = reshape(parts, 1, []);
    end
    used = min(c, m);
    values(rows, 1:used) = str2double(strip(erase(parts(:, 1:used), """")));
end
end

function map = boundedMap(bounds, start)
% Search variables z (1 at the start) for inputs with limits BOUNDS: each
% input is y(x) = x, log(x − lo), −log(hi − x), or log((x − lo)/(hi − x)),
% so every z stays inside the range; z is scaled so that a step of 0.05
% (fminsearch's first simplex) moves an input by about 5 %.
n = numel(start);
lo = bounds(:, 1)';
hi = bounds(:, 2)';
x0 = start;
for j = 1:n
    nudge = 1e-3 * max(abs(x0(j)), 1);
    if isfinite(lo(j)) && isfinite(hi(j))
        nudge = min(nudge, (hi(j) - lo(j)) / 4);
    end
    if isfinite(lo(j)) && x0(j) <= lo(j)
        x0(j) = lo(j) + nudge;        % start just inside a limit
    elseif isfinite(hi(j)) && x0(j) >= hi(j)
        x0(j) = hi(j) - nudge;
    end
end
y0 = zeros(1, n);
slope = zeros(1, n);
for j = 1:n
    [y0(j), slope(j)] = toY(x0(j), lo(j), hi(j));
end
magnitude = abs(x0);
magnitude(magnitude == 0) = 1;
scale = magnitude .* slope;
map.Start = x0;
map.toX = @(z) toX(y0 + scale .* (z - 1), lo, hi);
end

function [y, slope] = toY(x, lo, hi)
% The unbounded variable of x and its derivative dy/dx.
if isfinite(lo) && isfinite(hi)
    y = log((x - lo) / (hi - x));
    slope = 1 / (x - lo) + 1 / (hi - x);
elseif isfinite(lo)
    y = log(x - lo);
    slope = 1 / (x - lo);
elseif isfinite(hi)
    y = -log(hi - x);
    slope = 1 / (hi - x);
else
    y = x;
    slope = 1;
end
end

function x = toX(y, lo, hi)
x = y;
both = isfinite(lo) & isfinite(hi);
below = isfinite(lo) & ~isfinite(hi);
above = ~isfinite(lo) & isfinite(hi);
x(both) = lo(both) + (hi(both) - lo(both)) ./ (1 + exp(-y(both)));
x(below) = lo(below) + exp(y(below));
x(above) = hi(above) - exp(-y(above));
end

function text = withError(value, se)
% Value ± error, rounded to the error's first significant digit (two
% digits when that digit is 1), or to six digits when the error is tiny.
if ~isfinite(se) || se <= 0
    text = sprintf("%.4g", value);
    return
end
if se < 1e-6 * abs(value)
    text = sprintf("%.6g ± %.1g", value, se);    % noise-free data
    return
end
digits = -floor(log10(se));
if floor(se * 10 ^ digits) == 1
    digits = digits + 1;
end
if digits <= 0
    text = sprintf("%.4g ± %.2g", value, se);
else
    text = sprintf("%.*f ± %.*f", digits, value, digits, se);
end
end
