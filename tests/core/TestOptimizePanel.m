classdef (TestTags = {'ui'}) TestOptimizePanel < matlab.unittest.TestCase
    %TESTOPTIMIZEPANEL The "Optimize" tab in a hidden figure: what it
    %   asks the view to run, how it shows the result, and its snapshot.

    properties
        Figure
        Plugin
        Theme
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function openFigure(testCase)
            testCase.Figure = uifigure(Visible="off", Position=[100 100 1000 600]);
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.Plugin = dlabtest.ToyOscillatorPlugin();
            testCase.Theme = dlab.ui.Theme.dark();
        end
    end

    methods (Test)
        function startsWithTheFirstInputAndItsRange(testCase)
            panel = testCase.newPanel();
            for tag = ["input1" "input2" "input3" "from1" "to1" "goal" "metric" "constrain" ...
                    "constraintMetric" "constraintType" "constraintValue" "run" "apply" "note" "axes"]
                testCase.verifyNotEmpty(findall(testCase.Figure, Tag="dlab.optimize." + tag), tag);
            end
            testCase.verifyEqual(string(panel.InputDropdowns(1).Value), "omega");
            testCase.verifyEqual([panel.FromFields(1).Value panel.ToFields(1).Value], [0 100], ...
                "The allowed range of the natural frequency.");
            testCase.verifyEqual(string(panel.InputDropdowns(2).Value), "-");
            testCase.verifyEqual(string(panel.FromFields(2).Enable), "off");
            testCase.verifyEqual(string(panel.MetricDropdown.Enable), "off");
            testCase.verifyEqual(string(panel.ApplyButton.Enable), "off");
            testCase.verifyError(@() panel.request(), "dlab:optimize:metrics", ...
                "Before a solve there are no results to choose from.");

            panel.InputDropdowns(2).Value = "x0";
            panel.InputDropdowns(2).ValueChangedFcn(panel.InputDropdowns(2), []);
            testCase.verifyEqual([panel.FromFields(2).Value panel.ToFields(2).Value], [-9 11], ...
                "An unlimited input: ten times its size around the current value.");
            testCase.verifyEqual(string(panel.FromFields(2).Enable), "on");
        end

        function requestIsWhatTheOptimizerTakes(testCase)
            panel = testCase.newPanel();
            testCase.solveOnce(panel);
            testCase.verifyEqual(string(panel.MetricDropdown.Items), ...
                ["Peak displacement (m)" "Final displacement (m)"]);
            limit = struct("Metric", "Peak displacement", "Type", "<=", "Value", 2.5);
            panel.configure(["x0" "omega"], "Final displacement", Goal="maximize", Bounds=[-2 3; 4 8], ...
                Constraint=limit);
            job = panel.request();
            testCase.verifyEqual(job.Inputs, ["x0" "omega"]);
            testCase.verifyEqual(job.Bounds, [-2 3; 4 8]);
            testCase.verifyEqual([job.Metric job.Goal], ["Final displacement" "maximize"]);
            testCase.verifyEqual(job.Constraint, limit);
            testCase.verifyEqual(string(panel.ConstraintValueField.Enable), "on");

            panel.ConstraintCheckbox.Value = false;
            testCase.verifyEmpty(panel.request().Constraint);
        end

        function showsTheSearchAndAppliesTheBest(testCase)
            panel = testCase.newPanel();
            testCase.solveOnce(panel);
            p = testCase.Plugin.defaultParams();
            [p.zeta, p.duration] = deal(0, 1);
            panel.configure(["x0" "omega"], "Final displacement", Bounds=[-2 3; 4 8]);
            job = panel.request();
            R = dlab.core.Optimizer.run(testCase.Plugin, p, job.Inputs, job.Metric, Goal=job.Goal, ...
                Bounds=job.Bounds, Constraint=job.Constraint);
            panel.show(R);
            testCase.verifyEqual(string(panel.NoteLabel.Text), R.Message);
            testCase.verifyEqual(panel.NoteLabel.FontColor, testCase.Theme.TextMuted);
            best = findobj(panel.Axes, Tag="dlab.optimize.best");
            testCase.verifyEqual(best.YData, R.BestMetric);
            testCase.verifyEqual(R.Evaluations{best.XData, 1:2}, R.Best, ...
                "Several inputs: plotted against run number.");
            progress = findobj(panel.Axes, Tag="dlab.optimize.progress");
            testCase.verifyEqual(progress.YData(end), R.BestMetric, "The best-so-far line ends at the best.");
            testCase.verifyEqual(string(panel.ApplyButton.Enable), "on");

            chosen = [];
            testCase.addTeardown(@delete, listener(panel, "ApplyRequested", @(src, ~) assignChosen(src)));
            panel.ApplyButton.ButtonPushedFcn(panel.ApplyButton, []);
            testCase.verifyEqual(chosen, struct("x0", R.Best(1), "omega", R.Best(2)));

            function assignChosen(src)
                chosen = src.Chosen;
            end
        end

        function oneInputPlotsTheResultAgainstIt(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = plugin.defaultParams();
            p.findOptimal = false;
            panel = dlab.core.OptimizePanel(testCase.Figure, plugin.parameters(), @() p, testCase.Theme);
            panel.setMetrics(plugin.metrics(plugin.solve(p)));
            panel.configure("theta", "Range", Constraint=struct("Metric", "Maximum height", "Type", "<=", "Value", 40));
            job = panel.request();
            R = dlab.core.Optimizer.run(plugin, p, job.Inputs, job.Metric, Constraint=job.Constraint);
            panel.show(R);
            runs = findobj(panel.Axes, Tag="dlab.optimize.runs");
            met = R.Evaluations.Feasible;
            testCase.verifyEqual(runs.XData(:), R.Evaluations.theta(met));
            missed = findobj(panel.Axes, Tag="dlab.optimize.missed");
            testCase.verifyEqual(numel(missed.XData), nnz(~met), "Angles that fly too high are drawn apart.");
            testCase.verifyEqual(findobj(panel.Axes, Tag="dlab.optimize.best").XData, R.Best);
            testCase.verifyEqual(string(panel.Axes.XLabel.String), "Launch angle (deg)");
            testCase.verifyTrue(contains(panel.NoteLabel.Text, "meets Maximum height ≤ 40 m"));
        end

        function unmetConstraintIsAWarning(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            p = plugin.defaultParams();
            p.findOptimal = false;
            panel = dlab.core.OptimizePanel(testCase.Figure, plugin.parameters(), @() p, testCase.Theme);
            R = dlab.core.Optimizer.run(plugin, p, "theta", "Range", ...
                Constraint=struct("Metric", "Maximum height", "Type", ">=", "Value", 1000));
            panel.show(R);
            testCase.verifyEqual(panel.NoteLabel.FontColor, testCase.Theme.Warning);
            testCase.verifyTrue(contains(panel.NoteLabel.Text, "NO run met"));
        end

        function badRequestsAreExplained(testCase)
            panel = testCase.newPanel();
            testCase.solveOnce(panel);
            panel.configure(["x0" "omega"], "Peak displacement");
            panel.InputDropdowns(2).Value = "x0";
            testCase.verifyError(@() panel.request(), "dlab:optimize:inputs");
            panel.configure("zeta", "Peak displacement", Bounds=[0 2]);
            testCase.verifyError(@() panel.request(), "dlab:optimize:range");
            testCase.verifyError(@() panel.configure("showEnvelope", "Peak displacement"), "dlab:optimize:inputs");
        end

        function runningTurnsTheButtonIntoCancel(testCase)
            panel = testCase.newPanel();
            testCase.solveOnce(panel);
            R = dlab.core.Optimizer.run(testCase.Plugin, testCase.Plugin.defaultParams(), "x0", ...
                "Peak displacement", Goal="minimize", Bounds=[-1 2]);
            panel.show(R);
            panel.setRunning(true);
            testCase.verifyEqual(string(panel.RunButton.Text), "■  Cancel");
            testCase.verifyEqual(string(panel.ApplyButton.Enable), "off");
            testCase.verifyEqual(string(panel.InputDropdowns(1).Enable), "off");
            panel.setRunning(false);
            testCase.verifyEqual(string(panel.RunButton.Text), "▶  Optimize");
            testCase.verifyEqual(string(panel.ApplyButton.Enable), "on");
        end

        function snapshotRestoresThePanel(testCase)
            panel = testCase.newPanel();
            testCase.solveOnce(panel);
            panel.configure(["x0" "zeta"], "Final displacement", Goal="minimize", Bounds=[-1 2; 0 0.5], ...
                Constraint=struct("Metric", "Peak displacement", "Type", ">=", "Value", 0.5));
            R = dlab.core.Optimizer.run(testCase.Plugin, testCase.Plugin.defaultParams(), ["x0" "zeta"], ...
                "Final displacement", Goal="minimize", Bounds=[-1 2; 0 0.5], MaxEvaluations=20);
            panel.show(R);
            state = panel.snapshot();
            job = panel.request();
            delete(panel.Grid);

            again = testCase.newPanel(state);
            testCase.verifyEqual(again.request(), job);
            testCase.verifyEqual(again.Result, R);
            testCase.verifyEqual(string(again.NoteLabel.Text), R.Message);
            testCase.verifyEqual(again.snapshot(), state);
        end

        function noNumericInputsDisablesTheTab(testCase)
            specs = dlab.core.ParamSpec("mode", Type="choice", Choices=["a" "b"], Default="a");
            panel = dlab.core.OptimizePanel(testCase.Figure, specs, @() struct("mode", "a"), testCase.Theme);
            testCase.verifyEqual(string(panel.RunButton.Enable), "off");
            testCase.verifyError(@() panel.request(), "dlab:optimize:inputs");
        end
    end

    methods (Access = private)
        function panel = newPanel(testCase, saved)
            arguments
                testCase
                saved = []
            end
            plugin = testCase.Plugin;
            panel = dlab.core.OptimizePanel(testCase.Figure, plugin.parameters(), ...
                @() plugin.defaultParams(), testCase.Theme, saved);
        end

        function solveOnce(testCase, panel)
            % What the view does after every run.
            plugin = testCase.Plugin;
            panel.setMetrics(plugin.metrics(plugin.solve(plugin.defaultParams())));
        end
    end
end
