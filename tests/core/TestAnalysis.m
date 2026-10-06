classdef (TestTags = {'ui'}) TestAnalysis < matlab.unittest.TestCase
    %TESTANALYSIS Parameter sweeps, metrics, and linearization (the
    %   engines behind the Sweep, Custom plot, and Modes tabs).

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function sweepCollectsMetricsPerValue(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            S = dlab.core.Sweep.run(plugin, plugin.defaultParams(), "x0", [1; 2; 3]);
            testCase.verifyEqual(S.Label, "Initial displacement");
            testCase.verifyEqual(S.Units, "m");
            column = S.Quantities == "Peak displacement";
            testCase.verifyEqual(S.Data(:, column), [1; 2; 3], AbsTol=1e-12);
            testCase.verifyEqual(S.QuantityUnits(column), "m");
            testCase.verifyEqual(S.Errors, ["" ; ""; ""]);
            testCase.verifyFalse(S.Cancelled);
        end

        function sweepCollectsSetValuedResults(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            S = dlab.core.Sweep.run(plugin, plugin.defaultParams(), "x0", [1; 2]);
            testCase.verifyEqual(S.SetNames, "Peaks");
            testCase.verifyEqual(S.SetUnits, "m");
            for k = 1:2
                p = plugin.defaultParams();
                p.x0 = k;
                expected = plugin.distributions(plugin.solve(p)).Values{1};
                testCase.verifyEqual(S.SetData{k, 1}, expected(:), AbsTol=1e-12);
            end
            T = dlab.core.Sweep.toLongTable(S);
            testCase.verifyEqual(height(T), numel(S.SetData{1}) + numel(S.SetData{2}));
            testCase.verifyEqual(string(T.Properties.VariableNames), ["x0" "Quantity" "Value" "Units"]);
            testCase.verifyEqual(unique(T.Quantity), "Peaks");
            testCase.verifyEqual(T.Value(T.x0 == 2), S.SetData{2, 1});
        end

        function sweepRecordsFailedRuns(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            S = dlab.core.Sweep.run(plugin, plugin.defaultParams(), "dt", [0.01; 10]);
            testCase.verifyEqual(S.Errors(1), "");
            testCase.verifyEqual(S.Errors(2), "Output step must be smaller than the duration.");
            testCase.verifyTrue(all(isnan(S.Data(2, :))));
        end

        function sweepStopsWhenAsked(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            recorder = dlabtest.ProgressRecorder();
            recorder.StopAt = 0.5;
            S = dlab.core.Sweep.run(plugin, plugin.defaultParams(), "x0", (1:4)', ...
                Progress=@(f) recorder.report(f));
            testCase.verifyTrue(S.Cancelled);
            testCase.verifyTrue(all(isfinite(S.Data(1, :))));
            testCase.verifyTrue(all(isnan(S.Data(3:4, :)), "all"));
            testCase.verifyTrue(all(diff(recorder.Fractions) >= 0));
            testCase.verifyEmpty(plugin.ProgressFcn, "The plugin's progress hook is restored.");
        end

        function onlyNumericModelInputsSweep(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            params = plugin.defaultParams();
            testCase.verifyError(@() dlab.core.Sweep.run(plugin, params, "showEnvelope", 1), "dlab:sweep:parameter");
            testCase.verifyError(@() dlab.core.Sweep.run(plugin, params, "drive", 1), "dlab:sweep:parameter");
            testCase.verifyError(@() dlab.core.Sweep.run(plugin, params, "x0", zeros(0, 1)), "dlab:sweep:steps");
            testCase.verifyEqual([dlab.core.SweepPanel.sweepable(plugin.parameters()).Name], ...
                ["omega" "zeta" "x0" "F" "cycles" "duration" "dt"]);
        end

        function rangesAreLinearLogOrWhole(testCase)
            R = @dlab.core.Sweep.range;
            testCase.verifyEqual(R(0, 10, 3), [0; 5; 10]);
            testCase.verifyEqual(R(1, 100, 3, Log=true), [1; 10; 100], RelTol=1e-12);
            testCase.verifyEqual(R(1, 3, 5, Integer=true), [1; 2; 3]);
            testCase.verifyError(@() R(0, 10, 3, Log=true), "dlab:sweep:log");
        end

        function sweepTablesCarryUnits(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            T = dlab.core.Sweep.toTable(dlab.core.Sweep.run(plugin, plugin.defaultParams(), "x0", [1; 2]));
            testCase.verifyEqual(string(T.Properties.VariableNames), ...
                ["x0" "PeakDisplacement" "FinalDisplacement" "error"]);
            testCase.verifyEqual(string(T.Properties.VariableUnits(1:3)), ["m" "m" "m"]);
        end

        function scriptedSweepFindsTheBestLaunchAngle(testCase)
            T = dlab.sweep("projectile", "theta", 30:15:60);
            [~, best] = max(T.Range);
            testCase.verifyEqual(T.theta(best), 45);
            testCase.verifyEqual(T.Range(best), 254.84, AbsTol=0.01);
        end

        function defaultMetricsKeepNumericSummaryRows(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            M = plugin.metrics(plugin.solve(plugin.defaultParams()));
            testCase.verifyClass(M.Value, "double");
            testCase.verifyTrue(ismember("Final altitude", M.Quantity));
            testCase.verifyFalse(ismember("Termination", M.Quantity), "Text rows are not metrics.");
        end

        function linearOscillatorModes(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            L = dlab.core.Linearization.analyze(plugin.linearization(p));
            testCase.verifyTrue(L.IsEquilibrium);
            testCase.verifyEqual(height(L.Modes), 1, "A conjugate pair is one mode.");
            testCase.verifyEqual(L.Modes.NaturalFrequency, p.omega, RelTol=1e-6);
            testCase.verifyEqual(L.Modes.DampingRatio, p.zeta, RelTol=1e-6);
            testCase.verifyEqual(L.Modes.Period, 2*pi / (p.omega * sqrt(1 - p.zeta^2)), RelTol=1e-6);
            testCase.verifyEqual(L.Modes.Stability, "Stable");
            testCase.verifyEqual(L.Modes.Mode, "Oscillation");
        end

        function saddlesAndNonEquilibriaAreFlagged(testCase)
            saddle = struct("F", @(x) [x(2); x(1)], "X0", [0; 0], "StateNames", ["a" "b"], "Reference", "origin");
            L = dlab.core.Linearization.analyze(saddle);
            testCase.verifyEqual(sort(L.Modes.Stability), ["Stable"; "Unstable"]);
            testCase.verifyEqual(L.Modes.TimeConstant, [1; 1], AbsTol=1e-6);
            testCase.verifyEqual(string(L.Modes.Properties.VariableUnits([2 5 7])), ["1/s" "rad/s" "s"]);
            saddle.TimeUnit = "time unit";            % a dimensionless model
            L = dlab.core.Linearization.analyze(saddle);
            testCase.verifyEqual(string(L.Modes.Properties.VariableUnits([2 5 7])), ...
                ["1/time unit" "rad/time unit" "time units"]);
            drift = struct("F", @(x) [1; -x(2)], "X0", [0; 0], "StateNames", ["a" "b"], "Reference", "origin");
            testCase.verifyFalse(dlab.core.Linearization.analyze(drift).IsEquilibrium);
        end

        function pendulumModesFollowTheNearestEquilibrium(testCase)
            plugin = dlab.sims.pendulum.PendulumPlugin();
            p = plugin.defaultParams();
            L = dlab.core.Linearization.analyze(plugin.linearization(p));
            testCase.verifyEqual(L.Modes.NaturalFrequency, sqrt(p.g / p.L), RelTol=1e-6);
            testCase.verifyEqual(L.Modes.Mode, "Swing");
            p.theta0 = 170;
            L = dlab.core.Linearization.analyze(plugin.linearization(p));
            testCase.verifyEqual(sort(L.Modes.Mode), ["Settle"; "Topple"]);
            testCase.verifyTrue(ismember("Unstable", L.Modes.Stability));
        end

        function coupledMassesHaveInAndOutOfPhaseModes(testCase)
            plugin = dlab.sims.massspring.MassSpringPlugin();
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.presetParams("Beating (weak coupling)")));
            testCase.verifyEqual(L.Modes.Mode, ["Oscillation, in phase"; "Oscillation, out of phase"]);
            testCase.verifyEqual(L.Modes.NaturalFrequency, [sqrt(10); sqrt(11)], RelTol=1e-6);
        end

        function aircraftModesAreNamed(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.presetParams("Straight flight")));
            testCase.verifyTrue(L.IsEquilibrium, "Straight flight is trimmed.");
            for name = ["Dutch roll" "Roll subsidence" "Spiral" "Heading (neutral)"]
                testCase.verifyTrue(ismember(name, L.Modes.Mode), name);
            end
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.presetParams("Phugoid mode")));
            phugoid = L.Modes(L.Modes.Mode == "Phugoid", :);
            testCase.assertEqual(height(phugoid), 1);
            testCase.verifyEqual(phugoid.Period, 31.7, AbsTol=0.5);
        end

        function animationRecordingCanBeCancelled(testCase)
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            ax = uiaxes(uigridlayout(fig, [1 1]));
            h = line(ax, NaN, NaN);
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(temp.Folder, "cancelled.gif");
            info = dlab.core.AnimationExporter.write(file, "gif", @(t) set(h, XData=[0 t], YData=[0 t]), ...
                ax, 0, 10, MaxFrames=20, Progress=@(f) f >= 0.25);
            testCase.verifyTrue(info.Cancelled);
            testCase.verifyEqual(info.Frames, 5);
            testCase.verifyFalse(isfile(file), "A cancelled export leaves no partial file.");

            info = dlab.core.AnimationExporter.write(file, "gif", @(t) set(h, XData=[0 t], YData=[0 t]), ...
                ax, 0, 1, TimeScale=1);
            testCase.verifyEqual(info.Frames, 16, "1 s at 15 fps, both ends included.");
            testCase.verifyFalse(info.Capped);
        end

        function animationRecordsEveryAxesInTheGrid(testCase)
            % A main view with an inset over its lower-left corner: the frame
            % covers the whole grid, and both axes are in it where they sit.
            fig = uifigure(Visible="off", Position=[100 100 640 400]);
            testCase.addTeardown(@delete, fig);
            grid = uigridlayout(fig, [2 2], RowHeight={'1x', 120}, ColumnWidth={160, '1x'}, Padding=0, ...
                RowSpacing=0, ColumnSpacing=0, BackgroundColor=[1 1 1]);
            main = uiaxes(grid, Color=[0 0 1], XLim=[0 1], YLim=[0 1]);   % fixed: the box does not move
            main.Layout.Row = [1 2];
            main.Layout.Column = [1 2];
            inset = uiaxes(grid, Color=[1 0 0]);
            inset.Layout.Row = 2;
            inset.Layout.Column = 1;
            h = line(main, NaN, NaN);
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            draw = @(t) set(h, XData=[0 t], YData=[0 t]);
            drawnow        % on screen before recording, as in the app
            % A new axes can take a moment to appear (it fades in), and a
            % recording started earlier catches it half drawn (this check
            % used to fail about one run in twenty-five).
            waitUntilShown(fig, [345 90], [1 0 0]);

            file = fullfile(temp.Folder, "grid.gif");
            info = dlab.core.AnimationExporter.write(file, "gif", draw, grid, 0, 1, MaxFrames=3);
            testCase.verifyEqual(info.Frames, 3);
            frame = gifFrame(file, 3);
            testCase.verifyEqual(size(frame, [1 2]), [400 640], "The whole grid.");
            % Inside the main view (upper right) and inside the inset (lower left).
            testCase.verifyEqual(squeeze(frame(100, 400, :))', [0 0 1], "Main view", AbsTol=0.05);
            testCase.verifyEqual(squeeze(frame(345, 90, :))', [1 0 0], "Inset", AbsTol=0.05);

            % The grid's axes, or one of them (the shell passes the last one
            % found, here the inset), record the same.
            for target = {findall(grid, Type="axes"), inset}
                file = fullfile(temp.Folder, "axes.gif");
                dlab.core.AnimationExporter.write(file, "gif", draw, target{1}, 0, 1, MaxFrames=2);
                testCase.verifyEqual(size(gifFrame(file, 2), [1 2]), [400 640]);
            end

            % One axes alone is still recorded as its plot box.
            delete(inset);
            drawnow
            file = fullfile(temp.Folder, "single.gif");
            dlab.core.AnimationExporter.write(file, "gif", draw, grid, 0, 1, MaxFrames=2);
            box = size(getframe(main).cdata, [1 2]);
            testCase.verifyEqual(size(gifFrame(file, 1), [1 2]), box - mod(box, 2));
        end

        function customPlotDrawsAConservedQuantityFlat(testCase)
            % A total energy that varies only by rounding is drawn flat about
            % its value, not zoomed into 14-digit noise.
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            builder = dlab.core.PlotBuilder(uigridlayout(fig, [1 1]), dlab.ui.Theme.dark(), ...
                struct("X", "t", "Y", "E", "Measured", ""));
            T = table((0:10)', 5 + 1e-14 * sin((0:10)'), (0:10)'.^2, VariableNames=["t" "E" "x"]);
            T.Properties.VariableUnits = ["s" "J" "m"];
            builder.show(T);
            testCase.verifyEqual(builder.Axes.YLim, [4.75 5.25], AbsTol=1e-9);
            builder.choose("Y", "x");
            testCase.verifyEqual(builder.Axes.YLim(2) >= 100, true, "A varying column keeps automatic limits.");
        end

        function metricsOfEveryPluginAreNumeric(testCase)
            factories = dlab.sims.registry();
            for k = 1:numel(factories)
                plugin = factories{k}();
                M = plugin.metrics(plugin.solve(plugin.defaultParams()));
                testCase.verifyGreaterThan(height(M), 0, plugin.Id);
                testCase.verifyTrue(all(isfinite(M.Value)), plugin.Id);
            end
        end
    end
end

function waitUntilShown(fig, pixel, colour)
% Wait (up to 5 s) until FIG's frame shows COLOUR at PIXEL ([row column]).
clock = tic;
while toc(clock) < 5
    frame = im2double(getframe(fig).cdata);
    if all(abs(squeeze(frame(pixel(1), pixel(2), :))' - colour) < 0.05)
        return
    end
    pause(0.05);
end
end

function rgb = gifFrame(file, k)
% Frame K of a GIF as RGB in [0, 1], with that frame's own colour table
% (imread returns another frame's).
info = imfinfo(file);
rgb = ind2rgb(imread(file, k), info(k).ColorTable);
end
