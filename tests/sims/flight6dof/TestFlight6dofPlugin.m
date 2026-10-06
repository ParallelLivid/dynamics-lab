classdef (TestTags = {'ui'}) TestFlight6dofPlugin < matlab.unittest.TestCase
    %TESTFLIGHT6DOFPLUGIN 6DOF in the shell: reference results, preset
    %   fidelity, early termination, and playback geometry.
    %
    %   Since 1.1.0 the model uses the ISA atmosphere (the original used the
    %   pressure exponent for density) and the presets are re-trimmed, so
    %   the Glide values differ slightly from the original summary.csv
    %   (69.9668 m, 6.9923 m/s, 150.2987 m).

    properties
        App
    end

    properties (TestParameter)
        presetName = {"Straight flight", "Glide", "Phugoid mode", "Short-period mode", ...
            "Dutch roll mode", "Roll subsidence mode"}
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
            testCase.App = DynamicsLab("flight6dof", Visible=false);
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
            testCase.App.View.Playback.pause();
            testCase.App.View.Playback.seek(testCase.App.View.Playback.StartTime);   % Run auto-plays; start from a known frame
        end

        function value = summary(testCase, quantity)
            data = testCase.find("dlab.summary").Data;
            value = data.Value(data.Quantity == quantity);
        end
    end

    methods (Test)
        function straightFlightHoldsTrim(testCase)
            testCase.pressRun();
            final = testCase.App.View.Result.state(end, :);
            testCase.verifyEqual(-final(12), 100, AbsTol=1e-6);
            testCase.verifyEqual(norm(final(1:3)), 20, AbsTol=1e-6);
            testCase.verifyEqual(hypot(final(10), final(11)), 400, AbsTol=1e-6);
            testCase.verifyEqual(testCase.summary("Termination"), "completed");
        end

        function glideMatchesReference(testCase)
            testCase.choosePreset("Glide");
            testCase.pressRun();
            final = testCase.App.View.Result.state(end, :);
            testCase.verifyEqual(-final(12), 69.9945244401179, AbsTol=1e-6);
            testCase.verifyEqual(norm(final(1:3)), 6.98661141793732, AbsTol=1e-6);
            testCase.verifyEqual(hypot(final(10), final(11)), 150.155907508414, AbsTol=1e-6);
        end

        function presetsReproduceTheOriginalConfiguration(testCase, presetName)
            % Every value defaultConfig(preset) sets must reach the engine.
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            original = dlab.sims.flight6dof.defaultConfig(presetName);
            r = plugin.solve(plugin.presetParams(presetName));
            for group = ["initial" "aircraft"]
                testCase.verifyEqual(r.config.(group), original.(group), group);
            end
            for name = string(fieldnames(original.control))'
                control = r.config.control.(name);          % controls are schedules now
                testCase.verifyEqual(control.shape, "constant", name);
                testCase.verifyEqual(control.value, original.control.(name), name);
            end
            testCase.verifyEqual(r.config.duration, original.duration);
            simFields = string(fieldnames(original.sim))';
            for name = simFields
                testCase.verifyEqual(string(r.config.sim.(name)), string(original.sim.(name)), name);
            end
        end

        function earlyEndIsAWarning(testCase)
            testCase.choosePreset("Glide");
            testCase.set("alt0", 5);
            testCase.pressRun();
            testCase.verifyEqual(testCase.summary("Termination"), "ground contact");
            status = testCase.find("dlab.status");
            testCase.verifySubstring(string(status.Text), "ended early: ground contact");
            testCase.verifyEqual(status.FontColor, testCase.App.Theme.Warning);
        end

        function advancedSettingsStartCollapsed(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyTrue(panel.isRowShown("u0"));
            testCase.verifyTrue(panel.isRowShown("throttle"));
            for name = ["m" "pitch_alpha" "Vmax"]
                testCase.verifyFalse(panel.isRowShown(name), name);
            end
        end

        function durationKeepsThePresetOtherEditsDoNot(testCase)
            testCase.choosePreset("Dutch roll mode");
            testCase.set("duration", 30);
            testCase.verifyEqual(testCase.App.View.Preset, "Dutch roll mode");
            testCase.set("throttle.value", 0.7);
            testCase.verifyEqual(testCase.App.View.Preset, "Custom");
        end

        function playbackDrawsBodyAxes(testCase)
            testCase.pressRun();
            view = testCase.App.View;
            view.Playback.seek(10.005);                          % between samples
            ax = findall(testCase.App.Figure, Type="axes");
            anim = ax(arrayfun(@(a) string(a.Title.String) == "Flight playback", ax));
            axesLines = findall(anim, Type="line", LineWidth=2);
            testCase.verifyNumElements(axesLines, 3);
            lengths = arrayfun(@(l) norm([diff(l.XData) diff(l.YData) diff(l.ZData)]), axesLines);
            testCase.verifyEqual(lengths, lengths(1) * ones(3, 1), ...
                "Body axes are drawn with equal length.", RelTol=1e-9);
            aircraft = findall(anim, Type="line", Marker="o", MarkerSize=12);
            testCase.verifyEqual(aircraft.ZData, 100, "Trimmed flight holds 100 m.", AbsTol=1e-3);
        end

        function loopPresetNeedsTheQuaternion(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            params = plugin.presetParams("Loop");
            r = plugin.solve(params);
            testCase.verifyEqual(string(r.termination), "completed");
            testCase.verifyTrue(isfield(r, "quaternion"));
            T = plugin.exportTable(r);
            names = string(T.Properties.VariableNames);
            first = find(names == "q0", 1);
            testCase.assertNotEmpty(first, "The quaternion is exported.");
            testCase.verifyEqual(names(first:first + 3), ["q0" "q1" "q2" "q3"]);
            testCase.verifyEqual(numel(T.Properties.VariableUnits), width(T));
            params.attitude = "euler";
            testCase.verifyEqual(string(plugin.solve(params).termination), "attitude limit");
        end

        function olderScenariosKeepEulerAngles(testCase)
            file = fullfile(tempdir, "flight6dof-v1.json");
            testCase.addTeardown(@() delete(file));
            s = struct("format", "dynamicslab-scenario", "formatVersion", 1, "simulator", "flight6dof", ...
                "schemaVersion", 1, "preset", "Custom", "params", struct("u0", 20));
            writelines(jsonencode(s), file);
            testCase.App.View.loadScenario(file);
            testCase.verifyEqual(testCase.App.View.params().attitude, "euler");
            testCase.verifyEqual(dlab.sims.flight6dof.Flight6dofPlugin().defaultParams().attitude, "quaternion");
        end

        function crosswindMakesTheAircraftCrab(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            params = plugin.presetParams("Crosswind (10 m/s from the west)");
            r = plugin.solve(params);
            M = plugin.metrics(r);
            value = @(q) M.Value(M.Quantity == q);
            testCase.verifyEqual(value("Final altitude"), 100, AbsTol=0.01);
            testCase.verifyEqual(value("Final airspeed"), 20, AbsTol=0.01);
            testCase.verifyEqual(value("Wind drift"), 10 * 20, AbsTol=0.5);
            testCase.verifyEqual(value("Crab angle"), -atand(10 / 20), AbsTol=0.2);
            testCase.verifyEqual(value("Final ground speed"), hypot(20, 10), AbsTol=0.05);
            % Uniform wind moves the air mass, not the dynamics: same modes.
            still = plugin.presetParams("Straight flight");
            A = dlab.core.Linearization.analyze(plugin.linearization(params)).Eigenvalues;
            B = dlab.core.Linearization.analyze(plugin.linearization(still)).Eigenvalues;
            testCase.verifyEqual(sort(abs(A)), sort(abs(B)), AbsTol=1e-5);
            T = plugin.exportTable(r);
            testCase.verifyEqual(T.airspeed(end), 20, AbsTol=0.01);
        end

        function windInputsAppearWhenUsed(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("windFrom"));
            testCase.verifyFalse(panel.isRowShown("icFrame"));
            testCase.set("windSpeed", 6);
            testCase.verifyTrue(panel.isRowShown("windFrom"));
            testCase.verifyTrue(panel.isRowShown("icFrame"));
            testCase.pressRun();
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Tag="dlab.flight6dof.wind"));
            ax = findall(testCase.App.Figure, Type="axes");
            airspeed = ax(arrayfun(@(a) string(a.Title.String) == "Airspeed", ax));
            testCase.verifyNumElements(findall(airspeed, Type="line"), 2, "Airspeed and ground speed.");
        end

        function excitationsAreIdentifiedAgainstTheLinearModel(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            cases = ["Excite: Dutch roll (yaw doublet)" "Excite: roll subsidence (roll pulse)" ...
                "Excite: spiral (small roll pulse)" "Excite: phugoid (pitch pulse)"];
            labels = ["Dutch roll" "Roll subsidence" "Spiral" "Phugoid"];
            for k = 1:numel(cases)
                r = plugin.solve(plugin.presetParams(cases(k)));
                id = r.identification;
                testCase.verifyEqual(id.label, labels(k), cases(k));
                testCase.verifyTrue(id.ok, cases(k) + ": " + string(id.message));
                if isfinite(id.period)
                    testCase.verifyEqual(id.period, id.linear.period, "RelTol", 0.1, cases(k));
                else
                    testCase.verifyEqual(id.timeConstant, id.linear.timeConstant, "RelTol", 0.1, cases(k));
                end
            end
            rows = plugin.summaryTable(plugin.solve(plugin.presetParams(cases(1))));
            testCase.verifyEqual(rows.Display(rows.Quantity == "Identified mode"), "Dutch roll");
            period = rows.Value(rows.Quantity == "Identified period");
            testCase.verifyEqual(period, 3.24, AbsTol=0.1);
        end

        function trimButtonTrimsAtTheTrimInputs(testCase)
            testCase.set("trimSpeed", 24);
            trim = testCase.find("dlab.flight6dof.trim");
            trim.ButtonPushedFcn(trim, []);
            params = testCase.App.View.params();
            expected = dlab.sims.flight6dof.trim6dof(dlab.sims.flight6dof.defaultConfig().aircraft, 24, 100, 0);
            testCase.verifyEqual(params.u0, expected.u0, AbsTol=1e-9);
            testCase.verifyEqual(params.throttle.value, expected.throttle, AbsTol=1e-9);
            testCase.pressRun();
            final = testCase.App.View.Result.state(end, :);
            testCase.verifyEqual(-final(12), 100, AbsTol=1e-3);
            undo = testCase.find("dlab.undo");
            undo.ButtonPushedFcn(undo, []);                 % the trim is one undo step
            testCase.verifyEqual(testCase.App.View.params().u0, ...
                dlab.sims.flight6dof.Flight6dofPlugin().defaultParams().u0, AbsTol=1e-12);
        end

        function tuneSizesTheInputToTheMode(testCase)
            dropdown = testCase.find("dlab.flight6dof.tuneMode");
            dropdown.Value = "dutchroll";
            tune = testCase.find("dlab.flight6dof.tune");
            tune.ButtonPushedFcn(tune, []);
            params = testCase.App.View.params();
            testCase.verifyEqual(params.rudder.shape, "doublet");
            testCase.verifyEqual(2 * params.rudder.width, 3.244, "AbsTol", 0.05, "Doublet period = mode period.");
            testCase.verifyEqual(params.identify, "dutchroll");
            testCase.pressRun();
            testCase.verifyEqual(string(testCase.summary("Identified mode")), "Dutch roll");
            dropdown.Value = "rollsubsidence";
            tune.ButtonPushedFcn(tune, []);                 % a real mode: a pulse
            params = testCase.App.View.params();
            testCase.verifyEqual(params.aileron.shape, "pulse");
            testCase.verifyEqual(params.identify, "rollsubsidence");
        end

        function autopilotPresetsReachTheirTargets(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            r = plugin.solve(plugin.presetParams("Autopilot: turn to 90° (holding altitude and speed)"));
            M = plugin.metrics(r);
            testCase.verifyLessThan(abs(M.Value(M.Quantity == "Heading error at the end")), 1);
            testCase.verifyLessThan(abs(M.Value(M.Quantity == "Altitude error at the end")), 1);
            testCase.verifyLessThan(abs(M.Value(M.Quantity == "Airspeed error at the end")), 0.2);
            r = plugin.solve(plugin.presetParams("Autopilot: climb to 150 m"));
            M = plugin.metrics(r);
            testCase.verifyEqual(M.Value(M.Quantity == "Final altitude"), 150, "AbsTol", 1);
        end

        function autopilotInputsAndPlots(testCase)
            panel = testCase.App.View.Inputs;
            testCase.verifyFalse(panel.isRowShown("apAltitudeRef"));
            testCase.set("apAltitude", true);
            testCase.verifyTrue(panel.isRowShown("apAltitudeRef"));
            testCase.set("apAltitudeRef", 120);
            testCase.pressRun();
            refs = findall(testCase.App.Figure, Tag="dlab.flight6dof.reference");
            testCase.verifyNumElements(refs, 1, "The altitude reference is drawn.");
            r = testCase.App.View.Result;
            testCase.verifyEqual(size(r.controls), [numel(r.t) 4]);
            testCase.verifyNotEqual(r.controls(end, 2), r.controls(1, 2), "The autopilot moves the elevator.");
        end

        function plotsAreResampledToPlotPoints(testCase)
            testCase.choosePreset("Phugoid mode");
            testCase.set("MAX_PTS", 200);
            testCase.pressRun();
            ax = findall(testCase.App.Figure, Type="axes");
            airspeed = ax(arrayfun(@(a) string(a.Title.String) == "Airspeed", ax));
            trace = findall(airspeed, Type="line");
            testCase.verifyNumElements(trace.XData, 200);
        end

        function inputsExplainThemselves(testCase)
            plugin = testCase.App.View.Plugin;
            for spec = plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"           % "Automatic (from the excitation)" was cut off
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
            % about() said "12 states … Euler angles" and "held constant for the whole run".
            about = plugin.about();
            testCase.verifySubstring(about, "13 states");
            testCase.verifyFalse(contains(about, "held constant"));
        end

        function steadyTracesAreInsideTheirPlots(testCase)
            % In straight flight the airspeed (20 m/s), α and θ (1.4957°) lay on
            % the top edge of their plots, merged with the frame.
            testCase.pressRun();
            ax = findall(testCase.App.Figure, Type="axes");
            for title = ["Airspeed" "Angle of attack and sideslip" "Euler angles"]
                a = ax(arrayfun(@(x) string(x.Title.String) == title, ax));
                top = max(arrayfun(@(l) max(l.YData), findall(a, Type="line")));
                testCase.verifyGreaterThan(a.YLim(2), top + 1e-3 * abs(top), title);
            end
            % Body rates of 1e−10 rad/s (round-off in trim) were stretched over the plot.
            rates = ax(arrayfun(@(x) string(x.Title.String) == "Body rates", ax));
            testCase.verifyGreaterThanOrEqual(diff(rates.YLim), 0.01);
        end

        function phugoidPresetSwingsOnce(testCase)
            % Independent reference: a separate copy of the model, integrated in scipy.
            % My own copy of the model (scipy, Euler angles): about the preset's
            % start the phugoid has a 31.829 s period and ζ 0.566, so the
            % altitude rises once (104.89 m at 11.9 s) and then sinks to 87.85 m
            % at 120 s. The lesson said to compare the period "with the
            % oscillation on the Altitude tab", which has none.
            testCase.choosePreset("Phugoid mode");
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            M = dlab.core.Linearization.analyze(plugin.linearization(testCase.App.View.RunParams)).Modes;
            phugoid = M(M.Mode == "Phugoid", :);
            testCase.verifyEqual([phugoid.Period phugoid.DampingRatio], [31.829 0.56608], RelTol=1e-4);
            r = testCase.App.View.Result;
            h = -r.state(:, 12);
            [top, k] = max(h);
            testCase.verifyEqual([top r.t(k)], [104.89 11.86], RelTol=3e-3);
            testCase.verifyEqual(h(end), 87.850, AbsTol=2e-3);
            testCase.verifyTrue(all(diff(h(k:end)) <= 1e-9), "After its one swing up it only descends.");
        end
    end
end
