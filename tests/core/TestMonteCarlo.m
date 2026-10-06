classdef TestMonteCarlo < matlab.unittest.TestCase
    %TESTMONTECARLO The engine behind the Uncertainty tab: reproducible
    %   samples, their distributions, statistics, and variance shares.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function sameSeedSameResults(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            MC = @dlab.core.MonteCarlo.run;
            tol = dlab.core.MonteCarlo.tolerance(["x0" "zeta"], Kind=["uniform" "normal"], ...
                Spread=[10 0.02], Relative=[true false]);
            R1 = MC(plugin, plugin.defaultParams(), tol, Samples=20, Seed=7);
            R2 = MC(plugin, plugin.defaultParams(), tol, Samples=20, Seed=7);
            R3 = MC(plugin, plugin.defaultParams(), tol, Samples=20, Seed=8);
            testCase.verifyEqual(R2.Samples, R1.Samples);
            testCase.verifyEqual(R2.Data, R1.Data);
            testCase.verifyEqual(R2.Mean, R1.Mean);
            testCase.verifyNotEqual(R3.Samples, R1.Samples, "Another seed draws other samples.");
            testCase.verifyEqual(size(R1.Samples), [20 2]);
            testCase.verifyEqual(R1.Inputs, ["x0" "zeta"]);
            testCase.verifyEqual(R1.Labels, ["Initial displacement" "Damping ratio"]);
            testCase.verifyEqual(R1.Units, ["m" ""]);
            testCase.verifyEqual(R1.Tolerances.Std, [0.1 / sqrt(3); 0.02], AbsTol=1e-15);
            testCase.verifyEqual(plugin.SolveCount, 63, "One nominal run and one per sample, three times.");
        end

        function uniformSamplesHaveTheirMeanAndSpread(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            params = plugin.defaultParams();
            h = 0.2;
            n = 2000;
            tol = dlab.core.MonteCarlo.validate(plugin.parameters(), params, ...
                dlab.core.MonteCarlo.tolerance("x0", Spread=h));
            [x, clipped] = dlab.core.MonteCarlo.draw(plugin.parameters(), tol, n, 3);
            testCase.verifyEqual(clipped, 0);
            testCase.verifyTrue(all(abs(x - 1) <= h));
            sigma = h / sqrt(3);
            testCase.verifyEqual(mean(x), 1, "Mean within 3 standard errors.", AbsTol=3 * sigma / sqrt(n));
            testCase.verifyEqual(std(x), sigma, "Std of a uniform ± h is h/√3.", RelTol=0.05);
        end

        function normalSamplesHaveTheirMeanAndSpread(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            params = plugin.defaultParams();
            n = 2000;
            tol = dlab.core.MonteCarlo.validate(plugin.parameters(), params, ...
                dlab.core.MonteCarlo.tolerance("x0", Kind="normal", Spread=5, Relative=true));
            x = dlab.core.MonteCarlo.draw(plugin.parameters(), tol, n, 11);
            sigma = 0.05;
            testCase.verifyEqual(mean(x), 1, "Mean within 3 standard errors.", AbsTol=3 * sigma / sqrt(n));
            testCase.verifyEqual(std(x), sigma, "Std within sampling error.", RelTol=0.05);
            testCase.verifyEqual(mean(abs(x - 1) < sigma), 0.6827, "About 68 % within one σ.", AbsTol=0.03);
            testCase.verifyTrue(all(isfinite(x)));
        end

        function linearMetricFollowsItsInput(testCase)
            % The toy's peak displacement is x0 exactly (at t = 0), so its
            % spread is x0's spread and x0 explains all of it.
            plugin = dlabtest.ToyOscillatorPlugin();
            tol = dlab.core.MonteCarlo.tolerance(["x0" "zeta"], Kind=["uniform" "normal"], Spread=[0.1 0.01]);
            R = dlab.core.MonteCarlo.run(plugin, plugin.defaultParams(), tol, Samples=60, Seed=2);
            k = R.Quantities == "Peak displacement";
            testCase.verifyEqual(R.Data(:, k), R.Samples(:, 1), AbsTol=1e-12);
            testCase.verifyEqual(R.Nominal(k), 1, AbsTol=1e-12);
            testCase.verifyEqual(R.Std(k), std(R.Samples(:, 1)), RelTol=1e-10);
            testCase.verifyEqual(R.Mean(k), mean(R.Samples(:, 1)), RelTol=1e-12);
            testCase.verifyEqual(R.Sensitivity(:, k), [1; 0], AbsTol=1e-9);
            testCase.verifyEqual(R.RSquared(k), 1, AbsTol=1e-9);
            testCase.verifyEqual(R.Min(k), min(R.Samples(:, 1)), AbsTol=1e-12);
            testCase.verifyEqual(R.Max(k), max(R.Samples(:, 1)), AbsTol=1e-12);
            testCase.verifyEqual(R.Errors, strings(60, 1));
            testCase.verifyFalse(R.Cancelled);
        end

        function varianceSharesMatchTheLinearPrediction(testCase)
            % Point-mass range R = v² sin 2θ / g: to first order the shares
            % are (∂R/∂v σv)² and (∂R/∂θ σθ)², normalized.
            plugin = dlab.sims.projectile.ProjectilePlugin();
            params = plugin.defaultParams();
            params.theta = 30;
            params.findOptimal = false;
            v = params.v0;
            g = params.g;
            th = deg2rad(params.theta);
            sv = 1;                         % uniform ± √3 m/s
            st = deg2rad(1);                % normal, σ = 1°
            tol = dlab.core.MonteCarlo.tolerance(["v0" "theta"], Kind=["uniform" "normal"], ...
                Spread=[sqrt(3) 1]);
            R = dlab.core.MonteCarlo.run(plugin, params, tol, Samples=300, Seed=1);
            k = R.Quantities == "Range";
            parts = [(2 * v * sin(2 * th) / g * sv)^2; (2 * v^2 * cos(2 * th) / g * st)^2];
            testCase.verifyEqual(R.Sensitivity(:, k), parts / sum(parts), AbsTol=0.03);
            testCase.verifyGreaterThan(R.RSquared(k), 0.99);
            testCase.verifyEqual(R.Nominal(k), v^2 * sin(2 * th) / g, RelTol=1e-9);
            testCase.verifyEqual(R.Std(k), sqrt(sum(parts)), RelTol=0.05);
        end

        function samplesAreClippedToTheAllowedRange(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            specs = plugin.parameters();
            params = plugin.defaultParams();
            n = 400;
            % zeta is in [0, 1): 0.1 ± 0.2 crosses the closed lower bound.
            tol = dlab.core.MonteCarlo.validate(specs, params, dlab.core.MonteCarlo.tolerance("zeta", Spread=0.2));
            [x, clipped, mask] = dlab.core.MonteCarlo.draw(specs, tol, n, 4);
            u = dlab.physics.uniformSequence(4 + dlab.core.MonteCarlo.StreamStride, n)';
            raw = 0.1 + 0.2 * (2 * u - 1);
            testCase.verifyEqual(clipped, nnz(raw < 0));
            testCase.verifyEqual(mask, raw < 0);
            testCase.verifyEqual(x(raw < 0), zeros(nnz(raw < 0), 1));
            testCase.verifyEqual(x(raw >= 0), raw(raw >= 0), AbsTol=1e-15);
            testCase.verifyGreaterThan(clipped, 0);

            % The open upper bound: clipped to just below 1.
            params.zeta = 0.9;
            tol = dlab.core.MonteCarlo.validate(specs, params, dlab.core.MonteCarlo.tolerance("zeta", Spread=0.2));
            [x, clipped] = dlab.core.MonteCarlo.draw(specs, tol, n, 4);
            testCase.verifyEqual(clipped, nnz(0.9 + 0.2 * (2 * u - 1) > max(x)));
            testCase.verifyGreaterThan(clipped, 0);
            testCase.verifyLessThan(max(x), 1);
            testCase.verifyGreaterThan(max(x), 0.999);

            % Whole numbers stay whole and in range; rounding is not clipping.
            tol = dlab.core.MonteCarlo.validate(specs, params, dlab.core.MonteCarlo.tolerance("cycles", Spread=1.4));
            [x, clipped] = dlab.core.MonteCarlo.draw(specs, tol, n, 4);
            testCase.verifyEqual(x, round(x));
            testCase.verifyEqual(unique(x)', 2:4);
            testCase.verifyEqual(clipped, 0);
            tol = dlab.core.MonteCarlo.validate(specs, params, dlab.core.MonteCarlo.tolerance("cycles", Spread=4));
            [x, clipped] = dlab.core.MonteCarlo.draw(specs, tol, n, 4);
            testCase.verifyEqual(min(x), 1);
            testCase.verifyEqual(clipped, nnz(round(3 + 4 * (2 * u - 1)) < 1));
        end

        function clippedCountsReachTheResult(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            tol = dlab.core.MonteCarlo.tolerance(["x0" "zeta"], Spread=[0.1 0.2]);
            R = dlab.core.MonteCarlo.run(plugin, plugin.defaultParams(), tol, Samples=50, Seed=4);
            testCase.verifyEqual(R.Clipped(1), 0);
            testCase.verifyEqual(R.Clipped(2), nnz(R.Samples(:, 2) == 0));
            testCase.verifyGreaterThan(R.Clipped(2), 0);
        end

        function failedRunsAreCountedNotThrown(testCase)
            % The toy fails when the output step is not below the duration.
            plugin = dlabtest.ToyOscillatorPlugin();
            params = plugin.defaultParams();
            params.dt = 0.04;
            params.duration = 0.05;
            tol = dlab.core.MonteCarlo.tolerance("duration", Spread=0.03);
            R = dlab.core.MonteCarlo.run(plugin, params, tol, Samples=40, Seed=9);
            bad = R.Samples <= 0.04;
            testCase.verifyGreaterThan(nnz(bad), 0);
            testCase.verifyEqual(R.Errors ~= "", bad);
            testCase.verifyTrue(all(isnan(R.Data(bad, :)), "all"));
            testCase.verifyTrue(all(isfinite(R.Data(~bad, :)), "all"));
            k = R.Quantities == "Peak displacement";
            testCase.verifyEqual(R.Mean(k), mean(R.Data(~bad, k)), RelTol=1e-12);
            testCase.verifyEqual(R.NominalError, "");
        end

        function cancellingKeepsTheFinishedRuns(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            recorder = dlabtest.ProgressRecorder();
            recorder.StopAt = 0.5;
            tol = dlab.core.MonteCarlo.tolerance("x0", Spread=0.1);
            R = dlab.core.MonteCarlo.run(plugin, plugin.defaultParams(), tol, Samples=10, Seed=1, ...
                Progress=@(f) recorder.report(f));
            testCase.verifyTrue(R.Cancelled);
            testCase.verifyEqual(R.Requested, 10);
            n = size(R.Samples, 1);
            testCase.verifyGreaterThan(n, 0);
            testCase.verifyLessThan(n, 10);
            testCase.verifyEqual(size(R.Data, 1), n);
            testCase.verifyEqual(numel(R.Errors), n);
            testCase.verifyTrue(all(isfinite(R.Data), "all"));
            testCase.verifyTrue(all(isfinite(R.Mean)));
            testCase.verifyTrue(all(diff(recorder.Fractions) >= 0));
            testCase.verifyEmpty(plugin.ProgressFcn, "The plugin's progress hook is restored.");
        end

        function percentilesInterpolateBetweenSortedValues(testCase)
            P = @dlab.core.MonteCarlo.percentile;
            % Sorted 1..5 sit at 0, 25, 50, 75, 100 %: 5 % is a fifth of
            % the way from 1 to 2.
            testCase.verifyEqual(P([3 1 5 2 4], [5 50 95]), [1.2 3 4.8], AbsTol=1e-12);
            testCase.verifyEqual(P([10; 20], 25), 12.5, AbsTol=1e-12);
            testCase.verifyEqual(P([4 NaN 2], [0 100]), [2 4]);
            testCase.verifyEqual(P(7, 95), 7);
            testCase.verifyTrue(isnan(P([NaN NaN], 50)));
        end

        function sensitivityOfAKnownLinearModel(testCase)
            % y = 3 a + b with a, b orthogonal and equal spread: shares
            % 9/10 and 1/10, R² = 1.
            a = [1; -1; 1; -1];
            b = [1; 1; -1; -1];
            [shares, r2] = dlab.core.MonteCarlo.sensitivity([a b], 3 * a + b);
            testCase.verifyEqual(shares, [0.9; 0.1], AbsTol=1e-12);
            testCase.verifyEqual(r2, 1, AbsTol=1e-12);
            [shares, r2] = dlab.core.MonteCarlo.sensitivity([a b], ones(4, 1));
            testCase.verifyTrue(all(isnan(shares)) && isnan(r2), "A constant result has no shares.");
        end

        function tablesCarryUnitsAndSummaries(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            tol = dlab.core.MonteCarlo.tolerance(["x0" "zeta"], Spread=[0.1 0.02]);
            R = dlab.core.MonteCarlo.run(plugin, plugin.defaultParams(), tol, Samples=30, Seed=1);
            T = dlab.core.MonteCarlo.toTable(R);
            testCase.verifyEqual(height(T), 30);
            testCase.verifyEqual(string(T.Properties.VariableNames), ...
                ["x0" "zeta" "PeakDisplacement" "FinalDisplacement" "error"]);
            testCase.verifyEqual(string(T.Properties.VariableUnits(1:4)), ["m" "" "m" "m"]);
            S = dlab.core.MonteCarlo.summaryTable(R);
            testCase.verifyEqual(S.Quantity, ["Peak displacement"; "Final displacement"]);
            testCase.verifyEqual(S.MostInfluential(1), "Initial displacement");
            testCase.verifyEqual(S.Share(1), 1, AbsTol=1e-9);
            testCase.verifyEqual(S.P05, R.P05(:));
            testCase.verifyEqual(S.Std, R.Std(:));
        end

        function badRequestsAreExplained(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            params = plugin.defaultParams();
            MC = @(tol, varargin) dlab.core.MonteCarlo.run(plugin, params, tol, varargin{:});
            T = @dlab.core.MonteCarlo.tolerance;
            testCase.verifyError(@() MC(T(strings(1, 0))), "dlab:montecarlo:none");
            testCase.verifyError(@() MC(T("drive")), "dlab:sweep:parameter");
            testCase.verifyError(@() MC(T("x0", Kind="triangle")), "dlab:montecarlo:kind");
            testCase.verifyError(@() MC(T("x0", Spread=-1)), "dlab:montecarlo:spread");
            testCase.verifyError(@() MC(T(["x0" "x0"])), "dlab:montecarlo:duplicate");
            testCase.verifyError(@() MC(T("x0"), Samples=1), "dlab:montecarlo:samples");
            testCase.verifyError(@() MC(T("x0"), Samples=2001), "dlab:montecarlo:samples");
            testCase.verifyError(@() MC(T("x0"), Seed=2e6), "dlab:montecarlo:seed");
            params.x0 = 0;
            testCase.verifyError(@() dlab.core.MonteCarlo.validate(plugin.parameters(), params, ...
                T("x0", Relative=true)), "dlab:montecarlo:relative");
        end
    end
end
