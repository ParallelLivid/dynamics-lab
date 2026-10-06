classdef (TestTags = {'ui'}) TestEntryPlugin < matlab.unittest.TestCase
    %TESTENTRYPLUGIN The atmospheric entry simulator in the app, and its
    %   lesson worked through with the hidden solutions.

    properties
        App
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (TestMethodSetup)
        function launch(testCase)
            testCase.App = DynamicsLab("entry", Plugins={@dlab.sims.entry.EntryPlugin}, Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function pressRun(testCase)
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.assertEmpty(testCase.App.LastError);
        end

        function choosePreset(testCase, name)
            dd = findall(testCase.App.Figure, Tag="dlab.preset");
            dd.Value = "builtin:" + name;
            dd.ValueChangedFcn(dd, []);
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
            testCase.assertNumElements(value, 1, quantity);
        end
    end

    methods (Test)
        function lunarReturnIsCaptured(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Skipped out"), 0);
            testCase.verifyGreaterThan(testCase.metric("Peak deceleration"), 5);
            testCase.verifyLessThan(testCase.metric("Peak deceleration"), 9);
            testCase.verifyGreaterThan(testCase.metric("Heat load"), 5);
            testCase.verifyGreaterThan(testCase.metric("Peak heating rate"), 100);
            testCase.App.View.Playback.seek(80);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function allenEggersPresetMatchesTheFormula(testCase)
            testCase.choosePreset("Ballistic, exponential atmosphere (Allen–Eggers)");
            testCase.pressRun();
            formula = testCase.metric("Ballistic estimate of peak deceleration (Allen–Eggers)");
            testCase.verifyEqual(formula, 7500^2 * sind(20) / (2 * exp(1) * 7200) / 9.80665, "RelTol", 1e-12);
            testCase.verifyEqual(testCase.metric("Peak deceleration"), formula, "RelTol", 0.08, ...
                "Within the few per cent that gravity adds.");
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("scaleHeight"));
        end

        function ballisticEstimateOnlyWithoutLift(testCase)
            % The default capsule has lift (L/D 0.3), so the formula row is left out.
            name = "Ballistic estimate of peak deceleration (Allen–Eggers)";
            testCase.pressRun();
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyFalse(any(M.Quantity == name));
            testCase.choosePreset("Soyuz-like ballistic return from the ISS");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric(name), 7600^2 * sind(1.5) / (2 * exp(1) * 7200) / 9.80665, ...
                "RelTol", 1e-12);
        end

        function corridorPair(testCase)
            testCase.choosePreset("Corridor: too shallow (skips)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Skipped out"), 1);
            testCase.choosePreset("Corridor: too steep (over 10 g)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Skipped out"), 0);
            testCase.verifyGreaterThan(testCase.metric("Peak deceleration"), 10);
        end

        function liftLowersTheLoad(testCase)
            testCase.choosePreset("Soyuz-like ballistic return from the ISS");
            testCase.pressRun();
            ballistic = testCase.metric("Peak deceleration");
            testCase.App.View.Plugin.requestInputs(struct("LD", 0.3), "Lift");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Peak deceleration"), 0.5 * ballistic);
        end

        function scaleHeightOnlyForTheExponentialAtmosphere(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("scaleHeight"));
            testCase.App.View.Plugin.requestInputs(struct("atmosphere", "exponential"), "Atmosphere");
            testCase.verifyTrue(panel.isRowShown("scaleHeight"));
        end

        function lessonStepsCanBeCompleted(testCase)
            % The lesson's hidden solutions pass its checks (the shell's
            % lesson test does this once the simulator is registered).
            root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            lesson = jsondecode(fileread(fullfile(root, "resources", "lessons", "entry-corridor.json")));
            testCase.verifyEqual(string(lesson.simulator), "entry");
            steps = lesson.steps;
            if isstruct(steps)
                steps = num2cell(steps);
            end
            testCase.verifyGreaterThanOrEqual(numel(steps), 3);
            testCase.verifyLessThanOrEqual(numel(steps), 5);
            view = testCase.App.View;
            for k = 1:numel(steps)
                step = steps{k};
                view.applySetup(step.setup);
                testCase.assertEmpty(testCase.App.LastError, sprintf("Step %d setup", k));
                solution = step.solution;
                if isfield(solution, "params")
                    view.applySetup(struct("params", solution.params));
                end
                testCase.pressRun();
                [passed, message] = dlab.core.Lesson.evaluate(step.check, view.lessonContext());
                testCase.verifyTrue(passed, sprintf("Step %d: %s", k, message));
            end
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; the atmosphere choices fit their field
            % ("Standard (CIRA-72 bands)" was cut off).
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function skipOutStartsShallowerThanMinus5Point6(testCase)
            % My own integration: with the bank step at 80 s, −5.6° skips out
            % at 7.99 km/s and −5.7° stays in (the lesson said "shallower than
            % −6°" and "still near 10 km/s").
            plugin = testCase.App.View.Plugin;
            plugin.requestInputs(struct("gamma0", -5.7), "Stays");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Skipped out"), 0);
            % Not gentle at the shallow edge (the lesson said "the peak g is
            % low"): it climbs, then falls in steeply with its lift rolled
            % away, 8.768 g in my integration against 7.017 at −6.5°.
            testCase.verifyEqual(testCase.metric("Peak deceleration"), 8.768, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("Heat load"), 21.707, RelTol=1e-3);
            plugin.requestInputs(struct("gamma0", -5.6), "Skips");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Skipped out"), 1);
            testCase.verifyEqual(testCase.metric("Final speed"), 7993.6, RelTol=1e-3);
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyEqual(S.Display(S.Quantity == "Skipped out"), "yes");
        end
    end
end
