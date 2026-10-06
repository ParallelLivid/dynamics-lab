classdef SimulatorView < handle
    %SIMULATORVIEW The layout every simulator shares.
    %
    %   ┌ header slot: Preset [▾]  ↶ ↷  Save  Load  Export ▾ ────────────┐
    %   │  (a lesson, when open, adds a column on the right)               │
    %   │ parameters (scrollable) │ [Animation] [plot tabs…] [Summary] │
    %   │                         │ [Runs] (kept runs, when any)       │
    %   │ plugin extra controls   │ [Analyze]: [Custom plot] [Sweep]   │
    %   │ ☐ Keep previous runs  ⟷ │   [Map] [Optimize] [Uncertainty]   │
    %   │                         │   [Fit] [Modes] [Bode]             │
    %   │ [Reset]        [▶ Run]  │  playback bar (time-domain only)   │
    %   └─────────────────────────┴────────────────────────────────────┘
    %
    %   The view is disposable: close() stores everything in the Session
    %   and a new view restores it (Home and back, theme changes).
    %
    %   The input panel is wider for simulators with table inputs; the
    %   Wider ▸ / ◂ Narrower button switches, remembered per simulator.
    %
    %   Long work (solving, sweeps, video export) runs as a busy task: the
    %   Run button becomes Cancel, Esc cancels too, and the plugin reports
    %   progress through Plugin.progress, which also delivers the cancel.

    properties (SetAccess = private)
        Plugin
        Inputs              % dlab.core.ParamPanel or plugin-built panel
        Tabs                % uitabgroup
        Playback            % dlab.core.PlaybackController ([] for static plugins)
        PlaybackBar
        Result = []
        RunParams struct = struct()
        Preset (1,1) string = "Defaults"
        IsStale (1,1) logical = false
        RunButton
        ResetButton
        PresetDropdown
        UndoButton
        RedoButton
        IsBusy (1,1) logical = false
        History                     % dlab.core.History of input states
        KeepRuns (1,1) logical = false
        Runs = struct("Result", {}, "Params", {})   % kept earlier runs, oldest first
        LessonPanel = []                            % dlab.core.LessonPanel while a lesson is open
        WideInputs (1,1) logical = false            % the wider input panel (setWideInputs)
    end

    properties (Access = private)
        Shell
        Grid
        Containers          % dictionary tab title -> {uigridlayout}
        TabTitles (1,:) string = string.empty(1, 0)
        SummaryTab
        SummaryTable
        AnimationGrid
        ExportMenu
        HeaderControls = gobjects(0)
        Listeners = event.listener.empty
        LastState struct = struct()     % inputs before the next edit (for undo)
        CancelRequested (1,1) logical = false
        Redrawing (1,1) logical = false     % in showResult: no frames (its handles are being rebuilt)
        PendingTab (1,1) string = ""    % a tab the next run's outputs will add (applySetup)
        PendingBode = strings(1, 0)     % input and output the Bode tab shows next (applySetup)
        BusyLabel (1,1) string = ""
        BusyClock = []
        LastProgressDraw (1,1) double = -Inf
        PlotBuilder                     % dlab.core.PlotBuilder ("Custom plot" tab)
        SweepPanel                      % dlab.core.SweepPanel ("Sweep" tab, [] if nothing to sweep)
        MapPanel                        % dlab.core.MapPanel ("Map" tab, [] with fewer than two inputs)
        OptimizePanel                   % dlab.core.OptimizePanel ("Optimize" tab, [] if nothing to vary)
        UncertaintyPanel                % dlab.core.UncertaintyPanel ("Uncertainty" tab, [] if nothing to vary)
        FitPanel                        % dlab.core.FitPanel ("Fit" tab, [] if nothing to fit)
        MeasuredData = []               % the imported data set (dlab.core.MeasuredData.read), kept across tab rebuilds
        AnalysisGroup                   % the tab group inside the Analyze tab (one tab per AnalysisTabs title)
        LazyGrids = struct()            % tab grids of the panels built when first needed (analysisPanel)
        LazyStates = struct()           % their saved states, until they are built
        ModesPanel                      % dlab.core.ModesPanel ("Modes" tab, [] without linearization)
        FrequencyPanel                  % dlab.core.FrequencyPanel ("Bode" tab, [] without inputs)
        SavedAnalysis = []              % analysis state to restore into rebuilt tabs
        KeepCheckbox
        WidthButton                     % Wider ▸ / ◂ Narrower
        RunsTab
        RunsTable
    end

    properties (Constant, Access = private)
        DefaultsKey = "defaults"
        CustomKey = "custom"
    end

    properties (Constant)
        AnalysisTabs = ["Custom plot" "Sweep" "Map" "Optimize" "Uncertainty" "Fit" "Modes" "Bode"]
        ShellTabs = ["Animation" "Summary" "Runs" "Analyze" "Custom plot" "Sweep" "Map" "Optimize" "Uncertainty" ...
            "Fit" "Modes" "Bode"]   % titles plugins may not use
        MaxKeptRuns = 12
        InputWidths = [340 560]         % the input panel, narrow and wide (before text scaling)
        SummaryColumns = {'5x', '4x', '2x'}         % Quantity, Value, Units
        WideInputsSetting = "wideInputs"
    end

    methods
        function obj = SimulatorView(parent, shell, plugin, state)
            arguments
                parent
                shell (1,1) dlab.core.Shell
                plugin (1,1) dlab.core.Plugin
                state = []
            end
            obj.Shell = shell;
            obj.Plugin = plugin;
            if isempty(state)
                state = dlab.core.Session.newState(Params=plugin.defaultParams());
            end
            obj.Preset = state.Preset;
            obj.History = dlab.core.History(state.History);
            obj.SavedAnalysis = state.Analysis;
            obj.KeepRuns = state.KeepRuns;
            obj.Runs = state.Runs;
            obj.Containers = dictionary(string.empty, cell.empty);

            t = shell.Theme;
            obj.WideInputs = wideInputsSetting(plugin);
            obj.Grid = uigridlayout(parent, [1 2], ColumnWidth={obj.inputWidth(), "1x"}, ...
                Padding=[t.Spacing.sm t.Spacing.sm t.Spacing.sm t.Spacing.sm], ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Background);
            obj.buildHeaderControls(t);
            obj.buildLeftColumn(t, state.Params);
            if ismethod(obj.Inputs, "setWidth")
                obj.Inputs.setWidth(obj.inputWidth());
            end
            obj.Listeners(end+1) = listener(plugin, "InputsRequested", ...
                @(~, evt) shell.safeCall(@() obj.applyInputs(evt.Changes, evt.Label), evt.Label));
            obj.Listeners(end+1) = listener(plugin, "StatusMessage", ...
                @(~, evt) shell.setStatus(evt.Message, evt.Level));
            plugin.InputsFcn = @() obj.params();
            plugin.BusyFcn = @() isvalid(obj) && obj.IsBusy;
            obj.Tabs = uitabgroup(obj.Grid, Tag="dlab.tabs", ...
                SelectionChangedFcn=@(~, event) obj.Shell.safeCall(@() obj.tabSelected(event.NewValue), "Tab"));
            obj.Tabs.Layout.Column = 2;
            obj.buildOutputs(state.Params);

            if ~isempty(state.Result)
                obj.displayResult(state.Result, state.RunParams);
                obj.setStale(state.Stale);
                if ~isempty(obj.Playback) && ~isnan(state.PlaybackTime)
                    obj.Playback.seek(state.PlaybackTime);
                end
            elseif plugin.kind() == "static"
                plugin.previewInputs(state.Params);
            end
            obj.inputsSettled();
            if isfield(state, "Tab") && state.Tab ~= ""
                obj.reopenTab(state.Tab);
            end
            if ~isempty(state.Lesson)
                try
                    lesson = dlab.core.Lesson.load(state.Lesson.Id);
                    if dlab.core.Lesson.stepSimulator(lesson, state.Lesson.Step) == plugin.Id
                        obj.startLesson(lesson, state.Lesson);   % not if the lesson has moved on elsewhere
                    end
                catch
                    % The lesson file is gone or broken; carry on without it.
                end
            end
        end

        function params = params(obj)
            %PARAMS Inputs currently shown.
            params = obj.Inputs.values();
        end

        function run(obj)
            %RUN Validate inputs, solve, and show the result. While a task
            %   is running, the Run button is Cancel, so this cancels it.
            if obj.IsBusy
                obj.cancel();
                return
            end
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            if obj.KeepRuns && ~isempty(obj.Result) && numel(obj.Runs) >= obj.MaxKeptRuns
                error("dlab:compareLimit", "Up to %d runs can be kept. Press Reset or untick " + ...
                    "Keep previous runs to start a new set.", obj.MaxKeptRuns);
            end
            obj.runTask("Running…", @() obj.solveAndShow(params));
        end

        function setWideInputs(obj, wide)
            %SETWIDEINPUTS Show the wider input panel (tables have room) or
            %   the narrow one (more room for the plots); remembered for this
            %   simulator.
            obj.WideInputs = wide;
            obj.Grid.ColumnWidth{1} = obj.inputWidth();
            obj.WidthButton.Text = widthButtonText(wide);
            if ismethod(obj.Inputs, "setWidth")
                obj.Inputs.setWidth(obj.inputWidth());
            end
            saved = dlab.core.Settings.get(obj.WideInputsSetting, struct());
            if ~isstruct(saved)
                saved = struct();
            end
            saved.(obj.Plugin.Id) = wide;
            dlab.core.Settings.set(obj.WideInputsSetting, saved);
        end

        function setKeepRuns(obj, keep)
            %SETKEEPRUNS Keep earlier runs for comparison; turning it off
            %   drops the kept runs at once.
            obj.KeepRuns = keep;
            obj.KeepCheckbox.Value = keep;
            if ~keep && ~isempty(obj.Runs)
                obj.Runs = obj.Runs([]);
                obj.refreshComparison();
                obj.Shell.setStatus("Cleared the kept runs.");
            end
        end

        function applyInputs(obj, changes, label)
            %APPLYINPUTS Set some inputs on the plugin's behalf
            %   (Plugin.requestInputs). Each change goes through
            %   onParamChanged like a user edit (dependent inputs follow;
            %   the requested values win). Validated before anything is
            %   shown, so a bad request changes nothing; then one undo step
            %   that marks results stale (and the preset Custom).
            arguments
                obj
                changes (1,1) struct
                label (1,1) string = "Inputs"
            end
            if obj.IsBusy
                obj.Shell.setStatus(label + ": wait for the current task to finish.", "warning");
                return
            end
            before = obj.params();
            params = before;
            names = string(fieldnames(changes))';
            for name = names
                if ~isfield(params, name)
                    error("dlab:inputs:unknown", "%s: there is no input named ""%s"".", label, name);
                end
                params.(name) = changes.(name);
                params = obj.Plugin.onParamChanged(name, params);
            end
            for name = names
                params.(name) = changes.(name);      % what was asked for, over any adjustment
            end
            specs = obj.Plugin.parameters();
            params = dlab.core.ParamSpec.validateAll(specs, params);
            changed = changedFields(before, params);
            if isempty(changed)
                obj.Shell.setStatus(label + ": no change.");
                return
            end
            obj.History.record(obj.LastState);
            settle = onCleanup(@() obj.inputsSettled());
            obj.Inputs.setValues(params);
            isSpec = ismember(changed, [specs.Name]);
            displayOnly = all(isSpec) && all(arrayfun(@(name) ...
                dlab.core.ParamSpec.find(specs, name).Display, changed));
            if displayOnly
                obj.redisplay(obj.params());
            else
                marksCustom = ~all(isSpec) || any(arrayfun(@(name) ...
                    dlab.core.ParamSpec.find(specs, name).MarksCustom, changed(isSpec)));
                if marksCustom
                    obj.Preset = "Custom";
                    obj.selectPreset(obj.CustomKey);
                end
                obj.updateStale();
                if obj.Plugin.kind() == "static"
                    obj.Plugin.previewInputs(obj.params());
                end
            end
            obj.Shell.setStatus(label + obj.describeChange(before, params));
        end

        function cancel(obj)
            %CANCEL Stop the running task at its next progress report.
            if obj.IsBusy
                obj.CancelRequested = true;
                obj.Shell.setStatus("Cancelling…", "warning");
            end
        end

        function [result, ok] = solveCancellable(obj, params)
            %SOLVECANCELLABLE Solve PARAMS with progress and cancellation.
            %   OK is false (and RESULT []) when the user cancelled. Errors
            %   from the plugin are rethrown unless the run was cancelled.
            plugin = obj.Plugin;
            plugin.ProgressFcn = @(fraction) obj.onProgress(fraction);
            restore = onCleanup(@() clearProgress(plugin));
            result = [];
            try
                result = plugin.solve(params);
            catch ME
                if ~isvalid(obj) || ~obj.CancelRequested
                    rethrow(ME);
                end
            end
            ok = isvalid(obj) && ~obj.CancelRequested;
            if ~ok
                result = [];
            end
        end

        function runTask(obj, label, work)
            %RUNTASK Run WORK() as a cancellable busy task labelled LABEL.
            shell = obj.Shell;
            obj.beginTask(label);
            failure = [];
            try
                work();
            catch ME
                failure = ME;
            end
            if isvalid(obj)
                obj.endTask();
            end
            if shell.PendingClose
                shell.close();         % the window was closed during the task
                return
            end
            if ~isempty(failure)
                rethrow(failure);
            end
        end

        function stop = onProgress(obj, fraction)
            %ONPROGRESS Progress from the running task; true = stop now.
            if ~isvalid(obj)
                stop = true;
                return
            end
            elapsed = toc(obj.BusyClock);
            if elapsed - obj.LastProgressDraw >= 0.1 && ~obj.CancelRequested
                obj.LastProgressDraw = elapsed;
                message = obj.BusyLabel;
                if isfinite(fraction)
                    message = message + sprintf(" %d %%", round(100 * min(max(fraction, 0), 1)));
                end
                obj.Shell.setStatus(message + "   ·   Esc to cancel");
                drawnow limitrate   % lets a Cancel click or Esc run now (a full drawnow costs ~60 ms)
                if ~isvalid(obj)
                    stop = true;
                    return
                end
            end
            stop = obj.CancelRequested;
        end

        function undo(obj)
            %UNDO Go back to the inputs before the last edit.
            previous = obj.History.undo(obj.currentState());
            if isempty(previous)
                obj.Shell.setStatus("Nothing to undo.");
                return
            end
            changed = obj.describeChange(obj.params(), previous.Params);
            obj.restoreState(previous);
            obj.Shell.setStatus("Undo" + changed);
        end

        function redo(obj)
            %REDO Re-apply the edit undone last.
            next = obj.History.redo(obj.currentState());
            if isempty(next)
                obj.Shell.setStatus("Nothing to redo.");
                return
            end
            changed = obj.describeChange(obj.params(), next.Params);
            obj.restoreState(next);
            obj.Shell.setStatus("Redo" + changed);
        end

        function handled = handleKey(obj, key, ctrl, shift, focus)
            %HANDLEKEY Keyboard shortcuts (see dlab.core.Shell.ShortcutHelp).
            %   FOCUS is "text" while a field has focus (its own keys win),
            %   "button" for buttons and checkboxes, otherwise "".
            handled = true;
            free = focus == "";
            hasPlayback = ~isempty(obj.Playback) && ~isempty(obj.Result);
            if (ctrl && key == "r") || key == "f5"
                obj.run();
            elseif ctrl && key == "s"
                obj.saveScenario();
            elseif ctrl && key == "o"
                obj.loadScenario();
            elseif ctrl && key == "z" && ~shift && focus ~= "text"
                obj.undo();
            elseif ctrl && (key == "y" || (key == "z" && shift)) && focus ~= "text"
                obj.redo();
            elseif hasPlayback && free && ~ctrl && key == "space"
                obj.Playback.toggle();
            elseif hasPlayback && free && ~ctrl && ismember(key, ["leftarrow" "rightarrow"])
                frames = 1 + 9 * shift;
                step = frames * dlab.core.PlaybackController.FramePeriod * obj.Playback.Speed ...
                    * obj.Playback.TimeScale;
                if key == "leftarrow"
                    step = -step;
                end
                obj.Playback.pause();
                obj.Playback.seek(obj.Playback.Time + step);
            elseif hasPlayback && free && ~ctrl && key == "home"
                obj.Playback.restart();
            else
                handled = false;
            end
        end
    end

    methods (Access = private)
        function state = lessonSnapshot(obj)
            state = [];
            if ~isempty(obj.LessonPanel) && isvalid(obj.LessonPanel)
                state = obj.LessonPanel.snapshot();
            end
        end

        function writeAnimation(obj, format, file, maxFrames)
            previous = obj.Tabs.SelectedTab;
            time = obj.Playback.Time;
            obj.selectTab("Animation");          % frames are captured from the screen
            restore = onCleanup(@() obj.afterRecording(previous, time));
            ax = findall(obj.AnimationGrid, Type="axes");
            info = dlab.core.AnimationExporter.write(file, format, @(t) obj.Plugin.drawFrame(t), ax, ...
                obj.Playback.StartTime, obj.Playback.EndTime, ...
                TimeScale=obj.Playback.TimeScale * obj.Playback.Speed, MaxFrames=maxFrames, ...
                Progress=@(f) obj.onProgress(f));
            if info.Cancelled
                obj.Shell.setStatus("Animation export cancelled.", "warning");
                return
            end
            message = sprintf("Exported %s (%d frames at %g fps", fileName(file, true), info.Frames, info.FrameRate);
            if info.Capped
                message = message + ", sped up to keep the file small";
            end
            obj.Shell.setStatus(message + ")", "success");
        end

        function afterRecording(obj, tab, time)
            if isvalid(obj) && isvalid(tab)
                obj.Tabs.SelectedTab = tab;
                obj.Playback.seek(time);
            end
        end

        function sweepAndShow(obj, name, values, params)
            panel = obj.SweepPanel;
            panel.setRunning(true);
            restore = onCleanup(@() setRunningIfValid(panel));
            S = dlab.core.Sweep.run(obj.Plugin, params, name, values, Progress=@(f) obj.onProgress(f));
            if ~isvalid(obj)
                return
            end
            panel.show(S);
            failed = S.Errors(S.Errors ~= "");
            if S.Cancelled
                obj.Shell.setStatus(sprintf("Sweep cancelled after %d of %d runs.", ...
                    nnz(any(isfinite(S.Data), 2)), numel(values)), "warning");
            elseif ~isempty(failed)
                obj.Shell.setStatus(sprintf("Sweep done; %d of %d runs failed: %s", numel(failed), ...
                    numel(values), failed(1)), "warning");
            else
                obj.Shell.setStatus(sprintf("Sweep done: %d runs of %s.", numel(values), S.Label), "success");
            end
        end

        function mapAndShow(obj, xName, xValues, yName, yValues, params)
            panel = obj.MapPanel;
            panel.setRunning(true);
            restore = onCleanup(@() setRunningIfValid(panel));
            M = dlab.core.Map.run(obj.Plugin, params, xName, xValues, yName, yValues, ...
                Progress=@(f) obj.onProgress(f));
            if ~isvalid(obj)
                return
            end
            panel.show(M);
            total = numel(M.Errors);
            failed = M.Errors(M.Errors ~= "");
            if M.Cancelled
                obj.Shell.setStatus(sprintf("Map cancelled after %d of %d runs.", ...
                    nnz(any(isfinite(reshape(M.Data, total, [])), 2)), total), "warning");
            elseif ~isempty(failed)
                obj.Shell.setStatus(sprintf("Map done; %d of %d runs failed: %s", numel(failed), ...
                    total, failed(1)), "warning");
            else
                obj.Shell.setStatus(sprintf("Map done: %d runs of %s and %s.", total, M.Labels(1), ...
                    M.Labels(2)), "success");
            end
        end

        function optimizeAndShow(obj, job, params)
            panel = obj.OptimizePanel;
            panel.setRunning(true);
            restore = onCleanup(@() setRunningIfValid(panel));
            R = dlab.core.Optimizer.run(obj.Plugin, params, job.Inputs, job.Metric, Goal=job.Goal, ...
                Bounds=job.Bounds, Constraint=job.Constraint, Progress=@(f) obj.onProgress(f));
            if ~isvalid(obj)
                return
            end
            panel.show(R);
            level = "success";
            if R.Cancelled || ~R.Satisfied || any(isnan(R.Best))
                level = "warning";
            end
            obj.Shell.setStatus("Optimize: " + R.Message, level);
        end

        function fitAndShow(obj, asked, params)
            panel = obj.FitPanel;
            panel.setRunning(true);
            restore = onCleanup(@() setRunningIfValid(panel));
            R = dlab.core.MeasuredData.fit(obj.Plugin, params, obj.MeasuredData, asked.Mapping, ...
                asked.Inputs, Progress=@(f) obj.onProgress(f));
            if ~isvalid(obj)
                return
            end
            panel.show(R);
            if R.Cancelled
                obj.Shell.setStatus(sprintf("Fit cancelled after %d runs; the best so far is shown.", ...
                    R.Evaluations), "warning");
            elseif ~isfinite(R.BestRMS)
                obj.Shell.setStatus("Fit failed: " + R.Message, "warning");
            else
                obj.Shell.setStatus(sprintf("Fit done: RMS %.3g → %.3g in %d runs.", R.StartRMS, R.BestRMS, ...
                    R.Evaluations), "success");
            end
        end

        function saveLessonStepFrom(obj, dialog)
            obj.saveLessonStep(dialog.Request);
            delete(dialog);
        end

        function uncertaintyAndShow(obj, tol, n, seed, params)
            panel = obj.UncertaintyPanel;
            panel.setRunning(true);
            restore = onCleanup(@() setRunningIfValid(panel));
            R = dlab.core.MonteCarlo.run(obj.Plugin, params, tol, Samples=n, Seed=seed, ...
                Progress=@(f) obj.onProgress(f));
            if ~isvalid(obj)
                return
            end
            panel.show(R);
            failed = R.Errors(R.Errors ~= "");
            if R.Cancelled
                obj.Shell.setStatus(sprintf("Monte Carlo cancelled after %d of %d runs.", ...
                    size(R.Samples, 1), n), "warning");
            elseif R.NominalError ~= ""
                obj.Shell.setStatus("Monte Carlo done, but the nominal run failed: " + R.NominalError, "warning");
            elseif ~isempty(failed)
                obj.Shell.setStatus(sprintf("Monte Carlo done; %d of %d runs failed: %s", numel(failed), ...
                    n, failed(1)), "warning");
            else
                obj.Shell.setStatus(sprintf("Monte Carlo done: %d runs.", n), "success");
            end
        end

        function solveAndShow(obj, params)
            started = tic;
            try
                [result, ok] = obj.solveCancellable(params);
            catch ME
                obj.Shell.reportError(ME, "Solve " + obj.Plugin.Id);
                return
            end
            if ~ok
                if isvalid(obj)
                    obj.Shell.setStatus("Run cancelled.", "warning");
                end
                return
            end
            elapsed = toc(started);
            if obj.KeepRuns && ~isempty(obj.Result)
                obj.Runs(end+1) = struct("Result", {obj.Result}, "Params", obj.RunParams);
            elseif ~obj.KeepRuns
                obj.Runs = obj.Runs([]);
            end
            obj.displayResult(result, params);
            obj.setStale(false);
            if ~isempty(obj.Playback) && string(obj.Tabs.SelectedTab.Title) == "Animation"
                obj.Playback.play();   % only animate when the animation is on screen
            end

            message = sprintf("Solved in %.2f s", elapsed);
            if ~isempty(obj.Playback)
                message = message + sprintf(" · %d samples", numel(obj.Plugin.timeVector(result)));
            end
            [note, level] = obj.Plugin.resultNote(result);
            if note ~= ""
                message = message + " · " + note;
            end
            obj.Shell.setStatus(message, level);
        end
    end

    methods
        function reset(obj)
            %RESET Default inputs, no result.
            obj.History.record(obj.LastState);
            obj.Inputs.setValues(obj.Plugin.defaultParams());
            obj.selectPreset(obj.DefaultsKey);
            obj.clearOutputs();
            obj.inputsSettled();
            obj.Shell.setStatus("Inputs reset to defaults.");
        end

        function applyPreset(obj, key)
            %APPLYPRESET "defaults", "builtin:<name>", "user:<file>", or "custom".
            arguments
                obj
                key (1,1) string
            end
            if key == obj.CustomKey
                return
            end
            obj.History.record(obj.LastState);
            if key == obj.DefaultsKey
                obj.setInputs(obj.Plugin.defaultParams());
                obj.Preset = "Defaults";
            elseif startsWith(key, "builtin:")
                name = extractAfter(key, "builtin:");
                obj.setInputs(obj.Plugin.presetParams(name));
                obj.Preset = name;
            elseif startsWith(key, "user:")
                obj.loadScenario(extractAfter(key, "user:"));
                return
            end
            obj.selectPreset(key);
            obj.inputsSettled();
            obj.Shell.setStatus("Preset: " + obj.Preset);
        end

        function saveScenario(obj, file)
            %SAVESCENARIO Write the current inputs to FILE (asks if omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if file == ""
                file = askFile("put", "*.json", "Save scenario", ...
                    fullfile(dlab.core.Paths.scenarios(obj.Plugin.Id), "scenario.json"));
                if file == ""
                    return
                end
            end
            dlab.core.ScenarioIO.save(file, obj.Plugin, obj.params(), obj.Preset);
            dlab.core.Recent.noteScenario(file, obj.Plugin.Id);
            obj.refreshPresetItems();
            obj.Shell.setStatus("Saved scenario " + fileName(file), "success");
        end

        function loadScenario(obj, file, options)
            %LOADSCENARIO Read inputs from FILE (asks if omitted). A file for
            %   another simulator offers to switch to it.
            arguments
                obj
                file (1,1) string = ""
                options.Confirm (1,1) logical = true
            end
            if file == ""
                file = askFile("get", "*.json", "Load scenario", dlab.core.Paths.scenarios(obj.Plugin.Id));
                if file == ""
                    return
                end
            end
            raw = dlab.core.ScenarioIO.read(file);
            if raw.simulator ~= obj.Plugin.Id
                obj.offerSwitch(raw.simulator, file, options.Confirm);
                return
            end
            [params, warnings] = dlab.core.ScenarioIO.fromStruct(raw, obj.Plugin);
            obj.History.record(obj.LastState);
            obj.setInputs(params);
            obj.Preset = fileName(file);
            obj.refreshPresetItems();
            obj.selectPreset("user:" + file);
            obj.inputsSettled();
            dlab.core.Recent.noteScenario(file, obj.Plugin.Id);
            if isempty(warnings)
                obj.Shell.setStatus("Loaded scenario " + obj.Preset, "success");
            else
                obj.Shell.setStatus(sprintf("Loaded %s with %d warning(s): %s", obj.Preset, ...
                    numel(warnings), strjoin(warnings, " ")), "warning");
            end
        end

        function exportData(obj, format, file)
            %EXPORTDATA format "csv" or "mat"; asks for FILE if omitted.
            arguments
                obj
                format (1,1) string {mustBeMember(format, ["csv" "mat"])}
                file (1,1) string = ""
            end
            if ~obj.requireResult()
                return
            end
            if file == ""
                file = askFile("put", "*." + format, "Export data", obj.defaultExportName(format));
                if file == ""
                    return
                end
            end
            T = obj.Plugin.exportTable(obj.Result);
            if format == "csv"
                dlab.core.Exporter.csv(file, T);
            else
                scenario = dlab.core.ScenarioIO.toStruct(obj.Plugin, obj.RunParams, obj.Preset);
                dlab.core.Exporter.mat(file, scenario, obj.Result, T, obj.Runs);
            end
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function exportPlot(obj, file, options)
            %EXPORTPLOT PNG of the selected tab's graphics.
            arguments
                obj
                file (1,1) string = ""
                options.Resolution (1,1) double {mustBePositive} = 200
            end
            title = obj.currentTab();
            if ~isKey(obj.Containers, title)
                obj.Shell.setStatus("Select a plot tab to export it.", "warning");
                return
            end
            if file == ""
                file = askFile("put", "*.png", "Export plot", obj.defaultExportName("png", title));
                if file == ""
                    return
                end
            end
            dlab.core.Exporter.plotPng(obj.Containers{title}, file, options.Resolution);
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function exportWindow(obj, file)
            arguments
                obj
                file (1,1) string = ""
            end
            if file == ""
                file = askFile("put", "*.png", "Export window", obj.defaultExportName("png", "window"));
                if file == ""
                    return
                end
            end
            dlab.core.Exporter.windowPng(obj.Shell.Figure, file);
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function exportAnimation(obj, format, file, options)
            %EXPORTANIMATION Record the animation at the current speed to an
            %   MP4 or GIF (asks for FILE if omitted). Cancellable.
            arguments
                obj
                format (1,1) string {mustBeMember(format, ["mp4" "gif"])}
                file (1,1) string = ""
                options.MaxFrames (1,1) double = NaN
            end
            if isempty(obj.Playback)
                obj.Shell.setStatus("This simulator has no animation to export.", "warning");
                return
            end
            if ~obj.requireResult()
                return
            end
            if ~dlab.core.AnimationExporter.canWrite(format)
                error("dlab:export:format", "This computer cannot write %s video; export a GIF instead.", upper(format));
            end
            if file == ""
                file = askFile("put", "*." + format, "Export animation", ...
                    obj.defaultExportName(format, "animation"));
                if file == ""
                    return
                end
            end
            obj.runTask("Exporting animation…", @() obj.writeAnimation(format, file, options.MaxFrames));
        end

        function restoreInputs(obj, params, preset)
            %RESTOREINPUTS Show PARAMS (one undo step), under preset name PRESET.
            obj.History.record(obj.LastState);
            obj.setInputs(params);
            obj.Preset = preset;
            obj.PresetDropdown.Value = obj.keyForPreset(preset);
            obj.inputsSettled();
        end

        % --------------------------------------------------------- lessons
        function startLesson(obj, lesson, state)
            %STARTLESSON Open LESSON in a column on the right (STATE: Step,
            %   Passed, to resume).
            arguments
                obj
                lesson (1,1) struct
                state = []
            end
            obj.closeLesson();
            t = obj.Shell.Theme;
            shell = obj.Shell;
            actions = struct( ...
                "Setup", @(k) shell.safeCall(@() obj.lessonSetup(k), "Lesson setup"), ...
                "Check", @(k) shell.safeCall(@() obj.lessonCheck(k), "Lesson check"), ...
                "Go", @(k) shell.safeCall(@() obj.lessonGo(k), "Lesson"), ...
                "Close", @() shell.safeCall(@() obj.closeLesson(), "Close lesson"));
            obj.Grid.ColumnWidth = {obj.inputWidth(), "1x", round(t.scaled(300))};   % wider with larger text
            obj.LessonPanel = dlab.core.LessonPanel(obj.Grid, lesson, t, actions, state);
            obj.LessonPanel.Grid.Layout.Column = 3;
            dlab.core.Lesson.saveProgress(lesson.id, obj.LessonPanel.Step, false);
        end

        function closeLesson(obj)
            if ~isempty(obj.LessonPanel) && isvalid(obj.LessonPanel)
                delete(obj.LessonPanel.Grid);
                delete(obj.LessonPanel);
            end
            obj.LessonPanel = [];
            obj.Grid.ColumnWidth = {obj.inputWidth(), "1x"};
        end

        function lessonSetup(obj, k)
            %LESSONSETUP Apply step K's setup: preset, inputs, options, tab.
            step = obj.LessonPanel.Lesson.steps{k};
            obj.applySetup(step.setup);
            obj.Shell.setStatus("Loaded the setup for this step. Ctrl+Z undoes it.");
        end

        function [passed, message] = lessonCheck(obj, k)
            %LESSONCHECK Evaluate step K's check and show the feedback.
            step = obj.LessonPanel.Lesson.steps{k};
            [passed, message] = dlab.core.Lesson.evaluate(step.check, obj.lessonContext());
            obj.LessonPanel.showResult(passed, message);
            level = "warning";
            if passed
                level = "success";
            end
            obj.Shell.setStatus(message, level);
        end

        function lessonGo(obj, k)
            %LESSONGO Show step K; past the last step, finish the lesson.
            panel = obj.LessonPanel;
            id = panel.Lesson.id;
            if k > numel(panel.Lesson.steps)
                dlab.core.Lesson.saveProgress(id, numel(panel.Lesson.steps), true);
                title = panel.Lesson.title;
                obj.closeLesson();
                obj.Shell.setStatus("Lesson complete: " + title, "success");
                return
            end
            if k >= 1 && dlab.core.Lesson.stepSimulator(panel.Lesson, k) ~= obj.Plugin.Id
                % This step runs in another simulator: the lesson moves there.
                obj.Shell.continueLesson(panel.Lesson, k, panel.Passed);
                return
            end
            panel.showStep(k);
            dlab.core.Lesson.saveProgress(id, panel.Step, false);
        end

        function context = lessonContext(obj)
            %LESSONCONTEXT What lesson checks look at.
            context = struct("Params", obj.params(), "Specs", obj.Plugin.parameters(), ...
                "Fresh", ~isempty(obj.Result) && ~obj.IsStale, "RunParams", obj.RunParams, ...
                "Metrics", [], "Sweep", [], "Map", [], "Optimize", [], "Uncertainty", [], "Fit", [], ...
                "Modes", [], "Frequency", [], "KeptRuns", numel(obj.Runs), "Answer", NaN);
            if ~isempty(obj.LessonPanel)
                context.Answer = obj.LessonPanel.Answer;
            end
            if ~isempty(obj.FrequencyPanel)
                context.Frequency = obj.FrequencyPanel.Response;
            end
            if ~isempty(obj.Result)
                context.Metrics = obj.Plugin.metrics(obj.Result);
            end
            if ~isempty(obj.SweepPanel)
                context.Sweep = obj.SweepPanel.Result;
            end
            if ~isempty(obj.MapPanel)
                context.Map = obj.MapPanel.Result;
            end
            if ~isempty(obj.OptimizePanel)
                context.Optimize = obj.OptimizePanel.Result;
            end
            if ~isempty(obj.UncertaintyPanel)
                context.Uncertainty = obj.UncertaintyPanel.Result;
            end
            if ~isempty(obj.FitPanel)
                context.Fit = obj.FitPanel.Result;
            end
            if ~isempty(obj.ModesPanel) && ~isempty(obj.ModesPanel.Analysis)
                context.Modes = obj.ModesPanel.Analysis.Modes;
            end
        end

        function applySetup(obj, setup)
            %APPLYSETUP Inputs from a preset and/or values, then options:
            %   keepRuns, sweep (parameter, from, to, steps, log), map (x and
            %   y, each name, from, to, steps, log), optimize (inputs, metric,
            %   goal, bounds, constraint), uncertainty (inputs: name, kind,
            %   spread, relative; samples, seed), bode (input, output; shown
            %   after the next run), measured (a CSV in resources/data, or a
            %   path), fit (measured, simulated, inputs), and tab.
            plugin = obj.Plugin;
            if isfield(setup, "preset")
                name = string(setup.preset);
                if name == "Defaults"
                    params = plugin.defaultParams();
                    [preset, key] = deal("Defaults", obj.DefaultsKey);
                else
                    params = plugin.presetParams(name);
                    [preset, key] = deal(name, "builtin:" + name);
                end
            else
                params = obj.params();
                [preset, key] = deal(obj.Preset, string(obj.PresetDropdown.Value));
            end
            if isfield(setup, "params")
                for name = string(fieldnames(setup.params))'
                    value = setup.params.(name);
                    if ischar(value)
                        value = string(value);
                    end
                    params.(name) = value;
                    params = plugin.onParamChanged(name, params);
                    params.(name) = value;
                end
                [preset, key] = deal("Custom", obj.CustomKey);
                params = plugin.paramsFromJson(params);     % lesson values are as JSON stores them
            end
            params = dlab.core.ParamSpec.validateAll(plugin.parameters(), params);
            obj.History.record(obj.LastState);
            obj.setInputs(params);
            obj.Preset = preset;
            obj.PresetDropdown.Value = key;
            obj.inputsSettled();
            if isfield(setup, "keepRuns")
                obj.setKeepRuns(logical(setup.keepRuns));
            end
            if isfield(setup, "sweep") && ~isempty(obj.SweepPanel)
                s = setup.sweep;
                logSpacing = isfield(s, "log") && logical(s.log);
                obj.SweepPanel.configure(string(s.parameter), s.from, s.to, s.steps, logSpacing);
            end
            if isfield(setup, "map") && ~isempty(obj.analysisPanel("Map"))
                obj.MapPanel.configure(mapAxis(setup.map.x), mapAxis(setup.map.y));
            end
            if isfield(setup, "optimize") && ~isempty(obj.analysisPanel("Optimize"))
                o = setup.optimize;
                constraint = [];
                if isfield(o, "constraint")
                    constraint = struct("Metric", string(o.constraint.metric), "Type", string(o.constraint.type), ...
                        "Value", o.constraint.value);
                end
                bounds = [];
                if isfield(o, "bounds")
                    bounds = reshape(o.bounds, [], 2);
                end
                obj.OptimizePanel.configure(string(o.inputs), string(o.metric), ...
                    Goal=string(lessonField(o, "goal", "maximize")), Bounds=bounds, Constraint=constraint);
            end
            if isfield(setup, "uncertainty") && ~isempty(obj.analysisPanel("Uncertainty"))
                u = setup.uncertainty;
                inputs = u.inputs;
                if isstruct(inputs)
                    inputs = num2cell(inputs);
                end
                names = cellfun(@(i) string(i.name), inputs);
                tol = dlab.core.MonteCarlo.tolerance(names, ...
                    Kind=cellfun(@(i) string(lessonField(i, "kind", "uniform")), inputs), ...
                    Spread=cellfun(@(i) double(i.spread), inputs), ...
                    Relative=cellfun(@(i) logical(lessonField(i, "relative", false)), inputs));
                obj.UncertaintyPanel.configure(tol, Samples=lessonField(u, "samples", 100), ...
                    Seed=lessonField(u, "seed", 1));
            end
            if isfield(setup, "bode")
                obj.PendingBode = [string(setup.bode.input) string(setup.bode.output)];
            end
            if isfield(setup, "measured")
                file = string(setup.measured);
                shipped = fullfile(dlab.core.Paths.resources(), "data", file);
                if isfile(shipped)
                    file = shipped;
                end
                obj.importMeasured(file);
            end
            if isfield(setup, "fit") && ~isempty(obj.analysisPanel("Fit"))
                f = setup.fit;
                obj.FitPanel.configure(string(f.measured), string(f.simulated), ...
                    reshape(string(f.inputs), 1, []));
            end
            if isfield(setup, "tab")
                tab = string(setup.tab);
                if ~ismember(tab, obj.tabTitles()) && ismember(tab, plugin.outputTabs(params))
                    % Output tabs follow the inputs and are rebuilt with the
                    % next result: show this one as soon as it exists.
                    obj.PendingTab = tab;
                else
                    obj.selectTab(tab);
                end
            end
        end

        function runSweep(obj)
            %RUNSWEEP Run the sweep set up in the Sweep tab (cancels a running one).
            if obj.IsBusy
                if startsWith(obj.BusyLabel, "Sweep")
                    obj.cancel();
                end
                return
            end
            [name, values] = obj.SweepPanel.request();
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask(sprintf("Sweep of %d runs…", numel(values)), @() obj.sweepAndShow(name, values, params));
        end

        function exportSweep(obj, file)
            %EXPORTSWEEP The last sweep as CSV (asks for FILE if omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if isempty(obj.SweepPanel) || isempty(obj.SweepPanel.Result)
                obj.Shell.setStatus("Run a sweep first.", "warning");
                return
            end
            if file == ""
                file = askFile("put", "*.csv", "Export sweep", obj.defaultExportName("csv", "sweep"));
                if file == ""
                    return
                end
            end
            S = obj.SweepPanel.Result;
            if startsWith(obj.SweepPanel.Metric, "set:")
                dlab.core.Exporter.csv(file, dlab.core.Sweep.toLongTable(S));   % every value, one per row
            else
                dlab.core.Exporter.csv(file, dlab.core.Sweep.toTable(S));
            end
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function runMap(obj)
            %RUNMAP Run the map set up in the Map tab (cancels a running one).
            if obj.IsBusy
                if startsWith(obj.BusyLabel, "Map")
                    obj.cancel();
                end
                return
            end
            [xName, xValues, yName, yValues] = obj.analysisPanel("Map").request();
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask(sprintf("Map of %d runs…", numel(xValues) * numel(yValues)), ...
                @() obj.mapAndShow(xName, xValues, yName, yValues, params));
        end

        function exportMap(obj, file)
            %EXPORTMAP The last map as CSV, one row per grid point (asks for
            %   FILE if omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if isempty(obj.MapPanel) || isempty(obj.MapPanel.Result)
                obj.Shell.setStatus("Run a map first.", "warning");
                return
            end
            if file == ""
                file = askFile("put", "*.csv", "Export map", obj.defaultExportName("csv", "map"));
                if file == ""
                    return
                end
            end
            dlab.core.Exporter.csv(file, dlab.core.Map.toTable(obj.MapPanel.Result));
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function runOptimize(obj)
            %RUNOPTIMIZE Run the search set up in the Optimize tab (cancels a running one).
            if obj.IsBusy
                if startsWith(obj.BusyLabel, "Optimiz")
                    obj.cancel();
                end
                return
            end
            panel = obj.analysisPanel("Optimize");
            if isempty(panel.Metrics)
                obj.listOptimizeResults(panel);
            end
            job = panel.request();
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask("Optimizing…", @() obj.optimizeAndShow(job, params));
        end

        function listOptimizeResults(obj, panel)
            % The Optimize tab offers the results of a run; before the
            % first one, solve the current inputs once to list them.
            if obj.IsBusy
                return
            end
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask("Listing the results to optimize…", ...
                @() panel.setMetrics(obj.Plugin.metrics(obj.Plugin.solve(params))));
        end

        function importMeasured(obj, file)
            %IMPORTMEASURED Read a CSV of measurements for the Fit tab and
            %   the Custom plot (asks for FILE if omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if file == ""
                file = askFile("get", "*.csv", "Import measured data", "");
                if file == ""
                    return
                end
            end
            D = dlab.core.MeasuredData.read(file);
            obj.MeasuredData = D;
            if ~isempty(obj.analysisPanel("Fit"))
                obj.FitPanel.load(D);
            end
            obj.PlotBuilder.setMeasured(D);
            note = sprintf("Imported %s: %d rows of %s", D.Name, numel(D.Time), strjoin(D.Columns, ", "));
            if D.Dropped > 0
                note = note + sprintf(" (%d incomplete rows dropped)", D.Dropped);
            end
            obj.Shell.setStatus(note + ".", "success");
        end

        function applyFit(obj, R)
            %APPLYFIT Set the fitted inputs on the left (one undo step).
            if isempty(R)
                obj.Shell.setStatus("Run a fit first.", "warning");
                return
            end
            obj.applyInputs(cell2struct(num2cell(R.Best(:)), cellstr(R.Inputs(:)), 1), "Fit");
        end

        function runFit(obj)
            %RUNFIT Fit the inputs chosen in the Fit tab (cancels a running fit).
            if obj.IsBusy
                if startsWith(obj.BusyLabel, "Fitting")
                    obj.cancel();
                end
                return
            end
            asked = obj.analysisPanel("Fit").request();
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask("Fitting…", @() obj.fitAndShow(asked, params));
        end

        function runUncertainty(obj)
            %RUNUNCERTAINTY Run the Monte Carlo study set up in the
            %   Uncertainty tab (cancels a running one).
            if obj.IsBusy
                if startsWith(obj.BusyLabel, "Monte Carlo")
                    obj.cancel();
                end
                return
            end
            [tol, n, seed] = obj.analysisPanel("Uncertainty").request();
            params = dlab.core.ParamSpec.validateAll(obj.Plugin.parameters(), obj.params());
            obj.runTask(sprintf("Monte Carlo of %d runs…", n), @() obj.uncertaintyAndShow(tol, n, seed, params));
        end

        function exportUncertainty(obj, file)
            %EXPORTUNCERTAINTY The last Monte Carlo study as CSV, one row per
            %   sample (asks for FILE if omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if isempty(obj.UncertaintyPanel) || isempty(obj.UncertaintyPanel.Result)
                obj.Shell.setStatus("Run a Monte Carlo study first.", "warning");
                return
            end
            if file == ""
                file = askFile("put", "*.csv", "Export Monte Carlo", obj.defaultExportName("csv", "montecarlo"));
                if file == ""
                    return
                end
            end
            dlab.core.Exporter.csv(file, dlab.core.MonteCarlo.toTable(obj.UncertaintyPanel.Result));
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function exportReport(obj, file)
            %EXPORTREPORT One HTML page for a write-up: the run's inputs, the
            %   Summary, every plot tab, and the kept runs (asks for FILE if
            %   omitted).
            arguments
                obj
                file (1,1) string = ""
            end
            if ~obj.requireResult()
                return
            end
            if file == ""
                file = askFile("put", "*.html", "Export report", obj.defaultExportName("html", "report"));
                if file == ""
                    return
                end
            end
            info = struct("Title", obj.Plugin.Title, "Subtitle", "Preset: " + obj.Preset, ...
                "Version", dlab.version(), "Date", datetime("now"), ...
                "Groups", dlab.core.RunReport.inputGroups(obj.Plugin.parameters(), obj.RunParams), ...
                "Summary", dlab.core.RunReport.summaryRows(obj.Plugin.summaryTable(obj.Result)));
            if obj.IsStale
                info.Subtitle = info.Subtitle + " (the inputs have changed since; this report shows the run's)";
            end
            % The result's own tabs and the Custom plot; analysis tabs only
            % when they hold something.
            titles = ["Animation", obj.TabTitles, "Custom plot"];
            panels = {obj.SweepPanel, "Sweep"; obj.MapPanel, "Map"; obj.OptimizePanel, "Optimize"
                obj.UncertaintyPanel, "Uncertainty"; obj.FitPanel, "Fit"};
            for k = 1:size(panels, 1)
                if ~isempty(panels{k, 1}) && ~isempty(panels{k, 1}.Result)
                    titles(end+1) = panels{k, 2}; %#ok<AGROW>
                end
            end
            if ~isempty(obj.ModesPanel) && ~isempty(obj.ModesPanel.Analysis)
                titles(end+1) = "Modes";
            end
            if ~isempty(obj.FrequencyPanel) && ~isempty(obj.FrequencyPanel.Response)
                titles(end+1) = "Bode";
            end
            titles = titles(isKey(obj.Containers, titles));
            info.Images = struct("Title", cellstr(titles), "Container", cellfun(@(c) {c}, ...
                obj.Containers(titles), UniformOutput=false));
            if ~isempty(obj.Runs) && ~isempty(obj.RunsTable) && isvalid(obj.RunsTable)
                info.Runs = cell2table(obj.RunsTable.Data, VariableNames=obj.RunsTable.ColumnName);
            end
            obj.runTask("Writing the report…", @() dlab.core.RunReport.write(file, info));
            obj.Shell.setStatus("Exported " + fileName(file, true), "success");
        end

        function askLessonStep(obj)
            %ASKLESSONSTEP Open "Save as lesson step…" for the current inputs.
            metrics = [];
            if ~isempty(obj.Result) && ~obj.IsStale
                metrics = obj.Plugin.metrics(obj.Result);
            end
            dialog = dlab.core.LessonStepDialog(obj.Shell.Theme, ...
                dlab.core.LessonWriter.userLessons(obj.Plugin.Id), metrics, ...
                ["Animation", obj.Plugin.outputTabs(obj.params()), obj.AnalysisTabs], ...
                obj.currentTab(), Visible=obj.Shell.Figure.Visible == "on");
            obj.Listeners(end+1) = listener(dialog, "SaveRequested", @(src, ~) obj.Shell.safeCall(@() ...
                obj.saveLessonStepFrom(src), "Save lesson step"));
        end

        function L = saveLessonStep(obj, request)
            %SAVELESSONSTEP Add a step made from the current inputs to a
            %   lesson in the user's folder. REQUEST: Lesson (its file, or ""
            %   for a new one), NewTitle, Title, Text, Metric ("" for no
            %   check, else a key result of the up-to-date run), Tolerance
            %   (percent), and Tab ("" to leave the tab alone).
            if request.Title == ""
                error("dlab:lesson:title", "Give the step a title.");
            end
            file = request.Lesson;
            title = request.NewTitle;
            if file == ""
                if title == ""
                    error("dlab:lesson:title", "Give the new lesson a title.");
                end
                file = dlab.core.LessonWriter.fileFor(title);
                if isfile(file)
                    error("dlab:lesson:exists", "You already have a lesson called ""%s"".", title);
                end
            end
            value = NaN;
            units = "";
            if request.Metric ~= ""
                if isempty(obj.Result) || obj.IsStale
                    error("dlab:lesson:value", "Run first: the check uses this run's %s.", request.Metric);
                end
                M = obj.Plugin.metrics(obj.Result);
                row = M(M.Quantity == request.Metric, :);
                value = row.Value(1);
                units = string(row.Units(1));
            end
            preset = obj.Preset;
            step = dlab.core.LessonWriter.makeStep(obj.Plugin, obj.params(), preset, Title=request.Title, ...
                Text=request.Text, Tab=request.Tab, Metric=request.Metric, Value=value, Units=units, ...
                Tolerance=request.Tolerance);
            L = dlab.core.LessonWriter.append(file, obj.Plugin.Id, title, step);
            obj.Shell.setStatus(sprintf("Saved step %d of ""%s"" (%s). It is on the Home screen.", ...
                numel(L.steps), L.title, fileName(file, true)), "success");
        end

        function selectTab(obj, title)
            %SELECTTAB Show tab TITLE: an output tab, or an analysis tool
            %   inside Analyze ("Sweep" selects Analyze, then Sweep).
            tab = findobj(obj.Tabs.Children, "flat", "Title", title);
            if isempty(tab) && ~isempty(obj.AnalysisGroup) && isvalid(obj.AnalysisGroup)
                tab = findobj(obj.AnalysisGroup.Children, "flat", "Title", title);
                if ~isempty(tab)
                    obj.Tabs.SelectedTab = findobj(obj.Tabs.Children, "flat", "Title", "Analyze");
                    obj.AnalysisGroup.SelectedTab = tab;
                end
            else
                obj.Tabs.SelectedTab = tab;
            end
            assert(~isempty(tab), "dlab:view:noTab", "No tab ""%s"".", title);
            obj.tabSelected(tab);
        end

        function title = currentTab(obj)
            %CURRENTTAB The tab shown: an output tab, or the analysis tool
            %   shown inside Analyze.
            title = string(obj.Tabs.SelectedTab.Title);
            if title == "Analyze" && ~isempty(obj.AnalysisGroup) && isvalid(obj.AnalysisGroup)
                title = string(obj.AnalysisGroup.SelectedTab.Title);
            end
        end

        function state = viewState(obj)
            %VIEWSTATE What reopens this simulator as it was left, across
            %   launches: the selected tab and the analysis tabs' set-ups
            %   (without their results, which can be large).
            analysis = obj.analysisSnapshot();
            if ~isempty(analysis)
                for name = ["Sweep" "Map" "Optimize" "Uncertainty" "Fit"]
                    if isfield(analysis, name) && isstruct(analysis.(name)) && isfield(analysis.(name), "Result")
                        analysis.(name).Result = [];
                    end
                end
            end
            state = struct("Tab", obj.currentTab(), "Analysis", {analysis});
        end

        function panel = analysisPanel(obj, name)
            %ANALYSISPANEL The Map, Optimize, Uncertainty, or Fit panel
            %   (NAME), built the first time it is shown or needed, which keeps
            %   opening a simulator quick; [] when this simulator has none.
            panel = obj.(name + "Panel");
            if ~isempty(panel) || ~isfield(obj.LazyGrids, name)
                return
            end
            t = obj.Shell.Theme;
            specs = obj.Plugin.parameters();
            grid = obj.LazyGrids.(name);
            state = obj.LazyStates.(name);
            switch name
                case "Map"
                    obj.MapPanel = dlab.core.MapPanel(grid, specs, @() obj.params(), t, state);
                    obj.Containers("Map") = {obj.MapPanel.Axes};
                    obj.Listeners(end+1) = listener(obj.MapPanel, "RunRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.runMap(), "Map", AllowBusy=true));
                    obj.Listeners(end).Recursive = true;   % pressed again mid-map, it cancels
                    obj.Listeners(end+1) = listener(obj.MapPanel, "ExportRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.exportMap(), "Export map"));
                    obj.Listeners(end+1) = listener(obj.MapPanel, "ApplyRequested", ...
                        @(src, ~) obj.Shell.safeCall(@() obj.applyInputs(src.Chosen, "Map point"), "Map point"));
                case "Optimize"
                    obj.OptimizePanel = dlab.core.OptimizePanel(grid, specs, @() obj.params(), t, state);
                    obj.Containers("Optimize") = {obj.OptimizePanel.Axes};
                    obj.Listeners(end+1) = listener(obj.OptimizePanel, "RunRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.runOptimize(), "Optimize", AllowBusy=true));
                    obj.Listeners(end).Recursive = true;   % pressed again mid-search, it cancels
                    obj.Listeners(end+1) = listener(obj.OptimizePanel, "ApplyRequested", @(src, ~) ...
                        obj.Shell.safeCall(@() obj.applyInputs(src.Chosen, "Apply best inputs"), "Apply best inputs"));
                    if ~isempty(obj.Result)
                        obj.OptimizePanel.setMetrics(obj.Plugin.metrics(obj.Result));
                    else
                        obj.listOptimizeResults(obj.OptimizePanel);
                    end
                case "Uncertainty"
                    obj.UncertaintyPanel = dlab.core.UncertaintyPanel(grid, specs, @() obj.params(), t, state);
                    obj.Containers("Uncertainty") = {obj.UncertaintyPanel.PlotGrid};
                    obj.Listeners(end+1) = listener(obj.UncertaintyPanel, "RunRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.runUncertainty(), "Monte Carlo", AllowBusy=true));
                    obj.Listeners(end).Recursive = true;   % pressed again mid-run, it cancels
                    obj.Listeners(end+1) = listener(obj.UncertaintyPanel, "ExportRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.exportUncertainty(), "Export Monte Carlo"));
                case "Fit"
                    obj.FitPanel = dlab.core.FitPanel(grid, specs, @() obj.params(), t, state);
                    obj.Containers("Fit") = {obj.FitPanel.PlotGrid};
                    obj.Listeners(end+1) = listener(obj.FitPanel, "ImportRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.importMeasured(), "Import data"));
                    obj.Listeners(end+1) = listener(obj.FitPanel, "RunRequested", ...
                        @(~, ~) obj.Shell.safeCall(@() obj.runFit(), "Fit", AllowBusy=true));
                    obj.Listeners(end).Recursive = true;   % pressed again mid-fit, it cancels
                    obj.Listeners(end+1) = listener(obj.FitPanel, "ApplyRequested", ...
                        @(src, ~) obj.Shell.safeCall(@() obj.applyFit(src.Result), "Apply fit"));
                    if ~isempty(obj.MeasuredData) && isempty(state)
                        obj.FitPanel.load(obj.MeasuredData);
                    end
                    if ~isempty(obj.Result)
                        obj.FitPanel.setTable(obj.Plugin.exportTable(obj.Result));
                    end
            end
            panel = obj.(name + "Panel");
        end

        function titles = tabTitles(obj)
            %TABTITLES The top-level tabs, in order.
            titles = string({obj.Tabs.Children.Title});
        end

        function titles = analysisTitles(obj)
            %ANALYSISTITLES The analysis tools inside Analyze, in order.
            titles = strings(1, 0);
            if ~isempty(obj.AnalysisGroup) && isvalid(obj.AnalysisGroup)
                titles = string({obj.AnalysisGroup.Children.Title});
            end
        end

        function state = snapshot(obj)
            time = NaN;
            if ~isempty(obj.Playback)
                time = obj.Playback.Time;
            end
            state = dlab.core.Session.newState(Params=obj.params(), Preset=obj.Preset, ...
                Result=obj.Result, RunParams=obj.RunParams, Stale=obj.IsStale, PlaybackTime=time, ...
                History=obj.History.snapshot(), Analysis=obj.analysisSnapshot(), ...
                KeepRuns=obj.KeepRuns, Runs=obj.Runs, Lesson=obj.lessonSnapshot(), ...
                Tab=obj.currentTab());
        end

        function close(obj)
            %CLOSE Save state to the session and tear everything down.
            if ~isvalid(obj)
                return
            end
            obj.Shell.Session.put(obj.Plugin.Id, obj.snapshot());
            delete(obj.Listeners);
            if ~isempty(obj.PlaybackBar)
                delete(obj.PlaybackBar);
            end
            if ~isempty(obj.Playback)
                delete(obj.Playback);
            end
            if ~isempty(obj.ExportMenu) && isvalid(obj.ExportMenu)
                delete(obj.ExportMenu);
            end
            delete(obj.Plugin);
            if isvalid(obj.Grid)
                delete(obj.Grid);
            end
            delete(obj);
        end
    end

    methods (Access = private)
        function pixels = inputWidth(obj)
            pixels = round(obj.Shell.Theme.scaled(obj.InputWidths(1 + obj.WideInputs)));
        end

        % ---------------------------------------------------------- building
        function buildHeaderControls(obj, t)
            slot = obj.Shell.HeaderSlot;
            slot.ColumnWidth = {"fit", 220, 34, 34, 70, 70, 86};
            dlab.ui.label(slot, "Preset", t, Role="muted");
            obj.PresetDropdown = uidropdown(slot, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.preset", ...
                ValueChangedFcn=obj.Shell.callback(@() obj.applyPreset(obj.PresetDropdown.Value), "Preset"));
            obj.refreshPresetItems();
            obj.UndoButton = dlab.ui.button(slot, "↶", t, Kind="ghost", Tag="dlab.undo", ...
                Tooltip="Undo input change (Ctrl+Z)", Callback=obj.Shell.callback(@() obj.undo(), "Undo"));
            obj.RedoButton = dlab.ui.button(slot, "↷", t, Kind="ghost", Tag="dlab.redo", ...
                Tooltip="Redo (Ctrl+Y)", Callback=obj.Shell.callback(@() obj.redo(), "Redo"));
            saveButton = dlab.ui.button(slot, "Save", t, Tag="dlab.save", ...
                Tooltip="Save these inputs as a scenario (Ctrl+S)", ...
                Callback=obj.Shell.callback(@() obj.saveScenario(), "Save scenario"));
            loadButton = dlab.ui.button(slot, "Load", t, Tag="dlab.load", Tooltip="Load a scenario file (Ctrl+O)", ...
                Callback=obj.Shell.callback(@() obj.loadScenario(), "Load scenario"));
            exportButton = dlab.ui.button(slot, "Export ▾", t, Tag="dlab.export", ...
                Tooltip="Export data or images");
            obj.HeaderControls = [obj.PresetDropdown obj.UndoButton obj.RedoButton saveButton ...
                loadButton exportButton];
            obj.ExportMenu = uicontextmenu(obj.Shell.Figure);
            items = {"Data (CSV)…", @() obj.exportData("csv")
                     "Data (MAT)…", @() obj.exportData("mat")
                     "Current plot (PNG)…", @() obj.exportPlot()
                     "Window (PNG)…", @() obj.exportWindow()
                     "Report (HTML)…", @() obj.exportReport()
                     "Save as lesson step…", @() obj.askLessonStep()};
            if obj.Plugin.kind() == "time"
                for format = dlab.core.AnimationExporter.Formats
                    if dlab.core.AnimationExporter.canWrite(format)
                        items(end+1, :) = {"Animation (" + upper(format) + ")…", ...
                            @() obj.exportAnimation(format)}; %#ok<AGROW>
                    end
                end
            end
            for k = 1:size(items, 1)
                uimenu(obj.ExportMenu, Text=items{k, 1}, ...
                    MenuSelectedFcn=obj.Shell.callback(items{k, 2}, "Export"));
            end
            exportButton.ButtonPushedFcn = @(src, ~) dlab.ui.openMenuBelow(obj.ExportMenu, src);
        end

        function buildLeftColumn(obj, t, params)
            left = uigridlayout(obj.Grid, [4 1], RowHeight={"1x", "fit", 26, 44}, ...
                Padding=0, RowSpacing=0, BackgroundColor=t.Surface);
            left.Layout.Column = 1;

            custom = obj.Plugin.buildInputs(left, params, t);
            if isempty(custom)
                obj.Inputs = dlab.core.ParamPanel(left, obj.Plugin.parameters(), params, t);
                obj.Inputs.Grid.Layout.Row = 1;
            else
                obj.Inputs = custom;
            end
            obj.Listeners(end+1) = listener(obj.Inputs, "ValueChanged", ...
                @(~, evt) obj.Shell.safeCall(@() obj.onInputChanged(evt.Name), "Edit " + evt.Name));
            if ismember("StatusMessage", events(obj.Inputs))
                obj.Listeners(end+1) = listener(obj.Inputs, "StatusMessage", ...
                    @(~, evt) obj.Shell.setStatus(evt.Message, evt.Level));
            end

            extras = uigridlayout(left, [1 1], Padding=[t.Spacing.md 0 t.Spacing.md t.Spacing.sm], ...
                BackgroundColor=t.Surface, RowHeight={"fit"});
            extras.Layout.Row = 2;
            obj.Plugin.buildExtraControls(extras, t);
            if isempty(extras.Children)
                left.RowHeight{2} = 0;
            end

            keep = uigridlayout(left, [1 2], RowHeight={22}, ColumnWidth={"1x", "fit"}, ...
                Padding=[t.Spacing.md 4 t.Spacing.md 0], BackgroundColor=t.Surface);
            keep.Layout.Row = 3;
            obj.KeepCheckbox = uicheckbox(keep, Text="Keep previous runs", Value=obj.KeepRuns, ...
                FontColor=t.Text, Tag="dlab.keepRuns", Tooltip=sprintf("Draw earlier runs faintly " + ...
                "behind the next ones (up to %d) and list them on the Runs tab. Reset clears them.", ...
                obj.MaxKeptRuns), ValueChangedFcn=obj.Shell.callback( ...
                @() obj.setKeepRuns(obj.KeepCheckbox.Value), "Keep previous runs"));
            obj.WidthButton = dlab.ui.button(keep, widthButtonText(obj.WideInputs), t, Kind="ghost", ...
                Tag="dlab.inputWidth", Tooltip="Make the input panel wider (tables show more of their " + ...
                "columns) or narrower (more room for the plots)", ...
                Callback=obj.Shell.callback(@() obj.setWideInputs(~obj.WideInputs), "Input panel"));
            obj.WidthButton.FontSize = t.FontSize.sm + 1;
            if ~obj.Plugin.implements("overlayRuns")
                obj.KeepCheckbox.Visible = "off";
            end

            footer = uigridlayout(left, [1 2], ColumnWidth={"1x", "1x"}, RowHeight={30}, ...
                Padding=[t.Spacing.md 7 t.Spacing.md 7], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            footer.Layout.Row = 4;
            obj.ResetButton = dlab.ui.button(footer, "Reset", t, Tag="dlab.reset", ...
                Tooltip="Restore default inputs", ...
                Callback=obj.Shell.callback(@() obj.reset(), "Reset"));
            obj.RunButton = dlab.ui.button(footer, "▶  " + obj.Plugin.RunLabel, t, Kind="primary", ...
                Tag="dlab.run", Tooltip=obj.Plugin.RunLabel + " (Ctrl+R)", ...
                Callback=obj.Shell.callback(@() obj.run(), "Run", AllowBusy=true));
        end

        function buildOutputs(obj, params)
            %BUILDOUTPUTS (Re)create every output tab for PARAMS.
            t = obj.Shell.Theme;
            if ~isempty(obj.PlotBuilder)
                obj.SavedAnalysis = obj.analysisSnapshot();   % tabs are rebuilt below
            end
            if ~isempty(obj.PlaybackBar)
                delete(obj.PlaybackBar);
                obj.PlaybackBar = [];
            end
            delete(obj.Tabs.Children);
            obj.Containers = dictionary(string.empty, cell.empty);
            obj.SummaryTab = [];

            if obj.Plugin.kind() == "time"
                if isempty(obj.Playback)
                    obj.Playback = dlab.core.PlaybackController();
                    obj.Playback.OnError = @(ME) obj.Shell.reportError(ME, "Playback");
                    obj.Listeners(end+1) = listener(obj.Playback, "TimeChanged", @(~, ~) obj.drawFrame());
                end
                tab = obj.newTab("Animation", t);
                grid = uigridlayout(tab, [2 1], RowHeight={"1x", "fit"}, Padding=0, RowSpacing=0, ...
                    BackgroundColor=t.Surface);
                obj.AnimationGrid = uigridlayout(grid, [1 1], Padding=[6 6 6 6], ...
                    BackgroundColor=t.AxesBackground);
                obj.Containers("Animation") = {obj.AnimationGrid};
                obj.Plugin.buildAnimation(obj.AnimationGrid, t);
                obj.PlaybackBar = dlab.core.PlaybackBar(grid, obj.Playback, t);
                obj.Plugin.buildPlaybackControls(obj.PlaybackBar.Extras, t);
            end

            obj.TabTitles = obj.Plugin.outputTabs(params);
            for title = obj.TabTitles
                tab = obj.newTab(title, t);
                obj.Containers(title) = {uigridlayout(tab, [1 1], Padding=[6 6 6 6], ...
                    BackgroundColor=t.AxesBackground)};
            end
            outputs = dictionary(string.empty, cell.empty);
            for title = obj.TabTitles
                outputs(title) = obj.Containers(title);
            end
            obj.Plugin.buildOutputs(outputs, t);
            obj.buildAnalysisTabs(t, params);
        end

        function buildAnalysisTabs(obj, t, params)
            analyze = obj.newTab("Analyze", t);
            grid = uigridlayout(analyze, [1 1], Padding=0, BackgroundColor=t.Surface);
            obj.AnalysisGroup = uitabgroup(grid, Tag="dlab.analysis.tabs", ...
                SelectionChangedFcn=@(~, event) obj.Shell.safeCall(@() obj.tabSelected(event.NewValue), "Tab"));
            obj.buildAnalysisPanels(t, params);
        end

        function buildAnalysisPanels(obj, t, params)
            %BUILDANALYSISPANELS Custom plot, Sweep, Map, Optimize, Uncertainty,
            %   Fit, Modes, and Bode inside Analyze: the same for every simulator,
            %   built from its contract.
            saved = obj.SavedAnalysis;
            obj.SavedAnalysis = [];
            plotSelection = [];
            sweepState = [];
            mapState = [];
            uncertaintyState = [];
            optimizeState = [];
            fitState = [];
            if ~isempty(saved)
                plotSelection = saved.Plot;
                sweepState = saved.Sweep;
                if isfield(saved, "Map")
                    mapState = saved.Map;
                end
                if isfield(saved, "Uncertainty")
                    uncertaintyState = saved.Uncertainty;
                end
                if isfield(saved, "Optimize")
                    optimizeState = saved.Optimize;
                end
                if isfield(saved, "Fit")
                    fitState = saved.Fit;
                end
            end
            obj.PlotBuilder = dlab.core.PlotBuilder(obj.analysisGrid("Custom plot", t), t, plotSelection);
            obj.Containers("Custom plot") = {obj.PlotBuilder.Axes};

            obj.SweepPanel = [];
            specs = obj.Plugin.parameters();
            if ~isempty(dlab.core.SweepPanel.sweepable(specs))
                obj.SweepPanel = dlab.core.SweepPanel(obj.analysisGrid("Sweep", t), specs, ...
                    @() obj.params(), t, sweepState);
                obj.Containers("Sweep") = {obj.SweepPanel.Axes};
                obj.Listeners(end+1) = listener(obj.SweepPanel, "RunRequested", ...
                    @(~, ~) obj.Shell.safeCall(@() obj.runSweep(), "Sweep", AllowBusy=true));
                obj.Listeners(end).Recursive = true;   % pressed again mid-sweep, it cancels
                obj.Listeners(end+1) = listener(obj.SweepPanel, "ExportRequested", ...
                    @(~, ~) obj.Shell.safeCall(@() obj.exportSweep(), "Export sweep"));
            end

            % Map, Optimize, Uncertainty, and Fit: the tabs now, the panels
            % when first shown or needed (analysisPanel).
            [obj.MapPanel, obj.OptimizePanel, obj.UncertaintyPanel, obj.FitPanel] = deal([]);
            sweepable = dlab.core.SweepPanel.sweepable(specs);
            available = struct("Map", numel(sweepable) >= 2, "Optimize", ~isempty(sweepable), ...
                "Uncertainty", ~isempty(sweepable), "Fit", any([specs.Type] == "double" & ~[specs.Display]));
            obj.LazyStates = struct("Map", {mapState}, "Optimize", {optimizeState}, ...
                "Uncertainty", {uncertaintyState}, "Fit", {fitState});
            obj.LazyGrids = struct();
            for name = ["Map" "Optimize" "Uncertainty" "Fit"]
                if available.(name)
                    obj.LazyGrids.(name) = obj.analysisGrid(name, t);
                end
            end
            if ~isempty(obj.MeasuredData)
                obj.PlotBuilder.setMeasured(obj.MeasuredData);     % rebuilt tabs keep the overlay
            end

            obj.ModesPanel = [];
            if obj.Plugin.implements("linearization")
                obj.ModesPanel = dlab.core.ModesPanel(obj.analysisGrid("Modes", t), t);
                obj.Containers("Modes") = {obj.ModesPanel.Axes};
            end

            % Bode: when the linearization has inputs (G and U0).
            obj.FrequencyPanel = [];
            if obj.Plugin.implements("linearization") && hasInputs(obj.Plugin, params)
                obj.FrequencyPanel = dlab.core.FrequencyPanel(obj.analysisGrid("Bode", t), t);
                obj.Containers("Bode") = {obj.FrequencyPanel.PlotGrid};
            end
        end

        function reopenTab(obj, title)
            % Select TITLE if it exists now; a tab that the next result adds
            % is selected when it appears.
            if ismember(title, [obj.tabTitles(), obj.analysisTitles()])
                obj.selectTab(title);
            elseif ismember(title, obj.Plugin.outputTabs(obj.params())) || title == "Summary"
                obj.PendingTab = title;
            end
        end

        function tabSelected(obj, tab)
            % Build a lazily built analysis panel when its tab is first shown.
            if string(tab.Title) == "Analyze"
                tab = obj.AnalysisGroup.SelectedTab;
            end
            title = string(tab.Title);
            if isfield(obj.LazyGrids, title)
                obj.analysisPanel(title);
            end
        end

        function grid = analysisGrid(obj, title, t)
            % A tab inside Analyze.
            tab = uitab(obj.AnalysisGroup, Title=title, BackgroundColor=t.Surface, ...
                ForegroundColor=t.Text, Tag="dlab.tab." + title);
            grid = uigridlayout(tab, [1 1], Padding=[6 6 6 6], BackgroundColor=t.AxesBackground);
        end

        function state = analysisSnapshot(obj)
            state = [];
            if isempty(obj.PlotBuilder) || ~isvalid(obj.PlotBuilder)
                return
            end
            state = struct("Plot", obj.PlotBuilder.Selection, "Sweep", [], "Map", [], "Optimize", [], ...
                "Uncertainty", [], "Fit", []);
            if ~isempty(obj.SweepPanel) && isvalid(obj.SweepPanel)
                state.Sweep = obj.SweepPanel.snapshot();
            end
            for name = ["Map" "Optimize" "Uncertainty" "Fit"]
                panel = obj.(name + "Panel");
                if ~isempty(panel) && isvalid(panel)
                    state.(name) = panel.snapshot();
                elseif isfield(obj.LazyStates, name)
                    state.(name) = obj.LazyStates.(name);      % never built: keep what was saved
                end
            end
        end

        function showAnalysis(obj, result, params)
            %SHOWANALYSIS Fill the analysis tabs that follow each result.
            T = obj.Plugin.exportTable(result);
            obj.PlotBuilder.show(T, obj.keptTables());
            if ~isempty(obj.OptimizePanel)
                obj.OptimizePanel.setMetrics(obj.Plugin.metrics(result));
            end
            if ~isempty(obj.FitPanel)
                obj.FitPanel.setTable(T);
            end
            if isempty(obj.ModesPanel) && isempty(obj.FrequencyPanel)
                return
            end
            try
                lin = obj.Plugin.linearization(params);
            catch ME
                note = "Could not linearize this model: " + ME.message;
                if ~isempty(obj.ModesPanel)
                    obj.ModesPanel.clear(note);
                end
                if ~isempty(obj.FrequencyPanel)
                    obj.FrequencyPanel.clear(note);
                end
                return
            end
            if ~isempty(obj.ModesPanel)
                try
                    obj.ModesPanel.show(lin);
                catch ME
                    obj.ModesPanel.clear("Could not linearize this model: " + ME.message);
                end
            end
            if ~isempty(obj.FrequencyPanel)
                try
                    obj.FrequencyPanel.show(lin);
                    if ~isempty(obj.PendingBode)
                        obj.FrequencyPanel.select(obj.PendingBode(1), obj.PendingBode(2));
                        obj.PendingBode = strings(1, 0);
                    end
                catch ME
                    obj.FrequencyPanel.clear("Could not compute the frequency response: " + ME.message);
                end
            end
        end

        function orderTabs(obj)
            %ORDERTABS Animation, the plugin's tabs, Summary, Runs, then Analyze.
            children = obj.Tabs.Children;
            if isempty(children)
                return
            end
            selected = obj.Tabs.SelectedTab;
            desired = ["Animation", obj.TabTitles, "Summary", "Runs", "Analyze"];
            [~, rank] = ismember(string({children.Title}), desired);
            [sortedRank, order] = sort(rank);
            if ~isequal(sortedRank, rank)
                obj.Tabs.Children = children(order);
                obj.Tabs.SelectedTab = selected;
            end
        end

        function tab = newTab(obj, title, t)
            tab = uitab(obj.Tabs, Title=title, BackgroundColor=t.Surface, ...
                ForegroundColor=t.Text, Tag="dlab.tab." + title);
        end

        % ------------------------------------------------------- behaviour
        function displayResult(obj, result, params)
            if ~isequal(obj.Plugin.outputTabs(params), obj.TabTitles)
                obj.buildOutputs(params);
            end
            obj.Result = result;
            obj.RunParams = params;
            obj.showPluginResult(result, params);
            if obj.PendingTab ~= "" && ismember(obj.PendingTab, obj.tabTitles())
                obj.selectTab(obj.PendingTab);
            end
            obj.PendingTab = "";
            obj.drawOverlays();
            obj.showSummary(obj.Plugin.summaryTable(result));
            obj.showAnalysis(result, params);
            obj.showRuns();
            if ~isempty(obj.Playback)
                t = obj.Plugin.timeVector(result);
                obj.Playback.TimeScale = obj.Plugin.playbackRate(result);
                obj.Playback.load(t(1), t(end));
                obj.PlaybackBar.refresh();
            end
        end

        function clearOutputs(obj)
            obj.Result = [];
            obj.RunParams = struct();
            obj.Runs = obj.Runs([]);
            obj.Plugin.clearResult();
            obj.showRuns();
            obj.PlotBuilder.clear();
            if ~isempty(obj.ModesPanel)
                obj.ModesPanel.clear();
            end
            if ~isempty(obj.FrequencyPanel)
                obj.FrequencyPanel.clear();
            end
            if ~isempty(obj.Playback)
                obj.Playback.load(0, 0);
                obj.PlaybackBar.refresh();
            end
            if ~isempty(obj.SummaryTab) && isvalid(obj.SummaryTab)
                delete(obj.SummaryTab);
                obj.SummaryTab = [];
            end
            obj.setStale(false);
            if obj.Plugin.kind() == "static"
                obj.Plugin.previewInputs(obj.params());
            end
        end

        function showSummary(obj, T)
            if isempty(T) || height(T) == 0
                if ~isempty(obj.SummaryTab) && isvalid(obj.SummaryTab)
                    delete(obj.SummaryTab);
                end
                obj.SummaryTab = [];
                return
            end
            t = obj.Shell.Theme;
            if isempty(obj.SummaryTab) || ~isvalid(obj.SummaryTab)
                obj.SummaryTab = obj.newTab("Summary", t);
                % Headings as labels, which follow the text size (a uitable's
                % own headings keep one small size); the table is exactly as
                % tall as its rows, and the tab scrolls when they do not fit.
                grid = uigridlayout(obj.SummaryTab, [2 1], RowHeight={round(t.scaled(24)), 0}, ...
                    Padding=[12 12 12 12], RowSpacing=0, Scrollable="on", BackgroundColor=t.Surface);
                headings = uigridlayout(grid, [1 3], ColumnWidth=obj.SummaryColumns, Padding=[6 0 0 0], ...
                    ColumnSpacing=0, BackgroundColor=t.Surface);
                for name = ["Quantity" "Value" "Units"]
                    label = dlab.ui.label(headings, upper(name), t, Role="heading");
                    label.FontSize = t.FontSize.sm + 1;
                end
                obj.SummaryTable = uitable(grid, RowName={}, ColumnName={}, Tag="dlab.summary", ...
                    ColumnWidth=obj.SummaryColumns, BackgroundColor=t.SurfaceRaised, ...
                    ForegroundColor=t.Text, FontSize=t.FontSize.md);
                obj.orderTabs();
            end
            obj.SummaryTable.Data = table(string(T.Quantity), dlab.core.RunReport.summaryText(T), ...
                string(T.Units), VariableNames=["Quantity" "Value" "Units"]);
            obj.SummaryTable.Parent.RowHeight{2} = round(height(T) * dlab.ui.tableRowHeight(t.FontSize.md)) + 2;
        end

        % ------------------------------------------------------ comparison
        function refreshComparison(obj)
            if isempty(obj.Result)
                obj.showRuns();
                return
            end
            obj.drawOverlays();
            obj.PlotBuilder.show(obj.Plugin.exportTable(obj.Result), obj.keptTables());
            obj.showRuns();
        end

        function drawOverlays(obj)
            %DRAWOVERLAYS Kept runs, faint, on the plugin's plots.
            delete(findall(obj.Tabs, Tag="dlab.overlay"));
            if ~isempty(obj.Runs) && obj.Plugin.implements("overlayRuns")
                obj.Plugin.overlayRuns(obj.keptRuns());
            end
        end

        function runs = keptRuns(obj)
            %KEPTRUNS The kept runs as plugins and tables see them.
            t = obj.Shell.Theme;
            runs = struct("Result", {}, "Params", {}, "Label", {}, "Color", {}, "Index", {});
            for k = 1:numel(obj.Runs)
                runs(k) = struct("Result", {obj.Runs(k).Result}, "Params", obj.Runs(k).Params, ...
                    "Label", "Run " + k, "Color", t.series(k + 1), "Index", k);
            end
        end

        function tables = keptTables(obj)
            runs = obj.keptRuns();
            tables = struct("Table", {}, "Label", {}, "Color", {});
            for k = 1:numel(runs)
                tables(k) = struct("Table", obj.Plugin.exportTable(runs(k).Result), ...
                    "Label", runs(k).Label, "Color", runs(k).Color);
            end
        end

        function showRuns(obj)
            %SHOWRUNS The Runs tab: every kept run and the current one, with
            %   the inputs that differ and the key results side by side.
            if isempty(obj.Runs) || isempty(obj.Result)
                if ~isempty(obj.RunsTab) && isvalid(obj.RunsTab)
                    delete(obj.RunsTab);
                end
                obj.RunsTab = [];
                return
            end
            t = obj.Shell.Theme;
            if isempty(obj.RunsTab) || ~isvalid(obj.RunsTab)
                obj.RunsTab = obj.newTab("Runs", t);
                grid = uigridlayout(obj.RunsTab, [1 1], Padding=[12 12 12 12], BackgroundColor=t.Surface);
                obj.RunsTable = uitable(grid, RowName={}, Tag="dlab.runs", ...
                    BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, FontSize=t.FontSize.md);
                obj.orderTabs();
            end

            runs = obj.keptRuns();
            results = [{runs.Result}, {obj.Result}];
            params = [{runs.Params}, {obj.RunParams}];
            names = [[runs.Label], "Current"];
            colors = [reshape([runs.Color], 3, [])'; t.series(1)];
            metrics = cellfun(@(r) obj.Plugin.metrics(r), results, UniformOutput=false);
            quantities = unique(string(vertcat(metrics{:}).Quantity), "stable")';
            data = cell(numel(results), 2 + numel(quantities));
            for k = 1:numel(results)
                data{k, 1} = char(names(k));
                data{k, 2} = char(obj.describeInputs(params{k}, obj.RunParams));
                M = metrics{k};
                for q = 1:numel(quantities)
                    value = M.Value(M.Quantity == quantities(q));
                    if ~isempty(value)
                        data{k, 2 + q} = round(value(1), 6, "significant");
                    end
                end
            end
            units = strings(size(quantities));
            combined = vertcat(metrics{:});
            for q = 1:numel(quantities)
                unit = combined.Units(find(combined.Quantity == quantities(q), 1));
                units(q) = quantities(q);
                if unit ~= ""
                    units(q) = quantities(q) + " (" + unit + ")";
                end
            end
            obj.RunsTable.ColumnName = cellstr(["Run", "Inputs that differ from the current run", units]);
            obj.RunsTable.ColumnFormat = [{'char' 'char'}, repmat({'shortG'}, 1, numel(units))];
            obj.RunsTable.Data = data;
            removeStyle(obj.RunsTable);
            for k = 1:numel(results)
                addStyle(obj.RunsTable, uistyle(FontColor=colors(k, :), FontWeight="bold"), "cell", [k 1]);
            end
        end

        function text = describeInputs(obj, params, reference)
            %DESCRIBEINPUTS "Launch angle = 60 deg, Mass = 2 kg" for the
            %   solve inputs where PARAMS differs from REFERENCE.
            specs = obj.Plugin.parameters();
            parts = strings(0);
            for name = changedFields(obj.solveRelevant(params), obj.solveRelevant(reference))
                if ismember(name, [specs.Name])
                    spec = dlab.core.ParamSpec.find(specs, name);
                    value = params.(name);
                    if isnumeric(value)
                        value = string(sprintf("%.4g", value));
                    elseif istable(value)
                        value = sprintf("%d rows (edited)", height(value));
                    elseif isstruct(value)
                        value = dlab.core.Schedule.describe(value, spec.Units);
                    end
                    part = spec.Label + " = " + string(value);
                    if spec.Units ~= "" && isnumeric(params.(name))
                        part = part + " " + spec.Units;
                    end
                else
                    part = name + " differs";
                end
                parts(end+1) = part; %#ok<AGROW>
            end
            if isempty(parts)
                text = "(same inputs)";
            else
                text = strjoin(parts, ", ");
            end
        end

        function drawFrame(obj)
            if ~isempty(obj.Result) && ~obj.Redrawing
                obj.Plugin.drawFrame(obj.Playback.Time);
                drawnow limitrate
            end
        end

        function showPluginResult(obj, result, params)
            % A playback tick while the plugin rebuilds its axes would draw
            % on the handles it has just deleted (a display option changed
            % during playback), so frames wait until it is done.
            obj.Redrawing = true;
            try
                obj.Plugin.showResult(result, params);
            catch err
                obj.Redrawing = false;
                rethrow(err);
            end
            obj.Redrawing = false;
            dlab.ui.padLimits(obj.Tabs);        % no steady trace on a plot's frame
        end

        function onInputChanged(obj, name)
            obj.History.record(obj.LastState);
            settle = onCleanup(@() obj.inputsSettled());
            params = obj.params();
            adjusted = obj.Plugin.onParamChanged(name, params);
            if ~isequal(adjusted, params)
                obj.Inputs.setValues(adjusted);
                params = obj.params();
            end
            specs = obj.Plugin.parameters();
            isSpec = ismember(name, [specs.Name]);   % custom inputs may use other names
            if isSpec && dlab.core.ParamSpec.find(specs, name).Display
                obj.redisplay(params);
                return
            end
            if ~isSpec || dlab.core.ParamSpec.find(specs, name).MarksCustom
                obj.Preset = "Custom";
                obj.selectPreset(obj.CustomKey);
            end
            obj.updateStale();
            if obj.Plugin.kind() == "static"
                obj.Plugin.previewInputs(params);
            end
        end

        function redisplay(obj, params)
            %REDISPLAY Apply presentation-only (Display) settings to what is
            %   on screen: the current result if it is up to date, otherwise
            %   the input preview.
            specs = obj.Plugin.parameters();
            if ~isempty(obj.Result) && ~obj.IsStale
                for spec = specs([specs.Display])'
                    obj.RunParams.(spec.Name) = params.(spec.Name);
                end
                obj.showPluginResult(obj.Result, obj.RunParams);
                obj.drawOverlays();
                if ~isempty(obj.Playback)
                    obj.drawFrame();
                end
            elseif obj.Plugin.kind() == "static"
                obj.Plugin.previewInputs(params);
            end
        end

        function setInputs(obj, params)
            obj.Inputs.setValues(params);
            obj.updateStale();
            if obj.Plugin.kind() == "static"
                obj.Plugin.previewInputs(obj.params());
            end
        end

        function setStale(obj, stale)
            obj.IsStale = stale;
            obj.Shell.setStale(stale);
        end

        function updateStale(obj)
            %UPDATESTALE Results are stale when any solve-relevant input
            %   differs from the inputs that produced them.
            if isempty(obj.Result)
                obj.setStale(false);
                return
            end
            obj.setStale(~isequaln(obj.solveRelevant(obj.params()), obj.solveRelevant(obj.RunParams)));
        end

        function params = solveRelevant(obj, params)
            specs = obj.Plugin.parameters();
            display = string({specs([specs.Display]).Name});   % 1×0 when there are none
            params = rmfield(params, intersect(display, string(fieldnames(params))));
        end

        function beginTask(obj, label)
            t = obj.Shell.Theme;
            obj.IsBusy = true;
            obj.CancelRequested = false;
            obj.BusyLabel = label;
            obj.BusyClock = tic;
            obj.LastProgressDraw = -Inf;
            if ~isempty(obj.Playback)
                obj.Playback.pause();
                obj.PlaybackBar.setEnabled(false);
            end
            set(obj.RunButton, Text="■  Cancel", BackgroundColor=t.Danger, FontColor=t.OnDanger, ...
                Tooltip="Cancel (Esc)");
            set([obj.ResetButton obj.KeepCheckbox obj.HeaderControls], Enable="off");
            obj.Inputs.setEnabled(false);
            obj.Shell.setStatus(label);
            drawnow
        end

        function endTask(obj)
            t = obj.Shell.Theme;
            obj.IsBusy = false;
            if ~isvalid(obj.RunButton)
                return
            end
            set(obj.RunButton, Text="▶  " + obj.Plugin.RunLabel, BackgroundColor=t.Accent, ...
                FontColor=t.OnAccent, Tooltip=obj.Plugin.RunLabel + " (Ctrl+R)");
            set([obj.ResetButton obj.KeepCheckbox obj.HeaderControls], Enable="on");
            obj.Inputs.setEnabled(true);
            if ~isempty(obj.PlaybackBar)
                obj.PlaybackBar.setEnabled(true);
            end
            obj.refreshHistoryButtons();
        end

        % ---------------------------------------------------------- history
        function state = currentState(obj)
            state = struct("Params", obj.params(), "Preset", obj.Preset, ...
                "PresetKey", string(obj.PresetDropdown.Value));
        end

        function inputsSettled(obj)
            %INPUTSSETTLED The inputs on screen are the undo point for the next edit.
            if isvalid(obj)
                obj.LastState = obj.currentState();
                obj.refreshHistoryButtons();
            end
        end

        function restoreState(obj, state)
            specs = obj.Plugin.parameters();
            changed = changedFields(obj.params(), state.Params);
            displayOnly = ~isempty(changed) && all(ismember(changed, string({specs([specs.Display]).Name})));
            if displayOnly
                obj.Inputs.setValues(state.Params);
                obj.redisplay(state.Params);
            else
                obj.setInputs(state.Params);
            end
            obj.Preset = state.Preset;
            if ismember(state.PresetKey, string(obj.PresetDropdown.ItemsData))
                obj.PresetDropdown.Value = state.PresetKey;
            else
                obj.PresetDropdown.Value = obj.CustomKey;
            end
            obj.inputsSettled();
        end

        function refreshHistoryButtons(obj)
            if ~isempty(obj.UndoButton) && isvalid(obj.UndoButton) && ~obj.IsBusy
                obj.UndoButton.Enable = obj.History.canUndo();
                obj.RedoButton.Enable = obj.History.canRedo();
            end
        end

        function text = describeChange(obj, from, to)
            %DESCRIBECHANGE ": Length, Damping" for the inputs that differ,
            %   in the order the input panel lists them (others last).
            labels = strings(0);
            specs = obj.Plugin.parameters();
            changed = changedFields(from, to);
            [~, rank] = ismember(changed, [specs.Name]);
            rank(rank == 0) = numel(specs) + 1;
            [~, order] = sort(rank);
            for name = changed(order)
                if ismember(name, [specs.Name])
                    labels(end+1) = dlab.core.ParamSpec.find(specs, name).Label; %#ok<AGROW>
                else
                    labels(end+1) = name; %#ok<AGROW>
                end
            end
            text = "";
            if ~isempty(labels)
                text = ": " + strjoin(labels(1:min(3, end)), ", ");
                if numel(labels) > 3
                    text = text + sprintf(" and %d more", numel(labels) - 3);
                end
            end
        end

        function ok = requireResult(obj)
            ok = ~isempty(obj.Result);
            if ~ok
                obj.Shell.setStatus("Run the simulation first.", "warning");
            end
        end

        function offerSwitch(obj, simulatorId, file, confirm)
            known = [obj.Shell.simulators().Id];
            if ~ismember(simulatorId, known)
                error("dlab:scenario:wrongSimulator", ...
                    "This scenario is for ""%s"", which is not available.", simulatorId);
            end
            if confirm
                choice = uiconfirm(obj.Shell.Figure, ...
                    "This scenario belongs to another simulator. Open it there?", ...
                    "Different simulator", Options=["Open" "Cancel"]);
                if choice ~= "Open"
                    return
                end
            end
            shell = obj.Shell;
            shell.open(simulatorId);          % closes and deletes this view
            shell.View.loadScenario(file, Confirm=false);
        end

        % --------------------------------------------------------- presets
        function refreshPresetItems(obj)
            builtin = string({obj.Plugin.presets().Name});
            files = dir(fullfile(dlab.core.Paths.scenarios(obj.Plugin.Id), "*.json"));
            userFiles = string(fullfile({files.folder}, {files.name}));
            userNames = string(erase({files.name}, ".json"));
            current = obj.PresetDropdown.Value;

            obj.PresetDropdown.Items = ["Defaults", builtin, "My: " + userNames, "Custom"];
            obj.PresetDropdown.ItemsData = [obj.DefaultsKey, "builtin:" + builtin, ...
                "user:" + userFiles, obj.CustomKey];
            if ~isempty(current) && ismember(current, obj.PresetDropdown.ItemsData)
                obj.PresetDropdown.Value = current;
            else
                obj.PresetDropdown.Value = obj.keyForPreset(obj.Preset);
            end
        end

        function key = keyForPreset(obj, name)
            data = string(obj.PresetDropdown.ItemsData);
            if name == "Defaults"
                key = obj.DefaultsKey;
            elseif ismember("builtin:" + name, data)
                key = "builtin:" + name;
            else
                match = data(startsWith(data, "user:") & endsWith(data, filesep + name + ".json"));
                if isempty(match)
                    key = obj.CustomKey;
                else
                    key = match(1);
                end
            end
        end

        function selectPreset(obj, key)
            if ismember(key, string(obj.PresetDropdown.ItemsData))
                obj.PresetDropdown.Value = key;
            end
            if key == obj.DefaultsKey
                obj.Preset = "Defaults";
            end
        end

        function file = defaultExportName(obj, extension, suffix)
            arguments
                obj
                extension (1,1) string
                suffix (1,1) string = ""
            end
            stamp = string(datetime("now", Format="yyyyMMdd-HHmmss"));
            name = obj.Plugin.Id + "-" + stamp;
            if suffix ~= ""
                name = name + "-" + lower(regexprep(suffix, "\W+", "-"));
            end
            file = fullfile(dlab.core.Paths.exports(), name + "." + extension);
        end
    end
end

function file = askFile(mode, filter, title, default)
if mode == "put"
    [name, folder] = uiputfile(filter, title, default);
else
    [name, folder] = uigetfile(filter, title, default);
end
if isequal(name, 0)
    file = "";
else
    file = string(fullfile(folder, name));
end
end

function name = fileName(file, withExtension)
arguments
    file (1,1) string
    withExtension (1,1) logical = false
end
[~, name, extension] = fileparts(file);
if withExtension
    name = name + extension;
end
end

function names = changedFields(a, b)
names = strings(1, 0);
for name = union(string(fieldnames(a)), string(fieldnames(b)))'
    if ~isfield(a, name) || ~isfield(b, name) || ~isequaln(a.(name), b.(name))
        names(end+1) = name; %#ok<AGROW>
    end
end
end

function setRunningIfValid(panel)
if isvalid(panel)
    panel.setRunning(false);
end
end

function clearProgress(plugin)
if isvalid(plugin)
    plugin.ProgressFcn = [];
end
end

function tf = hasInputs(plugin, params)
% Whether PLUGIN's linearization for PARAMS drives inputs (Bode tab).
try
    tf = dlab.core.FrequencyResponse.available(plugin.linearization(params));
catch
    tf = false;
end
end

function a = mapAxis(s)
% A lesson's map axis (name, from, to, steps, log) as MapPanel.configure takes it.
a = struct("Name", string(s.name), "From", s.from, "To", s.to, "Steps", s.steps, ...
    "Log", isfield(s, "log") && logical(s.log));
end

function value = lessonField(s, name, default)
% An optional field of a lesson setup.
value = default;
if isfield(s, name)
    value = s.(name);
end
end

function wide = wideInputsSetting(plugin)
% Whether PLUGIN's input panel starts wide: as the learner last left it,
% else wide when it has table inputs.
saved = dlab.core.Settings.get(dlab.core.SimulatorView.WideInputsSetting, struct());
if isstruct(saved) && isfield(saved, plugin.Id) && islogical(saved.(plugin.Id)) && isscalar(saved.(plugin.Id))
    wide = saved.(plugin.Id);
else
    specs = plugin.parameters();
    wide = any([specs.Type] == "table");
end
end

function text = widthButtonText(wide)
if wide
    text = "◂ Narrower";
else
    text = "Wider ▸";
end
end
