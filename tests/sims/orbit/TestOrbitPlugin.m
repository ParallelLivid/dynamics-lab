classdef (TestTags = {'ui'}) TestOrbitPlugin < matlab.unittest.TestCase
    %TESTORBITPLUGIN Orbit in the shell: README sample outputs, coupled
    %   inputs, and the original app's UI tests (TestOrbitalSimulator.m).

    properties
        App
    end

    properties (TestParameter)
        reference = struct( ...
            "Earth", struct("body", "Earth", "periodMin", 92.558, "samples", 557), ...
            "Moon", struct("body", "Moon", "periodMin", 122.63, "samples", 2209), ...
            "Sun", struct("body", "Sun", "periodMin", 365.26 * 1440, "samples", 13151))
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
            testCase.App = DynamicsLab("orbit", Visible=false);
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

        function pressRun(testCase)
            b = testCase.find("dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.App.View.Playback.pause();
            testCase.App.View.Playback.seek(testCase.App.View.Playback.StartTime);   % Run auto-plays; start from a known frame
            testCase.assertEmpty(testCase.App.LastError);
        end

        function value = summary(testCase, quantity)
            data = testCase.find("dlab.summary").Data;
            value = data.Value(data.Quantity == quantity);
        end
    end

    methods (Test)
        function presetBodiesMatchReadme(testCase, reference)
            testCase.set("body", reference.body);
            testCase.pressRun();
            r = testCase.App.View.Result;
            testCase.verifyEqual(r.period / 60, reference.periodMin, RelTol=1e-4);
            testCase.verifyNumElements(r.time, reference.samples);
            testCase.verifyLessThan(str2double(testCase.summary("Max relative energy drift")), 2e-10);
            testCase.verifyLessThan(str2double(testCase.summary("Max relative angular-momentum drift")), 1e-10);
            testCase.verifyEqual(testCase.App.View.Playback.TimeScale, r.time(end) / 20, ...
                "A whole run plays in about 20 s at 1×.", RelTol=1e-12);
        end

        function earthAltitudeSpansPeriapsisToApoapsis(testCase)
            testCase.pressRun();
            r = testCase.App.View.Result;
            altitude = vecnorm(r.state(:, 1:3), 2, 2) - r.body.radius;
            testCase.verifyEqual([min(altitude) max(altitude)], [339.22 474.78], AbsTol=0.05);
        end

        function legacyWorkflowsComplete(testCase)
            % Keplerian, then Cartesian, then a custom body (legacy workflow test).
            testCase.pressRun();
            testCase.set("inputType", "cartesian");
            testCase.pressRun();
            testCase.set("body", "Custom");
            testCase.pressRun();
            testCase.verifyEqual(testCase.summary("Outcome"), "completed");
        end

        function switchingRepresentationKeepsTheOrbit(testCase)
            view = testCase.App.View;
            before = view.params();
            testCase.set("inputType", "cartesian");
            testCase.verifyTrue(view.Inputs.isRowShown("vx"));
            testCase.verifyFalse(view.Inputs.isRowShown("a"));
            testCase.set("inputType", "keplerian");
            after = view.params();
            for name = ["a" "e" "inc"]
                testCase.verifyEqual(after.(name), before.(name), name, RelTol=1e-9, AbsTol=1e-9);
            end
        end

        function choosingABodyLoadsItsDefaults(testCase)
            testCase.set("body", "Moon");
            p = testCase.App.View.params();
            moon = dlab.sims.orbit.BodyCatalog().Moon;
            testCase.verifyEqual([p.a p.e p.inc p.sampleStep], [moon.orbit(1:3) moon.sampleStep]);
            testCase.verifyFalse(testCase.App.View.Inputs.isGroupShown("Custom body"));
            testCase.set("body", "Custom");
            testCase.verifyTrue(testCase.App.View.Inputs.isGroupShown("Custom body"));
        end

        function periapsisInsideTheBodyIsRejected(testCase)
            testCase.set("e", 0.5);
            b = testCase.find("dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.verifySubstring(string(testCase.find("dlab.status").Text), "must be above the body surface");
        end

        function sunSynchronousPresetPrecesses(testCase)
            preset = testCase.find("dlab.preset");
            preset.Value = "builtin:Sun-synchronous (Earth, 700 km, J2)";
            preset.ValueChangedFcn(preset, []);
            testCase.pressRun();
            testCase.verifyTrue(ismember("Perturbations", testCase.App.View.tabTitles()));
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            measured = M.Value(M.Quantity == "Node drift (measured)");
            testCase.verifyEqual(measured, 360 / 365.2422, "RelTol", 0.01, "Sun-synchronous: 360° a year.");
            testCase.verifyEqual(M.Value(M.Quantity == "Node drift (J2 theory)"), 360 / 365.2422, RelTol=1e-3);
            % J2 with its reference radius, 6378.137 km (6371 km before: 98.177°).
            testCase.verifyEqual(str2double(testCase.summary("Inclination")), 98.159, "AbsTol", 1e-3, ...
                "The summary reports elements from the equator, as entered.");
            % The spin-axis angular momentum of a retrograde orbit is negative:
            % its drift read 2.6e10 when divided by max(h0, eps).
            testCase.verifyLessThan(M.Value(startsWith(M.Quantity, "Max relative angular-momentum")), 1e-8);
        end

        function geostationaryStaysOverOnePoint(testCase)
            % Measured from the equator: the track is a point, not a figure-
            % eight 47° tall (inclination 0 from the frame is 23.44° from the
            % equator). Zero angles read 0, not 360.
            preset = testCase.find("dlab.preset");
            preset.Value = "builtin:Geostationary (Earth)";
            preset.ValueChangedFcn(preset, []);
            testCase.pressRun();
            r = testCase.App.View.Result;
            spin = dlab.physics.roty(deg2rad(r.body.tilt)) * [0; 0; 1];
            latitude = asind((r.state(:, 1:3) * spin) ./ vecnorm(r.state(:, 1:3), 2, 2));
            testCase.verifyLessThan(max(abs(latitude)), 1e-6);
            testCase.verifyEqual(str2double(testCase.summary("RAAN")), 0);
            testCase.verifyEqual(str2double(testCase.summary("True anomaly")), 0);
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Orbital eleme…", "The frame (X…"). The body names fit.
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice" && spec.Name ~= "body"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function j2UsesItsReferenceRadius(testCase)
            % Earth's J2 is defined with the equatorial radius: a 6778 km
            % circular orbit at 51.6° turns by −1.5 n J2 (6378.137/a)² cos i =
            % −5.00269°/day (−4.99150 with the mean radius).
            testCase.App.View.Plugin.requestInputs(struct("reference", "equator", "a", 6778, "e", 0, ...
                "inc", 51.6, "oblateness", true, "durationOrbits", 3), "ISS");
            testCase.pressRun();
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyEqual(M.Value(M.Quantity == "Node drift (J2 theory)"), -5.00269, AbsTol=1e-5);
        end

        function reentryPresetDecays(testCase)
            preset = testCase.find("dlab.preset");
            preset.Value = "builtin:Re-entry by drag (Earth, from 250 km)";
            preset.ValueChangedFcn(preset, []);
            testCase.verifyTrue(testCase.App.View.Inputs.isRowShown("areaToMass"));
            testCase.pressRun();
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyEqual(M.Value(M.Quantity == "Time to re-entry"), 2.6, AbsTol=0.5);
            testCase.verifyLessThan(M.Value(M.Quantity == "Decay rate (mean)"), 0);
            testCase.set("body", "Mars");
            testCase.verifyFalse(testCase.App.View.Inputs.isRowShown("drag"), "Drag uses Earth's atmosphere only.");
        end

        function referencePlaneConvertsTheOrbit(testCase)
            % Switching the plane the elements are measured from keeps the
            % same orbit: the position and velocity do not change.
            plugin = testCase.App.View.Plugin;
            params = testCase.App.View.params();
            before = plugin.solve(params).state(1, :);
            testCase.set("reference", "equator");
            params = testCase.App.View.params();
            testCase.verifyNotEqual(params.inc, plugin.defaultParams().inc, "Earth is tilted: the inclination changes.");
            after = plugin.solve(params).state(1, :);
            testCase.verifyEqual(after, before, AbsTol=1e-6);
        end

        function escapeTrajectoryIsOpen(testCase)
            plugin = dlab.sims.orbit.OrbitPlugin();
            r = plugin.solve(plugin.presetParams("Escape trajectory (Earth)"));
            testCase.verifyEqual(r.period, Inf);
            testCase.verifyEqual(r.time(end), 86400);
        end

        function bodySurfaceDataLoads(testCase)
            folder = fullfile(dlab.core.Paths.resources(), "bodies");
            manifest = jsondecode(fileread(fullfile(folder, "manifest.json")));
            for name = string(fieldnames(manifest.bodies))'
                entry = manifest.bodies.(name);
                for part = string(fieldnames(entry))'
                    info = entry.(part);
                    pixels = imread(fullfile(folder, info.file));
                    testCase.verifyEqual([size(pixels, 2) size(pixels, 1)], [info.width info.height], name + " " + part);
                    testCase.verifyNotEmpty(info.source);
                end
            end
            bodies = dlab.sims.orbit.BodyCatalog();
            for name = string(fieldnames(bodies))'
                s = dlab.sims.orbit.bodySurface(name, bodies.(name).color);
                testCase.verifyEqual(size(s.Map, 3), 3, name);
                testCase.verifyTrue(all(s.Map(:) >= 0 & s.Map(:) <= 1), name);
            end
            earth = dlab.sims.orbit.bodySurface("Earth", bodies.Earth.color);
            testCase.verifyEqual(earth.Kind, "imagery");
            testCase.verifySize(earth.Elevation, [180 360]);
            testCase.verifyEqual(earth.Elevation(59, 268), 4718, "AbsTol", 600, "Tibet (32° N, 88° E) is high.");
            testCase.verifyLessThan(earth.Elevation(91, 31), -3000, "The Pacific is deep.");
            mars = dlab.sims.orbit.bodySurface("Mars", bodies.Mars.color);
            testCase.verifyEqual(mars.Kind, "elevation");
            testCase.verifyGreaterThan(max(mars.Elevation(:)), 15000, "Olympus Mons.");
            testCase.verifyEqual(dlab.sims.orbit.bodySurface("Jupiter", bodies.Jupiter.color).Kind, "procedural");
        end

        function missingSurfaceDataFallsBack(testCase)
            empty = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            bodies = dlab.sims.orbit.BodyCatalog();
            s = dlab.sims.orbit.bodySurface("Earth", bodies.Earth.color, string(empty.Folder));
            testCase.verifyEqual(s.Kind, "procedural");
            testCase.verifyEmpty(s.Elevation);
            testCase.verifyEqual(size(s.Map, 3), 3);
        end

        function surfacesAreDrawn(testCase)
            testCase.pressRun();
            fig = testCase.App.Figure;
            testCase.verifyNotEmpty(findall(fig, Tag="dlab.orbit.map"), "Map under the ground track.");
            globes = findall(fig, Tag="dlab.orbit.globe");
            testCase.verifyGreaterThanOrEqual(numel(globes), 3, "Orbit, Surface, and Animation globes.");
            testCase.verifyNotEmpty(findall(fig, Tag="dlab.orbit.subPoint"));
            r = testCase.App.View.Result;
            plugin = testCase.App.View.Plugin;
            plugin.drawFrame(0);
            spin = findall(fig, Type="hgtransform");
            testCase.assertNumElements(spin, 1);
            first = spin.Matrix;
            plugin.drawFrame(r.time(end));
            angle = r.body.spinRate * r.time(end);
            expected = dlab.physics.roty(deg2rad(r.body.tilt)) * dlab.physics.rotz(angle);
            testCase.verifyEqual(spin.Matrix(1:3, 1:3), expected, AbsTol=1e-12);
            testCase.verifyNotEqual(spin.Matrix, first);

            clearance = str2double(testCase.summary("Lowest altitude above terrain"));
            altitude = vecnorm(r.state(:, 1:3), 2, 2) - r.body.radius;
            testCase.verifyLessThan(clearance, min(altitude));
            testCase.verifyGreaterThan(clearance, min(altitude) - 6);

            testCase.set("surface", "plain");                     % Display: no re-run needed
            testCase.verifyEmpty(findall(fig, Tag="dlab.orbit.map"));
            testCase.verifyEqual(string(findall(fig, Tag="dlab.stale").Visible), "off");
            testCase.set("surfaceColors", "elevation");
            testCase.verifyEmpty(testCase.App.LastError);
        end

        function projectionsFlattenTheAnimation(testCase)
            % Port of the legacy animation-projection test.
            testCase.pressRun();
            plugin = testCase.App.View.Plugin;
            meridian = testCase.find("AnimationMeridian1");
            original = [meridian.XData; meridian.YData; meridian.ZData];
            velocity = testCase.find("AnimationVelocity");
            originalVelocity = [velocity.XData; velocity.YData; velocity.ZData].';

            testCase.set("body", "Jupiter");             % does not touch the current result
            plugin.setViewMode("3D");
            meridian = testCase.find("AnimationMeridian1");
            testCase.verifyEqual([meridian.XData; meridian.YData; meridian.ZData], original, AbsTol=1e-8);

            modes = ["2D XY" "2D XZ" "2D YZ"];
            columns = [1 2; 1 3; 2 3];
            names = ["X" "Y" "Z"];
            for k = 1:3
                dd = testCase.find("dlab.orbit.view");
                dd.Value = modes(k);
                dd.ValueChangedFcn(dd, []);
                velocity = testCase.find("AnimationVelocity");
                actual = [velocity.XData; velocity.YData; velocity.ZData].';
                testCase.verifyEqual(actual, [originalVelocity(:, columns(k, :)), zeros(2, 1)], AbsTol=1e-8);
                meridian = testCase.find("AnimationMeridian1");
                testCase.verifyEqual(meridian.XData, original(columns(k, 1), :), AbsTol=1e-8);
                testCase.verifyEqual(meridian.YData, original(columns(k, 2), :), AbsTol=1e-8);
                testCase.verifyEqual(meridian.ZData, zeros(size(meridian.ZData)));
                ax = ancestor(velocity, "axes");
                testCase.verifyEqual(ax.View, [0 90], AbsTol=1e-10);
                testCase.verifyEqual(string(ax.XLabel.String), names(columns(k, 1)) + " (km)");
                testCase.verifyEqual(string(ax.YLabel.String), names(columns(k, 2)) + " (km)");
            end
        end
    end
end
