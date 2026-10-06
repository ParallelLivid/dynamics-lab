classdef Optimizer
    %OPTIMIZER Find the inputs that maximize or minimize one key result
    %   (Plugin.metrics), each within its range, optionally keeping
    %   another result below or above a limit.
    %
    %       R = dlab.core.Optimizer.run(plugin, params, "theta", "Range");
    %       R.Best        % 45 for a point mass launched from the ground
    %
    %   The search: a coarse start grid over the ranges (7 values for one
    %   input, 4, 3, or 2 per input for more), then from its best point
    %   fminbnd (one input, between the grid's neighbours of that point)
    %   or fminsearch (several inputs) on the bounded transform
    %   x = lo + (hi − lo)(sin z + 1)/2 (Nelder–Mead, no restarts).
    %   Integer inputs are rounded before each solve, then a ±1 search over
    %   the neighbouring whole numbers finishes. Repeated points are not
    %   solved again.
    %
    %   A constraint is a penalty that ranks every run that meets it above
    %   every run that does not (those by how far they miss), so the best
    %   point meets it whenever any run did; Satisfied says whether it does.
    %   A run that fails (solve error, missing result, NaN) ranks below all
    %   of them and is recorded in Evaluations.Error.
    %
    %   R is a struct: Inputs, Labels, Units (string rows), Bounds (n×2,
    %   as searched), Best (row of values), BestMetric, Metric,
    %   MetricUnits, Goal ("maximize" | "minimize"), Constraint (struct
    %   Metric, Type "<=" | ">=", Value, Units; or []), ConstraintValue (at
    %   Best), Satisfied, Evaluations (table: one column per input, Metric,
    %   ConstraintMetric, Feasible, Error), Method, Capped (hit
    %   MaxEvaluations), Cancelled, and Message.

    properties (Constant)
        MaxInputs = 4
        DefaultEvaluations = 150
        GridPoints = [7 4 3 2]      % start grid values per input, by input count
    end

    methods (Static)
        function R = run(plugin, params, names, metric, options)
            %RUN Optimize METRIC over inputs NAMES, other inputs as PARAMS.
            %   Options: Goal ("maximize" or "minimize"); Constraint, a
            %   struct with Metric, Type ("<=" or ">="), and Value; Bounds,
            %   n×2 search ranges (default: each input's allowed range, see
            %   defaultRange); MaxEvaluations (solves, default 150);
            %   StartGrid (default true; false starts from PARAMS); and
            %   Progress, @(fraction) stop, as in Sweep.run. Cancelled
            %   runs return the best point so far with Cancelled true.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                names (1,:) string
                metric (1,1) string
                options.Goal (1,1) string {mustBeMember(options.Goal, ["maximize" "minimize"])} = "maximize"
                options.Constraint = []
                options.Bounds double = []
                options.MaxEvaluations (1,1) double {mustBeInteger, mustBePositive} = 150
                options.StartGrid (1,1) logical = true
                options.Progress = []
            end
            n = numel(names);
            if n < 1 || n > dlab.core.Optimizer.MaxInputs || numel(unique(names)) < n
                error("dlab:optimize:inputs", "Choose 1 to %d different inputs to vary.", ...
                    dlab.core.Optimizer.MaxInputs);
            end
            specs = plugin.parameters();
            spec = arrayfun(@(name) dlab.core.Sweep.numericInput(specs, name), names, UniformOutput=false);
            spec = [spec{:}];
            if isempty(options.Bounds)
                options.Bounds = zeros(n, 2);
                for q = 1:n
                    options.Bounds(q, :) = dlab.core.Optimizer.defaultRange(spec(q), params.(names(q)));
                end
            elseif ~isequal(size(options.Bounds), [n 2])
                error("dlab:optimize:bounds", "Bounds needs one row [from to] per input.");
            end
            bounds = zeros(n, 2);
            for q = 1:n
                bounds(q, :) = dlab.core.Optimizer.searchRange(spec(q), options.Bounds(q, 1), options.Bounds(q, 2));
            end
            constraint = normalizeConstraint(options.Constraint);
            lo = bounds(:, 1)';
            hi = bounds(:, 2)';
            isInteger = [spec.Type] == "integer";
            sense = 1 - 2 * (options.Goal == "maximize");     % minimize sense * metric
            maxEvaluations = options.MaxEvaluations;

            % Every solve, in order.
            X = nan(maxEvaluations, n);
            M = nan(maxEvaluations, 1);
            C = nan(maxEvaluations, 1);
            Errors = strings(maxEvaluations, 1);
            count = 0;
            units = struct("Metric", "", "Constraint", "");
            penalty = NaN;              % fixed once the start point is known
            capped = false;
            cancelled = false;
            stopRequested = false;
            previous = plugin.ProgressFcn;
            try
                search();
            catch ME
                plugin.ProgressFcn = previous;
                rethrow(ME);
            end
            plugin.ProgressFcn = previous;

            X = X(1:count, :);
            [~, best] = min(arrayfun(@cost, 1:count));
            R = struct("Inputs", names, "Labels", [spec.Label], "Units", [spec.Units], "Bounds", bounds, ...
                "Best", nan(1, n), "BestMetric", NaN, "Metric", metric, "MetricUnits", units.Metric, ...
                "Goal", options.Goal, "Constraint", constraint, "ConstraintValue", NaN, ...
                "Satisfied", false, "Evaluations", evaluationTable(), "Method", "fminsearch", ...
                "Capped", capped, "Cancelled", cancelled, "Message", "");
            if n == 1
                R.Method = "fminbnd";
            end
            if ~isempty(constraint)
                R.Constraint.Units = units.Constraint;
            end
            if ~isempty(best) && Errors(best) == ""
                R.Best = X(best, :);
                R.BestMetric = M(best);
                R.ConstraintValue = C(best);
                R.Satisfied = isFeasible(best);
            end
            R.Message = dlab.core.Optimizer.describe(R);

            function search()
                % Start grid, local search, then whole-number neighbours.
                start = [];
                if options.StartGrid
                    points = startGrid(lo, hi, isInteger);
                    for row = 1:size(points, 1)
                        if ~evaluate(points(row, :))
                            return
                        end
                    end
                    [~, k] = min(arrayfun(@cost, 1:count));
                    start = X(k, :);
                end
                if isempty(start)
                    start = min(max(cellfun(@(name) double(params.(name)), cellstr(names)), lo), hi);
                    start(isInteger) = round(start(isInteger));
                    if ~evaluate(start)
                        return
                    end
                end
                fixPenalty();
                if n == 1
                    [a, b] = bracket(start);
                    if ~runLocal(@() fminbnd(@costAt, a, b, optimset(Display="off", ...
                            TolX=1e-6 * (hi - lo), MaxFunEvals=4 * maxEvaluations, MaxIter=4 * maxEvaluations)))
                        return
                    end
                else
                    [bestCost, k] = min(arrayfun(@cost, 1:count));
                    u = min(max(2 * (X(k, :) - lo) ./ (hi - lo) - 1, -1), 1);
                    z0 = 2 * pi + asin(u);    % offset so the first simplex spans ~0.3 rad
                    if ~runLocal(@() fminsearch(@(z) costAt(fromZ(z)), z0, optimset(Display="off", ...
                            TolX=1e-3, TolFun=1e-6 * max(1, abs(bestCost)), ...
                            MaxFunEvals=4 * maxEvaluations, MaxIter=4 * maxEvaluations)))
                        return
                    end
                end
                if any(isInteger)
                    neighbours();
                end
            end

            function [a, b] = bracket(start)
                % One input: the grid values either side of the start.
                values = unique(X(1:count, 1));
                [~, k] = min(abs(values - start));
                a = values(max(k - 1, 1));
                b = values(min(k + 1, numel(values)));
                if a == b
                    [a, b] = deal(lo, hi);
                end
            end

            function ok = runLocal(optimize)
                % Run a local search; false once it stopped the whole search.
                ok = true;
                try
                    optimize();
                catch ME
                    if ME.identifier ~= "dlab:optimize:stop"
                        rethrow(ME);
                    end
                    ok = false;
                end
            end

            function neighbours()
                % Step each whole-number input by ±1 while that improves.
                [current, k] = min(arrayfun(@cost, 1:count));
                x = X(k, :);
                improved = true;
                while improved
                    improved = false;
                    for j = find(isInteger)
                        for step = [-1 1]
                            trial = x;
                            trial(j) = trial(j) + step;
                            if trial(j) < lo(j) || trial(j) > hi(j)
                                continue
                            end
                            [ok, k] = evaluate(trial);
                            if ~ok
                                return
                            end
                            if cost(k) < current
                                [current, x, improved] = deal(cost(k), trial, true);
                            end
                        end
                    end
                end
            end

            function x = fromZ(z)
                x = lo + (hi - lo) .* (sin(z(:)') + 1) / 2;
            end

            function c = costAt(x)
                % The penalized objective; stops the optimizer by an error.
                [ok, k] = evaluate(x);
                if ~ok
                    error("dlab:optimize:stop", "The search stopped.");
                end
                c = cost(k);
            end

            function [ok, k] = evaluate(x)
                % Solve at X (whole numbers rounded, kept in range) unless
                % it was solved already; OK is false once the search stops.
                x = min(max(x(:)', lo), hi);
                x(isInteger) = round(x(isInteger));
                k = find(all(X(1:count, :) == x, 2), 1);
                ok = true;
                if ~isempty(k)
                    return
                end
                if count >= maxEvaluations
                    capped = true;
                    ok = false;
                    return
                end
                if ~isempty(options.Progress)
                    plugin.ProgressFcn = @(fraction) report(fraction);
                end
                if report(0)
                    [cancelled, ok] = deal(true, false);
                    return
                end
                k = count + 1;
                X(k, :) = x;
                try
                    result = dlab.core.Sweep.solveAt(plugin, params, names, x);
                    if ~stopRequested
                        record(k, plugin.metrics(result));
                    end
                catch failure
                    Errors(k) = string(failure.message);
                end
                if stopRequested
                    X(k, :) = NaN;
                    Errors(k) = "";
                    [cancelled, ok] = deal(true, false);
                    return
                end
                count = k;
            end

            function record(k, T)
                % Run k's metric and constraint metric, or why it has none.
                [M(k), unit, found] = valueOf(T, metric);
                if ~found
                    error("dlab:optimize:metric", "This run has no result named ""%s"".", metric);
                end
                units.Metric = unit;
                if ~isempty(constraint)
                    [C(k), unit, found] = valueOf(T, constraint.Metric);
                    if ~found
                        error("dlab:optimize:metric", "This run has no result named ""%s"".", constraint.Metric);
                    end
                    units.Constraint = unit;
                end
                if ~isfinite(M(k)) || (~isempty(constraint) && ~isfinite(C(k)))
                    error("dlab:optimize:nan", "The result is not a finite number.");
                end
            end

            function stop = report(fraction)
                % Overall progress: solves done out of MaxEvaluations.
                if isempty(options.Progress)
                    stop = false;
                    return
                end
                if ~isfinite(fraction)
                    fraction = 0;
                end
                stop = logical(options.Progress(min((count + fraction) / maxEvaluations, 1)));
                stopRequested = stopRequested || stop;
            end

            function fixPenalty()
                % Large against every result seen so far; fixed from here on
                % so the optimizers see one unchanging objective.
                seen = abs(M(1:count));
                seen = seen(isfinite(seen));
                penalty = 1e6 * (1 + max([seen; 0]));
            end

            function tf = isFeasible(k)
                tf = Errors(k) == "" && violation(k) == 0;
            end

            function v = violation(k)
                % How far run k misses the constraint, relative to its limit.
                v = 0;
                if isempty(constraint)
                    return
                end
                limit = constraint.Value;
                if constraint.Type == "<="
                    v = max(0, C(k) - limit);
                else
                    v = max(0, limit - C(k));
                end
                if v <= 1e-12 * max(1, abs(limit))
                    v = 0;
                else
                    v = v / max(1, abs(limit));
                end
            end

            function c = cost(k)
                % Met constraint: sense × metric. Missed: P (1 + v/(1 + v)),
                % ordered by the miss v. Failed: 3P.
                P = penalty;
                if isnan(P)
                    P = 1e6 * (1 + max([abs(M(isfinite(M))); 0]));
                end
                if Errors(k) ~= ""
                    c = 3 * P;
                    return
                end
                v = violation(k);
                if v > 0
                    c = P * (1 + v / (1 + v));
                else
                    c = sense * M(k);
                end
            end

            function T = evaluationTable()
                feasible = logical(arrayfun(@isFeasible, (1:count)'));
                columns = matlab.lang.makeUniqueStrings([names "Metric" "ConstraintMetric" "Feasible" "Error"]);
                T = [array2table(X, VariableNames=columns(1:n)), ...
                    table(M(1:count), C(1:count), feasible, Errors(1:count), VariableNames=columns(n+1:end))];
                constraintName = "";
                constraintUnits = "";
                if ~isempty(constraint)
                    [constraintName, constraintUnits] = deal(constraint.Metric, units.Constraint);
                end
                T.Properties.VariableDescriptions = [[spec.Label], metric, constraintName, "", ""];
                T.Properties.VariableUnits = [[spec.Units], units.Metric, constraintUnits, "", ""];
            end
        end

        function range = defaultRange(spec, value)
            %DEFAULTRANGE The input's allowed range; an unlimited side ends
            %   ten times the current value's size (at least 10) away.
            range = [spec.Min spec.Max];
            span = 10 * max(abs(value), 1);
            if isinf(range(1)) && isinf(range(2))
                range = value + [-span span];
            elseif isinf(range(2))
                range(2) = max(value, range(1)) + span;
            elseif isinf(range(1))
                range(1) = min(value, range(2)) - span;
            end
        end

        function range = searchRange(spec, from, to)
            %SEARCHRANGE The values the search may try between FROM and TO:
            %   a hair inside an open limit, whole numbers for integers.
            %   Errors when the range is empty or outside what is allowed.
            if ~(isfinite(from) && isfinite(to) && from < to)
                error("dlab:optimize:range", "%s: the search range needs from < to.", spec.Label);
            end
            if from < spec.Min || to > spec.Max
                error("dlab:optimize:range", "%s can only be searched within %s.", spec.Label, spec.rangeText());
            end
            hair = 1e-6 * (to - from);
            if ~spec.MinInclusive && from <= spec.Min
                from = spec.Min + hair;
            end
            if ~spec.MaxInclusive && to >= spec.Max
                to = spec.Max - hair;
            end
            if spec.Type == "integer"
                from = ceil(from);
                to = floor(to);
                if from >= to
                    error("dlab:optimize:range", "%s: the search range needs two whole numbers or more.", spec.Label);
                end
            end
            range = [from to];
        end

        function text = describe(R)
            %DESCRIBE One line: "Best: Launch angle = 45 deg → Range 254.8 m
            %   (37 runs)", whether the constraint is met, and any trouble.
            runs = height(R.Evaluations);
            failed = nnz(R.Evaluations.Error ~= "");
            if all(isnan(R.Best))
                if runs == 0
                    text = "No runs finished.";
                else
                    first = R.Evaluations.Error(find(R.Evaluations.Error ~= "", 1));
                    text = sprintf("Every run failed (%d): %s", runs, first);
                end
            else
                parts = strings(1, numel(R.Inputs));
                for k = 1:numel(R.Inputs)
                    parts(k) = R.Labels(k) + " = " + sprintf("%.4g", R.Best(k)) + unitSuffix(R.Units(k));
                end
                text = "Best: " + strjoin(parts, ", ") + " → " + R.Metric + " " + ...
                    sprintf("%.4g", R.BestMetric) + unitSuffix(R.MetricUnits) + sprintf(" (%d runs)", runs);
                if ~isempty(R.Constraint)
                    c = R.Constraint;
                    limit = c.Metric + " " + symbolOf(c.Type) + " " + sprintf("%.4g", c.Value) + unitSuffix(c.Units);
                    if R.Satisfied
                        text = text + " · meets " + limit + sprintf(" (%.4g)", R.ConstraintValue);
                    else
                        text = text + " · NO run met " + limit + sprintf(" (closest %.4g)", R.ConstraintValue);
                    end
                end
            end
            if failed > 0 && failed < runs
                text = text + sprintf(" · %d failed", failed);
            end
            if R.Cancelled
                text = text + " · cancelled";
            elseif R.Capped
                text = text + sprintf(" · stopped at the %d-run limit", runs);
            end
        end
    end
end

function c = normalizeConstraint(c)
% [] or a struct Metric, Type ("<=" or ">=", "≤" and "≥" accepted), Value.
if isempty(c)
    c = [];
    return
end
if ~isstruct(c) || ~all(isfield(c, ["Metric" "Type" "Value"]))
    error("dlab:optimize:constraint", "A constraint is a struct with Metric, Type, and Value.");
end
type = replace(string(c.Type), ["≤" "≥"], ["<=" ">="]);
if ~ismember(type, ["<=" ">="]) || ~isnumeric(c.Value) || ~isscalar(c.Value) || ~isfinite(c.Value)
    error("dlab:optimize:constraint", "A constraint needs Type ""<="" or "">="" and a finite Value.");
end
c = struct("Metric", string(c.Metric), "Type", type, "Value", double(c.Value), "Units", "");
end

function points = startGrid(lo, hi, isInteger)
% Every combination of a few evenly spaced values per input, ends included.
n = numel(lo);
per = dlab.core.Optimizer.GridPoints(n);
grids = cell(1, n);
for j = 1:n
    values = linspace(lo(j), hi(j), per)';
    if isInteger(j)
        values = unique(round(values));
    end
    grids{j} = values;
end
[grids{:}] = ndgrid(grids{:});
points = cell2mat(cellfun(@(a) a(:), grids, UniformOutput=false));
end

function [value, unit, found] = valueOf(T, name)
row = find(string(T.Quantity) == name, 1);
found = ~isempty(row);
value = NaN;
unit = "";
if found
    value = double(T.Value(row));
    unit = string(T.Units(row));
end
end

function text = unitSuffix(unit)
text = "";
if unit ~= ""
    text = " " + unit;
end
end

function s = symbolOf(type)
s = "≥";
if type == "<="
    s = "≤";
end
end
