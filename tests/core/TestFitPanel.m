classdef (TestTags = {'ui'}) TestFitPanel < matlab.unittest.TestCase
    %TESTFITPANEL The Fit tab (dlab.core.FitPanel) and measured data on
    %   the Custom plot (dlab.core.PlotBuilder), in a hidden window.

    properties
        Figure
        Plugin
        Theme
        Data
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function open(testCase)
            testCase.Figure = uifigure(Visible="off");
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.Plugin = dlabtest.ToyOscillatorPlugin();
            testCase.Theme = dlab.ui.Theme.dark();
            time = (0:0.1:4)';
            p = testCase.Plugin.defaultParams();
            x = exp(-p.zeta * p.omega * time) .* cos(p.omega * sqrt(1 - p.zeta ^ 2) * time);
            testCase.Data = struct("File", "C:\data\ring.csv", "Name", "ring.csv", "Time", time, ...
                "Columns", ["x" "force"], "Units", ["m" "N"], "Values", [x 0 * x], "Dropped", 2, "Sorted", true);
        end
    end

    methods
        function panel = fitPanel(testCase, saved)
            arguments
                testCase
                saved = []
            end
            plugin = testCase.Plugin;
            panel = dlab.core.FitPanel(uigridlayout(testCase.Figure, [1 1]), plugin.parameters(), ...
                @() plugin.defaultParams(), testCase.Theme, saved);
        end

        function T = resultTable(testCase)
            plugin = testCase.Plugin;
            T = plugin.exportTable(plugin.solve(plugin.defaultParams()));
        end

        function c = find(testCase, tag)
            c = findall(testCase.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end
    end

    methods (Test)
        function startsEmptyWithTheFirstVisibleInput(testCase)
            panel = testCase.fitPanel();
            testCase.verifyEqual(string(testCase.find("dlab.fit.input1").Value), "omega");
            testCase.verifyEqual(string(testCase.find("dlab.fit.input2").Value), "");
            items = string(testCase.find("dlab.fit.input1").Items);
            testCase.verifyFalse(ismember("Envelope cycles", items), "Whole-number inputs are not offered.");
            testCase.verifyFalse(ismember("Show envelope", items));
            testCase.verifyEqual(string(panel.ApplyButton.Enable), "off");
            testCase.verifyError(@() panel.request(), "dlab:fit:noData");
            panel.load(testCase.Data);
            testCase.verifyError(@() panel.request(), "dlab:fit:noColumns");
        end

        function loadAndSetTableMatchColumns(testCase)
            panel = testCase.fitPanel();
            panel.load(testCase.Data);
            testCase.verifyEqual(string(testCase.find("dlab.fit.data").Text), ...
                "ring.csv · 41 rows · 2 dropped · sorted by time");
            testCase.verifyEqual(string(testCase.find("dlab.fit.measured").Items), ["x (m)" "force (N)"]);
            panel.setTable(testCase.resultTable());
            simulated = testCase.find("dlab.fit.simulated");
            testCase.verifyEqual(string(simulated.Items), ["x (m)" "v (m/s)"], "Time is not offered.");
            testCase.verifyEqual(string(simulated.Value), "x", "The column named like the measured one.");
            testCase.verifyNumElements(testCase.find("dlab.fit.measuredData").XData, 41);
            asked = panel.request();
            testCase.verifyEqual(asked.Inputs, "omega");
            testCase.verifyEqual(asked.Mapping, struct("Measured", "x", "Simulated", "x"));
            testCase.find("dlab.fit.input2").Value = "zeta";
            testCase.find("dlab.fit.input3").Value = "omega";
            testCase.verifyEqual(panel.request().Inputs, ["omega" "zeta"], "Repeats count once.");
            [testCase.find("dlab.fit.input1").Value, testCase.find("dlab.fit.input2").Value, ...
                testCase.find("dlab.fit.input3").Value] = deal("");
            testCase.verifyError(@() panel.request(), "dlab:fit:noInputs");
        end

        function showDrawsStartBestAndResiduals(testCase)
            panel = testCase.fitPanel();
            panel.load(testCase.Data);
            panel.setTable(testCase.resultTable());
            panel.configure("x", "x", "zeta");
            p = testCase.Plugin.defaultParams();
            p.zeta = 0.2;
            asked = panel.request();
            R = dlab.core.MeasuredData.fit(testCase.Plugin, p, testCase.Data, asked.Mapping, asked.Inputs);
            panel.show(R);
            testCase.verifyEqual(string(testCase.find("dlab.fit.apply").Enable), "on");
            testCase.verifyMatches(string(testCase.find("dlab.fit.note").Text), ...
                "^Fitted Damping ratio = 0\.1 ± \S+ · RMS 0\.126 → \S+ m · \d+ runs\. Converged\.$");
            best = testCase.find("dlab.fit.best");
            testCase.verifyEqual(best.Color, testCase.Theme.series(1));
            testCase.verifyNumElements(testCase.find("dlab.fit.start").XData, numel(R.Simulated.StartTime));
            residual = testCase.find("dlab.fit.residual");
            testCase.verifyEqual(residual.YData(:), R.Residuals.Value);
            testCase.verifyEqual(string(testCase.find("dlab.fit.axes").Legend.String), ...
                ["Start" "Best fit" "Measured: x"]);

            % Another measured column: the fit no longer applies to the plot.
            measured = testCase.find("dlab.fit.measured");
            measured.Value = "force";
            measured.ValueChangedFcn(measured, []);
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.fit.best"));
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.fit.residual"));
        end

        function eventsAndRunningState(testCase)
            panel = testCase.fitPanel();
            heard = strings(1, 0);
            for name = ["ImportRequested" "RunRequested" "ApplyRequested"]
                testCase.addTeardown(@delete, listener(panel, name, @(~, event) record(event.EventName)));
            end
            for tag = ["dlab.fit.import" "dlab.fit.run" "dlab.fit.apply"]
                button = testCase.find(tag);
                button.ButtonPushedFcn(button, []);
            end
            testCase.verifyEqual(heard, ["ImportRequested" "RunRequested" "ApplyRequested"]);
            panel.setRunning(true);
            testCase.verifyEqual(string(panel.RunButton.Text), "■  Cancel");
            testCase.verifyEqual(panel.RunButton.BackgroundColor, testCase.Theme.Danger);
            panel.setRunning(false);
            testCase.verifyEqual(string(panel.RunButton.Text), "▶  Fit");

            function record(name)
                heard(end+1) = string(name);
            end
        end

        function snapshotRestoresTheTab(testCase)
            panel = testCase.fitPanel();
            panel.load(testCase.Data);
            panel.setTable(testCase.resultTable());
            panel.configure("x", "v", ["zeta" "x0"]);
            R = dlab.core.MeasuredData.fit(testCase.Plugin, testCase.Plugin.defaultParams(), testCase.Data, ...
                struct("Measured", "x", "Simulated", "x"), "zeta", MaxEvaluations=5);
            panel.show(R);
            state = panel.snapshot();
            note = string(panel.NoteLabel.Text);
            delete(testCase.Figure.Children);
            again = testCase.fitPanel(state);
            testCase.verifyEqual(again.Data, testCase.Data);
            testCase.verifyEqual(string(again.SimulatedDropdown.Value), "v");
            testCase.verifyEqual(string({again.InputDropdowns.Value}), ["zeta" "x0" ""]);
            testCase.verifyEqual(again.Result, R);
            testCase.verifyEqual(string(again.NoteLabel.Text), note);
            testCase.verifyError(@() again.configure("x", "nope", "zeta"), "dlab:fit:choice");
        end

        function customPlotDrawsMeasuredMarkers(testCase)
            builder = dlab.core.PlotBuilder(uigridlayout(testCase.Figure, [1 1]), testCase.Theme);
            dropdown = testCase.find("dlab.customplot.measured");
            testCase.verifyEqual(string(dropdown.Enable), "off");
            builder.setMeasured(testCase.Data);         % before any result: nothing drawn yet
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.customplot.measuredData"));
            T = testCase.resultTable();
            kept = struct("Table", T, "Label", "Run 1", "Color", testCase.Theme.series(2));
            builder.show(T, kept);
            testCase.verifyEqual(string(dropdown.Value), "x", "The column named like Y.");
            markers = testCase.find("dlab.customplot.measuredData");
            testCase.verifyEqual(markers.YData(:), testCase.Data.Values(:, 1));
            testCase.verifyEqual(markers.Color, testCase.Theme.Text);
            testCase.verifyEqual(string(markers.LineStyle), "none");
            axes = testCase.find("dlab.customplot.axes");
            testCase.verifyNumElements(findobj(axes, Type="line"), 3, "Kept run, current run, measured.");
            testCase.verifyEqual(string(axes.Legend.String), ["Run 1" "Current run" "Measured: x"]);

            builder.choose("X", "v");                   % not time: no markers
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.customplot.measuredData"));
            builder.choose("X", "t");
            dropdown.Value = "";
            dropdown.ValueChangedFcn(dropdown, []);
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.customplot.measuredData"));
            testCase.verifyEqual(builder.Selection.Measured, "");
            builder.choose("Measured", "force");
            testCase.verifyNumElements(findall(testCase.Figure, Tag="dlab.customplot.measuredData"), 1);
            builder.clearMeasured();
            testCase.verifyEmpty(findall(testCase.Figure, Tag="dlab.customplot.measuredData"));
            testCase.verifyEqual(string(dropdown.Enable), "off");
            testCase.verifyNumElements(findobj(axes, Type="line"), 2, "The runs stay.");
        end

        function customPlotConvertsUnitsAndKeepsOldSelections(testCase)
            builder = dlab.core.PlotBuilder(uigridlayout(testCase.Figure, [1 1]), testCase.Theme, ...
                struct("X", "t", "Y", "x"));                % a snapshot from before measured data
            D = testCase.Data;
            D.Values(:, 1) = 1000 * D.Values(:, 1);
            D.Units(1) = "mm";
            builder.setMeasured(D);
            builder.show(testCase.resultTable());
            markers = testCase.find("dlab.customplot.measuredData");
            testCase.verifyEqual(markers.YData(:), testCase.Data.Values(:, 1), "Drawn in metres.", AbsTol=1e-12);
            testCase.verifyEqual(builder.Selection.Measured, "x");
        end
    end
end
