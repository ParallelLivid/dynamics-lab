classdef (TestTags = {'ui'}) TestMassSpringPlugin < matlab.unittest.TestCase
    %TESTMASSSPRINGPLUGIN Mass-spring in the shell: the original example CSVs
    %   and the behaviours of the original app's UI tests (TestMassSpringApp.m).

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
            testCase.App = DynamicsLab("massspring", Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function c = find(testCase, tag)
            c = findall(testCase.App.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end

        function set(testCase, name, value)
            field = testCase.find("dlab.param." + name);
            field.Value = value;
            field.ValueChangedFcn(field, []);
        end

        function choosePreset(testCase, name)
            dd = testCase.find("dlab.preset");
            dd.Value = "builtin:" + name;
            dd.ValueChangedFcn(dd, []);
        end

        function pressRun(testCase)
            b = testCase.find("dlab.run");
            b.ButtonPushedFcn(b, []);
            if ~isempty(testCase.App.View.Playback)
                testCase.App.View.Playback.pause();
                testCase.App.View.Playback.seek(testCase.App.View.Playback.StartTime);   % Run auto-plays; start from a known frame
            end
        end

        function ax = axesTitled(testCase, pattern)
            all = findall(testCase.App.Figure, Type="axes");
            ax = all(arrayfun(@(a) contains(string(a.Title.String), pattern), all));
            testCase.assertNumElements(ax, 1, pattern);
        end
    end

    methods (Test)
        function forcedSingleMatchesExampleCsv(testCase)
            % examples/single_forced_response.csv, row t = 7.99 s.
            testCase.choosePreset("Forced near resonance");
            testCase.pressRun();
            r = testCase.App.View.Result;
            k = find(abs(r.t - 7.99) < 1e-9);
            testCase.verifyEqual([r.x(k) r.v(k)], [-0.625311435396246 2.42267460498053], AbsTol=1e-7);
            testCase.verifyNumElements(r.t, 801);
        end

        function freeImpactMatchesReadme(testCase)
            testCase.choosePreset("Free impact (collision)");
            testCase.pressRun();
            r = testCase.App.View.Result;
            first = r.coll_log(1);
            testCase.verifyEqual(first.t, 0.916666666666667, AbsTol=1e-9);
            testCase.verifyEqual(string(first.type_str), "m1-m2 impact");
            after = first.post_idx;
            testCase.verifyEqual([r.v1(after) r.v2(after)], [-0.46 0.44], AbsTol=1e-9);
            testCase.verifyEqual(r.KE(after), 0.251, AbsTol=1e-9);
            momentum = 1 * r.v1 + 1.5 * r.v2;
            testCase.verifyEqual(momentum, 0.2 * ones(size(momentum)), AbsTol=1e-9);
            T = dlab.sims.massspring.MassSpringPlugin().exportTable(r);
            testCase.verifyEqual(T.event(after), "m1-m2 impact");
        end

        function modeSwitchShowsOnlyRelevantSections(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isGroupShown("Single mass"));
            testCase.verifyFalse(panel.isGroupShown("Coupled masses"));
            testCase.verifyFalse(panel.isGroupShown("Collisions"));
            testCase.set("mode", "coupled");
            testCase.verifyFalse(panel.isGroupShown("Single mass"));
            testCase.verifyFalse(panel.isGroupShown("Forcing"));
            testCase.verifyTrue(panel.isGroupShown("Coupled masses"));
            testCase.verifyTrue(panel.isGroupShown("Collisions"));
            testCase.verifyFalse(panel.isRowShown("e_rest"), "Collision details wait for the checkbox.");
            testCase.set("collision_on", true);
            testCase.verifyTrue(panel.isRowShown("e_rest"));
        end

        function overlappingStartIsReported(testCase)
            testCase.set("mode", "coupled");
            testCase.set("collision_on", true);
            testCase.set("x1_0", 10);
            testCase.pressRun();
            testCase.verifySubstring(string(testCase.find("dlab.status").Text), "overlap");
            testCase.verifyEmpty(testCase.App.View.Result);
        end

        function tabsFollowTheMode(testCase)
            testCase.pressRun();
            testCase.verifyTrue(ismember("Frequency response", testCase.App.View.tabTitles()));
            testCase.set("mode", "coupled");
            testCase.pressRun();
            titles = testCase.App.View.tabTitles();
            testCase.verifyTrue(ismember("Relative displacement", titles));
            testCase.verifyFalse(ismember("Frequency response", titles));
            testCase.verifyNotEmpty(testCase.axesTitled("Phase — Mass 2").Children);
        end

        function wallAndMassTouchAtContact(testCase)
            % Drawn geometry matches collision geometry (legacy wall test).
            testCase.set("mode", "coupled");
            testCase.set("x1_0", -2);                  % wall clearance is 2 m
            testCase.set("t_end", 0.5);
            testCase.set("dt", 0.1);
            testCase.pressRun();
            anim = testCase.axesTitled("Coupled two-mass");
            walls = findall(anim, Type="patch", Tag="wall");
            mass = findall(anim, Type="patch", Tag="mass1");
            leftWallFace = min(arrayfun(@(w) max(w.XData), walls));
            testCase.verifyEqual(leftWallFace, min(mass.XData), AbsTol=1e-10);
        end

        function impactsFlashInTheAnimation(testCase)
            testCase.choosePreset("Free impact (collision)");
            testCase.pressRun();
            first = testCase.App.View.Result.coll_log(1);
            testCase.App.View.Playback.seek(first.t + 0.01);
            anim = testCase.axesTitled("Coupled two-mass");
            captions = string({findall(anim, Type="text").String});
            testCase.verifyTrue(ismember("Impact!", captions));
            testCase.App.View.Playback.seek(first.t + 1);
            captions = string({findall(anim, Type="text").String});
            testCase.verifyFalse(ismember("Impact!", captions));
        end

        function summaryDescribesDamping(testCase)
            % The damping type has its own row (not the ratio's units, which
            % sweeps and the report would show as a unit).
            testCase.pressRun();
            data = testCase.find("dlab.summary").Data;
            testCase.verifyEqual(data.Units(data.Quantity == "Damping ratio ζ"), "");
            testCase.verifyEqual(data.Value(data.Quantity == "Damping"), "Under-damped");
            testCase.choosePreset("Critically damped");
            testCase.pressRun();
            data = testCase.find("dlab.summary").Data;
            testCase.verifyEqual(data.Value(data.Quantity == "Damping"), "Critically damped");
            testCase.verifySubstring(data.Value(data.Quantity == "Damped frequency ωd"), "no oscillation");
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyEqual(M.Units(M.Quantity == "Damping ratio ζ"), "");
        end

        function undampedResonanceShowsInfinityNotInf(testCase)
            testCase.set("c", 0);
            testCase.set("forced", true);
            testCase.set("omega_f", sqrt(10));
            testCase.pressRun();
            data = testCase.find("dlab.summary").Data;
            shown = data.Value(data.Quantity == "Magnification at ωf");
            testCase.verifySubstring(shown, "∞");
            testCase.verifyFalse(any(contains(string(data.Value), ["Inf" "NaN"])), "No Inf or NaN in the Summary.");
            testCase.verifyEqual(data.Value(data.Quantity == "Damping"), "Undamped");
            marker = findall(testCase.App.Figure, Type="line", Tag="forcing");
            testCase.verifyTrue(isfinite(marker.YData), "The resonance marker sits at the top edge.");
        end

        function animationDrawsOnlyTheElementsPresent(testCase)
            % Defaults: the damper sits above the floor, which the mass rides on.
            testCase.pressRun();
            anim = testCase.axesTitled("Single mass");
            floor = findall(anim, Type="line", Tag="floor");
            damper = findall(anim, Type="line", Tag="damper");
            mass = findall(anim, Type="patch", Tag="mass1");
            testCase.verifyGreaterThan(min(damper.YData(isfinite(damper.YData))), floor.YData(1));
            testCase.verifyEqual(min(mass.YData), floor.YData(1), AbsTol=1e-12);
            % Free impact has no springs and no dampers: none are drawn.
            testCase.choosePreset("Free impact (collision)");
            testCase.pressRun();
            anim = testCase.axesTitled("Coupled two-mass");
            dampers = findall(anim, Type="line", Tag="damper");
            testCase.verifyTrue(all(arrayfun(@(d) all(isnan(d.XData)), dampers)));
            springs = findall(anim, Type="line", Tag="spring");
            testCase.verifyNumElements(springs, 3);
            testCase.verifyTrue(all(arrayfun(@(d) all(isnan(d.XData)), springs)));
        end

        function animationShowsTheForce(testCase)
            testCase.choosePreset("Forced near resonance");
            testCase.pressRun();
            testCase.App.View.Playback.seek(1);
            anim = testCase.axesTitled("Single mass");
            captions = string({findall(anim, Type="text").String});
            testCase.verifyTrue(any(startsWith(captions, "F = ") & endsWith(captions, " N")));
            testCase.verifyTrue(any(endsWith(captions, " m/s")), "The velocity label has its units.");
        end

        function energyLegendLeavesTheCurvesClear(testCase)
            testCase.choosePreset("Beating (weak coupling)");
            testCase.pressRun();
            ax = testCase.axesTitled("Mechanical energy");
            r = testCase.App.View.Result;
            testCase.verifyGreaterThanOrEqual(ax.YLim(2), 1.15 * max(r.E));
            testCase.verifyEqual(ax.Legend.Location, 'north');
        end

        function phasePortraitsShowTheirEdges(testCase)
            testCase.choosePreset("Free impact (collision)");
            testCase.pressRun();
            ax = testCase.axesTitled("Phase — Mass 1");
            r = testCase.App.View.Result;
            testCase.verifyGreaterThan(ax.YLim(2), max(r.v1), "v₁ = 0.8 m/s runs along the top.");
        end

        function bodeTabShowsTheForcedResponse(testCase)
            testCase.verifyTrue(ismember("Bode", testCase.App.View.analysisTitles()));
            testCase.pressRun();
            testCase.verifyEqual(string(testCase.find("dlab.frequency.input").Value), "Force");
            p = testCase.App.View.params();
            magnitude = findobj(testCase.find("dlab.frequency.magnitude"), Type="line");
            testCase.assertNumElements(magnitude, 1);
            testCase.verifyEqual(magnitude.YData(1), 20 * log10(1 / p.k), ...
                "Far below resonance the gain is the static compliance 1/k.", AbsTol=1e-3);
            testCase.verifyMatches(string(testCase.find("dlab.frequency.note").Text), "^DC gain 0\.1 ");

            output = testCase.find("dlab.frequency.output");
            output.Value = 'v';
            output.ValueChangedFcn(output, []);
            magnitude = findobj(testCase.find("dlab.frequency.magnitude"), Type="line");
            testCase.verifyLessThan(magnitude.YData(1), -40, "A steady force holds the mass still.");

            testCase.set("mode", "coupled");
            testCase.pressRun();
            testCase.verifyEqual(string(testCase.find("dlab.frequency.input").Value), "Force on mass 1");
            testCase.verifyEqual(string(testCase.find("dlab.frequency.output").Items), ...
                ["x₁ (m)" "v₁ (m/s)" "x₂ (m)" "v₂ (m/s)"]);
        end
    end
end
