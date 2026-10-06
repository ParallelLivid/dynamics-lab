classdef ScenarioIO
    %SCENARIOIO Save and load simulator inputs as JSON scenario files.
    %
    %   {
    %     "format": "dynamicslab-scenario", "formatVersion": 1,
    %     "simulator": "pendulum", "schemaVersion": 1,
    %     "preset": "Custom", "savedWith": "Dynamics Lab 0.1.0",
    %     "params": { "L": 1, ... }
    %   }
    %
    %   Loading is forgiving: missing fields take defaults and unknown or
    %   invalid fields are dropped with a warning, so an old file still
    %   opens. A file from a newer schema, or for another simulator, is
    %   rejected with an identifiable error the shell can act on.

    properties (Constant)
        Format = "dynamicslab-scenario"
        FormatVersion = 1
    end

    methods (Static)
        function s = toStruct(plugin, params, preset)
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                preset (1,1) string = "Custom"
            end
            s = struct( ...
                "format", dlab.core.ScenarioIO.Format, ...
                "formatVersion", dlab.core.ScenarioIO.FormatVersion, ...
                "simulator", plugin.Id, ...
                "schemaVersion", plugin.SchemaVersion, ...
                "preset", preset, ...
                "savedWith", "Dynamics Lab " + dlab.version(), ...
                "params", plugin.paramsToJson(params));
        end

        function save(file, plugin, params, preset)
            arguments
                file (1,1) string
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                preset (1,1) string = "Custom"
            end
            s = dlab.core.ScenarioIO.toStruct(plugin, params, preset);
            fid = fopen(file, "w", "n", "UTF-8");
            if fid < 0
                error("dlab:scenario:write", "Cannot write scenario file ""%s"".", file);
            end
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(s, PrettyPrint=true), "char");
        end

        function s = read(file)
            %READ Decode and check the envelope, without interpreting params.
            arguments
                file (1,1) string
            end
            if ~isfile(file)
                error("dlab:scenario:missing", "Scenario file ""%s"" does not exist.", file);
            end
            try
                s = jsondecode(fileread(file, Encoding="UTF-8"));
            catch
                error("dlab:scenario:notJson", """%s"" is not a valid JSON file.", file);
            end
            required = ["format" "formatVersion" "simulator" "schemaVersion" "params"];
            if ~isstruct(s) || ~all(isfield(s, required)) || string(s.format) ~= dlab.core.ScenarioIO.Format
                error("dlab:scenario:format", """%s"" is not a Dynamics Lab scenario.", file);
            end
            if s.formatVersion > dlab.core.ScenarioIO.FormatVersion
                error("dlab:scenario:newerFormat", ...
                    "This scenario was saved by a newer version of Dynamics Lab.");
            end
            s.simulator = string(s.simulator);
            if isfield(s, "preset")
                s.preset = string(s.preset);
            else
                s.preset = "Custom";
            end
        end

        function [params, preset, warnings] = load(file, plugin)
            %LOAD Read FILE and return PLUGIN-ready params.
            arguments
                file (1,1) string
                plugin (1,1) dlab.core.Plugin
            end
            s = dlab.core.ScenarioIO.read(file);
            [params, warnings] = dlab.core.ScenarioIO.fromStruct(s, plugin);
            preset = s.preset;
        end

        function [params, warnings] = fromStruct(s, plugin)
            if s.simulator ~= plugin.Id
                error("dlab:scenario:wrongSimulator", ...
                    "This scenario is for the ""%s"" simulator, not ""%s"".", s.simulator, plugin.Id);
            end
            if s.schemaVersion > plugin.SchemaVersion
                error("dlab:scenario:newerSchema", ...
                    "This scenario was saved by a newer version of the %s simulator.", plugin.Title);
            end

            raw = s.params;
            if ~isstruct(raw)
                raw = struct();
            end
            raw = plugin.paramsFromJson(raw);
            if s.schemaVersion < plugin.SchemaVersion
                raw = plugin.migrate(raw, s.schemaVersion);
            end

            specs = plugin.parameters();
            params = plugin.defaultParams();
            warnings = strings(0);
            % Inputs without a spec (e.g. the truss model tables) are taken
            % as paramsFromJson left them; the plugin validates them on solve.
            for name = setdiff(string(fieldnames(params)), [specs.Name])'
                if isfield(raw, name)
                    params.(name) = raw.(name);
                else
                    warnings(end+1) = """" + name + """ was missing; using the default."; %#ok<AGROW>
                end
            end
            for spec = specs(:)'
                if ~isfield(raw, spec.Name)
                    warnings(end+1) = spec.Label + " was missing; using the default."; %#ok<AGROW>
                    continue
                end
                [value, ok, message] = spec.coerce(raw.(spec.Name));
                if ok
                    params.(spec.Name) = value;
                else
                    warnings(end+1) = spec.Label + " " + message + "; using the default."; %#ok<AGROW>
                end
            end
            extra = setdiff(string(fieldnames(raw)), string(fieldnames(params)));
            for name = extra(:)'
                warnings(end+1) = "Ignored unknown parameter """ + name + """."; %#ok<AGROW>
            end
        end
    end
end
