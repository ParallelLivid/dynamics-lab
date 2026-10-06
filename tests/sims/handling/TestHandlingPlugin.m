classdef (TestTags = {'ui'}) TestHandlingPlugin < matlab.unittest.TestCase
    %TESTHANDLINGPLUGIN The vehicle handling simulator in the app.

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
            testCase.App = DynamicsLab("handling", Plugins={@dlab.sims.handling.HandlingPlugin}, Visible=false);
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
        function familyCarUndersteers(testCase)
            testCase.pressRun();
            [m, a, b, Cf, Cr, V] = deal(1500, 1.1, 1.6, 80000, 110000, 100 / 3.6);
            L = a + b;
            K = m / L * (b / Cf - a / Cr);
            testCase.verifyEqual(testCase.metric("Understeer gradient"), rad2deg(K * 9.81), "RelTol", 1e-10);
            testCase.verifyEqual(testCase.metric("Understeer gradient"), 3.123, "AbsTol", 1e-3);
            testCase.verifyEqual(testCase.metric("Steady-state yaw-rate gain"), V / (L + K * V^2), "RelTol", 1e-9);
            testCase.verifyEqual(testCase.metric("Characteristic speed"), 3.6 * sqrt(L / K), "RelTol", 1e-10);
            testCase.verifyEmpty(testCase.metric("Critical speed"));
            testCase.verifyEqual(testCase.metric("Linear model stable"), 1);
            steady = V^2 / (L + K * V^2) * deg2rad(2);
            r = testCase.App.View.Result;
            testCase.verifyEqual(r.ay(end), steady, "RelTol", 1e-4, "Settled: a_y = V² δ / (L + K V²).");
            testCase.verifyEqual(testCase.metric("Peak lateral acceleration"), 1.034 * steady / 9.81, ...
                "RelTol", 2e-3, "A 3.4 % overshoot: damping ratio 0.66.");
            testCase.App.View.Playback.seek(3);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function neutralSteerGainIsVOverL(testCase)
            testCase.choosePreset("Neutral steer: step steer");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Understeer gradient"), 0);
            testCase.verifyEqual(testCase.metric("Steady-state yaw-rate gain"), 80 / 3.6 / 2.7, "RelTol", 1e-10);
            testCase.verifyEqual(testCase.metric("Steady-state yaw-rate gain"), ...
                testCase.metric("Neutral-steer gain V/L"), "RelTol", 1e-10);
            testCase.verifyEmpty(testCase.metric("Characteristic speed"));
            testCase.verifyEmpty(testCase.metric("Critical speed"));
        end

        function oversteerAboveTheCriticalSpeedSpins(testCase)
            testCase.choosePreset("Oversteer, below the critical speed (70 km/h)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Critical speed"), 3.6 * 27, "AbsTol", 0.01);
            testCase.verifyEqual(testCase.metric("Linear model stable"), 1);
            testCase.verifyEqual(testCase.metric("Spun out"), 0);
            testCase.verifyGreaterThan(testCase.metric("Steady-state yaw-rate gain"), ...
                testCase.metric("Neutral-steer gain V/L"), "Oversteer: more yaw than the neutral car.");
            testCase.choosePreset("Oversteer, above the critical speed (120 km/h)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Linear model stable"), 0);
            testCase.verifyEqual(testCase.metric("Spun out"), 1);
            testCase.verifyEmpty(testCase.metric("Steady-state yaw-rate gain"));
            testCase.App.View.Playback.seek(1);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function modesAndFrequencyResponseFields(testCase)
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            lin = plugin.linearization(params);
            L = dlab.core.Linearization.analyze(lin);
            testCase.verifyTrue(L.IsEquilibrium);
            testCase.verifyEqual(L.Modes.Mode, "Yaw–sideslip oscillation", ...
                "At 100 km/h the understeering car's two poles are a lightly damped pair.");
            q = plugin.presetParams("Family car (understeer): step steer");
            q.speed = 20;                       % slow: two real roots
            L = dlab.core.Linearization.analyze(plugin.linearization(q));
            testCase.verifyEqual(sort(L.Modes.Mode)', ["Sideslip mode" "Yaw mode"]);
            q = plugin.presetParams("Oversteer, above the critical speed (120 km/h)");
            L = dlab.core.Linearization.analyze(plugin.linearization(q));
            unstable = L.Modes(L.Modes.Mode == "Spin divergence (unstable)", :);
            testCase.verifyEqual(height(unstable), 1);
            testCase.verifyGreaterThan(unstable.Real, 0);

            % The frequency-response fields: u = δ (rad), outputs [r; a_y].
            x = [0.3; -0.05];
            testCase.verifyEqual(lin.F(x), lin.G(x, lin.U0), "AbsTol", 1e-12);
            testCase.verifyEqual(numel(lin.InputNames), numel(lin.U0));
            testCase.verifyEqual(numel(lin.OutputNames), numel(lin.H(lin.X0, lin.U0)));
            A = dlab.physics.jacobian(lin.F, lin.X0, Scale=lin.Scale(:));
            B = dlab.physics.jacobian(@(u) lin.G(lin.X0, u), lin.U0);
            C = dlab.physics.jacobian(@(s) lin.H(s, lin.U0), lin.X0, Scale=lin.Scale(:));
            D = dlab.physics.jacobian(@(u) lin.H(lin.X0, u), lin.U0);
            dc = -C * (A \ B) + D;
            [m, a, b, Cf, Cr, V] = deal(1500, 1.1, 1.6, 80000, 110000, 100 / 3.6);
            K = m / (a + b) * (b / Cf - a / Cr);
            testCase.verifyEqual(dc(1), V / (a + b + K * V^2), "RelTol", 1e-6, "DC gain r/δ.");
            testCase.verifyEqual(dc(2), V^2 / (a + b + K * V^2), "RelTol", 1e-6, "DC gain a_y/δ = V r/δ.");
        end

        function laneChangeEndsStraight(testCase)
            testCase.choosePreset("Double lane change (80 km/h)");
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyEqual(testCase.metric("Final heading"), 0, "AbsTol", 1);
            testCase.verifyEqual(max(r.y), 3.25, "AbsTol", 0.1, "One lane over and back.");
            testCase.verifyEqual(r.y(end), 0, "AbsTol", 0.1);
            testCase.verifyLessThan(testCase.metric("Peak lateral acceleration"), 0.6);
            testCase.App.View.Playback.seek(2.4);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function tyreLimitCapsLateralAcceleration(testCase)
            testCase.choosePreset("Tyre limit: understeer (saturating tyres)");
            testCase.pressRun();
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("mu"));
            peak = testCase.metric("Peak lateral acceleration");
            testCase.verifyLessThan(peak, 0.9);
            testCase.verifyGreaterThan(peak, 0.84);
            r = testCase.App.View.Result;
            testCase.verifyGreaterThan(abs(r.alphaF(end)), 1.5 * abs(r.alphaR(end)), ...
                "Understeer at the limit: the front tyres slide first.");
        end

        function exportsWithUnits(testCase)
            testCase.choosePreset("Slalom (sine steering, 60 km/h)");
            testCase.pressRun();
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("mu"));
            T = testCase.App.View.Plugin.exportTable(testCase.App.View.Result);
            testCase.verifyEqual(T.Properties.VariableUnits{5}, 'deg');
            testCase.verifyEqual(T.Properties.VariableUnits{8}, 'm/s^2');
            testCase.verifyEqual(max(abs(T.steering)), 2, "AbsTol", 0.01);
        end

        function summaryReadsYesOrNo(testCase)
            % "yes"/"no", not "1  yes = 1"; a spin with linear tyres says
            % its forces are not physical (6.3 g at the end).
            testCase.choosePreset("Oversteer, above the critical speed (120 km/h)");
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            r = testCase.App.View.Result;
            S = plugin.summaryTable(r);
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyEqual(shown(S.Quantity == "Spun out"), "yes");
            testCase.verifyEqual(shown(S.Quantity == "Linear model stable"), "no");
            testCase.verifyFalse(any(contains(S.Units, "=")), "Units are units only.");
            note = plugin.resultNote(r);
            testCase.verifySubstring(note, "linear tyres have no grip limit");
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Linear (F = −C α)" was cut off); the Bode tab has units.
            plugin = testCase.App.View.Plugin;
            for spec = plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                testCase.verifyLessThanOrEqual(strlength(spec.Label), 30, spec.Name + "'s label is cut off.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
            lin = plugin.linearization(plugin.defaultParams());
            testCase.verifyEqual(lin.InputUnits, "rad");
            testCase.verifyEqual(lin.OutputUnits, ["rad/s" "m/s²"]);
        end
    end
end
