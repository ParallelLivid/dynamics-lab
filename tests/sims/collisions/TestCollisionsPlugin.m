classdef (TestTags = {'ui'}) TestCollisionsPlugin < matlab.unittest.TestCase
    %TESTCOLLISIONSPLUGIN The billiards and gas collisions simulator in the app.

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
            testCase.App = DynamicsLab("collisions", Visible=false);
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
        function gasRelaxes(testCase)
            testCase.pressRun();
            testCase.verifyLessThan(testCase.metric("Energy drift (relative)"), 1e-9);
            testCase.verifyLessThan(testCase.metric("KS distance from Maxwell"), 0.08);
            testCase.verifyGreaterThan(testCase.metric("Collisions per disc"), 50);
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Type="histogram"));
            testCase.App.View.Playback.seek(10);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function denseGasPressure(testCase)
            testCase.choosePreset("Dense gas (pressure vs ideal)");
            testCase.pressRun();
            ratio = testCase.metric("Pressure ratio P / P_ideal");
            testCase.verifyGreaterThan(ratio, 1.2);
            % Henderson: (1 + η²/8) / (1 − η)² at η = 200 π 0.025² = 0.3927.
            eta = 200 * pi * 0.025^2;
            testCase.verifyEqual(testCase.metric("Henderson P / P_ideal"), (1 + eta^2 / 8) / (1 - eta)^2, RelTol=1e-12);
            % A box of 200 discs: the walls add about 7 % (my own simulations:
            % +7.2 % at r = 0.025 m, +3.6 % at 0.0125 m with 800 discs).
            testCase.verifyEqual(ratio, testCase.metric("Henderson P / P_ideal"), RelTol=0.12);
        end

        function brownianTracer(testCase)
            testCase.choosePreset("Brownian motion (heavy tracer)");
            testCase.pressRun();
            D = testCase.metric("Diffusion coefficient");
            % My own simulation of this gas (1500 s): D = 0.0080 m²/s; one
            % tracer over 60 s scatters by about ±50 % from seed to seed.
            testCase.verifyGreaterThan(D, 0.0015);
            testCase.verifyLessThan(D, 0.03);
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Type="uitab", Title="Tracer"));
            testCase.verifyEmpty(findall(testCase.App.Figure, Type="uitab", Title="Pressure"), "Periodic: no walls.");
            a = testCase.App.View.Result.analysis;
            testCase.verifyLessThanOrEqual(a.lags(end), 60 / 8 + 1e-9);
            testCase.verifyGreaterThan(a.fitFrom, 3, "D is fitted where the MSD is a straight line.");
            testCase.App.View.Playback.seek(30);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function twoBallsLeaveAtRightAngles(testCase)
            % Independent reference: the closed form for an elastic collision of equal masses.
            % Equal masses, e = 1, the line of centres at 30°: speeds sin 30°
            % and cos 30°, 90° apart.
            testCase.choosePreset("Two-ball oblique");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Angle between the paths after"), 90, AbsTol=1e-9);
            testCase.verifyEqual(testCase.metric("Moving ball's speed after"), 0.5, AbsTol=1e-12);
            testCase.verifyEqual(testCase.metric("Struck ball's speed after"), sqrt(3) / 2, AbsTol=1e-12);
            testCase.verifyEqual(testCase.metric("Time of the collision"), 1 - 0.2 * cosd(30), AbsTol=1e-12);
            fig = testCase.App.Figure;
            testCase.verifyEmpty(findall(fig, Type="uitab", Title="Speed distribution"), "Gas statistics: gas only.");
            testCase.verifyEmpty(findall(fig, Type="uitab", Title="Pressure"));
        end

        function inelasticGasPressureMatchesItsTemperature(testCase)
            % The pressure and kT come from the same (second) half of the
            % run: a cooling gas showed P / P_ideal = 5.4 before.
            testCase.choosePreset("Inelastic cooling (e = 0.9)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Pressure ratio P / P_ideal"), ...
                testCase.metric("Henderson P / P_ideal"), RelTol=0.15);
            % Haff's law, T = T0 / (1 + t/t0)², t0 = 4 / ((1 − e²) ω0) with
            % ω0 = 12.6 collisions per disc per second at the start: 97.95 %.
            testCase.verifyEqual(testCase.metric("Energy lost"), 97.95, AbsTol=1);
        end

        function axesAndSummaryStayReadable(testCase)
            testCase.pressRun();
            view = testCase.App.View;
            plugin = view.Plugin;
            ax = findall(testCase.App.Figure, Type="axes");
            energy = ax(arrayfun(@(a) isequal(string(a.Title.String), "Kinetic energy"), ax));
            testCase.verifyEqual(energy.YLim(1), 0, "Conserved KE is not zoomed into rounding.");
            speeds = ax(arrayfun(@(a) isequal(string(a.Title.String), "Speed distribution"), ax));
            testCase.verifyLessThan(speeds.YLim(2), 2, "The start's spike does not squash the histogram.");
            discs = ax(arrayfun(@(a) isequal(string(a.Title.String), "Discs"), ax));
            testCase.verifyGreaterThan(discs.YLim(2), 1.1, "Head room above the box for the readout.");
            % No motion: text, not NaN.
            p = plugin.defaultParams();
            [p.v0, p.tspan] = deal(0, 1);
            S = plugin.summaryTable(plugin.solve(p));
            testCase.verifyTrue(all(isfinite(S.Value) | S.Display ~= ""), "Nothing shows NaN or Inf.");
            % Two balls that miss.
            p = plugin.presetParams("Two-ball oblique");
            p.v0 = 0;
            S = plugin.summaryTable(plugin.solve(p));
            testCase.verifyTrue(all(isfinite(S.Value) | S.Display ~= ""));
            testCase.verifyTrue(all(S.Units == "" | ismember(S.Units, ["relative" "s" "m/s" "°" "J" "%" "m²/s"])), ...
                "Units only in the Units column.");
        end

        function billiardsAndCradle(testCase)
            testCase.choosePreset("Billiards break");
            testCase.pressRun();
            testCase.verifyGreaterThan(testCase.metric("Collisions"), 15);
            testCase.verifyGreaterThan(testCase.metric("Energy lost"), 0);
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("cueSpeed"));
            testCase.verifyFalse(panel.isRowShown("N"));
            testCase.choosePreset("Newton's cradle line (5 balls)");
            testCase.pressRun();
            r = testCase.App.View.Result;
            % The first ball's momentum runs down the line to the last one
            % (t = 0.6 s), which bounces off the wall (2.1 s) and sends it
            % back up the line (3.6 s): at the end only the first ball moves.
            before = find(r.t <= 2, 1, "last");
            testCase.verifyEqual(r.vx(before, :), [0 0 0 0 1], AbsTol=1e-12);
            testCase.verifyEqual(r.vx(end, :), [-1 0 0 0 0], AbsTol=1e-12);
        end
    end
end
