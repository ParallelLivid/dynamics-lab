classdef (TestTags = {'ui'}) TestPlatePlugin < matlab.unittest.TestCase
    %TESTPLATEPLUGIN The 2-D plate heat-conduction simulator in the app.

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
            testCase.App = DynamicsLab("plate", Plugins={@dlab.sims.plate.PlatePlugin}, Visible=false);
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
        function hotSpotSpreads(testCase)
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyEqual(testCase.metric("Stable"), 1);
            testCase.verifyLessThan(testCase.metric("Energy balance error"), 1e-6);
            % A Gaussian spot's peak falls as w² / (w² + 4αt) in 2-D (the plate's edges barely matter yet).
            [w, alpha] = deal(0.15 * 0.2, 50 / (7850 * 490));
            testCase.verifyEqual(testCase.metric("Final maximum temperature") - 20, 80 * w^2 / (w^2 + 4 * alpha * 60), ...
                RelTol=0.03);
            testCase.verifyGreaterThan(testCase.metric("Probe temperature"), 20.5, "Heat reached the probe.");
            testCase.verifyEqual(testCase.metric("Final mean temperature"), r.meanT(end), RelTol=1e-12);
        end

        function separableModeMatchesTheExactSolution(testCase)
            testCase.choosePreset("Separable mode decay");
            testCase.pressRun();
            testCase.verifyLessThan(abs(testCase.metric("Decay-rate error")), 0.5);
            testCase.verifyLessThan(testCase.metric("Max error vs exact"), 0.05);
            steel = 50 / (7850 * 490);
            testCase.verifyEqual(testCase.metric("Exact decay rate"), steel * pi^2 * 2 / 0.2^2, RelTol=1e-12);
        end

        function explicitLimitIsAQuarter(testCase)
            testCase.choosePreset("Explicit at the limit (r = 1/4)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Stable"), 1);
            sumR = testCase.metric("r_x + r_y");     % the step is shortened to land on the end time
            testCase.verifyLessThanOrEqual(sumR, 0.5);
            testCase.verifyGreaterThan(sumR, 0.49);
            testCase.choosePreset("Explicit past the limit (r = 0.3)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Stable"), 0);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifySubstring(string(status.Text), "unstable");
            testCase.verifyEqual(testCase.App.View.Result.termination, 'unstable');
        end

        function adiTakesLargeSteps(testCase)
            testCase.choosePreset("ADI with a large step (r = 5)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Stable"), 1);
            testCase.verifyEqual(testCase.metric("Mesh Fourier number r"), 5, RelTol=1e-3);
            testCase.verifyGreaterThan(testCase.metric("Time step"), 15 * testCase.metric("Largest stable explicit step"));
        end

        function finMatchesTheFinEquation(testCase)
            % A thin plate cooled at its faces' edges behaves as a 1-D fin:
            % θ_tip / θ_base = 1 / (cosh mL + (h / mk) sinh mL),  m² = 2h / (k b).
            testCase.choosePreset("Cooling fin edge (convection)");
            testCase.pressRun();
            [h, k, b, L] = deal(200, 237, 0.04, 0.2);
            m = sqrt(2 * h / (k * b));
            tip = 20 + 80 / (cosh(m * L) + h / (m * k) * sinh(m * L));
            testCase.verifyEqual(testCase.metric("Probe temperature") - 20, tip - 20, RelTol=0.01);
            testCase.verifyLessThan(testCase.metric("Time to steady state (99 %)"), 900);
            testCase.verifyLessThan(testCase.metric("Energy balance error"), 1e-6);
        end

        function heaterWarmsAnInsulatedPlate(testCase)
            testCase.choosePreset("Insulated plate with heater");
            testCase.pressRun();
            % A Gaussian spot of peak q and width w delivers q π w² d per second.
            [q, w, d, t] = deal(1e7, 0.1 * 0.2, 0.005, 300);
            generated = testCase.metric("Heat generated");
            testCase.verifyEqual(generated, q * pi * w^2 * d * t, RelTol=1e-3);
            capacity = 2700 * 897 * d * 0.2^2;
            testCase.verifyEqual(testCase.metric("Final mean temperature") - 20, generated / capacity, RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Heat in through the edges"), 0);
        end

        function materialsFillInTheirProperties(testCase)
            field = findall(testCase.App.Figure, Tag="dlab.param.material");
            field.Value = "copper";
            field.ValueChangedFcn(field, []);
            params = testCase.App.View.params();
            testCase.verifyEqual([params.k params.rho params.c], [401 8960 385]);
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("k"));
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("leftH"));
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("leftT"));
        end

        function everyTabIsDrawnAndTheViewSwitches(testCase)
            testCase.pressRun();
            fig = testCase.App.Figure;
            testCase.verifyGreaterThanOrEqual(numel(findall(fig, Type="surface")), 7, ...
                "Six snapshot tiles and the animated plate.");
            testCase.verifyNotEmpty(findall(fig, Type="contour"));
            testCase.App.View.Playback.seek(testCase.App.View.Result.t(end) / 2);
            dd = findall(fig, Tag="dlab.plate.view");
            dd.Value = "Surface";
            dd.ValueChangedFcn(dd, []);
            dd.Value = "Heatmap";
            dd.ValueChangedFcn(dd, []);
            testCase.verifyEmpty(testCase.App.LastError);
            testCase.choosePreset("Separable mode decay");
            testCase.pressRun();
            testCase.verifyNotEmpty(findall(fig, Type="line", DisplayName="Exact"));
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Heat flux (0 = …", "ADI (Peaceman–…", "Stability numb…").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end
    end
end
