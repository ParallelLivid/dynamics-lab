classdef TestScripting < matlab.unittest.TestCase
    %TESTSCRIPTING dlab.run and dlab.simulators: the window-free API.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function defaultsMatchTheApp(testCase)
            out = dlab.run("pendulum");
            plugin = dlab.sims.pendulum.PendulumPlugin();
            testCase.verifyEqual(out.Simulator, "pendulum");
            testCase.verifyEqual(out.Params, plugin.defaultParams());
            testCase.verifyEqual(out.Data, plugin.exportTable(plugin.solve(plugin.defaultParams())));
            testCase.verifyClass(out.Metrics.Value, "double");
            testCase.verifyTrue(ismember("Peak angle", out.Summary.Quantity));
        end

        function overridesAndPresets(testCase)
            out = dlab.run("pendulum", theta0=60, L=2);
            testCase.verifyEqual([out.Params.theta0 out.Params.L], [60 2]);
            out = dlab.run("projectile", Preset="Moon", theta=30);
            testCase.verifyEqual([out.Params.g out.Params.theta], [1.62 30]);
        end

        function coupledInputsFollowButExplicitValuesWin(testCase)
            bodies = dlab.sims.orbit.BodyCatalog();
            out = dlab.run("orbit", body="Mars");
            testCase.verifyEqual(out.Params.sampleStep, bodies.Mars.sampleStep);
            testCase.verifyEqual(out.Params.a, bodies.Mars.orbit(1));
            out = dlab.run("orbit", body="Mars", sampleStep=40);
            testCase.verifyEqual(out.Params.sampleStep, 40);
        end

        function scenarioFilesLoad(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(temp.Folder, "swing.json");
            plugin = dlab.sims.pendulum.PendulumPlugin();
            params = plugin.defaultParams();
            params.theta0 = 120;
            dlab.core.ScenarioIO.save(file, plugin, params);
            out = dlab.run("pendulum", Scenario=file, b=0);
            testCase.verifyEqual([out.Params.theta0 out.Params.b], [120 0]);
        end

        function mistakesAreClearErrors(testCase)
            testCase.verifyError(@() dlab.run("nope"), "dlab:unknownSimulator");
            testCase.verifyError(@() dlab.run("pendulum", Length=2), "dlab:run:unknownParameter");
            testCase.verifyError(@() dlab.run("pendulum", L=-1), "dlab:invalidParameter");
            testCase.verifyError(@() dlab.run("pendulum", "L"), "dlab:run:overrides");
            testCase.verifyError(@() dlab.run("projectile", Preset="Nope"), "dlab:unknownPreset");
        end

        function simulatorsAreListed(testCase)
            list = dlab.simulators();
            testCase.verifyEqual(list.Id', ["pendulum" "massspring" "projectile" "nonlinear" "attractors" "rigidbody" ...
                "collisions" "dcmotor" "cartpole" "quartercar" "handling" "orbit" "maneuvers" "flyby" "threebody" ...
                "rocket" "entry" "attitude" "flight6dof" ...
                "quadrotor" "truss" "frame" "column" "wave" "membrane" "heat" "plate"], ...
                "Home-screen order (dlab.sims.registry).");
            inputs = dlab.simulators("pendulum");
            lengthRow = inputs(inputs.Name == "L", :);
            testCase.verifyEqual(height(lengthRow), 1);
            testCase.verifyEqual(lengthRow.Units, "m");
            testCase.verifyEqual(lengthRow.Range, "[0.1, 10] m");
        end
    end
end
