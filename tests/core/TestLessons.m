classdef (TestTags = {'ui'}) TestLessons < matlab.unittest.TestCase
    %TESTLESSONS Lesson files, checks, the lesson panel, and every shipped
    %   lesson worked through end to end with its hidden solutions.

    properties (TestParameter)
        LessonId = TestLessons.shipped()
    end

    properties
        App
        UserData
    end

    methods (Static)
        function ids = shipped()
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            files = dir(fullfile(root, "resources", "lessons", "*.json"));
            ids = erase(string({files.name}), ".json");
            ids = cell2struct(cellstr(ids), matlab.lang.makeValidName(ids), 2);
        end
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function isolateUserData(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.UserData = string(temp.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, testCase.UserData));
        end
    end

    methods (Test)
        function shippedLessonCanBeCompleted(testCase, LessonId)
            lesson = dlab.core.Lesson.load(LessonId);
            testCase.verifyEqual(lesson.id, string(LessonId), "The id matches the file name.");
            testCase.App = DynamicsLab(Visible=false);
            testCase.addTeardown(@() closeIfOpen(testCase.App));
            testCase.App.startLesson(LessonId);
            testCase.assertNotEmpty(testCase.App.View.LessonPanel);
            for k = 1:numel(lesson.steps)
                step = lesson.steps{k};
                view = testCase.App.View;       % a step may move the lesson to another simulator
                testCase.verifyEqual(view.Plugin.Id, dlab.core.Lesson.stepSimulator(lesson, k), ...
                    sprintf("Step %d runs in its simulator.", k));
                testCase.verifyEqual(view.LessonPanel.Step, k);
                if isfield(step, "setup")
                    view.lessonSetup(k);
                    testCase.assertEmpty(testCase.App.LastError, sprintf("Step %d setup", k));
                end
                if isfield(step, "check")
                    testCase.assertTrue(isfield(step, "solution"), sprintf("Step %d needs a solution.", k));
                    testCase.applySolution(step.solution);
                    [passed, message] = view.lessonCheck(k);
                    testCase.verifyTrue(passed, sprintf("Step %d: %s", k, message));
                elseif isfield(step, "claims")
                    testCase.applySolution(step.solution);
                end
                if isfield(step, "claims")
                    % The numbers the step states, against the run it describes.
                    context = view.lessonContext();
                    for j = 1:numel(step.claims)
                        [passed, message] = dlab.core.Lesson.evaluate(step.claims{j}, context);
                        testCase.verifyTrue(passed, sprintf("Step %d, claim %d: %s", k, j, message));
                    end
                end
                view.lessonGo(k + 1);
            end
            testCase.verifyEmpty(testCase.App.View.LessonPanel, "Finishing closes the lesson.");
            testCase.verifyTrue(dlab.core.Lesson.progress(LessonId).Done);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function everyShippedLessonIsListed(testCase)
            list = dlab.core.Lesson.list([dlab.simulators().Id]');
            testCase.verifyEqual(sort([list.Id]), sort(string(struct2cell(TestLessons.shipped()))).');
            testCase.verifyEqual(numel(unique([list.Id])), numel(list), "Lesson ids are unique.");
            missing = setdiff([dlab.simulators().Id]', [list.Simulator]);
            testCase.verifyEmpty(missing, "Every simulator has at least one lesson.");
            testCase.verifyTrue(issorted([list.Order]));
        end

        function checksExplainWhatIsMissing(testCase)
            specs = dlab.core.ParamSpec("theta", Label="Launch angle", Units="deg", Default=45);
            metrics = table("Range", 254.8, "m", VariableNames=["Quantity" "Value" "Units"]);
            context = struct("Params", struct("theta", 45), "Specs", specs, "Fresh", false, ...
                "RunParams", struct(), "Metrics", metrics, "Sweep", [], "Modes", [], "KeptRuns", 0);
            check = struct("kind", "metric", "quantity", "Range", "min", 260, "hint", "Try again.");
            [passed, message] = dlab.core.Lesson.evaluate(check, context);
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Press Run first; results must be up to date with the inputs. Try again.");
            context.Fresh = true;
            [~, message] = dlab.core.Lesson.evaluate(check, context);
            testCase.verifyEqual(message, "✗ Range is 254.8 m; aim for at least 260 m. Try again.");
            check.min = 250;
            [passed, message] = dlab.core.Lesson.evaluate(check, context);
            testCase.verifyTrue(passed);
            testCase.verifyEqual(message, "✓ Well done.");

            [passed, message] = dlab.core.Lesson.evaluate(struct("kind", "input", "name", "theta", "max", 40), context);
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Launch angle is 45 deg; aim for at most 40 deg.");
            [passed, message] = dlab.core.Lesson.evaluate(struct("kind", "runs", "min", 2), context);
            testCase.verifyFalse(passed);
            testCase.verifySubstring(message, "Keep previous runs");
            combined = struct("kind", "all", "checks", {{struct("kind", "run"), struct("kind", "runs", "min", 1)}});
            [passed, message] = dlab.core.Lesson.evaluate(combined, context);
            testCase.verifyFalse(passed);
            testCase.verifySubstring(message, "Keep previous runs", "The first failing check explains.");
        end

        function savedLessonStepsMakeALessonThatWorks(testCase)
            % "Save as lesson step…": a reading step, then a step that checks
            % the period of a longer pendulum; then work through the lesson.
            testCase.App = DynamicsLab(Visible=false);
            testCase.addTeardown(@() closeIfOpen(testCase.App));
            testCase.App.open("pendulum");
            view = testCase.App.View;
            request = struct("Lesson", "", "NewTitle", "Longer is slower", "Title", "Look", ...
                "Text", "A pendulum.", "Metric", "", "Tolerance", 5, "Tab", "");
            view.saveLessonStep(request);
            view.applySetup(struct("params", struct("L", 2)));
            press(findall(testCase.App.Figure, Tag="dlab.run"));
            request.Lesson = dlab.core.LessonWriter.fileFor("Longer is slower");
            request.Title = "Two metres";
            request.Metric = "Period (measured)";
            L = view.saveLessonStep(request);
            testCase.verifyNumElements(L.steps, 2);
            testCase.verifyMatches(string(findall(testCase.App.Figure, Tag="dlab.status").Text), ...
                "^Saved step 2 of ""Longer is slower""");
            testCase.verifyError(@() view.saveLessonStep(setfield(request, "Title", "")), "dlab:lesson:title");

            view.applySetup(struct("preset", "Defaults"));
            press(findall(testCase.App.Figure, Tag="dlab.run"));
            testCase.App.startLesson(L.id);
            view = testCase.App.View;
            view.lessonGo(2);
            view.lessonSetup(2);
            testCase.verifyEqual(view.params().L, 2, "The setup restores the inputs.");
            testCase.verifyFalse(view.lessonCheck(2), "The last run was of the default pendulum.");
            press(findall(testCase.App.Figure, Tag="dlab.run"));
            [passed, message] = view.lessonCheck(2);
            testCase.verifyTrue(passed, message);
        end

        function dialogCollectsTheAnswers(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            M = plugin.metrics(plugin.solve(plugin.defaultParams()));
            dialog = dlab.core.LessonStepDialog(dlab.ui.Theme.dark(), struct("Title", {}, "File", {}), M, ...
                ["Animation" "Phase"], "Phase", Visible=false);
            testCase.addTeardown(@() delete(dialog));
            find = @(tag) findall(dialog.Figure, Tag=tag);
            set(find("dlab.lessonstep.newtitle"), Value="Mine");
            set(find("dlab.lessonstep.title"), Value="A step");
            set(find("dlab.lessonstep.text"), Value=["Line one"; "Line two"]);
            metric = find("dlab.lessonstep.metric");
            metric.Value = "Period (measured)";
            metric.ValueChangedFcn(metric, []);
            set(find("dlab.lessonstep.tolerance"), Value=2);
            dialog.save();
            r = dialog.Request;
            testCase.verifyEqual([r.Lesson r.NewTitle r.Title r.Metric r.Tab], ["" "Mine" "A step" "Period (measured)" "Phase"]);
            testCase.verifyEqual(r.Text, "Line one" + newline + "Line two");
            testCase.verifyEqual(r.Tolerance, 2);
        end

        function claimsAreReadAsRanges(testCase)
            % "value" and a relative "tolerance" become "min" and "max"; a
            % claim without a solution to check it is an error.
            folder = dlab.core.Paths.lessons();
            claim = struct("kind", "metric", "quantity", "Range", "value", 200, "tolerance", 0.05);
            lesson = struct("format", "dynamicslab-lesson", "formatVersion", 1, "id", "claims", "title", "Claims", ...
                "simulator", "projectile", "steps", struct("title", "One", "text", "It goes 200 m.", ...
                "solution", struct("run", true), "claims", claim));
            writelines(jsonencode(lesson), fullfile(folder, "claims.json"));
            L = dlab.core.Lesson.read(fullfile(folder, "claims.json"));
            testCase.verifyEqual([L.steps{1}.claims{1}.min L.steps{1}.claims{1}.max], [190 210], AbsTol=1e-12);
            lesson.steps = rmfield(lesson.steps, "solution");
            writelines(jsonencode(lesson), fullfile(folder, "claims.json"));
            testCase.verifyError(@() dlab.core.Lesson.read(fullfile(folder, "claims.json")), "dlab:lesson:format");
        end

        function badLessonFilesAreRejectedOrSkipped(testCase)
            folder = dlab.core.Paths.lessons();
            good = struct("format", "dynamicslab-lesson", "formatVersion", 1, "id", "mine", "title", "Mine", ...
                "simulator", "pendulum", "steps", struct("title", "One", "text", "Do it."));
            writelines(jsonencode(good), fullfile(folder, "mine.json"));
            writelines("{ not json", fullfile(folder, "broken.json"));
            bad = good;
            bad.id = "badcheck";
            bad.steps.check = struct("kind", "teleport");
            writelines(jsonencode(bad), fullfile(folder, "badcheck.json"));
            ids = [dlab.core.Lesson.list().Id];
            testCase.verifyTrue(ismember("mine", ids), "User lessons are listed.");
            testCase.verifyFalse(ismember("badcheck", ids));
            testCase.verifyError(@() dlab.core.Lesson.read(fullfile(folder, "badcheck.json")), "dlab:lesson:format");
            testCase.verifyError(@() dlab.core.Lesson.load("nope"), "dlab:lesson:unknown");
            orbitOnly = dlab.core.Lesson.list("orbit");
            testCase.verifyFalse(ismember("mine", [orbitOnly.Id]), ...
                "Lessons for simulators that are not available are hidden.");
        end

        function lessonPanelNavigatesAndSurvivesRebuilds(testCase)
            testCase.App = DynamicsLab(Visible=false);
            testCase.addTeardown(@() closeIfOpen(testCase.App));
            testCase.App.startLesson("projectile-best-angle");
            component = @(tag) findall(testCase.App.Figure, Tag=tag);
            testCase.verifyEqual(string(component("dlab.lesson.counter").Text), "LESSON · STEP 1 OF 5");
            testCase.verifyEqual(string(component("dlab.lesson.back").Enable), "off");
            press(component("dlab.lesson.check"));
            testCase.verifyMatches(string(component("dlab.lesson.result").Text), "^✗ Press Run first");
            press(component("dlab.lesson.setup"));
            press(component("dlab.run"));
            press(component("dlab.lesson.check"));
            testCase.verifyMatches(string(component("dlab.lesson.result").Text), "^✓ 254\.8 m");
            press(component("dlab.lesson.next"));
            testCase.verifyEqual(testCase.App.View.LessonPanel.Step, 2);

            testCase.App.toggleTheme();                        % rebuilt from the session
            testCase.verifyEqual(testCase.App.View.LessonPanel.Step, 2);
            testCase.App.goHome();
            % Projectile has two lessons: one "Lessons (2) ▾" button beside
            % Open, whose menu lists them by title with the progress.
            card = findall(testCase.App.Figure, Tag="dlab.lesson.start.projectile-best-angle");
            testCase.verifyMatches(string(card.Text), "^\d\.  The best launch angle  ·  continue at step 2$", ...
                "A menu item names its lesson and where the learner left off.");
            button = findall(testCase.App.Figure, Tag="dlab.lessons.projectile");
            testCase.verifyEqual(string(button.Text), "Lessons (2) ▾");
            testCase.verifyTrue(contains(string(button.Tooltip), "The best launch angle (5 steps · at step 2)"), ...
                "The button's tooltip lists the lessons with the progress.");
            testCase.verifyEqual(string(ancestor(button, "uipanel").Tag), "dlab.card.projectile", ...
                "The lessons sit on their simulator's card, beside Open.");
            testCase.verifyEmpty(findall(testCase.App.Figure, Type="uilabel", Text="LESSONS"), ...
                "No separate lessons section.");
            search = findall(testCase.App.Figure, Tag="dlab.home.search");
            search.Value = "best launch angle";                % a lesson's title finds its simulator
            search.ValueChangedFcn(search, []);
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Tag="dlab.card.projectile"));
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.card.orbit"));
            card = findall(testCase.App.Figure, Tag="dlab.lesson.start.projectile-best-angle");
            press(card);
            testCase.verifyEqual(testCase.App.View.LessonPanel.Step, 2, "Resumes where the learner left off.");
            press(component("dlab.lesson.close"));
            testCase.verifyEmpty(testCase.App.View.LessonPanel);
            testCase.verifyEqual(numel(testCase.App.View.tabTitles()) > 0, true);
        end

        function everyCardKeepsRoomForOpen(testCase)
            % However many lessons a simulator has, its card shows Open and at
            % most one lesson control (Pendulum's four once squeezed Open to a
            % sliver); a menu lists several, in their order.
            testCase.App = DynamicsLab(Visible=false);
            testCase.addTeardown(@() closeIfOpen(testCase.App));
            lessons = dlab.core.Lesson.list();
            for sim = testCase.App.simulators()
                open = findall(testCase.App.Figure, Tag="dlab.open." + sim.Id);
                testCase.assertNumElements(open, 1, sim.Id);
                actions = open.Parent;
                testCase.verifyLessThanOrEqual(numel(actions.ColumnWidth), 2, sim.Id + ": Open and one lesson control");
                testCase.verifyEqual(actions.ColumnWidth{1}, '1x', sim.Id + ": Open takes the room left");
                mine = lessons([lessons.Simulator] == sim.Id);
                if numel(mine) > 1
                    menu = findall(testCase.App.Figure, Tag="dlab.lessons.menu." + sim.Id);
                    testCase.assertNumElements(menu, 1, sim.Id);
                    items = flip(menu.Children);
                    testCase.verifyEqual(string({items.Tag}), "dlab.lesson.start." + [mine.Id], ...
                        sim.Id + ": one item per lesson, in order");
                end
            end
            item = findall(testCase.App.Figure, Tag="dlab.lesson.start.pendulum-period");
            testCase.verifyMatches(string(item.Text), "^1\.  How long does a swing take\?$");
            press(item);
            testCase.verifyEqual(testCase.App.View.Plugin.Id, "pendulum");
            testCase.verifyEqual(testCase.App.View.LessonPanel.Lesson.id, "pendulum-period");
            testCase.App.goHome();
            testCase.verifyEmpty(findall(testCase.App.Figure, Type="uicontextmenu", Tag="dlab.lessons.menu.attractors"), ...
                "Simulators with one lesson have no menu.");
            testCase.verifyNumElements(findall(testCase.App.Figure, Tag="dlab.lessons.menu.pendulum"), 1, ...
                "Going Home again does not leave the old menus behind.");
        end
    end

    methods
        function applySolution(testCase, solution)
            view = testCase.App.View;
            if isfield(solution, "keepRuns")
                view.setKeepRuns(logical(solution.keepRuns));
            end
            if isfield(solution, "params")
                view.applySetup(struct("params", solution.params));
            end
            runs = 0;
            if isfield(solution, "run") && solution.run
                runs = 1;
            end
            if isfield(solution, "runs")
                runs = solution.runs;
            end
            for k = 1:runs
                press(findall(testCase.App.Figure, Tag="dlab.run"));
                testCase.assertEmpty(testCase.App.LastError, "Run raised an error.");
            end
            if isfield(solution, "sweep") && solution.sweep
                view.runSweep();
            end
            if isfield(solution, "map") && solution.map
                view.runMap();
            end
            if isfield(solution, "optimize") && solution.optimize
                view.runOptimize();
            end
            if isfield(solution, "uncertainty") && solution.uncertainty
                view.runUncertainty();
            end
            if isfield(solution, "fit") && solution.fit
                view.runFit();
            end
            if isfield(solution, "answer")
                view.LessonPanel.choose(solution.answer);
            end
            testCase.assertEmpty(testCase.App.LastError, "The solution raised an error.");
            if ~isempty(view.Playback)
                view.Playback.pause();
            end
        end
    end
end

function press(control)
% Press a button, or choose a menu item (a card's Lessons ▾ menu).
if isa(control, "matlab.ui.container.Menu")
    control.MenuSelectedFcn(control, []);
else
    control.ButtonPushedFcn(control, []);
end
end

function closeIfOpen(app)
if ~isempty(app) && isvalid(app) && isvalid(app.Figure)
    app.close();
end
end
