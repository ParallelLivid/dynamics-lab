classdef (TestTags = {'ui'}) TestUncertaintyPanel < matlab.unittest.TestCase
    %TESTUNCERTAINTYPANEL The "Uncertainty" tab: what it asks for, what it
    %   draws, and that it survives a rebuild.

    properties
        Figure
        Plugin
        Params
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
            testCase.Figure = uifigure(Visible="off");
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.Plugin = dlabtest.ToyOscillatorPlugin();
            testCase.Params = testCase.Plugin.defaultParams();
        end
    end

    methods (Test)
        function listsTheNumericInputs(testCase)
            panel = testCase.makePanel();
            data = panel.Table.Data;
            testCase.verifyEqual(size(data, 1), 7);
            testCase.verifyEqual(string(data{3, 2}), "Initial displacement (m)");
            testCase.verifyFalse(any([data{:, 1}]), "Nothing is varied until ticked.");
            testCase.verifyEqual(data(3, 3:5), {'uniform', 5, true});
            testCase.verifyError(@() panel.request(), "dlab:montecarlo:none");
            testCase.verifyEqual(panel.Table.Tag, 'dlab.uncertainty.inputs');
        end

        function requestReturnsTheTickedTolerances(testCase)
            panel = testCase.makePanel();
            % Listed in the inputs' order.
            tol = dlab.core.MonteCarlo.tolerance(["zeta" "x0"], Kind=["uniform" "normal"], ...
                Spread=[0.02 10], Relative=[false true]);
            panel.configure(flipud(tol), Samples=40, Seed=3);
            [request, samples, seed] = panel.request();
            testCase.verifyEqual(request, tol);
            testCase.verifyEqual([samples seed], [40 3]);

            % A percentage of a zero value is refused before anything runs.
            testCase.Params.x0 = 0;
            testCase.verifyError(@() panel.request(), "dlab:montecarlo:relative");
            testCase.verifyError(@() panel.configure(dlab.core.MonteCarlo.tolerance("nope")), ...
                "dlab:montecarlo:parameter");
        end

        function showsTheHistogramAndShares(testCase)
            panel = testCase.makePanel();
            tol = dlab.core.MonteCarlo.tolerance(["x0" "zeta"], Spread=[0.1 0.2]);
            panel.configure(tol, Samples=40);
            [request, samples, seed] = panel.request();
            R = dlab.core.MonteCarlo.run(testCase.Plugin, testCase.Params, request, Samples=samples, Seed=seed);
            panel.show(R);
            testCase.verifyEqual(panel.Quantity, "Peak displacement");
            testCase.verifyEqual(string(panel.QuantityDropdown.Enable), "on");
            testCase.verifyEqual(string(panel.ExportButton.Enable), "on");
            ax = panel.HistogramAxes;
            bars = findobj(ax, Tag="dlab.uncertainty.bars");
            testCase.verifyEqual(sum(bars.YData), 40, "Every run is in a bin.");
            testCase.verifyNotEmpty(findobj(ax, Tag="dlab.uncertainty.band"));
            testCase.verifyEqual(findobj(ax, Tag="dlab.uncertainty.nominal").Value, 1, AbsTol=1e-12);
            testCase.verifyEqual(findobj(ax, Tag="dlab.uncertainty.mean").Value, R.Mean(1));
            shares = findobj(panel.SensitivityAxes, Tag="dlab.uncertainty.shares");
            testCase.verifyEqual(shares.YData, [100 0], AbsTol=1e-6);
            testCase.verifyEqual(string(panel.SensitivityAxes.YTickLabel{1}), "Initial displacement");
            note = string(panel.NoteLabel.Text);
            testCase.verifyTrue(startsWith(note, "40 runs"), note);
            testCase.verifySubstring(note, sprintf("%d samples clipped to the input's range", sum(R.Clipped)));
            testCase.verifySubstring(note, "R² 1.00");

            panel.chooseQuantity("Final displacement");
            testCase.verifyEqual(findobj(panel.HistogramAxes, Tag="dlab.uncertainty.mean").Value, R.Mean(2));
            testCase.verifyEqual(string(panel.QuantityDropdown.Value), "Final displacement");
            testCase.verifyEqual(numel(findobj(panel.SensitivityAxes, Tag="dlab.uncertainty.shares")), 1);
        end

        function notesFailedRuns(testCase)
            testCase.Params.dt = 0.04;
            testCase.Params.duration = 0.05;
            panel = testCase.makePanel();
            panel.configure(dlab.core.MonteCarlo.tolerance("duration", Spread=0.03, Relative=false), Samples=20);
            [request, samples, seed] = panel.request();
            R = dlab.core.MonteCarlo.run(testCase.Plugin, testCase.Params, request, Samples=samples, Seed=seed);
            panel.show(R);
            testCase.verifySubstring(string(panel.NoteLabel.Text), sprintf("%d failed", nnz(R.Errors ~= "")));
        end

        function runButtonDoublesAsCancel(testCase)
            panel = testCase.makePanel();
            fired = 0;
            l = addlistener(panel, "RunRequested", @(~, ~) count());
            testCase.addTeardown(@() delete(l));
            panel.RunButton.ButtonPushedFcn(panel.RunButton, []);
            testCase.verifyEqual(fired, 1);
            panel.setRunning(true);
            testCase.verifySubstring(string(panel.RunButton.Text), "Cancel");
            panel.setRunning(false);
            testCase.verifySubstring(string(panel.RunButton.Text), "Run Monte Carlo");

            function count()
                fired = fired + 1;
            end
        end

        function snapshotRestoresThePanel(testCase)
            panel = testCase.makePanel();
            panel.configure(dlab.core.MonteCarlo.tolerance("x0", Kind="normal", Spread=0.05), Samples=12, Seed=9);
            [request, samples, seed] = panel.request();
            R = dlab.core.MonteCarlo.run(testCase.Plugin, testCase.Params, request, Samples=samples, Seed=seed);
            panel.show(R);
            panel.chooseQuantity("Final displacement");
            state = panel.snapshot();
            delete(panel.Grid);

            again = dlab.core.UncertaintyPanel(testCase.Figure, testCase.Plugin.parameters(), ...
                @() testCase.Params, dlab.ui.Theme.dark(), state);
            [request2, samples2, seed2] = again.request();
            testCase.verifyEqual(request2, request);
            testCase.verifyEqual([samples2 seed2], [12 9]);
            testCase.verifyEqual(again.Quantity, "Final displacement");
            testCase.verifyEqual(again.Result, R);
        end

        function badSpreadEditsAreUndone(testCase)
            panel = testCase.makePanel();
            data = panel.Table.Data;
            data{1, 4} = -2;
            panel.Table.Data = data;
            event = struct("Indices", [1 4], "NewData", -2, "PreviousData", 5);
            panel.Table.CellEditCallback(panel.Table, event);
            testCase.verifyEqual(panel.Table.Data{1, 4}, 5);
            testCase.verifyFalse(panel.Table.Data{1, 1});
            event = struct("Indices", [2 3], "NewData", 'normal', "PreviousData", 'uniform');
            panel.Table.CellEditCallback(panel.Table, event);
            testCase.verifyTrue(panel.Table.Data{2, 1}, "Changing a tolerance ticks Vary.");
        end

        function noInputsDisablesTheTab(testCase)
            specs = testCase.Plugin.parameters();
            specs = specs(~ismember([specs.Type], ["double" "integer"]));
            panel = dlab.core.UncertaintyPanel(testCase.Figure, specs, @() testCase.Params, dlab.ui.Theme.dark());
            testCase.verifyEqual(string(panel.RunButton.Enable), "off");
            testCase.verifyError(@() panel.request(), "dlab:montecarlo:none");
        end
    end

    methods (Access = private)
        function panel = makePanel(testCase)
            panel = dlab.core.UncertaintyPanel(testCase.Figure, testCase.Plugin.parameters(), ...
                @() testCase.Params, dlab.ui.Theme.dark());
        end
    end
end
