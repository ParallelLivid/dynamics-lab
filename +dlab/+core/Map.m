classdef Map
    %MAP Two-parameter maps: solve over a grid of two inputs and collect
    %   every run's metrics (the engine behind the Map tab).
    %
    %       M = dlab.core.Map.run(plugin, params, "v0", 10:5:50, "theta", 15:5:75);
    %       T = dlab.core.Map.toTable(M);      % one row per grid point
    %
    %   M is a struct: Parameters, Labels, and Units (1×2 string: X then
    %   Y), XValues and YValues (columns), Quantities and QuantityUnits
    %   (string rows), Data (numel(YValues) × numel(XValues) × numel(Quantities),
    %   NaN where a run failed or lacked that quantity), Errors (a string
    %   grid of the same shape, "" for runs that solved), Cancelled, and,
    %   for set-valued results (Plugin.distributions), SetNames, SetUnits,
    %   and SetCounts (Y × X × sets: the number of distinct values, so a
    %   period-doubling map shows 1, 2, 4, …).

    properties (Constant)
        MaxPoints = 1600        % a 40 × 40 grid
        DistinctTolerance = 1e-3  % values closer than this (relative to the largest) count once
    end

    methods (Static)
        function M = run(plugin, params, xName, xValues, yName, yValues, options)
            %RUN Solve PLUGIN at each (x, y) of the grid; other inputs as PARAMS.
            %   Option Progress, @(fraction) stop, as in dlab.core.Sweep.run.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                xName (1,1) string
                xValues (:,1) double {mustBeFinite}
                yName (1,1) string
                yValues (:,1) double {mustBeFinite}
                options.Progress = []
            end
            specs = plugin.parameters();
            xSpec = dlab.core.Sweep.numericInput(specs, xName);
            ySpec = dlab.core.Sweep.numericInput(specs, yName);
            if xName == yName
                error("dlab:map:sameInput", "Choose two different inputs for a map.");
            end
            nx = numel(xValues);
            ny = numel(yValues);
            if nx < 2 || ny < 2 || nx * ny > dlab.core.Map.MaxPoints
                error("dlab:map:steps", "A map takes 2 or more values of each input and at most %d runs.", ...
                    dlab.core.Map.MaxPoints);
            end
            [X, Y] = meshgrid(xValues, yValues);
            P = dlab.core.Sweep.runPoints(plugin, params, [xName yName], [X(:) Y(:)], ...
                Progress=options.Progress);
            q = numel(P.Quantities);
            s = numel(P.SetNames);
            counts = zeros(ny * nx, s);
            for k = 1:numel(P.SetData)
                counts(k) = distinctCount(P.SetData{k});
            end
            solved = P.Errors == "" & any(isfinite(P.Data), 2);
            counts(~solved, :) = NaN;      % failed or never reached (cancelled)
            M = struct("Parameters", [xName yName], "Labels", [xSpec.Label ySpec.Label], ...
                "Units", [xSpec.Units ySpec.Units], "XValues", xValues, "YValues", yValues, ...
                "Quantities", P.Quantities, "QuantityUnits", P.QuantityUnits, ...
                "Data", reshape(P.Data, ny, nx, q), "Errors", reshape(P.Errors, ny, nx), ...
                "Cancelled", P.Cancelled, "SetNames", P.SetNames, "SetUnits", P.SetUnits, ...
                "SetCounts", reshape(counts, ny, nx, s));
        end

        function [z, label, units] = layer(M, name)
            %LAYER The Y × X grid of quantity NAME, or of the distinct-value
            %   count of set-valued result NAME, with its label and units.
            column = find(M.Quantities == name, 1);
            if ~isempty(column)
                z = M.Data(:, :, column);
                label = name;
                units = M.QuantityUnits(column);
                return
            end
            column = find(M.SetNames == name, 1);
            if isempty(column)
                error("dlab:map:quantity", "The map has no result ""%s"".", name);
            end
            z = M.SetCounts(:, :, column);
            label = name + " (distinct values)";
            units = "";
        end

        function T = toTable(M)
            %TOTABLE One row per grid point: both inputs, every quantity and
            %   distinct-value count, and the run's error ("" if it solved).
            [X, Y] = meshgrid(M.XValues, M.YValues);
            n = numel(X);
            data = [X(:) Y(:) reshape(M.Data, n, []) reshape(M.SetCounts, n, [])];
            descriptions = [M.Labels, M.Quantities, M.SetNames + " (distinct values)"];
            names = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName([M.Parameters, ...
                M.Quantities, M.SetNames + "_distinct"]));
            T = array2table(data, VariableNames=names);
            T.Properties.VariableDescriptions = descriptions;
            T.Properties.VariableUnits = [M.Units, M.QuantityUnits, repmat("", 1, numel(M.SetNames))];
            T.error = M.Errors(:);
        end
    end
end

function n = distinctCount(values)
% Distinct values, to DistinctTolerance of the largest magnitude.
values = values(isfinite(values));
if isempty(values)
    n = 0;
    return
end
n = numel(uniquetol(values, dlab.core.Map.DistinctTolerance));
end
