classdef (TestTags = {'ui'}) TestCartPolePlugin < matlab.unittest.TestCase
    %TESTCARTPOLEPLUGIN The inverted pendulum on a cart in the app.

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
            testCase.App = DynamicsLab("cartpole", Visible=false);
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
        function lqrBalances(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Settling time (θ within 1°)"), 3);
            testCase.verifyLessThan(testCase.metric("Final x error"), 0.01);
            testCase.verifyLessThan(testCase.metric("Slowest closed-loop pole"), 0);
            testCase.verifyEqual(testCase.metric("Time saturated"), 0);
            testCase.App.View.Playback.seek(1);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function withoutControlItTopples(testCase)
            testCase.choosePreset("Falls without control");
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(testCase.App.View.params()));
            testCase.verifyEqual(sum(L.Modes.Mode == "Topple (unstable)"), 1);
            testCase.verifyEqual(sum(L.Modes.Mode == "Cart drift (neutral)"), 1);
            testCase.pressRun();
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "fell"));
        end

        function lqrModesAreStable(testCase)
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            testCase.verifyEqual(sum(L.Modes.Mode == "Topple (unstable)"), 0);
            testCase.verifyLessThan(max(L.Modes.Real), 0);
        end

        function weakMotorFallsOff(testCase)
            testCase.choosePreset("Weak motor (saturation)");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Time saturated"), 50);
            testCase.verifyEmpty(testCase.metric("Settling time (θ within 1°)"));
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("qtheta"));
            testCase.verifyFalse(panel.isRowShown("Kp"));
        end

        function referenceStepMovesTheCart(testCase)
            testCase.choosePreset("LQR: move the cart 1 m (reference step)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Final x error"), 0.01);
            testCase.verifyGreaterThanOrEqual(testCase.metric("Cart overshoot"), 0);
        end

        function summaryNeverShowsNaN(testCase)
            % A run that falls has no settling time: a dash, not "NaN". With
            % no controller there is no closed loop and no target to miss.
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            params.controller = "none";
            result = plugin.solve(params);
            S = plugin.summaryTable(result);
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyFalse(any(contains(shown, "NaN")), strjoin(shown, ", "));
            testCase.verifyEqual(shown(S.Quantity == "Settling time (θ within 1°)"), "— (the pole fell)");
            testCase.verifyFalse(any(S.Quantity == "Slowest closed-loop pole"));
            testCase.verifyFalse(any(S.Quantity == "Final x error"));
            testCase.verifyEqual(S.Value(S.Quantity == "Open-loop unstable pole"), 3.970628, "AbsTol", 1e-6);
            params = plugin.defaultParams();
            [params.theta0, params.Fmax] = deal(10, 2);
            S = plugin.summaryTable(plugin.solve(params));
            testCase.verifyEqual(S.Display(S.Quantity == "Settling time (θ within 1°)"), "— (the cart hit the end stop)");
        end

        function neutralPoleReadsZero(testCase)
            % PID on the angle alone: the cart's position and ∫θ are both
            % neutral (poles at 0); rounding left 3e-15, shown as a pole.
            testCase.choosePreset("PID: balances, cart drifts");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Slowest closed-loop pole"), 0);
            areas = findall(testCase.App.Figure, Type="uitextarea");
            text = strings(0, 1);
            for k = 1:numel(areas)
                value = string(areas(k).Value);
                if any(startsWith(value, "Controller:"))
                    text = value;
                end
            end
            testCase.verifyNotEmpty(text, "The Gains and poles text.");
            testCase.verifyTrue(any(text == "  0"));
            testCase.verifyFalse(any(contains(text, "e-1")), strjoin(text, " | "));
        end

        function unstableLoopIsFlagged(testCase)
            % PD on the angle with no cart loop: a slow unstable pole at
            % +0.0333 1/s (the cart runs away), from the characteristic polynomial.
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            [params.controller, params.Ki, params.Kx, params.Kv] = deal("pid", 0, 0, 0);
            result = plugin.solve(params);
            [note, level] = plugin.resultNote(result);
            testCase.verifyEqual(level, "warning");
            testCase.verifySubstring(note, "unstable (a pole at +0.0333 1/s)");
            [~, level] = plugin.resultNote(plugin.solve(plugin.defaultParams()));
            testCase.verifyEqual(level, "success");
        end

        function inputsFitAndExplainThemselves(testCase)
            % Choice labels short enough for their fields ("Uniform rod (l…",
            % "PID on the an…"), and a tooltip on every input.
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
            panel = testCase.App.View.Inputs;
            testCase.choosePreset("Falls without control");
            testCase.verifyFalse(panel.isRowShown("Fmax"), "No motor limit without a controller.");
            testCase.pressRun();
            ax = findall(testCase.App.Figure, Type="axes");
            ax = ax(arrayfun(@(a) string(a.Title.String) == "Motor force (no controller)", ax));
            testCase.verifyNumElements(ax, 1);
            testCase.verifyEmpty(findobj(ax, Type="patch"), "No ±Fmax band without a motor.");
        end
    end
end
