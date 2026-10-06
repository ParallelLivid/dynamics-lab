classdef (TestTags = {'ui'}) TestQuarterCarPlugin < matlab.unittest.TestCase
    %TESTQUARTERCARPLUGIN The quarter-car suspension simulator in the app.

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
            testCase.App = DynamicsLab("quartercar", Visible=false);
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
        end
    end

    methods (Test)
        function speedBumpStaysOnTheRoad(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Body bounce frequency (undamped)"), 1.238, AbsTol=0.002);
            testCase.verifyEqual(testCase.metric("Wheel hop frequency (undamped)"), 11.81, AbsTol=0.01);
            testCase.verifyEqual(testCase.metric("Suspension damping ratio"), 1500 / (2 * sqrt(20000 * 300)), ...
                RelTol=1e-12);
            testCase.verifyEqual(testCase.metric("Wheel left the road"), 0);
            testCase.verifyEqual(testCase.metric("Peak body acceleration"), 7.9, AbsTol=0.3);
            testCase.verifyEqual(testCase.metric("Static tire load"), 340 * 9.81, RelTol=1e-12);
        end

        function modesAreBodyBounceAndWheelHop(testCase)
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            bounce = L.Modes(L.Modes.Mode == "Body bounce", :);
            hop = L.Modes(L.Modes.Mode == "Wheel hop", :);
            testCase.verifyEqual(height(bounce), 1, "A conjugate pair is one mode.");
            testCase.verifyEqual(height(hop), 1);
            testCase.verifyEqual(bounce.NaturalFrequency(1), 7.90, AbsTol=0.02);
            testCase.verifyEqual(hop.NaturalFrequency(1), 73.1, AbsTol=0.1);
        end

        function wornDampersLetTheWheelHop(testCase)
            testCase.choosePreset("Worn dampers");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Wheel left the road"), 1);
            testCase.verifyEqual(testCase.metric("Minimum tire load"), 0);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("length"));
            testCase.verifyFalse(panel.isRowShown("isoClass"));
        end

        function roughRoadDrawsEveryTab(testCase)
            testCase.choosePreset("Rough road (ISO class D, 80 km/h)");
            testCase.pressRun();
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("isoClass"));
            testCase.verifyFalse(panel.isRowShown("length"));
            testCase.verifyGreaterThan(testCase.metric("RMS body acceleration"), 1);
            testCase.App.View.Playback.seek(5);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function summaryReadsYesOrNo(testCase)
            % "yes"/"no" and the time off the road, not "1  yes = 1".
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            p.speed = 40;
            S = plugin.summaryTable(plugin.solve(p));
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyEqual(shown(S.Quantity == "Wheel left the road"), "yes");
            testCase.verifyEqual(S.Value(S.Quantity == "Time off the road"), 0.05, AbsTol=0.004);
            testCase.verifyFalse(any(contains(S.Units, "=")), "Units are units only.");
            testCase.verifyFalse(any(contains(shown, "NaN")));
        end

        function pullingTireIsNotCalledAirborne(testCase)
            % With lift-off off the wheel never leaves the road; the note
            % says the tire pulled it instead.
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            [p.speed, p.liftoff] = deal(80, false);
            r = plugin.solve(p);
            [note, level] = plugin.resultNote(r);
            testCase.verifyEqual(level, "warning");
            testCase.verifySubstring(note, "the tire pulled the road");
            S = plugin.summaryTable(r);
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyEqual(shown(S.Quantity == "Wheel left the road"), "no");
            testCase.verifyGreaterThan(S.Value(S.Quantity == "Time the tire pulled the road"), 0);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for
            % their fields ("Rough (ISO 8…" was cut off).
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end
    end
end
