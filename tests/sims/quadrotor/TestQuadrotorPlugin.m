classdef (TestTags = {'ui'}) TestQuadrotorPlugin < matlab.unittest.TestCase
    %TESTQUADROTORPLUGIN The quadrotor in the app.

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
            testCase.App = DynamicsLab("quadrotor", Plugins={@dlab.sims.quadrotor.QuadrotorPlugin}, Visible=false);
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
        function boxMissionFliesTheSquare(testCase)
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyEqual(r.termination, "completed");
            testCase.verifyLessThan(testCase.metric("Final position error"), 0.1);
            testCase.verifyLessThan(testCase.metric("Max tilt"), 35);
            testCase.verifyEqual(size(r.path.points, 1), 11, "The start, then arrive at and leave each of 5 waypoints.");
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("waypoints"));
            testCase.verifyFalse(panel.isRowShown("zRef"));
            testCase.App.View.Playback.seek(9);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function hoverThrustIsAQuarterOfTheWeight(testCase)
            testCase.choosePreset("Hover (recover from a 20° tilt)");
            testCase.pressRun();
            p = testCase.App.View.params();
            testCase.verifyEqual(testCase.metric("Hover thrust per rotor"), p.m * p.g / 4, RelTol=1e-12);
            testCase.verifyEqual(testCase.metric("Max tilt"), 20, AbsTol=1e-6);
            testCase.verifyLessThan(testCase.metric("Final position error"), 0.1);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("zRef"));
            testCase.verifyFalse(panel.isRowShown("waypoints"));
        end

        function heightStepSettles(testCase)
            testCase.choosePreset("Step in height (3 → 6 m)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Settling time"), 3);
            testCase.verifyLessThan(testCase.metric("Overshoot"), 10);
            testCase.verifyEqual(testCase.metric("Time saturated"), 0);
        end

        function motorFailureSpinsAndCrashes(testCase)
            testCase.choosePreset("Motor failure (rotor 1 stops at 2 s)");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Max yaw rate"), 180);
            testCase.verifyGreaterThan(testCase.metric("Ground contact speed"), 1);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "crashed"));
            testCase.App.View.Playback.seek(3);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function saturatedClimbHitsTheLimit(testCase)
            testCase.choosePreset("Saturated climb (3 → 20 m)");
            testCase.pressRun();
            p = testCase.App.View.params();
            testCase.verifyGreaterThan(testCase.metric("Time saturated"), 1);
            testCase.verifyEqual(testCase.metric("Peak rotor thrust"), p.Tmax, AbsTol=1e-6);
            testCase.verifyLessThan(testCase.metric("Thrust-to-weight ratio"), 1.5);
        end

        function modesAndFrequencyResponse(testCase)
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            lin = plugin.linearization(p);
            x = lin.X0 + 0.01 * (1:numel(lin.X0))' / numel(lin.X0);
            testCase.verifyEqual(lin.F(x), lin.G(x, lin.U0));
            testCase.verifyEqual(lin.U0(1:4)', [0 0 3 0], "Hover at the first waypoint.");
            L = dlab.core.Linearization.analyze(lin);
            testCase.verifyTrue(L.IsEquilibrium);
            testCase.verifyLessThan(max(L.Modes.Real), 0);
            testCase.verifyTrue(any(L.Modes.Mode == "Rotor lag"));
            testCase.verifyTrue(any(L.Modes.Mode == "Roll/pitch oscillation"));
            S = dlab.core.FrequencyResponse.model(lin);
            testCase.verifyEqual(S.InputNames, ["Setpoint x" "Setpoint y" "Setpoint z" "Setpoint yaw" ...
                "Disturbance force x"]);
            testCase.verifyEqual(S.OutputNames, ["x" "y" "z" "Yaw"]);
            dc = -S.C / S.A * S.B;
            testCase.verifyEqual(dc(:, 1:4), eye(4), AbsTol=1e-6);
            % Aggressive gains: lightly damped, but still stable.
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.presetParams("Aggressive gains (oscillatory)")));
            testCase.verifyLessThan(max(L.Modes.Real), 0);
            testCase.verifyLessThan(min(L.Modes.DampingRatio), 0.2);
            % Rotors at a fixed thrust: no closed loop to analyse.
            p.controller = "off";
            testCase.verifyEmpty(plugin.linearization(p));
        end

        function roundOffIsDrawnFlat(testCase)
            % After a pure roll x and yaw stay 0 up to 1e−16, which the plots
            % stretched into a wiggle.
            testCase.choosePreset("Hover (recover from a 20° tilt)");
            testCase.pressRun();
            tabs = [findall(testCase.App.Figure, Type="uitab", Title="Position"), ...
                findall(testCase.App.Figure, Type="uitab", Title="Attitude")];
            all = findall(tabs, Type="axes");
            for label = ["x (m)" "Yaw (°)"]
                ax = all(arrayfun(@(a) string(a.YLabel.String) == label, all));
                testCase.assertNumElements(ax, 1, label);
                testCase.verifyGreaterThanOrEqual(diff(ax.YLim), 0.02, label);
            end
            % A real motion keeps its own scale.
            ax = all(arrayfun(@(a) string(a.YLabel.String) == "y (m)", all));
            testCase.verifyLessThan(diff(ax.YLim), 1);
        end

        function inputsFitAndExplainThemselves(testCase)
            % "Attitude commands + height hold" and "Cascaded position control"
            % were cut off, and 27 inputs had no tooltip.
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function presetsMatchAnIndependentClosedLoop(testCase)
            % Independent reference: a separate quadrotor and controller, integrated in scipy.
            % My own quadrotor, written from the docs (scipy RK45, sampled
            % every 0.02 s as here).
            testCase.choosePreset("Saturated climb (3 → 20 m)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Time saturated"), 2.38, AbsTol=0.021);
            testCase.verifyEqual(testCase.metric("Settling time"), 3.28, AbsTol=0.021);
            testCase.choosePreset("Motor failure (rotor 1 stops at 2 s)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Max yaw rate"), 370.76, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("Ground contact speed"), 12.06, RelTol=1e-3);
            testCase.App.View.Plugin.requestInputs(struct("failScale", 0.5), "Half");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Final height"), 9.6494, RelTol=1e-4);
            testCase.verifyEqual(testCase.metric("Max yaw rate"), 15.425, RelTol=1e-3);
            % My own hover Jacobian (the same model, 20 states): −0.14 is the
            % height loop's slowest pole, −0.3623 (twice) the horizontal ones.
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            testCase.verifyEqual(L.Modes.Real(L.Modes.Mode == "Height integral (slow)"), -0.1400, AbsTol=5e-5);
            testCase.verifyEqual(sort(L.Modes.Real(L.Modes.Mode == "Horizontal integral (slow)")), ...
                [-0.6383; -0.6383; -0.3623; -0.3623], AbsTol=5e-5);
            testCase.verifyFalse(any(L.Modes.Mode == "Integral (slow)"));
            % The tilt limit bounds the command, not the motion: 48° with 30°.
            testCase.choosePreset("Aggressive gains (oscillatory)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Max tilt"), 48.007, RelTol=1e-4);
        end
    end
end
