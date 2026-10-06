classdef TestOptimizer < matlab.unittest.TestCase
    %TESTOPTIMIZER The search behind the Optimize tab, against closed
    %   forms and the projectile's own optimal-angle search.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function launchAngleWithoutDragIs45Degrees(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = projectile(plugin);
            R = dlab.core.Optimizer.run(plugin, p, "theta", "Range");
            testCase.verifyEqual(R.Best, 45, "Range v² sin 2θ / g peaks at 45°.", AbsTol=0.1);
            testCase.verifyEqual(R.BestMetric, p.v0^2 / p.g, AbsTol=1e-3);
            testCase.verifyEqual([R.Inputs R.Labels R.Units], ["theta" "Launch angle" "deg"]);
            testCase.verifyEqual([R.Goal R.Metric R.MetricUnits R.Method], ["maximize" "Range" "m" "fminbnd"]);
            testCase.verifyEmpty(R.Constraint);
            testCase.verifyTrue(R.Satisfied);
            testCase.verifyFalse(R.Cancelled);
            testCase.verifyLessThanOrEqual(height(R.Evaluations), dlab.core.Optimizer.DefaultEvaluations);
            testCase.verifyTrue(startsWith(R.Message, "Best: Launch angle = 45 deg → Range 254.8 m ("), R.Message);
        end

        function agreesWithTheProjectilesOptimalAngle(testCase)
            % Off the start grid (a cliff launch) and with drag, the search
            % matches the plugin's own optimum (exact, and a 0.01° search).
            plugin = dlab.sims.projectile.ProjectilePlugin();
            for model = ["point" "sphere"]
                p = projectile(plugin);
                p.model = model;
                p.h0 = 20;
                R = dlab.core.Optimizer.run(plugin, p, "theta", "Range");
                p.findOptimal = true;
                M = plugin.metrics(plugin.solve(p));
                own = M.Value(M.Quantity == "Optimal angle");
                testCase.verifyEqual(R.Best, own, model + ": the plugin's optimal angle.", AbsTol=0.1);
                testCase.verifyEqual(R.BestMetric, M.Value(M.Quantity == "Range at optimal angle"), RelTol=1e-4);
            end
            exact = atand(p.v0 / sqrt(p.v0^2 + 2 * p.g * p.h0));
            testCase.verifyNotEqual(round(exact), 45, "The cliff moves the optimum below 45°.");
        end

        function heightLimitBindsTheLaunchAngle(testCase)
            % Range grows up to 45°, so with max height v² sin²θ / 2g ≤ H
            % the best angle is where the height reaches the limit.
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = projectile(plugin);
            limit = 40;
            R = dlab.core.Optimizer.run(plugin, p, "theta", "Range", ...
                Constraint=struct("Metric", "Maximum height", "Type", "<=", "Value", limit));
            testCase.verifyEqual(R.Best, asind(sqrt(2 * p.g * limit) / p.v0), AbsTol=0.1);
            testCase.verifyTrue(R.Satisfied);
            testCase.verifyLessThanOrEqual(R.ConstraintValue, limit + 1e-9);
            testCase.verifyEqual(R.ConstraintValue, limit, AbsTol=0.1);
            testCase.verifyEqual(R.Constraint.Units, "m");
            E = R.Evaluations;
            testCase.verifyEqual(E.Feasible, E.ConstraintMetric <= limit + 1e-9, ...
                "Every run is marked by whether it meets the limit.");
            testCase.verifyTrue(any(~E.Feasible), "The search tried angles above the limit.");
            testCase.verifyTrue(contains(R.Message, "meets Maximum height ≤ 40 m"), R.Message);
        end

        function unreachableConstraintIsReported(testCase)
            % No angle lifts a 50 m/s launch 1000 m: the closest is straight up.
            plugin = dlab.sims.projectile.ProjectilePlugin();
            R = dlab.core.Optimizer.run(plugin, projectile(plugin), "theta", "Range", ...
                Constraint=struct("Metric", "Maximum height", "Type", "≥", "Value", 1000));
            testCase.verifyFalse(R.Satisfied);
            testCase.verifyEqual(R.Constraint.Type, ">=");
            testCase.verifyEqual(R.Best, 90, AbsTol=0.1);
            testCase.verifyTrue(contains(R.Message, "NO run met Maximum height ≥ 1000 m"), R.Message);
        end

        function toyFrequencyWithTheEndAtTheTop(testCase)
            % Undamped, x(1 s) = x0 cos ω: the largest final displacement
            % in 4–8 rad/s is at ω = 2π.
            plugin = dlabtest.ToyOscillatorPlugin();
            p = toy(plugin);
            R = dlab.core.Optimizer.run(plugin, p, "omega", "Final displacement", Bounds=[4 8]);
            testCase.verifyEqual(R.Best, 2 * pi, AbsTol=1e-3);
            testCase.verifyEqual(R.BestMetric, p.x0, AbsTol=1e-6);
            R = dlab.core.Optimizer.run(plugin, p, "omega", "Final displacement", Goal="minimize", Bounds=[2 4]);
            testCase.verifyEqual(R.Best, pi, "Minimizing finds the trough at ω = π.", AbsTol=1e-3);
            testCase.verifyEqual(R.BestMetric, -p.x0, AbsTol=1e-6);
        end

        function toyTwoInputs(testCase)
            % x(1 s) = x0 cos ω over x0 in [−2, 3] and ω in [4, 8]: 3 at 2π.
            plugin = dlabtest.ToyOscillatorPlugin();
            R = dlab.core.Optimizer.run(plugin, toy(plugin), ["x0" "omega"], "Final displacement", ...
                Bounds=[-2 3; 4 8]);
            testCase.verifyEqual(R.Method, "fminsearch");
            testCase.verifyEqual(R.Best, [3 2 * pi], AbsTol=[1e-3 2e-2]);
            testCase.verifyEqual(R.BestMetric, 3, AbsTol=1e-3);
            testCase.verifyEqual(R.Bounds, [-2 3; 4 8]);
            testCase.verifyEqual(string(R.Evaluations.Properties.VariableNames), ...
                ["x0" "omega" "Metric" "ConstraintMetric" "Feasible" "Error"]);
            testCase.verifyEqual(string(R.Evaluations.Properties.VariableUnits(1:3)), ["m" "rad/s" "m"]);
            testCase.verifyFalse(R.Capped, "A smooth two-input search ends before the run limit.");
        end

        function optimaOutsideTheRangeLandOnTheBound(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            R = dlab.core.Optimizer.run(plugin, projectile(plugin), "v0", "Range", Bounds=[10 60]);
            testCase.verifyEqual(R.Best, 60, "Range grows with speed: the upper limit.");
            R = dlab.core.Optimizer.run(plugin, projectile(plugin), "theta", "Flight time");
            testCase.verifyEqual(R.Best, 90, "The allowed range (0–90°) is respected.");

            % Open limit (ω > 0): the search stays a hair inside it.
            toyPlugin = dlabtest.ToyOscillatorPlugin();
            p = toy(toyPlugin);
            p.zeta = 0.5;
            R = dlab.core.Optimizer.run(toyPlugin, p, "omega", "Final displacement", Bounds=[0 1]);
            testCase.verifyGreaterThan(min(R.Evaluations.omega), 0);
            testCase.verifyLessThan(R.Best, 1e-4, "Slower decay is better: as close to 0 as allowed.");
            testCase.verifyTrue(all(R.Evaluations.Error == ""));
        end

        function searchRangesFollowTheSpecs(testCase)
            specs = dlabtest.ToyOscillatorPlugin().parameters();
            find = @(name) dlab.core.ParamSpec.find(specs, name);
            range = dlab.core.Optimizer.searchRange(find("omega"), 0, 10);
            testCase.verifyGreaterThan(range(1), 0, "Open lower limit: a hair inside.");
            testCase.verifyEqual(range, [0 10], AbsTol=1e-4);
            range = dlab.core.Optimizer.searchRange(find("zeta"), 0, 1);
            testCase.verifyEqual(range(1), 0, "Closed limit: searched exactly.");
            testCase.verifyLessThan(range(2), 1);
            testCase.verifyEqual(dlab.core.Optimizer.searchRange(find("cycles"), 1.5, 7.5), [2 7]);
            testCase.verifyError(@() dlab.core.Optimizer.searchRange(find("zeta"), 0, 2), "dlab:optimize:range");
            testCase.verifyError(@() dlab.core.Optimizer.searchRange(find("x0"), 3, 3), "dlab:optimize:range");
            testCase.verifyError(@() dlab.core.Optimizer.searchRange(find("cycles"), 2.2, 2.8), "dlab:optimize:range");
            % Unlimited inputs search ten times the current size either way.
            testCase.verifyEqual(dlab.core.Optimizer.defaultRange(find("x0"), 2), [-18 22]);
            testCase.verifyEqual(dlab.core.Optimizer.defaultRange(find("dt"), 0.01), [0 10.01]);
            testCase.verifyEqual(dlab.core.Optimizer.defaultRange(find("zeta"), 0.1), [0 1]);
        end

        function integerInputsTakeWholeNumbers(testCase)
            % Heat in a rod: sine mode n decays as exp(−n²π²αt/L²), so the
            % hottest final rod that stays at most 1 °C above the ends is n = 2.
            plugin = dlab.sims.heat.HeatPlugin();
            p = plugin.defaultParams();
            T = plugin.metrics(plugin.solve(p));
            base = T.Value(T.Quantity == "Final minimum temperature");
            R = dlab.core.Optimizer.run(plugin, p, "mode", "Final maximum temperature", Bounds=[1 50], ...
                Constraint=struct("Metric", "Final maximum temperature", "Type", "<=", "Value", base + 1));
            testCase.verifyEqual(R.Best, 2);
            testCase.verifyTrue(R.Satisfied);
            testCase.verifyEqual(R.Evaluations.mode, round(R.Evaluations.mode), "Only whole numbers are solved.");
            testCase.verifyEqual(numel(unique(R.Evaluations.mode)), height(R.Evaluations), ...
                "No whole number is solved twice.");

            toyPlugin = dlabtest.ToyOscillatorPlugin();
            R = dlab.core.Optimizer.run(toyPlugin, toy(toyPlugin), ["cycles" "x0"], "Peak displacement", ...
                Goal="minimize", Bounds=[1 20; -2 3], MaxEvaluations=40);
            testCase.verifyEqual(R.Evaluations.cycles, round(R.Evaluations.cycles));
            testCase.verifyEqual(R.Best(1), round(R.Best(1)));
            testCase.verifyEqual(R.BestMetric, 0, AbsTol=0.05);
        end

        function cancellingKeepsTheBestSoFar(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            recorder = dlabtest.ProgressRecorder();
            recorder.StopAt = 0.2;
            R = dlab.core.Optimizer.run(plugin, toy(plugin), ["x0" "omega"], "Final displacement", ...
                Bounds=[-2 3; 4 8], Progress=@(f) recorder.report(f));
            testCase.verifyTrue(R.Cancelled);
            E = R.Evaluations;
            testCase.verifyEqual(height(E), 29, ...
                "Stopped within the 30th of 150 runs (20 %), which is dropped unfinished.");
            [best, at] = max(E.Metric);
            testCase.verifyEqual(R.BestMetric, best);
            testCase.verifyEqual(R.Best, [E.x0(at) E.omega(at)]);
            testCase.verifyTrue(all(diff(recorder.Fractions) >= 0));
            testCase.verifyLessThanOrEqual(max(recorder.Fractions), 1);
            testCase.verifyEmpty(plugin.ProgressFcn, "The plugin's progress hook is restored.");
            testCase.verifyTrue(endsWith(R.Message, "· cancelled"), R.Message);
        end

        function failedRunsAreRecordedNotThrown(testCase)
            % The toy refuses an output step at or above the 5 s duration.
            plugin = dlabtest.ToyOscillatorPlugin();
            R = dlab.core.Optimizer.run(plugin, plugin.defaultParams(), "dt", "Final displacement", ...
                Goal="minimize", Bounds=[0.001 20]);
            E = R.Evaluations;
            failed = E.Error ~= "";
            testCase.verifyTrue(any(failed));
            testCase.verifyEqual(unique(E.Error(failed)), "Output step must be smaller than the duration.");
            testCase.verifyTrue(all(E.dt(failed) >= 5));
            testCase.verifyFalse(any(E.Feasible(failed)));
            testCase.verifyLessThan(R.Best, 5);
            testCase.verifyTrue(contains(R.Message, "failed"), R.Message);

            R = dlab.core.Optimizer.run(plugin, plugin.defaultParams(), "x0", "No such result", Bounds=[0 1]);
            testCase.verifyTrue(all(isnan(R.Best)));
            testCase.verifyTrue(isnan(R.BestMetric));
            testCase.verifyFalse(R.Satisfied);
            testCase.verifyTrue(startsWith(R.Message, "Every run failed"), R.Message);
            testCase.verifyTrue(contains(R.Evaluations.Error(1), "No such result"));
        end

        function runLimitAndStartPoint(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = toy(plugin);
            R = dlab.core.Optimizer.run(plugin, p, ["x0" "omega"], "Final displacement", ...
                Bounds=[-2 3; 4 8], MaxEvaluations=10);
            testCase.verifyEqual(height(R.Evaluations), 10);
            testCase.verifyTrue(R.Capped);
            testCase.verifyTrue(contains(R.Message, "10-run limit"), R.Message);

            p.omega = 6;
            R = dlab.core.Optimizer.run(plugin, p, "omega", "Final displacement", Bounds=[4 8], StartGrid=false);
            testCase.verifyEqual(R.Evaluations.omega(1), 6, "Without the grid, the search starts from the inputs.");
            testCase.verifyEqual(R.Best, 2 * pi, AbsTol=1e-3);

            again = dlab.core.Optimizer.run(plugin, p, "omega", "Final displacement", Bounds=[4 8], StartGrid=false);
            testCase.verifyEqual(again.Evaluations, R.Evaluations, "The search is deterministic.");
        end

        function badRequestsAreRefused(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            run = @(varargin) dlab.core.Optimizer.run(plugin, p, varargin{:});
            testCase.verifyError(@() run(["omega" "zeta" "x0" "F" "cycles"], "Peak displacement"), "dlab:optimize:inputs");
            testCase.verifyError(@() run(["x0" "x0"], "Peak displacement"), "dlab:optimize:inputs");
            testCase.verifyError(@() run("showEnvelope", "Peak displacement"), "dlab:sweep:parameter");
            testCase.verifyError(@() run("x0", "Peak displacement", Bounds=[0 1; 2 3]), "dlab:optimize:bounds");
            testCase.verifyError(@() run("zeta", "Peak displacement", Bounds=[0 2]), "dlab:optimize:range");
            testCase.verifyError(@() run("x0", "Peak displacement", ...
                Constraint=struct("Metric", "Final displacement", "Type", "<", "Value", 1)), "dlab:optimize:constraint");
        end
    end
end

function p = projectile(plugin)
% A point mass at 50 m/s from the ground, without the plugin's own search.
p = plugin.defaultParams();
p.findOptimal = false;
end

function p = toy(plugin)
% Undamped for one second, so x(1 s) = x0 cos ω.
p = plugin.defaultParams();
p.zeta = 0;
p.duration = 1;
end
