classdef (TestTags = {'ui'}) TestPendulumPlugin < matlab.unittest.TestCase
    %TESTPENDULUMPLUGIN Pendulum in the shell: golden results and the
    %   behaviours the original app's UI tests covered (test_pendulum_ui.m).

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
            testCase.App = DynamicsLab("pendulum", Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function pressRun(testCase)
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.App.View.Playback.pause();
            testCase.App.View.Playback.seek(testCase.App.View.Playback.StartTime);   % Run auto-plays; start from a known frame
            testCase.assertEmpty(testCase.App.LastError);
        end

        function set(testCase, name, value)
            field = findall(testCase.App.Figure, Tag="dlab.param." + name);
            field.Value = value;
            field.ValueChangedFcn(field, []);
        end

        function ax = axesTitled(testCase, title)
            all = findall(testCase.App.Figure, Type="axes");
            ax = all(arrayfun(@(a) string(a.Title.String) == title, all));
            testCase.assertNumElements(ax, 1, title);
        end
    end

    methods (Test)
        function defaultRunMatchesReferenceResults(testCase)
            % docs/test-results.md of the original repository.
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyNumElements(r.t, 751);
            testCase.verifyEqual(r.t(end), 15);
            testCase.verifyEqual(r.thetaDeg(end), -11.796865, AbsTol=5e-7);
            testCase.verifyEqual(r.E(end), 0.290997, AbsTol=5e-7);
            testCase.verifyEqual(testCase.App.View.Playback.EndTime, 15);
        end

        function exportMatchesLegacySampleOutput(testCase)
            % docs/sample-output.csv rows at t = 0 and t = 3 s.
            testCase.pressRun();
            T = dlab.sims.pendulum.PendulumPlugin().exportTable(testCase.App.View.Result);
            testCase.verifyEqual(T.Properties.VariableUnits, {'s' 'deg' 'rad/s' 'J' 'J' 'J'});
            row0 = T{T.time == 0, :};
            row3 = T{abs(T.time - 3) < 1e-12, :};
            testCase.verifyEqual(row0, [0 30 0 0 1.314291 1.314291], AbsTol=5e-7);
            testCase.verifyEqual(row3, [3 -25.339520 -0.231593 0.026818 0.943844 0.970662], AbsTol=5e-7);
        end

        function plotsKeepLabelsAcrossRuns(testCase)
            titles = ["Angular displacement" "Angular velocity" "Phase portrait (θ vs ω)" "Mechanical energy"];
            before = arrayfun(@(t) labelsOf(testCase.axesTitled(t)), titles, UniformOutput=false);
            testCase.pressRun();
            testCase.pressRun();
            after = arrayfun(@(t) labelsOf(testCase.axesTitled(t)), titles, UniformOutput=false);
            testCase.verifyEqual(after, before);
            testCase.verifyEqual(string(testCase.axesTitled("Angular displacement").XGrid), "on");
        end

        function phasePortraitHasStartAndEndLegend(testCase)
            testCase.pressRun();
            lgd = testCase.axesTitled("Phase portrait (θ vs ω)").Legend;
            testCase.verifyEqual(string(lgd.String), ["Start" "End"]);
            testCase.verifyNumElements(lgd.PlotChildren, 2);
        end

        function animationFitsTheSwingAndInterpolates(testCase)
            testCase.pressRun();
            ax = testCase.axesTitled("Pendulum");
            reach = 1 * (1 + 0.06);                            % L + bob radius
            testCase.verifyLessThanOrEqual([ax.XLim(1) ax.YLim(1)], -reach * [1 1]);
            testCase.verifyGreaterThanOrEqual([ax.XLim(2) ax.YLim(2)], reach * [1 1]);

            % Two samples either side of the top: halfway must be exactly
            % upright with the rod at full length (legacy interpolation test).
            plugin = testCase.App.View.Plugin;
            theta = deg2rad([150; 210]);
            fake = struct("t", [0; 1], "theta", theta, "thetaDeg", rad2deg(theta), ...
                "omega", [0; 0], "KE", [0; 0], "PE", [0; 0], "E", [0; 0], ...
                "bx", sin(theta), "by", -cos(theta));
            params = plugin.defaultParams();
            plugin.showResult(fake, params);
            plugin.drawFrame(0.5);
            rod = findall(ax, Type="line", LineWidth=2.5);
            testCase.verifyEqual([rod.XData(end) rod.YData(end)], [0 1], AbsTol=1e-12);
            angle = findall(ax, Type="text", FontName=dlab.ui.Theme.MonoFont, FontWeight="bold");
            testCase.assertNumElements(angle, 1);
            testCase.verifyEqual(string(angle.String), "θ = 180.0°");
        end

        function speedPersistsAcrossRuns(testCase)
            speed = findall(testCase.App.Figure, Tag="dlab.playback.speed");
            speed.Value = 0.25;
            speed.ValueChangedFcn(speed, []);
            testCase.pressRun();
            testCase.verifyEqual(testCase.App.View.Playback.Speed, 0.25);
        end

        function editingAfterARunMarksResultsStale(testCase)
            % Regression: a plugin with no display-only inputs once failed here.
            testCase.pressRun();
            testCase.set("L", 2);
            testCase.verifyEmpty(testCase.App.LastError);
            testCase.verifyEqual(string(findall(testCase.App.Figure, Tag="dlab.stale").Visible), "on");
            testCase.set("L", 1);
            testCase.verifyEqual(string(findall(testCase.App.Figure, Tag="dlab.stale").Visible), "off");
        end

        function summaryReportsEnergy(testCase)
            testCase.pressRun();
            data = findall(testCase.App.Figure, Tag="dlab.summary").Data;
            testCase.verifyEqual(data.Value(data.Quantity == "Peak angle"), "30");
            testCase.verifyEqual(data.Value(data.Quantity == "Samples"), "751");
            testCase.verifyEqual(data.Value(data.Quantity == "Final energy"), "0.290997");
        end

        function invalidEngineInputIsReported(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            params = plugin.defaultParams();
            params.L = -1;      % bypasses the panel limits on purpose
            testCase.verifyError(@() plugin.solve(params), "dlab:invalidParameter");
        end

        function smallAngleModelMatchesSmallSwings(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            small = summaryOf(plugin, struct("theta0", 5, "b", 0));
            testCase.verifyEqual(small("Small-angle period"), 2 * pi * sqrt(1 / 9.81), RelTol=1e-12);
            testCase.verifyLessThan(small("Max deviation from small-angle model"), 0.2);
            testCase.verifyLessThan(small("Small-angle period error"), 0.1);
            large = summaryOf(plugin, struct("theta0", 150, "b", 0));
            testCase.verifyGreaterThan(large("Small-angle period error"), 40);
            testCase.verifyGreaterThan(large("Max deviation from small-angle model"), 90);
        end

        function exactPeriodMatchesTheMeasuredOne(testCase)
            % Independent reference: the exact period 4 sqrt(L/g) K(sin²(θ₀/2)).
            % T = 4 √(L/g) K(sin²(θ₀/2)) for an undamped swing from rest.
            plugin = dlab.sims.pendulum.PendulumPlugin();
            for theta0 = [10 90 150]
                rows = summaryOf(plugin, struct("theta0", theta0, "b", 0, "dt", 0.005));
                testCase.verifyEqual(rows("Exact period (undamped)"), rows("Period (measured)"), "RelTol", 1e-3, ...
                    sprintf("%d°", theta0));
            end
            % Damped or looping runs have no exact row.
            testCase.verifyFalse(isKey(summaryOf(plugin, struct("b", 0.1)), "Exact period (undamped)"));
            testCase.verifyFalse(isKey(summaryOf(plugin, struct("theta0", 0, "omega0", 7, "b", 0)), ...
                "Exact period (undamped)"));
        end

        function smallAngleOverlayIsADisplaySetting(testCase)
            testCase.pressRun();
            dashed = findall(testCase.axesTitled("Angular displacement"), Type="line", LineStyle="--");
            testCase.assertNumElements(dashed, 1);
            testCase.verifyNumElements(dashed.XData, 751);
            testCase.set("showLinear", false);
            testCase.verifyTrue(all(isnan(dashed.XData)));
            testCase.verifyEqual(string(findall(testCase.App.Figure, Tag="dlab.stale").Visible), "off");
            testCase.set("showLinear", true);
            testCase.verifyNumElements(dashed.XData, 751);
        end

        function doublePendulumHasItsOwnTabs(testCase)
            preset = findall(testCase.App.Figure, Tag="dlab.preset");
            preset.Value = "builtin:Double: butterfly effect";
            preset.ValueChangedFcn(preset, []);
            testCase.pressRun();
            titles = string({findall(testCase.App.Figure, Type="uitab").Title});
            testCase.verifyTrue(all(ismember(["Angles" "Divergence" "Poincaré section"], titles)));
            testCase.verifyFalse(ismember("Angle & velocity", titles));
            r = testCase.App.View.Result;
            testCase.verifyEqual(r.model, "double");
            testCase.verifyNotEmpty(r.twin);
            rows = dictionary(testCase.App.View.Plugin.summaryTable(r).Quantity, ...
                testCase.App.View.Plugin.summaryTable(r).Value);
            testCase.verifyEqual(rows("Diverged"), 1);
            testCase.verifyLessThan(rows("Divergence time"), 20);
            testCase.verifyLessThan(rows("Energy drift (relative)"), 1e-7);

            % Both rods and the twin are drawn; the lower rod hangs from the upper bob.
            ax = testCase.axesTitled("Pendulum");
            rods = [findall(ax, Type="line", LineWidth=2.5) findall(ax, Type="line", LineWidth=2.4)];
            testCase.verifyEqual(string({rods.Visible}), ["on" "on"]);
            testCase.verifyEqual(rods(1).XData(end), rods(2).XData(1), AbsTol=1e-12);
            testCase.verifyGreaterThanOrEqual(ax.XLim(2), 2, "Room for both rods.");

            % Back to a single pendulum: its tabs return.
            testCase.set("model", "single");
            testCase.pressRun();
            titles = string({findall(testCase.App.Figure, Type="uitab").Title});
            testCase.verifyTrue(ismember("Angle & velocity", titles));
            testCase.verifyFalse(ismember("Divergence", titles));
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function doublePendulumModesAreInAndAntiPhase(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            params = plugin.presetParams("Double: gentle (normal modes)");
            L = dlab.core.Linearization.analyze(plugin.linearization(params));
            names = string(L.Modes.Mode);
            testCase.verifyTrue(any(names == "In-phase swing") && any(names == "Anti-phase swing"));
            periods = L.Modes.Period(names == "In-phase swing");
            testCase.verifyEqual(periods(1), 2 * pi / sqrt(9.81 * (2 - sqrt(2))), RelTol=1e-5);
            rows = summaryOf(plugin, struct("model", "double", "theta0", 5, "theta20", 5, "b", 0, "twin", false));
            testCase.verifyEqual(rows("In-phase period (small-angle)"), periods(1), RelTol=1e-5);
            testCase.verifyEqual(rows("Anti-phase period (small-angle)"), 2 * pi / sqrt(9.81 * (2 + sqrt(2))), RelTol=1e-9);
            testCase.verifyLessThan(rows("Max deviation from small-angle model"), 0.5);
        end

        function poincarePointsFeedSweeps(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            result = plugin.solve(plugin.presetParams("Double: chaotic"));
            D = plugin.distributions(result);
            testCase.verifyEqual(D.Quantity, ["Poincaré θ₂"; "Poincaré ω₂"]);
            testCase.verifyEqual(numel(D.Values{2}), size(result.poincare, 1));
            single = plugin.solve(plugin.defaultParams());
            testCase.verifyEqual(height(plugin.distributions(single)), 0);
            T = plugin.exportTable(result);
            testCase.verifyEqual(numel(T.Properties.VariableUnits), width(T));
        end

        function overTheTopPresetRotates(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            r = plugin.solve(plugin.presetParams("Over the top"));
            testCase.verifyGreaterThan(max(r.thetaDeg), 360, "Starting at 7 rad/s should loop over the top.");
            % The Summary says so, and does not show a period it cannot measure.
            T = plugin.summaryTable(r);
            passes = T.Value(T.Quantity == "Passes over the top");
            testCase.verifyEqual(passes, 2, "863° from 0°: through 180° and 540°.");
            testCase.verifyEqual(T.Display(T.Quantity == "Period (measured)"), "— (no complete swings)");
            M = plugin.metrics(r);
            testCase.verifyFalse(ismember("Period (measured)", M.Quantity), "No period to sweep or check.");
        end

        function ceilingOnlyWhenTheBobStaysBelowThePivot(testCase)
            % A pendulum that swings above the pivot turns on an axle: a
            % ceiling there would cut through its rod.
            ceiling = @() findobj(testCase.axesTitled("Pendulum"), Type="patch", FaceColor=testCase.App.Theme.Surface);
            testCase.pressRun();                                   % 30°: below the pivot throughout
            testCase.verifyEqual(string(ceiling().Visible), "on");
            view = testCase.App.View;
            view.applySetup(struct("preset", "Over the top"));
            testCase.pressRun();
            testCase.verifyEqual(string(ceiling().Visible), "off");
        end
    end
end

function labels = labelsOf(ax)
labels = string({ax.Title.String, ax.XLabel.String, ax.YLabel.String});
end

function rows = summaryOf(plugin, values)
% Summary of one run as a Quantity → Value dictionary.
params = plugin.defaultParams();
for name = string(fieldnames(values))'
    params.(name) = values.(name);
end
T = plugin.summaryTable(plugin.solve(params));
rows = dictionary(T.Quantity, T.Value);
end
