classdef AttitudePlugin < dlab.core.TimeDomainPlugin
    %ATTITUDEPLUGIN Point a rigid spacecraft with reaction wheels and
    %   thrusters: free tumbling, detumbling, PD and bang-bang slews, and a
    %   disturbance that saturates the wheels. Solved by simulateAttitude.

    properties (Constant)
        Id = "attitude"
        Title = "Spacecraft Attitude Control"
        Category = "Aerospace"
        Summary = "Reaction wheels and thrusters: detumble, slew with a quaternion PD or bang-bang, and saturate the wheels."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        WheelTabs = ["Pointing error" "Body rates" "Wheel momentum" "Torques" "Euler angles"]
        FreeTabs = ["Pointing error" "Body rates" "Euler angles" "Conservation"]
        AxisNames = ["x" "y" "z"]
        MaxPlotPoints = 5000
        Reach = 1.6            % drawing: half-size of the animation box
        View = [-37.5 22]      % drawing: azimuth, elevation
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isSlew = @(p) ismember(p.mode, ["slew" "bangbang"]);
            hasPd = @(p) ismember(p.mode, ["slew" "bangbang" "hold"]);
            controlled = @(p) p.mode ~= "free";
            wheelModes = @(p) ismember(p.mode, ["detumble" "slew" "hold"]);
            dumping = @(p) wheelModes(p) && p.dump;
            specs = [
                P("mode", Label="Mode", Type="choice", Default="slew", ...
                    Choices=["free" "detumble" "slew" "bangbang" "hold"], ...
                    ChoiceLabels=["Free" "Detumble" "PD slew" "Bang-bang" "Hold"], Group="Mode", ...
                    Description="Free: no control. Detumble: the wheels damp the rates. PD slew: the wheels turn " + ...
                    "it to the target. Bang-bang: the thrusters turn it about the eigenaxis, then the wheels " + ...
                    "hold. Hold: the wheels hold the start attitude against a disturbance.")
                P("Ix", Label="Inertia Iₓ", Units="kg·m²", Default=30, Min=0.01, Max=1e6, Group="Spacecraft", ...
                    Description="Principal moments of inertia; the body axes are the principal axes.")
                P("Iy", Label="Inertia Iᵧ", Units="kg·m²", Default=40, Min=0.01, Max=1e6, Group="Spacecraft", ...
                    Description="About the body y axis. Each inertia must be at most the sum of the other two.")
                P("Iz", Label="Inertia I_z", Units="kg·m²", Default=50, Min=0.01, Max=1e6, Group="Spacecraft", ...
                    Description="About the body z axis (the yaw axis).")
                P("roll0", Label="Start roll", Units="°", Default=0, Min=-180, Max=180, Group="Start", ...
                    Description="3-2-1 Euler angles: yaw about z, then pitch about y, then roll about x.")
                P("pitch0", Label="Start pitch", Units="°", Default=0, Min=-90, Max=90, Group="Start", ...
                    Description="The second 3-2-1 angle, about y.")
                P("yaw0", Label="Start yaw", Units="°", Default=0, Min=-180, Max=180, Group="Start", ...
                    Description="The first 3-2-1 angle, about z.")
                P("wx0", Label="Start rate ωₓ", Units="°/s", Default=0, Min=-1000, Max=1000, Group="Start", ...
                    Description="Angular velocity in body axes.")
                P("wy0", Label="Start rate ωᵧ", Units="°/s", Default=0, Min=-1000, Max=1000, Group="Start", ...
                    Description="Angular velocity about the body y axis.")
                P("wz0", Label="Start rate ω_z", Units="°/s", Default=0, Min=-1000, Max=1000, Group="Start", ...
                    Description="Angular velocity about the body z axis.")
                P("rollT", Label="Target roll", Units="°", Default=0, Min=-180, Max=180, Group="Target", ...
                    VisibleWhen=isSlew, Description="The attitude to slew to (3-2-1 Euler angles).")
                P("pitchT", Label="Target pitch", Units="°", Default=0, Min=-90, Max=90, Group="Target", ...
                    VisibleWhen=isSlew, Description="The target's second 3-2-1 angle, about y.")
                P("yawT", Label="Target yaw", Units="°", Default=90, Min=-180, Max=180, Group="Target", ...
                    VisibleWhen=isSlew, Description="The target's first 3-2-1 angle, about z.")
                P("Kp", Label="Attitude gain Kp", Units="N·m/rad", Default=0.5, Min=0, Max=1e5, Group="Controller", ...
                    VisibleWhen=hasPd, Description="τ = −Kp · 2 sign(q_e0) q_e,vec − Kd ω. " + ...
                    "About one axis: ωn = √(Kp / I).")
                P("Kd", Label="Rate gain Kd", Units="N·m·s/rad", Default=7, Min=0, Max=1e6, Group="Controller", ...
                    VisibleWhen=controlled, Description="Damping ratio about one axis: ζ = Kd / (2 √(Kp I)).")
                P("tauMax", Label="Wheel torque limit", Units="N·m", Default=0.2, Min=1e-4, Max=1e3, ...
                    Group="Reaction wheels", VisibleWhen=controlled, Description="Per wheel (one on each body axis).")
                P("hMax", Label="Wheel momentum capacity", Units="N·m·s", Default=6, Min=1e-3, Max=1e5, ...
                    Group="Reaction wheels", VisibleWhen=controlled, ...
                    Description="Per wheel: at this momentum a wheel is at top speed and can push no further.")
                P("thrust", Label="Thruster torque per axis", Units="N·m", Default=1, Min=1e-4, Max=1e4, ...
                    Group="Thrusters", VisibleWhen=@(p) p.mode == "bangbang", ...
                    Description="The largest thruster torque about each body axis.")
                P("dump", Label="Dump wheel momentum with thrusters", Type="logical", Default=false, ...
                    Group="Thrusters", VisibleWhen=wheelModes, ...
                    Description="An axis fires its thrusters against its wheel's momentum until it is back to 10 %.")
                P("dumpAt", Label="Start dumping at", Units="%", Default=80, Min=20, Max=100, Group="Thrusters", ...
                    VisibleWhen=dumping, Description="Of the wheel capacity.")
                P("dumpTorque", Label="Dumping torque", Units="N·m", Default=0.02, Min=1e-5, Max=1e3, ...
                    Group="Thrusters", VisibleWhen=dumping, Description="Must be larger than the disturbance.")
                P("dx", Label="Disturbance τₓ", Units="N·m", Default=0, Min=-100, Max=100, Group="Disturbance", ...
                    VisibleWhen=controlled, DisplayFormat="%.4g", ...
                    Description="Constant torque in body axes (solar pressure, gravity gradient, a leak).")
                P("dy", Label="Disturbance τᵧ", Units="N·m", Default=0, Min=-100, Max=100, Group="Disturbance", ...
                    VisibleWhen=controlled, DisplayFormat="%.4g", Description="Constant torque about the body y axis.")
                P("dz", Label="Disturbance τ_z", Units="N·m", Default=0, Min=-100, Max=100, Group="Disturbance", ...
                    VisibleWhen=controlled, DisplayFormat="%.4g", Description="Constant torque about the body z axis.")
                P("tspan", Label="Duration", Units="s", Default=200, Min=0.1, Max=1e5, Group="Simulation", ...
                    MarksCustom=false, Description="How long to follow the spacecraft.")
                P("dt", Label="Output step", Units="s", Default=0.1, Min=1e-3, Max=100, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of saved samples; ode45 picks its own steps, and " + ...
                    "saturation and dumping are found exactly.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Free tumble: intermediate axis", "Values", struct("mode", "free", ...
                "wx0", 0.05, "wy0", 10, "wz0", 0.05, "tspan", 600, "dt", 0.2));
            list(end+1) = struct("Name", "Detumble", "Values", struct("mode", "detumble", ...
                "wx0", 3, "wy0", -2, "wz0", 4, "tspan", 150));
            list(end+1) = struct("Name", "90° yaw slew (PD)", "Values", struct());
            list(end+1) = struct("Name", "Large three-axis slew (PD)", "Values", struct( ...
                "rollT", 60, "pitchT", -40, "yawT", 120, "tspan", 300));
            list(end+1) = struct("Name", "Bang-bang slew (thrusters)", "Values", struct("mode", "bangbang", ...
                "tspan", 60, "dt", 0.05));
            holding = struct("mode", "hold", "Kp", 1, "Kd", 10, "dx", 0.002, "dz", 0.01, "tspan", 750, "dt", 0.5);
            list(end+1) = struct("Name", "Hold: a disturbance saturates the wheels", "Values", holding);
            holding.dump = true;
            list(end+1) = struct("Name", "Hold with momentum dumping", "Values", holding);
        end

        function result = solve(obj, p)
            q = engineParams(p);
            q.progressFcn = obj.progressMonitor();
            result = dlab.sims.attitude.simulateAttitude(q);
            result.params = p;
        end

        function titles = outputTabs(obj, p)
            titles = obj.WheelTabs;
            if p.mode == "free"
                titles = obj.FreeTabs;
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax = struct();
            grid = uigridlayout(containers{"Pointing error"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.err = dlab.ui.axesIn(grid, t, Row=1, Title="Pointing error (eigenaxis angle)", ...
                XLabel="Time (s)", YLabel="Error (°)");
            obj.Ax.errLog = dlab.ui.axesIn(grid, t, Row=2, Title="Pointing error, log scale", ...
                XLabel="Time (s)", YLabel="Error (°)");
            obj.Ax.rates = dlab.ui.axesIn(containers{"Body rates"}, t, Title="Body rates", ...
                XLabel="Time (s)", YLabel="ω (°/s)");
            if isKey(containers, "Wheel momentum")
                obj.Ax.wheel = dlab.ui.axesIn(containers{"Wheel momentum"}, t, ...
                    Title="Reaction-wheel momentum", XLabel="Time (s)", YLabel="h (N·m·s)");
            end
            if isKey(containers, "Torques")
                grid = uigridlayout(containers{"Torques"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                    BackgroundColor=t.AxesBackground);
                obj.Ax.torque = dlab.ui.axesIn(grid, t, Row=1, Title="Wheel torque on the body", ...
                    XLabel="Time (s)", YLabel="τ (N·m)");
                obj.Ax.thruster = dlab.ui.axesIn(grid, t, Row=2, Title="Thruster and disturbance torques", ...
                    XLabel="Time (s)", YLabel="τ (N·m)");
            end
            obj.Ax.euler = dlab.ui.axesIn(containers{"Euler angles"}, t, ...
                Title="Euler angles (3-2-1: yaw, pitch, roll)", XLabel="Time (s)", YLabel="Angle (°)");
            if isKey(containers, "Conservation")
                obj.Ax.drift = dlab.ui.axesIn(containers{"Conservation"}, t, ...
                    Title="Conservation without torque (relative change)", XLabel="Time (s)", ...
                    YLabel="Relative change");
            end
        end

        function buildAnimation(obj, parent, theme)
            % The 3-D view spans the whole grid; the wheel-momentum inset
            % shares its lower-left cell and is drawn on top (created later).
            % Animation export records every axes in the grid.
            grid = uigridlayout(parent, [2 2], Padding=0, RowSpacing=0, ColumnSpacing=0, ...
                RowHeight={'1x', 160}, ColumnWidth={190, '1x'}, BackgroundColor=theme.AxesBackground);
            ax = dlab.ui.axesIn(grid, theme, Title="Spacecraft attitude", Row=[1 2], Column=[1 2]);
            disableDefaultInteractivity(ax);
            wheels = dlab.ui.axesIn(grid, theme, Row=2, Column=1);
            disableDefaultInteractivity(wheels);
            wheels.Toolbar.Visible = "off";
            wheels.Visible = "off";
            obj.Anim = struct("axes", ax, "wheels", wheels);
        end

        function showResult(obj, r, ~)
            obj.Result = r;
            t = obj.Theme;
            rows = plotRows(numel(r.t), obj.MaxPlotPoints);
            time = r.t(rows);
            band = 0.1;
            fromStart = ismember(r.mode, ["free" "detumble" "hold"]);

            ax = obj.Ax.err;
            dlab.ui.clearAxes(ax);
            plot(ax, time, rad2deg(r.error(rows)), Color=t.series(1), LineWidth=1.5, DisplayName="Error");
            obj.markPlan(ax, r);
            hold(ax, "off");
            if fromStart
                title(ax, "Angle from the start attitude (eigenaxis angle)");
            else
                title(ax, "Pointing error (eigenaxis angle)");
            end

            ax = obj.Ax.errLog;
            dlab.ui.clearAxes(ax);
            smallest = 1e-8;
            plot(ax, time, max(rad2deg(r.error(rows)), smallest), Color=t.series(1), LineWidth=1.4, ...
                DisplayName="Error");
            yline(ax, band, ":", Color=t.TextMuted, LineWidth=1.2, DisplayName="0.1°");
            if isfinite(r.settleTime) && r.settleTime > 0 && ~fromStart
                xline(ax, r.settleTime, "--", Color=t.series(3), LineWidth=1.2, ...
                    DisplayName=sprintf("Within 0.1° from %.4g s", r.settleTime));
            end
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.rates;
            dlab.ui.clearAxes(ax);
            for k = 1:3
                plot(ax, time, rad2deg(r.omega(rows, k)), Color=axisColor(t, k), LineWidth=1.4, ...
                    DisplayName="ω_" + obj.AxisNames(k));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            if isfield(obj.Ax, "wheel")
                obj.drawWheels(r, rows);
            end
            if isfield(obj.Ax, "torque")
                obj.drawTorques(r, rows);
            end

            ax = obj.Ax.euler;
            dlab.ui.clearAxes(ax);
            names = ["Roll (x)" "Pitch (y)" "Yaw (z)"];
            for k = 1:3
                [x, y] = breakWraps(time, rad2deg(r.euler(rows, k)));
                plot(ax, x, y, Color=axisColor(t, k), LineWidth=1.4, DisplayName=names(k));
            end
            if ismember(r.mode, ["slew" "bangbang"])
                for k = 1:3
                    yline(ax, rad2deg(r.targetEuler(k)), "--", Color=axisColor(t, k), LineWidth=1, ...
                        HandleVisibility="off");
                end
                title(ax, "Euler angles (3-2-1), targets dashed");
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            if isfield(obj.Ax, "drift")
                ax = obj.Ax.drift;
                dlab.ui.clearAxes(ax);
                tiny = 1e-17;
                E = r.energy(rows);
                H = r.H(rows, :);
                plot(ax, time, max(abs(E - E(1)) / max(abs(E(1)), realmin), tiny), Color=t.series(1), ...
                    LineWidth=1.3, DisplayName="Energy ½ ωᵀIω");
                plot(ax, time, max(sqrt(sum((H - H(1, :)).^2, 2)) / max(norm(H(1, :)), realmin), tiny), ...
                    Color=t.series(2), LineWidth=1.3, DisplayName="Angular momentum (inertial vector)");
                hold(ax, "off");
                set(ax, YScale="log");
                dlab.ui.legend(ax, t, "Location", "best");
            end

            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.err, r.t, rad2deg(r.error), run);
                dlab.ui.overlayLine(obj.Ax.errLog, r.t, max(rad2deg(r.error), 1e-8), run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            if isfield(obj.Anim, "axes") && isvalid(obj.Anim.axes)
                delete(allchild(obj.Anim.axes));
                legend(obj.Anim.axes, "off");
                hideWheels(obj.Anim.wheels);
            end
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(~, r)
            % Slews take minutes: play each run in about 20 s.
            rate = max(1, r.t(end) / 20);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "body")
                return
            end
            a = obj.Anim;
            t = obj.Theme;
            k = dlab.core.frameAt(r.t, simTime);
            R = reshape(r.axes(k, :, :), 3, 3);
            set(a.body, Vertices=dlab.ui.Schematic.transform(a.vertices, R, [0 0 0]));
            set(a.panels, Vertices=dlab.ui.Schematic.transform(a.panelVertices, R, [0 0 0]));
            for i = 1:3
                tip = a.axisLength * R(:, i);
                set(a.bodyAxes(i), XData=[0 tip(1)], YData=[0 tip(2)], ZData=[0 tip(3)]);
                set(a.labels(i), Position=1.1 * tip');
            end
            firing = any(r.tauThruster(k, :) ~= 0);
            if firing
                torque = a.torqueScale * (R * r.tauThruster(k, :)');
                set(a.torque, XData=[0 torque(1)], YData=[0 torque(2)], ZData=[0 torque(3)], Visible="on");
            else
                set(a.torque, Visible="off");
            end
            if isfield(a, "bars")
                fraction = max(min(r.h(k, :) / r.hMax, 1), -1);
                for i = 1:3
                    color = axisColor(t, i);
                    if r.saturated(k, i)
                        color = t.Warning;
                    end
                    set(a.bars(i), Vertices=a.barShape(i, fraction(i)), FaceColor=color);
                end
            end
            note = "";
            if firing
                note = "   thrusters firing";
            elseif any(r.saturated(k, :))
                note = "   wheel saturated";
            end
            a.readout.String = sprintf("t = %.1f s   error = %.3g°   |ω| = %.3g°/s%s", simTime, ...
                rad2deg(r.error(k)), rad2deg(norm(r.omega(k, :))), note);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.q(:, 1), r.q(:, 2), r.q(:, 3), r.q(:, 4), rad2deg(r.euler(:, 1)), ...
                rad2deg(r.euler(:, 2)), rad2deg(r.euler(:, 3)), rad2deg(r.error), rad2deg(r.omega(:, 1)), ...
                rad2deg(r.omega(:, 2)), rad2deg(r.omega(:, 3)), r.h(:, 1), r.h(:, 2), r.h(:, 3), ...
                r.tauWheel(:, 1), r.tauWheel(:, 2), r.tauWheel(:, 3), r.tauThruster(:, 1), ...
                r.tauThruster(:, 2), r.tauThruster(:, 3), VariableNames=["time" "q_w" "q_x" "q_y" "q_z" ...
                "roll" "pitch" "yaw" "pointing_error" "omega_x" "omega_y" "omega_z" "h_x" "h_y" "h_z" ...
                "wheel_torque_x" "wheel_torque_y" "wheel_torque_z" "thruster_torque_x" "thruster_torque_y" ...
                "thruster_torque_z"]);
            T.Properties.VariableUnits = ["s" "" "" "" "" "deg" "deg" "deg" "deg" "deg/s" "deg/s" "deg/s" ...
                "N*m*s" "N*m*s" "N*m*s" "N*m" "N*m" "N*m" "N*m" "N*m" "N*m"];
        end

        function T = summaryTable(~, r)
            slewing = ismember(r.mode, ["slew" "bangbang"]);
            rows = cell(0, 3);
            if slewing
                rows(end+1, :) = {"Slew time (within 0.1°)", r.settleTime, "s"};
                rows(end+1, :) = {"Initial error", rad2deg(r.initialError), "°"};
                rows(end+1, :) = {"Final pointing error", clean(rad2deg(r.finalError), 1e-9), "°"};
                rows(end+1, :) = {"Overshoot", clean(r.overshoot, 1e-9), "%"};
            elseif r.mode == "hold"
                rows(end+1, :) = {"Final pointing error", rad2deg(r.finalError), "°"};
                rows(end+1, :) = {"Largest pointing error", rad2deg(r.maxError), "°"};
            else
                rows(end+1, :) = {"Largest angle from start", rad2deg(r.maxError), "°"};
            end
            rows(end+1, :) = {"Max rate", rad2deg(r.maxRate), "°/s"};
            rows(end+1, :) = {"Final rate", clean(rad2deg(norm(r.omega(end, :))), 1e-9), "°/s"};
            if r.mode == "free"
                rows(end+1, :) = {"Energy drift (relative)", r.drift.energy, ""};
                rows(end+1, :) = {"Momentum drift (relative)", r.drift.H, ""};
            else
                % (A bang-bang slew leaves the wheels at rounding level: 6e−14.)
                rows(end+1, :) = {"Max wheel momentum", clean(r.maxWheel, 1e-9 * r.hMax), "N·m·s"};
                rows(end+1, :) = {"Wheel capacity used", clean(100 * r.wheelFraction, 1e-7), "%"};
                rows(end+1, :) = {"Wheels saturated", double(r.wasSaturated), ""};
                if r.wasSaturated
                    rows(end+1, :) = {"Time to saturation", r.saturationTime, "s"};
                end
            end
            if r.mode == "bangbang"
                rows(end+1, :) = {"Bang-bang time 2√(θ/α)", r.plan.endTime, "s"};
                rows(end+1, :) = {"Eigenaxis acceleration α", rad2deg(r.plan.alpha), "°/s²"};
            end
            if r.mode == "bangbang" || any(r.dumping(:)) || r.dumps > 0
                rows(end+1, :) = {"Thruster impulse", r.impulse, "N·m·s"};
            end
            if r.params.dump && ismember(r.mode, ["detumble" "slew" "hold"])
                rows(end+1, :) = {"Momentum dumps", r.dumps, ""};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = strings(height(T), 1);
            T.Display(T.Quantity == "Wheels saturated") = pick(r.wasSaturated, "yes", "no");
        end

        function [note, level] = resultNote(~, r)
            [note, level] = deal("", "success");
            if r.wasSaturated
                [note, level] = deal(sprintf("a reaction wheel saturated at t = %.4g s", r.saturationTime), ...
                    "warning");
            elseif ismember(r.mode, ["slew" "bangbang"]) && ~isfinite(r.settleTime)
                [note, level] = deal("not within 0.1° of the target by the end", "warning");
            end
        end

        function lin = linearization(~, p)
            lin = [];
            if p.mode == "free"
                return
            end
            I = [p.Ix; p.Iy; p.Iz];
            Kp = p.Kp;
            reference = "the target attitude at rest, PD on (wheels at zero momentum, limits ignored)";
            if p.mode == "detumble"
                Kp = 0;
                reference = "at rest, rate damping on (wheels at zero momentum, limits ignored)";
            elseif p.mode == "hold"
                reference = "the held attitude at rest, PD on (wheels at zero momentum, limits ignored)";
            end
            G = @(x, u) errorDynamics(x, u, I, Kp, p.Kd);
            U0 = zeros(3, 1);
            lin = struct("F", @(x) G(x, U0), "X0", zeros(6, 1), ...
                "StateNames", ["φₓ" "φᵧ" "φ_z" "ωₓ" "ωᵧ" "ω_z"], "Reference", reference, ...
                "Classify", @modeNames, "Scale", [], "G", G, "U0", U0, ...
                "InputNames", ["Torque about x" "Torque about y" "Torque about z"], ...
                "H", @(x, ~) x(1:3), "OutputNames", ["Roll error φₓ" "Pitch error φᵧ" "Yaw error φ_z"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Large three-axis slew (PD)", "Tab", "Animation", "Time", 45);
        end

        function description = about(~)
            description = join([
                "A rigid spacecraft (principal inertias I) with a reaction wheel on each body axis:"
                "  I ω' = −ω × (I ω + h) − τ_w + τ_thr + τ_d,    h' = τ_w,    q' = ½ q ⊗ [0; ω]"
                "h is the wheels' momentum; the motors' torque τ_w spins them up and turns the body the " + ...
                "other way. Each wheel gives at most ±τmax and holds at most ±hmax: a full wheel is saturated."
                ""
                "Free: no control. Spin about the intermediate axis tumbles; energy and the inertial " + ...
                "angular momentum stay constant."
                "Detumble: τ = −Kd ω. The body stops, and its momentum ends up in the wheels."
                "Slew (PD), with the error quaternion q_e = q_target⁻¹ ⊗ q:"
                "  τ = −Kp · 2 sign(q_e0) q_e,vec − Kd ω     (one axis: I θ'' + Kd θ' + Kp θ = 0)"
                "Bang-bang: thrusters accelerate about the eigenaxis for half the angle and brake for the " + ...
                "other half, t = 2 √(θ I / τ) about a principal axis; then the wheels hold."
                "Hold: a constant disturbance τ_d is absorbed by the wheels, whose momentum grows at " + ...
                "τ_d until they saturate. Dumping fires the thrusters to unload them."
            ], newline);
        end
    end

    methods (Access = private)
        function markPlan(obj, ax, r)
            % Bang-bang switching and end times.
            t = obj.Theme;
            if r.mode == "bangbang" && r.plan.endTime > 0
                xline(ax, r.plan.switchTime, ":", Color=t.TextMuted, LineWidth=1.1, DisplayName="Switch");
                xline(ax, r.plan.endTime, "--", Color=t.TextMuted, LineWidth=1.1, DisplayName="Thrusters off");
                dlab.ui.legend(ax, t, "Location", "best");
            end
        end

        function drawWheels(obj, r, rows)
            t = obj.Theme;
            ax = obj.Ax.wheel;
            dlab.ui.clearAxes(ax);
            time = r.t(rows);
            yline(ax, r.hMax, "--", Color=t.Danger, LineWidth=1.3, DisplayName="Capacity ±h_{max}");
            yline(ax, -r.hMax, "--", Color=t.Danger, LineWidth=1.3, HandleVisibility="off");
            if r.params.dump
                level = r.params.dumpAt / 100 * r.hMax;
                yline(ax, level * [-1 1], ":", Color=t.Warning, LineWidth=1.1, HandleVisibility="off");
            end
            for k = 1:3
                plot(ax, time, r.h(rows, k), Color=axisColor(t, k), LineWidth=1.5, DisplayName="h_" + obj.AxisNames(k));
            end
            hold(ax, "off");
            span = max([r.hMax, max(abs(r.h(:)))]);
            ylim(ax, 1.15 * span * [-1 1]);
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function drawTorques(obj, r, rows)
            t = obj.Theme;
            time = r.t(rows);
            ax = obj.Ax.torque;
            dlab.ui.clearAxes(ax);
            patch(ax, [time(1) time(end) time(end) time(1)], r.tauMax * [-1 -1 1 1], t.series(8), ...
                FaceAlpha=0.08, EdgeColor="none", DisplayName="Wheel limit ±τ_{max}");
            for k = 1:3
                plot(ax, time, r.tauWheel(rows, k), Color=axisColor(t, k), LineWidth=1.4, ...
                    DisplayName="τ_" + obj.AxisNames(k));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.thruster;
            dlab.ui.clearAxes(ax);
            for k = 1:3
                plot(ax, time, r.tauThruster(rows, k), Color=axisColor(t, k), LineWidth=1.4, ...
                    DisplayName="Thrusters " + obj.AxisNames(k));
            end
            for k = find(r.disturbance ~= 0)
                yline(ax, r.disturbance(k), ":", Color=axisColor(t, k), LineWidth=1.6, ...
                    DisplayName="Disturbance " + obj.AxisNames(k));
            end
            hold(ax, "off");
            ax.YLimitMethod = "padded";     % a constant torque at the limit was hidden in the frame
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax, "wheels", obj.Anim.wheels);
            I = r.I;
            dims = sqrt(max(I([2 3 1]) + I([3 1 2]) - I, 1e-9 * max(I)));
            dims = 1.1 * dims / max(dims);
            [faces, vertices] = dlab.ui.Schematic.box3(dims);
            a.vertices = vertices;
            % A neutral body: the palette's lime was loud and hid the green y axis.
            a.body = patch(ax, Faces=faces, Vertices=vertices, FaceColor=t.Border, EdgeColor=t.Text, ...
                FaceAlpha=0.85, HandleVisibility="off");
            % Solar panels along ±y.
            y0 = dims(2) / 2 + 0.08;
            y1 = y0 + 0.75;
            w = 0.3;
            a.panelVertices = [-w y0 0; w y0 0; w y1 0; -w y1 0; -w -y0 0; w -y0 0; w -y1 0; -w -y1 0];
            a.panels = patch(ax, Faces=[1 2 3 4; 5 6 7 8], Vertices=a.panelVertices, FaceColor=t.Accent, ...
                FaceAlpha=0.45, EdgeColor=t.TextMuted, HandleVisibility="off");
            a.axisLength = 1.5;
            Rt = r.targetAxes;
            ghost = gobjects(3, 1);
            for i = 1:3
                tip = a.axisLength * Rt(:, i);
                ghost(i) = plot3(ax, [0 tip(1)], [0 tip(2)], [0 tip(3)], "--", Color=axisColor(t, i), ...
                    LineWidth=1.3, DisplayName="Target axes");
            end
            a.bodyAxes = gobjects(3, 1);
            a.labels = gobjects(3, 1);
            for i = 1:3
                a.bodyAxes(i) = plot3(ax, NaN, NaN, NaN, Color=axisColor(t, i), LineWidth=2.6, ...
                    DisplayName="Body axes");
                a.labels(i) = text(ax, 0, 0, 0, obj.AxisNames(i), Color=axisColor(t, i), FontWeight="bold", ...
                    HorizontalAlignment="center");
            end
            a.torqueScale = 1.2 / max(r.thrust, max(abs(r.tauThruster(:))));
            a.torque = plot3(ax, NaN, NaN, NaN, Color=t.series(5), LineWidth=3.5, DisplayName="Thruster torque", ...
                Visible="off");
            L = obj.Reach;
            set(ax, XLim=[-L L], YLim=[-L L], ZLim=[-L L]);
            daspect(ax, [1 1 1]);
            view(ax, obj.View(1), obj.View(2));
            axis(ax, "off");                 % open space: no box, ticks, or grid
            if r.mode == "free"
                hideWheels(a.wheels);
            else
                a = obj.addWheelBars(a);
            end
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            items = [a.bodyAxes(1) ghost(1)];
            if any(r.tauThruster(:) ~= 0)
                items(end+1) = a.torque;
            end
            dlab.ui.legend(ax, t, items, "Location", "northeast");
            obj.Anim = a;
        end

        function a = addWheelBars(obj, a)
            % Three bars of h/h_max in the inset, red green blue for x y z
            % (warning colour when saturated), with the capacity dashed.
            t = obj.Theme;
            ax = a.wheels;
            dlab.ui.clearAxes(ax);
            yline(ax, [-1 1], "--", Color=t.Danger, LineWidth=1);
            yline(ax, 0, Color=t.TextMuted);
            half = 0.3;
            a.barShape = @(i, f) [i + half * [-1; 1; 1; -1], f * [0; 0; 1; 1]];
            a.bars = gobjects(3, 1);
            for i = 1:3
                a.bars(i) = patch(ax, Faces=1:4, Vertices=a.barShape(i, 0), FaceColor=axisColor(t, i), ...
                    EdgeColor="none");
            end
            hold(ax, "off");
            set(ax, XLim=[0.4 3.6], YLim=[-1.15 1.15], XTick=1:3, XTickLabel="h_" + obj.AxisNames, ...
                YTick=[-1 0 1], YTickLabel=["−h_{max}" "0" "h_{max}"], XGrid="off", YGrid="off", ...
                FontSize=t.FontSize.sm, Visible="on");
            title(ax, "Wheel momentum", FontSize=t.FontSize.sm);
        end
    end
end

% ---------------------------------------------------------------- helpers
function q = engineParams(p)
Q = @dlab.physics.Quaternion.fromEuler;
q0 = Q(deg2rad(p.roll0), deg2rad(p.pitch0), deg2rad(p.yaw0));
target = q0;
if ismember(p.mode, ["slew" "bangbang"])
    target = Q(deg2rad(p.rollT), deg2rad(p.pitchT), deg2rad(p.yawT));
end
disturbance = [p.dx p.dy p.dz];
if p.mode == "free"
    disturbance = [0 0 0];
end
q = struct("I", [p.Ix p.Iy p.Iz], "omega0", deg2rad([p.wx0 p.wy0 p.wz0]), "q0", q0, "qTarget", target, ...
    "mode", char(p.mode), "Kp", p.Kp, "Kd", p.Kd, "tauMax", p.tauMax, "hMax", p.hMax, "thrust", p.thrust, ...
    "disturbance", disturbance, "dump", logical(p.dump), "dumpAt", p.dumpAt / 100, "dumpStop", 0.1, ...
    "dumpTorque", p.dumpTorque, "tspan", p.tspan, "dt", p.dt);
end

function dx = errorDynamics(x, u, I, Kp, Kd)
% Small-motion model about the target: x = [φ; ω] with φ = 2 q_e,vec (the
% error angles for small errors), u = extra body torque (command or
% disturbance). Exact for |φ| < 2.
phi = x(1:3);
w = x(4:6);
qv = phi / 2;
q0 = sqrt(max(0, 1 - qv' * qv));
dphi = q0 * w + cross(qv, w);
tau = -Kp * phi - Kd * w + u(:);
dw = (-cross(w, I .* w) + tau) ./ I;
dx = [dphi; dw];
end

function labels = modeNames(lambda, V)
%MODENAMES The axis each mode turns about, and what it does.
names = ["Roll (x)" "Pitch (y)" "Yaw (z)"];
labels = strings(numel(lambda), 1);
scale = max(1, max(abs(lambda)));
for k = 1:numel(lambda)
    v = abs(V(:, k));
    [~, i] = max(v(1:3) + v(4:6));
    if abs(lambda(k)) < 1e-9 * scale
        labels(k) = names(i) + " drift (neutral)";
    elseif abs(imag(lambda(k))) > 1e-9 * scale
        labels(k) = names(i) + " oscillation";
    elseif real(lambda(k)) < 0
        labels(k) = names(i) + " settling";
    else
        labels(k) = names(i) + " divergence";
    end
end
end

function hideWheels(ax)
% Empty and hide the wheel inset (free motion has no wheels).
delete(allchild(ax));
title(ax, "");
ax.Visible = "off";
end

function color = axisColor(t, k)
% x, y, z drawn red, green, blue (the usual axis colors).
order = [4 3 1];
color = t.series(order(k));
end

function rows = plotRows(n, most)
rows = (1:n)';
if n > most
    rows = unique(round(linspace(1, n, most)))';
end
end

function [x, y] = breakWraps(x, y)
% NaN gaps where an angle wraps through ±180°, so no vertical lines.
jump = find(abs(diff(y)) > 180);
for j = flip(jump(:)')
    x = [x(1:j); NaN; x(j + 1:end)];
    y = [y(1:j); NaN; y(j + 1:end)];
end
end

function value = clean(value, below)
% Rounding noise shown as 0.
if abs(value) < below
    value = 0;
end
end

function value = pick(condition, yes, no)
value = no;
if condition
    value = yes;
end
end
