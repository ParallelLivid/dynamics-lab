classdef (TestTags = {'ui'}) TestFramePlugin < matlab.unittest.TestCase
    %TESTFRAMEPLUGIN The 2-D frame and beam solver in the app.

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
            testCase.App = DynamicsLab("frame", Visible=false);
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
        function cantileverTipDeflection(testCase)
            testCase.pressRun();
            EI = 200e9 * 8356e-8;
            testCase.verifyEqual(testCase.metric("Max displacement"), 1e3 * 10e3 * 4^3 / (3 * EI), RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Max |M|"), 40, RelTol=1e-12);
            testCase.verifyLessThan(testCase.metric("Equilibrium residual (relative)"), 1e-9);
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Type="patch"), "Diagrams are drawn as patches.");
        end

        function beamPresets(testCase)
            testCase.choosePreset("Simply supported beam (UDL)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Max |M|"), 5 * 6^2 / 8, RelTol=1e-10);
            testCase.choosePreset("Fixed-end beam");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Max |M|"), 5 * 6^2 / 12, RelTol=1e-10);
            testCase.verifyEqual(testCase.metric("Degree of indeterminacy"), 3);
            testCase.choosePreset("Gable frame (snow load)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Equilibrium residual (relative)"), 1e-9);
        end

        function draggingANodeIsOneEdit(testCase)
            testCase.choosePreset("Portal frame (wind load)");
            testCase.pressRun();
            before = testCase.metric("Max |M|");
            plugin = testCase.App.View.Plugin;
            plugin.dragNode(3, [6.2 5.1]);                       % snaps to 0.5 m: (6, 5)
            params = testCase.App.View.params();
            testCase.verifyEqual([params.nodes.x(3) params.nodes.y(3)], [6 5]);
            testCase.pressRun();
            testCase.verifyNotEqual(testCase.metric("Max |M|"), before);
            undo = findall(testCase.App.Figure, Tag="dlab.undo");
            undo.ButtonPushedFcn(undo, []);
            params = testCase.App.View.params();
            testCase.verifyEqual([params.nodes.x(3) params.nodes.y(3)], [6 4], "One undo restores the node.");
        end

        function mechanismIsReported(testCase)
            testCase.App.View.Plugin.requestInputs(struct("supports", table(1, "pin", ...
                VariableNames=["node" "type"])), "Pin only");
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "mechanism"));
        end

        function summaryAndLabelsAreClean(testCase)
            % Units are units only ("m from the element start" was in the
            % units column); the gable's ridge moves straight down, so its
            % label reads 0, not −8.4e−15 mm.
            testCase.choosePreset("Gable frame (snow load)");
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyTrue(all(ismember(S.Units, ["" "kN·m" "kN" "m" "mm"])), strjoin(S.Units, ", "));
            labels = string(get(findall(testCase.App.Figure, Type="text"), "String"));
            testCase.verifyFalse(any(contains(labels, "e-1")), strjoin(labels(contains(labels, "e-1")), " | "));
            testCase.verifyTrue(any(contains(labels, "C: 0, -2 mm")));
        end
    end
end
