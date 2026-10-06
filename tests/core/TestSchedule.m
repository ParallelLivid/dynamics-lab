classdef (TestTags = {'ui'}) TestSchedule < matlab.unittest.TestCase
    %TESTSCHEDULE Time-varying inputs: shapes, parameter checks, the panel
    %   rows, and the simulators that use them (6DOF controls, mass-spring
    %   forcing profiles).

    properties
        Fig
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (Test)
        function shapesEvaluate(testCase)
            S = @dlab.core.Schedule.make;
            E = @dlab.core.Schedule.evaluate;
            t = [0 0.99 1 1.5 2 2.5 3.5];
            testCase.verifyEqual(E(S("constant", Value=2), t), 2 * ones(1, 7));
            testCase.verifyEqual(E(S("step", Value=1, Amplitude=2, Start=1), t), [1 1 3 3 3 3 3]);
            testCase.verifyEqual(E(S("pulse", Amplitude=1, Start=1, Width=1), t), [0 0 1 1 0 0 0]);
            testCase.verifyEqual(E(S("doublet", Amplitude=1, Start=1, Width=1), t), [0 0 1 1 -1 -1 0]);
            testCase.verifyEqual(E(S("ramp", Value=0, Amplitude=4, Start=1, Width=2), t), ...
                [0 0 0 1 2 3 4], AbsTol=1e-12);
            testCase.verifyEqual(E(S("sine", Value=1, Amplitude=2, Start=1, Period=2), [0 1 1.5 2.5]), ...
                [1 1 3 -1], AbsTol=1e-12);
            testCase.verifyEqual(E(S("points", Points=[0 0; 2 4]), [-1 1 3]), [0 2 4]);
        end

        function functionsClipToTheLimits(testCase)
            u = dlab.core.Schedule.toFunction(dlab.core.Schedule.make("step", Value=0.5, Amplitude=1), [0 1]);
            testCase.verifyEqual(u([0 2]), [0.5 1]);
            c = dlab.core.Schedule.toFunction(3, [0 1]);
            testCase.verifyEqual(c(7), 1, "A number is a constant schedule.");
            testCase.verifyEqual(c([0 2 4]), [1 1 1], "Constants are vectorized like every other shape.");
        end

        function normalizeReadsJsonAndRejectsNonsense(testCase)
            N = @dlab.core.Schedule.normalize;
            s = dlab.core.Schedule.make("points", Points=[0 1]);
            decoded = jsondecode(jsonencode(s));
            testCase.verifyEqual(N(decoded), s, "One point survives jsondecode's vector.");
            [~, ok] = N(struct("shape", "zigzag"));
            testCase.verifyFalse(ok);
            [~, ok, message] = N(struct("shape", "pulse", "width", 0));
            testCase.verifyFalse(ok);
            testCase.verifyEqual(message, "duration must be positive");
            [~, ok] = N("text");
            testCase.verifyFalse(ok);
        end

        function pointsParseAndFormat(testCase)
            [points, ok] = dlab.core.Schedule.parsePoints("0 0; 2, 1;4 0");
            testCase.verifyTrue(ok);
            testCase.verifyEqual(points, [0 0; 2 1; 4 0]);
            testCase.verifyEqual(dlab.core.Schedule.formatPoints(points), "0 0; 2 1; 4 0");
            [~, ok] = dlab.core.Schedule.parsePoints("0 0; 2");
            testCase.verifyFalse(ok);
            testCase.verifyEqual(dlab.core.Schedule.describe(dlab.core.Schedule.make("step", Amplitude=0.3, ...
                Start=2), "N"), "step from 0 to 0.3 N at 2 s");
        end

        function specsAcceptNumbersAndCheckTheStartingValue(testCase)
            spec = dlab.core.ParamSpec("u", Type="schedule", Default=0.5, Min=0, Max=1);
            testCase.verifyEqual(spec.Default, dlab.core.Schedule.make("constant", Value=0.5));
            [value, ok] = spec.coerce(0.25);
            testCase.verifyTrue(ok);
            testCase.verifyEqual(value.shape, "constant");
            [~, ok, message] = spec.coerce(dlab.core.Schedule.make("step", Value=2));
            testCase.verifyFalse(ok);
            testCase.verifyEqual(message, "starting value must be in [0, 1]");
            testCase.verifyEqual(spec.rangeText(), "[0, 1]");
            testCase.verifySubstring(spec.tooltip(), "clipped");
        end

        function panelShowsTheRowsTheShapeNeeds(testCase)
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            spec = dlab.core.ParamSpec("u", Label="Torque", Type="schedule", Default=0, Min=-1, Max=1);
            panel = dlab.core.ParamPanel(uigridlayout(fig, [1 1]), spec, struct("u", 0), dlab.ui.Theme.dark());
            field = @(suffix) findall(fig, Tag="dlab.param.u" + suffix);
            shape = field("");
            testCase.verifyEqual(string(shape.Value), "constant");
            testCase.verifyTrue(logical(field(".value").Visible));
            testCase.verifyFalse(logical(field(".amplitude").Visible));

            shape.Value = "doublet";
            shape.ValueChangedFcn(shape, []);
            for name = [".value" ".amplitude" ".start" ".width"]
                testCase.verifyTrue(logical(field(name).Visible), name);
            end
            testCase.verifyFalse(logical(field(".period").Visible));
            amplitude = field(".amplitude");
            amplitude.Value = 0.4;
            amplitude.ValueChangedFcn(amplitude, []);
            s = panel.values().u;
            testCase.verifyEqual([string(s.shape) s.amplitude], ["doublet" "0.4"]);

            shape.Value = "points";
            shape.ValueChangedFcn(shape, []);
            testCase.verifyTrue(logical(field(".points").Visible));
            testCase.verifyEqual(panel.values().u.points, [0 0; 1 0.4], "A table to start editing from.");
            points = field(".points");
            points.Value = "not numbers";
            points.ValueChangedFcn(points, []);
            testCase.verifyEqual(panel.values().u.points, [0 0; 1 0.4], "Unreadable text is ignored.");

            panel.setValues(struct("u", 0.2));
            testCase.verifyEqual(string(shape.Value), "constant");
            testCase.verifyEqual(field(".value").Value, 0.2);
        end

        function aircraftControlsFollowTheirSchedules(testCase)
            plugin = dlab.sims.flight6dof.Flight6dofPlugin();
            params = plugin.presetParams("Straight flight");
            params.duration = 8;
            steady = plugin.solve(params);
            params.elevator = dlab.core.Schedule.make("doublet", Amplitude=0.3, Start=1, Width=0.5);
            excited = plugin.solve(params);
            q = @(r) r.state(:, 5);
            testCase.verifyLessThan(max(abs(q(steady))), 1e-3, "Trimmed flight stays level.");
            testCase.verifyGreaterThan(max(abs(q(excited))), 0.05, "The doublet pitches the aircraft.");
            T = plugin.exportTable(excited);
            testCase.verifyEqual(T.pitch_torque(T.time > 1.1 & T.time < 1.4), ...
                0.3 * ones(nnz(T.time > 1.1 & T.time < 1.4), 1));
            testCase.verifyClass(excited.config.control.elevator, "struct", "Results keep data, not functions.");
        end

        function massSpringStepResponseSettlesAtFOverK(testCase)
            plugin = dlab.sims.massspring.MassSpringPlugin();
            params = plugin.defaultParams();
            params.x0 = 0;
            params.c = 4;
            params.t_end = 30;
            params.dt = 0.01;
            params.forced = true;
            params.forceShape = "profile";
            params.Fprofile = dlab.core.Schedule.make("step", Amplitude=5, Start=1);
            r = plugin.solve(params);
            testCase.verifyEqual(r.x(end), 5 / params.k, AbsTol=1e-3);
            testCase.verifyEqual(r.F_ext(r.t > 2), 5 * ones(nnz(r.t > 2), 1));
            testCase.verifyTrue(isnan(r.MF_at_f), "No magnification factor for a profile.");
        end

        function oldMassSpringScenariosLoadQuietly(testCase)
            plugin = dlab.sims.massspring.MassSpringPlugin();
            s = dlab.core.ScenarioIO.toStruct(plugin, plugin.defaultParams());
            s.schemaVersion = 1;
            s.params = rmfield(s.params, ["forceShape" "forceShape_c" "Fprofile" "Fprofile_c"]);
            s = jsondecode(jsonencode(s));
            s.simulator = string(s.simulator);
            [params, warnings] = dlab.core.ScenarioIO.fromStruct(s, plugin);
            testCase.verifyEmpty(warnings);
            testCase.verifyEqual(params.forceShape, "harmonic");
        end
    end
end
