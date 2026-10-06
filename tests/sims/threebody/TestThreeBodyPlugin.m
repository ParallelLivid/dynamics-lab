classdef (TestTags = {'ui'}) TestThreeBodyPlugin < matlab.unittest.TestCase
    %TESTTHREEBODYPLUGIN The three-body simulator in the app.

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
            testCase.App = DynamicsLab("threebody", Visible=false);
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

    methods
        function L = modes(testCase)
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(testCase.App.View.params()));
        end
    end

    methods (Test)
        function arenstorfCloses(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Return error"), 1e-4);
            testCase.verifyLessThan(testCase.metric("Jacobi drift"), 1e-10);
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Type="image"), "The forbidden region is shaded.");
            testCase.App.View.Playback.seek(8);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function lagrangePointModes(testCase)
            testCase.choosePreset("Planar Lyapunov orbit at L1");
            L = testCase.modes();
            testCase.verifyEqual(L.Modes.Stability(L.Modes.Mode == "Saddle, growing direction"), "Unstable", ...
                "One ± real pair, named by its sign.");
            testCase.verifyEqual(L.Modes.Stability(L.Modes.Mode == "Saddle, decaying direction"), "Stable");
            testCase.verifyEqual(string(L.Modes.Properties.VariableUnits([2 7])), ["1/time unit" "time units"], ...
                "The model's time is dimensionless, not seconds.");
            inPlane = L.Modes(L.Modes.Mode == "In-plane oscillation", :);
            testCase.verifyEqual([inPlane.Real inPlane.DampingRatio], [0 0], "Round-off is not shown (was −1.9e−16).");
            testCase.verifyEqual(inPlane.Eigenvalue, "0 ± 2.334i");
            testCase.pressRun();
            fig = testCase.App.Figure;
            table = findall(fig, Tag="dlab.modes.table");
            testCase.verifyEqual(string(table.ColumnName([2 5])), ["Eigenvalue (1/time unit)"; "Period (time units)"]);
            testCase.verifyEqual(string(findall(fig, Tag="dlab.modes.axes").XLabel.String), "Real (1/time unit)");
            testCase.verifySubstring(string(findall(fig, Tag="dlab.modes.note").Text), "one time unit is 4.348 days");
            testCase.choosePreset("Tadpole orbit at L4");
            L = testCase.modes();
            testCase.verifyEqual(sum(L.Modes.Mode == "In-plane oscillation"), 2);
            testCase.verifyFalse(any(L.Modes.Stability == "Unstable"));
            testCase.App.View.Plugin.requestInputs(struct("system", "custom", "mu", 0.05), "Heavier");
            L = testCase.modes();
            testCase.verifyEqual(sum(L.Modes.Mode == "Growing oscillation (unstable)"), 1);
        end

        function earthMoonUnits(testCase)
            testCase.choosePreset("Through the L1 neck to the Moon");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("L1 x"), 0.836915, AbsTol=1e-6);
            testCase.verifyEqual(testCase.metric("Duration in days"), 30 * 27.321661 / (2 * pi), RelTol=1e-9);
            testCase.verifyLessThan(testCase.metric("Closest to Moon"), 0.1);
        end

        function figureEight(testCase)
            testCase.choosePreset("Figure-8 choreography");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Return error"), 1e-4);
            testCase.verifyLessThan(testCase.metric("Energy drift (relative)"), 1e-9);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("bodies"));
            testCase.verifyFalse(panel.isRowShown("x0"));
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Type="uitab", Title="Trajectories"));
            testCase.App.View.Playback.seek(3);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Restricted (two primaries + a small body)").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function summaryUnitsAndTheTriangleBreaksUp(testCase)
            % Units only in the units column ("relative" was there, and "km"
            % twice); the equal-mass triangle, unstable, breaks up within the
            % preset's 40 time units (it holds to 2e−5 for the first 20).
            testCase.choosePreset("Lagrange equilateral triangle");
            testCase.pressRun();
            r = testCase.App.View.Result;
            S = testCase.App.View.Plugin.summaryTable(r);
            testCase.verifyTrue(all(ismember(S.Units, ["" "km" "days"])), strjoin(S.Units, ", "));
            change = 0;
            for pair = [1 2; 1 3; 2 3]'
                side = sqrt(sum((r.pos(:, pair(1), :) - r.pos(:, pair(2), :)).^2, 3));
                change = max(change, max(abs(side - 1)));
            end
            testCase.verifyGreaterThan(change, 0.5, "The triangle breaks up.");
        end
    end
end
