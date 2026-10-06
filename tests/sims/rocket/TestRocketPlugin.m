classdef (TestTags = {'ui'}) TestRocketPlugin < matlab.unittest.TestCase
    %TESTROCKETPLUGIN The rocket ascent simulator in the app.

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
            testCase.App = DynamicsLab("rocket", Visible=false);
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

        function ax = axesTitled(testCase, prefix)
            all = findall(testCase.App.Figure, Type="axes");
            ax = all(arrayfun(@(a) startsWith(string(a.Title.String), prefix), all));
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
        end
    end

    methods (Test)
        function launcherReachesOrbit(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Orbit achieved"), 1);
            testCase.verifyGreaterThan(testCase.metric("Perigee"), 150);
            testCase.verifyGreaterThan(testCase.metric("Max-Q altitude"), 8);
            testCase.verifyLessThan(testCase.metric("Max-Q altitude"), 15);
            ideal = testCase.metric("Ideal Δv (Tsiolkovsky)");
            parts = testCase.metric("Achieved Δv") + testCase.metric("Gravity loss") + testCase.metric("Drag loss") + ...
                testCase.metric("Steering loss") + testCase.metric("Back-pressure loss");
            testCase.verifyEqual(parts, ideal, "RelTol", 1e-6, "The budget closes.");
            testCase.App.View.Playback.seek(150);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function soundingRocket(testCase)
            testCase.choosePreset("Sounding rocket (single stage, vertical)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Ideal Δv (Tsiolkovsky)"), 9.80665 * 260 * log(4), RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Orbit achieved"), 0);
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("targetApoapsis"));
        end

        function throttleBucket(testCase)
            testCase.pressRun();
            nominal = testCase.metric("Max-Q");
            testCase.choosePreset("Max-Q throttle bucket");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Max-Q"), 0.9 * nominal);
            % Its apoapsis is past the 2000 s limit: the coast still gets there
            % and circularizes (it used to stop at 163 × 237 km).
            testCase.verifyGreaterThan(testCase.metric("Circularization Δv"), 10);
            testCase.verifyEqual(testCase.metric("Perigee"), testCase.metric("Apogee"), RelTol=1e-5);
            % The plots mark the Summary's (climb) max-Q.
            marker = findobj(testCase.axesTitled("Dynamic pressure"), "Marker", "diamond");
            testCase.verifyEqual(marker.YData, testCase.metric("Max-Q"), RelTol=1e-12);
        end

        function maxQMarkersFollowTheClimb(testCase)
            testCase.choosePreset("Sounding rocket (single stage, vertical)");
            testCase.pressRun();
            marker = findobj(testCase.axesTitled("Dynamic pressure"), "Marker", "diamond");
            testCase.verifyEqual(marker.YData, testCase.metric("Max-Q"), "Not the 496 kPa of the fall.", ...
                RelTol=1e-12);
            marker = findobj(testCase.axesTitled("Altitude against downrange"), "Marker", "diamond");
            testCase.verifyEqual(marker.YData, testCase.metric("Max-Q altitude"), RelTol=1e-12);
            % Straight up and down: the impact shares the lift-off's label.
            labels = string(get(findobj(testCase.axesTitled("Altitude against downrange"), "Type", "text"), "String"));
            testCase.verifyTrue(any(contains(labels, "Stage 1 ignition, impact")), strjoin(labels, " | "));
            % It fell back: no conic through the impact point ("Perigee −6371 km").
            orbit = testCase.axesTitled("No orbit");
            testCase.verifyNumElements(orbit, 1);
            testCase.verifyEmpty(findobj(orbit, "LineStyle", "--"));
            % "Too shallow" dives under thrust: its max-Q is the dive's (the
            % climb's top gave 129 kPa against the plot's 1 MPa).
            testCase.choosePreset("Too shallow: drag-loss demo");
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyEqual(testCase.metric("Max-Q"), max(r.q) / 1e3, RelTol=1e-12);
        end

        function eventLabelsDoNotOverlap(testCase)
            % Stage 2 burnout and stage 3 ignition are 2 s apart, the apoapsis
            % and the circularization at the same moment: one label each.
            testCase.choosePreset("Heavy launcher, 3 stages (Saturn V-like, approximate)");
            testCase.pressRun();
            labels = string(get(findobj(testCase.axesTitled("Altitude against downrange"), "Type", "text"), "String"));
            testCase.verifyTrue(any(contains(labels, "Stage 2 burnout, stage 3 ignition")), strjoin(labels, " | "));
            testCase.verifyTrue(any(contains(labels, "Apoapsis, circularization burn")), strjoin(labels, " | "));
            testCase.verifyFalse(any(strip(labels) == "Stage 3 ignition"));
        end

        function oneStageIsNotEnough(testCase)
            testCase.App.View.Plugin.requestInputs(struct("stages", [22000 400000 8200 311 282 0]), "One stage");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Orbit achieved"), 0);
        end

        function inputsExplainThemselves(testCase)
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
            end
        end

        function soundingRocketMatchesAVerticalFlight(testCase)
            % Independent reference: a separate vertical flight with the ISA, integrated in scipy.
            % My own vertical flight (ISA, the same thrust, Cd and staging):
            % apogee 434.98 km, max-Q 130.7 kPa at 10.3 km in the climb, and
            % (59 992 N − 237 N of drag) / 400 kg = 15.233 g at burnout. The
            % max-Q of the whole flight was 496 kPa on the way down, an impact
            % gave a "perigee" of −6370 km, and the burnout sample, recomputed
            % after the stage was dropped (100 kg), read 60.9 g.
            testCase.choosePreset("Sounding rocket (single stage, vertical)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Highest altitude"), 434.98, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("Max-Q"), 130.7, RelTol=0.01);
            testCase.verifyLessThan(testCase.metric("Max-Q time"), 60);
            testCase.verifyEmpty(testCase.metric("Perigee"));
            testCase.verifyEqual(testCase.metric("Max acceleration under thrust"), 15.2334, RelTol=1e-4);
            S = testCase.App.View.Plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyTrue(all(ismember(S.Units, ["" "kPa" "km" "s" "g" "m/s" "%"])), strjoin(S.Units, ", "));
            testCase.verifyEqual(S.Display(S.Quantity == "Orbit achieved"), "no");
        end
    end
end
