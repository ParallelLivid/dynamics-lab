classdef (TestTags = {'ui'}) TestFlybyPlugin < matlab.unittest.TestCase
    %TESTFLYBYPLUGIN The gravity-assist simulator in the app.

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
            testCase.App = DynamicsLab("flyby", Plugins={@dlab.sims.flyby.FlybyPlugin}, Visible=false);
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

        function ax = axesTitled(testCase, prefix)
            found = findall(testCase.App.Figure, Type="axes");
            titles = arrayfun(@(a) string(a.Title.String), found);
            ax = found(startsWith(titles, prefix));
        end
    end

    methods (Test)
        function voyagerLikeJupiterAssist(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Turning angle (integrated)"), ...
                testCase.metric("Turning angle (analytic)"), "AbsTol", 1e-4);
            testCase.verifyEqual(testCase.metric("Turning angle (analytic)"), 98.98, "AbsTol", 0.01);
            testCase.verifyGreaterThan(testCase.metric("Speed gained"), 10);
            testCase.verifyLessThan(abs(testCase.metric("Planet-frame speed change")), 1e-6);
            testCase.verifyEqual(testCase.metric("Perihelion before"), 1.02, "AbsTol", 0.01, "Launched from about 1 AU.");
            testCase.verifyEmpty(testCase.metric("Aphelion after"), "Unbound: left out of the metrics.");
            S = testCase.App.View.Plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyEqual(S.Display(S.Quantity == "Aphelion after"), "unbound: leaves the Sun");
            testCase.App.View.Playback.seek(testCase.App.View.Result.t(end) / 2);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function aheadLosesAndCloseTurnsMore(testCase)
            testCase.choosePreset("Slowing down: passing ahead of Venus");
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Speed gained"), -5);
            testCase.verifyLessThan(testCase.metric("Perihelion after"), testCase.metric("Perihelion before"));
            testCase.choosePreset("Close Jupiter pass (large turning angle)");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Turning angle (integrated)"), 150);
        end

        function earthFlybyRaisesTheAphelion(testCase)
            testCase.choosePreset("Earth flyby gaining speed (Galileo-like)");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Aphelion after"), 2 * testCase.metric("Aphelion before"));
        end

        function displayOptions(testCase)
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            % During playback: frames used to land on the animation's
            % deleted handles while it was rebuilt ("Invalid or deleted object").
            playback = testCase.App.View.Playback;
            playback.play();
            testCase.addTeardown(@() playback.pause());
            for k = 1:6                               % the timer fires at its own moments
                testCase.verifyWarningFree(@() plugin.requestInputs(struct("showSoi", mod(k, 2) == 0, ...
                    "showInset", mod(k, 2) == 0), "Display"));
            end
            plugin.requestInputs(struct("showSoi", true, "showInset", false), "Display");
            playback.pause();
            testCase.verifyEmpty(testCase.App.LastError);
            testCase.verifyNotEmpty(testCase.App.View.Result, "Display options keep the result.");
            ax = testCase.axesTitled("Jupiter frame");
            r = testCase.App.View.Result;
            testCase.verifyGreaterThan(ax.XLim(2), r.rSoi / r.R, "The sphere of influence is in view.");
            side = testCase.axesTitled("Around the Sun");
            testCase.verifyTrue(any(arrayfun(@(a) a.Visible == "off", side)), "The heliocentric inset is hidden.");
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; the pass choices fit their field
            % ("Behind the planet (gain speed)" was cut off).
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end
    end
end
