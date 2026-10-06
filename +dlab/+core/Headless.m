classdef Headless
    %HEADLESS Simulators without the window: the engine behind dlab.run,
    %   dlab.sweep, and lessons. Inputs go through the same defaults,
    %   presets, scenario loading, coupled-input rules, and validation as
    %   the app, so a script gets exactly what the app would compute.

    methods (Static)
        function plugin = plugin(simulatorId, factories)
            %PLUGIN A new plugin instance for SIMULATORID.
            arguments
                simulatorId (1,1) string
                factories cell
            end
            known = strings(1, 0);
            for k = 1:numel(factories)
                plugin = factories{k}();
                if plugin.Id == simulatorId
                    return
                end
                known(end+1) = plugin.Id; %#ok<AGROW>
                delete(plugin);
            end
            error("dlab:unknownSimulator", "There is no simulator called ""%s"". Available: %s.", ...
                simulatorId, strjoin(known, ", "));
        end

        function params = params(plugin, overrides, options)
            %PARAMS Inputs for PLUGIN: defaults, or a preset or scenario
            %   file, then OVERRIDES (name/value cell) applied in order.
            %   Coupled inputs follow each override (picking an orbit's
            %   body loads its orbit), but explicit overrides always win.
            arguments
                plugin (1,1) dlab.core.Plugin
                overrides cell = {}
                options.Preset (1,1) string = ""
                options.Scenario (1,1) string = ""
            end
            if options.Preset ~= "" && options.Scenario ~= ""
                error("dlab:run:options", "Give a Preset or a Scenario, not both.");
            elseif options.Preset ~= ""
                params = plugin.presetParams(options.Preset);
            elseif options.Scenario ~= ""
                [params, ~, warnings] = dlab.core.ScenarioIO.load(options.Scenario, plugin);
                for w = warnings
                    warning("dlab:run:scenario", "%s", w);
                end
            else
                params = plugin.defaultParams();
            end
            if mod(numel(overrides), 2) ~= 0
                error("dlab:run:overrides", "Inputs must come in name/value pairs.");
            end
            names = string(overrides(1:2:end));
            values = overrides(2:2:end);
            known = string(fieldnames(params))';
            unknown = setdiff(names, known);
            if ~isempty(unknown)
                error("dlab:run:unknownParameter", "%s has no input ""%s"". Inputs: %s.", ...
                    plugin.Title, unknown(1), strjoin(known, ", "));
            end
            for k = 1:numel(names)
                params.(names(k)) = values{k};
                params = plugin.onParamChanged(names(k), params);
            end
            for k = 1:numel(names)
                params.(names(k)) = values{k};
            end
            params = dlab.core.ParamSpec.validateAll(plugin.parameters(), params);
        end

        function out = solve(plugin, params)
            %SOLVE Solve and package everything a script needs.
            result = plugin.solve(params);
            out = struct( ...
                "Simulator", plugin.Id, ...
                "Params", params, ...
                "Result", {result}, ...
                "Data", plugin.exportTable(result), ...
                "Summary", plugin.summaryTable(result), ...
                "Metrics", plugin.metrics(result));
        end
    end
end
