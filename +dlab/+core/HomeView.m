classdef HomeView < handle
    %HOMEVIEW Main menu: search, recent work, and simulator cards grouped
    %   by Category. Built entirely from plugin metadata and the lesson
    %   files; registering a plugin is all it takes to appear.
    %
    %   Pick a simulator to explore.                 [ Search…          ]
    %   ┌ Welcome to Dynamics Lab (until dismissed) ─────────────────────┐
    %   PICK UP WHERE YOU LEFT OFF  [▶ Pendulum · 5 min ago] [▶ Orbit · …]
    %   RECENT SCENARIOS            [Baseball · Projectile] …
    %   MECHANICS  [card] [card] [card] [card]
    %   …
    %
    %   Cards keep their size and fill as many columns as the window has
    %   room for, reflowing when it is resized (resized).
    %
    %   A card with one lesson has a button for it beside Open ("Start
    %   lesson", "Continue lesson", "Lesson ✓"); a card with several has a
    %   "Lessons (n) ▾" button whose menu lists them by title with the
    %   learner's progress.

    properties (SetAccess = private)
        Grid
        SearchField
        Content
        Query (1,1) string = ""
        Columns (1,1) double = 3        % card columns in the current layout
    end

    properties (Access = private)
        Shell
        Theme
        Top                             % intro and search row
        Banner = []                     % welcome row (uigridlayout), when shown
        CardGrids = {}                  % per category: struct(Grid, Cards)
        Menus = gobjects(0)             % lesson menus (children of the figure)
    end

    properties (Constant)
        WelcomeSetting = "welcomeDismissed"
    end

    properties (Constant, Access = private)
        CardWidth = 300
        CardHeight = 280
        SearchWidth = 320
        ScrollbarWidth = 16
    end

    methods
        function obj = HomeView(parent, shell)
            t = shell.Theme;
            obj.Shell = shell;
            obj.Theme = t;
            obj.Grid = uigridlayout(parent, [2 1], RowHeight={34, "1x"}, Padding=[24 20 24 0], ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.Background);
            obj.Top = uigridlayout(obj.Grid, [1 3], ColumnWidth={"1x", obj.SearchWidth, 0}, Padding=0, ...
                BackgroundColor=t.Background);
            intro = dlab.ui.label(obj.Top, "Pick a simulator to explore.", t, Role="muted");
            intro.FontSize = t.FontSize.lg;
            obj.SearchField = uieditfield(obj.Top, "text", Placeholder="Search simulators and lessons", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, FontSize=t.FontSize.md, ...
                Tag="dlab.home.search", ...
                ValueChangingFcn=@(~, evt) obj.search(evt.Value), ValueChangedFcn=@(src, ~) obj.search(src.Value));
            obj.Content = uigridlayout(obj.Grid, [1 1], Scrollable="on", RowHeight={"fit"}, ...
                Padding=[0 0 0 24], RowSpacing=t.Spacing.md, BackgroundColor=t.Background);
            obj.Columns = obj.columnCount();
            obj.render();
            obj.focusSearch();
        end

        function focusSearch(obj)
            %FOCUSSEARCH Keyboard users start in the search box; Tab then
            %   reaches the recent work and each card's Open and lesson
            %   buttons in order. (A hidden window cannot take focus.)
            if ancestor(obj.SearchField, "figure").Visible == "on"
                focus(obj.SearchField);
            end
        end

        function search(obj, query)
            %SEARCH Show only simulators and lessons matching QUERY.
            obj.Query = strtrim(string(query));
            obj.render();
        end

        function resized(obj)
            %RESIZED Reflow the cards into as many columns as now fit.
            if ~isvalid(obj) || ~isvalid(obj.Grid)
                return
            end
            columns = obj.columnCount();
            if columns ~= obj.Columns
                obj.Columns = columns;
                obj.layoutCards();
            end
        end

        function dismissWelcome(obj)
            %DISMISSWELCOME Hide the welcome banner, now and in later sessions.
            dlab.core.Settings.set(obj.WelcomeSetting, true);
            obj.render();
        end

        function close(obj)
            obj.deleteMenus();
            if isvalid(obj.Grid)
                delete(obj.Grid);
            end
            delete(obj);
        end
    end

    methods (Static)
        function showWelcomeAgain()
            %SHOWWELCOMEAGAIN Show the welcome banner on Home again.
            dlab.core.Settings.set(dlab.core.HomeView.WelcomeSetting, false);
        end
    end

    methods (Access = private)
        function render(obj)
            t = obj.Theme;
            shell = obj.Shell;
            obj.deleteMenus();
            delete(obj.Content.Children);
            obj.Banner = [];
            obj.CardGrids = {};
            info = shell.simulators();
            ids = string({info.Id});
            lessons = dlab.core.Lesson.list(ids);
            if obj.Query ~= ""
                % A simulator matches through its own text or its lessons'.
                info = info(arrayfun(@(s) matches(obj.Query, [s.Title s.Summary s.Category ...
                    lessonText(lessons, s.Id)]), info));
            end
            recent = struct([]);
            scenarios = struct([]);
            welcome = false;
            if obj.Query == ""
                recent = dlab.core.Recent.simulators(ids);
                scenarios = dlab.core.Recent.scenarios(ids);
                welcome = ~isempty(ids) && ~isequal(dlab.core.Settings.get(obj.WelcomeSetting, false), true);
            end
            categories = reshape(unique(string({info.Category}), "stable"), 1, []);   % 1×0 when empty
            rows = welcome + 2 * ~isempty(recent) + 2 * ~isempty(scenarios) + 2 * numel(categories) + isempty(info);
            obj.Content.RowHeight = repmat({"fit"}, 1, max(rows, 1));

            if isempty(ids)
                dlab.ui.label(obj.Content, "No simulators are registered yet " + ...
                    "(add them in +dlab/+sims/registry.m).", t);
                return
            end
            if welcome
                obj.welcomeBanner(numel(ids), lessons);
            end
            if isempty(info)
                dlab.ui.label(obj.Content, "Nothing matches """ + obj.Query + """.", t, Role="muted", ...
                    Tag="dlab.home.nomatch");
            end

            if ~isempty(recent)
                obj.heading("PICK UP WHERE YOU LEFT OFF");
                row = obj.chipRow(numel(recent));
                for k = 1:numel(recent)
                    id = recent(k).id;
                    dlab.ui.button(row, "▶  " + titleOf(shell, id) + "  ·  " + dlab.core.Recent.ago(recent(k).time), ...
                        t, Tag="dlab.continue." + id, Tooltip="Open with the inputs you left it with", ...
                        Callback=shell.callback(@() shell.resume(id), "Continue " + id));
                end
            end
            if ~isempty(scenarios)
                obj.heading("RECENT SCENARIOS");
                row = obj.chipRow(numel(scenarios));
                for k = 1:numel(scenarios)
                    file = scenarios(k).file;
                    [~, name] = fileparts(file);
                    dlab.ui.button(row, name + "  ·  " + titleOf(shell, scenarios(k).simulator), t, ...
                        Tag="dlab.recentScenario." + k, Tooltip=file, ...
                        Callback=shell.callback(@() shell.openScenario(file), "Open scenario"));
                end
            end

            for category = categories
                obj.heading(upper(category));
                members = info([info.Category] == category);
                grid = uigridlayout(obj.Content, [1 1], ColumnSpacing=t.Spacing.lg, ...
                    RowSpacing=t.Spacing.lg, Padding=0, BackgroundColor=t.Background);
                cards = gobjects(1, numel(members));
                for k = 1:numel(members)
                    cards(k) = obj.simulatorCard(grid, members(k), ...
                        lessons(string({lessons.Simulator}) == members(k).Id));
                end
                obj.CardGrids{end+1} = struct("Grid", grid, "Cards", cards);
            end
            obj.layoutCards();
        end

        function columns = columnCount(obj)
            %COLUMNCOUNT How many cards fit side by side in the window.
            fig = ancestor(obj.Grid, "figure");
            available = fig.Position(3) - sum(obj.Grid.Padding([1 3])) - obj.ScrollbarWidth;
            gap = obj.Theme.Spacing.lg;
            columns = max(1, floor((available + gap) / (obj.CardWidth + gap)));
        end

        function width = cardsWidth(obj)
            width = obj.Columns * obj.CardWidth + (obj.Columns - 1) * obj.Theme.Spacing.lg;
        end

        function layoutCards(obj)
            %LAYOUTCARDS Place the cards in obj.Columns columns, and line the
            %   search box and the welcome banner up with them.
            columns = obj.Columns;
            for k = 1:numel(obj.CardGrids)
                grid = obj.CardGrids{k}.Grid;
                cards = obj.CardGrids{k}.Cards;
                n = numel(cards);
                rows = ceil(n / columns);
                % Stack them in one column first, so that no card is left
                % outside the grid while it changes shape.
                grid.RowHeight = repmat({obj.CardHeight}, 1, max(n, 1));
                for j = 1:n
                    cards(j).Layout.Row = j;
                    cards(j).Layout.Column = 1;
                end
                grid.ColumnWidth = repmat({obj.CardWidth}, 1, columns);
                for j = 1:n
                    cards(j).Layout.Row = ceil(j / columns);
                    cards(j).Layout.Column = mod(j - 1, columns) + 1;
                end
                grid.RowHeight = repmat({obj.CardHeight}, 1, max(rows, 1));
            end
            width = obj.cardsWidth();
            if width > obj.SearchWidth + 100
                obj.Top.ColumnWidth = {width - obj.SearchWidth - obj.Top.ColumnSpacing, obj.SearchWidth, "1x"};
            else
                obj.Top.ColumnWidth = {"1x", obj.SearchWidth, 0};
            end
            if ~isempty(obj.Banner) && isvalid(obj.Banner)
                obj.Banner.ColumnWidth = {width, "1x"};
            end
        end

        function welcomeBanner(obj, count, lessons)
            %WELCOMEBANNER What Dynamics Lab is and where to start, until
            %   the learner dismisses it (or starts the first lesson).
            t = obj.Theme;
            shell = obj.Shell;
            obj.Banner = uigridlayout(obj.Content, [1 2], ColumnWidth={obj.cardsWidth(), "1x"}, ...
                RowHeight={round(t.scaled(130))}, Padding=0, BackgroundColor=t.Background);
            panel = uipanel(obj.Banner, BackgroundColor=t.SurfaceRaised, BorderType="line", ...
                BorderColor=t.Accent, Tag="dlab.welcome");
            grid = uigridlayout(panel, [3 3], RowHeight={"fit", "1x", round(t.scaled(30))}, ...
                ColumnWidth={"fit", "fit", "1x"}, Padding=t.Spacing.md * [1 1 1 1], ...
                RowSpacing=t.Spacing.xs, ColumnSpacing=t.Spacing.sm, BackgroundColor=t.SurfaceRaised);
            title = dlab.ui.label(grid, "Welcome to Dynamics Lab", t);
            set(title, FontWeight="bold", FontSize=t.FontSize.lg);
            title.Layout.Column = [1 3];
            text = dlab.ui.label(grid, sprintf("%d interactive physics simulators that share one " + ...
                "interface. Pick one, set its inputs on the left, and press Run; hover over any input " + ...
                "to see what it means. The Analyze tab sweeps, maps, optimizes, and fits every model, " + ...
                "and guided lessons walk you through them step by step.", count), t, ...
                Role="muted", WordWrap="on", Tag="dlab.welcome.text");
            text.Layout.Column = [1 3];
            if ~isempty(lessons)
                first = lessons(1);
                dlab.ui.button(grid, "▶  Start the first lesson", t, Kind="primary", ...
                    Tag="dlab.welcome.lesson", Tooltip="Lesson: " + first.Title + newline + first.Summary, ...
                    Callback=shell.callback(@() obj.startFirstLesson(first.Id), "Start lesson"));
            end
            dlab.ui.button(grid, "Got it", t, Tag="dlab.welcome.dismiss", ...
                Tooltip="Hide this welcome (the ? button on Home brings it back)", ...
                Callback=shell.callback(@() obj.dismissWelcome(), "Welcome"));
        end

        function startFirstLesson(obj, id)
            dlab.core.Settings.set(obj.WelcomeSetting, true);
            obj.Shell.startLesson(id);
        end

        function heading(obj, text)
            label = dlab.ui.label(obj.Content, text, obj.Theme, Role="heading");
            label.FontSize = obj.Theme.FontSize.md;
        end

        function row = chipRow(obj, n)
            t = obj.Theme;
            row = uigridlayout(obj.Content, [1 n + 1], ColumnWidth=[repmat({"fit"}, 1, n), {"1x"}], ...
                RowHeight={30}, Padding=0, ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Background);
        end

        function card = simulatorCard(obj, parent, sim, lessons)
            t = obj.Theme;
            shell = obj.Shell;
            openIt = shell.callback(@() shell.open(sim.Id), "Open " + sim.Title);
            card = uipanel(parent, BackgroundColor=t.SurfaceRaised, BorderType="line", ...
                BorderColor=t.Border, Tag="dlab.card." + sim.Id);
            grid = uigridlayout(card, [4 1], RowHeight={150, 24, "1x", 30}, ...
                Padding=[t.Spacing.md t.Spacing.md t.Spacing.md t.Spacing.md], ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.SurfaceRaised);

            thumbnail = dlab.core.Paths.thumbnail(sim.Id, t.Name);
            if thumbnail ~= ""
                uiimage(grid, ImageSource=thumbnail, ScaleMethod="fill", Tag="dlab.thumbnail." + sim.Id, ...
                    ImageClickedFcn=openIt, Tooltip="Open " + sim.Title);
            else
                placeholder = uilabel(grid, Text=extractBefore(sim.Title, 2), ...
                    HorizontalAlignment="center", FontSize=64, FontWeight="bold", ...
                    FontColor=t.Accent, BackgroundColor=t.Surface);
                placeholder.Tooltip = sim.Title;
            end

            titleRow = uigridlayout(grid, [1 2], ColumnWidth={"1x", "fit"}, Padding=0, ...
                BackgroundColor=t.SurfaceRaised);
            name = dlab.ui.label(titleRow, sim.Title, t);
            set(name, FontWeight="bold", FontSize=t.FontSize.lg);
            if sim.Kind == "static"
                dlab.ui.label(titleRow, "STATIC", t, Role="heading", Tooltip="Solver without playback");
            end
            dlab.ui.label(grid, sim.Summary, t, Role="muted", WordWrap="on");
            actions = uigridlayout(grid, [1 1 + ~isempty(lessons)], ...
                ColumnWidth=[{"1x"}, repmat({"fit"}, 1, ~isempty(lessons))], RowHeight={"1x"}, Padding=0, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.SurfaceRaised);
            dlab.ui.button(actions, "Open", t, Kind="primary", Tag="dlab.open." + sim.Id, Callback=openIt);
            if isscalar(lessons)
                obj.lessonButton(actions, lessons);
            elseif ~isempty(lessons)
                obj.lessonMenu(actions, sim, lessons);
            end
        end

        function lessonButton(obj, parent, lesson)
            %LESSONBUTTON Start or continue a simulator's only LESSON; the
            %   text shows the learner's progress.
            t = obj.Theme;
            shell = obj.Shell;
            [state, status] = lessonState(lesson);
            text = struct("new", "Start lesson", "started", "Continue lesson", "done", "Lesson ✓").(state);
            dlab.ui.button(parent, text, t, Tag="dlab.lesson.start." + lesson.Id, ...
                Tooltip="Lesson: " + lesson.Title + newline + lesson.Summary + newline + status, ...
                Callback=shell.callback(@() shell.startLesson(lesson.Id), "Start lesson"));
        end

        function lessonMenu(obj, parent, sim, lessons)
            %LESSONMENU "Lessons (n) ▾": a menu of a simulator's LESSONS,
            %   each by title with the learner's progress.
            t = obj.Theme;
            shell = obj.Shell;
            menu = uicontextmenu(ancestor(parent, "figure"), Tag="dlab.lessons.menu." + sim.Id);
            obj.Menus(end+1) = menu;
            tips = strings(1, numel(lessons));
            for k = 1:numel(lessons)
                lesson = lessons(k);
                [state, status] = lessonState(lesson);
                mark = struct("new", "", "started", "  ·  continue at step " + ...
                    dlab.core.Lesson.progress(lesson.Id).Step, "done", "  ✓").(state);
                uimenu(menu, Text=sprintf("%d.  %s", k, lesson.Title) + mark, ...
                    Tag="dlab.lesson.start." + lesson.Id, ...
                    MenuSelectedFcn=shell.callback(@() shell.startLesson(lesson.Id), "Start lesson"));
                tips(k) = sprintf("%d. %s (%s)", k, lesson.Title, status);
            end
            done = nnz(arrayfun(@(lesson) lessonState(lesson) == "done", lessons));
            text = sprintf("Lessons (%d) ▾", numel(lessons));
            if done == numel(lessons)
                text = sprintf("Lessons (%d) ✓ ▾", numel(lessons));
            end
            button = dlab.ui.button(parent, text, t, Tag="dlab.lessons." + sim.Id, ...
                Tooltip=join(["Lessons:" tips], newline));
            button.ButtonPushedFcn = @(src, ~) dlab.ui.openMenuBelow(menu, src);
        end

        function deleteMenus(obj)
            delete(obj.Menus(isvalid(obj.Menus)));
            obj.Menus = gobjects(0);
        end
    end
end

function [state, status] = lessonState(lesson)
% "new", "started", or "done", and a phrase on the learner's progress.
progress = dlab.core.Lesson.progress(lesson.Id);
status = sprintf("%d steps", lesson.Steps);
if progress.Done
    state = "done";
    status = status + " · completed (press to start again)";
elseif progress.Step > 1
    state = "started";
    status = status + sprintf(" · at step %d", progress.Step);
else
    state = "new";
end
end

function tf = matches(query, texts)
tf = any(contains(texts, query, IgnoreCase=true));
end

function text = lessonText(lessons, id)
% Titles and summaries of a simulator's lessons, for search.
mine = lessons(string({lessons.Simulator}) == id);   % string: [] when there are none
text = [string({mine.Title}) string({mine.Summary})];
end

function title = titleOf(shell, id)
info = shell.simulators();
match = info([info.Id] == id);
title = id;
if ~isempty(match)
    title = match(1).Title;
end
end
