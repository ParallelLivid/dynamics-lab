classdef Sweep
    %SWEEP Parameter studies: solve once per value of one input and
    %   collect every run's metrics (Plugin.metrics).
    %
    %       S = dlab.core.Sweep.run(plugin, params, "theta", 5:5:85);
    %       T = dlab.core.Sweep.toTable(S);    % one row per value
    %
    %   S is a struct: Parameter, Label, Units, Values (column), Quantities
    %   and QuantityUnits (string rows), Data (numel(Values) × numel(Quantities),
    %   NaN where a run failed or lacked that quantity), Errors (string
    %   column, "" for runs that solved), and Cancelled. Results with many
    %   values per run (Plugin.distributions) are in SetNames, SetUnits
    %   (string rows), and SetData (numel(Values) × numel(SetNames) cell of
    %   columns); Sweep.toLongTable lists them one value per row.

    properties (Constant)
        MaxSteps = 200
    end

    methods (Static)
        function S = run(plugin, params, name, values, options)
            %RUN Solve PLUGIN for each value of input NAME, other inputs as PARAMS.
            %   Options: Progress, @(fraction) stop, called with the overall
            %   progress; returning true cancels (S.Cancelled is then true
            %   and later values stay NaN).
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                name (1,1) string
                values (:,1) double {mustBeFinite}
                options.Progress = []
            end
            spec = dlab.core.Sweep.numericInput(plugin.parameters(), name);
            if isempty(values) || numel(values) > dlab.core.Sweep.MaxSteps
                error("dlab:sweep:steps", "A sweep takes 1 to %d values.", dlab.core.Sweep.MaxSteps);
            end
            P = dlab.core.Sweep.runPoints(plugin, params, name, values, Progress=options.Progress);
            S = struct("Parameter", name, "Label", spec.Label, "Units", spec.Units, "Values", values);
            for field = string(fieldnames(P))'
                S.(field) = P.(field);
            end
        end

        function P = runPoints(plugin, params, names, points, options)
            %RUNPOINTS Solve PLUGIN once per row of POINTS (one column per
            %   input in NAMES, other inputs as PARAMS) and collect every
            %   run's metrics: the engine behind sweeps, maps, and Monte
            %   Carlo. P: Quantities, QuantityUnits, Data (rows × quantities,
            %   NaN where a run failed or lacked one), Errors, Cancelled,
            %   SetNames, SetUnits, SetData. Option Progress as in run.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                names (1,:) string
                points double
                options.Progress = []
            end
            n = size(points, 1);
            P = struct("Quantities", strings(1, 0), "QuantityUnits", strings(1, 0), ...
                "Data", nan(n, 0), "Errors", strings(n, 1), "Cancelled", false, ...
                "SetNames", strings(1, 0), "SetUnits", strings(1, 0), "SetData", {cell(n, 0)});
            stopRequested = false;
            % Restored explicitly: an onCleanup here would be kept alive by
            % the nested progress function the plugin holds.
            previous = plugin.ProgressFcn;
            try
                P = runAll(P);
            catch ME
                plugin.ProgressFcn = previous;
                rethrow(ME);
            end
            plugin.ProgressFcn = previous;

            function P = runAll(P)
                % One solve per point; a failed run records its message.
                for k = 1:n
                    if ~isempty(options.Progress)
                        plugin.ProgressFcn = @(fraction) report(fraction, k);
                    end
                    if report(0, k)
                        P.Cancelled = true;
                        break
                    end
                    try
                        result = dlab.core.Sweep.solveAt(plugin, params, names, points(k, :));
                        if stopRequested
                            P.Cancelled = true;
                            break
                        end
                        P = store(P, k, plugin.metrics(result));
                        P = storeSets(P, k, plugin.distributions(result));
                    catch failure
                        if stopRequested
                            P.Cancelled = true;
                            break
                        end
                        P.Errors(k) = string(failure.message);
                    end
                end
            end

            function stop = report(fraction, k)
                % Overall progress: run k of n, FRACTION of the way through it.
                if isempty(options.Progress)
                    stop = false;
                    return
                end
                if ~isfinite(fraction)
                    fraction = 0;
                end
                stop = logical(options.Progress((k - 1 + fraction) / n));
                stopRequested = stopRequested || stop;
            end
        end

        function [result, p] = solveAt(plugin, params, names, values)
            %SOLVEAT Solve PLUGIN with inputs NAMES set to VALUES over
            %   PARAMS, as edits would set them: onParamChanged runs for each,
            %   then the requested values win and every input is validated.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                names (1,:) string
                values (1,:) double
            end
            p = params;
            for j = 1:numel(names)
                p.(names(j)) = values(j);
                p = plugin.onParamChanged(names(j), p);
            end
            for j = 1:numel(names)
                p.(names(j)) = values(j);
            end
            p = dlab.core.ParamSpec.validateAll(plugin.parameters(), p);
            result = plugin.solve(p);
        end

        function spec = numericInput(specs, name)
            %NUMERICINPUT The spec of input NAME, which must be a numeric
            %   model input (sweeps, maps, and optimization vary only these).
            spec = dlab.core.ParamSpec.find(specs, name);
            if ~ismember(spec.Type, ["double" "integer"]) || spec.Display
                error("dlab:sweep:parameter", "%s cannot be swept (only numeric model inputs can).", spec.Label);
            end
        end

        function T = toTable(S)
            %TOTABLE The swept value and every quantity, units in VariableUnits.
            names = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName([S.Parameter, S.Quantities]));
            T = array2table([S.Values, S.Data], VariableNames=names);
            T.Properties.VariableDescriptions = [S.Label, S.Quantities];
            T.Properties.VariableUnits = [S.Units, S.QuantityUnits];
            T.error = S.Errors;
        end

        function T = toLongTable(S)
            %TOLONGTABLE One row per value of each set-valued result:
            %   the swept value, Quantity, Value, and Units.
            rows = {};
            if isfield(S, "SetNames")
                for j = 1:numel(S.SetNames)
                    for k = 1:numel(S.Values)
                        v = S.SetData{k, j};
                        if ~isempty(v)
                            rows(end+1, :) = {repmat(S.Values(k), numel(v), 1), ...
                                repmat(S.SetNames(j), numel(v), 1), v(:), ...
                                repmat(S.SetUnits(j), numel(v), 1)}; %#ok<AGROW>
                        end
                    end
                end
            end
            name = matlab.lang.makeValidName(S.Parameter);
            if isempty(rows)
                T = table(zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
                    VariableNames=[name "Quantity" "Value" "Units"]);
            else
                T = table(vertcat(rows{:, 1}), vertcat(rows{:, 2}), vertcat(rows{:, 3}), vertcat(rows{:, 4}), ...
                    VariableNames=[name "Quantity" "Value" "Units"]);
            end
            T.Properties.VariableUnits = [S.Units "" "" ""];
        end

        function values = range(from, to, steps, options)
            %RANGE STEPS values from FROM to TO, evenly or log-spaced, and
            %   whole numbers only when Integer is true.
            arguments
                from (1,1) double {mustBeFinite}
                to (1,1) double {mustBeFinite}
                steps (1,1) double {mustBeInteger, mustBePositive}
                options.Log (1,1) logical = false
                options.Integer (1,1) logical = false
            end
            if options.Log
                if from <= 0 || to <= 0
                    error("dlab:sweep:log", "A logarithmic sweep needs positive limits.");
                end
                values = logspace(log10(from), log10(to), steps)';
            else
                values = linspace(from, to, steps)';
            end
            if options.Integer
                values = unique(round(values), "stable");
            end
        end
    end
end

function S = store(S, k, M)
% Add run k's metrics, growing the quantity list as new ones appear.
for row = 1:height(M)
    quantity = string(M.Quantity(row));
    column = find(S.Quantities == quantity, 1);
    if isempty(column)
        S.Quantities(end+1) = quantity;
        S.QuantityUnits(end+1) = string(M.Units(row));
        S.Data(:, end+1) = NaN;
        column = numel(S.Quantities);
    end
    S.Data(k, column) = M.Value(row);
end
end

function S = storeSets(S, k, D)
% Add run k's set-valued results, growing the list as new ones appear.
for row = 1:height(D)
    quantity = string(D.Quantity(row));
    column = find(S.SetNames == quantity, 1);
    if isempty(column)
        S.SetNames(end+1) = quantity;
        S.SetUnits(end+1) = string(D.Units(row));
        S.SetData(:, end+1) = {[]};
        column = numel(S.SetNames);
    end
    values = D.Values{row};
    S.SetData{k, column} = double(reshape(values(isfinite(values)), [], 1));
end
end
