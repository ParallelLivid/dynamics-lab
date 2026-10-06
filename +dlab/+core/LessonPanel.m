classdef LessonPanel < handle
    %LESSONPANEL The lesson column on the right of a simulator.
    %
    %   LESSON · STEP 2 OF 5                ✕
    %   Lesson title
    %   Step title
    %   ┌ step text (scrolls) ───────────┐
    %   ○ option 1  ○ option 2 …          (multiple-choice steps)
    %   [ Load this setup ]
    %   [ Check ]   ✓ / ✗ feedback
    %   [ ◀ Back ]            [ Next ▶ ]
    %
    %   The simulator view does the work; the panel calls its ACTIONS:
    %   Setup(step), Check(step), Go(step), and Close().

    properties (SetAccess = private)
        Grid
        Lesson
        Step (1,1) double = 1
        Passed (1,:) logical
        Feedback (1,1) string = ""
        Answer (1,1) double = NaN      % the option chosen on a multiple-choice step
    end

    properties (Access = private)
        Theme
        Actions
        Counter
        StepTitle
        Text
        Choices
        SetupButton
        CheckButton
        ResultLabel
        BackButton
        NextButton
    end

    methods
        function obj = LessonPanel(parent, lesson, theme, actions, state)
            arguments
                parent
                lesson (1,1) struct
                theme (1,1) dlab.ui.Theme
                actions (1,1) struct           % Setup, Check, Go, Close function handles
                state = []
            end
            t = theme;
            obj.Theme = t;
            obj.Lesson = lesson;
            obj.Actions = actions;
            obj.Passed = false(1, numel(lesson.steps));
            if ~isempty(state)
                obj.Step = min(max(state.Step, 1), numel(lesson.steps));
                obj.Passed(1:min(end, numel(state.Passed))) = state.Passed(1:min(end, numel(state.Passed)));
            end

            obj.Grid = uigridlayout(parent, [9 1], ...
                RowHeight={26, "fit", "fit", "1x", 0, 30, 30, "fit", 30}, ...
                Padding=[t.Spacing.md t.Spacing.md t.Spacing.md t.Spacing.md], RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface, Tag="dlab.lesson");
            top = uigridlayout(obj.Grid, [1 2], ColumnWidth={"1x", 30}, Padding=0, BackgroundColor=t.Surface);
            obj.Counter = dlab.ui.label(top, "", t, Role="heading", Tag="dlab.lesson.counter");
            dlab.ui.button(top, "✕", t, Kind="ghost", Tag="dlab.lesson.close", Tooltip="Close the lesson", ...
                Callback=@(~, ~) obj.Actions.Close());
            heading = dlab.ui.label(obj.Grid, lesson.title, t, Role="title", WordWrap="on", Tag="dlab.lesson.title");
            heading.FontSize = t.FontSize.lg;
            heading.FontColor = t.Accent;
            obj.StepTitle = dlab.ui.label(obj.Grid, "", t, WordWrap="on", Tag="dlab.lesson.step");
            obj.StepTitle.FontWeight = "bold";
            obj.Text = uitextarea(obj.Grid, Editable="off", WordWrap="on", FontSize=t.FontSize.md, ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.lesson.text");
            obj.Choices = uibuttongroup(obj.Grid, BorderType="none", BackgroundColor=t.Surface, ...
                Tag="dlab.lesson.choices", SelectionChangedFcn=@(~, event) obj.choose(event.NewValue.UserData));
            obj.SetupButton = dlab.ui.button(obj.Grid, "Load this setup", t, Tag="dlab.lesson.setup", ...
                Tooltip="Set the inputs this step uses (Ctrl+Z undoes it)", ...
                Callback=@(~, ~) obj.Actions.Setup(obj.Step));
            obj.CheckButton = dlab.ui.button(obj.Grid, "Check", t, Kind="primary", Tag="dlab.lesson.check", ...
                Tooltip="See whether you have done what this step asks", ...
                Callback=@(~, ~) obj.Actions.Check(obj.Step));
            obj.ResultLabel = dlab.ui.label(obj.Grid, "", t, WordWrap="on", Tag="dlab.lesson.result");
            nav = uigridlayout(obj.Grid, [1 2], ColumnWidth={"1x", "1x"}, Padding=0, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            obj.BackButton = dlab.ui.button(nav, "◀  Back", t, Tag="dlab.lesson.back", ...
                Callback=@(~, ~) obj.Actions.Go(obj.Step - 1));
            obj.NextButton = dlab.ui.button(nav, "Next  ▶", t, Kind="primary", Tag="dlab.lesson.next", ...
                Callback=@(~, ~) obj.Actions.Go(obj.Step + 1));
            obj.showStep(obj.Step);
        end

        function showStep(obj, k)
            %SHOWSTEP Display step K (clamped to the lesson).
            n = numel(obj.Lesson.steps);
            obj.Step = min(max(k, 1), n);
            step = obj.Lesson.steps{obj.Step};
            obj.Counter.Text = sprintf("LESSON · STEP %d OF %d", obj.Step, n);
            obj.StepTitle.Text = step.title;
            obj.Text.Value = splitlines(step.text);
            hasSetup = isfield(step, "setup");
            hasCheck = isfield(step, "check");
            obj.showChoices(step);
            obj.Grid.RowHeight{6} = 30 * hasSetup;
            obj.Grid.RowHeight{7} = 30 * hasCheck;
            obj.SetupButton.Visible = hasSetup;
            obj.CheckButton.Visible = hasCheck;
            obj.Feedback = "";
            if hasCheck && obj.Passed(obj.Step)
                obj.Feedback = "✓ Done.";
            end
            obj.showFeedback(obj.Feedback, obj.Passed(obj.Step));
            obj.BackButton.Enable = obj.Step > 1;
            if obj.Step == n
                obj.NextButton.Text = "Finish  ✓";
                obj.NextButton.Tooltip = "Close the lesson";
            else
                obj.NextButton.Text = "Next  ▶";
                obj.NextButton.Tooltip = "";
            end
        end

        function showResult(obj, passed, message)
            %SHOWRESULT Feedback from a check of the current step.
            if passed
                obj.Passed(obj.Step) = true;
            end
            obj.Feedback = message;
            obj.showFeedback(message, passed);
        end

        function choose(obj, k)
            %CHOOSE Pick option K of a multiple-choice step.
            buttons = findobj(obj.Choices, Type="uiradiobutton", Tag="dlab.lesson.choice");
            match = buttons([buttons.UserData] == k);
            assert(~isempty(match), "dlab:lesson:choice", "This step has no option %d.", k);
            match.Value = true;
            obj.Answer = k;
        end

        function state = snapshot(obj)
            state = struct("Id", obj.Lesson.id, "Step", obj.Step, "Passed", obj.Passed);
        end
    end

    methods (Access = private)
        function showChoices(obj, step)
            % One radio button per option of a multiple-choice step.
            delete(obj.Choices.Children);
            obj.Answer = NaN;
            obj.Grid.RowHeight{5} = 0;
            if ~isfield(step, "check") || string(step.check.kind) ~= "choice"
                return
            end
            t = obj.Theme;
            options = string(step.check.options);
            n = numel(options);
            rowHeight = 24;
            width = max(obj.Choices.InnerPosition(3), 200) - 8;
            % A hidden button holds the selection until the learner picks
            % one (a button group always has one selected).
            uiradiobutton(obj.Choices, Text="", Visible="off", UserData=NaN, Value=true);
            for k = 1:n
                uiradiobutton(obj.Choices, Text=options(k), FontColor=t.Text, UserData=k, ...
                    Tag="dlab.lesson.choice", Position=[4, (n - k) * rowHeight + 4, width, rowHeight - 2]);
            end
            obj.Grid.RowHeight{5} = n * rowHeight + 6;
        end

        function showFeedback(obj, message, passed)
            obj.ResultLabel.Text = message;
            if passed
                obj.ResultLabel.FontColor = obj.Theme.Success;
            else
                obj.ResultLabel.FontColor = obj.Theme.Warning;
            end
            obj.Grid.RowHeight{8} = "fit";
            if message == ""
                obj.Grid.RowHeight{8} = 0;
            end
        end
    end
end
