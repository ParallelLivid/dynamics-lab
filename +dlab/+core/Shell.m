classdef Shell < handle
    %SHELL The Dynamics Lab window: header, content area, status bar.
    %   Owns the single uifigure and swaps the content between the Home
    %   menu and one simulator at a time. Theme changes rebuild everything
    %   from the Session snapshot, so no component needs restyling code.
    %
    %       app = dlab.core.Shell();           % Home screen
    %       app.open("pendulum");              % a simulator
    %       app.setTheme("light");

    properties (SetAccess = private)
        Figure
        Theme                     % dlab.ui.Theme
        Session                   % dlab.core.Session
        View                      % dlab.core.HomeView or dlab.core.SimulatorView
        HeaderSlot                % uigridlayout views fill with their controls
        LastError = []                 % the last error reported (an MException), [] if none
        PendingClose (1,1) logical = false   % closed while a task ran; close when it ends
    end

    properties (Access = private)
        PluginFactories cell
        Metadata struct
        Content
        HomeButton
        Crumb
        StatusLabel
        StaleLabel
        HeaderGrid
    end

    properties (Constant)
        MinimumSize = [1000 650]
        DefaultSize = [1400 860]
        ShortcutHelp = join([
            "Keyboard shortcuts"
            "  Ctrl+R or F5     Run (Esc cancels a running task)"
            "  Ctrl+Z / Ctrl+Y  Undo / redo input changes"
            "  Ctrl+S / Ctrl+O  Save / load a scenario"
            "  Space            Play / pause the animation"
            "  ← / →            Step back / forward (Shift: 10 frames)"
            "  Home             Back to the start of the animation"
        ], newline)
    end

    methods
        function obj = Shell(options)
            arguments
                options.Plugins cell = dlab.sims.registry()
                options.Theme (1,1) string = ""
                options.Visible (1,1) logical = true
            end
            obj.PluginFactories = options.Plugins(:)';
            obj.Metadata = obj.readMetadata();
            obj.Session = dlab.core.Session();

            name = options.Theme;
            if name == ""
                name = string(dlab.core.Settings.get("theme", "dark"));
            end
            if ~ismember(name, dlab.ui.Theme.Names)
                name = "dark";
            end
            textSize = string(dlab.core.Settings.get("textSize", "normal"));
            if ~ismember(textSize, dlab.ui.Theme.TextSizes)
                textSize = "normal";
            end
            obj.Theme = dlab.ui.Theme.byName(name, textSize);

            obj.Figure = uifigure(Name="Dynamics Lab", Visible="off", ...
                Position=centeredPosition(obj.DefaultSize), AutoResizeChildren="off", ...
                CloseRequestFcn=@(~, ~) obj.close(), ...
                SizeChangedFcn=@(src, ~) obj.onResized(src), ...
                WindowKeyPressFcn=@(~, evt) obj.safeCall(@() obj.onKey(evt), "Keyboard", AllowBusy=true));
            obj.buildChrome();
            obj.goHome();
            obj.Figure.Visible = options.Visible;
            obj.View.focusSearch();
        end

        function info = simulators(obj)
            %SIMULATORS Metadata of every available simulator (struct array:
            %   Id, Title, Category, Summary, Kind).
            info = obj.Metadata;
        end

        function goHome(obj)
            obj.closeView();
            obj.HomeButton.Visible = "off";
            obj.HeaderGrid.ColumnWidth{1} = 0;
            obj.Crumb.Text = "";
            obj.Figure.Name = "Dynamics Lab";
            obj.View = dlab.core.HomeView(obj.Content, obj);
            obj.setStatus("Choose a simulator.");
        end

        function open(obj, id)
            %OPEN Show simulator ID, restoring its previous state if any.
            arguments
                obj
                id (1,1) string
            end
            plugin = obj.createPlugin(id);
            obj.closeView();
            obj.HomeButton.Visible = "on";
            obj.HeaderGrid.ColumnWidth{1} = 96;
            obj.Crumb.Text = "›  " + plugin.Title;
            obj.Figure.Name = "Dynamics Lab — " + plugin.Title;
            state = obj.Session.get(id);
            if isempty(state)
                % First time this launch: reopen on the tab and analysis
                % set-ups it was left with last time.
                view = dlab.core.Recent.lastView(id);
                if ~isempty(view)
                    state = dlab.core.Session.newState(Params=plugin.defaultParams(), ...
                        Analysis=view.Analysis, Tab=view.Tab);
                end
                obj.setStatus("Set the inputs and press " + plugin.RunLabel + ".");
            elseif isempty(state.Result)
                obj.setStatus("Restored your previous inputs.");
            else
                obj.setStatus("Restored your previous inputs and result.");
            end
            obj.View = dlab.core.SimulatorView(obj.Content, obj, plugin, state);
        end

        function resume(obj, id)
            %RESUME Open simulator ID with the inputs it was last left with
            %   (this session's state if any, else the saved inputs).
            arguments
                obj
                id (1,1) string
            end
            if obj.Session.has(id)
                obj.open(id);
                return
            end
            obj.open(id);
            [params, preset] = dlab.core.Recent.lastInputs(obj.View.Plugin);
            if ~isempty(params)
                obj.View.restoreInputs(params, preset);
                obj.setStatus("Restored your inputs from last time.");
            end
        end

        function openScenario(obj, file)
            %OPENSCENARIO Open the simulator a scenario file belongs to and load it.
            arguments
                obj
                file (1,1) string
            end
            if ~isfile(file)
                error("dlab:scenario:missing", "The scenario file ""%s"" no longer exists.", file);
            end
            obj.open(dlab.core.ScenarioIO.read(file).simulator);
            obj.View.loadScenario(file, Confirm=false);
        end

        function startLesson(obj, id)
            %STARTLESSON Open lesson ID in its simulator, where the learner left off.
            arguments
                obj
                id (1,1) string
            end
            lesson = dlab.core.Lesson.load(id);
            missing = setdiff(dlab.core.Lesson.simulators(lesson), [obj.Metadata.Id], "stable");
            if ~isempty(missing)
                error("dlab:lesson:simulator", "This lesson needs the ""%s"" simulator.", missing(1));
            end
            progress = dlab.core.Lesson.progress(id);
            step = min(progress.Step, numel(lesson.steps));
            if progress.Done
                step = 1;
            end
            obj.continueLesson(lesson, step, false(1, 0));
            obj.setStatus("Lesson: " + lesson.title);
        end

        function continueLesson(obj, lesson, step, passed)
            %CONTINUELESSON Show STEP of LESSON in the simulator that step
            %   uses (opening it if needed), keeping the steps PASSED so far.
            id = dlab.core.Lesson.stepSimulator(lesson, step);
            if ~isa(obj.View, "dlab.core.SimulatorView") || obj.View.Plugin.Id ~= id
                obj.open(id);
            end
            obj.View.startLesson(lesson, struct("Step", step, "Passed", passed));
            dlab.core.Lesson.saveProgress(lesson.id, step, false);
        end

        function setTheme(obj, name)
            arguments
                obj
                name (1,1) string {mustBeMember(name, ["dark" "light"])}
            end
            if name == obj.Theme.Name
                return
            end
            obj.rebuild(dlab.ui.Theme.byName(name, obj.Theme.TextSize));
            dlab.core.Settings.set("theme", name);
            obj.setStatus("Switched to the " + name + " theme.");
        end

        function toggleTheme(obj)
            obj.setTheme(obj.Theme.toggled().Name);
        end

        function setTextSize(obj, textSize)
            %SETTEXTSIZE "normal", "large", or "larger" text throughout,
            %   remembered between sessions.
            arguments
                obj
                textSize (1,1) string {mustBeMember(textSize, ["normal" "large" "larger"])}
            end
            if textSize == obj.Theme.TextSize
                return
            end
            obj.rebuild(obj.Theme.withTextSize(textSize));
            dlab.core.Settings.set("textSize", textSize);
            obj.setStatus("Text size: " + textSize + ".");
        end

        function cycleTextSize(obj)
            sizes = dlab.ui.Theme.TextSizes;
            k = find(sizes == obj.Theme.TextSize, 1);
            obj.setTextSize(sizes(mod(k, numel(sizes)) + 1));
        end

        function setStatus(obj, message, level)
            %SETSTATUS Status bar text. LEVEL: info | success | warning | error.
            arguments
                obj
                message (1,1) string
                level (1,1) string {mustBeMember(level, ["info" "success" "warning" "error"])} = "info"
            end
            colors = struct("info", obj.Theme.TextMuted, "success", obj.Theme.Success, ...
                "warning", obj.Theme.Warning, "error", obj.Theme.Danger);
            obj.StatusLabel.Text = message;
            obj.StatusLabel.FontColor = colors.(level);
        end

        function setStale(obj, stale)
            obj.StaleLabel.Visible = stale;
        end

        function reportError(obj, ME, context)
            %REPORTERROR Status-bar message for expected errors; for anything
            %   else also log it and alert the user (with the log location).
            arguments
                obj
                ME (1,1) MException
                context (1,1) string = ""
            end
            obj.LastError = ME;
            message = dlab.core.ErrorLog.userMessage(ME);
            obj.setStatus(message, "error");
            if ~dlab.core.ErrorLog.isExpected(ME)
                logFile = dlab.core.ErrorLog.write(ME, context);
                if isvalid(obj.Figure) && obj.Figure.Visible
                    uialert(obj.Figure, message + newline + newline + "Details were written to:" ...
                        + newline + logFile, "Something went wrong", Icon="error");
                end
            end
        end

        function safeCall(obj, fn, context, options)
            %SAFECALL Run a UI callback; errors are reported, never thrown.
            %   While a busy task runs (a solve can let other callbacks run),
            %   callbacks are ignored unless AllowBusy is true.
            arguments
                obj
                fn
                context (1,1) string = ""
                options.AllowBusy (1,1) logical = false
            end
            if ~options.AllowBusy && obj.isBusy()
                return
            end
            try
                fn();
            catch ME
                obj.reportError(ME, context);
            end
        end

        function cb = callback(obj, fn, context, options)
            %CALLBACK Wrap FN (no arguments) as a safe component callback.
            arguments
                obj
                fn
                context (1,1) string = ""
                options.AllowBusy (1,1) logical = false
            end
            cb = @(~, ~) obj.safeCall(fn, context, AllowBusy=options.AllowBusy);
        end

        function tf = isBusy(obj)
            %ISBUSY Whether the open simulator is running a task.
            tf = isa(obj.View, "dlab.core.SimulatorView") && isvalid(obj.View) && obj.View.IsBusy;
        end

        function onKey(obj, evt)
            %ONKEY Window-level keyboard shortcuts (ShortcutHelp).
            key = lower(string(evt.Key));
            modifiers = string(evt.Modifier);
            ctrl = any(ismember(modifiers, ["control" "command"]));
            shift = any(modifiers == "shift");
            if key == "escape"
                if obj.isBusy()
                    obj.View.cancel();
                end
                return
            end
            if obj.isBusy() || ~isa(obj.View, "dlab.core.SimulatorView")
                return
            end
            obj.View.handleKey(key, ctrl, shift, focusKind(obj.Figure.CurrentObject));
        end

        function plugin = createPlugin(obj, id)
            k = find([obj.Metadata.Id] == id, 1);
            if isempty(k)
                error("dlab:unknownSimulator", "There is no simulator called ""%s"".", id);
            end
            plugin = obj.PluginFactories{k}();
        end

        function showAbout(obj)
            if isa(obj.View, "dlab.core.SimulatorView")
                plugin = obj.View.Plugin;
                uialert(obj.Figure, plugin.about() + newline + newline + obj.ShortcutHelp, ...
                    "About " + plugin.Title, Icon="info");
            else
                uiconfirm(obj.Figure, "Dynamics Lab " + dlab.version() + newline + newline + ...
                    "Interactive physics simulators sharing one interface." + newline + ...
                    "User files: " + dlab.core.Paths.userData(), "About Dynamics Lab", Icon="info", ...
                    Options=["OK" "Show the welcome"], DefaultOption=1, CancelOption=1, ...
                    CloseFcn=@(~, evt) obj.aboutClosed(evt.SelectedOption));
            end
        end

        function showWelcome(obj)
            %SHOWWELCOME Show the welcome banner on Home again (and go Home).
            dlab.core.HomeView.showWelcomeAgain();
            obj.goHome();
        end

        function close(obj)
            if obj.isBusy()
                % Let the running task stop first; it closes the window when it ends.
                obj.PendingClose = true;
                obj.View.cancel();
                return
            end
            obj.closeView();
            dlab.core.PlaybackController.stopAll();
            if isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.close();
            end
        end
    end

    methods (Access = private)
        function onResized(obj, fig)
            enforceMinimumSize(fig, obj.MinimumSize);
            if isa(obj.View, "dlab.core.HomeView") && isvalid(obj.View)
                obj.View.resized();
            end
        end

        function aboutClosed(obj, choice)
            if choice == "Show the welcome"
                obj.safeCall(@() obj.showWelcome(), "Welcome");
            end
        end

        function buildChrome(obj)
            t = obj.Theme;
            dlab.ui.applyFigureTheme(obj.Figure, t);
            root = uigridlayout(obj.Figure, [3 1], RowHeight={52, "1x", 28}, ...
                RowSpacing=0, Padding=0, BackgroundColor=t.Background);

            obj.HeaderGrid = uigridlayout(root, [1 8], ...
                ColumnWidth={96, "fit", "fit", "1x", "fit", 40, 44, 44}, RowHeight={34}, ...
                ColumnSpacing=t.Spacing.sm, Padding=[t.Spacing.md 9 t.Spacing.md 9], ...
                BackgroundColor=t.Surface);
            obj.HomeButton = dlab.ui.button(obj.HeaderGrid, "⌂  Home", t, Kind="ghost", ...
                Tag="dlab.home", Tooltip="Back to the simulator list", ...
                Callback=obj.callback(@() obj.goHome(), "Home"));
            title = dlab.ui.label(obj.HeaderGrid, "Dynamics Lab", t, Role="title");
            title.FontColor = t.Accent;
            obj.Crumb = dlab.ui.label(obj.HeaderGrid, "", t, Role="title", Tag="dlab.crumb");
            uilabel(obj.HeaderGrid, Text="");   % spacer
            obj.HeaderSlot = uigridlayout(obj.HeaderGrid, [1 1], Padding=0, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface, ColumnWidth={"fit"});
            dlab.ui.button(obj.HeaderGrid, "?", t, Kind="ghost", Tag="dlab.about", ...
                Tooltip="About", Callback=obj.callback(@() obj.showAbout(), "About"));
            dlab.ui.button(obj.HeaderGrid, "Aa", t, Kind="ghost", Tag="dlab.textsize", ...
                Tooltip="Text size: " + t.TextSize + " (click for the next size)", ...
                Callback=obj.callback(@() obj.cycleTextSize(), "Text size"));
            other = t.toggled().Name;
            dlab.ui.button(obj.HeaderGrid, "◐", t, Kind="ghost", Tag="dlab.theme", ...
                Tooltip="Switch to the " + other + " theme", ...
                Callback=obj.callback(@() obj.toggleTheme(), "Theme"));

            obj.Content = uigridlayout(root, [1 1], Padding=0, BackgroundColor=t.Background);

            status = uigridlayout(root, [1 3], ColumnWidth={"1x", "fit", "fit"}, RowHeight={20}, ...
                Padding=[t.Spacing.md 4 t.Spacing.md 4], ColumnSpacing=t.Spacing.lg, ...
                BackgroundColor=t.Surface);
            obj.StatusLabel = dlab.ui.label(status, "", t, Role="muted", Tag="dlab.status");
            obj.StaleLabel = dlab.ui.label(status, "⚠ Inputs changed since the last run", t, ...
                Role="muted", Tag="dlab.stale");
            obj.StaleLabel.FontColor = t.Warning;
            obj.StaleLabel.Visible = "off";
            dlab.ui.label(status, "v" + dlab.version(), t, Role="muted");
        end

        function rebuild(obj, theme)
            %REBUILD Redraw the window with THEME, reopening what was open
            %   (the session keeps its inputs and results).
            reopen = "";
            if isa(obj.View, "dlab.core.SimulatorView")
                reopen = obj.View.Plugin.Id;
            end
            obj.closeView();
            obj.Theme = theme;
            delete(obj.Figure.Children);
            obj.buildChrome();
            if reopen == ""
                obj.goHome();
            else
                obj.open(reopen);
            end
        end

        function closeView(obj)
            if isa(obj.View, "dlab.core.SimulatorView") && isvalid(obj.View)
                dlab.core.Recent.noteSimulator(obj.View.Plugin, obj.View.params(), obj.View.Preset);
                dlab.core.Recent.noteView(obj.View.Plugin.Id, obj.View.viewState());
            end
            if ~isempty(obj.View) && isvalid(obj.View)
                obj.View.close();
            end
            obj.View = [];
            if ~isempty(obj.HeaderSlot) && isvalid(obj.HeaderSlot)
                delete(obj.HeaderSlot.Children);
                obj.HeaderSlot.ColumnWidth = {"fit"};
            end
            if ~isempty(obj.Content) && isvalid(obj.Content)
                delete(obj.Content.Children);
            end
            if ~isempty(obj.StaleLabel) && isvalid(obj.StaleLabel)
                obj.setStale(false);
            end
        end

        function info = readMetadata(obj)
            info = struct("Id", {}, "Title", {}, "Category", {}, "Summary", {}, ...
                "Kind", {});
            for k = 1:numel(obj.PluginFactories)
                plugin = obj.PluginFactories{k}();
                info(k) = struct("Id", string(plugin.Id), "Title", string(plugin.Title), ...
                    "Category", string(plugin.Category), "Summary", string(plugin.Summary), ...
                    "Kind", plugin.kind());
                delete(plugin);
            end
            ids = [info.Id];
            assert(numel(unique(ids)) == numel(ids), "dlab:duplicateSimulator", ...
                "Two simulators share an Id.");
        end
    end
end

function position = centeredPosition(size)
screen = get(groot, "ScreenSize");
size = min(size, max(screen(3:4) - [40 80], [800 500]));
position = [max(1, (screen(3) - size(1)) / 2), max(1, (screen(4) - size(2)) / 2), size];
end

function kind = focusKind(component)
%FOCUSKIND "text" for components that take typing (their keys win),
%   "button" for ones that react to Space, otherwise "".
kind = "";
if isempty(component) || ~isvalid(component)
    return
end
type = string(component.Type);
if any(startsWith(type, ["uieditfield" "uinumericeditfield" "uitextarea" "uitable" "uispinner" ...
        "uidropdown" "uilistbox" "uislider"]))
    kind = "text";
elseif any(startsWith(type, ["uibutton" "uicheckbox" "uistatebutton" "uiradiobutton"]))
    kind = "button";
end
end

function enforceMinimumSize(fig, minimum)
position = fig.Position;
grown = max(position(3:4), minimum);
if any(grown ~= position(3:4))
    fig.Position(3:4) = grown;
end
end
