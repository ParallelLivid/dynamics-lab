classdef Session < handle
    %SESSION Per-simulator state kept while the app is open.
    %   Leaving a simulator (Home, or a theme switch) stores its inputs,
    %   preset, last result, and playback time here; reopening restores
    %   them, so views can be rebuilt from scratch at any time.

    properties (Access = private)
        States = dictionary(string.empty, cell.empty)
    end

    methods
        function put(obj, id, state)
            arguments
                obj
                id (1,1) string
                state (1,1) struct
            end
            obj.States(id) = {state};
        end

        function state = get(obj, id)
            %GET The stored state struct, or [] if none.
            if obj.has(id)
                state = obj.States{id};
            else
                state = [];
            end
        end

        function tf = has(obj, id)
            tf = isConfigured(obj.States) && isKey(obj.States, id);
        end

        function remove(obj, id)
            if obj.has(id)
                obj.States(id) = [];
            end
        end
    end

    methods (Static)
        function state = newState(options)
            %NEWSTATE The struct SimulatorView stores and restores.
            %   Params      inputs currently shown
            %   Preset      preset name shown ("Defaults", "Custom", ...)
            %   Result      last solve result ([] if none)
            %   RunParams   inputs that produced Result
            %   Stale       inputs changed since Result was computed
            %   PlaybackTime  animation position (NaN if none)
            %   History     undo / redo stacks (dlab.core.History.snapshot, or [])
            %   Analysis    Custom plot selection and Sweep tab state ([] if none)
            %   KeepRuns    "Keep previous runs" is ticked
            %   Runs        kept earlier runs (struct array: Result, Params)
            %   Lesson      open lesson (struct: Id, Step, Passed) or []
            %   Tab         the selected output tab ("" for the first)
            arguments
                options.Params (1,1) struct = struct()
                options.Preset (1,1) string = "Defaults"
                options.Result = []
                options.RunParams (1,1) struct = struct()
                options.Stale (1,1) logical = false
                options.PlaybackTime (1,1) double = NaN
                options.History = []
                options.Analysis = []
                options.KeepRuns (1,1) logical = false
                options.Runs struct = struct("Result", {}, "Params", {})
                options.Lesson = []
                options.Tab (1,1) string = ""
            end
            state = struct("Params", options.Params, "Preset", options.Preset, ...
                "Result", {options.Result}, "RunParams", options.RunParams, ...
                "Stale", options.Stale, "PlaybackTime", options.PlaybackTime, ...
                "History", {options.History}, "Analysis", {options.Analysis}, ...
                "KeepRuns", options.KeepRuns, "Runs", {options.Runs}, "Lesson", {options.Lesson}, ...
                "Tab", options.Tab);
        end
    end
end
