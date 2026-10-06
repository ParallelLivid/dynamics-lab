classdef (TestTags = {'ui'}) TestAttitudePlugin < matlab.unittest.TestCase
    %TESTATTITUDEPLUGIN The spacecraft attitude control simulator in the app.

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
            testCase.App = DynamicsLab("attitude", Plugins={@dlab.sims.attitude.AttitudePlugin}, Visible=false);
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

        function tf = hasTab(testCase, title)
            tf = ~isempty(findall(testCase.App.Figure, Type="uitab", Title=title));
        end
    end

    methods (Test)
        function pdSlewSettles(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Slew time (within 0.1°)"), 120);
            testCase.verifyLessThan(testCase.metric("Final pointing error"), 0.1);
            testCase.verifyEqual(testCase.metric("Initial error"), 90, AbsTol=1e-9);
            testCase.verifyEqual(testCase.metric("Wheels saturated"), 0);
            testCase.verifyTrue(testCase.hasTab("Wheel momentum"));
            testCase.App.View.Playback.seek(50);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function bangBangMatchesTheMinimumTime(testCase)
            testCase.choosePreset("Bang-bang slew (thrusters)");
            testCase.pressRun();
            T = 2 * sqrt(pi / 2 * 50 / 1);          % 2 √(θ I / τ), about z
            testCase.verifyEqual(testCase.metric("Bang-bang time 2√(θ/α)"), T, RelTol=1e-12);
            testCase.verifyEqual(testCase.metric("Slew time (within 0.1°)"), T, AbsTol=0.5);
            testCase.verifyEqual(testCase.metric("Thruster impulse"), T, RelTol=1e-6);
            testCase.App.View.Playback.seek(5);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function disturbanceSaturatesTheWheels(testCase)
            testCase.choosePreset("Hold: a disturbance saturates the wheels");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Wheels saturated"), 1);
            testCase.verifyEqual(testCase.metric("Time to saturation"), 6 / 0.01, RelTol=2e-3);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "saturated"));
            testCase.choosePreset("Hold with momentum dumping");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Wheels saturated"), 0);
            testCase.verifyGreaterThanOrEqual(testCase.metric("Momentum dumps"), 1);
        end

        function torquesAndBodyAreVisible(testCase)
            % The 0.01 N·m disturbance lay on the axes' top edge, hidden in
            % the frame; the lime body hid the green y axis.
            testCase.choosePreset("Hold: a disturbance saturates the wheels");
            testCase.pressRun();
            all = findall(testCase.App.Figure, Type="axes");
            ax = all(arrayfun(@(a) string(a.Title.String) == "Thruster and disturbance torques", all));
            testCase.verifyGreaterThan(ax.YLim(2), 0.01, "The disturbance is inside the plot.");
            testCase.verifyLessThan(ax.YLim(1), 0);
            body = findall(testCase.App.Figure, Type="patch", FaceAlpha=0.85);
            testCase.verifyNotEmpty(body);
            testCase.verifyEqual(body(1).FaceColor, testCase.App.Theme.Border);
        end

        function freeTumbleConserves(testCase)
            testCase.choosePreset("Free tumble: intermediate axis");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Energy drift (relative)"), 1e-9);
            testCase.verifyLessThan(testCase.metric("Momentum drift (relative)"), 1e-9);
            testCase.verifyGreaterThan(testCase.metric("Largest angle from start"), 150);
            testCase.verifyTrue(testCase.hasTab("Conservation"));
            testCase.verifyFalse(testCase.hasTab("Wheel momentum"));
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("Kd"));
        end

        function modesAreTheSecondOrderLoops(testCase)
            % About each axis: ωn = √(Kp/I), ζ = Kd / (2 √(Kp I)).
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            lin = plugin.linearization(p);
            L = dlab.core.Linearization.analyze(lin);
            I = [p.Ix p.Iy p.Iz];
            names = ["Roll (x) oscillation" "Pitch (y) oscillation" "Yaw (z) oscillation"];
            for k = 1:3
                mode = L.Modes(L.Modes.Mode == names(k), :);
                testCase.assertEqual(height(mode), 1, names(k));
                testCase.verifyEqual(mode.NaturalFrequency, sqrt(p.Kp / I(k)), RelTol=1e-6);
                testCase.verifyEqual(mode.DampingRatio, p.Kd / (2 * sqrt(p.Kp * I(k))), RelTol=1e-6);
            end
            % The frequency-response fields: F(x) = G(x, U0), torque enters as 1/I.
            x = [0.01; -0.02; 0.015; 0.001; 0.002; -0.003];
            testCase.verifyEqual(lin.F(x), lin.G(x, lin.U0), AbsTol=1e-15);
            B = dlab.physics.jacobian(@(u) lin.G(zeros(6, 1), u), lin.U0);
            testCase.verifyEqual(B, [zeros(3); diag(1 ./ I)], AbsTol=1e-9);
            testCase.verifyEqual(numel(lin.InputNames), numel(lin.U0));
            testCase.verifyEqual(numel(lin.OutputNames), numel(lin.H(x, lin.U0)));
        end

        function detumbleModesDampTheRates(testCase)
            testCase.choosePreset("Detumble");
            plugin = testCase.App.View.Plugin;
            p = testCase.App.View.params();
            L = dlab.core.Linearization.analyze(plugin.linearization(p));
            testCase.verifyEqual(sum(endsWith(L.Modes.Mode, "drift (neutral)")), 3);
            settling = L.Modes(endsWith(L.Modes.Mode, "settling"), :);
            testCase.verifyEqual(sort(settling.TimeConstant), sort([p.Ix; p.Iy; p.Iz] / p.Kd), RelTol=1e-6);
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Final rate"), 0.01);
            testCase.verifyGreaterThan(testCase.metric("Max wheel momentum"), 3);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; the mode choices fit their field
            % ("Detumble (rate damping)", "Slew: thrusters, bang-bang").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function bangBangSummaryIsClean(testCase)
            % My own one-axis references: the PD slew settles in 107.73 s with
            % 3.89 % overshoot; bang-bang takes 2√(θI/τ) = 17.7245 s. The
            % idle wheels read 0, not 6e−14; units only in the units column.
            testCase.choosePreset("90° yaw slew (PD)");
            testCase.pressRun();
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyEqual(M.Value(M.Quantity == "Slew time (within 0.1°)"), 107.73, RelTol=1e-4);
            testCase.verifyEqual(M.Value(M.Quantity == "Overshoot"), 3.891, RelTol=1e-3);
            testCase.choosePreset("Bang-bang slew (thrusters)");
            testCase.pressRun();
            S = testCase.App.View.Plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyEqual(S.Value(S.Quantity == "Max wheel momentum"), 0);
            testCase.verifyEqual(S.Value(S.Quantity == "Overshoot"), 0);
            testCase.verifyEqual(S.Display(S.Quantity == "Wheels saturated"), "no");
            testCase.verifyTrue(all(ismember(S.Units, ["" "s" "°" "%" "°/s" "N·m·s" "°/s²"])), strjoin(S.Units, ", "));
        end
    end
end
