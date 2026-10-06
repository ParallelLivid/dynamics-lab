classdef (TestTags = {'ui'}) TestHeatPlugin < matlab.unittest.TestCase
    %TESTHEATPLUGIN The heat-conduction simulator in the app.

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
            testCase.App = DynamicsLab("heat", Visible=false);
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
        function coolingBarMatchesTheExactSolution(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Max error vs exact"), 0.01);
            testCase.verifyEqual(testCase.metric("Stable"), 1);
            testCase.verifyEqual(testCase.metric("Mesh Fourier number r"), 401 / (8960 * 385) * 1 / 0.02^2, RelTol=1e-9);
            dashed = findall(testCase.App.Figure, Type="line", LineStyle="--", DisplayName="Exact");
            testCase.verifyNotEmpty(dashed);
        end

        function explicitBeyondTheLimitIsFlagged(testCase)
            testCase.choosePreset("Explicit beyond the limit (r = 0.55)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Stable"), 0);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifySubstring(string(status.Text), "unstable");
            testCase.choosePreset("Explicit at the stability limit (r = 0.5)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Stable"), 1);
            r = testCase.metric("Mesh Fourier number r");      % the step is shortened to land on the end time
            testCase.verifyLessThanOrEqual(r, 0.5);
            testCase.verifyGreaterThan(r, 0.49);
        end

        function materialsFillInTheirProperties(testCase)
            field = findall(testCase.App.Figure, Tag="dlab.param.material");
            field.Value = "brick";
            field.ValueChangedFcn(field, []);
            params = testCase.App.View.params();
            testCase.verifyEqual([params.k params.rho params.c], [0.7 1800 840]);
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("k"));
            field.Value = "custom";
            field.ValueChangedFcn(field, []);
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("k"));
        end

        function wallDampsTheDailyCycle(testCase)
            testCase.choosePreset("Daily temperature cycle in a brick wall");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Surface temperature swing"), 20, AbsTol=0.1);
            testCase.verifyEqual(testCase.metric("Swing ratio (middle / surface)"), 0.27, AbsTol=0.05);
        end

        function insulatedRodKeepsItsHeat(testCase)
            testCase.choosePreset("Hot spot spreading (insulated ends)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Energy balance error"), 1e-6);
            r = testCase.App.View.Result;
            testCase.verifyLessThan(max(r.T(end, :)) - min(r.T(end, :)), 0.5 * 80, "The spot spreads out.");
            % No cycling end: no swing rows (they read 0.28 °C and a ratio of 1).
            testCase.verifyEmpty(testCase.metric("Swing ratio (middle / surface)"));
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Fixed temper…", "Heat flux (0 = …", "Implicit (backw…").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 14, spec.Name);
                end
            end
        end

        function wallSwingMatchesThePeriodicSolution(testCase)
            % Independent reference: the exact periodic solution of the slab.
            % The exact periodic slab (T̂'' = iω/α T̂, 10 °C at the outer face,
            % convection inside) gives a mid-wall swing of 0.2678 of the face's.
            testCase.choosePreset("Daily temperature cycle in a brick wall");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Swing ratio (middle / surface)"), 0.267826, RelTol=5e-3);
            testCase.verifyLessThan(testCase.metric("Energy balance error"), 1e-8);
        end
    end
end
