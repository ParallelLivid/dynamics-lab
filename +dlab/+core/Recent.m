classdef Recent
    %RECENT What the Home screen offers to pick up again: recently used
    %   simulators (with the inputs they were left with) and recently saved
    %   or loaded scenario files. Kept in settings.json and in
    %   <user data>/session/<id>.json, so it lasts across launches.

    properties (Constant)
        MaxSimulators = 3
        MaxScenarios = 5
    end

    methods (Static)
        function noteSimulator(plugin, params, preset)
            %NOTESIMULATOR PLUGIN was just left with PARAMS shown.
            try
                dlab.core.ScenarioIO.save(dlab.core.Recent.sessionFile(plugin.Id), plugin, params, preset);
            catch
                return          % unwritable user data must never block leaving a simulator
            end
            list = dlab.core.Recent.read("recent", ["id" "time"]);
            list = list(string({list.id}) ~= plugin.Id);
            list = [struct("id", plugin.Id, "time", stamp()), list];
            dlab.core.Recent.write("recent", list(1:min(end, 10)));
        end

        function list = simulators(knownIds)
            %SIMULATORS Most recent first: struct array (id, time as datetime).
            arguments
                knownIds (1,:) string = string.empty(1, 0)
            end
            list = dlab.core.Recent.read("recent", ["id" "time"]);
            if ~isempty(knownIds)
                list = list(ismember(string({list.id}), knownIds));
            end
            list = list(arrayfun(@(e) isfile(dlab.core.Recent.sessionFile(e.id)), list));
            list = withTimes(list(1:min(end, dlab.core.Recent.MaxSimulators)));
        end

        function noteView(simulatorId, state)
            %NOTEVIEW Remember the tab and analysis set-ups (SimulatorView.viewState)
            %   SIMULATORID was left with, for the next launch.
            try
                save(dlab.core.Recent.viewFile(simulatorId), "state");
            catch
                % unwritable user data must never block leaving a simulator
            end
        end

        function state = lastView(simulatorId)
            %LASTVIEW What noteView kept ([] if nothing or unreadable).
            state = [];
            file = dlab.core.Recent.viewFile(simulatorId);
            if ~isfile(file)
                return
            end
            try
                loaded = load(file, "state");
                if isfield(loaded.state, "Tab") && isfield(loaded.state, "Analysis")
                    state = loaded.state;
                end
            catch
                state = [];
            end
        end

        function [params, preset] = lastInputs(plugin)
            %LASTINPUTS The inputs PLUGIN was left with ([] if unknown or unreadable).
            params = [];
            preset = "Custom";
            file = dlab.core.Recent.sessionFile(plugin.Id);
            if ~isfile(file)
                return
            end
            try
                [params, preset] = dlab.core.ScenarioIO.load(file, plugin);
            catch
                params = [];
            end
        end

        function noteScenario(file, simulatorId)
            %NOTESCENARIO FILE was just saved or loaded.
            list = dlab.core.Recent.read("recentScenarios", ["file" "simulator" "time"]);
            list = list(string({list.file}) ~= file);
            list = [struct("file", string(file), "simulator", string(simulatorId), "time", stamp()), list];
            dlab.core.Recent.write("recentScenarios", list(1:min(end, 20)));
        end

        function list = scenarios(knownIds)
            %SCENARIOS Most recent first, existing files only: struct array
            %   (file, simulator, time as datetime).
            arguments
                knownIds (1,:) string = string.empty(1, 0)
            end
            list = dlab.core.Recent.read("recentScenarios", ["file" "simulator" "time"]);
            list = list(arrayfun(@(e) isfile(e.file), list));
            if ~isempty(knownIds)
                list = list(ismember(string({list.simulator}), knownIds));
            end
            list = withTimes(list(1:min(end, dlab.core.Recent.MaxScenarios)));
        end

        function file = sessionFile(simulatorId)
            file = fullfile(dlab.core.Paths.session(), simulatorId + ".json");
        end

        function file = viewFile(simulatorId)
            file = fullfile(dlab.core.Paths.session(), simulatorId + "-view.mat");
        end

        function text = ago(when)
            %AGO "just now", "5 min ago", "3 h ago", "2 days ago", or a date.
            elapsed = max(0, floor(minutes(datetime("now") - when)));
            if elapsed < 1
                text = "just now";
            elseif elapsed < 60
                text = sprintf("%d min ago", elapsed);
            elseif elapsed < 48 * 60
                text = sprintf("%d h ago", floor(elapsed / 60));
            elseif elapsed < 14 * 24 * 60
                text = sprintf("%d days ago", floor(elapsed / 1440));
            else
                text = string(datetime(when, Format="d MMM yyyy"));
            end
            text = string(text);
        end
    end

    methods (Static, Access = private)
        function list = read(name, fields)
            % A struct array with string FIELDS; anything malformed is dropped.
            raw = dlab.core.Settings.get(name, []);
            template = cell2struct(repmat({""}, numel(fields), 1), cellstr(fields), 1);
            list = repmat(template, 1, 0);
            if iscell(raw)
                raw = [raw{:}];
            end
            if ~isstruct(raw) || ~all(isfield(raw, cellstr(fields)))
                return
            end
            for entry = reshape(raw, 1, [])
                item = template;
                for f = fields
                    item.(f) = string(entry.(f));
                end
                list(end+1) = item; %#ok<AGROW>
            end
        end

        function write(name, list)
            dlab.core.Settings.set(name, list);
        end
    end
end

function text = stamp()
text = string(datetime("now", Format="yyyy-MM-dd'T'HH:mm:ss"));
end

function list = withTimes(list)
for k = 1:numel(list)
    try
        list(k).time = datetime(list(k).time, InputFormat="yyyy-MM-dd'T'HH:mm:ss");
    catch
        list(k).time = NaT;
    end
end
end
