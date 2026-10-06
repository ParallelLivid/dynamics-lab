classdef TestEngineProgress < matlab.unittest.TestCase
    %TESTENGINEPROGRESS Every ODE engine reports progress through its
    %   plugin and stops early when asked (the basis of Cancel).

    properties (TestParameter)
        Simulator = {"pendulum", "massspring", "orbit", "flight6dof", "quadrotor", "attitude", ...
            "rigidbody", "threebody", "cartpole", "handling", "flyby"}
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function progressRisesToOne(testCase, Simulator)
            plugin = dlab.core.Headless.plugin(Simulator, dlab.sims.registry());
            recorder = dlabtest.ProgressRecorder();
            plugin.ProgressFcn = @(fraction) recorder.report(fraction);
            plugin.solve(plugin.defaultParams());
            f = recorder.Fractions;
            testCase.verifyNotEmpty(f);
            testCase.verifyTrue(all(f >= 0 & f <= 1 + 1e-9), "Fractions lie in [0, 1].");
            testCase.verifyTrue(all(diff(f) >= -1e-12), "Fractions never go backwards.");
            testCase.verifyEqual(f(end), 1, AbsTol=1e-6);
        end

        function askingToStopEndsTheSolveEarly(testCase, Simulator)
            plugin = dlab.core.Headless.plugin(Simulator, dlab.sims.registry());
            params = plugin.defaultParams();
            full = plugin.timeVector(plugin.solve(params));
            recorder = dlabtest.ProgressRecorder();
            recorder.StopAt = 0.3;
            plugin.ProgressFcn = @(fraction) recorder.report(fraction);
            try
                t = plugin.timeVector(plugin.solve(params));
                testCase.verifyLessThan(t(end), full(end), "A stopped solve ends early.");
            catch
                % Stopping may also surface as an error (the result is
                % incomplete); the shell discards either after a cancel.
            end
            testCase.verifyLessThan(max(recorder.Fractions), 0.5, "The solver stopped soon after the request.");
        end

        function projectileReportsUnknownProgress(testCase)
            plugin = dlab.core.Headless.plugin("projectile", dlab.sims.registry());
            recorder = dlabtest.ProgressRecorder();
            plugin.ProgressFcn = @(fraction) recorder.report(fraction);
            p = plugin.presetParams("Drag example (60°)");
            p.findOptimal = false;          % the angle search reports known fractions (trial k of n)
            plugin.solve(p);
            testCase.verifyNotEmpty(recorder.Fractions);
            testCase.verifyTrue(all(isnan(recorder.Fractions)), "The impact time is unknown in advance.");
        end

        function resultsHoldNoCallbacks(testCase)
            % MAT exports save the result; it must not drag the plugin along.
            for id = ["projectile" "flight6dof"]
                plugin = dlab.core.Headless.plugin(id, dlab.sims.registry());
                presets = plugin.presets();
                result = plugin.solve(plugin.presetParams(presets(1).Name));
                testCase.verifyFalse(containsHandle(result), id);
            end
        end
    end
end

function tf = containsHandle(value)
if isa(value, "function_handle")
    tf = true;
elseif isstruct(value)
    tf = false;
    for k = 1:numel(value)
        for name = string(fieldnames(value))'
            tf = tf || containsHandle(value(k).(name));
        end
    end
elseif iscell(value)
    tf = any(cellfun(@containsHandle, value));
else
    tf = false;
end
end
