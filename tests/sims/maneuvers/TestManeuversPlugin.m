classdef (TestTags = {'ui'}) TestManeuversPlugin < matlab.unittest.TestCase
    %TESTMANEUVERSPLUGIN The orbital maneuvers simulator in the app.

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
            testCase.App = DynamicsLab("maneuvers", Visible=false);
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
        function hohmannToGeo(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Total Δv"), 3.8952, AbsTol=5e-4);
            testCase.verifyEqual(testCase.metric("Transfer time"), 5.27, AbsTol=0.005);
            testCase.verifyLessThan(abs(testCase.metric("Final a error (relative)")), 1e-6);
            testCase.verifyLessThan(testCase.metric("Bi-elliptic saving"), 0, "Hohmann is cheaper to GEO.");
            testCase.App.View.Playback.seek(3 * 3600);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function combinedPlaneChange(testCase)
            testCase.choosePreset("LEO to GEO with plane change (from Cape Canaveral)");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Total Δv"), 4.4);
            testCase.verifyGreaterThan(testCase.metric("Combined saving"), 1);
            testCase.verifyLessThan(abs(testCase.metric("Final inclination error")), 1e-5);
        end

        function biellipticWins(testCase)
            testCase.choosePreset("Bi-elliptic beats Hohmann (r₂ = 20 r₁)");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Bi-elliptic saving"), 0);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("altB"));
            testCase.verifyFalse(panel.isRowShown("phaseAngle"));
        end

        function phasingAndCustom(testCase)
            testCase.choosePreset("Phasing: catch up 30°");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Rendezvous miss"), 1);
            testCase.App.View.Plugin.requestInputs(struct("maneuver", "custom"), "Custom");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Total Δv"), 1, AbsTol=1e-12);
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("burns"));
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Hohmann with plane change", "Phasing (rendezvous)").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function noBiellipticInsideTheTarget(testCase)
            % The lunar transfer's intermediate apoapsis (100 000 km) is inside
            % the target (384 400 km): there is no bi-elliptic transfer, so no
            % "saving" (it read 0) and no bar equal to the Hohmann's.
            testCase.choosePreset("Lunar-distance transfer");
            testCase.pressRun();
            testCase.verifyEmpty(testCase.metric("Bi-elliptic saving"));
            testCase.verifyTrue(isnan(testCase.App.View.Result.plan.alternatives.bielliptic));
            S = testCase.App.View.Plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyTrue(all(ismember(S.Units, ["" "km/s" "h" "km" "°"])), strjoin(S.Units, ", "));
        end
    end
end
