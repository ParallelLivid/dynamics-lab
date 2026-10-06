classdef Flight6dofPlugin < dlab.core.TimeDomainPlugin
    %FLIGHT6DOFPLUGIN Rigid-body 6DOF flight of a small aircraft model:
    %   12-state body/NED integration with presets for the classic
    %   longitudinal and lateral dynamic modes.

    properties (Constant)
        Id = "flight6dof"
        Title = "6DOF Flight"
        Category = "Aerospace"
        Summary = "Rigid-body flight dynamics: trim, modes, wind, and an altitude, heading, and speed autopilot."
        SchemaVersion = 2       % 2: quaternion attitude (older scenarios keep Euler angles)
    end

    properties (Constant, Access = private)
        Initial = ["u0" "v0" "w0" "p0" "q0" "r0" "phi0" "theta0" "psi0" "alt0"]
        Controls = ["throttle" "elevator" "aileron" "rudder"]
        Aircraft = ["m" "Ix" "Iy" "Iz" "S" "Tmax" "CLa" "CD0" "CDa2" "CLmax" "Kctrl" ...
            "damp_p" "damp_q" "damp_r" "alpha_trim" "pitch_alpha" "roll_beta" "yaw_beta"]
        Sim = ["Vmax" "groundAltitude" "attitudeLimitDeg" "RelTol" "AbsTol" "MaxStep" "TIMEOUT" "Solver"]
        PresetNames = ["Straight flight" "Glide" "Phugoid mode" "Short-period mode" ...
            "Dutch roll mode" "Roll subsidence mode"]
        Gains = ["Kh" "Khi" "Khd" "Ktheta" "Kq" "Kpsi" "Kphi" "Kp" "Kv" "Kvi" "maxPitch" "maxBank" "bandH" "bandV"]
    end

    properties (Constant, Access = private)
        ModeKeys = ["phugoid" "dutchroll" "rollsubsidence" "spiral"]
        ModeLabels = ["Phugoid" "Dutch roll" "Roll subsidence" "Spiral"]
        ModeControls = ["elevator" "rudder" "aileron" "aileron"]
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
        IdTable                 % Mode ID comparison table
        TuneDropdown
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            d = flatten(dlab.sims.flight6dof.defaultConfig());
            ic = "Initial conditions";
            Short = "%.4g";     % the trimmed state is exact; four figures are shown (19.99, not 19.9932)
            specs = [
                P("u0", Label="u₀ (forward)", Units="m/s", Default=d.u0, Min=-200, Max=200, Group=ic, DisplayFormat=Short, ...
                    Description="Initial forward velocity in body axes (relative to the air or the ground: see Wind).")
                P("v0", Label="v₀ (side)", Units="m/s", Default=d.v0, Min=-50, Max=50, Group=ic, DisplayFormat=Short, ...
                    Description="Initial sideways velocity in body axes, to the right: a sideslip, which starts a Dutch roll.")
                P("w0", Label="w₀ (down)", Units="m/s", Default=d.w0, Min=-50, Max=50, Group=ic, DisplayFormat=Short, ...
                    Description="Initial downward velocity in body axes; with u₀ it sets the angle of attack, atan(w₀/u₀).")
                P("p0", Label="p₀ roll rate", Units="rad/s", Default=d.p0, Min=-5, Max=5, Group=ic, DisplayFormat=Short, ...
                    Description="Initial roll rate about the body x axis (right wing down is positive).")
                P("q0", Label="q₀ pitch rate", Units="rad/s", Default=d.q0, Min=-5, Max=5, Group=ic, DisplayFormat=Short, ...
                    Description="Initial pitch rate about the body y axis (nose up is positive).")
                P("r0", Label="r₀ yaw rate", Units="rad/s", Default=d.r0, Min=-5, Max=5, Group=ic, DisplayFormat=Short, ...
                    Description="Initial yaw rate about the body z axis (nose right is positive).")
                P("phi0", Label="φ₀ roll", Units="deg", Default=d.phi0, Min=-180, Max=180, Group=ic, DisplayFormat=Short, ...
                    Description="Initial bank angle (right wing down is positive).")
                P("theta0", Label="θ₀ pitch", Units="deg", Default=d.theta0, Min=-90, Max=90, Group=ic, DisplayFormat=Short, ...
                    Description="With Euler angles it must stay inside the pitch limit.")
                P("psi0", Label="ψ₀ heading", Units="deg", Default=d.psi0, Min=-180, Max=180, Group=ic, DisplayFormat=Short, ...
                    Description="Initial heading, clockwise from north.")
                P("alt0", Label="h₀ altitude", Units="m", Default=d.alt0, Min=1, Max=10000, Group=ic, ...
                    Description="Initial altitude; the air density (ISA) depends on it.")
                P("throttle", Label="Throttle", Type="schedule", Default=d.throttle, Min=0, Max=1, Group="Controls", DisplayFormat=Short, ...
                    Description="Fraction of maximum thrust.")
                P("elevator", Label="Pitch torque", Type="schedule", Default=d.elevator, Min=-1, Max=1, Group="Controls", DisplayFormat=Short, ...
                    Description="Normalised body torque command: moment = Kctrl × command. " + ...
                    "A doublet excites the short-period mode; a pulse, the phugoid.")
                P("aileron", Label="Roll torque", Type="schedule", Default=d.aileron, Min=-1, Max=1, Group="Controls", ...
                    Description="A short pulse shows roll subsidence; a doublet, the Dutch roll.")
                P("rudder", Label="Yaw torque", Type="schedule", Default=d.rudder, Min=-1, Max=1, Group="Controls", ...
                    Description="Normalised yaw torque command: moment = Kctrl × command. A doublet excites the Dutch roll.")
                P("duration", Label="Duration", Units="s", Default=d.duration, Min=1, Max=600, ...
                    Group="Simulation", MarksCustom=false, ...
                    Description="Length of the run; it stops earlier at the ground, the airspeed or pitch limit, or the wall-clock limit.")
                % Autopilot: holds on top of the pilot's inputs (see autopilotLaw)
                P("apAltitude", Label="Hold altitude", Type="logical", Default=false, Group="Autopilot", ...
                    Description="Pitch the aircraft to climb or descend to the reference altitude, then hold it " + ...
                    "(elevator, on top of the Pitch torque input).")
                P("apAltitudeRef", Label="Altitude", Units="m", Default=100, Min=1, Max=10000, Group="Autopilot", ...
                    VisibleWhen=@(p) p.apAltitude, ...
                    Description="The altitude to climb or descend to, and hold.")
                P("apHeading", Label="Hold heading", Type="logical", Default=false, Group="Autopilot", ...
                    Description="Bank to turn onto the reference heading, then hold it (aileron).")
                P("apHeadingRef", Label="Heading", Units="deg", Default=0, Min=-180, Max=360, Group="Autopilot", ...
                    VisibleWhen=@(p) p.apHeading, Description="Clockwise from north (0); 90 is east.")
                P("apSpeed", Label="Hold airspeed", Type="logical", Default=false, Group="Autopilot", ...
                    Description="Throttle to reach and hold the reference airspeed (an autothrottle). " + ...
                    "Use it with altitude hold: alone, more thrust only makes the aircraft climb.")
                P("apSpeedRef", Label="Airspeed", Units="m/s", Default=20, Min=1, Max=300, Group="Autopilot", ...
                    VisibleWhen=@(p) p.apSpeed, ...
                    Description="The airspeed to reach and hold (relative to the air).")
                P("Kh", Label="Altitude gain Kh", Units="rad/m", Default=0.02, Min=0, Max=1, Group="Autopilot gains", ...
                    Advanced=true, Description="Pitch command per metre of altitude error.")
                P("Khi", Label="Altitude integral Khi", Units="rad/(m·s)", Default=0.003, Min=0, Max=1, ...
                    Group="Autopilot gains", Advanced=true, ...
                    Description="Pitch command per metre-second of accumulated altitude error (only inside the capture band).")
                P("Khd", Label="Climb-rate damping Khd", Units="rad·s/m", Default=0.03, Min=0, Max=1, ...
                    Group="Autopilot gains", Advanced=true, ...
                    Description="Pitch command per m/s of climb rate: it damps the altitude response.")
                P("Ktheta", Label="Pitch gain Kθ", Units="1/rad", Default=1, Min=0, Max=100, Group="Autopilot gains", ...
                    Advanced=true, Description="Pitch torque per radian of pitch error.")
                P("Kq", Label="Pitch-rate damping Kq", Units="s/rad", Default=0.05, Min=0, Max=10, ...
                    Group="Autopilot gains", Advanced=true, ...
                    Description="Pitch torque per rad/s of pitch rate.")
                P("Kpsi", Label="Heading gain Kψ", Default=1, Min=0, Max=20, Group="Autopilot gains", Advanced=true, ...
                    Description="Bank command (rad) per radian of heading error.")
                P("Kphi", Label="Bank gain Kφ", Units="1/rad", Default=0.1, Min=0, Max=100, Group="Autopilot gains", ...
                    Advanced=true, ...
                    Description="Roll torque per radian of bank error.")
                P("Kp", Label="Roll-rate damping Kp", Units="s/rad", Default=0.02, Min=0, Max=10, ...
                    Group="Autopilot gains", Advanced=true, ...
                    Description="Roll torque per rad/s of roll rate.")
                P("Kv", Label="Airspeed gain Kv", Units="1/(m/s)", Default=0.1, Min=0, Max=10, ...
                    Group="Autopilot gains", Advanced=true, Description="Throttle per m/s of airspeed error.")
                P("Kvi", Label="Airspeed integral Kvi", Units="1/m", Default=0.03, Min=0, Max=10, ...
                    Group="Autopilot gains", Advanced=true, ...
                    Description="Throttle per metre of accumulated airspeed error (only inside the capture band).")
                P("maxPitch", Label="Pitch limit", Units="deg", Default=15, Min=1, Max=60, Group="Autopilot gains", ...
                    Advanced=true, Description="Largest pitch command away from level flight.")
                P("maxBank", Label="Bank limit", Units="deg", Default=30, Min=1, Max=75, Group="Autopilot gains", ...
                    Advanced=true, ...
                    Description="Largest bank command.")
                P("bandH", Label="Altitude capture band", Units="m", Default=5, Min=0.1, Max=1000, ...
                    Group="Autopilot gains", Advanced=true, Description="The altitude integral runs only " + ...
                    "this close to the reference, so a large climb does not wind it up and overshoot.")
                P("bandV", Label="Airspeed capture band", Units="m/s", Default=3, Min=0.1, Max=100, ...
                    Group="Autopilot gains", Advanced=true, Description="The airspeed integral runs only " + ...
                    "this close to the reference.")
                % Wind (steady; no gusts)
                P("windSpeed", Label="Wind speed", Units="m/s", Default=0, Min=0, Max=30, Group="Wind", ...
                    Description="Steady horizontal wind. The aerodynamics use the velocity relative to the air.")
                P("windFrom", Label="Wind from", Units="deg", Default=270, Min=0, Max=360, Group="Wind", ...
                    VisibleWhen=@(p) p.windSpeed > 0, ...
                    Description="Direction the wind blows from, clockwise from north (270 = a westerly).")
                P("windVertical", Label="Vertical wind", Units="m/s", Default=0, Min=-10, Max=10, Group="Wind", ...
                    Description="Rising (+) or sinking (−) air, as in a thermal or a downdraft.")
                P("windProfile", Label="Wind profile", Type="choice", Default="uniform", Choices=["uniform" "powerlaw"], ...
                    ChoiceLabels=["Uniform" "Power law"], Group="Wind", ...
                    VisibleWhen=@(p) p.windSpeed > 0, ...
                    Description="Uniform: the same at every height. Power law: stronger with height, " + ...
                    "speed × (altitude / reference height)^(1/7).")
                P("windRef", Label="Reference height", Units="m", Default=10, Min=1, Max=1000, Group="Wind", ...
                    VisibleWhen=@(p) p.windSpeed > 0 && p.windProfile == "powerlaw", ...
                    Description="Height at which the power-law wind equals the wind speed.")
                P("icFrame", Label="Initial velocity relative to", Type="choice", Default="air", ...
                    Choices=["air" "ground"], ChoiceLabels=["The air" "The ground"], Group="Wind", ...
                    VisibleWhen=@(p) p.windSpeed > 0 || p.windVertical ~= 0, ...
                    Description="Relative to the air keeps a trimmed aircraft trimmed: it drifts with the wind.")
                % Aircraft (the original "⚙ Props" dialog, plus the stability terms presets change)
                P("m", Label="Mass", Units="kg", Default=d.m, Min=0.01, Max=500, Group="Aircraft", Advanced=true, ...
                    Description="Mass of the aircraft.")
                P("Ix", Label="Ix (roll)", Units="kg·m²", Default=d.Ix, Min=0.001, Max=50, Group="Aircraft", Advanced=true, ...
                    Description="Moment of inertia about the body x (roll) axis.")
                P("Iy", Label="Iy (pitch)", Units="kg·m²", Default=d.Iy, Min=0.001, Max=50, Group="Aircraft", Advanced=true, ...
                    Description="Moment of inertia about the body y (pitch) axis.")
                P("Iz", Label="Iz (yaw)", Units="kg·m²", Default=d.Iz, Min=0.001, Max=50, Group="Aircraft", Advanced=true, ...
                    Description="Moment of inertia about the body z (yaw) axis.")
                P("S", Label="Wing area", Units="m²", Default=d.S, Min=0.01, Max=50, Group="Aircraft", Advanced=true, ...
                    Description="Wing reference area for lift and drag.")
                P("Tmax", Label="Maximum thrust", Units="N", Default=d.Tmax, Min=0, Max=5000, Group="Aircraft", Advanced=true, ...
                    Description="Thrust at full throttle, along the body x axis.")
                P("CLa", Label="Lift slope CLα", Units="1/rad", Default=d.CLa, Min=0.5, Max=10, Group="Aircraft", Advanced=true, ...
                    Description="Lift-curve slope: CL ≈ CLα α at small angles of attack.")
                P("CLmax", Label="CL max", Default=d.CLmax, Min=0.1, Max=3, Group="Aircraft", Advanced=true, ...
                    Description="Where the lift coefficient saturates (a smooth stall).")
                P("CD0", Label="Zero-lift drag CD₀", Default=d.CD0, Min=0, Max=2, Group="Aircraft", Advanced=true, ...
                    Description="Drag coefficient at zero angle of attack.")
                P("CDa2", Label="Drag polar CDα²", Default=d.CDa2, Min=0, Max=10, Group="Aircraft", Advanced=true, ...
                    Description="Growth of drag with angle of attack: CD = CD₀ + CDα² α².")
                P("Kctrl", Label="Control torque Kctrl", Units="N·m", Default=d.Kctrl, Min=0.01, Max=100, ...
                    Group="Aircraft", Advanced=true, ...
                    Description="Torque per unit of control command: moment = Kctrl × command.")
                P("damp_p", Label="Roll damping", Units="1/s", Default=d.damp_p, Min=0, Max=20, Group="Aircraft", Advanced=true, ...
                    Description="Roll angular deceleration per rad/s of roll rate (the same at every airspeed).")
                P("damp_q", Label="Pitch damping", Units="1/s", Default=d.damp_q, Min=0, Max=20, Group="Aircraft", Advanced=true, ...
                    Description="Pitch angular deceleration per rad/s of pitch rate (the same at every airspeed).")
                P("damp_r", Label="Yaw damping", Units="1/s", Default=d.damp_r, Min=0, Max=20, Group="Aircraft", Advanced=true, ...
                    Description="Yaw angular deceleration per rad/s of yaw rate (the same at every airspeed).")
                P("alpha_trim", Label="Trim angle of attack", Units="rad", Default=d.alpha_trim, Min=-0.5, Max=0.5, ...
                    Group="Stability", Advanced=true, DisplayFormat="%.10g", ...
                    Description="The angle of attack at which the pitch stiffness gives no moment.")
                P("pitch_alpha", Label="Pitch stiffness", Units="1/s²", Default=d.pitch_alpha, Min=0, Max=50, ...
                    Group="Stability", Advanced=true, Description="Pitch angular acceleration per radian of " + ...
                    "angle of attack away from the trim angle (the same at every airspeed).")
                P("roll_beta", Label="Roll from sideslip", Default=d.roll_beta, Min=0, Max=50, Group="Stability", Advanced=true, ...
                    Description="Roll angular acceleration per radian of sideslip, rolling away from it (the dihedral effect).")
                P("yaw_beta", Label="Weathercock stiffness", Default=d.yaw_beta, Min=0, Max=50, Group="Stability", Advanced=true, ...
                    Description="Yaw angular acceleration per radian of sideslip, turning the nose into the relative wind.")
                % Solver (the original "⚙ Sim" dialog)
                P("Vmax", Label="Maximum airspeed", Units="m/s", Default=d.Vmax, Min=10, Max=600, ...
                    Group="Solver and limits", Advanced=true, Description="The run stops if exceeded.")
                P("groundAltitude", Label="Ground altitude", Units="m", Default=d.groundAltitude, Min=-1000, Max=9000, ...
                    Group="Solver and limits", Advanced=true, ...
                    Description="The run stops when the aircraft comes down to this altitude.")
                P("attitude", Label="Attitude", Type="choice", Default="quaternion", Choices=["quaternion" "euler"], ...
                    ChoiceLabels=["Quaternion" "Euler"], Group="Solver and limits", ...
                    Advanced=true, Description="Quaternion: no pitch limit, so the aircraft can loop and climb " + ...
                    "vertically. Euler: the 3-2-1 angles of versions before 1.2, singular at ±90° pitch, so " + ...
                    "those runs stop at the pitch limit.")
                P("attitudeLimitDeg", Label="Pitch limit", Units="deg", Default=d.attitudeLimitDeg, Min=10, Max=89, ...
                    Group="Solver and limits", Advanced=true, VisibleWhen=@(p) p.attitude == "euler", ...
                    Description="With Euler angles, the run stops when the pitch reaches ± this.")
                P("Solver", Label="ODE solver", Type="choice", Default=string(d.Solver), Choices=["ode45" "ode113"], ...
                    Group="Solver and limits", Advanced=true, ...
                    Description="ode45, or ode113 for long, smooth runs.")
                P("RelTol", Label="Relative tolerance", Default=d.RelTol, Min=1e-8, Max=1e-2, ...
                    Group="Solver and limits", Advanced=true, DisplayFormat="%.2e", ...
                    Description="Relative tolerance of the ODE solver.")
                P("AbsTol", Label="Absolute tolerance", Default=d.AbsTol, Min=1e-10, Max=1e-4, ...
                    Group="Solver and limits", Advanced=true, DisplayFormat="%.2e", ...
                    Description="Absolute tolerance of the ODE solver.")
                P("MaxStep", Label="Maximum step", Units="s", Default=d.MaxStep, Min=0.01, Max=1, ...
                    Group="Solver and limits", Advanced=true, ...
                    Description="Largest solver step, so that short control pulses are not stepped over.")
                P("TIMEOUT", Label="Wall-clock limit", Units="s", Default=d.TIMEOUT, Min=5, Max=300, ...
                    Group="Solver and limits", Advanced=true, ...
                    Description="A run that takes longer than this in real time is stopped.")
                P("MAX_PTS", Label="Plot points", Type="integer", Default=d.MAX_PTS, Min=100, Max=5000, ...
                    Group="Display", Display=true, Description="Plots are resampled to at most this many points.")
                % Trim (the "Trim aircraft" button below the inputs uses these)
                P("trimSpeed", Label="Trim airspeed", Units="m/s", Default=20, Min=3, Max=150, Group="Trim", ...
                    MarksCustom=false, Description="Airspeed for the Trim aircraft button.")
                P("trimAltitude", Label="Trim altitude", Units="m", Default=100, Min=1, Max=10000, Group="Trim", ...
                    MarksCustom=false, ...
                    Description="Altitude for the Trim aircraft button.")
                P("trimGamma", Label="Flight-path angle", Units="deg", Default=0, Min=-30, Max=30, Group="Trim", ...
                    MarksCustom=false, Description="0 = level; positive climbs, negative descends.")
                P("identify", Label="Identify mode", Type="choice", Default="auto", ...
                    Choices=["auto" "phugoid" "dutchroll" "rollsubsidence" "spiral" "off"], ...
                    ChoiceLabels=["Automatic" "Phugoid" "Dutch roll" "Roll" "Spiral" "Off"], Group="Analysis", ...
                    Description="Fit the response after the excitation and compare it with the linear model " + ...
                    "(Mode ID tab). Roll: roll subsidence. Automatic: from the excitation, a pitch input → " + ...
                    "phugoid, yaw → Dutch roll, roll → roll subsidence (spiral in runs of 40 s or more).")
            ];
        end

        function list = presets(obj)
            list = struct("Name", {}, "Values", {});
            for name = obj.PresetNames
                list(end+1) = struct("Name", name, ...
                    "Values", flatten(dlab.sims.flight6dof.defaultConfig(name))); %#ok<AGROW>
            end
            % A loop: past 90° pitch, which only the quaternion attitude can fly.
            loop = flatten(dlab.sims.flight6dof.defaultConfig("Straight flight"));
            [loop.u0, loop.alt0, loop.throttle, loop.duration] = deal(25, 200, 0.9, 12);
            loop.elevator = dlab.core.Schedule.make("pulse", Value=0, Amplitude=0.06, Start=1, Width=4.5);
            loop.attitude = "quaternion";
            list(end+1) = struct("Name", "Loop", "Values", loop);
            % Straight flight in a crosswind: the aircraft crabs and drifts.
            crosswind = flatten(dlab.sims.flight6dof.defaultConfig("Straight flight"));
            [crosswind.windSpeed, crosswind.windFrom] = deal(10, 270);
            list(end+1) = struct("Name", "Crosswind (10 m/s from the west)", "Values", crosswind);
            % Excitations: a pilot's input from trim, for the Mode ID tab.
            straight = flatten(dlab.sims.flight6dof.defaultConfig("Straight flight"));
            dutch = straight;
            dutch.rudder = dlab.core.Schedule.make("doublet", Value=0, Amplitude=0.3, Start=1, Width=0.5);
            dutch.duration = 20;
            list(end+1) = struct("Name", "Excite: Dutch roll (yaw doublet)", "Values", dutch);
            roll = straight;
            roll.aileron = dlab.core.Schedule.make("pulse", Value=0, Amplitude=0.1, Start=1, Width=0.3);
            roll.duration = 8;
            list(end+1) = struct("Name", "Excite: roll subsidence (roll pulse)", "Values", roll);
            spiral = straight;
            spiral.aileron = dlab.core.Schedule.make("pulse", Value=0, Amplitude=0.01, Start=1, Width=1);
            spiral.duration = 60;
            list(end+1) = struct("Name", "Excite: spiral (small roll pulse)", "Values", spiral);
            phugoid = flatten(dlab.sims.flight6dof.defaultConfig("Phugoid mode"));
            trim = dlab.sims.flight6dof.trim6dof(aircraftOf(phugoid, obj.Aircraft), 23, 100, 0);
            [phugoid.u0, phugoid.w0, phugoid.theta0] = deal(trim.u0, trim.w0, trim.theta0);
            phugoid.throttle = trim.throttle;
            phugoid.elevator = dlab.core.Schedule.make("pulse", Value=trim.elevator, Amplitude=0.01, Start=1, Width=2);
            [phugoid.duration, phugoid.trimSpeed] = deal(150, 23);
            list(end+1) = struct("Name", "Excite: phugoid (pitch pulse)", "Values", phugoid);
            % Autopilot: holds from straight, trimmed flight.
            climb = straight;
            [climb.apAltitude, climb.apAltitudeRef, climb.apSpeed, climb.apSpeedRef, climb.duration] = ...
                deal(true, 150, true, 20, 60);
            list(end+1) = struct("Name", "Autopilot: climb to 150 m", "Values", climb);
            turn = straight;
            [turn.apAltitude, turn.apAltitudeRef, turn.apHeading, turn.apHeadingRef, turn.apSpeed, ...
                turn.apSpeedRef, turn.duration] = deal(true, 100, true, 90, true, 20, 40);
            list(end+1) = struct("Name", "Autopilot: turn to 90° (holding altitude and speed)", "Values", turn);
            gusty = phugoid;
            [gusty.apAltitude, gusty.apAltitudeRef, gusty.apSpeed, gusty.apSpeedRef, gusty.duration] = ...
                deal(true, 100, true, 23, 60);
            gusty.identify = "off";
            list(end+1) = struct("Name", "Autopilot: rides out a pitch pulse", "Values", gusty);
        end

        function buildExtraControls(obj, parent, theme)
            t = theme;
            grid = uigridlayout(parent, [2 2], ColumnWidth={"1x", "fit"}, RowHeight={26, 26}, Padding=0, ...
                RowSpacing=t.Spacing.xs, ColumnSpacing=t.Spacing.xs, BackgroundColor=t.Surface);
            trim = dlab.ui.button(grid, "Trim aircraft", t, Tag="dlab.flight6dof.trim", ...
                Tooltip="Set the initial state, throttle, and pitch torque for steady flight at the " + ...
                "Trim airspeed, altitude, and flight-path angle", Callback=@(~, ~) obj.guard(@() obj.trimAircraft()));
            trim.Layout.Column = [1 2];
            obj.TuneDropdown = uidropdown(grid, Items=obj.ModeLabels, ItemsData=obj.ModeKeys, ...
                BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.flight6dof.tuneMode", ...
                Tooltip="Mode to excite");
            dlab.ui.button(grid, "Tune input", t, Tag="dlab.flight6dof.tune", ...
                Tooltip="Set a doublet or pulse sized to the chosen mode (from the Modes analysis), " + ...
                "and a duration long enough to watch it", ...
                Callback=@(~, ~) obj.guard(@() obj.tuneInput(string(obj.TuneDropdown.Value))));
        end

        function trimAircraft(obj)
            %TRIMAIRCRAFT Trim at the Trim inputs: one undo step.
            p = obj.currentInputs();
            trim = dlab.sims.flight6dof.trim6dof(aircraftOf(p, obj.Aircraft), p.trimSpeed, p.trimAltitude, p.trimGamma);
            changes = struct("u0", trim.u0, "v0", 0, "w0", trim.w0, "p0", 0, "q0", 0, "r0", 0, ...
                "phi0", 0, "theta0", trim.theta0, "alt0", p.trimAltitude);
            throttle = dlab.core.Schedule.normalize(p.throttle);
            throttle.value = trim.throttle;
            elevator = dlab.core.Schedule.normalize(p.elevator);
            elevator.value = trim.elevator;           % a doublet keeps riding on trim
            [changes.throttle, changes.elevator] = deal(throttle, elevator);
            obj.requestInputs(changes, sprintf("Trimmed at %.4g m/s (α = %.2f°, throttle %.3f)", ...
                p.trimSpeed, rad2deg(trim.alpha), trim.throttle));
        end

        function tuneInput(obj, key)
            %TUNEINPUT Size a doublet (oscillatory modes) or pulse (real
            %   modes) to the linear model's mode KEY, on its control.
            p = obj.currentInputs();
            k = find(obj.ModeKeys == key, 1);
            [label, control] = deal(obj.ModeLabels(k), obj.ModeControls(k));
            modes = dlab.core.Linearization.analyze(obj.linearization(p)).Modes;
            row = find(startsWith(modes.Mode, label), 1);
            if isempty(row)
                error("dlab:flight6dof:mode", "The linear model has no %s mode at these inputs.", lower(label));
            end
            current = dlab.core.Schedule.normalize(p.(control));
            amplitudes = struct("phugoid", 0.01, "dutchroll", 0.3, "rollsubsidence", 0.1, "spiral", 0.01);
            amplitude = amplitudes.(key);
            % The Dutch-roll amplitude suits the 0.5 s doublet of its Excite
            % preset. The tuned doublet is longer (half the mode's period),
            % so it keeps the preset's impulse: at full amplitude it would
            % yaw the aircraft into a departure, not a linear Dutch roll.
            referenceWidths = struct("phugoid", Inf, "dutchroll", 0.5, "rollsubsidence", Inf, "spiral", Inf);
            if isfinite(modes.Period(row))
                period = modes.Period(row);
                amplitude = amplitude * min(1, referenceWidths.(key) / (period / 2));
                schedule = dlab.core.Schedule.make("doublet", Value=current.value, Amplitude=amplitude, ...
                    Start=1, Width=period / 2);
                duration = 1 + period + 6 * period;
            else
                tau = modes.TimeConstant(row);
                width = min(max(0.5 * tau, 0.2), 2);
                schedule = dlab.core.Schedule.make("pulse", Value=current.value, Amplitude=amplitude, ...
                    Start=1, Width=width);
                duration = 1 + width + 5 * tau + 8 * (key == "spiral");
            end
            changes = struct(control, schedule, "duration", min(max(duration, 8), 600), "identify", key);
            obj.requestInputs(changes, "Tuned a " + schedule.shape + " to the " + lower(label));
        end

        function params = migrate(~, params, fromVersion)
            % Version 1 always integrated Euler angles; keep old scenarios exact.
            if fromVersion < 2 && ~isfield(params, "attitude")
                params.attitude = "euler";
            end
        end

        function result = solve(obj, p)
            config = obj.configFor(p);
            config.sim.progressFcn = obj.progressMonitor();
            result = dlab.sims.flight6dof.simulate6dof(config);
            result.config.sim = rmfield(result.config.sim, "progressFcn");   % results hold data only
            for name = obj.Controls
                result.config.control.(name) = p.(name);                     % the schedule, not a function
            end
            result.identification = obj.identification(result, p);
        end

        function titles = outputTabs(~, ~)
            titles = ["3D path" "Airspeed" "Altitude" "Euler angles" "Body rates" "Ground track" "Air data" ...
                "Controls" "Mode ID"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.path = dlab.ui.axesIn(containers{"3D path"}, t, Title="3D flight path", ...
                XLabel="X north (m)", YLabel="Y east (m)", ZLabel="Altitude (m)");
            obj.Ax.airspeed = dlab.ui.axesIn(containers{"Airspeed"}, t, Title="Airspeed", ...
                XLabel="Time (s)", YLabel="Airspeed (m/s)");
            obj.Ax.altitude = dlab.ui.axesIn(containers{"Altitude"}, t, Title="Altitude", ...
                XLabel="Time (s)", YLabel="Altitude (m)");
            obj.Ax.euler = dlab.ui.axesIn(containers{"Euler angles"}, t, Title="Euler angles", ...
                XLabel="Time (s)", YLabel="Angle (deg)");
            obj.Ax.rates = dlab.ui.axesIn(containers{"Body rates"}, t, Title="Body rates", ...
                XLabel="Time (s)", YLabel="Rate (rad/s)");
            obj.Ax.ground = dlab.ui.axesIn(containers{"Ground track"}, t, Title="Ground track", ...
                XLabel="X north (m)", YLabel="Y east (m)");
            obj.Ax.air = dlab.ui.axesIn(containers{"Air data"}, t, Title="Angle of attack and sideslip", ...
                XLabel="Time (s)", YLabel="Angle (deg)");
            obj.Ax.controls = dlab.ui.axesIn(containers{"Controls"}, t, Title="Control inputs", ...
                XLabel="Time (s)", YLabel="Command");
            grid = uigridlayout(containers{"Mode ID"}, [3 1], RowHeight={"2x", "1x", "fit"}, Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.identified = dlab.ui.axesIn(grid, t, Row=1, Title="Mode identification", XLabel="Time (s)");
            obj.Ax.residual = dlab.ui.axesIn(grid, t, Row=2, Title="Residual (response − fit)", XLabel="Time (s)");
            obj.IdTable = uitable(grid, ColumnName={'', 'Identified', 'Linear model', 'Difference'}, RowName={}, ...
                FontSize=t.FontSize.md, BackgroundColor=t.SurfaceRaised, ForegroundColor=t.Text, ...
                Tag="dlab.flight6dof.modeTable");
            obj.IdTable.Layout.Row = 3;
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Flight playback", ...
                XLabel="X north (m)", YLabel="Y east (m)", ZLabel="Altitude (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            [time, state] = resample(r.t, r.state, params.MAX_PTS);
            x = state(:, 10); y = state(:, 11); h = -state(:, 12);
            [airspeed, alpha, beta] = airDataOf(r, time);
            windy = hasWind(r);

            ax = obj.Ax.path;
            dlab.ui.clearAxes(ax);
            plot3(ax, x, y, h, Color=t.series(1), LineWidth=2.2, DisplayName="Path");
            plot3(ax, x(1), y(1), h(1), "o", MarkerSize=9, MarkerFaceColor=t.Success, ...
                MarkerEdgeColor=t.Text, DisplayName="Start");
            plot3(ax, x(end), y(end), h(end), "s", MarkerSize=9, MarkerFaceColor=t.Danger, ...
                MarkerEdgeColor=t.Text, DisplayName="End");
            hold(ax, "off");
            axis(ax, "equal");
            cubeLimits(ax, x, y, h);
            view(ax, -35, 25);
            dlab.ui.legend(ax, t, "Location", "best");

            obj.filledTrace(obj.Ax.airspeed, time, airspeed, t.series(1), "Airspeed");
            if windy
                hold(obj.Ax.airspeed, "on");
                plot(obj.Ax.airspeed, time, vecnorm(state(:, 1:3), 2, 2), "--", Color=t.series(2), ...
                    LineWidth=1.6, DisplayName="Ground speed");
                hold(obj.Ax.airspeed, "off");
                dlab.ui.legend(obj.Ax.airspeed, t, "Location", "best");
            end
            ax = obj.Ax.air;
            dlab.ui.clearAxes(ax);
            plot(ax, time, rad2deg(alpha), Color=t.series(1), LineWidth=1.8, DisplayName="α angle of attack");
            plot(ax, time, rad2deg(beta), Color=t.series(2), LineWidth=1.8, DisplayName="β sideslip");
            hold(ax, "off");
            ax.YLimitMethod = "padded";
            dlab.ui.legend(ax, t, "Location", "best");
            obj.filledTrace(obj.Ax.altitude, time, h, t.series(3), "Altitude");
            ap = autopilotOf(r);
            if ap.altitude
                reference(obj.Ax.altitude, ap.altitudeRef, sprintf("hold %.0f m", ap.altitudeRef), t);
            end
            if ap.speed
                reference(obj.Ax.airspeed, ap.speedRef, sprintf("hold %.1f m/s", ap.speedRef), t);
            end

            % State columns: 4–6 body rates p, q, r; 7–9 Euler angles φ, θ, ψ.
            obj.threeTraces(obj.Ax.euler, time, rad2deg(state(:, 7:9)), ["φ roll" "θ pitch" "ψ yaw"], 0.1);
            if ap.heading
                target = mod(ap.headingRef + 180, 360) - 180;          % as ψ is plotted, in ±180°
                reference(obj.Ax.euler, target, sprintf("hold ψ = %.0f°", ap.headingRef), t);
            end
            obj.threeTraces(obj.Ax.rates, time, state(:, 4:6), ["p roll rate" "q pitch rate" "r yaw rate"], 0.01);

            ax = obj.Ax.ground;
            dlab.ui.clearAxes(ax);
            plot(ax, x, y, Color=t.series(1), LineWidth=2.2, DisplayName="Track");
            plot(ax, x(1), y(1), "o", MarkerSize=9, MarkerFaceColor=t.Success, MarkerEdgeColor=t.Text, DisplayName="Start");
            plot(ax, x(end), y(end), "s", MarkerSize=9, MarkerFaceColor=t.Danger, MarkerEdgeColor=t.Text, DisplayName="End");
            if windy
                w = r.config.wind;
                text(ax, 0.02, 0.97, sprintf("wind %.1f m/s from %03.0f°", w.speed, w.fromDeg), ...
                    Units="normalized", VerticalAlignment="top", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                    Color=t.series(5), Tag="dlab.flight6dof.wind");
            end
            hold(ax, "off");
            axis(ax, "equal");
            dlab.ui.legend(ax, t, "Location", "best");

            obj.showControls(r, time);
            obj.showIdentification(r);
            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                s = run.Result.state;
                t = run.Result.t;
                dlab.ui.overlayLine(obj.Ax.path, s(:, 10), s(:, 11), run, -s(:, 12));
                dlab.ui.overlayLine(obj.Ax.ground, s(:, 10), s(:, 11), run);
                dlab.ui.overlayLine(obj.Ax.airspeed, t, airDataOf(run.Result, t), run);
                dlab.ui.overlayLine(obj.Ax.altitude, t, -s(:, 12), run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            if ~isempty(obj.IdTable) && isvalid(obj.IdTable)
                obj.IdTable.Data = {};
            end
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            delete(allchild(obj.Anim.axes));
            legend(obj.Anim.axes, "off");
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "aircraft")
                return
            end
            a = obj.Anim;
            % Interpolate between samples so playback stays smooth.
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            s = r.state(k, :) + fraction * (r.state(next, :) - r.state(k, :));
            here = [s(10); s(11); -s(12)];
            set(a.trail, XData=[r.state(1:k, 10); here(1)], YData=[r.state(1:k, 11); here(2)], ...
                ZData=[-r.state(1:k, 12); here(3)]);
            set(a.aircraft, XData=here(1), YData=here(2), ZData=here(3));
            if isfield(r, "quaternion")
                % Interpolate the quaternion: no gimbal ambiguity near ±90° pitch.
                qk = r.quaternion(k, :)' + fraction * (r.quaternion(next, :)' - r.quaternion(k, :)');
                rotation = dlab.physics.Quaternion.toDcm(qk);
            else
                rotation = dlab.physics.eulerToDcm(s(7), s(8), s(9));
            end
            for axisIndex = 1:3
                direction = rotation(:, axisIndex);
                direction(3) = -direction(3);              % NED down → altitude up
                tip = here + a.axisLength * direction;
                set(a.bodyAxes(axisIndex), XData=[here(1) tip(1)], YData=[here(2) tip(2)], ZData=[here(3) tip(3)]);
            end
            a.readout.String = sprintf("t = %.2f s   V = %.1f m/s   h = %.1f m   (%.0f, %.0f) m", ...
                simTime, norm(s(1:3)), here(3), here(1), here(2));
        end

        function T = exportTable(obj, r)
            controls = zeros(numel(r.t), numel(obj.Controls));
            specs = obj.parameters();
            for k = 1:numel(obj.Controls)
                spec = dlab.core.ParamSpec.find(specs, obj.Controls(k));
                u = dlab.core.Schedule.toFunction(r.config.control.(obj.Controls(k)), [spec.Min spec.Max]);
                controls(:, k) = u(r.t);
            end
            T = array2table([r.t r.state controls], VariableNames=["time" "u" "v" "w" "p" "q" "r" ...
                "roll" "pitch" "yaw" "north" "east" "down" "throttle" "pitch_torque" "roll_torque" "yaw_torque"]);
            T.Properties.VariableUnits = ["s" "m/s" "m/s" "m/s" "rad/s" "rad/s" "rad/s" ...
                "rad" "rad" "rad" "m" "m" "m" "" "" "" ""];
            if isfield(r, "quaternion")
                Q = array2table(r.quaternion, VariableNames=["q0" "q1" "q2" "q3"]);
                Q.Properties.VariableUnits = ["" "" "" ""];
                T = [T Q];
            end
            [airspeed, alpha, beta] = airDataOf(r, r.t);
            A = table(airspeed, alpha, beta, VariableNames=["airspeed" "alpha" "beta"]);
            A.Properties.VariableUnits = ["m/s" "rad" "rad"];
            T = [T A];
        end

        function T = summaryTable(~, r)
            % Numbers at full precision (metrics reads them, for sweeps and
            % lesson checks); Format sets how the Summary shows them, and
            % Display holds the rows that are text.
            final = r.state(end, :);
            rows = {                                % Quantity, Value, Units, Format, Display
                "Termination", NaN, "", "", string(r.termination)
                "Final time", r.t(end), "s", "%.2f", ""
                "Final altitude", -final(12), "m", "%.2f", ""
                "Final airspeed", airDataOf(r, r.t(end)), "m/s", "%.2f", ""
                "Horizontal range", hypot(final(10), final(11)), "m", "%.2f", ""
                "Final heading", mod(rad2deg(final(9)), 360), "deg", "%.1f", ""
                "Solve time", NaN, "s", "", sprintf("%.2f", r.solveTime)
            };
            if hasWind(r)
                % Drift: the wind's displacement of the air mass over the run.
                w = r.config.wind;
                windNed = zeros(numel(r.t), 3);
                for k = 1:numel(r.t)
                    windNed(k, :) = dlab.sims.flight6dof.windAt(w, max(-r.state(k, 12), 0)).';
                end
                drift = trapz(r.t, windNed(:, 1:2));
                v = r.state(end, 1:3).';
                ground = dlab.physics.eulerToDcm(final(7), final(8), final(9)) * v;
                crab = mod(rad2deg(final(9) - atan2(ground(2), ground(1))) + 180, 360) - 180;
                rows = [rows; {
                    "Final ground speed", norm(ground(1:2)), "m/s", "%.2f", ""
                    "Wind drift", norm(drift), "m", "%.2f", ""
                    "Crab angle", crab, "deg", "%.1f", ""}];
            end
            for row = autopilotRows(r)'
                rows(end+1, :) = {row{1}, row{2}, row{3}, "%.3g", ""}; %#ok<AGROW>
            end
            if isfield(r, "identification") && ~isempty(r.identification) && r.identification.ok
                id = r.identification;
                rows(end+1, :) = {"Identified mode", NaN, "", "", id.label};
                if isfinite(id.period)
                    rows = [rows; {"Identified period", id.period, "s", "%.4g", ""
                        "Identified damping ratio", id.dampingRatio, "", "%.3g", ""}];
                else
                    rows(end+1, :) = {"Identified time constant", id.timeConstant, "s", "%.4g", ""};
                end
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            if r.termination == "completed"
                [note, level] = deal("", "success");
            else
                [note, level] = deal("ended early: " + string(r.termination), "warning");
            end
        end

        function lin = linearization(obj, p)
            % Body velocities, rates, and attitude (9 states) about the
            % initial state; position does not feed back except through
            % air density, so altitude is held at h₀.
            config = obj.configFor(p);
            i = config.initial;            % velocities over the ground (wind included)
            x0 = [i.u0; i.v0; i.w0; p.p0; p.q0; p.r0; deg2rad([p.phi0; p.theta0; p.psi0])];
            speed = max(norm(x0(1:3)), 1);
            down = -p.alt0;
            F = @(x) firstNine(dlab.sims.flight6dof.dynamics(0, [x; 0; 0; down], config.control, ...
                config.aircraft, config.wind));
            % (inputs are held at their t = 0 values)
            lin = struct("F", F, "X0", x0, ...
                "StateNames", ["u" "v" "w" "p" "q" "r" "φ" "θ" "ψ"], ...
                "Reference", sprintf("the initial flight state (%.1f m/s at %.0f m)", norm(x0(1:3)), p.alt0), ...
                "Classify", @(lambda, V) flightModes(lambda, V, speed), ...
                "Scale", [speed; speed; speed; 1; 1; 1; 1; 1; 1]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Dutch roll mode", "Tab", "Euler angles", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Rigid-body flight model with 13 states: body velocities (u, v, w), body rates " + ...
                "(p, q, r), the attitude as a unit quaternion (or, as an option, 12 with Euler angles " + ...
                "φ, θ, ψ), and north/east/down position."
                ""
                "Lift saturates smoothly at CL max; drag follows CD₀ + CDα² α². Air density follows " + ...
                "the standard atmosphere. Control inputs are normalised body torques (moment = Kctrl × " + ...
                "command): useful for exploring stability and modes, not a model of real control " + ...
                "surfaces. The stability and damping terms are angular accelerations that do not " + ...
                "change with airspeed, as a real aircraft's would (with the dynamic pressure)."
                ""
                "The run stops at ground contact, at the maximum airspeed, at the pitch limit, or at " + ...
                "the wall-clock limit."
                ""
                "Attitude is integrated as a unit quaternion by default, so the aircraft can loop " + ...
                "and fly vertically; the Euler-angle option (as in older versions) stops at the " + ...
                "pitch limit, because Euler angles are singular at ±90°. Plots show Euler angles " + ...
                "either way."
                ""
                "Wind: a steady wind (optionally stronger with height) and a vertical wind. The " + ...
                "aerodynamics use the velocity relative to the air; u, v, w, and the track are over " + ...
                "the ground. Uniform wind leaves the modes unchanged: the aircraft simply drifts."
                ""
                "Each control can also change during the run (step, pulse, doublet, ramp, sine, or " + ...
                "custom points), for example to excite a mode the way a pilot would."
                ""
                "Autopilot: altitude, heading, and airspeed holds, added to the pilot's inputs. " + ...
                "Altitude: a pitch command θc = α_trim + Kh·e + Khi·∫e − Khd·ḣ (within the pitch " + ...
                "limit), flown by the elevator: Kθ(θc − θ) − Kq·q. Heading: a bank command " + ...
                "φc = Kψ·(heading error) (within the bank limit), flown by the aileron: " + ...
                "Kφ(φc − φ) − Kp·p. Airspeed: throttle Kv·e + Kvi·∫e. The integrals run only near " + ...
                "their targets (the capture bands) and while their output is not saturated. The " + ...
                "Modes tab shows the aircraft without the autopilot."
            ], newline);
        end
    end

    methods (Access = private)
        function guard(obj, action)
            %GUARD Plugin button callbacks: report failures in the status bar.
            try
                action();
            catch failure
                obj.reportStatus(string(failure.message), "error");
            end
        end

        function id = identification(obj, r, p)
            %IDENTIFICATION Fit the excited mode and compare it with the
            %   linear model ([] when off or nothing was excited).
            id = [];
            key = string(p.identify);
            if key == "auto"
                key = autoMode(p, obj.Controls);
            end
            if key == "off" || key == ""
                return
            end
            k = find(obj.ModeKeys == key, 1);
            label = obj.ModeLabels(k);
            schedule = dlab.core.Schedule.normalize(p.(obj.ModeControls(k)));
            start = excitationEnd(schedule);
            if key == "spiral"
                start = start + 8;              % let the Dutch roll die away first
            end
            expected = NaN;
            linear = struct("period", NaN, "dampingRatio", NaN, "timeConstant", NaN);
            try
                modes = dlab.core.Linearization.analyze(obj.linearization(p)).Modes;
                row = find(startsWith(modes.Mode, label), 1);
                if ~isempty(row)
                    expected = complex(modes.Real(row), modes.Imaginary(row));
                    linear = struct("period", modes.Period(row), "dampingRatio", modes.DampingRatio(row), ...
                        "timeConstant", modes.TimeConstant(row));
                end
            catch
                % No linear comparison; the fit still stands.
            end
            id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, char(key), start, expected);
            id.label = label;
            id.linear = linear;
            id.excitationEnd = start;
        end

        function showControls(obj, r, time)
            t = obj.Theme;
            ax = obj.Ax.controls;
            dlab.ui.clearAxes(ax);
            names = ["Throttle" "Pitch torque" "Roll torque" "Yaw torque"];
            if isfield(r, "controls") && ~isempty(r.controls)
                % The controls applied (the pilot's inputs plus any autopilot correction).
                for k = 1:4
                    plot(ax, r.t, r.controls(:, k), Color=t.series(k), LineWidth=1.6, DisplayName=names(k));
                end
                if autopilotOf(r).active
                    title(ax, "Controls applied (pilot inputs + autopilot)");
                end
            else
                specs = obj.parameters();
                for k = 1:numel(obj.Controls)
                    spec = dlab.core.ParamSpec.find(specs, obj.Controls(k));
                    u = dlab.core.Schedule.toFunction(r.config.control.(obj.Controls(k)), [spec.Min spec.Max]);
                    stairs(ax, time, u(time), Color=t.series(k), LineWidth=1.6, DisplayName=names(k));
                end
            end
            hold(ax, "off");
            ax.YLimitMethod = "padded";
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function showIdentification(obj, r)
            t = obj.Theme;
            dlab.ui.clearAxes(obj.Ax.identified);
            dlab.ui.clearAxes(obj.Ax.residual);
            obj.IdTable.Data = {};
            if ~isfield(r, "identification") || isempty(r.identification)
                title(obj.Ax.identified, "Mode identification: excite a mode (a doublet or pulse), or choose one under Analysis");
                return
            end
            id = r.identification;
            if isempty(id.t)
                title(obj.Ax.identified, "Mode identification: " + string(id.message));
                return
            end
            plot(obj.Ax.identified, id.t, id.y, Color=t.series(1), LineWidth=1.6, DisplayName="Response");
            if ~isempty(id.fit)
                plot(obj.Ax.identified, id.t, id.fit, "--", Color=t.series(2), LineWidth=1.6, DisplayName="Fit");
                plot(obj.Ax.residual, id.t, id.y - id.fit, Color=t.series(4), LineWidth=1.2);
            end
            hold(obj.Ax.identified, "off");
            hold(obj.Ax.residual, "off");
            ylabel(obj.Ax.identified, id.signal);
            dlab.ui.legend(obj.Ax.identified, t, "Location", "best");
            heading = id.label + " from the " + extractBefore(string(id.signal) + " (", " (");
            if ~id.ok
                heading = heading + ": " + string(id.message);
            end
            title(obj.Ax.identified, heading);
            if isfinite(id.period)
                rows = {"Period (s)", id.period, id.linear.period
                        "Damping ratio", id.dampingRatio, id.linear.dampingRatio};
            else
                rows = {"Time constant (s)", id.timeConstant, id.linear.timeConstant};
            end
            data = cell(size(rows, 1), 4);
            for k = 1:size(rows, 1)
                difference = 100 * (rows{k, 2} - rows{k, 3}) / rows{k, 3};
                % As char: uitable cells cannot hold strings.
                data(k, :) = cellstr([string(rows{k, 1}), sprintf("%.4g", rows{k, 2}), ...
                    sprintf("%.4g", rows{k, 3}), sprintf("%+.1f %%", difference)]);
            end
            obj.IdTable.Data = data;
        end

        function config = configFor(obj, p)
            %CONFIGFOR The engine's nested configuration from flat inputs.
            config = struct();
            for name = obj.Initial
                config.initial.(name) = p.(name);
            end
            specs = obj.parameters();
            for name = obj.Controls
                spec = dlab.core.ParamSpec.find(specs, name);
                config.control.(name) = dlab.core.Schedule.toFunction(p.(name), [spec.Min spec.Max]);
            end
            for name = obj.Aircraft
                config.aircraft.(name) = p.(name);
            end
            for name = obj.Sim
                config.sim.(name) = p.(name);
            end
            config.sim.Solver = char(p.Solver);
            config.sim.attitude = char(p.attitude);
            config.sim.MAX_PTS = p.MAX_PTS;
            config.duration = p.duration;
            config.wind = struct("speed", p.windSpeed, "fromDeg", p.windFrom, "vertical", p.windVertical, ...
                "profile", char(p.windProfile), "refHeight", p.windRef);
            config.autopilot = struct("active", p.apAltitude || p.apHeading || p.apSpeed, ...
                "altitude", p.apAltitude, "heading", p.apHeading, "speed", p.apSpeed, ...
                "altitudeRef", p.apAltitudeRef, "headingRef", p.apHeadingRef, "speedRef", p.apSpeedRef, ...
                "alphaTrim", p.alpha_trim);
            for name = obj.Gains
                config.autopilot.(name) = p.(name);
            end
            if p.icFrame == "air" && (p.windSpeed > 0 || p.windVertical ~= 0)
                % The inputs are air-relative; the engine integrates ground velocity.
                R = dlab.physics.eulerToDcm(deg2rad(p.phi0), deg2rad(p.theta0), deg2rad(p.psi0));
                windBody = R.' * dlab.sims.flight6dof.windAt(config.wind, p.alt0);
                config.initial.u0 = p.u0 + windBody(1);
                config.initial.v0 = p.v0 + windBody(2);
                config.initial.w0 = p.w0 + windBody(3);
            end
        end

        function threeTraces(obj, ax, time, values, names, span)
            dlab.ui.clearAxes(ax);
            for k = 1:3
                plot(ax, time, values(:, k), Color=obj.Theme.series(k + 1), LineWidth=2, DisplayName=names(k));
            end
            hold(ax, "off");
            ax.YLimitMethod = "padded";     % a steady value was drawn on the frame's edge
            dlab.ui.minimumSpan(ax, span);  % round-off (body rates of 1e−10 in trim) stays flat
            dlab.ui.legend(ax, obj.Theme, "Location", "best");
        end

        function filledTrace(obj, ax, time, values, color, name)
            dlab.ui.clearAxes(ax);
            fill(ax, [time; flipud(time)], [values; zeros(numel(time), 1)], color, FaceAlpha=0.13, ...
                EdgeColor="none", HandleVisibility="off");
            plot(ax, time, values, Color=color, LineWidth=2, DisplayName=name);
            hold(ax, "off");
            ax.YLimitMethod = "padded";
            dlab.ui.legend(ax, obj.Theme, "Location", "best");
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            x = r.state(:, 10); y = r.state(:, 11); h = -r.state(:, 12);
            plot3(ax, x, y, h, Color=t.Grid, LineWidth=1.2, HandleVisibility="off");
            plot3(ax, x(1), y(1), h(1), "o", MarkerSize=9, MarkerFaceColor=t.Success, ...
                MarkerEdgeColor=t.Text, DisplayName="Start");
            plot3(ax, x(end), y(end), h(end), "s", MarkerSize=9, MarkerFaceColor=t.TextMuted, ...
                MarkerEdgeColor=t.Text, DisplayName="End");
            a = obj.Anim;
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=2.5, HandleVisibility="off");
            a.aircraft = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=12, MarkerFaceColor=t.series(2), ...
                MarkerEdgeColor=t.Text, LineWidth=1.5, DisplayName="Aircraft");
            a.bodyAxes = [plot3(ax, NaN, NaN, NaN, Color=t.series(4), LineWidth=2, HandleVisibility="off"), ...
                          plot3(ax, NaN, NaN, NaN, Color=t.series(3), LineWidth=2, HandleVisibility="off"), ...
                          plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=2, HandleVisibility="off")];
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            axis(ax, "equal");
            cubeLimits(ax, x, y, h);
            view(ax, -35, 25);
            dlab.ui.legend(ax, t, "Location", "best");
            a.axisLength = 0.04 * max([max(x) - min(x), max(y) - min(y), max(h) - min(h), 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function aircraft = aircraftOf(p, names)
% The engine's aircraft struct from flat inputs.
aircraft = struct();
for name = names
    aircraft.(name) = p.(name);
end
end

function key = autoMode(p, controls)
% The mode a pilot's input excites: yaw → Dutch roll, roll → roll
% subsidence (spiral in long runs), pitch → phugoid.
key = "";
excited = arrayfun(@(name) shapeOf(p.(name)) ~= "constant", controls);
if excited(controls == "rudder")
    key = "dutchroll";
elseif excited(controls == "aileron")
    key = "rollsubsidence";
    if p.duration >= 40
        key = "spiral";
    end
elseif excited(controls == "elevator")
    key = "phugoid";
end
end

function shape = shapeOf(value)
s = dlab.core.Schedule.normalize(value);
shape = s.shape;
end

function t = excitationEnd(s)
% When a schedule's input is over (its free response starts).
switch s.shape
    case "pulse"
        t = s.start + s.width;
    case "doublet"
        t = s.start + 2 * s.width;
    case "ramp"
        t = s.start + s.width;
    case "step"
        t = s.start;
    otherwise
        t = 0;
end
end

function tf = hasWind(r)
tf = isfield(r.config, "wind") && (r.config.wind.speed > 0 || r.config.wind.vertical ~= 0);
end

function [airspeed, alpha, beta] = airDataOf(r, time)
%AIRDATAOF Air-relative speed, angle of attack, and sideslip at TIME
%   (results from before wind was added: from the ground velocity).
if isfield(r, "airspeed") && isscalar(r.t)
    data = [r.airspeed r.alpha r.beta];
elseif isfield(r, "airspeed")
    data = interp1(r.t, [r.airspeed r.alpha r.beta], time(:), "linear", "extrap");
else
    v = interp1(r.t, r.state(:, 1:3), time(:), "linear", "extrap");
    speed = vecnorm(v, 2, 2);
    data = [speed, atan2(v(:, 3), v(:, 1)), asin(v(:, 2) ./ max(speed, eps))];
end
airspeed = data(:, 1);
alpha = data(:, 2);
beta = data(:, 3);
end

function flat = flatten(config)
%FLATTEN defaultConfig's nested struct as one params struct.
flat = struct();
for group = ["initial" "control" "aircraft" "sim"]
    values = config.(group);
    for name = string(fieldnames(values))'
        flat.(name) = values.(name);
    end
end
flat.Solver = string(flat.Solver);
flat.duration = config.duration;
end

function d = firstNine(dstate)
d = dstate(1:9);
end

function labels = flightModes(lambda, V, speed)
%FLIGHTMODES Name the classic aircraft modes from each eigenvector's
%   make-up: longitudinal states (u, w, q, θ) or lateral ones (v, p, r,
%   φ, ψ). Velocities are scaled by the airspeed so they compare with
%   angles and rates.
n = numel(lambda);
labels = strings(n, 1);
W = abs(V) ./ [speed; speed; speed; 1; 1; 1; 1; 1; 1];
longitudinal = [1 3 5 8];                % u, w, q, θ; the rest are lateral
share = sum(W(longitudinal, :).^2, 1) ./ max(sum(W.^2, 1), eps);
tol = 1e-6 * max(1, max(abs(lambda)));
oscillatory = abs(imag(lambda)) > tol;
fastestLateral = max([0; abs(lambda(~oscillatory & share(:) <= 0.5 & abs(lambda) > tol))]);
% Strong pitch damping can split a longitudinal pair into two real roots.
% Then the slowest stands in for the phugoid and the fastest for the short
% period, unless that mode still oscillates.
realLongitudinal = ~oscillatory & share(:) > 0.5 & abs(lambda) > tol;
speeds = abs(lambda(realLongitudinal));
for k = 1:n
    [~, dominant] = max(W(:, k));
    if abs(lambda(k)) <= tol
        labels(k) = "Neutral";
        if dominant == 9
            labels(k) = "Heading (neutral)";
        end
    elseif share(k) > 0.5 && oscillatory(k)
        % Phugoid trades speed (u) and height; the short period is a fast
        % pitching motion in w and q.
        if W(1, k)^2 > W(3, k)^2
            labels(k) = "Phugoid";
        else
            labels(k) = "Short period";
        end
    elseif share(k) > 0.5
        labels(k) = "Longitudinal (non-oscillatory)";
    elseif oscillatory(k)
        labels(k) = "Dutch roll";
    elseif abs(lambda(k)) == fastestLateral
        labels(k) = "Roll subsidence";
    else
        labels(k) = "Spiral";
    end
end
if ~isempty(speeds)
    named = labels(oscillatory);
    if ~any(named == "Phugoid")
        labels(realLongitudinal & abs(lambda) == min(speeds)) = "Phugoid (non-oscillatory)";
    end
    if ~any(named == "Short period") && numel(speeds) > 1
        labels(realLongitudinal & abs(lambda) == max(speeds)) = "Short period (non-oscillatory)";
    end
end
end

function [time, state] = resample(t, state, maxPoints)
% Plots are resampled to at most maxPoints, as the original MAX_PTS did.
time = t(:);
if numel(time) > maxPoints
    sampled = linspace(time(1), time(end), maxPoints)';
    state = interp1(time, state, sampled, "linear");
    time = sampled;
end
end

function cubeLimits(ax, x, y, z)
centre = [(min(x) + max(x)) / 2, (min(y) + max(y)) / 2, (min(z) + max(z)) / 2];
span = max([max(x) - min(x), max(y) - min(y), max(z) - min(z), 10]);
half = 0.8 * span;
set(ax, XLim=centre(1) + [-half half], YLim=centre(2) + [-half half], ZLim=centre(3) + [-half half]);
end

function a = autopilotOf(r)
% The run's autopilot settings (all holds off for runs without one).
a = struct("active", false, "altitude", false, "heading", false, "speed", false);
if isfield(r, "autopilot") && ~isempty(r.autopilot)
    a = r.autopilot;
end
end

function rows = autopilotRows(r)
% How far each hold is from its reference at the end of the run.
rows = cell(0, 3);
a = autopilotOf(r);
final = r.state(end, :);
if a.altitude
    rows(end+1, :) = {"Altitude error at the end", a.altitudeRef + final(12), "m"};
end
if a.heading
    miss = mod(a.headingRef - rad2deg(final(9)) + 180, 360) - 180;
    rows(end+1, :) = {"Heading error at the end", miss, "deg"};
end
if a.speed
    rows(end+1, :) = {"Airspeed error at the end", a.speedRef - airDataOf(r, r.t(end)), "m/s"};
end
end

function reference(ax, value, label, t)
% A dashed line at an autopilot reference.
hold(ax, "on");
yline(ax, value, "--", label, Color=t.TextMuted, LineWidth=1.2, LabelHorizontalAlignment="left", ...
    HandleVisibility="off", Tag="dlab.flight6dof.reference");
hold(ax, "off");
end
