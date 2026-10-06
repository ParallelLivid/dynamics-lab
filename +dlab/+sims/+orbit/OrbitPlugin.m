classdef OrbitPlugin < dlab.core.TimeDomainPlugin
    %ORBITPLUGIN Two-body orbit around a planet, the Moon, the Sun, or a
    %   custom body: 3-D trajectory, ground track, orbital elements,
    %   conservation diagnostics, and an animation with 3-D / 2-D views.
    %   Bodies are drawn with surface maps (Earth imagery; Earth and Mars
    %   topography; procedural surfaces for the rest, see bodySurface).

    properties (Constant)
        Id = "orbit"
        Title = "Orbital Mechanics"
        Category = "Aerospace"
        Summary = "Orbits around planets, the Moon, or the Sun: ground tracks, J2 precession, and drag decay."
        SchemaVersion = 1
        Views = ["3D" "2D XY" "2D XZ" "2D YZ"]
    end

    properties (Constant, Access = private)
        PlaySeconds = 20      % a whole run plays in about this long at 1×
        TrailSamples = 200
        Kepler = ["a" "e" "inc" "raan" "argp" "nu"]
        Cartesian = ["rx" "ry" "rz" "vx" "vy" "vz"]
        ReliefBodies = ["Earth" "Mars"]     % bodies with elevation data (resources/bodies)
        GlobeResolution = 96
    end

    properties (SetAccess = private)
        ViewMode (1,1) string = "3D"
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
        LastTime (1,1) double = 0
        ViewDropdown
        Surface                 % bodySurface of the body being shown
        Textured (1,1) logical = true
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            bodies = dlab.sims.orbit.BodyCatalog();
            earth = bodies.Earth;
            [r, v] = defaultCartesian(earth);
            custom = @(p) p.body == "Custom";
            kepler = @(p) p.inputType == "keplerian";
            cartesian = @(p) p.inputType == "cartesian";
            specs = [
                P("body", Label="Central body", Type="choice", Default="Earth", ...
                    Choices=string(fieldnames(bodies))', Group="Central body", ...
                    Description="Choosing a body loads its default orbit and output step.")
                P("mu", Label="Gravitational parameter μ", Units="km³/s²", Default=earth.mu, Min=0, ...
                    MinInclusive=false, Group="Custom body", VisibleWhen=custom, DisplayFormat="%.10g", ...
                    Description="G times the body's mass (Earth 398600.4418 km³/s²).")
                P("radius", Label="Radius", Units="km", Default=earth.radius, Min=0, MinInclusive=false, ...
                    Group="Custom body", VisibleWhen=custom, Description="The surface: the run stops if the orbit " + ...
                    "reaches it. Also J2's reference radius for a custom body.")
                P("spinRate", Label="Spin rate", Units="rad/s", Default=earth.spinRate, Min=-1, Max=1, ...
                    Group="Custom body", VisibleWhen=custom, DisplayFormat="%.6g", ...
                    Description="How fast the body turns (Earth 7.292e−5 rad/s, one sidereal day): it moves " + ...
                    "the ground track.")
                P("tilt", Label="Axial tilt", Units="deg", Default=earth.tilt, Min=0, Max=180, ...
                    Group="Custom body", VisibleWhen=custom, Description="The equator's tilt from the frame's XY " + ...
                    "plane, about Y (Earth 23.44°).")
                P("J2", Label="Oblateness J2", Default=dlab.physics.bodyConstants("Earth").J2, Min=-0.05, ...
                    Max=0.05, Group="Custom body", VisibleWhen=custom, DisplayFormat="%.6g", ...
                    Description="Flattening of the body's gravity (Earth 1.0826e-3), used with J2 oblateness.")
                P("inputType", Label="Initial state as", Type="choice", Default="keplerian", ...
                    Choices=["keplerian" "cartesian"], ChoiceLabels=["Elements" "r and v"], ...
                    Group="Initial orbit", Description="Orbital elements (a, e, i, Ω, ω, ν), or position and " + ...
                    "velocity in the frame. Switching converts the current orbit.")
                P("reference", Label="Elements measured from", Type="choice", Default="frame", ...
                    Choices=["frame" "equator"], ChoiceLabels=["Frame" "Equator"], ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="The frame's XY plane, or the " + ...
                    "body's equator (tilted by its axial tilt about Y). Oblateness acts about the spin axis, " + ...
                    "so sun-synchronous and frozen orbits are set from the equator. Switching converts the orbit.")
                P("a", Label="Semi-major axis", Units="km", Default=earth.orbit(1), Min=0, MinInclusive=false, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="Half the ellipse's long axis, from the " + ...
                    "body's centre (not the altitude): it sets the period, T = 2π √(a³/μ).")
                P("e", Label="Eccentricity", Default=earth.orbit(2), Min=0, Max=1, MaxInclusive=false, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="0 is a circle; towards 1 a long ellipse. " + ...
                    "Open (escape) trajectories are set by position and velocity.")
                P("inc", Label="Inclination", Units="deg", Default=earth.orbit(3), Min=0, Max=180, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="The tilt of the orbit's plane from the " + ...
                    "reference plane; over 90° the orbit is retrograde.")
                P("raan", Label="RAAN", Units="deg", Default=earth.orbit(4), Min=-360, Max=360, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="Right ascension of the ascending node.")
                P("argp", Label="Argument of periapsis", Units="deg", Default=earth.orbit(5), Min=-360, Max=360, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="Where the lowest point lies, from the " + ...
                    "ascending node, in the orbit's plane.")
                P("nu", Label="True anomaly", Units="deg", Default=earth.orbit(6), Min=-360, Max=360, ...
                    Group="Initial orbit", VisibleWhen=kepler, Description="Where the spacecraft starts, from " + ...
                    "periapsis: 0 starts at the lowest point.")
                P("rx", Label="X", Units="km", Default=r(1), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting position along the frame's X axis, from the body's centre.")
                P("ry", Label="Y", Units="km", Default=r(2), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting position along Y.")
                P("rz", Label="Z", Units="km", Default=r(3), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting position along Z.")
                P("vx", Label="Vx", Units="km/s", Default=v(1), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting velocity along X (inertial).")
                P("vy", Label="Vy", Units="km/s", Default=v(2), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting velocity along Y.")
                P("vz", Label="Vz", Units="km/s", Default=v(3), Group="Initial orbit", VisibleWhen=cartesian, ...
                    Description="Starting velocity along Z.")
                P("oblateness", Label="J2 oblateness", Type="logical", Default=false, Group="Perturbations", ...
                    Description="The gravity of the body's equatorial bulge: the orbit's plane turns about the " + ...
                    "spin axis (nodal precession) and its ellipse turns in the plane (apsidal precession).")
                P("drag", Label="Atmospheric drag", Type="logical", Default=false, Group="Perturbations", ...
                    VisibleWhen=@(p) p.body == "Earth", Description="Drag in Earth's atmosphere (an " + ...
                    "exponential model to 1000 km, turning with the Earth): low orbits decay and re-enter.")
                P("Cd", Label="Drag coefficient", Default=2.2, Min=0, MinInclusive=false, Max=10, ...
                    Group="Perturbations", VisibleWhen=@(p) p.body == "Earth" && p.drag, ...
                    Description="About 2.2 for a satellite in free molecular flow.")
                P("areaToMass", Label="Area-to-mass ratio", Units="m²/kg", Default=0.01, Min=0, ...
                    MinInclusive=false, Max=10, Group="Perturbations", VisibleWhen=@(p) p.body == "Earth" && p.drag, ...
                    DisplayFormat="%.4g", Description="Frontal area over mass: the ISS is about 0.005 m²/kg, " + ...
                    "a small CubeSat about 0.01–0.02.")
                P("durationOrbits", Label="Duration", Units="orbits", Default=3, Min=0, MinInclusive=false, ...
                    Max=1000, Group="Integration", MarksCustom=false, ...
                    Description="Closed orbits only; open trajectories run for 24 h.")
                P("sampleStep", Label="Output step", Units="s", Default=earth.sampleStep, Min=0, ...
                    MinInclusive=false, Group="Integration", ...
                    Description="Spacing of saved samples (at most 20,000). ode45 picks its own internal steps.")
                P("relTol", Label="Relative tolerance", Default=1e-10, Min=0, MinInclusive=false, Max=1, ...
                    Group="Solver tolerances", Advanced=true, DisplayFormat="%.3g", ...
                    Description="ode45's relative error per step; the Diagnostics tab shows the drift it allows.")
                P("absTol", Label="Absolute tolerance", Default=1e-12, Min=0, MinInclusive=false, Max=1, ...
                    Group="Solver tolerances", Advanced=true, DisplayFormat="%.3g", ...
                    Description="ode45's absolute error per step (km, km/s).")
                P("showBody", Label="Show central body", Type="logical", Default=true, Group="Display", Display=true, ...
                    Description="Draw the body in the Orbit and Animation tabs.")
                P("surface", Label="Body surface", Type="choice", Default="texture", Choices=["texture" "plain"], ...
                    ChoiceLabels=["Map" "Plain color"], Group="Display", Display=true, ...
                    Description="Map: Earth imagery; Mars colored from its topography; banded, cloudy, " + ...
                    "or mottled surfaces for the rest.")
                P("relief", Label="Relief exaggeration", Units="×", Default=25, Min=0, Max=200, Group="Display", ...
                    Display=true, VisibleWhen=@(p) ismember(p.body, ["Earth" "Mars"]), ...
                    Description="Stretches mountains and basins on the Surface tab so they can be seen " + ...
                    "(Everest is 0.14 % of Earth's radius).")
                P("surfaceColors", Label="Surface tab colors", Type="choice", Default="map", ...
                    Choices=["map" "elevation"], ChoiceLabels=["Map" "Elevation"], Group="Display", Display=true, ...
                    VisibleWhen=@(p) ismember(p.body, ["Earth" "Mars"]), ...
                    Description="Color the Surface tab with the map, or by height above the mean radius.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            % Geostationary and Molniya orbits are defined from the equator (from
            % the frame, tilted 23.44° to it, the geostationary track was a
            % figure-eight 47° tall).
            list(end+1) = struct("Name", "Geostationary (Earth)", "Values", struct( ...
                "reference", "equator", "a", 42164, "e", 0, "inc", 0, "raan", 0, "argp", 0, "nu", 0, ...
                "durationOrbits", 1, "sampleStep", 120));
            list(end+1) = struct("Name", "Molniya (Earth)", "Values", struct( ...
                "reference", "equator", "a", 26600, "e", 0.74, "inc", 63.4, "raan", 0, "argp", 270, "nu", 0, ...
                "durationOrbits", 2, "sampleStep", 60));
            list(end+1) = struct("Name", "Escape trajectory (Earth)", "Values", struct( ...
                "inputType", "cartesian", "rx", 7000, "ry", 0, "rz", 0, "vx", 0, "vy", 12, "vz", 0));
            % Sun-synchronous: the J2 nodal precession matches the Sun's
            % apparent motion, 360° per year: cos i = −Ω̇ / (1.5 n J2 (R/a)²).
            earth = dlab.physics.bodyConstants("Earth");
            a = earth.radius + 700;
            n = sqrt(earth.mu / a^3);
            inc = acosd(-2 * pi / (365.2422 * 86400) / (1.5 * n * earth.J2 * (earth.J2Radius / a)^2));
            list(end+1) = struct("Name", "Sun-synchronous (Earth, 700 km, J2)", "Values", struct( ...
                "reference", "equator", "a", a, "e", 0.001, "inc", round(inc, 3), "raan", 0, "argp", 0, ...
                "nu", 0, "oblateness", true, "durationOrbits", 30, "sampleStep", 60));
            list(end+1) = struct("Name", "Molniya with J2 (frozen perigee)", "Values", struct( ...
                "reference", "equator", "a", 26600, "e", 0.74, "inc", 63.435, "argp", 270, "raan", 0, ...
                "nu", 0, "oblateness", true, "durationOrbits", 30, "sampleStep", 300));
            list(end+1) = struct("Name", "Re-entry by drag (Earth, from 250 km)", "Values", struct( ...
                "reference", "equator", "a", earth.radius + 250, "e", 0, "inc", 51.6, "raan", 0, "argp", 0, ...
                "nu", 0, "drag", true, "Cd", 2.2, "areaToMass", 0.02, "durationOrbits", 100, "sampleStep", 60));
        end

        function params = onParamChanged(~, name, params)
            bodies = dlab.sims.orbit.BodyCatalog();
            switch name
                case "body"
                    % Load the body's default orbit and step, as the original app did.
                    body = bodies.(params.body);
                    params.sampleStep = body.sampleStep;
                    if params.body ~= "Custom"
                        [params.mu, params.radius, params.spinRate, params.tilt] = ...
                            deal(body.mu, body.radius, body.spinRate, body.tilt);
                        params.J2 = dlab.physics.bodyConstants(params.body).J2;
                    end
                    params = setKepler(params, body.orbit);
                    [r, v] = defaultCartesian(withConstants(body, params));
                    params = setCartesian(params, r, v);
                case "inputType"
                    % Convert the orbit being shown into the other representation.
                    if params.inputType == "cartesian"
                        [r, v] = keplerToFrame(params, params.reference);
                        params = setCartesian(params, r, v);
                    else
                        params = setKeplerFrom(params, [params.rx params.ry params.rz], ...
                            [params.vx params.vy params.vz]);
                    end
                case "reference"
                    % The same orbit, measured from the other plane.
                    previous = setdiff(["frame" "equator"], params.reference);
                    [r, v] = keplerToFrame(params, previous);
                    params = setKeplerFrom(params, r, v);
            end
        end

        function result = solve(obj, p)
            body = bodyConstants(p);
            if p.inputType == "keplerian"
                if p.a * (1 - p.e) <= body.radius
                    error("dlab:orbit:insideBody", ...
                        "Periapsis (%.1f km) must be above the body surface (radius %.1f km).", ...
                        p.a * (1 - p.e), body.radius);
                end
                [r, v] = keplerToFrame(p, p.reference);
                state = [r(:); v(:)];
            else
                state = [p.rx; p.ry; p.rz; p.vx; p.vy; p.vz];
            end
            options = struct("durationOrbits", p.durationOrbits, "sampleStep", p.sampleStep, ...
                "relativeTolerance", p.relTol, "absoluteTolerance", p.absTol, ...
                "maxOutputPoints", 20000, "hyperbolicDuration", 86400, ...
                "J2", p.oblateness * body.J2, "dragB", (p.drag && p.body == "Earth") * p.Cd * p.areaToMass, ...
                "progressFcn", obj.progressMonitor());
            result = dlab.sims.orbit.simulateOrbit(state, body, options);
            result.bodyName = p.body;
            result.reference = p.reference;
        end

        function titles = outputTabs(~, p)
            titles = ["Orbit" "Ground track" "Surface" "Elements" "Diagnostics"];
            if p.oblateness || (p.drag && p.body == "Earth")
                titles(end+1) = "Perturbations";
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.orbit = dlab.ui.axesIn(containers{"Orbit"}, t, Title="Two-body trajectory", ...
                XLabel="X (km)", YLabel="Y (km)", ZLabel="Z (km)");
            obj.Ax.ground = dlab.ui.axesIn(containers{"Ground track"}, t, Title="Body-fixed ground track", ...
                XLabel="Longitude (deg)", YLabel="Latitude (deg)");
            set(obj.Ax.ground, XLim=[-180 180], YLim=[-90 90], XTick=-180:30:180, YTick=-90:30:90);
            obj.Ax.surface = dlab.ui.axesIn(containers{"Surface"}, t, Title="Surface", ...
                XLabel="X (km)", YLabel="Y (km)", ZLabel="Z (km)");
            g = uigridlayout(containers{"Elements"}, [3 2], Padding=0, BackgroundColor=t.AxesBackground);
            labels = ["a (km)" "e" "i (deg)" "RAAN (deg)" "Argument of periapsis (deg)" "True anomaly (deg)"];
            obj.Ax.elements = gobjects(1, 6);
            for k = 1:6
                obj.Ax.elements(k) = dlab.ui.axesIn(g, t, Title=labels(k), XLabel="Time (min)", YLabel=labels(k));
            end
            g = uigridlayout(containers{"Diagnostics"}, [2 1], Padding=0, BackgroundColor=t.AxesBackground);
            obj.Ax.energy = dlab.ui.axesIn(g, t, Row=1, Title="Specific mechanical energy", ...
                XLabel="Time (h)", YLabel="Relative error");
            obj.Ax.momentum = dlab.ui.axesIn(g, t, Row=2, Title="Specific angular momentum", ...
                XLabel="Time (h)", YLabel="Relative error");
            obj.Ax.node = [];
            obj.Ax.altitude = [];
            if isKey(containers, "Perturbations")
                g = uigridlayout(containers{"Perturbations"}, [2 1], Padding=0, BackgroundColor=t.AxesBackground);
                obj.Ax.node = dlab.ui.axesIn(g, t, Row=1, Title="Orbit plane: node and periapsis (from the equator)", ...
                    XLabel="Time (days)", YLabel="Angle (deg)");
                obj.Ax.altitude = dlab.ui.axesIn(g, t, Row=2, Title="Altitude", XLabel="Time (days)", ...
                    YLabel="Altitude (km)");
            end
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Trajectory animation");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function buildPlaybackControls(obj, parent, theme)
            parent.ColumnWidth = {"fit", 86};
            dlab.ui.label(parent, "View", theme, Role="muted");
            obj.ViewDropdown = uidropdown(parent, Items=obj.Views, Value=obj.ViewMode, ...
                BackgroundColor=theme.SurfaceRaised, FontColor=theme.Text, Tag="dlab.orbit.view", ...
                ValueChangedFcn=@(src, ~) obj.setViewMode(src.Value));
        end

        function setViewMode(obj, mode)
            %SETVIEWMODE Switch the animation between 3-D and a 2-D projection.
            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["3D" "2D XY" "2D XZ" "2D YZ"])}
            end
            obj.ViewMode = mode;
            if ~isempty(obj.ViewDropdown) && isvalid(obj.ViewDropdown)
                obj.ViewDropdown.Value = mode;
            end
            if ~isempty(obj.Result)
                obj.setupAnimation(obj.Result);
                obj.drawFrame(obj.LastTime);
            end
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            body = r.body;
            position = r.state(:, 1:3);

            obj.Textured = ~isfield(params, "surface") || params.surface == "texture";
            obj.Surface = dlab.sims.orbit.bodySurface(bodyNameOf(r), body.color);

            ax = obj.Ax.orbit;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            plot3(ax, position(:,1), position(:,2), position(:,3), Color=t.series(1), LineWidth=1.8);
            if params.showBody
                if obj.Textured
                    % Body-fixed map turned to its orientation at t = 0.
                    globe(ax, obj.Surface, body.radius, 0, bodyRotation(body.tilt, 0), obj.GlobeResolution);
                else
                    [x, y, z] = sphere(36);
                    surf(ax, body.radius*x, body.radius*y, body.radius*z, FaceColor=body.color, ...
                        EdgeColor="none", FaceAlpha=0.8);
                end
            end
            plot3(ax, position(1,1), position(1,2), position(1,3), "o", MarkerSize=9, ...
                MarkerFaceColor=t.series(6), MarkerEdgeColor=t.Text);
            hold(ax, "off");
            axis(ax, "equal");
            view(ax, 35, 24);

            [longitude, latitude] = groundTrack(r);
            ax = obj.Ax.ground;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            if obj.Textured
                image(ax, [-180 180], [90 -90], obj.Surface.Map, AlphaData=0.8, Tag="dlab.orbit.map");
            end
            plot(ax, longitude, latitude, Color=t.series(1), LineWidth=1.5);
            hold(ax, "off");
            set(ax, XLim=[-180 180], YLim=[-90 90], YDir="normal", Layer="top");

            obj.drawSurfaceTab(r, params, longitude, latitude);

            values = elementsOf(r);
            values(:, 3:6) = rad2deg(unwrap(values(:, 3:6), [], 1));
            % Two-body elements are constant: at least these spans (a in km, e,
            % then degrees), so round-off (a ± 1e−6 km) is drawn flat.
            spans = [0.01 1e-6 1e-4 1e-4 1e-4 1e-4];
            for k = 1:6
                ax = obj.Ax.elements(k);
                dlab.ui.clearAxes(ax, KeepLegend=true);
                plot(ax, r.time / 60, values(:, k), Color=t.series(k), LineWidth=1.3);
                hold(ax, "off");
                dlab.ui.minimumSpan(ax, spans(k));
            end

            [energyDrift, momentumDrift] = drifts(r);
            hours = r.time / 3600;
            dlab.ui.clearAxes(obj.Ax.energy, KeepLegend=true);
            plot(obj.Ax.energy, hours, energyDrift, Color=t.series(1), LineWidth=1.5);
            dlab.ui.clearAxes(obj.Ax.momentum, KeepLegend=true);
            plot(obj.Ax.momentum, hours, momentumDrift, Color=t.series(3), LineWidth=1.5);
            hold(obj.Ax.energy, "off");
            hold(obj.Ax.momentum, "off");
            if r.J2 ~= 0
                title(obj.Ax.energy, "Energy (with the J2 potential)");
                title(obj.Ax.momentum, "Angular momentum about the spin axis");
            end
            if r.dragB > 0
                ylabel(obj.Ax.energy, "Relative change (drag)");
                ylabel(obj.Ax.momentum, "Relative change (drag)");
            end
            obj.drawPerturbations(r);

            obj.setupAnimation(r);
            obj.drawFrame(r.time(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                p = r.state(:, 1:3);
                dlab.ui.overlayLine(obj.Ax.orbit, p(:, 1), p(:, 2), run, p(:, 3));
                [longitude, latitude] = groundTrack(r);
                dlab.ui.overlayLine(obj.Ax.ground, longitude, latitude, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for ax = [obj.Ax.orbit obj.Ax.ground obj.Ax.surface obj.Ax.elements obj.Ax.energy obj.Ax.momentum obj.Anim.axes]
                delete(allchild(ax));
            end
            for ax = {obj.Ax.node, obj.Ax.altitude}
                if ~isempty(ax{1}) && isvalid(ax{1})
                    delete(allchild(ax{1}));
                    legend(ax{1}, "off");
                end
            end
        end

        function t = timeVector(~, r)
            t = r.time;
        end

        function [note, level] = resultNote(~, r)
            if r.impacted
                [note, level] = deal("trajectory reached the surface", "warning");
            elseif strlength(r.warning) > 0
                [note, level] = deal("open trajectory: 24 h window", "info");
            else
                [note, level] = deal("", "success");
            end
        end

        function rate = playbackRate(obj, r)
            rate = max(r.time(end) / obj.PlaySeconds, 1);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "satellite")
                return
            end
            obj.LastTime = simTime;
            a = obj.Anim;
            k = dlab.core.frameAt(r.time, simTime);
            p = a.position;
            first = max(1, k - obj.TrailSamples + 1);
            set(a.satellite, XData=p(k,1), YData=p(k,2), ZData=p(k,3));
            set(a.trail, XData=p(first:k,1), YData=p(first:k,2), ZData=p(first:k,3));
            arrow = a.velocity(k,:) / max(norm(r.state(k,4:6)), eps) * a.radius * 0.4;
            set(a.velocityLine, XData=p(k,1) + [0 arrow(1)], YData=p(k,2) + [0 arrow(2)], ...
                ZData=p(k,3) + [0 arrow(3)]);
            rotation = bodyRotation(r.body.tilt, r.body.spinRate * r.time(k));
            if isfield(a, "spin") && ~isempty(a.spin) && isgraphics(a.spin)
                a.spin.Matrix = [rotation zeros(3, 1); 0 0 0 1];
            end
            if isfield(a, "subPoint") && ~isempty(a.subPoint) && isgraphics(a.subPoint)
                set(a.subPoint, XData=a.subPointXYZ(k, 1), YData=a.subPointXYZ(k, 2), ZData=a.subPointXYZ(k, 3));
            end
            for m = 1:4
                points = project((rotation * a.meridianBase{m}).', obj.ViewMode).';
                set(a.meridians(m), XData=points(1,:), YData=points(2,:), ZData=points(3,:));
            end
            a.readout.String = sprintf("t = %s   altitude = %.0f km", ...
                dlab.ui.timeText(r.time(k), Fixed=true), norm(r.state(k,1:3)) - r.body.radius);
        end

        function T = exportTable(~, r)
            T = table(r.time, r.state(:,1), r.state(:,2), r.state(:,3), r.state(:,4), r.state(:,5), ...
                r.state(:,6), r.energy, r.angularMomentum, ...
                VariableNames=["time" "x" "y" "z" "vx" "vy" "vz" "specific_energy" "specific_angular_momentum"]);
            T.Properties.VariableUnits = ["s" "km" "km" "km" "km/s" "km/s" "km/s" "km²/s²" "km²/s"];
        end

        function T = summaryTable(~, r)
            % Numbers at full precision (metrics reads them, for sweeps and
            % lessons); Format sets how the Summary shows them, and Display
            % holds the rows that are text.
            first = elementsOf(r);
            first = first(1, :);
            [energyDrift, momentumDrift] = drifts(r);
            altitude = vecnorm(r.state(:, 1:3), 2, 2) - r.body.radius;
            if r.impacted
                outcome = "reached the surface";
            elseif strlength(r.warning) > 0
                outcome = r.warning;
            else
                outcome = "completed";
            end
            angles = rad2deg(first(3:6));
            angles(abs(angles) < 1e-9 | abs(angles - 360) < 1e-9) = 0;   % rounding noise
            eccentricity = first(2) * (first(2) > 1e-12);
            altitude(abs(altitude) < 1e-6) = 0;                          % touching the surface
            rows = {                                % Quantity, Value, Units, Format, Display
                "Semi-major axis", first(1), "km", "%.6g", ""
                "Eccentricity", eccentricity, "", "%.6g", ""
                "Inclination", angles(1), "deg", "%.5g", ""
                "RAAN", angles(2), "deg", "%.5g", ""
                "Argument of periapsis", angles(3), "deg", "%.5g", ""
                "True anomaly", angles(4), "deg", "%.5g", ""
            };
            if isfinite(r.period)
                rows(end+1, :) = {"Period", r.period / 60, "min", "%.5g", ""};
            else
                rows(end+1, :) = {"Period", NaN, "", "", "open trajectory"};
            end
            rows = [rows; {
                "Lowest altitude", min(altitude), "km", "%.6g", ""
                "Highest altitude", max(altitude), "km", "%.6g", ""
                "Samples", NaN, "", "", string(numel(r.time))
                "Max relative energy " + driftWord(r), max(abs(energyDrift)), "", "%.3e", ""
                "Max relative angular-momentum " + driftWord(r), max(abs(momentumDrift)), "", "%.3e", ""
                "Outcome", NaN, "", "", outcome}];
            for row = perturbationRows(r)'
                rows(end+1, :) = {row{1}, row{2}, row{3}, "%.5g", ""}; %#ok<AGROW>
            end
            surfaceData = dlab.sims.orbit.bodySurface(bodyNameOf(r), r.body.color);
            if ~isempty(surfaceData.Elevation)
                [longitude, latitude] = groundTrack(r);
                terrain = elevationAt(surfaceData.Elevation, latitude, longitude) / 1000;
                clearance = altitude(:) - terrain(:);
                rows(end+1, :) = {"Lowest altitude above terrain", min(clearance), "km", "%.6g", ""};
            end
            if surfaceData.Source ~= ""
                rows(end+1, :) = {"Surface data", NaN, "", "", surfaceData.Source};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Molniya (Earth)", "Tab", "Orbit", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Two-body motion:  r'' = −μ r / |r|³, integrated with ode45. The run stops if the " + ...
                "trajectory reaches the body's surface."
                ""
                "Perturbations (optional): J2 oblateness, the gravity of the equatorial bulge, which " + ...
                "turns the orbit's plane about the spin axis at Ω̇ = −1.5 n J2 (R/p)² cos i and its " + ...
                "ellipse at ω̇ = 0.75 n J2 (R/p)² (5 cos² i − 1); and drag in Earth's atmosphere " + ...
                "(Vallado's exponential model to 1000 km, turning with the Earth), " + ...
                "a = −½ ρ (Cd A/m) |v_rel| v_rel, which shrinks low orbits until they re-enter."
                ""
                "Closed orbits run for the chosen number of periods; open (escape) trajectories run " + ...
                "for 24 hours. The ground track accounts for the body's spin rate and axial tilt. " + ...
                "Energy and angular-momentum drift measure numerical error, not physics (with J2 the " + ...
                "energy includes its potential and the momentum is about the spin axis, both still " + ...
                "conserved; drag takes both away)."
                ""
                "Surfaces: Earth imagery (NASA Blue Marble, public domain) and Earth and Mars " + ...
                "topography (SRTM and MOLA spherical-harmonic models to degree 90); the other bodies " + ...
                "are drawn procedurally from their color. Topography is for display and the " + ...
                "terrain clearance in the Summary; the dynamics treat the body as a sphere."
            ], newline);
        end
    end

    methods (Access = private)
        function drawPerturbations(obj, r)
            %DRAWPERTURBATIONS Node and periapsis (from the equator) and
            %   altitude over time, with the J2 rates from theory.
            ax = obj.Ax.node;
            if isempty(ax) || ~isvalid(ax)
                return
            end
            t = obj.Theme;
            days = r.time / 86400;
            E = r.equatorial;
            altitude = vecnorm(r.state(:, 1:3), 2, 2) - r.body.radius;
            % After a re-entry the axes follow the flight above 100 km: in the
            % last minutes the osculating elements swing wildly (a − R fell to
            % −3200 km) and flattened the days of decay before.
            shown = true(size(days));
            if r.impacted && any(altitude > 100)
                shown = altitude > 100;
            end
            dlab.ui.clearAxes(ax, KeepLegend=true);
            node = rad2deg(unwrap(E(:, 4)));
            plot(ax, days, node, Color=t.series(1), LineWidth=1.3, DisplayName="Node Ω");
            periapsis = rad2deg(unwrap(E(:, 5)));
            if E(1, 2) > 0.01
                plot(ax, days, periapsis, Color=t.series(3), LineWidth=1.3, DisplayName="Periapsis ω");
            end
            [nodeRate, apsisRate] = j2Rates(r);
            if r.J2 ~= 0 && isfinite(nodeRate)
                plot(ax, days, node(1) + nodeRate * days, "--", Color=t.series(2), LineWidth=1.2, ...
                    DisplayName=sprintf("J2 theory: %.4g°/day", nodeRate));
                if E(1, 2) > 0.01
                    plot(ax, days, periapsis(1) + apsisRate * days, ":", Color=t.series(4), LineWidth=1.2, ...
                        DisplayName=sprintf("J2 theory: %.4g°/day", apsisRate));
                end
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
            if ~all(shown)
                angles = node(shown);
                if E(1, 2) > 0.01
                    angles = [angles; periapsis(shown)];
                end
                ylim(ax, [min(angles) max(angles)] + [-1 1] * max(1, 0.1 * (max(angles) - min(angles))));
            end

            ax = obj.Ax.altitude;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            plot(ax, days, altitude, Color=t.series(1), LineWidth=1, DisplayName="Altitude");
            plot(ax, days, E(:, 1) - r.body.radius, Color=t.series(2), LineWidth=1.4, ...
                DisplayName="Semi-major axis − radius");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
            if r.dragB > 0 && r.impacted
                title(ax, sprintf("Altitude: re-entered after %.2f days", r.time(end) / 86400));
            end
            if ~all(shown)
                ylim(ax, [0, 1.08 * max(altitude)]);
            end
        end

        function drawSurfaceTab(obj, r, params, longitude, latitude)
            %DRAWSURFACETAB The body close up, in body-fixed axes, with
            %   exaggerated relief and the track below the spacecraft.
            t = obj.Theme;
            ax = obj.Ax.surface;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            surfaceData = obj.Surface;
            body = r.body;
            relief = 0;
            if isfield(params, "relief")
                relief = params.relief;
            end
            byElevation = isfield(params, "surfaceColors") && params.surfaceColors == "elevation" ...
                && ~isempty(surfaceData.Elevation);
            if byElevation
                [x, y, z] = sphere(120);
                [lat, lon] = nodeLatLon(x, y, z);
                heights = elevationAt(surfaceData.Elevation, lat, lon);
                scale = 1 + relief * heights / (1000 * body.radius);
                surf(ax, body.radius * scale .* x, body.radius * scale .* y, body.radius * scale .* z, heights, ...
                    EdgeColor="none", FaceColor="interp", FaceLighting="none", Tag="dlab.orbit.globe");
                colormap(ax, t.divergingMap());
                limit = max(abs(heights(:)));
                clim(ax, [-limit limit]);
                c = colorbar(ax, Color=t.AxesForeground);
                c.Label.String = "Elevation (m)";
            else
                colorbar(ax, "off");
                globe(ax, surfaceData, body.radius, relief, eye(3), 120);
            end
            % Ground track and the point below the spacecraft, just above the surface.
            lift = 1.02 * body.radius * (1 + relief * max([0; surfaceData.Elevation(:)]) / (1000 * body.radius));
            track = lift * [cosd(latitude) .* cosd(longitude); cosd(latitude) .* sind(longitude); sind(latitude)];
            plot3(ax, track(1, :), track(2, :), track(3, :), Color=t.series(6), LineWidth=1.4);
            position = r.state(:, 1:3).';
            fixed = zeros(size(position));
            for k = 1:size(position, 2)
                fixed(:, k) = bodyRotation(body.tilt, body.spinRate * r.time(k)).' * position(:, k);
            end
            obj.Anim.subPointXYZ = (lift * fixed ./ vecnorm(fixed)).';
            obj.Anim.subPoint = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=9, MarkerFaceColor=t.series(6), ...
                MarkerEdgeColor=t.Text, Tag="dlab.orbit.subPoint");
            hold(ax, "off");
            axis(ax, "equal");
            view(ax, 35, 20);
            heading = "Surface (body-fixed)";
            if relief > 0 && ~isempty(surfaceData.Elevation)
                heading = heading + sprintf(", relief ×%g", relief);
            end
            title(ax, heading);
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            mode = obj.ViewMode;
            a = obj.Anim;
            a.position = project(r.state(:, 1:3), mode);
            a.velocity = project(r.state(:, 4:6), mode);
            plot3(ax, a.position(:,1), a.position(:,2), a.position(:,3), "--", Color=[t.series(1) 0.45]);
            a.radius = max(r.body.radius, max(vecnorm(r.state(:, 1:3), 2, 2)) * 0.04);
            a.spin = gobjects(0);
            if mode == "3D" && obj.Textured && ~isempty(obj.Surface)
                % A textured globe in body axes, turned each frame (drawFrame).
                a.spin = hgtransform(ax);
                globe(a.spin, obj.Surface, a.radius, 0, eye(3), 48);
            else
                [x, y, z] = sphere(30);
                surface = project(a.radius * [x(:) y(:) z(:)], mode);
                surf(ax, reshape(surface(:,1), size(x)), reshape(surface(:,2), size(y)), ...
                    reshape(surface(:,3), size(z)), FaceColor=r.body.color, EdgeColor="none", FaceAlpha=0.72);
            end
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=2.5);
            a.satellite = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=10, MarkerFaceColor=t.series(6), ...
                MarkerEdgeColor=t.Text);
            a.velocityLine = plot3(ax, NaN, NaN, NaN, Color=t.series(6), LineWidth=2, Tag="AnimationVelocity");
            polar = linspace(0, pi, 50);
            a.meridianBase = cell(4, 1);
            a.meridians = gobjects(4, 1);
            for m = 1:4
                lon = (m - 1) * pi / 2;
                a.meridianBase{m} = a.radius * [sin(polar) * cos(lon); sin(polar) * sin(lon); cos(polar)];
                a.meridians(m) = plot3(ax, NaN, NaN, NaN, Color=r.body.ringColor, LineWidth=0.7, ...
                    Tag="AnimationMeridian" + m);
            end
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, ...
                FontSize=t.scaled(10), Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            axis(ax, "equal");
            if mode == "3D"
                xlabel(ax, "X (km)"); ylabel(ax, "Y (km)"); zlabel(ax, "Z (km)");
                view(ax, 35, 24);
            else
                axesNames = char(erase(mode, "2D "));
                xlabel(ax, axesNames(1) + " (km)"); ylabel(ax, axesNames(2) + " (km)"); zlabel(ax, "");
                view(ax, 2);
            end
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function name = bodyNameOf(r)
% Results from before surfaces were added have no body name.
name = "Custom";
if isfield(r, "bodyName")
    name = string(r.bodyName);
end
end

function h = globe(parent, surfaceData, radius, relief, rotation, resolution)
%GLOBE A sphere of RADIUS draped with the body's map, optionally with
%   relief (exaggeration factor; heights in m, radius in km), turned by
%   ROTATION (body to world). PARENT is an axes or an hgtransform.
[x, y, z] = sphere(resolution);
scale = ones(size(x));
if relief > 0 && ~isempty(surfaceData.Elevation)
    [lat, lon] = nodeLatLon(x, y, z);
    scale = 1 + relief * elevationAt(surfaceData.Elevation, lat, lon) / (1000 * radius);
end
points = rotation * [x(:)'; y(:)'; z(:)'] .* (radius * scale(:)');
h = surface(reshape(points(1, :), size(x)), reshape(points(2, :), size(y)), reshape(points(3, :), size(z)), ...
    Parent=parent, CData=flipud(surfaceData.Map), FaceColor="texturemap", EdgeColor="none", ...
    FaceLighting="none", Tag="dlab.orbit.globe");
end

function [lat, lon] = nodeLatLon(x, y, z)
lat = rad2deg(asin(max(min(z, 1), -1)));
lon = rad2deg(atan2(y, x));
end

function h = elevationAt(heights, latitude, longitude)
%ELEVATIONAT Heights (m) of a 180×360 map (pixel centres, north up,
%   −180° left) at LATITUDE and LONGITUDE in degrees (any shape).
lonGrid = [-180.5, -179.5:179.5, 180.5];
latGrid = -89.5:89.5;
padded = flipud([heights(:, end), heights, heights(:, 1)]);
lat = min(max(latitude, -89.5), 89.5);
lon = mod(longitude + 180, 360) - 180;
h = interp2(lonGrid, latGrid, padded, lon, lat, "linear");
end

function body = bodyConstants(p)
bodies = dlab.sims.orbit.BodyCatalog();
body = withConstants(bodies.(p.body), p);
end

function body = withConstants(body, p)
% A custom body takes its physical constants from the inputs.
if p.body == "Custom"
    [body.mu, body.radius, body.spinRate, body.tilt] = deal(p.mu, p.radius, p.spinRate, p.tilt);
    body.J2 = 0;
    if isfield(p, "J2")
        body.J2 = p.J2;
    end
    body.J2Radius = p.radius;
else
    constants = dlab.physics.bodyConstants(p.body);
    [body.J2, body.J2Radius] = deal(constants.J2, constants.J2Radius);
end
end

function [r, v] = keplerToFrame(p, reference)
% Position and velocity in the frame from the element inputs, measured
% from the frame's XY plane or from the body's (tilted) equator.
body = bodyConstants(p);
[r, v] = dlab.physics.kep2cart(p.a, p.e, deg2rad(p.inc), deg2rad(p.raan), deg2rad(p.argp), ...
    deg2rad(p.nu), body.mu);
if reference == "equator"
    toFrame = dlab.physics.roty(deg2rad(body.tilt));
    [r, v] = deal(toFrame * r(:), toFrame * v(:));
end
end

function params = setKeplerFrom(params, r, v)
% The element inputs for a frame position and velocity (closed orbits only).
body = bodyConstants(params);
if params.reference == "equator"
    toEquator = dlab.physics.roty(deg2rad(body.tilt)).';
    [r, v] = deal(toEquator * r(:), toEquator * v(:));
end
elements = dlab.physics.cart2kep(r(:).', v(:).', body.mu);
if elements(1) > 0 && elements(2) < 1
    params = setKepler(params, [elements(1:2), rad2deg(elements(3:6))]);
end
end

function values = elementsOf(r)
% The element history measured from the plane the inputs use.
values = r.elements;
if isfield(r, "reference") && r.reference == "equator"
    values = r.equatorial;
end
end

function [nodeRate, apsisRate] = j2Rates(r)
% Secular J2 rates (deg/day) for the initial equatorial elements.
E = r.equatorial(1, :);
[a, e, inc] = deal(E(1), E(2), E(3));
nodeRate = NaN;
apsisRate = NaN;
if ~(a > 0 && e < 1)
    return
end
n = sqrt(r.body.mu / a^3);
factor = n * r.J2 * (r.body.J2Radius / (a * (1 - e^2)))^2;
nodeRate = rad2deg(-1.5 * factor * cos(inc)) * 86400;
apsisRate = rad2deg(0.75 * factor * (5 * cos(inc)^2 - 1)) * 86400;
end

function rows = perturbationRows(r)
% Measured and predicted effects of J2 and drag.
rows = cell(0, 3);
days = r.time / 86400;
E = r.equatorial;
if numel(days) < 3 || days(end) <= 0
    return
end
if r.J2 ~= 0
    [nodeRate, apsisRate] = j2Rates(r);
    fit = polyfit(days, rad2deg(unwrap(E(:, 4))), 1);
    rows(end+1, :) = {"Node drift (measured)", fit(1), "deg/day"};
    rows(end+1, :) = {"Node drift (J2 theory)", nodeRate, "deg/day"};
    if E(1, 2) > 0.01
        fit = polyfit(days, rad2deg(unwrap(E(:, 5))), 1);
        rows(end+1, :) = {"Periapsis drift (measured)", fit(1), "deg/day"};
        rows(end+1, :) = {"Periapsis drift (J2 theory)", apsisRate, "deg/day"};
    end
end
if r.dragB > 0
    rows(end+1, :) = {"Semi-major axis change", E(end, 1) - E(1, 1), "km"};
    rows(end+1, :) = {"Decay rate (mean)", (E(end, 1) - E(1, 1)) / days(end), "km/day"};
    if r.impacted
        rows(end+1, :) = {"Time to re-entry", days(end), "days"};
    end
end
end

function word = driftWord(r)
% Drift is numerical error; with drag the change is physical.
word = "drift";
if r.dragB > 0
    word = "change";
end
end

function [r, v] = defaultCartesian(body)
dynamics = dlab.sims.orbit.OrbitalDynamics();
o = body.orbit;
[r, v] = dynamics.kep2cart(o(1), o(2), deg2rad(o(3)), deg2rad(o(4)), deg2rad(o(5)), deg2rad(o(6)), body.mu);
end

function params = setKepler(params, values)
names = ["a" "e" "inc" "raan" "argp" "nu"];
for k = 1:6
    params.(names(k)) = values(k);
end
params.e = min(max(params.e, 0), 1 - eps);
for name = ["raan" "argp" "nu"]
    params.(name) = mod(params.(name) + 360, 720) - 360;     % keep within [−360, 360)
end
end

function params = setCartesian(params, r, v)
values = [r(:); v(:)];
names = ["rx" "ry" "rz" "vx" "vy" "vz"];
for k = 1:6
    params.(names(k)) = values(k);
end
end

function [longitude, latitude] = groundTrack(r)
position = r.state(:, 1:3).';
untilted = dlab.physics.roty(deg2rad(r.body.tilt)).' * position;
angle = r.body.spinRate * r.time.';
x = cos(angle) .* untilted(1,:) + sin(angle) .* untilted(2,:);
y = -sin(angle) .* untilted(1,:) + cos(angle) .* untilted(2,:);
latitude = rad2deg(atan2(untilted(3,:), hypot(x, y)));
longitude = rad2deg(atan2(y, x));
breaks = [false, abs(diff(longitude)) > 180];     % no lines across the map edge
longitude(breaks) = NaN;
latitude(breaks) = NaN;
end

function [energyDrift, momentumDrift] = drifts(r)
energyDrift = (r.energy - r.energy(1)) / max(abs(r.energy(1)), eps);
% Relative to |h| at the start: with J2 the conserved quantity is the
% component along the spin axis, which is negative for a retrograde orbit
% and 0 for a polar one (dividing by it gave 2.6e10 for the SSO).
scale = abs(r.angularMomentum(1));
if isfield(r, "angularMomentumScale")
    scale = r.angularMomentumScale;
end
momentumDrift = (r.angularMomentum - r.angularMomentum(1)) / max(scale, eps);
end

function position = project(position, mode)
switch mode
    case "2D XY"
        position(:, 3) = 0;
    case "2D XZ"
        position = [position(:,1), position(:,3), zeros(size(position, 1), 1)];
    case "2D YZ"
        position = [position(:,2), position(:,3), zeros(size(position, 1), 1)];
end
end

function rotation = bodyRotation(tiltDegrees, spinAngle)
rotation = dlab.physics.roty(deg2rad(tiltDegrees)) * dlab.physics.rotz(spinAngle);
end
