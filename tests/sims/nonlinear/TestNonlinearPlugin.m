classdef (TestTags = {'ui'}) TestNonlinearPlugin < matlab.unittest.TestCase
    %TESTNONLINEARPLUGIN The nonlinear oscillators simulator in the app.

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
            testCase.App = DynamicsLab("nonlinear", Visible=false);
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

        function ax = axesTitled(testCase, title)
            all = findall(testCase.App.Figure, Type="axes");
            ax = all(arrayfun(@(a) string(a.Title.String) == title, all));
            testCase.assertNumElements(ax, 1, title);
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
        end
    end

    methods (Test)
        function doubleWellIsChaotic(testCase)
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Distinct Poincaré points"), 32);
            D = testCase.App.View.Plugin.distributions(testCase.App.View.Result);
            testCase.verifyEqual(D.Quantity, "Poincaré x");
            testCase.verifyEqual(numel(D.Values{1}), 151, "Periods 150 to 300.");
            testCase.App.View.Playback.seek(100);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function vanDerPolLimitCycle(testCase)
            testCase.choosePreset("Van der Pol: limit cycle");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Limit-cycle amplitude"), 2.0086, AbsTol=1e-3);
            testCase.verifyEqual(testCase.metric("Cycle period"), 6.6633, AbsTol=1e-3);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("tspan"));
            testCase.verifyFalse(panel.isRowShown("periods"));
            testCase.verifyFalse(panel.isRowShown("alpha"));
        end

        function pendulumPeriodDoubling(testCase)
            testCase.choosePreset("Driven pendulum: period-1");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Distinct Poincaré points"), 1);
            testCase.choosePreset("Driven pendulum: period-2");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Distinct Poincaré points"), 2);
            D = testCase.App.View.Plugin.distributions(testCase.App.View.Result);
            testCase.verifyEqual(D.Quantity, "Poincaré θ");
        end

        function bifurcationSweep(testCase)
            % A short sweep of the drive: every run adds its section points.
            testCase.choosePreset("Driven pendulum: period-1");
            plugin = testCase.App.View.Plugin;
            params = plugin.presetParams("Driven pendulum: period-1");
            S = dlab.core.Sweep.run(plugin, params, "A", [0.9 1.07]);
            testCase.verifyEqual(S.SetNames, "Poincaré θ");
            testCase.verifyEqual(cellfun(@numel, S.SetData(:, 1)), [101; 101]);
            testCase.verifyEqual(numel(uniquetol(S.SetData{2, 1}, 1e-3)), 2, "Period-2 at A = 1.07.");
        end

        function sectionAndPotentialStayReadable(testCase)
            % A period-1 section is one point plus rounding noise: its axes
            % must not zoom into the noise (1e-13 wide before).
            testCase.choosePreset("Driven pendulum: period-1");
            testCase.pressRun();
            ax = testCase.axesTitled("Poincaré section: once per forcing period (101 points)");
            testCase.verifyGreaterThan(diff(ax.XLim), 0.4, "At least a tenth of θ's swing (about 5 rad).");
            testCase.verifyGreaterThan(diff(ax.YLim), 0.3, "At least a tenth of θ' (about 4 rad/s).");
            % Chaos turns the pendulum over and over: the Potential tab shows
            % one turn, and the Summary has no amplitude for θ.
            testCase.choosePreset("Driven pendulum: chaos (A = 1.5)");
            testCase.pressRun();
            ax = testCase.axesTitled("Potential energy");
            testCase.verifyLessThan(diff(ax.XLim), 1.3 * 2 * pi, "One turn, though θ runs over 150 rad.");
            testCase.verifyEqual(string(ax.YLabel.String), "V(θ) = 1 − cos θ");
            plugin = testCase.App.View.Plugin;
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyEqual(S.Display(S.Quantity == "Steady amplitude"), "— (turns over the top)");
            testCase.verifyEqual(S.Units(S.Quantity == "Steady amplitude"), "rad");
            T = plugin.exportTable(testCase.App.View.Result);
            testCase.verifyEqual(string(T.Properties.VariableUnits), ["s" "rad" "rad/s" ""]);
        end

        function freeDampedMotionSettlesToRest(testCase)
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            [params.A, params.alpha, params.beta] = deal(0, 1, 1);
            r = plugin.solve(params);
            testCase.verifyEqual(plugin.resultNote(r), "settles to rest");
            S = plugin.summaryTable(r);
            testCase.verifyEqual(S.Display(S.Quantity == "Dominant frequency"), "— (at rest)");
        end

        function modesAtTheBottomOfTheWell(testCase)
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            testCase.verifyEqual(L.Modes.Mode, "Oscillation", "A conjugate pair is one mode.");
            testCase.verifyEqual(L.Modes.NaturalFrequency(1), sqrt(2), RelTol=1e-6);
            params = plugin.defaultParams();
            params.x0 = 0;
            L = dlab.core.Linearization.analyze(plugin.linearization(params));
            testCase.verifyEqual(L.Modes.Mode, ["Unstable (saddle)"; "Unstable (saddle)"]);
        end
    end
end
