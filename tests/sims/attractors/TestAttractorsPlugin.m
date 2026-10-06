classdef (TestTags = {'ui'}) TestAttractorsPlugin < matlab.unittest.TestCase
    %TESTATTRACTORSPLUGIN The strange attractors simulator in the app.

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
            testCase.App = DynamicsLab("attractors", Visible=false);
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

        function ax = axesTitled(testCase, prefix)
            axs = findall(testCase.App.Figure, Type="axes");
            titles = arrayfun(@(a) string(a.Title.String), axs);
            ax = axs(startsWith(titles, prefix));
            testCase.assertNumElements(ax, 1);
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
        end
    end

    methods (Test)
        function butterflyIsChaotic(testCase)
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Largest Lyapunov exponent"), 0.9, AbsTol=0.1);
            testCase.verifyGreaterThan(testCase.metric("Distinct maxima"), 32);
            testCase.verifyLessThan(testCase.metric("Twins apart (10 % of the size)"), 40);
            testCase.verifyEqual(testCase.metric("Equilibria"), 3);
            testCase.verifySubstring(string(findall(testCase.App.Figure, Tag="dlab.status").Text), "chaotic");
            testCase.App.View.Playback.seek(50);
            testCase.verifyEmpty(testCase.App.LastError);
            D = testCase.App.View.Plugin.distributions(testCase.App.View.Result);
            testCase.verifyEqual(D.Quantity, "Maxima of z");
        end

        function inputsFollowTheSystem(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("rho"));
            testCase.verifyFalse(panel.isRowShown("c"));
            testCase.choosePreset("Rössler: period-2 (c = 3.5)");
            testCase.verifyTrue(panel.isRowShown("c"));
            testCase.verifyFalse(panel.isRowShown("rho"));
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Distinct maxima"), 2);
            testCase.verifySubstring(string(findall(testCase.App.Figure, Tag="dlab.status").Text), "periodic");
        end

        function fixedPointIsReported(testCase)
            testCase.choosePreset("Lorenz: settles to a fixed point (ρ = 14)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Settled at an equilibrium"), 1);
            testCase.verifyLessThan(testCase.metric("Largest Lyapunov exponent"), 0);
        end

        function modesAtTheEquilibrium(testCase)
            % Lorenz at ρ = 28: C+ has one stable direction and an unstable
            % spiral (the Hopf bifurcation was at ρ ≈ 24.74).
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            testCase.verifyEqual(sum(L.Modes.Mode == "Stable direction"), 1);
            testCase.verifyEqual(sum(L.Modes.Mode == "Unstable spiral (out)"), 1);
            testCase.verifyEqual(string(L.Modes.Properties.VariableUnits(7)), "time units", "Dimensionless time.");
            params = plugin.defaultParams();
            params.rho = 14;
            L = dlab.core.Linearization.analyze(plugin.linearization(params));
            testCase.verifyEqual(sum(startsWith(L.Modes.Mode, "Unstable")), 0, "Below the Hopf point, C+ is stable.");
        end

        function summaryRowsSayWhatTheyMean(testCase)
            % Units hold units only; a periodic orbit (λ ≈ 0.003, within the
            % estimate's accuracy of 0) has no "Lyapunov time" of 300; a
            % settled run says yes.
            plugin = testCase.App.View.Plugin;
            testCase.choosePreset("Rössler: period-2 (c = 3.5)");
            testCase.pressRun();
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyFalse(any(S.Quantity == "Lyapunov time (1/λ)"));
            testCase.verifyEqual(S.Units(S.Quantity == "Distinct maxima"), "");
            testCase.verifyEqual(S.Display(S.Quantity == "Settled at an equilibrium"), "no");
            testCase.choosePreset("Lorenz: settles to a fixed point (ρ = 14)");
            testCase.pressRun();
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyEqual(S.Display(S.Quantity == "Settled at an equilibrium"), "yes");
            testCase.verifyEqual(S.Display(S.Quantity == "Distinct maxima"), "— (settled)");
            % The twins become identical: the log plot stays on the data.
            ax = testCase.axesTitled("Distance");
            testCase.verifyGreaterThan(min(ylim(ax)), 1e-100);
            T = plugin.exportTable(testCase.App.View.Result);
            testCase.verifyFalse(any(contains(string(T.Properties.VariableUnits), "(")));
        end

        function periodicWindowIsPeriodic(testCase)
            % ρ = 160 is chaotic for its first 20 or so time units; with the
            % first half left out it is the two-maximum cycle.
            testCase.choosePreset("Lorenz: periodic window (ρ = 160)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Distinct maxima"), 2);
            testCase.verifyLessThan(abs(testCase.metric("Largest Lyapunov exponent")), 0.01);
            testCase.verifySubstring(string(findall(testCase.App.Figure, Tag="dlab.status").Text), "periodic");
        end

        function returnMapOfACycleIsADot(testCase)
            % Period-1: the axes span at least a tenth of the attractor,
            % not the 0.004 of its slow convergence.
            testCase.choosePreset("Rössler: period-1 (c = 2.5)");
            testCase.pressRun();
            ax = testCase.axesTitled("Return map");
            testCase.verifyGreaterThan(diff(xlim(ax)), 0.1 * testCase.App.View.Result.extent);
        end

        function chuaModesAtTheScrollCentre(testCase)
            % P+ = (1.5, 0, −1.5): an unstable spiral 0.3055 ± 4.5253i and a
            % stable direction −6.0726 (eigenvalues by hand, verification
            % sheet); the origin is a saddle the scrolls do not circle.
            plugin = testCase.App.View.Plugin;
            params = plugin.defaultParams();
            params.model = "chua";
            lin = plugin.linearization(params);
            testCase.verifyEqual(lin.X0, [1.5; 0; -1.5], AbsTol=1e-12);
            L = dlab.core.Linearization.analyze(lin);
            spiral = L.Modes(L.Modes.Mode == "Unstable spiral (out)", :);
            testCase.verifyEqual([spiral.Real spiral.Imaginary], [0.305496 4.525326], AbsTol=1e-5);
            testCase.verifyEqual(L.Modes.Real(L.Modes.Mode == "Stable direction"), -6.072592, AbsTol=1e-5);
            % Rössler with c² < 4ab has no equilibrium: no Modes.
            params.model = "rossler";
            [params.a, params.b, params.c] = deal(0.5, 2, 1);
            testCase.verifyEmpty(plugin.linearization(params));
        end

        function bifurcationSweepOverC(testCase)
            testCase.choosePreset("Rössler: period-1 (c = 2.5)");
            plugin = testCase.App.View.Plugin;
            params = testCase.App.View.params();
            S = dlab.core.Sweep.run(plugin, params, "c", [2.5 3.5]);
            testCase.verifyEqual(S.SetNames, "Maxima of x");
            counts = cellfun(@(v) numel(uniquetol(v, 1e-2)), S.SetData(:, 1));
            testCase.verifyEqual(counts, [1; 2], "Period-1, then period-2.");
        end
    end
end
