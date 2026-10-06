classdef (TestTags = {'ui'}) TestRigidBodyPlugin < matlab.unittest.TestCase
    %TESTRIGIDBODYPLUGIN The rigid-body rotation simulator in the app.

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
            testCase.App = DynamicsLab("rigidbody", Visible=false);
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
        function tennisRacketFlips(testCase)
            % I = 1, 2, 2.5 and ω = (0.001, 10, 0.001): the flips are half
            % a period of ω₂ apart, 2K(k)/rate = 4.95828 s (elliptic
            % functions, Landau & Lifshitz §37; my own integration agrees).
            testCase.choosePreset("Tennis racket (Dzhanibekov effect)");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Flips"), 4, "Zero crossings at 2.80, 7.76, 12.72, 17.68 s.");
            testCase.verifyEqual(testCase.metric("Time between flips"), 4.95828, RelTol=1e-4);
            testCase.verifyEqual(testCase.metric("Spin axis stable"), 0);
            testCase.verifyLessThan(testCase.metric("Energy drift (relative)"), 1e-9);
            testCase.App.View.Playback.seek(2);
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function defaultBodyIsARealBox(testCase)
            % 1, 2, 3 is a flat plate (I₃ = I₁ + I₂): the box had no thickness
            % and any smaller I₁ in a sweep or a study was no body at all.
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            I = [p.I1 p.I2 p.I3];
            testCase.verifyTrue(all(I < I([2 3 1]) + I([3 1 2])), "Strictly inside the triangle inequality.");
            for scale = [0.9 1.1]
                q = p;
                q.I1 = scale * p.I1;
                q.I3 = scale * p.I3;
                testCase.verifyWarningFree(@() plugin.solve(q));
            end
        end

        function intermediateAxisTumbles(testCase)
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(plugin.defaultParams()));
            tumble = L.Modes(L.Modes.Mode == "Tumble (unstable)", :);
            testCase.verifyEqual(height(tumble), 1);
            I = [1 2 2.5];
            growth = 10 * sqrt((I(2) - I(1)) * (I(3) - I(2)) / (I(1) * I(3)));
            testCase.verifyEqual(tumble.Real, growth, RelTol=1e-8);
            decaying = L.Modes(L.Modes.Mode == "Tumble (decaying)", :);
            testCase.verifyEqual(decaying.Real, -growth, "The saddle's other direction is not unstable.", RelTol=1e-8);
            testCase.verifyEqual(decaying.Stability, "Stable");
            testCase.verifyEqual(sum(L.Modes.Mode == "Spin (neutral)"), 1);
        end

        function stableSpinWobblesAtTheHandFrequency(testCase)
            % Independent reference: the closed-form wobble frequency of a spin about a principal axis.
            % Major axis: ω₃ √((I₃ − I₁)(I₃ − I₂)/(I₁ I₂)); minor axis:
            % ω₁ √((I₂ − I₁)(I₃ − I₁)/(I₂ I₃)).
            plugin = testCase.App.View.Plugin;
            I = [1 2 2.5];
            expected = [10 * sqrt((I(3) - I(1)) * (I(3) - I(2)) / (I(1) * I(2))), ...
                10 * sqrt((I(2) - I(1)) * (I(3) - I(1)) / (I(2) * I(3)))];
            names = ["Stable spin: major axis" "Stable spin: minor axis"];
            for k = 1:2
                testCase.choosePreset(names(k));
                L = dlab.core.Linearization.analyze(plugin.linearization(testCase.App.View.params()));
                wobble = L.Modes(L.Modes.Mode == "Wobble (stable)", :);
                testCase.verifyEqual(wobble.Imaginary, expected(k), names(k), RelTol=1e-8);
            end
        end

        function autoSpinAxisIsTheOneNearestL(testCase)
            % ω = (0, 5, 4.5) with I = 1, 2, 2.5: L = (0, 10, 11.25), so axis
            % 3, although ω₂ is the largest component.
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            [p.w1, p.w2, p.w3] = deal(0, 5, 4.5);
            r = plugin.solve(p);
            testCase.verifyEqual(r.spinAxis, 3);
        end

        function summaryRowsSayWhatTheyMean(testCase)
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            S = plugin.summaryTable(plugin.solve(p));
            testCase.verifyEqual(S.Display(S.Quantity == "Spin axis stable"), "no");
            testCase.verifyTrue(all(S.Units == "" | ismember(S.Units, ["relative" "s" "rad/s" "°"])), ...
                "Units only in the Units column.");
            % A symmetric body spun about a transverse axis: neutral, and no
            % intermediate axis to flip.
            [p.I1, p.I2, p.I3, p.w1, p.w2, p.w3] = deal(2, 2, 3, 10, 0, 0.01);
            S = plugin.summaryTable(plugin.solve(p));
            testCase.verifyEqual(S.Display(S.Quantity == "Spin axis stable"), "neutral (equal inertias)");
            testCase.verifyMatches(S.Display(S.Quantity == "Flips"), "^— \(two inertias equal");
            % The intermediate axis need not be axis 2.
            [p.I1, p.I2, p.I3, p.w1, p.w2, p.w3] = deal(2, 1, 2.5, 10, 0.001, 0.001);
            M = plugin.metrics(plugin.solve(p));
            testCase.verifyGreaterThanOrEqual(M.Value(M.Quantity == "Flips"), 1, "Axis 1 is the intermediate one.");
            testCase.verifyEqual(M.Value(M.Quantity == "Spin axis stable"), 0);
            % A top with no spin: no "Inf" gyroscopic estimate.
            p = plugin.defaultParams();
            [p.model, p.spin, p.tspan] = deal("top", 0, 1);
            S = plugin.summaryTable(plugin.solve(p));
            testCase.verifyEqual(S.Display(S.Quantity == "Gyroscopic estimate m g l / (I_s ω_s)"), "— (no spin)");
            testCase.verifyTrue(all(isfinite(S.Value) | S.Display ~= ""), "Nothing shows NaN or Inf.");
        end

        function steadyPrecessionIsTheSlowRoot(testCase)
            % I_t cos θ Ω² − I_s ω₃ Ω + m g l = 0 at θ = 30°: slow roots
            % 2.52132 (400 rad/s) and 5.57884 rad/s (200 rad/s); at 80 rad/s
            % there is none (the discriminant is negative).
            plugin = testCase.App.View.Plugin;
            p = plugin.defaultParams();
            p.model = "top";
            p.tspan = 0.5;
            for pair = [400 2.52132; 200 5.57884]'
                p.spin = pair(1);
                M = plugin.metrics(plugin.solve(p));
                testCase.verifyEqual(M.Value(M.Quantity == "Steady precession at the start tilt"), pair(2), RelTol=1e-5);
            end
            testCase.choosePreset("Spinning top: looping nutation");
            S = plugin.summaryTable(plugin.solve(testCase.App.View.params()));
            testCase.verifyEqual(S.Display(S.Quantity == "Steady precession at the start tilt"), ...
                "none: too slow at this tilt");
        end

        function floorOnlyWhenTheTopStaysAboveIt(testCase)
            % The looping top dips to 117°, below its tip: on a floor it
            % would go through it, so it stands on a post.
            stand = @() findall(testCase.App.Figure, Tag="dlab.rigidbody.stand");
            testCase.choosePreset("Spinning top: fast");
            testCase.pressRun();
            testCase.verifyEmpty(stand());
            floor = findall(testCase.App.Figure, Tag="dlab.rigidbody.floor");
            testCase.verifyEqual(unique(floor.ZData), 0);
            testCase.choosePreset("Spinning top: looping nutation");
            testCase.pressRun();
            testCase.verifyNotEmpty(stand());
            floor = findall(testCase.App.Figure, Tag="dlab.rigidbody.floor");
            testCase.verifyLessThan(max(floor.ZData(:)), -1.3, "Below the axle's tip even when hanging (1.3).");
        end

        function majorAxisWobbles(testCase)
            testCase.choosePreset("Stable spin: major axis");
            plugin = testCase.App.View.Plugin;
            L = dlab.core.Linearization.analyze(plugin.linearization(testCase.App.View.params()));
            testCase.verifyEqual(sum(L.Modes.Mode == "Wobble (stable)"), 1, "A conjugate pair is one mode.");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Flips"), 0);
            testCase.verifyEqual(testCase.metric("Spin axis stable"), 1);
        end

        function topPrecesses(testCase)
            testCase.choosePreset("Spinning top: fast");
            testCase.pressRun();
            testCase.verifyEqual(testCase.metric("Precession rate"), ...
                testCase.metric("Gyroscopic estimate m g l / (I_s ω_s)"), RelTol=0.05);
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Type="uitab", Title="Nutation and precession"));
            testCase.verifyEmpty(findall(fig, Type="uitab", Title="Polhode"));
            testCase.App.View.Playback.seek(1);
            testCase.verifyEmpty(testCase.App.LastError);
        end
    end
end
