classdef MonteCarlo
    %MONTECARLO Uncertainty studies: give some numeric inputs a tolerance,
    %   solve once per random sample about the nominal inputs, and collect
    %   the spread of every key result (Plugin.metrics).
    %
    %       tol = dlab.core.MonteCarlo.tolerance(["v0" "theta"], Kind=["uniform" "normal"], ...
    %           Spread=[2 1]);
    %       R = dlab.core.MonteCarlo.run(plugin, params, tol, Samples=500, Seed=1);
    %       dlab.core.MonteCarlo.summaryTable(R)    % one row per quantity
    %
    %   A tolerance is uniform (± Spread, a half-width) or normal (standard
    %   deviation Spread), in the input's units or, with Relative, in
    %   percent of the nominal value. Samples are drawn reproducibly from
    %   dlab.physics.uniformSequence (one stream per input), clipped to
    %   the input's allowed range, and rounded for whole-number inputs.
    %
    %   R is a struct: Inputs, Labels, Units (string rows), Tolerances (the
    %   tolerance table with each input's Nominal and Std in its units),
    %   Seed, Requested, Samples (N × inputs), Clipped (samples clipped per
    %   input), Quantities, QuantityUnits, Data (N × quantities, NaN where
    %   a run failed), Errors (string column), Cancelled (then only the
    %   runs that finished are kept), NominalError, and per quantity (rows):
    %   Nominal (one run at the nominal inputs), Mean, Std, Min, Max, P05,
    %   P95, RSquared, and Sensitivity (inputs × quantities): each input's
    %   share of the variance from a standardized linear regression. A low
    %   RSquared means the result is not close to linear in the inputs, and
    %   the shares are then only a rough guide.

    properties (Constant)
        DefaultSamples = 100
        MaxSamples = 2000
        MaxSeed = 1e6           % keeps the stream seeds exact in double
        StreamStride = 7919     % seed offset between inputs' streams
        Kinds = ["uniform" "normal"]
    end

    methods (Static)
        function R = run(plugin, params, tolerances, options)
            %RUN Solve PLUGIN at the nominal PARAMS, then once per sample.
            %   Options: Samples (default 100), Seed (default 1), and
            %   Progress, @(fraction) stop, as in Sweep.run.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                tolerances table
                options.Samples (1,1) double {mustBeInteger} = dlab.core.MonteCarlo.DefaultSamples
                options.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 1
                options.Progress = []
            end
            if options.Samples < 2 || options.Samples > dlab.core.MonteCarlo.MaxSamples
                error("dlab:montecarlo:samples", "A Monte Carlo study takes 2 to %d samples.", ...
                    dlab.core.MonteCarlo.MaxSamples);
            end
            specs = plugin.parameters();
            tol = dlab.core.MonteCarlo.validate(specs, params, tolerances);
            [samples, clipped, mask] = dlab.core.MonteCarlo.draw(specs, tol, options.Samples, options.Seed);

            % The nominal run goes first, in the same batch, so progress and
            % cancelling cover it too.
            names = reshape(tol.Name, 1, []);
            P = dlab.core.Sweep.runPoints(plugin, params, names, [tol.Nominal'; samples], ...
                Progress=options.Progress);

            m = numel(names);
            R = struct("Inputs", names, "Labels", strings(1, m), "Units", strings(1, m), ...
                "Tolerances", tol, "Seed", options.Seed, "Requested", options.Samples, ...
                "Samples", samples, "Clipped", clipped, ...
                "Quantities", P.Quantities, "QuantityUnits", P.QuantityUnits, ...
                "Data", P.Data(2:end, :), "Errors", P.Errors(2:end), "Cancelled", P.Cancelled, ...
                "NominalError", P.Errors(1));
            for j = 1:m
                spec = dlab.core.ParamSpec.find(specs, names(j));
                R.Labels(j) = spec.Label;
                R.Units(j) = spec.Units;
            end
            if R.Cancelled
                % Keep only the runs that finished (failed ones count).
                ran = find(R.Errors ~= "" | any(isfinite(R.Data), 2), 1, "last");
                if isempty(ran)
                    ran = 0;
                end
                R.Samples = R.Samples(1:ran, :);
                R.Data = R.Data(1:ran, :);
                R.Errors = R.Errors(1:ran);
                R.Clipped = sum(mask(1:ran, :), 1);
            end
            R.Nominal = P.Data(1, :);
            R = dlab.core.MonteCarlo.addStatistics(R);
        end

        function T = tolerance(names, options)
            %TOLERANCE A tolerance table (Name, Kind, Spread, Relative) for
            %   run: one row per name; options are scalars or one per name.
            arguments
                names (1,:) string
                options.Kind (1,:) string = "uniform"
                options.Spread (1,:) double = 5
                options.Relative (1,:) logical = false
            end
            n = numel(names);
            T = table(names(:), expand(options.Kind, n), expand(options.Spread, n), ...
                expand(options.Relative, n), VariableNames=["Name" "Kind" "Spread" "Relative"]);
        end

        function tol = validate(specs, params, tolerances)
            %VALIDATE Check a tolerance table against the inputs SPECS and
            %   the nominal PARAMS; adds each input's Nominal value and Std
            %   (the standard deviation it implies, in the input's units).
            %   Errors with a readable message.
            arguments
                specs (:,1) dlab.core.ParamSpec
                params (1,1) struct
                tolerances table
            end
            tol = tolerances;
            if ~ismember("Name", tol.Properties.VariableNames) || height(tol) == 0
                error("dlab:montecarlo:none", "Choose at least one input to vary.");
            end
            n = height(tol);
            tol.Name = string(tol.Name);
            if ~ismember("Kind", tol.Properties.VariableNames)
                tol.Kind = repmat("uniform", n, 1);
            end
            if ~ismember("Spread", tol.Properties.VariableNames)
                error("dlab:montecarlo:spread", "Give each varied input a spread.");
            end
            if ~ismember("Relative", tol.Properties.VariableNames)
                tol.Relative = false(n, 1);
            end
            tol.Kind = lower(string(tol.Kind));
            tol.Spread = double(tol.Spread);
            tol.Relative = logical(tol.Relative);
            tol = tol(:, ["Name" "Kind" "Spread" "Relative"]);
            if numel(unique(tol.Name)) < n
                error("dlab:montecarlo:duplicate", "Each input can be varied only once.");
            end
            tol.Nominal = zeros(n, 1);
            tol.Std = zeros(n, 1);
            for j = 1:n
                spec = dlab.core.Sweep.numericInput(specs, tol.Name(j));
                if ~ismember(tol.Kind(j), dlab.core.MonteCarlo.Kinds)
                    error("dlab:montecarlo:kind", "%s: the distribution must be uniform or normal.", spec.Label);
                end
                if ~isfinite(tol.Spread(j)) || tol.Spread(j) < 0
                    error("dlab:montecarlo:spread", "%s: the spread must be zero or more.", spec.Label);
                end
                nominal = double(params.(spec.Name));
                if tol.Relative(j) && nominal == 0
                    error("dlab:montecarlo:relative", ...
                        "%s is 0, so a percentage gives no spread; give the spread in %s instead.", ...
                        spec.Label, unitsOrValue(spec.Units));
                end
                spread = tol.Spread(j);
                if tol.Relative(j)
                    spread = spread / 100 * abs(nominal);
                end
                tol.Nominal(j) = nominal;
                if tol.Kind(j) == "uniform"
                    tol.Std(j) = spread / sqrt(3);
                else
                    tol.Std(j) = spread;
                end
            end
        end

        function [samples, clipped, mask] = draw(specs, tol, count, seed)
            %DRAW COUNT samples (rows) of the inputs in TOL (from validate),
            %   reproducible for a SEED. CLIPPED counts, per input, the
            %   samples moved back inside the input's allowed range (MASK
            %   marks them).
            arguments
                specs (:,1) dlab.core.ParamSpec
                tol table
                count (1,1) double {mustBeInteger, mustBePositive}
                seed (1,1) double {mustBeInteger, mustBeNonnegative}
            end
            if seed > dlab.core.MonteCarlo.MaxSeed
                error("dlab:montecarlo:seed", "The seed must be a whole number from 0 to %d.", ...
                    dlab.core.MonteCarlo.MaxSeed);
            end
            m = height(tol);
            raw = zeros(count, m);
            for j = 1:m
                stream = seed + dlab.core.MonteCarlo.StreamStride * j;
                if tol.Kind(j) == "uniform"
                    u = dlab.physics.uniformSequence(stream, count);
                    z = sqrt(3) * (2 * u - 1);          % unit variance
                else
                    u = dlab.physics.uniformSequence(stream, 2 * count);
                    u1 = u(1:2:end);
                    u1(u1 == 0) = 2^-33;                % log(0) guard
                    z = sqrt(-2 * log(u1)) .* cos(2 * pi * u(2:2:end));   % Box–Muller
                end
                raw(:, j) = tol.Nominal(j) + tol.Std(j) * z(:);
            end
            [samples, mask] = clipToRange(specs, tol, raw);
            clipped = sum(mask, 1);
        end

        function q = percentile(values, percent)
            %PERCENTILE Percentiles of VALUES (NaN ignored) by sorting and
            %   linear interpolation between order statistics: the k-th of
            %   n sorted values sits at 100 (k - 1) / (n - 1) percent (as
            %   Excel's PERCENTILE.INC). NaN when no value is finite.
            arguments
                values double
                percent double {mustBeInRange(percent, 0, 100)}
            end
            x = sort(values(isfinite(values(:))));
            q = nan(size(percent));
            n = numel(x);
            if n == 0
                return
            end
            if n == 1
                q(:) = x;
                return
            end
            position = 1 + (n - 1) * percent / 100;
            below = min(floor(position), n - 1);
            q = x(below) + (position - below) .* (x(below + 1) - x(below));
            q = reshape(q, size(percent));
        end

        function [shares, rSquared] = sensitivity(X, y)
            %SENSITIVITY Each column of X's share of the variance of Y:
            %   squared standardized regression coefficients, normalized to
            %   sum to 1, and the fit's R². Rows with a NaN are left out;
            %   columns that do not vary get share 0. NaN when Y does not
            %   vary or there are too few rows.
            m = size(X, 2);
            shares = nan(m, 1);
            rSquared = NaN;
            keep = isfinite(y) & all(isfinite(X), 2);
            X = X(keep, :);
            y = y(keep);
            sx = std(X, 0, 1);
            varies = sx > 0 & sx > 1e-12 * max(abs(mean(X, 1)), realmin);
            sy = std(y);
            if numel(y) < nnz(varies) + 2 || ~(sy > 1e-12 * max(abs(mean(y)), realmin))
                return
            end
            Z = (X(:, varies) - mean(X(:, varies), 1)) ./ sx(varies);
            w = (y - mean(y)) / sy;
            beta = Z \ w;
            residual = w - Z * beta;
            rSquared = max(0, 1 - sum(residual.^2) / sum(w.^2));
            shares(:) = 0;
            total = sum(beta.^2);
            if total > 0
                shares(varies) = beta.^2 / total;
            end
        end

        function T = toTable(R)
            %TOTABLE One row per sample: the inputs, every quantity, and
            %   the error of runs that failed; units in VariableUnits.
            names = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName([R.Inputs, R.Quantities]));
            T = array2table([R.Samples, R.Data], VariableNames=names);
            T.Properties.VariableDescriptions = [R.Labels, R.Quantities];
            T.Properties.VariableUnits = [R.Units, R.QuantityUnits];
            T.error = R.Errors;
        end

        function T = summaryTable(R)
            %SUMMARYTABLE One row per quantity: its nominal value, mean,
            %   standard deviation, 5th and 95th percentiles, and the input
            %   with the largest share of its variance (with that share and
            %   the regression's R²).
            q = numel(R.Quantities);
            influential = strings(q, 1);
            share = nan(q, 1);
            for k = 1:q
                [best, at] = max(R.Sensitivity(:, k));
                if ~isempty(best) && isfinite(best)
                    influential(k) = R.Labels(at);
                    share(k) = best;
                end
            end
            T = table(R.Quantities(:), R.QuantityUnits(:), R.Nominal(:), R.Mean(:), R.Std(:), ...
                R.P05(:), R.P95(:), influential, share, R.RSquared(:), ...
                VariableNames=["Quantity" "Units" "Nominal" "Mean" "Std" "P05" "P95" ...
                "MostInfluential" "Share" "RSquared"]);
        end
    end

    methods (Static, Access = private)
        function R = addStatistics(R)
            % Statistics and sensitivities over the runs that solved.
            q = numel(R.Quantities);
            m = numel(R.Inputs);
            [R.Mean, R.Std, R.Min, R.Max, R.P05, R.P95, R.RSquared] = deal(nan(1, q));
            R.Sensitivity = nan(m, q);
            for k = 1:q
                y = R.Data(:, k);
                ok = isfinite(y);
                if ~any(ok)
                    continue
                end
                R.Mean(k) = mean(y(ok));
                R.Std(k) = std(y(ok));
                R.Min(k) = min(y(ok));
                R.Max(k) = max(y(ok));
                R.P05(k) = dlab.core.MonteCarlo.percentile(y, 5);
                R.P95(k) = dlab.core.MonteCarlo.percentile(y, 95);
                [R.Sensitivity(:, k), R.RSquared(k)] = dlab.core.MonteCarlo.sensitivity(R.Samples, y);
            end
        end
    end
end

function [samples, mask] = clipToRange(specs, tol, raw)
% Round whole-number inputs, then move samples outside an input's allowed
% range onto its edge (just inside an open bound). MASK marks the moved
% samples (rounding alone does not count).
samples = raw;
mask = false(size(raw));
for j = 1:height(tol)
    spec = dlab.core.ParamSpec.find(specs, tol.Name(j));
    [low, high] = allowedRange(spec, tol.Std(j));
    if spec.Type == "integer"
        samples(:, j) = round(samples(:, j));
    end
    inside = min(max(samples(:, j), low), high);
    mask(:, j) = inside ~= samples(:, j);
    samples(:, j) = inside;
end
end

function [low, high] = allowedRange(spec, sigma)
% The allowed range; an open bound is replaced by a value just inside it.
low = spec.Min;
high = spec.Max;
margin = 1e-3 * sigma;
if ~spec.MinInclusive && isfinite(low)
    low = low + max(margin, eps(low));
end
if ~spec.MaxInclusive && isfinite(high)
    high = high - max(margin, eps(high));
end
if spec.Type == "integer"
    low = ceil(low);
    high = floor(high);
    if ~spec.MinInclusive && low == spec.Min
        low = low + 1;
    end
    if ~spec.MaxInclusive && high == spec.Max
        high = high - 1;
    end
end
end

function values = expand(values, n)
if isscalar(values)
    values = repmat(values, n, 1);
elseif numel(values) ~= n
    error("dlab:montecarlo:size", "Give one value, or one per input.");
end
values = values(:);
end

function text = unitsOrValue(units)
text = "the input's units";
if units ~= ""
    text = units;
end
end
