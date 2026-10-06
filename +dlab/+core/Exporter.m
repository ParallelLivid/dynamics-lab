classdef Exporter
    %EXPORTER Write results and figures to files.

    methods (Static)
        function csv(file, T)
            %CSV Table to CSV; units go into the header ("t [s]").
            arguments
                file (1,1) string
                T table
            end
            names = string(T.Properties.VariableNames);
            units = string(T.Properties.VariableUnits);
            if numel(units) == numel(names)
                withUnits = units ~= "";
                names(withUnits) = names(withUnits) + " [" + units(withUnits) + "]";
            end
            T.Properties.VariableNames = names;
            writetable(T, file);
        end

        function mat(file, scenario, result, T, runs)
            %MAT Inputs, raw result, tabulated data, and provenance; plus
            %   the kept runs (Result, Params) when comparing.
            arguments
                file (1,1) string
                scenario (1,1) struct
                result
                T table
                runs struct = struct("Result", {}, "Params", {})
            end
            data = T;                % saved by name below
            metadata = struct("app", "Dynamics Lab", "version", dlab.version(), ...
                "matlab", version("-release"), "created", datetime("now"));
            if isempty(runs)
                save(file, "scenario", "result", "data", "metadata");
            else
                save(file, "scenario", "result", "data", "metadata", "runs");
            end
        end

        function plotPng(container, file, resolution)
            %PLOTPNG Graphics in CONTAINER (axes or the grid of a tab).
            arguments
                container (1,1)
                file (1,1) string
                resolution (1,1) double {mustBePositive} = 200
            end
            exportgraphics(container, file, Resolution=resolution, BackgroundColor="current");
        end

        function windowPng(fig, file)
            %WINDOWPNG The whole app window, controls included.
            arguments
                fig (1,1) matlab.ui.Figure
                file (1,1) string
            end
            exportapp(fig, file);
        end
    end
end
