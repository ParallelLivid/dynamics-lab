classdef QuadrotorPlugin < dlab.core.TimeDomainPlugin
    %QUADROTORPLUGIN A rigid-body quadrotor (X configuration) flown by a
    %   cascaded position and attitude controller: hover, steps, waypoint
    %   missions, wind, rotor saturation, and a motor failure. Solved by
    %   dlab.sims.quadrotor.simulateQuadrotor.

    properties (Constant)
        Id = "quadrotor"
        Title = "Quadrotor"
        Category = "Aerospace"
        Summary = "A quadcopter's cascaded flight control: hover, steps, waypoints, wind, rotor limits, and a motor failure."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        RotorNames = ["1 front-left" "2 front-right" "3 rear-right" "4 rear-left"]
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            C = @dlab.core.TableColumn;
            isSetpoint = @(p) p.mission == "setpoint";
            isWaypoints = @(p) p.mission == "waypoints";
            flies = @(p) p.controller ~= "off";
            specs = [
                P("mission", Label="Mission", Type="choice", Default="waypoints", Choices=["setpoint" "waypoints"], ...
                    ChoiceLabels=["Setpoints" "Waypoints"], Group="Mission", ...
                    Description="Setpoints: x, y, z, and yaw, each constant or changing in time (a step, ramp, …). " + ...
                    "Waypoints: the setpoint flies through a list of points at the cruise speed.")
                P("xRef", Label="Setpoint x", Type="schedule", Units="m", Default=0, Min=-1000, Max=1000, ...
                    Group="Mission", VisibleWhen=isSetpoint, ...
                    Description="Where to hover along x (world, m): a constant, or a step, ramp, … in time.")
                P("yRef", Label="Setpoint y", Type="schedule", Units="m", Default=0, Min=-1000, Max=1000, ...
                    Group="Mission", VisibleWhen=isSetpoint, ...
                    Description="Where to hover along y (world, m).")
                P("zRef", Label="Setpoint z (height)", Type="schedule", Units="m", Default=3, Min=0, Max=1000, ...
                    Group="Mission", VisibleWhen=isSetpoint, ...
                    Description="The height to hold (z is up; the ground is at 0).")
                P("yawRef", Label="Setpoint yaw", Type="schedule", Units="°", Default=0, Min=-720, Max=720, ...
                    Group="Mission", VisibleWhen=isSetpoint, Description="Heading of the nose, from +x toward +y.")
                P("waypoints", Label="Waypoints", Type="table", Group="Mission", MinRows=1, MaxRows=30, ...
                    VisibleWhen=isWaypoints, Description="Flown in order from the start, in straight lines; " + ...
                    "the nose turns to each yaw along the leg, and the quadrotor waits there for the hold time.", ...
                    Columns=[
                        C("x", Label="x", Units="m", Min=-1000, Max=1000, Default=0)
                        C("y", Label="y", Units="m", Min=-1000, Max=1000, Default=0)
                        C("z", Label="z", Units="m", Min=0, Max=1000, Default=3)
                        C("yaw", Label="Yaw", Units="°", Min=-720, Max=720, Default=0)
                        C("hold", Label="Hold", Units="s", Min=0, Max=600, Default=1)
                    ], Default=boxMission())
                P("cruiseSpeed", Label="Cruise speed", Units="m/s", Default=2, Min=0.1, Max=30, Group="Mission", ...
                    VisibleWhen=isWaypoints, Description="Speed of the setpoint between waypoints.")
                P("x0", Label="Start x", Units="m", Default=0, Min=-1000, Max=1000, Group="Start", ...
                    Description="Start position along x (world).")
                P("y0", Label="Start y", Units="m", Default=0, Min=-1000, Max=1000, Group="Start", ...
                    Description="Start position along y (world).")
                P("z0", Label="Start z (height)", Units="m", Default=0, Min=0, Max=1000, Group="Start", ...
                    Description="0: on the ground. The rotors start at hover speed.")
                P("yaw0", Label="Start yaw", Units="°", Default=0, Min=-180, Max=180, Group="Start", ...
                    Description="Start heading: the nose's direction, anticlockwise from the x axis seen from above.")
                P("roll0", Label="Start roll", Units="°", Default=0, Min=-180, Max=180, Group="Start", ...
                    Description="Start roll angle (3-2-1 angles: yaw, then pitch, then roll).")
                P("pitch0", Label="Start pitch", Units="°", Default=0, Min=-89, Max=89, Group="Start", ...
                    Description="Start pitch angle.")
                P("p0", Label="Start roll rate p", Units="°/s", Default=0, Min=-3600, Max=3600, Group="Start rates", ...
                    Advanced=true, ...
                    Description="Start roll rate (body x).")
                P("q0", Label="Start pitch rate q", Units="°/s", Default=0, Min=-3600, Max=3600, Group="Start rates", ...
                    Advanced=true, ...
                    Description="Start pitch rate (body y).")
                P("r0", Label="Start yaw rate r", Units="°/s", Default=0, Min=-3600, Max=3600, Group="Start rates", ...
                    Advanced=true, ...
                    Description="Start yaw rate (body z).")
                P("controller", Label="Controller", Type="choice", Default="position", ...
                    Choices=["position" "attitude" "off"], ChoiceLabels=["Position" "Attitude" "Off"], ...
                    Group="Controller", ...
                    Description="Position: position → tilt and thrust → attitude → torques → rotors. " + ...
                    "Attitude: you command roll and pitch; the height loop still runs. Off: no feedback.")
                P("rollCmd", Label="Roll command", Type="schedule", Units="°", Default=0, Min=-60, Max=60, ...
                    Group="Controller", VisibleWhen=@(p) p.controller == "attitude", ...
                    Description="Roll angle the attitude controller holds (a constant, or changing in time).")
                P("pitchCmd", Label="Pitch command", Type="schedule", Units="°", Default=0, Min=-60, Max=60, ...
                    Group="Controller", VisibleWhen=@(p) p.controller == "attitude", ...
                    Description="Positive pitch tips the nose down and flies forward (+x).")
                P("offThrust", Label="Rotor thrust", Units="% of hover", Default=100, Min=0, Max=1000, ...
                    Group="Controller", VisibleWhen=@(p) p.controller == "off", ...
                    Description="Every rotor gives this share of m g / 4. 0: free fall; 100: no net force.")
                P("maxTilt", Label="Tilt limit", Units="°", Default=30, Min=1, Max=80, Group="Controller", ...
                    VisibleWhen=@(p) p.controller == "position", ...
                    Description="The position loop never asks for more tilt than this.")
                P("KpXY", Label="Horizontal Kp", Units="1/s²", Default=1.5, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Acceleration per metre of horizontal position error.")
                P("KdXY", Label="Horizontal Kd", Units="1/s", Default=2.2, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Horizontal acceleration per m/s of velocity error.")
                P("KiXY", Label="Horizontal Ki", Units="1/s³", Default=0.3, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Removes the steady offset a wind leaves; 0 turns it off.")
                P("KpZ", Label="Height Kp", Units="1/s²", Default=4, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Vertical acceleration per metre of height error.")
                P("KdZ", Label="Height Kd", Units="1/s", Default=3.2, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Vertical acceleration per m/s of climb-rate error.")
                P("KiZ", Label="Height Ki", Units="1/s³", Default=0.5, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Vertical acceleration per metre-second of accumulated height error (within the capture band).")
                P("KrRP", Label="Roll/pitch stiffness", Units="1/s²", Default=144, Min=0, Max=1e5, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Angular acceleration per radian of attitude error: ωn = √Kr (rad/s).")
                P("KwRP", Label="Roll/pitch damping", Units="1/s", Default=19, Min=0, Max=1e4, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, Description="ζ = Kw / (2 √Kr).")
                P("KrYaw", Label="Yaw stiffness", Units="1/s²", Default=9, Min=0, Max=1e5, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Yaw angular acceleration per radian of heading error.")
                P("KwYaw", Label="Yaw damping", Units="1/s", Default=5, Min=0, Max=1e4, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="Yaw angular acceleration per rad/s of yaw rate.")
                P("band", Label="Integral capture band", Units="m", Default=1, Min=0, Max=1000, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="The integrals run only this close to the setpoint, so a big step does not wind them up.")
                P("aIntMax", Label="Integral limit", Units="m/s²", Default=3, Min=0, Max=100, ...
                    Group="Controller gains", Advanced=true, VisibleWhen=flies, ...
                    Description="The most acceleration the integrals may add (anti-windup).")
                P("m", Label="Mass", Units="kg", Default=1, Min=0.01, Max=1000, Group="Airframe", ...
                    Description="Mass of the quadrotor.")
                P("L", Label="Arm length", Units="m", Default=0.2, Min=0.01, Max=10, Group="Airframe", ...
                    Description="From the centre to each rotor.")
                P("Tmax", Label="Rotor thrust limit", Units="N", Default=6, Min=0.01, Max=1e4, Group="Airframe", ...
                    Description="Most thrust per rotor; 4 Tmax / (m g) is the thrust-to-weight ratio.")
                P("tauMotor", Label="Rotor time constant", Units="s", Default=0.03, Min=0.005, Max=1, Group="Airframe", ...
                    Description="Each rotor's speed follows its command as a first-order lag.")
                P("Ixx", Label="Ixx (roll)", Units="kg·m²", Default=0.01, Min=1e-5, Max=1000, Group="Airframe details", ...
                    Advanced=true, ...
                    Description="Moment of inertia about the body x (roll) axis.")
                P("Iyy", Label="Iyy (pitch)", Units="kg·m²", Default=0.01, Min=1e-5, Max=1000, Group="Airframe details", ...
                    Advanced=true, ...
                    Description="Moment of inertia about the body y (pitch) axis.")
                P("Izz", Label="Izz (yaw)", Units="kg·m²", Default=0.018, Min=1e-5, Max=1000, Group="Airframe details", ...
                    Advanced=true, ...
                    Description="Moment of inertia about the body z (yaw) axis.")
                P("kf", Label="Thrust coefficient kf", Units="N/(rad/s)²", Default=1e-5, Min=1e-9, Max=1, ...
                    Group="Airframe details", Advanced=true, DisplayFormat="%.4g", Description="T = kf Ω².")
                P("km", Label="Drag-torque coefficient km", Units="N·m/(rad/s)²", Default=1.5e-7, Min=0, Max=1, ...
                    Group="Airframe details", Advanced=true, DisplayFormat="%.4g", ...
                    Description="Q = km Ω², the torque that yaws the body; yaw authority grows with km/kf.")
                P("kd", Label="Body drag", Units="N·s²/m²", Default=0.02, Min=0, Max=100, Group="Airframe details", ...
                    Advanced=true, Description="Drag force −kd |v − w| (v − w), with w the wind.")
                P("g", Label="Gravity", Units="m/s²", Default=9.81, Min=0.1, Max=100, Group="Airframe details", ...
                    Advanced=true, ...
                    Description="Gravitational acceleration.")
                P("windSpeed", Label="Wind speed", Type="schedule", Units="m/s", Default=0, Min=0, Max=50, ...
                    Group="Wind", Description="A step makes a gust front; a sine, a gusty breeze.")
                P("windDir", Label="Wind toward", Units="°", Default=90, Min=-360, Max=360, Group="Wind", ...
                    Description="Direction the wind blows toward, from +x toward +y (90 = along +y).")
                P("failRotor", Label="Failed rotor", Type="choice", Default="none", Choices=["none" "1" "2" "3" "4"], ...
                    ChoiceLabels=["None" "1" "2" "3" "4"], ...
                    Group="Motor failure", ...
                    Description="Which rotor fails: 1 front-left, 2 front-right, 3 rear-right, 4 rear-left (numbered clockwise seen from above; 1 and 3 spin clockwise).")
                P("failTime", Label="Fails at", Units="s", Default=2, Min=0, Max=1e4, Group="Motor failure", ...
                    VisibleWhen=@(p) p.failRotor ~= "none", ...
                    Description="When the rotor fails.")
                P("failScale", Label="Thrust left", Units="fraction", Default=0, Min=0, Max=1, Group="Motor failure", ...
                    VisibleWhen=@(p) p.failRotor ~= "none", Description="0: the rotor stops; 0.5: half its thrust.")
                P("duration", Label="Duration", Units="s", Default=20, Min=0.1, Max=1e4, Group="Simulation", ...
                    MarksCustom=false, ...
                    Description="Length of the run; it ends earlier if the quadrotor reaches the ground.")
                P("dt", Label="Output step", Units="s", Default=0.02, Min=0.001, Max=1, Group="Simulation", ...
                    Advanced=true, ...
                    Description="Spacing of saved samples; ode45 picks its own steps (at most 0.01 s).")
                P("crashSpeed", Label="Crash speed", Units="m/s", Default=1, Min=0, Max=100, Group="Simulation", ...
                    Advanced=true, Description="Reaching the ground faster than this is a crash; slower, a landing.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            hover = struct("mission", "setpoint", "xRef", 0, "yRef", 0, "zRef", 3, "yawRef", 0, ...
                "x0", 0, "y0", 0, "z0", 3);
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Hover (recover from a 20° tilt)", "Values", ...
                with(hover, "roll0", 20, "duration", 5));
            list(end+1) = struct("Name", "Step in height (3 → 6 m)", "Values", ...
                with(hover, "zRef", S("step", Value=3, Amplitude=3, Start=1), "duration", 8));
            list(end+1) = struct("Name", "Box waypoint mission", "Values", struct());
            list(end+1) = struct("Name", "Crosswind gust (7 m/s)", "Values", ...
                with(hover, "windSpeed", S("step", Value=0, Amplitude=7, Start=1), "windDir", 90, "duration", 12));
            list(end+1) = struct("Name", "Motor failure (rotor 1 stops at 2 s)", "Values", ...
                with(hover, "zRef", 10, "z0", 10, "failRotor", "1", "failTime", 2, "failScale", 0, "duration", 8));
            list(end+1) = struct("Name", "Aggressive gains (oscillatory)", "Values", ...
                with(hover, "xRef", S("step", Value=0, Amplitude=2, Start=1), "KpXY", 8, "KdXY", 1, "KiXY", 0, ...
                "KrRP", 250, "KwRP", 12, "duration", 10));
            list(end+1) = struct("Name", "Saturated climb (3 → 20 m)", "Values", ...
                with(hover, "zRef", S("step", Value=3, Amplitude=17, Start=1), "Tmax", 3.5, "KpZ", 6, "KdZ", 4, ...
                "duration", 12));
        end

        function result = solve(obj, p)
            q = obj.engineParams(p);
            q.progressFcn = obj.progressMonitor();
            result = dlab.sims.quadrotor.simulateQuadrotor(q);
            result.windDir = p.windDir;
            result.windSpeed = p.windSpeed;
        end

        function titles = outputTabs(~, ~)
            titles = ["3-D path" "Position" "Attitude" "Rotor thrusts"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.path = dlab.ui.axesIn(containers{"3-D path"}, t, Title="Flight path", ...
                XLabel="x (m)", YLabel="y (m)", ZLabel="z (m)");
            grid = uigridlayout(containers{"Position"}, [3 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.x = dlab.ui.axesIn(grid, t, Row=1, Title="Position (dashed: setpoint)", YLabel="x (m)");
            obj.Ax.y = dlab.ui.axesIn(grid, t, Row=2, YLabel="y (m)");
            obj.Ax.z = dlab.ui.axesIn(grid, t, Row=3, XLabel="Time (s)", YLabel="z (m)");
            grid = uigridlayout(containers{"Attitude"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.tilt = dlab.ui.axesIn(grid, t, Row=1, Title="Roll and pitch (dashed: inner-loop target)", ...
                YLabel="Angle (°)");
            obj.Ax.yaw = dlab.ui.axesIn(grid, t, Row=2, Title="Yaw", XLabel="Time (s)", YLabel="Yaw (°)");
            obj.Ax.thrust = dlab.ui.axesIn(containers{"Rotor thrusts"}, t, Title="Rotor thrusts", ...
                XLabel="Time (s)", YLabel="Thrust (N)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Flight", XLabel="x (m)", YLabel="y (m)", ZLabel="z (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, ~)
            obj.Result = r;
            t = obj.Theme;
            time = r.t;

            ax = obj.Ax.path;
            dlab.ui.clearAxes(ax);
            if ~isempty(r.path)
                plot3(ax, r.path.points(:, 1), r.path.points(:, 2), r.path.points(:, 3), "--", Color=t.TextMuted, ...
                    LineWidth=1.2, DisplayName="Planned path");
                plot3(ax, r.path.points(2:end, 1), r.path.points(2:end, 2), r.path.points(2:end, 3), "d", ...
                    MarkerSize=8, MarkerFaceColor=t.series(4), MarkerEdgeColor=t.Text, DisplayName="Waypoints");
            else
                plot3(ax, r.reference(:, 1), r.reference(:, 2), r.reference(:, 3), "d", MarkerSize=8, ...
                    MarkerFaceColor=t.series(4), MarkerEdgeColor=t.Text, DisplayName="Setpoints");
            end
            plot3(ax, r.pos(:, 1), r.pos(:, 2), r.pos(:, 3), Color=t.series(1), LineWidth=2.2, DisplayName="Path");
            plot3(ax, r.pos(1, 1), r.pos(1, 2), r.pos(1, 3), "o", MarkerSize=9, MarkerFaceColor=t.Success, ...
                MarkerEdgeColor=t.Text, DisplayName="Start");
            plot3(ax, r.pos(end, 1), r.pos(end, 2), r.pos(end, 3), "s", MarkerSize=9, ...
                MarkerFaceColor=endColor(t, r), MarkerEdgeColor=t.Text, DisplayName=endLabel(r));
            hold(ax, "off");
            cubeLimits(ax, r);
            view(ax, -35, 25);
            grid(ax, "on");
            dlab.ui.legend(ax, t, "Location", "best");

            names = ["x" "y" "z"];
            for k = 1:3
                ax = obj.Ax.(names(k));
                dlab.ui.clearAxes(ax);
                plot(ax, time, r.reference(:, k), "--", Color=t.TextMuted, LineWidth=1.3, DisplayName="Setpoint");
                plot(ax, time, r.pos(:, k), Color=t.series(k), LineWidth=1.8, DisplayName=names(k));
                obj.markFailure(ax, r);
                hold(ax, "off");
                dlab.ui.minimumSpan(ax, 0.02);       % m
            end

            ax = obj.Ax.tilt;
            dlab.ui.clearAxes(ax);
            plot(ax, time, rad2deg(r.attitudeCmd(:, 1)), "--", Color=t.series(2), LineWidth=1.1, HandleVisibility="off");
            plot(ax, time, rad2deg(r.attitudeCmd(:, 2)), "--", Color=t.series(3), LineWidth=1.1, HandleVisibility="off");
            plot(ax, time, rad2deg(r.euler(:, 1)), Color=t.series(2), LineWidth=1.8, DisplayName="Roll φ");
            plot(ax, time, rad2deg(r.euler(:, 2)), Color=t.series(3), LineWidth=1.8, DisplayName="Pitch θ");
            obj.markFailure(ax, r);
            hold(ax, "off");
            dlab.ui.minimumSpan(ax, 0.2);            % degrees
            dlab.ui.legend(ax, t, "Location", "best");
            ax = obj.Ax.yaw;
            dlab.ui.clearAxes(ax);
            plot(ax, time, rad2deg(r.reference(:, 4)), "--", Color=t.TextMuted, LineWidth=1.3, DisplayName="Setpoint");
            plot(ax, time, rad2deg(r.euler(:, 3)), Color=t.series(4), LineWidth=1.8, DisplayName="Yaw ψ");
            obj.markFailure(ax, r);
            hold(ax, "off");
            dlab.ui.minimumSpan(ax, 0.2);
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.thrust;
            dlab.ui.clearAxes(ax);
            [starts, stops] = runsOf(r.saturated, time);
            if ~isempty(starts)
                xregion(ax, starts, stops, FaceColor=t.Warning, FaceAlpha=0.12, EdgeColor="none", ...
                    DisplayName="Mixer saturated");
            end
            yline(ax, r.model.Tmax, "--", sprintf("limit %.3g N", r.model.Tmax), Color=t.TextMuted, ...
                LineWidth=1.4, LabelHorizontalAlignment="left", HandleVisibility="off");
            yline(ax, 0, "--", Color=t.TextMuted, LineWidth=1.4, HandleVisibility="off");
            yline(ax, r.hoverThrust, ":", "hover m g / 4", Color=t.TextMuted, LineWidth=1.2, ...
                LabelHorizontalAlignment="left", HandleVisibility="off");
            for k = 1:4
                plot(ax, time, r.thrust(:, k), Color=t.series(k), LineWidth=1.6, DisplayName="Rotor " + obj.RotorNames(k));
            end
            obj.markFailure(ax, r);
            hold(ax, "off");
            ylim(ax, [-0.05 1.12] * r.model.Tmax);
            dlab.ui.legend(ax, t, "Location", "best");

            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.path, r.pos(:, 1), r.pos(:, 2), run, r.pos(:, 3));
                dlab.ui.overlayLine(obj.Ax.x, r.t, r.pos(:, 1), run);
                dlab.ui.overlayLine(obj.Ax.y, r.t, r.pos(:, 2), run);
                dlab.ui.overlayLine(obj.Ax.z, r.t, r.pos(:, 3), run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            delete(allchild(obj.Anim.axes));
            legend(obj.Anim.axes, "off");
            colorbar(obj.Anim.axes, "off");
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "rotors")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            here = r.pos(k, :)';
            R = dlab.physics.Quaternion.toDcm(r.quat(k, :)');
            place = @(V) (R * V' + here)';
            hub = place(a.hub);
            set(a.arms, XData=hub(:, 1), YData=hub(:, 2), ZData=hub(:, 3));
            nose = place(a.nose);
            set(a.nose3, XData=nose(:, 1), YData=nose(:, 2), ZData=nose(:, 3));
            for i = 1:4
                disc = place(a.discs{i});
                set(a.rotors(i), Vertices=disc, FaceVertexCData=r.thrust(k, i));
            end
            failed = r.failRotor > 0 && r.t(k) >= r.failTime;
            if failed
                set(a.rotors(r.failRotor), EdgeColor=obj.Theme.Danger, LineWidth=2.5);
            elseif r.failRotor > 0
                set(a.rotors(r.failRotor), EdgeColor=obj.Theme.Text, LineWidth=1);
            end
            set(a.trail, XData=r.pos(1:k, 1), YData=r.pos(1:k, 2), ZData=r.pos(1:k, 3));
            set(a.shadow, XData=here(1), YData=here(2), ZData=0);
            set(a.drop, XData=[here(1) here(1)], YData=[here(2) here(2)], ZData=[0 here(3)]);
            set(a.setpoint, XData=r.reference(k, 1), YData=r.reference(k, 2), ZData=r.reference(k, 3));
            a.readout.String = sprintf("t = %.2f s   (%.2f, %.2f, %.2f) m   tilt %.1f°   yaw %.0f°   " + ...
                "T = %.2f %.2f %.2f %.2f N", simTime, here, rad2deg(r.tilt(k)), rad2deg(r.euler(k, 3)), r.thrust(k, :));
        end

        function T = exportTable(~, r)
            T = array2table([r.t r.pos r.vel rad2deg(r.euler) rad2deg(r.omega) r.thrust r.rotorSpeed * 30 / pi ...
                r.reference(:, 1:3) rad2deg(r.reference(:, 4)) double(r.saturated) r.quat], VariableNames=[ ...
                "time" "x" "y" "z" "vx" "vy" "vz" "roll" "pitch" "yaw" "p" "q" "r" ...
                "thrust1" "thrust2" "thrust3" "thrust4" "speed1" "speed2" "speed3" "speed4" ...
                "x_setpoint" "y_setpoint" "z_setpoint" "yaw_setpoint" "saturated" "q0" "q1" "q2" "q3"]);
            T.Properties.VariableUnits = ["s" "m" "m" "m" "m/s" "m/s" "m/s" "deg" "deg" "deg" ...
                "deg/s" "deg/s" "deg/s" "N" "N" "N" "N" "rpm" "rpm" "rpm" "rpm" "m" "m" "m" "deg" "" "" "" "" ""];
        end

        function T = summaryTable(~, r)
            s = r.stats;
            rows = {                                % Quantity, Value, Units, Format, Display
                "Termination", NaN, "", "", string(r.termination)
                "Hover thrust per rotor", r.hoverThrust, "N", "%.4f", ""
                "Hover rotor speed", r.hoverSpeed * 30 / pi, "rpm", "%.0f", ""
                "Thrust-to-weight ratio", r.thrustToWeight, "", "%.3g", ""
                "Final position error", s.finalError, "m", "%.3g", ""
                "Max tilt", rad2deg(s.maxTilt), "deg", "%.2f", ""
                "Peak rotor thrust", s.peakThrust, "N", "%.3f", ""
                "Time saturated", s.timeSaturated, "s", "%.2f", ""
                "Max yaw rate", rad2deg(s.maxYawRate), "deg/s", "%.1f", ""
                "Final height", r.pos(end, 3), "m", "%.3f", ""
            };
            if isfinite(s.settlingTime)
                rows(end+1, :) = {"Settling time", s.settlingTime, "s", "%.2f", ""};
            end
            if isfinite(s.overshoot)
                rows(end+1, :) = {"Overshoot", s.overshoot, "%", "%.1f", ""};
            end
            if isfinite(r.contactSpeed)
                rows(end+1, :) = {"Ground contact speed", r.contactSpeed, "m/s", "%.2f", ""};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            switch r.termination
                case "crashed"
                    [note, level] = deal(sprintf("crashed at t = %.2f s (%.1f m/s)", r.t(end), r.contactSpeed), ...
                        "warning");
                case "landed"
                    [note, level] = deal(sprintf("touched down at t = %.2f s", r.t(end)), "warning");
                otherwise
                    [note, level] = deal("", "success");
            end
        end

        function lin = linearization(obj, p)
            q = obj.engineParams(p);
            if q.controller == "off"
                lin = [];
                return
            end
            if q.mission == "waypoints"
                first = q.waypoints(1, :);
                hover = [first(1:3) first(4)];
                where = sprintf("the first waypoint (%.3g, %.3g, %.3g) m", hover(1:3));
            else
                hover = q.reference(0)';
                where = sprintf("the setpoint at t = 0 (%.3g, %.3g, %.3g) m", hover(1:3));
            end
            if q.controller == "attitude"
                hover(1:2) = [p.x0 p.y0];
                where = sprintf("%.3g m", hover(3));
            end
            m = dlab.sims.quadrotor.hoverLinearization(q, hover);
            groups = m.Groups;
            % Which axis an integral belongs to: five slow modes were all
            % "Integral (slow)".
            groups(m.StateNames == "∫ez") = "height integral";
            groups(ismember(m.StateNames, ["∫ex" "∫ey"])) = "horizontal integral";
            scale = m.Scale;
            lin = struct("F", @(x) m.G(x, m.U0), "X0", m.X0, "StateNames", m.StateNames, ...
                "Reference", "hovering at " + where + " in still air, controller on (rotor limits not reached)", ...
                "Classify", @(lambda, V) quadModes(lambda, V, groups, scale), "Scale", scale, ...
                "G", m.G, "U0", m.U0, "InputNames", m.InputNames, "H", m.H, "OutputNames", m.OutputNames);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Box waypoint mission", "Tab", "Animation", "Time", 9);
        end

        function description = about(~)
            description = join([
                "A rigid quadrotor in the X configuration (body x forward, y left, z up; world z up, ground at z = 0)."
                "Rotors 1 front-left and 3 rear-right spin clockwise, 2 front-right and 4 rear-left counter-clockwise."
                "Each gives thrust T = kf Ω² and a drag torque km Ω² that yaws the body the other way. The rotor " + ...
                "speeds lag their commands (time constant τ), and each thrust stays within 0 … Tmax."
                "  m v' = R ẑ ΣT − m g ẑ − kd |v − w| (v − w),   I ω' = τ − ω × I ω,   q' = ½ q ⊗ [0; ω]"
                ""
                "Cascaded control:"
                "  position: a = Kp e + Kd ė + Ki ∫e (integrals only within the capture band, and limited)"
                "  thrust vector F = m (a + g ẑ), tilted at most the tilt limit; thrust = F · body z"
                "  attitude: τ = ω × I ω + I (−Kr · 2 q_e,vec − Kw ω), q_e = q_target⁻¹ ⊗ q"
                "  mixer: [F; τx; τy; τz] = A T inverted. When rotors saturate it keeps roll and pitch first, " + ...
                "then shifts the collective thrust, and gives up yaw last."
                ""
                "Missions: setpoints (each a constant, step, ramp, …) or waypoints flown at a cruise speed. " + ...
                "Wind enters through the drag. A motor failure scales one rotor's thrust (and torque) at a set " + ...
                "time: its diagonal partner must slow to keep the level, the other pair's torque is no longer " + ...
                "balanced, and the quadrotor spins up in yaw."
                ""
                "The run stops at the ground: a crash above the crash speed, else a landing. Modes and Bode: the " + ...
                "closed loop near hover, with the setpoints (and a force along x) as inputs."
            ], newline);
        end
    end

    methods (Access = private)
        function q = engineParams(~, p)
            limits = [-1000 1000];
            xs = dlab.core.Schedule.toFunction(p.xRef, limits);
            ys = dlab.core.Schedule.toFunction(p.yRef, limits);
            zs = dlab.core.Schedule.toFunction(p.zRef, [0 1000]);
            yaws = dlab.core.Schedule.toFunction(p.yawRef, [-720 720]);
            rolls = dlab.core.Schedule.toFunction(p.rollCmd, [-60 60]);
            pitches = dlab.core.Schedule.toFunction(p.pitchCmd, [-60 60]);
            speed = dlab.core.Schedule.toFunction(p.windSpeed, [0 50]);
            direction = [cosd(p.windDir); sind(p.windDir); 0];
            W = p.waypoints;
            if istable(W)
                W = [W.x W.y W.z deg2rad(W.yaw) W.hold];
            end
            failRotor = 0;
            if p.failRotor ~= "none"
                failRotor = str2double(p.failRotor);
            end
            q = struct("m", p.m, "L", p.L, "Ixx", p.Ixx, "Iyy", p.Iyy, "Izz", p.Izz, "kf", p.kf, "km", p.km, ...
                "tauMotor", p.tauMotor, "Tmax", p.Tmax, "kd", p.kd, "g", p.g, "controller", string(p.controller), ...
                "KpXY", p.KpXY, "KdXY", p.KdXY, "KiXY", p.KiXY, "KpZ", p.KpZ, "KdZ", p.KdZ, "KiZ", p.KiZ, ...
                "KrRP", p.KrRP, "KwRP", p.KwRP, "KrYaw", p.KrYaw, "KwYaw", p.KwYaw, "maxTilt", deg2rad(p.maxTilt), ...
                "band", p.band, "aIntMax", p.aIntMax, "offThrust", p.offThrust / 100, ...
                "mission", string(p.mission), ...
                "reference", @(t) [xs(t); ys(t); zs(t); deg2rad(yaws(t))], ...
                "waypoints", W, "cruiseSpeed", p.cruiseSpeed, ...
                "attitudeCommand", @(t) deg2rad([rolls(t); pitches(t)]), ...
                "wind", @(t) speed(t) * direction, ...
                "pos0", [p.x0; p.y0; p.z0], "vel0", zeros(3, 1), "euler0", deg2rad([p.roll0; p.pitch0; p.yaw0]), ...
                "omega0", deg2rad([p.p0; p.q0; p.r0]), "failRotor", failRotor, "failTime", p.failTime, ...
                "failScale", p.failScale, "crashSpeed", p.crashSpeed, "tEnd", p.duration, "dt", p.dt);
        end

        function markFailure(obj, ax, r)
            if r.failRotor > 0 && r.failTime <= r.t(end)
                xline(ax, r.failTime, "--", "rotor " + r.failRotor + " fails", Color=obj.Theme.Danger, ...
                    LineWidth=1.2, LabelVerticalAlignment="bottom", HandleVisibility="off");
            end
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            [lo, hi] = cubeLimits(ax, r);
            patch(ax, [lo(1) hi(1) hi(1) lo(1)], [lo(2) lo(2) hi(2) hi(2)], [0 0 0 0], t.Grid, FaceAlpha=0.25, ...
                EdgeColor="none", HandleVisibility="off");
            plot3(ax, r.pos(:, 1), r.pos(:, 2), r.pos(:, 3), Color=t.Grid, LineWidth=1, HandleVisibility="off");
            if ~isempty(r.path)
                plot3(ax, r.path.points(2:end, 1), r.path.points(2:end, 2), r.path.points(2:end, 3), "d", ...
                    MarkerSize=8, MarkerFaceColor=t.series(4), MarkerEdgeColor=t.Text, DisplayName="Waypoints");
            end
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=2, HandleVisibility="off");
            a.drop = plot3(ax, NaN, NaN, NaN, ":", Color=t.TextMuted, LineWidth=1, HandleVisibility="off");
            a.shadow = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=6, MarkerFaceColor=t.TextMuted, ...
                MarkerEdgeColor="none", HandleVisibility="off");
            a.setpoint = plot3(ax, NaN, NaN, NaN, "+", MarkerSize=12, LineWidth=2, Color=t.series(5), ...
                DisplayName="Setpoint");
            % The airframe, drawn larger than life so it shows at the scale of the flight.
            span = max(hi - lo);
            L = r.model.L * max(1, 0.1 * span / r.model.L);
            rotors = r.model.rotorPositions / r.model.L * L;
            a.hub = [rotors(1, :); rotors(3, :); NaN NaN NaN; rotors(2, :); rotors(4, :)];
            a.nose = [0 0 0; 0.9 * L 0 0];
            angles = linspace(0, 2 * pi, 25)';
            radius = 0.42 * L;
            a.discs = cell(1, 4);
            a.rotors = gobjects(1, 4);
            for i = 1:4
                a.discs{i} = rotors(i, :) + [radius * cos(angles), radius * sin(angles), zeros(25, 1) + 0.05 * L];
                a.rotors(i) = patch(ax, Faces=1:25, Vertices=a.discs{i}, FaceVertexCData=0, FaceColor="flat", ...
                    CDataMapping="scaled", EdgeColor=t.Text, LineWidth=1, FaceAlpha=0.85, HandleVisibility="off");
            end
            a.arms = plot3(ax, NaN, NaN, NaN, Color=t.Text, LineWidth=3, HandleVisibility="off");
            a.nose3 = plot3(ax, NaN, NaN, NaN, Color=t.Accent, LineWidth=3.5, DisplayName="Nose (+x body)");
            colormap(ax, t.sequentialMap(64));
            clim(ax, [0 r.model.Tmax]);
            thrustBar = colorbar(ax, Color=t.AxesForeground);
            thrustBar.Label.String = "Rotor thrust (N)";
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            view(ax, -35, 25);
            grid(ax, "on");
            dlab.ui.legend(ax, t, "Location", "northeast");
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers

function W = boxMission()
% Take off, fly a 4 m square at 3 m, turning the nose along each side.
W = table([0; 4; 4; 0; 0], [0; 0; 4; 4; 0], [3; 3; 3; 3; 3], [0; 0; 90; 180; 270], [1; 1; 1; 1; 1], ...
    VariableNames=["x" "y" "z" "yaw" "hold"]);
end

function s = with(s, varargin)
for k = 1:2:numel(varargin)
    s.(varargin{k}) = varargin{k + 1};
end
end

function [starts, stops] = runsOf(flag, t)
% Time intervals where FLAG is true.
flag = flag(:);
edges = diff([false; flag; false]);
starts = t(edges(1:end-1) == 1);
ends = edges(2:end) == -1;              % the last sample of each run
stops = t([false; ends(1:end-1)] | (ends & (1:numel(t))' == numel(t)));
end

function [lo, hi] = cubeLimits(ax, r)
% Equal-scale limits around the flight (and its waypoints), from the ground up.
points = r.pos;
if ~isempty(r.path)
    points = [points; r.path.points(:, 1:3)];
end
lo = min(points, [], 1);
hi = max(points, [], 1);
span = max([hi - lo, 2]) * 1.15;
centre = (lo + hi) / 2;
lo = centre - span / 2;
hi = centre + span / 2;
lo(3) = 0;
hi(3) = max([1.3 * max(points(:, 3)), 0.4 * span, 1]);
set(ax, XLim=[lo(1) hi(1)], YLim=[lo(2) hi(2)], ZLim=[lo(3) hi(3)]);
daspect(ax, [1 1 1]);
end

function c = endColor(t, r)
c = t.Danger;
if r.termination == "completed"
    c = t.TextMuted;
end
end

function label = endLabel(r)
label = "End";
if r.termination ~= "completed"
    label = "End (" + r.termination + ")";
end
end

function labels = quadModes(lambda, V, groups, scale)
%QUADMODES Name each mode by the states that dominate its eigenvector.
names = dictionary(["horizontal" "altitude" "attitude" "yaw" "integral" "horizontal integral" ...
    "height integral" "rotor"], ["Horizontal position" "Height" "Roll/pitch" "Yaw" "Integral (slow)" ...
    "Horizontal integral (slow)" "Height integral (slow)" "Rotor lag"]);
W = abs(V) ./ scale(:);
kinds = unique(groups, "stable");
labels = strings(numel(lambda), 1);
tol = 1e-9 * max(1, max(abs(lambda)));
for k = 1:numel(lambda)
    share = arrayfun(@(g) sum(W(groups == g, k).^2), kinds);
    [~, best] = max(share);
    labels(k) = names(kinds(best));
    if abs(imag(lambda(k))) > tol
        labels(k) = labels(k) + " oscillation";
    end
end
end
