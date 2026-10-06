classdef TestLessonWriter < matlab.unittest.TestCase
    %TESTLESSONWRITER Lessons built from the app ("Save as lesson step…").

    properties
        UserData
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
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
        function setupKeepsOnlyTheChangedInputs(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            params = plugin.defaultParams();
            params.L = 2;
            step = dlab.core.LessonWriter.makeStep(plugin, params, "Custom", Title="Longer", Tab="Animation");
            testCase.verifyEqual(step.setup.preset, "Defaults", "A custom state starts from the defaults.");
            testCase.verifyEqual(step.setup.params, struct("L", 2));
            testCase.verifyEqual(step.setup.tab, "Animation");
            testCase.verifyFalse(isfield(step, "check"), "No metric: a reading step.");
            testCase.verifyFalse(isfield(step, "solution"));
        end

        function aPresetIsTheStartingPoint(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            names = string({plugin.presets().Name});
            params = plugin.presetParams(names(1));
            step = dlab.core.LessonWriter.makeStep(plugin, params, names(1));
            testCase.verifyEqual(step.setup.preset, names(1));
            testCase.verifyFalse(isfield(step.setup, "params"), "Nothing differs from the preset.");
        end

        function aMetricBecomesACheckWithATolerance(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            step = dlab.core.LessonWriter.makeStep(plugin, plugin.defaultParams(), "Defaults", ...
                Metric="Period", Value=2, Units="s", Tolerance=5);
            testCase.verifyEqual(step.check.kind, "metric");
            testCase.verifyEqual([step.check.min step.check.max], [1.9 2.1], AbsTol=1e-12);
            testCase.verifyEqual(step.check.success, "Period is 2 s.");
            testCase.verifyEqual(step.solution, struct("run", true));
            step = dlab.core.LessonWriter.makeStep(plugin, plugin.defaultParams(), "Defaults", ...
                Metric="Drift", Value=0, Tolerance=5);
            testCase.verifyEqual([step.check.min step.check.max], [-0.05 0.05], ...
                "A zero target gets an absolute band.", AbsTol=1e-12);
            testCase.verifyError(@() dlab.core.LessonWriter.makeStep(plugin, plugin.defaultParams(), ...
                "Defaults", Metric="Period"), "dlab:lesson:value");
        end

        function stepsCollectIntoAUserLesson(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            file = dlab.core.LessonWriter.fileFor("My  pendulum lesson!");
            testCase.verifyEqual(file, fullfile(testCase.UserData, "lessons", "my-my-pendulum-lesson.json"));
            one = dlab.core.LessonWriter.makeStep(plugin, plugin.defaultParams(), "Defaults", Title="One", Text="Read.");
            p = plugin.defaultParams();
            p.L = 3;
            two = dlab.core.LessonWriter.makeStep(plugin, p, "Custom", Title="Two", Metric="Period", Value=3.5);
            dlab.core.LessonWriter.append(file, "pendulum", "My pendulum lesson", one);
            L = dlab.core.LessonWriter.append(file, "pendulum", "ignored once it exists", two);
            testCase.verifyEqual(L.title, "My pendulum lesson");
            testCase.verifyEqual(L.id, "my-my-pendulum-lesson");
            testCase.verifyNumElements(L.steps, 2);
            testCase.verifyEqual(L.steps{2}.setup.params.L, 3);
            testCase.verifyEqual(string(L.steps{2}.check.quantity), "Period");
            list = dlab.core.Lesson.list("pendulum");
            testCase.verifyTrue(ismember("my-my-pendulum-lesson", [list.Id]), "The Home screen lists it.");
            mine = dlab.core.LessonWriter.userLessons("pendulum");
            testCase.verifyEqual([mine.Title], "My pendulum lesson");
            testCase.verifyEmpty(dlab.core.LessonWriter.userLessons("orbit"));
            testCase.verifyError(@() dlab.core.LessonWriter.append(file, "orbit", "x", one), "dlab:lesson:simulator");
        end
    end
end
