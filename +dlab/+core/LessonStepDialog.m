classdef LessonStepDialog < handle
    %LESSONSTEPDIALOG "Save as lesson step…": a small window that turns
    %   the current inputs (and, optionally, a key result of the last run)
    %   into a step of one of the user's lessons.
    %
    %   Lesson   [New lesson ▾]  Title [My pendulum lesson]
    %   Step     [Twice as long          ]
    %   Text     ┌ what to try ─────────────┐
    %   Check    [Period (s) = 2.84 ▾]  within ± [5] %
    %   Tab      [Animation ▾]
    %                                 [Cancel] [Save step]

    events
        SaveRequested     % Request holds the answers
    end

    properties (SetAccess = private)
        Figure
        Request = struct()      % Lesson ("" = new), NewTitle, Title, Text, Metric, Tolerance, Tab
    end

    properties (Access = private)
        LessonDropdown
        NewTitleField
        TitleField
        TextArea
        MetricDropdown
        ToleranceField
        TabDropdown
    end

    properties (Constant, Access = private)
        NewLesson = "<new>"
        NoCheck = "<none>"
    end

    methods
        function obj = LessonStepDialog(theme, lessons, metrics, tabs, currentTab, options)
            %LESSONSTEPDIALOG LESSONS: struct array (Title, File) of the
            %   user's lessons for this simulator; METRICS: the last run's
            %   Plugin.metrics ([] before a run); TABS: output tab titles.
            arguments
                theme (1,1) dlab.ui.Theme
                lessons struct
                metrics
                tabs (1,:) string
                currentTab (1,1) string = ""
                options.Visible (1,1) logical = true
            end
            t = theme;
            obj.Figure = uifigure(Name="Save as lesson step", Position=[200 200 520 420], ...
                Color=t.Background, WindowStyle="modal", Visible=options.Visible, Tag="dlab.lessonstep");
            dlab.ui.applyFigureTheme(obj.Figure, t);
            grid = uigridlayout(obj.Figure, [7 2], ColumnWidth={70, "1x"}, ...
                RowHeight={26, 26, 26, "1x", 26, 26, 30}, BackgroundColor=t.Background, ...
                Padding=[t.Spacing.md t.Spacing.md t.Spacing.md t.Spacing.md]);

            dlab.ui.label(grid, "Lesson", t, Role="muted");
            row = uigridlayout(grid, [1 2], ColumnWidth={"1x", "1x"}, Padding=0, BackgroundColor=t.Background);
            obj.LessonDropdown = uidropdown(row, Items=["New lesson…", [lessons.Title]], ...
                ItemsData=[obj.NewLesson, [lessons.File]], BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                Tag="dlab.lessonstep.lesson", ValueChangedFcn=@(~, ~) obj.refresh());
            obj.NewTitleField = uieditfield(row, Placeholder="Title of the new lesson", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.lessonstep.newtitle");

            dlab.ui.label(grid, "Step", t, Role="muted");
            obj.TitleField = uieditfield(grid, Placeholder="Step title", BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.lessonstep.title");

            label = dlab.ui.label(grid, "Text", t, Role="muted");
            label.Layout.Row = [3 4];
            label.VerticalAlignment = "top";
            obj.TextArea = uitextarea(grid, Placeholder="What the learner should try, and why", ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.lessonstep.text");
            obj.TextArea.Layout.Row = [3 4];

            dlab.ui.label(grid, "Check", t, Role="muted");
            row = uigridlayout(grid, [1 3], ColumnWidth={"1x", "fit", 60}, Padding=0, BackgroundColor=t.Background);
            [items, keys] = metricItems(metrics);
            obj.MetricDropdown = uidropdown(row, Items=items, ItemsData=keys, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.lessonstep.metric", ValueChangedFcn=@(~, ~) obj.refresh());
            dlab.ui.label(row, "within ± %", t, Role="muted");
            obj.ToleranceField = uieditfield(row, "numeric", Value=5, Limits=[0.01 100], ...
                LowerLimitInclusive="on", BackgroundColor=t.SurfaceRaised, FontColor=t.Text, ...
                Tag="dlab.lessonstep.tolerance");

            dlab.ui.label(grid, "Tab", t, Role="muted");
            obj.TabDropdown = uidropdown(grid, Items=["(leave as it is)", tabs], ItemsData=["", tabs], ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.lessonstep.tab");
            if ismember(currentTab, tabs)
                obj.TabDropdown.Value = currentTab;
            end

            buttons = uigridlayout(grid, [1 3], ColumnWidth={"1x", 100, 110}, Padding=0, BackgroundColor=t.Background);
            buttons.Layout.Column = [1 2];
            uilabel(buttons, Text="");
            dlab.ui.button(buttons, "Cancel", t, Tag="dlab.lessonstep.cancel", Callback=@(~, ~) delete(obj.Figure));
            dlab.ui.button(buttons, "Save step", t, Kind="primary", Tag="dlab.lessonstep.save", ...
                Callback=@(~, ~) obj.save());
            obj.refresh();
        end

        function save(obj)
            %SAVE Collect the answers and ask the view to save the step.
            lesson = string(obj.LessonDropdown.Value);
            if lesson == obj.NewLesson
                lesson = "";
            end
            metric = string(obj.MetricDropdown.Value);
            if metric == obj.NoCheck
                metric = "";
            end
            obj.Request = struct("Lesson", lesson, "NewTitle", strtrim(string(obj.NewTitleField.Value)), ...
                "Title", strtrim(string(obj.TitleField.Value)), "Text", strjoin(string(obj.TextArea.Value), newline), ...
                "Metric", metric, "Tolerance", obj.ToleranceField.Value, "Tab", string(obj.TabDropdown.Value));
            notify(obj, "SaveRequested");
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end
    end

    methods (Access = private)
        function refresh(obj)
            obj.NewTitleField.Enable = string(obj.LessonDropdown.Value) == obj.NewLesson;
            obj.ToleranceField.Enable = string(obj.MetricDropdown.Value) ~= obj.NoCheck;
        end
    end
end

function [items, keys] = metricItems(M)
% "No check" and one item per key result, showing its value in the last run.
items = "No check (a reading step)";
keys = "<none>";
if isempty(M)
    return
end
for k = 1:height(M)
    text = sprintf("%s = %.4g", M.Quantity(k), M.Value(k));
    if string(M.Units(k)) ~= ""
        text = text + " " + string(M.Units(k));
    end
    items(end+1) = text; %#ok<AGROW>
    keys(end+1) = string(M.Quantity(k)); %#ok<AGROW>
end
end
