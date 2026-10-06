classdef (TestTags = {'ui'}) TestDcMotorPlugin < matlab.unittest.TestCase
    %TESTDCMOTORPLUGIN The DC motor servo in the app.

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
            testCase.App = DynamicsLab("dcmotor", Plugins={@dlab.sims.dcmotor.DcMotorPlugin}, Visible=false);
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

        function value = solvedMetric(testCase, params, quantity)
            plugin = testCase.App.View.Plugin;
            M = plugin.metrics(plugin.solve(params));
            value = M.Value(M.Quantity == quantity);
        end
    end

    methods (Test)
        function positionPDSettlesQuickly(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Overshoot"), 3);
            testCase.verifyLessThan(testCase.metric("Settling time (2 %)"), 0.2);
            testCase.verifyLessThan(testCase.metric("Final error"), 0.01);
            testCase.verifyEqual(testCase.metric("Time at the voltage limit"), 0);
            testCase.verifyEqual(testCase.metric("Peak voltage (applied)"), 15.708, "AbsTol", 0.01, ...
                "Kp times the 90° step, at the instant of the step.");
            testCase.App.View.Playback.seek(0.2);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function openLoopTimeConstant(testCase)
            testCase.choosePreset("Open loop: voltage step");
            testCase.pressRun();
            tau = 1e-3 * 2 / (0.1^2 + 1e-4 * 2);
            testCase.verifyEqual(testCase.metric("Mechanical time constant"), tau, "RelTol", 1e-12);
            testCase.verifyEqual(testCase.metric("Time to 63 %"), tau, "RelTol", 0.02);
            testCase.verifyEqual(testCase.metric("Final speed"), 12 * 0.1 / 0.0102 * 30 / pi, "RelTol", 0.005);
            testCase.verifyEmpty(testCase.metric("Final error"), "No reference in open loop.");
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("voltage"));
            testCase.verifyFalse(panel.isRowShown("Kp"));
            testCase.verifyFalse(panel.isRowShown("antiWindup"));
        end

        function positionPOvershootFollowsTheDampingRatio(testCase)
            testCase.choosePreset("Position P (oscillatory)");
            testCase.pressRun();
            zeta = testCase.metric("Lowest damping ratio");
            testCase.verifyEqual(zeta, 0.1425, "AbsTol", 0.002);
            testCase.verifyEqual(testCase.metric("Overshoot"), 100 * exp(-pi * zeta / sqrt(1 - zeta^2)), ...
                "RelTol", 0.03);
        end

        function speedPIRemovesTheError(testCase)
            testCase.choosePreset("Speed loop: PI (Ki = 0 for P)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Final error"), 0.1);
            params = testCase.App.View.params();
            params.KiSpeed = 0;
            G = 0.1 / 0.0102;
            testCase.verifyEqual(testCase.solvedMetric(params, "Final error"), 600 / (1 + 0.3 * G), ...
                "RelTol", 1e-4, "P only: e = r / (1 + G Kp).");
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("KiSpeed"));
            testCase.verifyFalse(panel.isRowShown("Kd"));
        end

        function clampingTamesWindup(testCase)
            testCase.choosePreset("PID, saturated: windup");
            testCase.pressRun();
            wound = testCase.metric("Overshoot");
            testCase.verifyGreaterThan(testCase.metric("Time at the voltage limit"), 0.05);
            testCase.choosePreset("PID, saturated: anti-windup");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Overshoot"), wound / 2);
            testCase.verifyEqual(testCase.metric("Peak voltage (applied)"), 12, "AbsTol", 1e-9);
        end

        function integralRejectsALoad(testCase)
            testCase.choosePreset("Load torque disturbance (PID)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Final error"), 0.05);
            testCase.verifyEmpty(testCase.metric("Overshoot"), "No reference step: no step metrics.");
            params = testCase.App.View.params();
            params.Ki = 0;
            testCase.verifyEqual(testCase.solvedMetric(params, "Final error"), rad2deg(0.1 * 2 / (0.1 * 10)), ...
                "RelTol", 1e-4, "PD: e = τ R / (K Kp).");
            testCase.App.View.Playback.seek(1);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function modesAreTheMotorAlone(testCase)
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            lin = plugin.linearization(params);
            L = dlab.core.Linearization.analyze(lin);
            testCase.verifyTrue(L.IsEquilibrium);
            testCase.verifyEqual(sort(L.Modes.Mode)', ["Electrical (current)" "Mechanical (speed)" "Shaft angle (neutral)"]);
            [J, R, Lh, K, b] = deal(1e-3, 2, 5e-3, 0.1, 1e-4);
            poles = roots([J * Lh, J * R + b * Lh, b * R + K^2]);
            testCase.verifyEqual(sort(L.Modes.Real(L.Modes.Real < 0)), sort(poles), "RelTol", 1e-5);
            mechanical = L.Modes(L.Modes.Mode == "Mechanical (speed)", :);
            testCase.verifyEqual(mechanical.TimeConstant, 0.1936, "AbsTol", 1e-4);
            % The frequency-response fields: u = [V; τ], outputs [ω; θ].
            x = [0.3; -2; 0.7];
            u = [5; 0.02];
            testCase.verifyEqual(lin.F(x), lin.G(x, lin.U0), "AbsTol", 1e-15);
            testCase.verifyEqual(lin.H(x, u), [-2; 0.7]);
            testCase.verifyEqual(lin.G(x, u), [(5 - R * 0.3 - K * -2) / Lh; (K * 0.3 - b * -2 - 0.02) / J; -2], ...
                "RelTol", 1e-12);
            testCase.verifyEqual(numel(lin.InputNames), numel(lin.U0));
            testCase.verifyEqual(numel(lin.OutputNames), numel(lin.H(lin.X0, lin.U0)));
            % With L = 0 the current is not a state.
            params.L = 0;
            L = dlab.core.Linearization.analyze(plugin.linearization(params));
            testCase.verifyEqual(height(L.Modes), 2);
            testCase.verifyEqual(min(L.Modes.Real), -(K^2 / R + b) / J, "RelTol", 1e-6);
        end

        function exportsWithUnits(testCase)
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            T = plugin.exportTable(testCase.App.View.Result);
            testCase.verifyEqual(T.Properties.VariableUnits{2}, 'deg');
            testCase.verifyEqual(T.Properties.VariableUnits{7}, 'deg');
            testCase.verifyEqual(T.angle(end), 90, "AbsTol", 0.01);
            % Open loop has no reference, so no reference or error columns
            % (they were all NaN).
            params = plugin.defaultParams();
            params.mode = "open";
            T = plugin.exportTable(plugin.solve(params));
            testCase.verifyFalse(any(ismember(["reference" "error"], T.Properties.VariableNames)));
            testCase.verifyTrue(all(isfinite(T{:, :}), "all"));
            testCase.verifyTrue(all(string(T.Properties.VariableUnits) ~= ""));
        end

        function summaryNeverShowsNaN(testCase)
            % A loop with no gain does not move: no step metrics, and dashes
            % instead of "NaN" in the Summary.
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            [params.Kp, params.Kd] = deal(0, 0);
            S = plugin.summaryTable(plugin.solve(params));
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyFalse(any(contains(shown, "NaN")), strjoin(shown, ", "));
            testCase.verifyEqual(shown(S.Quantity == "Overshoot"), "— (no change after the step)");
            testCase.verifyEmpty(plugin.metrics(plugin.solve(params)).Value( ...
                plugin.metrics(plugin.solve(params)).Quantity == "Overshoot"));
            testCase.verifyEqual(S.Value(S.Quantity == "Final error"), 90, "AbsTol", 1e-9);
        end

        function dampingIsTheLeastDampedPole(testCase)
            % PID: a real pole at −10.41 is the slowest, but the pair at
            % −13.39 ± 9.244i, nearly as slow, has ζ = 0.823. The Summary
            % used to report ζ = 1 (the slowest pole's).
            testCase.choosePreset("PID, saturated: anti-windup");
            testCase.pressRun();
            pair = complex(-13.3916914, 9.2442596);
            testCase.verifyEqual(testCase.metric("Lowest damping ratio"), -real(pair) / abs(pair), "AbsTol", 1e-6);
            testCase.verifyEqual(testCase.metric("Slowest closed-loop pole"), -10.4062171, "AbsTol", 1e-6);
        end

        function unstableLoopIsFlagged(testCase)
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            params.Ki = 5000;
            [note, level] = plugin.resultNote(plugin.solve(params));
            testCase.verifyEqual(level, "warning");
            testCase.verifySubstring(note, "unstable");
            testCase.verifyLessThan(plugin.metrics(plugin.solve(params)).Value( ...
                plugin.metrics(plugin.solve(params)).Quantity == "Lowest damping ratio"), 0);
            [~, level] = plugin.resultNote(plugin.solve(plugin.defaultParams()));
            testCase.verifyEqual(level, "success");
        end

        function inputsFitAndExplainThemselves(testCase)
            % Choice labels short enough for their fields (they were cut
            % off: "Position contr…"), and a tooltip on every input.
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 10, spec.Name);
                end
            end
        end
    end
end
