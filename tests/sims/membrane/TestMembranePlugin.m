classdef (TestTags = {'ui'}) TestMembranePlugin < matlab.unittest.TestCase
    %TESTMEMBRANEPLUGIN The vibrating membrane simulator in the app.

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
            testCase.App = DynamicsLab("membrane", Plugins={@dlab.sims.membrane.MembranePlugin}, Visible=false);
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
        function squareDrumIsInharmonic(testCase)
            % 0.5 m square, T = 2000 N/m, ρ = 0.25 kg/m²: f11 = (c/2) √2 / a.
            testCase.pressRun();
            c = sqrt(2000 / 0.25);
            testCase.verifyEqual(testCase.metric("Fundamental frequency"), c / 2 * sqrt(2) / 0.5, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("f2 / f1"), sqrt(5 / 2), RelTol=2e-3);
            testCase.verifyEqual(testCase.metric("Wave speed"), c, RelTol=1e-12);
            testCase.verifyEmpty(testCase.metric("Energy in axisymmetric modes"), "A rectangle has none.");
        end

        function centreStrikeRingsOnlyAxisymmetricModes(testCase)
            testCase.choosePreset("Circular drum struck at the centre");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Energy in axisymmetric modes"), 100, AbsTol=1e-9);
            testCase.verifyEqual(testCase.metric("f2 / f1"), 3.831706 / 2.404826, RelTol=2e-3);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("R"));
            testCase.verifyFalse(panel.isRowShown("a"));

            testCase.choosePreset("Circular drum struck off-centre");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Energy in axisymmetric modes"), 50);
        end

        function singleModeRingsAtItsBesselZero(testCase)
            testCase.choosePreset("Single mode (2,1) on the circular drum");
            testCase.pressRun();
            f21 = sqrt(2000 / 0.25) * 5.135622 / (2 * pi * 0.33);
            testCase.verifyEqual(testCase.metric("Dominant mode frequency"), f21, RelTol=5e-3);
            testCase.verifyEqual(testCase.metric("Energy remaining at the end"), 100, RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Energy captured by the modes kept"), 100, RelTol=1e-9);
        end

        function dampedStrikeDiesAway(testCase)
            testCase.choosePreset("Damped strike");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Energy remaining at the end"), 5);
        end

        function everyTabIsDrawn(testCase)
            testCase.choosePreset("Rectangle 2:1");
            testCase.pressRun();
            fig = testCase.App.Figure;
            testCase.verifyGreaterThanOrEqual(numel(findall(fig, Type="surface")), 10, ...
                "Nine mode tiles and the animated surface.");
            testCase.verifyEmpty(findall(fig, Type="contour"), "Nodal lines are drawn exactly.");
            testCase.verifyNotEmpty(findall(fig, Type="bar"), "Mode content and errors.");
            testCase.App.View.Playback.seek(testCase.App.View.Result.t(end) / 2);
            dd = findall(fig, Tag="dlab.membrane.view");
            dd.Value = "Heatmap";
            dd.ValueChangedFcn(dd, []);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Strike (initial …").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function nodalLinesAreExact(testCase)
            % Contours of the grid shape broke where nodal lines cross (a gap
            % at the centre of (1,1), jogs in (1,2) and (2,2)). Now: the
            % (0,2) mode's nodal circle at r = R j01 / j02, and diameters
            % straight through the centre.
            testCase.choosePreset("Circular drum struck off-centre");
            testCase.pressRun();
            r = testCase.App.View.Result;
            lines = findall(testCase.App.Figure, Type="line", LineWidth=1.4);
            radii = [];
            for h = lines'
                x = h.XData;
                y = h.YData;
                ok = isfinite(x);
                radii = [radii, hypot(x(ok) - (max(x(ok)) + min(x(ok))) / 2, y(ok) - (max(y(ok)) + min(y(ok))) / 2)]; %#ok<AGROW>
            end
            testCase.verifyTrue(any(abs(radii - 0.33 * 2.404826 / 5.520078) < 1e-6), ...
                "The (0,2) nodal circle.");
            testCase.verifyEqual(r.labels(find(r.distinct, 1), :), [0 1]);
            % A single mode excites no axisymmetric mode: 0, not 3.7e-30 %.
            testCase.choosePreset("Single mode (2,1) on the circular drum");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Energy in axisymmetric modes"), 0);
        end
    end
end
