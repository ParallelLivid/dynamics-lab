classdef (TestTags = {'ui'}) TestWavePlugin < matlab.unittest.TestCase
    %TESTWAVEPLUGIN The vibrating string and beam simulator in the app.

    properties
        App
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (TestMethodSetup)
        function launch(testCase)
            testCase.App = DynamicsLab("wave", Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function pressRun(testCase)
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.assertEmpty(testCase.App.LastError);
        end

        function choosePreset(testCase, name)
            dd = findall(testCase.App.Figure, Tag="dlab.preset");
            dd.Value = "builtin:" + name;
            dd.ValueChangedFcn(dd, []);
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
        end
    end

    methods (Test)
        function guitarStringIsHarmonic(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Fundamental frequency"), sqrt(70 / 0.0006) / 1.3, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("f2 / f1"), 2, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("f3 / f1"), 3, RelTol=1e-3);
            testCase.verifyEqual(testCase.metric("Dominant mode"), 1);
        end

        function middlePluckHasOnlyOddHarmonics(testCase)
            testCase.choosePreset("Pluck at the middle (odd harmonics)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Mode 2 energy share"), 0);
            testCase.verifyEqual(testCase.metric("Mode 4 energy share"), 0);
            testCase.verifyGreaterThan(testCase.metric("Mode 3 energy share"), 0.5);
        end

        function rulerOvertonesAreNotHarmonic(testCase)
            testCase.choosePreset("Cantilever beam (a ruler)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("f2 / f1"), 6.267, AbsTol=0.01);
            testCase.verifyEqual(testCase.metric("Fundamental frequency"), 9.06, AbsTol=0.01);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("beamBc"));
            testCase.verifyFalse(panel.isRowShown("tension"));
        end

        function everyTabIsDrawn(testCase)
            testCase.choosePreset("Free–free bar (a xylophone key)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Rigid-body modes"), 2);
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Type="image"), "Space-time heatmap.");
            testCase.verifyNotEmpty(findall(fig, Type="bar"), "Mode content.");
            testCase.App.View.Playback.seek(testCase.App.View.Result.t(end) / 2);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Clamped – fr…", "Strike (initial …", "String (te…").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function rulerSoundsMostlyItsFundamental(testCase)
            % Plucked from its static deflection, the ruler keeps 97 % of its
            % energy in mode 1 (the dominant mode was 18, a mesh artefact).
            testCase.choosePreset("Cantilever beam (a ruler)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Dominant mode"), 1);
            testCase.verifyGreaterThan(testCase.metric("Mode 1 energy share"), 97);
        end

        function nodesGiveExactlyNoEnergy(testCase)
            % A middle pluck: the even modes' shares read 0, not 3.6e-25 %;
            % the bar labels fit inside the axes.
            testCase.choosePreset("Pluck at the middle (odd harmonics)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Mode 2 energy share"), 0);
            bars = findall(testCase.App.Figure, Type="bar");
            content = ancestor(bars(1), "axes");
            testCase.verifyGreaterThanOrEqual(content.YLim(2), 1.2 * max(bars(1).YData));
        end
    end
end
