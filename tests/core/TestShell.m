classdef (TestTags = {'ui'}) TestShell < matlab.unittest.TestCase
    %TESTSHELL End-to-end flows through the app window, using the toy plugin.

    properties
        App
        UserData
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function launch(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.UserData = string(temp.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, testCase.UserData));
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Theme="dark", Visible=false);
            testCase.addTeardown(@() closeIfOpen(testCase.App));
        end
    end

    methods
        function c = find(testCase, tag)
            c = findall(testCase.App.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end

        function press(testCase, tag)
            b = testCase.find(tag);
            b.ButtonPushedFcn(b, []);
        end

        function edit(testCase, name, value)
            field = testCase.find("dlab.param." + name);
            field.Value = value;
            field.ValueChangedFcn(field, []);
        end

        function text = status(testCase)
            text = string(testCase.find("dlab.status").Text);
        end

        function duringRun(testCase, fraction)
            % While the toy solve runs: other actions are ignored, Run cancels.
            if fraction == 0.25
                testCase.press("dlab.home");
                testCase.verifyClass(testCase.App.View, "dlab.core.SimulatorView", "Home is ignored while busy.");
                testCase.verifyTrue(testCase.App.View.IsBusy);
                testCase.verifyEqual(string(testCase.find("dlab.run").Text), "■  Cancel");
            elseif fraction == 0.5
                testCase.press("dlab.run");
            end
        end

        function cancelSecondRun(testCase, fraction)
            % Called by the toy solve: the sweep's own button cancels it.
            solves = testCase.App.View.Plugin.SolveCount;
            if solves == 2 && fraction == 0.5
                testCase.press("dlab.sweep.run");
            end
        end

        function pressKeyAt(testCase, fraction, when, key)
            if fraction == when
                testCase.pressKey(key);
            end
        end

        function closeAt(testCase, fraction, when)
            if fraction == when
                testCase.App.close();
                testCase.verifyTrue(isvalid(testCase.App.Figure), "Closing waits for the task.");
            end
        end

        function pressKey(testCase, key, modifiers)
            arguments
                testCase
                key (1,1) string
                modifiers cell = {}
            end
            fig = testCase.App.Figure;
            fig.WindowKeyPressFcn(fig, struct("Key", key, "Modifier", {modifiers}));
        end
    end

    methods (Test)
        function homeListsSimulatorsAndOpensThem(testCase)
            testCase.verifyClass(testCase.App.View, "dlab.core.HomeView");
            testCase.verifyEqual(string(testCase.find("dlab.home").Visible), "off");
            testCase.press("dlab.open.toy");
            testCase.verifyClass(testCase.App.View, "dlab.core.SimulatorView");
            testCase.verifyEqual(string(testCase.App.Figure.Name), "Dynamics Lab — Toy Oscillator");
            testCase.verifyEqual(testCase.App.View.tabTitles(), ...
                ["Animation" "Displacement" "Phase" "Analyze"]);
            testCase.verifyEqual(testCase.App.View.analysisTitles(), ...
                ["Custom plot" "Sweep" "Map" "Optimize" "Uncertainty" "Fit" "Modes"], ...
                "The analysis tools sit inside Analyze (no Bode: the toy has no inputs to drive).");
            testCase.App.View.selectTab("Modes");
            testCase.verifyEqual(string(testCase.App.View.Tabs.SelectedTab.Title), "Analyze");
            testCase.verifyEqual(testCase.App.View.currentTab(), "Modes");
            testCase.press("dlab.home");
            testCase.verifyClass(testCase.App.View, "dlab.core.HomeView");
        end

        function runShowsResultsSummaryAndPlayback(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");
            view = testCase.App.View;
            testCase.verifyNotEmpty(view.Result);
            testCase.verifyMatches(testCase.status(), "^Solved in \d+\.\d\d s · 501 samples$");
            testCase.verifyEqual(view.tabTitles(), ...
                ["Animation" "Displacement" "Phase" "Summary" "Analyze"]);
            summary = testCase.find("dlab.summary");
            testCase.verifyEqual(summary.Data.Quantity(1), "Peak displacement");
            testCase.verifyEqual(view.Playback.EndTime, 5);
            testCase.verifyEqual(string(testCase.find("dlab.playback.play").Enable), "on");

            view.Playback.pause();
            view.selectTab("Phase");              % no auto-play when the animation is hidden
            testCase.press("dlab.run");
            testCase.verifyFalse(view.Playback.IsPlaying);
        end

        function invalidInputIsReportedNotThrown(testCase)
            testCase.App.open("toy");
            testCase.find("dlab.group.Simulation").ButtonPushedFcn([], []);
            testCase.edit("dt", 10);                 % larger than the duration
            testCase.press("dlab.run");
            testCase.verifyEqual(testCase.status(), "Output step must be smaller than the duration.");
            testCase.verifyEmpty(testCase.App.View.Result);
            testCase.verifyEqual(string(testCase.find("dlab.run").Enable), "on");
        end

        function editsMarkCustomAndStale(testCase)
            testCase.App.open("toy");
            preset = testCase.find("dlab.preset");
            testCase.verifyEqual(preset.Value, "defaults");
            testCase.press("dlab.run");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");

            testCase.edit("duration", 8);            % MarksCustom = false
            testCase.verifyEqual(preset.Value, "defaults");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "on");
            testCase.edit("zeta", 0.4);
            testCase.verifyEqual(preset.Value, "custom");
            testCase.verifyEqual(testCase.App.View.Preset, "Custom");
            testCase.press("dlab.run");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
        end

        function displaySettingsRedrawWithoutStaleness(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");
            envelope = findall(testCase.App.Figure, Type="line", LineStyle="--");
            testCase.assertNumElements(envelope, 1);
            testCase.verifyGreaterThan(numel(envelope.XData), 1);
            testCase.edit("showEnvelope", false);
            testCase.verifyTrue(all(isnan(envelope.XData)), "Envelope hidden immediately.");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
            testCase.verifyEqual(testCase.find("dlab.preset").Value, "defaults");
            testCase.verifyFalse(testCase.App.View.RunParams.showEnvelope);
        end

        function coupledParameterHookRuns(testCase)
            testCase.App.open("toy");
            testCase.edit("drive", "forced");
            testCase.verifyEqual(testCase.App.View.params().dt, 0.005);
        end

        function presetsApplyAndResetRestoresDefaults(testCase)
            testCase.App.open("toy");
            preset = testCase.find("dlab.preset");
            testCase.verifyEqual(string(preset.Items), ["Defaults" "Light damping" "Heavy damping" "Custom"]);
            preset.Value = "builtin:Heavy damping";
            preset.ValueChangedFcn(preset, []);
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.7);
            testCase.verifyEqual(testCase.find("dlab.param.x0").Value, 2);
            testCase.press("dlab.run");
            testCase.press("dlab.reset");
            testCase.verifyEqual(testCase.App.View.params(), dlab.core.ParamSpec.defaults( ...
                dlabtest.ToyOscillatorPlugin().parameters()));
            testCase.verifyEmpty(testCase.App.View.Result);
            testCase.verifyEqual(preset.Value, "defaults");
            testCase.verifyEqual(testCase.App.View.tabTitles(), ...
                ["Animation" "Displacement" "Phase" "Analyze"]);
        end

        function stateSurvivesHomeAndThemeSwitch(testCase)
            testCase.App.open("toy");
            testCase.edit("zeta", 0.25);
            testCase.press("dlab.run");
            testCase.verifyTrue(testCase.App.View.Playback.IsPlaying, "Run auto-plays the animation.");
            testCase.App.View.Playback.pause();
            testCase.App.View.Playback.seek(2.5);
            testCase.App.goHome();
            testCase.App.open("toy");
            testCase.verifyEqual(testCase.status(), "Restored your previous inputs and result.");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.25);
            testCase.verifyEqual(testCase.App.View.Playback.Time, 2.5);

            testCase.press("dlab.theme");
            testCase.verifyEqual(testCase.App.Theme.Name, "light");
            testCase.verifyEqual(testCase.App.Figure.Color, dlab.ui.Theme.light().Background);
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.25);
            testCase.verifyNotEmpty(testCase.App.View.Result);
            testCase.verifyEqual(testCase.App.View.Playback.Time, 2.5);
            testCase.verifyEqual(string(dlab.core.Settings.get("theme")), "light");
        end

        function scenariosSaveAndLoad(testCase)
            testCase.App.open("toy");
            testCase.edit("zeta", 0.33);
            file = fullfile(dlab.core.Paths.scenarios("toy"), "My test.json");
            testCase.App.View.saveScenario(file);
            preset = testCase.find("dlab.preset");
            testCase.verifyTrue(ismember("My: My test", string(preset.Items)));

            testCase.press("dlab.reset");
            testCase.App.View.loadScenario(file);
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.33);
            testCase.verifyEqual(testCase.App.View.Preset, "My test");
            testCase.verifyEqual(preset.Value, "user:" + file);
        end

        function exportsWriteFiles(testCase)
            testCase.App.open("toy");
            view = testCase.App.View;
            view.exportData("csv", fullfile(testCase.UserData, "early.csv"));
            testCase.verifyEqual(testCase.status(), "Run the simulation first.");

            testCase.press("dlab.run");
            csvFile = fullfile(testCase.UserData, "out.csv");
            view.exportData("csv", csvFile);
            header = readlines(csvFile);
            testCase.verifyEqual(header(1), "t [s],x [m],v [m/s]");

            matFile = fullfile(testCase.UserData, "out.mat");
            view.exportData("mat", matFile);
            saved = load(matFile);
            testCase.verifyEqual(sort(string(fieldnames(saved)))', ["data" "metadata" "result" "scenario"]);
            testCase.verifyEqual(string(saved.scenario.simulator), "toy");

            view.selectTab("Phase");
            pngFile = fullfile(testCase.UserData, "phase.png");
            view.exportPlot(pngFile);
            testCase.verifyTrue(isfile(pngFile));
            view.selectTab("Summary");
            view.exportPlot(fullfile(testCase.UserData, "none.png"));
            testCase.verifyEqual(testCase.status(), "Select a plot tab to export it.");
        end

        function playbackTimersAreCleanedUp(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");          % auto-plays: Animation tab is showing
            testCase.verifyNotEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
            pause(0.2);
            testCase.verifyGreaterThan(testCase.App.View.Playback.Time, 0);
            testCase.App.goHome();
            testCase.verifyEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
            testCase.App.open("toy");
            testCase.press("dlab.playback.play");
            testCase.verifyTrue(testCase.App.View.Playback.IsPlaying);
            testCase.App.close();
            testCase.verifyEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
            testCase.verifyFalse(isvalid(testCase.App.Figure));
        end

        function keyboardShortcutsRunAndControlPlayback(testCase)
            testCase.App.open("toy");
            testCase.pressKey("r", {'control'});
            view = testCase.App.View;
            testCase.verifyNotEmpty(view.Result);
            view.Playback.pause();
            view.Playback.seek(1);
            frame = dlab.core.PlaybackController.FramePeriod;
            testCase.pressKey("rightarrow");
            testCase.verifyEqual(view.Playback.Time, 1 + frame, AbsTol=1e-12);
            testCase.pressKey("leftarrow", {'shift'});
            testCase.verifyEqual(view.Playback.Time, 1 - 9 * frame, AbsTol=1e-12);
            testCase.pressKey("home");
            testCase.verifyEqual(view.Playback.Time, 0);
            testCase.pressKey("space");
            testCase.verifyTrue(view.Playback.IsPlaying);
            testCase.pressKey("space");
            testCase.verifyFalse(view.Playback.IsPlaying);
        end

        function undoAndRedoInputChanges(testCase)
            testCase.App.open("toy");
            undo = testCase.find("dlab.undo");
            testCase.verifyEqual(string(undo.Enable), "off");
            testCase.edit("zeta", 0.4);
            testCase.edit("x0", 2);
            testCase.verifyEqual(string(undo.Enable), "on");
            testCase.press("dlab.undo");
            testCase.verifyEqual(testCase.App.View.params().x0, 1);
            testCase.verifyEqual(testCase.status(), "Undo: Initial displacement");
            testCase.pressKey("z", {'control'});
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.1);
            testCase.verifyEqual(testCase.find("dlab.preset").Value, "defaults");
            testCase.verifyEqual(testCase.find("dlab.param.zeta").Value, 0.1);
            testCase.pressKey("y", {'control'});
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.4);
            testCase.verifyEqual(testCase.find("dlab.preset").Value, "custom");

            % A preset is one undo step; a new edit clears redo.
            preset = testCase.find("dlab.preset");
            preset.Value = "builtin:Heavy damping";
            preset.ValueChangedFcn(preset, []);
            testCase.press("dlab.undo");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.4);
            testCase.edit("zeta", 0.2);
            testCase.verifyEqual(string(testCase.find("dlab.redo").Enable), "off");
        end

        function undoingBackToTheRunInputsClearsStale(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");
            testCase.edit("zeta", 0.3);
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "on");
            testCase.press("dlab.undo");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
        end

        function historySurvivesGoingHome(testCase)
            testCase.App.open("toy");
            testCase.edit("zeta", 0.3);
            testCase.App.goHome();
            testCase.App.open("toy");
            testCase.press("dlab.undo");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.1);
        end

        function cancelStopsARun(testCase)
            testCase.App.open("toy");
            view = testCase.App.View;
            view.Plugin.OnProgress = @(fraction) testCase.duringRun(fraction);
            testCase.press("dlab.run");
            testCase.verifyEmpty(view.Result);
            testCase.verifyFalse(view.IsBusy);
            testCase.verifyEqual(testCase.status(), "Run cancelled.");
            testCase.verifyEmpty(testCase.App.LastError);
            testCase.verifyEqual(string(testCase.find("dlab.run").Text), "▶  Run");
            testCase.verifyEqual(string(testCase.find("dlab.param.zeta").Enable), "on");
            testCase.verifyEqual(string(testCase.find("dlab.save").Enable), "on");
        end

        function escapeCancelsAndClosingWaitsForTheTask(testCase)
            testCase.App.open("toy");
            view = testCase.App.View;
            view.Plugin.OnProgress = @(fraction) testCase.pressKeyAt(fraction, 0.5, "escape");
            testCase.press("dlab.run");
            testCase.verifyEqual(testCase.status(), "Run cancelled.");

            view.Plugin.OnProgress = @(fraction) testCase.closeAt(fraction, 0.5);
            testCase.press("dlab.run");
            testCase.verifyFalse(isvalid(testCase.App.Figure), "The window closed once the run stopped.");
        end

        function scenarioOptionOpensItsSimulator(testCase)
            testCase.App.open("toy");
            testCase.edit("zeta", 0.45);
            file = fullfile(testCase.UserData, "half.json");
            testCase.App.View.saveScenario(file);
            testCase.App.close();
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Scenario=file, Visible=false);
            testCase.verifyClass(testCase.App.View, "dlab.core.SimulatorView");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.45);
        end

        function customPlotOffersEveryColumn(testCase)
            testCase.App.open("toy");
            x = testCase.find("dlab.customplot.x");
            testCase.verifyEqual(string(x.Enable), "off");
            testCase.press("dlab.run");
            testCase.verifyEqual(string(x.Items), ["t (s)" "x (m)" "v (m/s)"]);
            y = testCase.find("dlab.customplot.y");
            testCase.verifyEqual(y.Value, "x");
            y.Value = "v";
            y.ValueChangedFcn(y, []);
            line = findobj(testCase.find("dlab.customplot.axes"), Type="line");
            testCase.verifyEqual(line.YData(:), testCase.App.View.Result.v);
            testCase.App.goHome();
            testCase.App.open("toy");
            testCase.verifyEqual(testCase.find("dlab.customplot.y").Value, "v", "The choice is kept.");
        end

        function sweepRunsFromItsTab(testCase)
            testCase.App.open("toy");
            parameter = testCase.find("dlab.sweep.parameter");
            parameter.Value = "x0";
            parameter.ValueChangedFcn(parameter, []);
            testCase.verifyEqual([testCase.find("dlab.sweep.from").Value testCase.find("dlab.sweep.to").Value], ...
                [0.5 1.5], "The suggested range brackets the current value.");
            testCase.find("dlab.sweep.from").Value = 1;
            testCase.find("dlab.sweep.to").Value = 3;
            testCase.find("dlab.sweep.steps").Value = 3;
            testCase.press("dlab.sweep.run");
            testCase.verifyEqual(testCase.status(), "Sweep done: 3 runs of Initial displacement.");
            metric = testCase.find("dlab.sweep.metric");
            testCase.verifyEqual(metric.Value, "Peak displacement");
            line = findobj(testCase.find("dlab.sweep.axes"), Type="line", Marker="o", LineStyle="-");
            testCase.verifyEqual(line.YData(:), [1; 2; 3], AbsTol=1e-12);
            testCase.verifyEmpty(testCase.App.View.Result, "A sweep leaves the main result alone.");

            file = fullfile(testCase.UserData, "sweep.csv");
            testCase.App.View.exportSweep(file);
            header = readlines(file);
            testCase.verifyTrue(startsWith(header(1), "x0 [m],PeakDisplacement [m]"));
        end

        function optimizeListsResultsBeforeTheFirstRun(testCase)
            testCase.App.open("toy");
            testCase.App.View.selectTab("Optimize");
            metric = testCase.find("dlab.optimize.metric");
            testCase.verifyTrue(ismember("Peak displacement", string(metric.ItemsData)), ...
                "The results are listed from one solve of the current inputs.");
            testCase.verifyEmpty(testCase.App.View.Result, "That solve is not shown as a run.");
            testCase.verifyEqual(string(testCase.App.LastError), strings(0, 0), "No error, and none to print.");
        end

        function simulatorsReopenAsTheyWereLeft(testCase)
            % The selected tab and the analysis set-ups last across Home and
            % across launches (results are not kept between launches).
            testCase.App.open("toy");
            testCase.App.View.selectTab("Map");
            set(testCase.find("dlab.map.x.steps"), Value=4);
            testCase.App.View.selectTab("Phase");
            testCase.App.goHome();
            testCase.App.open("toy");
            testCase.verifyEqual(string(testCase.App.View.Tabs.SelectedTab.Title), "Phase");

            testCase.App.close();
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Theme="dark", Visible=false);
            testCase.App.open("toy");
            view = testCase.App.View;
            testCase.verifyEqual(string(view.Tabs.SelectedTab.Title), "Phase", "The tab is remembered.");
            view.selectTab("Map");
            testCase.verifyEqual(testCase.find("dlab.map.x.steps").Value, 4, "So is the Map set-up.");
            testCase.verifyEmpty(view.Result, "Results start afresh.");
        end

        function textSizeAppliesEverywhereAndIsRemembered(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.textsize");
            testCase.verifyEqual(testCase.App.Theme.TextSize, "large");
            testCase.verifyEqual(testCase.find("dlab.param.zeta").FontSize, round(12 * 1.15));
            testCase.verifyClass(testCase.App.View, "dlab.core.SimulatorView", "The simulator stays open.");
            testCase.App.toggleTheme();
            testCase.verifyEqual(testCase.App.Theme.TextSize, "large", "A theme switch keeps the size.");
            testCase.App.close();
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Visible=false);
            testCase.verifyEqual(testCase.App.Theme.TextSize, "large", "Remembered between launches.");
        end

        function mapRunsFromItsTabAndAppliesACell(testCase)
            testCase.App.open("toy");
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.map.run"), ...
                "The Map panel is built when its tab is first shown.");
            testCase.App.View.selectTab("Map");
            x = testCase.find("dlab.map.x.parameter");
            testCase.verifyEqual(string(x.Value), "omega", "X starts on the first input, Y on the second.");
            testCase.verifyEqual(string(testCase.find("dlab.map.y.parameter").Value), "zeta");
            x.Value = "x0";
            x.ValueChangedFcn(x, []);
            testCase.verifyEqual([testCase.find("dlab.map.x.from").Value testCase.find("dlab.map.x.to").Value], ...
                [0.5 1.5], "The suggested range brackets the current value.");
            set(testCase.find("dlab.map.x.from"), Value=1);
            set(testCase.find("dlab.map.x.to"), Value=3);
            set(testCase.find("dlab.map.x.steps"), Value=3);
            set(testCase.find("dlab.map.y.from"), Value=0);
            set(testCase.find("dlab.map.y.to"), Value=0.2);
            set(testCase.find("dlab.map.y.steps"), Value=2);
            testCase.press("dlab.map.run");
            testCase.verifyEqual(testCase.status(), "Map done: 6 runs of Initial displacement and Damping ratio.");
            testCase.verifyEqual(string(testCase.find("dlab.map.quantity").Value), "Peak displacement");
            cells = testCase.find("dlab.map.cells");
            testCase.verifyEqual(cells.CData(1:2, 1:3), [1 2 3; 1 2 3], AbsTol=1e-12);
            testCase.verifyEmpty(testCase.App.View.Result, "A map leaves the main result alone.");

            cells.ButtonDownFcn(cells, struct("IntersectionPoint", [2.1 0.18 0]));
            p = testCase.App.View.params();
            testCase.verifyEqual([p.x0 p.zeta], [2 0.2], "A click uses the nearest grid point's inputs.");

            file = fullfile(testCase.UserData, "map.csv");
            testCase.App.View.exportMap(file);
            header = readlines(file);
            testCase.verifyTrue(startsWith(header(1), "x0 [m],zeta,PeakDisplacement [m]"));
        end

        function setValuedSweepsPlotEveryValue(testCase)
            testCase.App.open("toy");
            parameter = testCase.find("dlab.sweep.parameter");
            parameter.Value = "x0";
            parameter.ValueChangedFcn(parameter, []);
            testCase.find("dlab.sweep.from").Value = 1;
            testCase.find("dlab.sweep.to").Value = 2;
            testCase.find("dlab.sweep.steps").Value = 2;
            testCase.press("dlab.sweep.run");
            metric = testCase.find("dlab.sweep.metric");
            testCase.verifyTrue(ismember("set:Peaks", string(metric.ItemsData)));
            metric.Value = "set:Peaks";
            metric.ValueChangedFcn(metric, []);
            cloud = testCase.find("dlab.sweep.cloud");
            plugin = dlabtest.ToyOscillatorPlugin();
            peaks = plugin.distributions(plugin.solve(plugin.defaultParams())).Values{1};
            testCase.verifyEqual(numel(cloud.XData), 2 * numel(peaks), "Every peak of both runs.");
            testCase.verifyEqual(unique(cloud.XData(:))', [1 2]);

            file = fullfile(testCase.UserData, "peaks.csv");
            testCase.App.View.exportSweep(file);
            header = readlines(file);
            testCase.verifyTrue(startsWith(header(1), "x0 [m],Quantity,Value,Units"));
        end

        function sweepCanBeCancelled(testCase)
            testCase.App.open("toy");
            testCase.find("dlab.sweep.steps").Value = 3;
            testCase.App.View.Plugin.OnProgress = @(fraction) testCase.cancelSecondRun(fraction);
            testCase.press("dlab.sweep.run");
            testCase.verifyEqual(testCase.status(), "Sweep cancelled after 1 of 3 runs.");
            testCase.verifyEqual(string(testCase.find("dlab.sweep.run").Text), "▶  Run sweep");
        end

        function modesTabShowsTheLinearization(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");
            data = testCase.find("dlab.modes.table").Data;
            testCase.verifyEqual(string(data{1, 1}), "Oscillation");
            testCase.verifyEqual(data{1, 3}, 6.283, AbsTol=1e-3);
            testCase.verifyEqual(string(data{1, 7}), "Stable");
            testCase.verifyMatches(string(testCase.find("dlab.modes.note").Text), "^Linearized about rest");
            testCase.press("dlab.reset");
            testCase.verifyEmpty(testCase.find("dlab.modes.table").Data);
        end

        function keptRunsAreOverlaidAndListed(testCase)
            testCase.App.open("toy");
            keep = testCase.find("dlab.keepRuns");
            testCase.verifyEqual(string(keep.Visible), "on", "The toy plugin draws overlays.");
            keep.Value = true;
            keep.ValueChangedFcn(keep, []);
            testCase.press("dlab.run");
            testCase.verifyEmpty(testCase.App.View.Runs, "Nothing to keep before the first result.");
            testCase.edit("zeta", 0.4);
            testCase.press("dlab.run");
            view = testCase.App.View;
            testCase.verifyNumElements(view.Runs, 1);
            testCase.verifyEqual(view.Runs(1).Params.zeta, 0.1);
            testCase.verifyNumElements(findall(testCase.App.Figure, Tag="dlab.overlay"), 1);
            testCase.verifyEqual(view.tabTitles(), ["Animation" "Displacement" "Phase" "Summary" "Runs" ...
                "Analyze"]);
            runs = testCase.find("dlab.runs").Data;
            testCase.verifyEqual(string(runs(:, 1))', ["Run 1" "Current"]);
            testCase.verifyEqual(string(runs{1, 2}), "Damping ratio = 0.1");
            testCase.verifyEqual(string(runs{2, 2}), "(same inputs)");
            testCase.verifyNumElements(findobj(testCase.find("dlab.customplot.axes"), Type="line"), 2);

            testCase.press("dlab.theme");                 % rebuilt from the session
            testCase.verifyNumElements(testCase.App.View.Runs, 1);
            testCase.verifyNumElements(findall(testCase.App.Figure, Tag="dlab.overlay"), 1);

            keep = testCase.find("dlab.keepRuns");
            keep.Value = false;
            keep.ValueChangedFcn(keep, []);
            testCase.verifyEmpty(testCase.App.View.Runs);
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.overlay"));
            testCase.verifyFalse(ismember("Runs", testCase.App.View.tabTitles()));
        end

        function keptRunsAreLimitedAndResetClearsThem(testCase)
            testCase.App.open("toy");
            testCase.App.View.setKeepRuns(true);
            for k = 1:dlab.core.SimulatorView.MaxKeptRuns + 1
                testCase.press("dlab.run");
            end
            testCase.verifyNumElements(testCase.App.View.Runs, dlab.core.SimulatorView.MaxKeptRuns);
            testCase.press("dlab.run");
            testCase.verifyMatches(testCase.status(), "^Up to 12 runs can be kept");
            testCase.verifyNumElements(testCase.App.View.Runs, dlab.core.SimulatorView.MaxKeptRuns);

            file = fullfile(testCase.UserData, "runs.mat");
            testCase.App.View.exportData("mat", file);
            saved = load(file);
            testCase.verifyNumElements(saved.runs, dlab.core.SimulatorView.MaxKeptRuns);

            testCase.press("dlab.reset");
            testCase.verifyEmpty(testCase.App.View.Runs);
            testCase.verifyTrue(testCase.App.View.KeepRuns, "Reset keeps the option ticked.");
        end

        function animationExportsToVideo(testCase)
            testCase.App.open("toy");
            view = testCase.App.View;
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Type="uimenu", Text="Animation (GIF)…"));
            view.exportAnimation("gif", fullfile(testCase.UserData, "early.gif"));
            testCase.verifyEqual(testCase.status(), "Run the simulation first.");

            testCase.press("dlab.run");
            view.Playback.pause();
            view.Playback.seek(2);
            view.selectTab("Phase");
            gif = fullfile(testCase.UserData, "toy.gif");
            view.exportAnimation("gif", gif, MaxFrames=12);
            testCase.verifyNumElements(imfinfo(gif), 12);
            testCase.verifyMatches(testCase.status(), "^Exported toy\.gif \(12 frames at 15 fps, sped up");
            testCase.verifyEqual(string(view.Tabs.SelectedTab.Title), "Phase", "The tab is restored.");
            testCase.verifyEqual(view.Playback.Time, 2, "The playback position is restored.");

            if dlab.core.AnimationExporter.canWrite("mp4")
                mp4 = fullfile(testCase.UserData, "toy.mp4");
                view.exportAnimation("mp4", mp4, MaxFrames=10);
                testCase.verifyEqual(VideoReader(mp4).NumFrames, 10);
            end
        end

        function homeOffersRecentWorkAndSearch(testCase)
            testCase.App.open("toy");
            testCase.edit("zeta", 0.3);
            file = fullfile(dlab.core.Paths.scenarios("toy"), "Kept.json");
            testCase.App.View.saveScenario(file);
            testCase.App.goHome();
            testCase.verifyMatches(string(testCase.find("dlab.continue.toy").Text), "Toy Oscillator  ·  just now$");
            testCase.verifyMatches(string(testCase.find("dlab.recentScenario.1").Text), "^Kept  ·  Toy Oscillator");

            search = testCase.find("dlab.home.search");
            search.Value = "zebra";
            search.ValueChangedFcn(search, []);
            testCase.find("dlab.home.nomatch");
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.card.toy"));
            search.Value = "oscillator";
            search.ValueChangedFcn(search, []);
            testCase.find("dlab.card.toy");

            % After a restart, Continue brings back the inputs.
            testCase.App.close();
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Visible=false);
            testCase.press("dlab.continue.toy");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.3);
            testCase.verifyEqual(testCase.status(), "Restored your inputs from last time.");
            testCase.press("dlab.undo");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.1, "Restoring is one undo step.");

            testCase.App.goHome();
            testCase.press("dlab.recentScenario.1");
            testCase.verifyEqual(testCase.App.View.Preset, "Kept");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.3);
        end

        function homeWelcomesNewcomersUntilDismissed(testCase)
            testCase.find("dlab.welcome");
            testCase.verifyMatches(string(testCase.find("dlab.welcome.text").Text), "^1 interactive physics simulators");
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.welcome.lesson"), ...
                "No lesson button without lessons (the toy plugin has none).");
            search = testCase.find("dlab.home.search");
            search.Value = "toy";
            search.ValueChangedFcn(search, []);
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.welcome"), "Not among search results.");
            search.Value = "";
            search.ValueChangedFcn(search, []);
            testCase.press("dlab.welcome.dismiss");
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.welcome"));

            testCase.App.close();           % stays dismissed after a restart
            testCase.App = DynamicsLab(Plugins={@dlabtest.ToyOscillatorPlugin}, Visible=false);
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.welcome"));
            testCase.App.open("toy");
            testCase.App.showWelcome();     % the About dialog on Home offers it again
            testCase.verifyClass(testCase.App.View, "dlab.core.HomeView");
            testCase.find("dlab.welcome");
        end

        function homeCardsFillTheWindowWidth(testCase)
            fig = testCase.App.Figure;
            for widthAndColumns = [1000 3; 1300 3; 1400 4; 1800 5]'
                fig.Position(3) = widthAndColumns(1);
                testCase.App.View.resized();
                testCase.verifyEqual(testCase.App.View.Columns, widthAndColumns(2), ...
                    sprintf("Columns in a window %d px wide", widthAndColumns(1)));
                cards = testCase.find("dlab.card.toy").Parent;
                testCase.verifyNumElements(cards.ColumnWidth, widthAndColumns(2));
                banner = testCase.find("dlab.welcome").Parent;
                testCase.verifyEqual(banner.ColumnWidth{1}, widthAndColumns(2) * 300 + (widthAndColumns(2) - 1) * 16, ...
                    "The welcome is as wide as the cards.");
            end
        end

        function missingRecentScenariosDisappear(testCase)
            testCase.App.open("toy");
            file = fullfile(testCase.UserData, "gone.json");
            testCase.App.View.saveScenario(file);
            delete(file);
            testCase.App.goHome();
            testCase.verifyEmpty(findall(testCase.App.Figure, Tag="dlab.recentScenario.1"));
        end

        function pluginsCanRequestInputChanges(testCase)
            testCase.App.open("toy");
            testCase.press("dlab.run");
            plugin = testCase.App.View.Plugin;
            plugin.requestInputs(struct("zeta", 0.3, "x0", 2), "Try this");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.3);
            testCase.verifyEqual(testCase.find("dlab.param.zeta").Value, 0.3);
            testCase.verifyEqual(testCase.status(), "Try this: Damping ratio, Initial displacement");
            testCase.verifyEqual(testCase.find("dlab.preset").Value, "custom");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "on");
            testCase.press("dlab.undo");                      % one undo step
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.1);
            testCase.verifyEqual(testCase.App.View.params().x0, 1);
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");

            % MarksCustom=false keeps the preset; Display inputs redraw only.
            plugin.requestInputs(struct("duration", 6), "Longer");
            testCase.verifyEqual(testCase.find("dlab.preset").Value, "defaults");
            testCase.press("dlab.run");
            plugin.requestInputs(struct("showEnvelope", false), "Hide");
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
            testCase.verifyFalse(testCase.App.View.RunParams.showEnvelope);

            % Bad requests change nothing and say why.
            plugin.requestInputs(struct("zeta", 5), "Bad");
            testCase.verifyEqual(testCase.App.View.params().zeta, 0.1);
            testCase.verifySubstring(testCase.status(), "Damping ratio must be in");
            plugin.requestInputs(struct("nope", 1), "Bad");
            testCase.verifySubstring(testCase.status(), "no input named");

            % Requests go through onParamChanged like edits; what was asked for wins.
            plugin.requestInputs(struct("drive", "forced"), "Force it");
            testCase.verifyEqual(testCase.App.View.params().dt, 0.005);
            plugin.requestInputs(struct("drive", "free", "dt", 0.01), "Reset");
            plugin.requestInputs(struct("drive", "forced", "dt", 0.008), "Force, coarse");
            testCase.verifyEqual(testCase.App.View.params().dt, 0.008);
            testCase.verifyTrue(plugin.canRequestInputs());
        end

        function inputRequestsWithoutAViewAreIgnored(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            plugin.requestInputs(struct("zeta", 0.3), "Nobody listens");
            testCase.verifyTrue(plugin.canRequestInputs());
        end

        function unknownSimulatorIsAnError(testCase)
            testCase.verifyError(@() testCase.App.open("nope"), "dlab:unknownSimulator");
        end
    end
end

function closeIfOpen(app)
if isvalid(app) && isvalid(app.Figure)
    app.close();
end
end
