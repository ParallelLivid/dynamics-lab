classdef TestLessonChecks < matlab.unittest.TestCase
    %TESTLESSONCHECKS Lesson check kinds against hand-built contexts (no
    %   window): multiple choice, maps, optimization, uncertainty, Bode,
    %   and lessons that move between simulators.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function choiceNeedsTheRightOption(testCase)
            check = struct("kind", "choice", "options", {{'Shorter', 'Same', 'Longer'}}, "answer", 3);
            [passed, message] = dlab.core.Lesson.evaluate(check, context(Answer=NaN));
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Choose an answer, then press Check.");
            [passed, message] = dlab.core.Lesson.evaluate(check, context(Answer=2));
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Not quite.");
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, context(Answer=3)));
        end

        function choiceMustNameAnOption(testCase)
            check = struct("kind", "choice", "options", {{'A', 'B'}}, "answer", 3);
            testCase.verifyError(@() dlab.core.Lesson.validateCheck(check, 1), "dlab:lesson:format");
            testCase.verifyError(@() dlab.core.Lesson.validateCheck(struct("kind", "choice"), 1), ...
                "dlab:lesson:format");
        end

        function mapNeedsBothInputsAndARange(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            M = dlab.core.Map.run(plugin, plugin.defaultParams(), "v0", [20; 40], "theta", [30; 45; 60]);
            check = struct("kind", "map", "x", "theta", "y", "v0", "minRuns", 6);
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, context(Map=M, Specs=plugin.parameters())), ...
                "The axes may be either way round.");
            check.minRuns = 7;
            [passed, message] = dlab.core.Lesson.evaluate(check, context(Map=M, Specs=plugin.parameters()));
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Run a map of Launch angle and Launch speed with at least 7 points (Analyze ▸ Map).");
            check = struct("kind", "map", "x", "v0", "y", "theta", "quantity", "Range", "min", 160, "max", 170);
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, context(Map=M)), "40²/9.81 = 163.1 m");
            check.min = 200;
            [~, message] = dlab.core.Lesson.evaluate(check, context(Map=M));
            testCase.verifyMatches(message, "The largest Range is 163\.1 m");
        end

        function optimizeChecksTheBestInputOrResult(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            R = dlab.core.Optimizer.run(plugin, plugin.defaultParams(), "theta", "Range");
            ctx = context(Optimize=R, Specs=plugin.parameters());
            check = struct("kind", "optimize", "inputs", "theta", "metric", "Range", "input", "theta", ...
                "min", 44.5, "max", 45.5);
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, ctx));
            check = struct("kind", "optimize", "inputs", "theta", "min", 250);
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, ctx), "The best range is 254.8 m.");
            check = struct("kind", "optimize", "inputs", ["theta" "v0"]);
            [passed, message] = dlab.core.Lesson.evaluate(check, ctx);
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Optimize Launch angle and Launch speed (Analyze ▸ Optimize), and let it finish.");
            check = struct("kind", "optimize", "inputs", "theta", "metric", "Max height");
            testCase.verifyFalse(dlab.core.Lesson.evaluate(check, ctx), "A different result was optimized.");
        end

        function uncertaintyChecksAStatistic(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            tol = dlab.core.MonteCarlo.tolerance("x0", Spread=0.1);
            R = dlab.core.MonteCarlo.run(plugin, plugin.defaultParams(), tol, Samples=40);
            check = struct("kind", "uncertainty", "inputs", "x0", "minRuns", 40, "quantity", "Peak displacement", ...
                "statistic", "Std", "min", 0.045, "max", 0.07);   % uniform ±0.1: σ = 0.1/√3
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, context(Uncertainty=R)));
            check.minRuns = 41;
            testCase.verifyFalse(dlab.core.Lesson.evaluate(check, context(Uncertainty=R)));
            check = struct("kind", "uncertainty", "inputs", "zeta");
            testCase.verifyFalse(dlab.core.Lesson.evaluate(check, context(Uncertainty=R, ...
                Specs=plugin.parameters())), "zeta was not varied.");
        end

        function bodeChecksThePairAndAQuantity(testCase)
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = plugin.defaultParams();
            p.mode = "single";
            S = dlab.core.FrequencyResponse.model(plugin.linearization(p));
            R = dlab.core.FrequencyResponse.response(S, "Force", "x");
            check = struct("kind", "bode", "input", "Force", "output", "x", "quantity", "PeakFrequency", ...
                "min", 3, "max", 3.3);
            testCase.verifyTrue(dlab.core.Lesson.evaluate(check, context(Frequency=R)), "√(k/m) ≈ 3.16 rad/s");
            check.output = "v";
            [passed, message] = dlab.core.Lesson.evaluate(check, context(Frequency=R));
            testCase.verifyFalse(passed);
            testCase.verifyEqual(message, "✗ Choose Force → v on Analyze ▸ Bode.");
            [passed, message] = dlab.core.Lesson.evaluate(struct("kind", "bode"), context(Frequency=R, Fresh=false));
            testCase.verifyFalse(passed);
            testCase.verifyMatches(message, "Press Run first");
        end

        function stepsCanMoveToAnotherSimulator(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            file = fullfile(folder, "compare.json");
            writelines(jsonencode(struct("format", "dynamicslab-lesson", "formatVersion", 1, "id", "compare", ...
                "title", "Compare", "simulator", "pendulum", "steps", {{ ...
                struct("title", "One", "text", "In the pendulum."), ...
                struct("title", "Two", "text", "In the mass-spring.", "simulator", "massspring"), ...
                struct("title", "Three", "text", "Back.")}})), file);
            L = dlab.core.Lesson.read(file);
            testCase.verifyEqual(dlab.core.Lesson.simulators(L), ["pendulum" "massspring"]);
            testCase.verifyEqual(arrayfun(@(k) dlab.core.Lesson.stepSimulator(L, k), 1:3), ...
                ["pendulum" "massspring" "pendulum"]);
        end
    end
end

function c = context(options)
% A lesson context with fresh results and nothing else, unless given.
arguments
    options.Fresh = true
    options.Specs = dlab.core.ParamSpec.empty
    options.Map = []
    options.Optimize = []
    options.Uncertainty = []
    options.Frequency = []
    options.Answer = NaN
end
c = struct("Params", struct(), "Specs", options.Specs, "Fresh", options.Fresh, "RunParams", struct(), ...
    "Metrics", [], "Sweep", [], "Map", options.Map, "Optimize", options.Optimize, ...
    "Uncertainty", options.Uncertainty, "Fit", [], "Modes", [], "Frequency", options.Frequency, ...
    "KeptRuns", 0, "Answer", options.Answer);
end
