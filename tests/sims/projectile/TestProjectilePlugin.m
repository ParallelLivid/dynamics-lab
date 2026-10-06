classdef (TestTags = {'ui'}) TestProjectilePlugin < matlab.unittest.TestCase
    %TESTPROJECTILEPLUGIN Projectile in the shell: README sample outputs and
    %   comparing runs (the shell's "Keep previous runs").

    properties
        App
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(repoRoot, "tests", "fixtures")));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (TestMethodSetup)
        function launch(testCase)
            testCase.App = DynamicsLab("projectile", Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function ax = axesTitled(testCase, name)
            ax = findall(testCase.App.Figure, Type="axes");
            ax = ax(arrayfun(@(a) string(a.Title.String) == name, ax));
            testCase.assertNumElements(ax, 1, name);
        end

        function c = find(testCase, tag)
            c = findall(testCase.App.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end

        function set(testCase, name, value)
            field = testCase.find("dlab.param." + name);
            field.Value = value;
            field.ValueChangedFcn(field, []);
        end

        function pressRun(testCase)
            b = testCase.find("dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.App.View.Playback.pause();
            testCase.App.View.Playback.seek(testCase.App.View.Playback.StartTime);   % Run auto-plays; start from a known frame
        end

        function keep(testCase, value)
            box = testCase.find("dlab.keepRuns");
            box.Value = value;
            box.ValueChangedFcn(box, []);
        end

        function value = summary(testCase, quantity)
            data = testCase.find("dlab.summary").Data;
            value = str2double(data.Value(data.Quantity == quantity));
        end

        function preset(testCase, name)
            box = findall(testCase.App.Figure, Tag="dlab.preset");
            box.Value = "builtin:" + name;
            box.ValueChangedFcn(box, []);
        end

        function text = readout(testCase)
            trajectory = testCase.axesTitled("Trajectory");
            label = findall(trajectory, Type="text", Units="normalized");
            label = label(arrayfun(@(h) startsWith(join(string(h.String), newline), "t = "), label));
            testCase.assertNumElements(label, 1);
            text = join(string(label.String), newline);
        end

    end

    methods (Test)
        function pointMassMatchesReadme(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.summary("Flight time"), 7.208, AbsTol=5e-4);
            testCase.verifyEqual(testCase.summary("Range"), 254.84, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Maximum height"), 63.71, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Impact speed"), 50.00, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Impact angle"), -45.00, AbsTol=5e-3);
        end

        function sphereWithDragMatchesReadme(testCase)
            testCase.set("model", "sphere");
            testCase.set("theta", 60);
            testCase.pressRun();
            testCase.verifyEqual(testCase.summary("Flight time"), 7.882, AbsTol=5e-4);
            testCase.verifyEqual(testCase.summary("Range"), 152.29, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Maximum height"), 76.32, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Impact speed"), 38.17, AbsTol=5e-3);
            testCase.verifyEqual(testCase.summary("Impact angle"), -66.84, AbsTol=5e-3);
        end

        function dragInputsAppearOnlyForTheSphere(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("Cd"));
            testCase.set("model", "sphere");
            testCase.verifyTrue(panel.isRowShown("Cd"));
            testCase.verifyTrue(panel.isRowShown("radius"));
            testCase.verifyFalse(panel.isRowShown("area"));
            testCase.set("geometry", "area");
            testCase.verifyFalse(panel.isRowShown("radius"));
            testCase.verifyTrue(panel.isRowShown("area"));
        end

        function comparisonAccumulatesAndSurvivesRebuilds(testCase)
            testCase.keep(true);
            testCase.pressRun();
            testCase.set("theta", 60);
            testCase.pressRun();
            testCase.verifyNumElements(testCase.App.View.Runs, 1);
            runs = testCase.find("dlab.runs");
            testCase.verifyEqual(size(runs.Data, 1), 2);
            testCase.verifyEqual(string(runs.Data{1, 2}), "Launch angle = 45 deg");
            range = string(runs.ColumnName) == "Range (m)";
            testCase.verifyEqual([runs.Data{:, range}], [254.84 220.7], AbsTol=0.01);

            testCase.App.toggleTheme();                 % view rebuilt from the session
            testCase.set("theta", 30);
            testCase.pressRun();
            testCase.verifyNumElements(testCase.App.View.Runs, 2);
            testCase.verifyEqual(testCase.App.View.Playback.EndTime, ...
                testCase.App.View.Result.impactTime, "Playback follows the latest run.");
            trajectory = testCase.axesTitled("Trajectory");
            testCase.verifyNumElements(findall(trajectory, Tag="dlab.overlay"), 2);
            testCase.verifyGreaterThanOrEqual(trajectory.YLim(2), 95.5, "Room for the 60° arc.");

            testCase.keep(false);
            testCase.pressRun();
            testCase.verifyEmpty(testCase.App.View.Runs);
        end

        function oldScenariosWithCompareStillLoad(testCase)
            file = fullfile(tempdir, "projectile-v1.json");
            testCase.addTeardown(@() delete(file));
            s = struct("format", "dynamicslab-scenario", "formatVersion", 1, "simulator", "projectile", ...
                "schemaVersion", 1, "preset", "Custom", "params", struct("theta", 30, "compare", true));
            writelines(jsonencode(s), file);
            testCase.App.View.loadScenario(file);
            testCase.verifyEqual(testCase.App.View.params().theta, 30);
            testCase.verifyFalse(contains(testCase.find("dlab.status").Text, "compare"), ...
                "The retired input is dropped quietly.");
        end

        function rerunsDoNotLeaveStaleMarkers(testCase)
            % Hidden-handle graphics survive cla; re-runs must not pile them up.
            testCase.keep(true);
            for k = 1:3
                testCase.pressRun();
            end
            trajectory = testCase.axesTitled("Trajectory");
            markers = findall(trajectory, Type="line", Marker="o");
            testCase.verifyNumElements(markers, 1);
            testCase.verifyNumElements(findall(trajectory, Type="constantline"), 1);
        end

        function groundLaunchWithoutLiftHasOneSample(testCase)
            testCase.set("theta", 0);
            testCase.pressRun();
            testCase.verifyEmpty(testCase.App.LastError);
            testCase.verifyEqual(testCase.summary("Flight time"), 0);
        end

        function optimalAngleIsFoundAndCanBeUsed(testCase)
            testCase.set("model", "sphere");
            testCase.set("theta", 60);
            testCase.pressRun();
            best = testCase.summary("Optimal angle");
            testCase.verifyEqual(best, 42.3, AbsTol=0.1);
            testCase.verifyGreaterThan(testCase.summary("Range at optimal angle"), 152.29);
            testCase.verifyGreaterThan(testCase.summary("Range lost vs optimal"), 0);
            trajectory = testCase.axesTitled("Trajectory");
            testCase.verifyNumElements(findall(trajectory, Type="line", LineStyle=":"), 1, "The best arc is drawn.");

            button = testCase.find("dlab.projectile.useOptimal");
            testCase.verifyEqual(string(button.Enable), "on");
            button.ButtonPushedFcn(button, []);
            testCase.verifyEqual(testCase.App.View.params().theta, round(best, 2), AbsTol=0.006);
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "on");
            undo = testCase.find("dlab.undo");
            undo.ButtonPushedFcn(undo, []);
            testCase.verifyEqual(testCase.App.View.params().theta, 60);
        end

        function optimalSearchCanBeTurnedOff(testCase)
            testCase.set("findOptimal", false);
            testCase.pressRun();
            data = testCase.find("dlab.summary").Data;
            testCase.verifyFalse(any(data.Quantity == "Optimal angle"));
            testCase.verifyEqual(string(testCase.find("dlab.projectile.useOptimal").Enable), "off");
        end

        function optimalSearchIsReusedWhileOnlyTheAngleChanges(testCase)
            % A sweep over the angle (or trying angles) searches once. The
            % search reports one fraction per trial angle; the trajectory
            % itself reports NaN (its end time is unknown).
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = plugin.defaultParams();
            p.model = "sphere";
            recorder = dlabtest.ProgressRecorder();
            plugin.ProgressFcn = @(fraction) recorder.report(fraction);
            trials = @() nnz(~isnan(recorder.Fractions));
            first = plugin.solve(p);
            testCase.verifyGreaterThan(trials(), 15, "The first run searches.");
            recorder.Fractions = [];
            p.theta = 20;
            second = plugin.solve(p);
            testCase.verifyEqual(trials(), 0, "Only the angle changed: no second search.");
            testCase.verifyEqual(second.optimal, first.optimal);
            p.v0 = p.v0 + 5;                          % anything else searches again
            recorder.Fractions = [];
            third = plugin.solve(p);
            testCase.verifyGreaterThan(trials(), 15);
            testCase.verifyGreaterThan(third.optimal.range, first.optimal.range);
        end

        function spinCurvesTheBall(testCase)
            % Sidespin adds a Top view; backspin a longer carry.
            preset = findall(testCase.App.Figure, Tag="dlab.preset");
            preset.Value = "builtin:Curveball (sidespin)";
            preset.ValueChangedFcn(preset, []);
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("sidespin"));
            testCase.pressRun();
            testCase.verifyTrue(ismember("Top view", testCase.App.View.tabTitles()));
            testCase.verifyLessThan(testCase.summary("Lateral deflection (+ to the right)"), -0.2, "Negative sidespin: to the left.");
            T = testCase.App.View.Plugin.exportTable(testCase.App.View.Result);
            testCase.verifyTrue(all(ismember(["z" "vz"], T.Properties.VariableNames)));
            preset.Value = "builtin:Golf drive with backspin";
            preset.ValueChangedFcn(preset, []);
            testCase.pressRun();
            testCase.verifyFalse(ismember("Top view", testCase.App.View.tabTitles()), "No sidespin: no top view.");
            carry = testCase.summary("Range");
            testCase.set("backspin", 0);
            testCase.pressRun();
            testCase.verifyGreaterThan(carry, 1.2 * testCase.summary("Range"), "Backspin lifts the drive.");
        end

        function windAndDensityInputsFollowTheModel(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("windX"), "No air without drag.");
            testCase.set("model", "sphere");
            testCase.verifyTrue(panel.isRowShown("windX"));
            testCase.verifyTrue(panel.isRowShown("rho"));
            testCase.verifyFalse(panel.isRowShown("siteAltitude"));
            testCase.verifyFalse(panel.isRowShown("windProfile"));
            testCase.set("density", "isa");
            testCase.verifyFalse(panel.isRowShown("rho"));
            testCase.verifyTrue(panel.isRowShown("siteAltitude"));
            testCase.set("windX", -6);
            testCase.verifyTrue(panel.isRowShown("windProfile"));
            testCase.pressRun();
            testCase.verifyLessThan(testCase.summary("Wind drift"), 0, "A headwind shortens the throw.");
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function equalAxesIsADisplaySetting(testCase)
            testCase.pressRun();
            testCase.set("equalAxes", false);
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
            ax = findall(testCase.App.Figure, Type="axes", Tag="");
            trajectory = ax(arrayfun(@(a) string(a.Title.String) == "Trajectory", ax));
            testCase.verifyEqual(string(trajectory.DataAspectRatioMode), "auto");
        end
        function windIsReadNotHiddenBehindTheLegend(testCase)
            % The wind label sat in the top-right corner, under the legend.
            testCase.preset("Golf drive into a headwind");
            testCase.pressRun();
            testCase.verifyTrue(contains(testCase.readout(), "wind 8.0 m/s ← headwind"));
            trajectory = testCase.axesTitled("Trajectory");
            others = findall(trajectory, Type="text", Units="normalized");
            testCase.verifyNumElements(others, 1, "Only the readout: no corner label.");
        end

        function trajectoryLeavesRoomForTheReadout(testCase)
            % The readout and the legend sit above the highest arc, and a flat
            % throw is not squeezed into a strip under them.
            testCase.pressRun();
            trajectory = testCase.axesTitled("Trajectory");
            testCase.verifyGreaterThanOrEqual(trajectory.YLim(2), 1.3 * testCase.summary("Maximum height"));
            testCase.preset("Topspin tennis drive");
            testCase.pressRun();
            testCase.verifyGreaterThanOrEqual(trajectory.YLim(2), 0.3 * trajectory.XLim(2));
        end

        function sidewaysFlightIsShownEverywhere(testCase)
            % Curveball: z and vz plotted and read out; the top view is seen
            % from above (the ball's right is down the screen) with the
            % straight line inside the limits.
            testCase.preset("Curveball (sidespin)");
            testCase.pressRun();
            position = testCase.axesTitled("Position vs time");
            testCase.verifyNumElements(findall(position, Type="line", DisplayName="z (to the right)"), 1);
            velocity = testCase.axesTitled("Velocity vs time");
            testCase.verifyNumElements(findall(velocity, Type="line", DisplayName="vz"), 1);
            testCase.verifyTrue(contains(testCase.readout(), "z = 0.00 m"));
            top = findall(testCase.App.Figure, Type="axes");
            top = top(arrayfun(@(a) string(a.XLabel.String) == "Downrange x (m)", top));
            testCase.assertNumElements(top, 1);
            testCase.verifyEqual(string(top.YDir), "reverse");
            testCase.verifyGreaterThan(top.YLim(2), 0, "The straight line (z = 0) is inside.");
            testCase.verifyLessThan(top.YLim(1), testCase.summary("Lateral deflection (+ to the right)"));
        end

        function summaryUnitsAreUnits(testCase)
            % Headless, every preset: the Units column holds units only (they
            % become sweep and map axis labels), and nothing is NaN.
            plugin = dlab.sims.projectile.ProjectilePlugin();
            list = plugin.presets();
            for k = 1:numel(list)
                p = plugin.defaultParams();
                for f = string(fieldnames(list(k).Values))'
                    p.(f) = list(k).Values.(f);
                end
                S = plugin.summaryTable(plugin.solve(p));
                testCase.verifyTrue(all(ismember(S.Units, ["s" "m" "m/s" "deg" "%" ""])), list(k).Name);
                testCase.verifyTrue(all(isfinite(S.Value)), list(k).Name);
            end
        end

        function maximumSpeedCountsSidewaysMotion(testCase)
            % A curveball dropped from 30 m speeds up all the way down; its
            % sideways velocity counts in the maximum as in the impact speed.
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = plugin.defaultParams();
            [p.model, p.v0, p.theta, p.h0, p.radius, p.Cd, p.m, p.sidespin, p.findOptimal] = ...
                deal("sphere", 10, 0, 30, 0.0366, 0.35, 0.145, 2500, false);
            S = plugin.summaryTable(plugin.solve(p));
            value = @(name) S.Value(S.Quantity == name);
            testCase.verifyEqual(value("Maximum speed"), value("Impact speed"), RelTol=1e-12);
        end
    end
end
