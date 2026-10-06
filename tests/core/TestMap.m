classdef TestMap < matlab.unittest.TestCase
    %TESTMAP Two-parameter maps (the engine behind the Map tab).

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function projectileRangeMatchesTheClosedForm(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            speeds = [20; 35; 50];
            angles = [15; 30; 45; 60; 75];
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "v0", speeds, "theta", angles);
            testCase.verifyEqual(M.Labels, ["Launch speed" "Launch angle"]);
            testCase.verifyEqual(M.Units, ["m/s" "deg"]);
            [range, label, units] = dlab.core.Map.layer(M, "Range");
            testCase.verifyEqual(size(range), [5 3], "Rows follow Y (the angle), columns X (the speed).");
            testCase.verifyEqual([label units], ["Range" "m"]);
            [V, TH] = meshgrid(speeds, angles);
            testCase.verifyEqual(range, V.^2 .* sind(2 * TH) / 9.81, RelTol=1e-6);
            testCase.verifyEqual(M.Errors, strings(5, 3));
            testCase.verifyFalse(M.Cancelled);
        end

        function setValuedResultsCountDistinctValues(testCase)
            % Undamped, every peak is the same height; damped, each is lower.
            plugin = dlabtest.ToyOscillatorPlugin();
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "x0", [1; 2], "zeta", [0; 0.1]);
            [counts, label] = dlab.core.Map.layer(M, "Peaks");
            testCase.verifyEqual(label, "Peaks (distinct values)");
            testCase.verifyEqual(counts(1, :), [1 1]);
            testCase.verifyGreaterThan(counts(2, :), [3 3]);
        end

        function failedRunsAreBlankAndRecorded(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "dt", [0.01; 10], "x0", [1; 2]);
            testCase.verifyEqual(M.Errors(:, 2), repmat("Output step must be smaller than the duration.", 2, 1));
            testCase.verifyEqual(M.Errors(:, 1), ["" ; ""]);
            testCase.verifyTrue(all(isnan(M.Data(:, 2, :)), "all"));
            testCase.verifyTrue(all(isnan(M.SetCounts(:, 2, :)), "all"), "A failed run has no count, not zero.");
        end

        function mapStopsWhenAsked(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            recorder = dlabtest.ProgressRecorder();
            recorder.StopAt = 0.5;
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "x0", [1; 2], "omega", [3; 4], ...
                Progress=@(f) recorder.report(f));
            testCase.verifyTrue(M.Cancelled);
            testCase.verifyTrue(all(isfinite(M.Data(1, 1, :))));
            testCase.verifyTrue(all(isnan(M.Data(:, 2, :)), "all"), "Runs go down each column, then across.");
            testCase.verifyTrue(all(isnan(M.SetCounts(:, 2, :)), "all"));
            testCase.verifyEmpty(plugin.ProgressFcn, "The plugin's progress hook is restored.");
        end

        function inputsAreChecked(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            testCase.verifyError(@() dlab.core.Map.run(plugin, p, "x0", [1; 2], "x0", [1; 2]), "dlab:map:sameInput");
            testCase.verifyError(@() dlab.core.Map.run(plugin, p, "x0", 1, "zeta", [0; 1]), "dlab:map:steps");
            testCase.verifyError(@() dlab.core.Map.run(plugin, p, "x0", (1:41)', "zeta", linspace(0, 1, 40)'), ...
                "dlab:map:steps");
            testCase.verifyError(@() dlab.core.Map.run(plugin, p, "drive", [1; 2], "zeta", [0; 1]), ...
                "dlab:sweep:parameter");
            testCase.verifyError(@() dlab.core.Map.layer(dlab.core.Map.run(plugin, p, "x0", [1; 2], ...
                "zeta", [0; 0.5]), "Nothing"), "dlab:map:quantity");
        end

        function onParamChangedRunsForBothInputs(testCase)
            % Each input is applied as an edit would be, then both values win.
            plugin = dlabtest.ToyOscillatorPlugin();
            [~, p] = dlab.core.Sweep.solveAt(plugin, plugin.defaultParams(), ["x0" "zeta"], [2 0.3]);
            testCase.verifyEqual([p.x0 p.zeta], [2 0.3]);
        end

        function tableHasOneRowPerPoint(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "x0", [1; 2; 3], "zeta", [0; 0.2]);
            T = dlab.core.Map.toTable(M);
            testCase.verifyEqual(height(T), 6);
            testCase.verifyEqual(string(T.Properties.VariableNames), ...
                ["x0" "zeta" "PeakDisplacement" "FinalDisplacement" "Peaks_distinct" "error"]);
            testCase.verifyEqual(string(T.Properties.VariableUnits(1:4)), ["m" "" "m" "m"]);
            testCase.verifyEqual(T.PeakDisplacement, T.x0, AbsTol=1e-12);
            testCase.verifyEqual(T.zeta, [0; 0.2; 0; 0.2; 0; 0.2]);
        end
    end
end
