classdef DcMotorPlugin < dlab.core.TimeDomainPlugin
    %DCMOTORPLUGIN A DC motor driven in open loop or as a speed or position
    %   servo (P, PI, PD, PID), within its supply voltage, with load torque
    %   and integrator windup. Solved by simulateDcMotor.

    properties (Constant)
        Id = "dcmotor"
        Title = "DC Motor Servo"
        Category = "Controls & Vehicles"
        Summary = "Drive a DC motor: time constants, speed and position control, PID tuning, saturation, and windup."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        DialTicks = 12            % marks around the dial
        BarHalf = 1.2             % half height of the current and voltage bars (drawing units)
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            S = @dlab.core.Schedule.make;
            isOpen = @(p) p.mode == "open";
            isSpeed = @(p) p.mode == "speed";
            isPosition = @(p) p.mode == "position";
            specs = [
                P("R", Label="Armature resistance R", Units="Ω", Default=2, Min=1e-4, Max=1e4, Group="Motor", ...
                    MinInclusive=false, Description="Resistance of the winding: it turns R i² into heat " + ...
                    "and limits the current at a stall to V / R.")
                P("L", Label="Armature inductance L", Units="mH", Default=5, Min=0, Max=1e5, Group="Motor", ...
                    Description="0 makes the current follow the voltage at once (no electrical lag).")
                P("K", Label="Motor constant K", Units="V·s/rad", Default=0.1, Min=1e-5, Max=100, Group="Motor", ...
                    DisplayFormat="%.4g", Description="Back-EMF per rad/s, and torque per ampere (N·m/A): " + ...
                    "the same number in SI units.")
                P("J", Label="Inertia J (rotor and load)", Units="kg·m²", Default=1e-3, Min=1e-9, Max=1e4, ...
                    Group="Motor", DisplayFormat="%.4g", Description="Everything that turns with the shaft.")
                P("b", Label="Viscous friction b", Units="N·m·s/rad", Default=1e-4, Min=0, Max=1e3, Group="Motor", ...
                    DisplayFormat="%.4g", Description="Friction torque b ω in the bearings, against the rotation.")
                P("Vmax", Label="Supply limit ±Vmax", Units="V", Default=24, Min=0.01, Max=1e4, Group="Motor", ...
                    Description="The drive cannot apply more than this: commands beyond it are clipped (saturation).")
                P("mode", Label="Control", Type="choice", Default="position", ...
                    Choices=["open" "speed" "position"], ChoiceLabels=["Open loop" "Speed" "Position"], ...
                    Group="Controller", Description="Open loop: the voltage schedule drives the motor. " + ...
                    "Speed: P or PI control of ω. Position: P, PD, or PID control of θ.")
                P("KpSpeed", Label="Speed Kp", Units="V·s/rad", Default=0.3, Min=0, Max=1e4, Group="Controller", ...
                    VisibleWhen=isSpeed, DisplayFormat="%.4g", Description="V = Kp e + Ki ∫e dt, e = ω_ref − ω (rad/s).")
                P("KiSpeed", Label="Speed Ki", Units="V/rad", Default=3, Min=0, Max=1e6, Group="Controller", ...
                    VisibleWhen=isSpeed, DisplayFormat="%.4g", Description="0 gives a P controller.")
                P("Kp", Label="Position Kp", Units="V/rad", Default=10, Min=0, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPosition, DisplayFormat="%.4g", ...
                    Description="V = Kp e + Ki ∫e dt − Kd ω, e = θ_ref − θ (rad).")
                P("Ki", Label="Position Ki", Units="V/(rad·s)", Default=0, Min=0, Max=1e6, Group="Controller", ...
                    VisibleWhen=isPosition, DisplayFormat="%.4g", Description="Removes the steady error under a load torque.")
                P("Kd", Label="Position Kd", Units="V·s/rad", Default=0.6, Min=0, Max=1e4, Group="Controller", ...
                    VisibleWhen=isPosition, DisplayFormat="%.4g", ...
                    Description="Acts on the measured speed ω (no kick when the reference steps).")
                P("antiWindup", Label="Anti-windup", Type="choice", Default="clamping", Choices=["none" "clamping"], ...
                    ChoiceLabels=["None" "Clamping"], Group="Controller", VisibleWhen=@(p) p.mode ~= "open", ...
                    Description="None: the integral keeps growing while the voltage is clipped (windup). " + ...
                    "Clamping: it holds while the voltage is clipped and the error would push it further.")
                P("voltage", Label="Voltage", Type="schedule", Units="V", Group="Commands", VisibleWhen=isOpen, ...
                    Default=S("step", Value=0, Amplitude=12, Start=0.05), Min=-1e4, Max=1e4, ...
                    Description="Applied directly (then clipped to ±Vmax).")
                P("speedRef", Label="Speed reference", Type="schedule", Units="rpm", Group="Commands", ...
                    VisibleWhen=isSpeed, Default=S("step", Value=0, Amplitude=600, Start=0.05), Min=-1e6, Max=1e6, ...
                    Description="The speed the controller aims for (the gains act on rad/s).")
                P("angleRef", Label="Angle reference", Type="schedule", Units="°", Group="Commands", ...
                    VisibleWhen=isPosition, Default=S("step", Value=0, Amplitude=90, Start=0.05), Min=-1e6, Max=1e6, ...
                    Description="The angle the controller aims for, counter-clockwise (the gains act on rad).")
                P("load", Label="Load torque", Type="schedule", Units="N·m", Default=0, Min=-1e4, Max=1e4, ...
                    Group="Commands", Description="Opposes positive rotation (a step: a weight hung on the shaft).")
                P("tspan", Label="Duration", Units="s", Default=1, Min=1e-3, Max=1000, Group="Simulation", ...
                    MarksCustom=false, Description="The motor starts at rest at t = 0.")
                P("dt", Label="Output step", Units="s", Default=1e-3, Min=1e-6, Max=1, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of the samples (at most 2 million); the solver's " + ...
                    "own step is shorter when the motor or the loop is fast.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            windup = struct("Kp", 10, "Ki", 50, "Kd", 0.6, "Vmax", 12, "antiWindup", "none", ...
                "angleRef", S("step", Value=0, Amplitude=360, Start=0.05), "tspan", 1.5);
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Open loop: voltage step", "Values", struct("mode", "open", "tspan", 1.2));
            list(end+1) = struct("Name", "Speed loop: PI (Ki = 0 for P)", "Values", struct("mode", "speed"));
            list(end+1) = struct("Name", "Position P (oscillatory)", "Values", struct("Kp", 5, "Kd", 0, "tspan", 2));
            list(end+1) = struct("Name", "Position PD (well damped)", "Values", struct());
            list(end+1) = struct("Name", "PID, saturated: windup", "Values", windup);
            windup.antiWindup = "clamping";
            list(end+1) = struct("Name", "PID, saturated: anti-windup", "Values", windup);
            list(end+1) = struct("Name", "Load torque disturbance (PID)", "Values", struct("Ki", 50, ...
                "angleRef", 0, "load", S("step", Value=0, Amplitude=0.1, Start=0.2), "tspan", 1.5));
        end

        function result = solve(obj, p)
            q = obj.engineParams(p);
            q.progressFcn = obj.progressMonitor();
            result = dlab.sims.dcmotor.simulateDcMotor(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Angle and speed" "Voltage and current" "Error and power" "Poles"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            grid = uigridlayout(containers{"Angle and speed"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.angle = dlab.ui.axesIn(grid, t, Row=1, Title="Shaft angle", XLabel="Time (s)", YLabel="θ (°)");
            obj.Ax.speed = dlab.ui.axesIn(grid, t, Row=2, Title="Speed", XLabel="Time (s)", YLabel="ω (rpm)");
            grid = uigridlayout(containers{"Voltage and current"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.voltage = dlab.ui.axesIn(grid, t, Row=1, Title="Voltage", XLabel="Time (s)", YLabel="V (V)");
            obj.Ax.current = dlab.ui.axesIn(grid, t, Row=2, Title="Armature current", XLabel="Time (s)", ...
                YLabel="i (A)");
            grid = uigridlayout(containers{"Error and power"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.error = dlab.ui.axesIn(grid, t, Row=1, Title="Tracking error", XLabel="Time (s)", YLabel="Error");
            obj.Ax.power = dlab.ui.axesIn(grid, t, Row=2, Title="Power", XLabel="Time (s)", YLabel="Power (W)");
            grid = uigridlayout(containers{"Poles"}, [1 2], Padding=0, ColumnWidth={"2x", "1x"}, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.poles = dlab.ui.axesIn(grid, t, Column=1, Title="Poles (s-plane, linear, no voltage limit)", ...
                XLabel="Real (1/s)", YLabel="Imaginary (rad/s)");
            obj.Ax.gains = uitextarea(grid, Editable="off", FontName=t.MonoFont, FontSize=t.FontSize.md, ...
                BackgroundColor=t.Surface, FontColor=t.Text);
            obj.Ax.gains.Layout.Column = 2;
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Motor", XLabel="", YLabel="");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            mode = params.mode;

            ax = obj.Ax.angle;
            dlab.ui.clearAxes(ax);
            if mode == "position"
                plot(ax, r.t, rad2deg(r.reference), "--", Color=t.TextMuted, LineWidth=1.2, DisplayName="Reference");
            end
            plot(ax, r.t, rad2deg(r.theta), Color=t.series(1), LineWidth=1.6, DisplayName="Angle");
            hold(ax, "off");
            legendIf(ax, t, mode == "position");

            ax = obj.Ax.speed;
            dlab.ui.clearAxes(ax);
            if mode == "speed"
                plot(ax, r.t, rpm(r.reference), "--", Color=t.TextMuted, LineWidth=1.2, DisplayName="Reference");
            end
            plot(ax, r.t, rpm(r.omega), Color=t.series(2), LineWidth=1.6, DisplayName="Speed");
            hold(ax, "off");
            legendIf(ax, t, mode == "speed");

            ax = obj.Ax.voltage;
            dlab.ui.clearAxes(ax);
            band = params.Vmax;
            patch(ax, [r.t(1) r.t(end) r.t(end) r.t(1)], [-band -band band band], t.series(3), ...
                FaceAlpha=0.08, EdgeColor="none", DisplayName="Supply limit ±Vmax");
            plot(ax, r.t, r.Vcmd, "--", Color=t.TextMuted, LineWidth=1.1, DisplayName="Commanded");
            plot(ax, r.t, r.V, Color=t.series(3), LineWidth=1.6, DisplayName="Applied");
            hold(ax, "off");
            ylim(ax, paddedLimits([r.V; -band; band; clip(r.Vcmd, 3 * band)]));
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.current;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.i, Color=t.series(5), LineWidth=1.5);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            hold(ax, "off");

            ax = obj.Ax.error;
            dlab.ui.clearAxes(ax);
            [scale, units] = errorUnits(mode);
            if mode == "open"
                ax.Title.String = "Tracking error (no reference in open loop)";
                ax.YLabel.String = "Error";
            else
                ax.Title.String = "Tracking error (reference − measured)";
                ax.YLabel.String = "Error (" + units + ")";
                plot(ax, r.t, scale * r.error, Color=t.series(1), LineWidth=1.5);
                yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            end
            hold(ax, "off");

            ax = obj.Ax.power;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.power, Color=t.series(3), LineWidth=1.5, DisplayName="From the supply (V i)");
            plot(ax, r.t, r.shaftPower, Color=t.series(2), LineWidth=1.4, DisplayName="Shaft (K i ω)");
            plot(ax, r.t, r.copperLoss, Color=t.series(4), LineWidth=1.2, DisplayName="Copper loss (R i²)");
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.poles;
            dlab.ui.clearAxes(ax);
            xline(ax, 0, ":", Color=t.TextMuted, HandleVisibility="off");
            yline(ax, 0, ":", Color=t.TextMuted, HandleVisibility="off");
            plot(ax, real(r.openPoles), imag(r.openPoles), "x", Color=t.Danger, MarkerSize=11, LineWidth=2, ...
                DisplayName="Open loop (motor)");
            if mode ~= "open"
                plot(ax, real(r.closedPoles), imag(r.closedPoles), "o", Color=t.series(3), MarkerSize=9, ...
                    LineWidth=1.8, DisplayName="Closed loop");
                shown = [r.openPoles; r.closedPoles];
            else
                shown = r.openPoles;
            end
            [xl, yl, far] = poleView(shown);
            if ~isempty(far)
                text(ax, 0.02, 0.04, "Off to the left: " + strjoin(compose("%.4g", far), ", ") + " 1/s", ...
                    Units="normalized", Color=t.TextMuted, FontSize=t.FontSize.sm, VerticalAlignment="bottom");
            end
            hold(ax, "off");
            set(ax, XLim=xl, YLim=yl);
            dlab.ui.legend(ax, t, "Location", "best");
            obj.Ax.gains.Value = poleText(r, params);

            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                q = run.Result;
                dlab.ui.overlayLine(obj.Ax.angle, q.t, rad2deg(q.theta), run);
                dlab.ui.overlayLine(obj.Ax.speed, q.t, rpm(q.omega), run);
                dlab.ui.overlayLine(obj.Ax.voltage, q.t, q.V, run);
                dlab.ui.overlayLine(obj.Ax.current, q.t, q.i, run);
                dlab.ui.overlayLine(obj.Ax.power, q.t, q.power, run);
                if any(isfinite(q.error))
                    scale = errorUnits(run.Params.mode);
                    dlab.ui.overlayLine(obj.Ax.error, q.t, scale * q.error, run);
                end
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = ["angle" "speed" "voltage" "current" "error" "power" "poles"]
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            obj.Ax.gains.Value = "";
            delete(allchild(obj.Anim.axes));
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(~, r)
            % Servo responses last a fraction of a second: play each run in about 8 s.
            rate = max(r.t(end), eps) / 8;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "rotor")
                return
            end
            a = obj.Anim;
            t = obj.Theme;
            k = dlab.core.frameAt(r.t, simTime);
            theta = r.theta(k);
            [sx, sy] = dlab.ui.Schematic.wheel([0 0], 1, 3, theta + pi / 2);
            set(a.spokes, XData=sx(50:end), YData=sy(50:end));
            set(a.pointer, XData=[0 -0.92 * sin(theta)], YData=[0 0.92 * cos(theta)]);
            if isfinite(r.reference(k)) && a.showReference
                ref = r.reference(k);
                set(a.reference, XData=[-0.6 -1.18] * sin(ref), YData=[0.6 1.18] * cos(ref), Visible="on");
                set(a.refTip, XData=-1.24 * sin(ref), YData=1.24 * cos(ref), Visible="on");
            end

            h = obj.BarHalf;
            level = h * max(min(r.i(k) / a.iScale, 1.1), -1.1);
            [bx, by] = dlab.ui.Schematic.rect([a.iBar, level / 2], 0.15, abs(level) / 2 + 1e-9);
            set(a.current, XData=bx, YData=by);
            level = h * r.V(k) / a.vScale;
            [bx, by] = dlab.ui.Schematic.rect([a.vBar, level / 2], 0.15, abs(level) / 2 + 1e-9);
            color = t.series(3);
            if r.saturated(k)
                color = t.Warning;
            end
            set(a.voltage, XData=bx, YData=by, FaceColor=color);
            command = h * max(min(r.Vcmd(k) / a.vScale, 1.3), -1.3);
            set(a.command, XData=a.vBar + [-0.24 0.24], YData=command * [1 1]);

            tau = r.load(k);
            if abs(tau) > 0
                % Below the rotor, an arc arrow against positive (counterclockwise)
                % rotation when τ > 0.
                phi = pi + linspace(0.45, -0.45, 24) * sign(tau);
                arcX = -1.55 * sin(phi);
                arcY = 1.55 * cos(phi);
                tip = [arcX(end) arcY(end)];
                along = tip - [arcX(end - 1) arcY(end - 1)];
                along = 0.2 * along / norm(along);
                [~, ~, hx, hy] = dlab.ui.Schematic.arrow(tip - along, along, 0.2);
                set(a.loadArc, XData=arcX, YData=arcY, Visible="on");
                set(a.loadHead, XData=hx, YData=hy, Visible="on");
                a.loadLabel.Visible = "on";
            else
                set([a.loadArc a.loadHead a.loadLabel], Visible="off");
            end
            a.readout.String = sprintf("t = %.3f s   θ = %+.1f°   ω = %+.0f rpm   i = %+.2f A   V = %+.1f V", ...
                simTime, rad2deg(theta), rpm(r.omega(k)), r.i(k), r.V(k));
        end

        function T = exportTable(~, r)
            [scale, units] = errorUnits(r.params.mode);
            T = table(r.t, rad2deg(r.theta), rpm(r.omega), r.i, r.Vcmd, r.V, scale * r.reference, scale * r.error, ...
                r.load, r.power, r.shaftPower, r.copperLoss, r.energy, ...
                VariableNames=["time" "angle" "speed" "current" "voltage_commanded" "voltage_applied" ...
                "reference" "error" "load_torque" "power_supply" "power_shaft" "copper_loss" "energy"]);
            T.Properties.VariableUnits = ["s" "deg" "rpm" "A" "V" "V" units units "N*m" "W" "W" "W" "J"];
            if r.params.mode == "open"
                T = removevars(T, ["reference" "error"]);    % no reference in open loop
            end
        end

        function T = summaryTable(~, r)
            p = r.params;
            scale = errorUnits(p.mode);
            stepUnits = "rpm";
            if p.mode == "position"
                stepUnits = "°";
            end
            rows = cell(0, 4);
            if ~isempty(r.step) && isfinite(r.step.final)
                still = "— (no change after the step)";
                rows = [rows
                    numberOr("Rise time (10–90 %)", r.step.rise, "s", still)
                    numberOr("Time to 63 %", r.step.t63, "s", still)
                    numberOr("Overshoot", r.step.overshoot, "%", still)
                    numberOr("Settling time (2 %)", r.step.settling, "s", still)];
            end
            if p.mode ~= "open"
                rows(end+1, :) = {"Final error", abs(scale * r.error(end)), stepUnits, ""};
            end
            weights = gradient(r.t);
            rows = [rows
                {"Peak current", max(abs(r.i)), "A", ""
                 "Peak voltage (applied)", max(abs(r.V)), "V", ""
                 "Time at the voltage limit", sum(weights(r.saturated)), "s", ""
                 "Energy used (∫ V i dt)", r.energy(end), "J", ""
                 "Final speed", rpm(r.omega(end)), "rpm", ""
                 "Mechanical time constant", r.tauMech, "s", ""
                 "Electrical time constant", 1000 * r.tauElec, "ms", ""}];
            if p.mode ~= "open"
                rows = [rows
                    numberOr("Lowest damping ratio", lowestDamping(r.closedPoles), "", "— (no closed-loop pole off 0)")
                    {"Slowest closed-loop pole", max(real(r.closedPoles)), "1/s", ""}];
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                VariableNames=["Quantity" "Value" "Units" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            notes = strings(1, 0);
            level = "success";
            if any(r.saturated)
                weights = gradient(r.t);
                notes(end+1) = sprintf("the voltage was at the ±%g V limit for %.3g s", r.params.Vmax, ...
                    sum(weights(r.saturated)));
                level = "info";
            end
            unstable = max(real(r.closedPoles));
            if r.params.mode ~= "open" && unstable > 1e-9 * max(1, max(abs(r.closedPoles)))
                notes(end+1) = sprintf("the linear closed loop is unstable (a pole at +%.3g 1/s): lower the gains", ...
                    unstable);
                level = "warning";
            end
            note = strjoin(notes, "; ");
        end

        function lin = linearization(obj, p)
            m = struct("R", p.R, "L", p.L / 1000, "K", p.K, "J", p.J, "b", p.b);
            if m.L > 0
                names = ["i" "ω" "θ"];
                scale = [1 10 1];
            else
                names = ["ω" "θ"];
                scale = [10 1];
            end
            U0 = [0; 0];
            G = @(x, u) dlab.sims.dcmotor.dynamics(x, u, m);
            lin = struct("F", @(x) G(x, U0), "X0", zeros(numel(names), 1), "StateNames", names, ...
                "Reference", "at rest with no voltage or load: the motor alone, without the controller", ...
                "Classify", @(lambda, V) modeNames(lambda, V, m), "Scale", scale, ...
                "G", G, "U0", U0, "InputNames", ["Voltage" "Load torque"], ...
                "H", @(x, ~) x(end - 1:end), "OutputNames", ["Speed" "Angle"]);
            if string(p.mode) ~= "open"
                lin.Loop = voltageLoop(m, obj.engineParams(p), numel(names));
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Position P (oscillatory)", "Tab", "Animation", "Time", 0.25);
        end

        function description = about(~)
            description = join([
                "Armature:  L di/dt = V − R i − K ω"
                "Rotor:     J dω/dt = K i − b ω − τ_load,   dθ/dt = ω"
                "(K is both the back-EMF constant in V·s/rad and the torque constant in N·m/A.)"
                ""
                "Open loop:  V = the voltage schedule"
                "Speed:      V = Kp e + Ki ∫e dt,         e = ω_ref − ω"
                "Position:   V = Kp e + Ki ∫e dt − Kd ω,  e = θ_ref − θ"
                ""
                "The applied voltage is clipped to ±Vmax. While it is clipped an integral keeps " + ...
                "growing (windup) unless clamping holds it. With L → 0 the speed responds to a " + ...
                "voltage step in first order, with time constant τ = J R / (K² + b R) and steady " + ...
                "speed K V / (K² + b R)."
            ], newline);
        end
    end

    methods (Access = private)
        function q = engineParams(~, p)
            S = @dlab.core.Schedule.normalize;
            switch p.mode
                case "open"
                    command = S(p.voltage);
                    unit = 1;
                case "speed"
                    command = S(p.speedRef);
                    unit = pi / 30;
                otherwise
                    command = S(p.angleRef);
                    unit = pi / 180;
            end
            fcn = dlab.core.Schedule.toFunction(command);
            q = struct("R", p.R, "L", p.L / 1000, "K", p.K, "J", p.J, "b", p.b, "Vmax", p.Vmax, ...
                "mode", char(p.mode), "Kp", p.Kp, "Ki", p.Ki, "Kd", p.Kd, "antiWindup", char(p.antiWindup), ...
                "command", @(t) unit * fcn(t), "load", dlab.core.Schedule.toFunction(p.load), ...
                "tspan", p.tspan, "dt", p.dt, "stepWindow", []);
            if p.mode == "speed"
                [q.Kp, q.Ki, q.Kd] = deal(p.KpSpeed, p.KiSpeed, 0);
            end
            % Step metrics for a step command, up to a later change in the load.
            if command.shape == "step" && command.amplitude ~= 0 && command.start < p.tspan
                stop = p.tspan;
                load = S(p.load);
                if load.shape ~= "constant" && load.start > command.start && load.start < stop
                    stop = load.start;
                end
                q.stepWindow = [command.start stop];
            end
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            h = obj.BarHalf;
            [hx, hy] = dlab.ui.Schematic.rect([0 0], 1.25, 1.25);
            patch(ax, hx, hy, t.Grid, FaceAlpha=0.35, EdgeColor=t.TextMuted, LineWidth=1.2);
            [cx, cy] = dlab.ui.Schematic.circle([0 0], 1, 72);
            a.rotor = patch(ax, cx, cy, t.series(1), FaceAlpha=0.18, EdgeColor=t.Text, LineWidth=1.5);
            phi = (0:obj.DialTicks - 1) * 2 * pi / obj.DialTicks;
            tickX = [-sin(phi); -1.1 * sin(phi); nan(size(phi))];
            tickY = [cos(phi); 1.1 * cos(phi); nan(size(phi))];
            plot(ax, tickX(:), tickY(:), Color=t.TextMuted, LineWidth=1);
            a.spokes = plot(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.2);
            a.reference = plot(ax, NaN, NaN, "--", Color=t.series(6), LineWidth=2, Visible="off");
            a.refTip = plot(ax, NaN, NaN, "v", MarkerSize=8, MarkerFaceColor=t.series(6), ...
                MarkerEdgeColor=t.series(6), Visible="off");
            a.pointer = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=4);
            plot(ax, 0, 0, "o", MarkerSize=9, MarkerFaceColor=t.Text, MarkerEdgeColor=t.Text);
            a.showReference = params.mode == "position";
            a.loadArc = plot(ax, NaN, NaN, Color=t.Danger, LineWidth=2, Visible="off");
            a.loadHead = patch(ax, NaN, NaN, t.Danger, EdgeColor="none", Visible="off");
            a.loadLabel = text(ax, 0, -1.68, "load torque", HorizontalAlignment="center", ...
                VerticalAlignment="top", Color=t.Danger, FontSize=t.FontSize.sm, Visible="off");

            % Current and voltage bars, ±BarHalf at full scale.
            a.iBar = 1.95;
            a.vBar = 2.6;
            a.iScale = max([max(abs(r.i)), 1e-6]);
            a.vScale = params.Vmax;
            for x = [a.iBar a.vBar]
                [fx, fy] = dlab.ui.Schematic.rect([x 0], 0.18, h);
                patch(ax, fx, fy, t.Grid, FaceAlpha=0.15, EdgeColor=t.TextMuted);
            end
            plot(ax, [a.iBar a.vBar; a.iBar a.vBar] + [-0.24; 0.24], [0 0; 0 0], Color=t.TextMuted);
            a.current = patch(ax, NaN, NaN, t.series(5), EdgeColor="none");
            a.voltage = patch(ax, NaN, NaN, t.series(3), EdgeColor="none");
            a.command = plot(ax, NaN, NaN, Color=t.Text, LineWidth=2);
            text(ax, a.iBar, -h - 0.15, sprintf("i\n±%.3g A", a.iScale), HorizontalAlignment="center", ...
                VerticalAlignment="top", Color=t.TextMuted, FontSize=t.FontSize.sm);
            text(ax, a.vBar, -h - 0.15, sprintf("V\n±%.3g V", a.vScale), HorizontalAlignment="center", ...
                VerticalAlignment="top", Color=t.TextMuted, FontSize=t.FontSize.sm);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            set(ax, XLim=[-1.75 3.05], YLim=[-1.95 1.95], XTick=[], YTick=[]);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function v = rpm(omega)
v = omega * 30 / pi;
end

function [scale, units] = errorUnits(mode)
% Errors are shown in degrees (position) or rpm (speed).
switch mode
    case "position"
        [scale, units] = deal(180 / pi, "deg");
    case "speed"
        [scale, units] = deal(30 / pi, "rpm");
    otherwise
        [scale, units] = deal(1, "");
end
end

function zeta = lowestDamping(poles)
% The smallest damping ratio −Re λ / |λ| among the closed-loop poles: the
% least damped motion (1 for a stable real pole, negative when unstable). A
% pole at the origin (a free integrator, no motion of its own) is left out;
% NaN when no pole is left.
poles = poles(abs(poles) > 1e-9 * max(1, max(abs(poles))));
zeta = min(-real(poles) ./ abs(poles));
if isempty(zeta)
    zeta = NaN;
end
end

function row = numberOr(name, value, units, text)
% A Summary row, with TEXT in place of a value that is not a number.
if isfinite(value)
    row = {name, value, units, ""};
else
    row = {name, NaN, units, text};
end
end

function [xl, yl, far] = poleView(poles)
% Axis limits around the slow poles; a pole more than 10 times faster than
% the rest (the electrical pole, usually) is left out and listed in FAR.
m = sort(abs(poles(:)));
gap = find(m(2:end) > 10 * m(1:end - 1) & m(1:end - 1) > 1e-6 * max(m), 1, "last");
far = [];
reach = max(m);
if ~isempty(gap)
    reach = m(gap);
    far = unique(round(real(poles(abs(poles) > reach)), 4, "significant"));
end
reach = max(reach, 1);
xl = [-1.3 * reach, 0.3 * reach];
near = poles(abs(poles) <= reach);
yl = 1.2 * max([reach; abs(imag(near(:)))]) * [-1 1];
end

function v = clip(v, limit)
v = min(max(v, -limit), limit);
end

function lim = paddedLimits(v)
lo = min(v);
hi = max(v);
pad = 0.08 * max(hi - lo, eps);
lim = [lo - pad, hi + pad];
end

function legendIf(ax, t, show)
if show
    dlab.ui.legend(ax, t, "Location", "best");
end
end

function text = poleText(r, params)
% Short lines: the column is narrow, at Larger text especially.
names = struct("open", "open loop", "speed", "speed (P, PI)", "position", "position (P, PD, PID)");
lines = "Control: " + names.(params.mode);
switch params.mode
    case "speed"
        lines(end+1) = sprintf("Kp = %.4g V·s/rad", params.KpSpeed);
        lines(end+1) = sprintf("Ki = %.4g V/rad", params.KiSpeed);
    case "position"
        lines(end+1) = sprintf("Kp = %.4g V/rad", params.Kp);
        lines(end+1) = sprintf("Ki = %.4g V/(rad·s)", params.Ki);
        lines(end+1) = sprintf("Kd = %.4g V·s/rad", params.Kd);
end
lines(end+1) = sprintf("τ_mech = %.4g s", r.tauMech);
lines(end+1) = "  = J R/(K² + b R)";
lines(end+1) = sprintf("τ_elec = L/R = %.4g ms", 1000 * r.tauElec);
lines(end+1) = sprintf("Speed per volt = %.4g rpm/V", rpm(r.gain));
lines(end+1) = "";
lines(end+1) = "Open-loop poles (motor):";
lines = [lines(:); compose("  %s", poleStrings(r.openPoles))];
if params.mode ~= "open"
    lines(end+1) = "Closed-loop poles:";
    lines = [lines; compose("  %s", poleStrings(r.closedPoles))];
    lines(end+1) = sprintf("Lowest damping ratio ζ = %.3g", lowestDamping(r.closedPoles));
end
text = lines(:);
end

function s = poleStrings(p)
s = strings(numel(p), 1);
for k = 1:numel(p)
    if abs(imag(p(k))) < 1e-9 * max(1, abs(p(k)))
        s(k) = sprintf("%.4g", real(p(k)));
    else
        signs = ["+" "−"];
        s(k) = sprintf("%.4g %s %.4gi", real(p(k)), signs(1 + (imag(p(k)) < 0)), abs(imag(p(k))));
    end
end
end

function labels = modeNames(lambda, V, m)
%MODENAMES The shaft angle (neutral), and electrical or mechanical modes
%   by where each mode keeps its energy (½ L i² against ½ J ω²).
labels = strings(numel(lambda), 1);
scale = max(1, max(abs(lambda)));
for k = 1:numel(lambda)
    if abs(lambda(k)) < 1e-7 * scale
        labels(k) = "Shaft angle (neutral)";
    elseif abs(imag(lambda(k))) > 1e-9 * scale
        labels(k) = "Electromechanical oscillation";
    elseif m.L > 0 && m.L * abs(V(1, k))^2 > m.J * abs(V(2, k))^2
        labels(k) = "Electrical (current)";
    else
        labels(k) = "Mechanical (speed)";
    end
end
end

function loop = voltageLoop(m, q, n)
% The control loop broken where the controller's voltage enters the motor:
% inject a voltage u; what returns is the voltage the controller then asks
% for (reference zero, no load). Q holds the gains in use (engineParams).
% States: the motor's, then ∫e with an integral term. Speed control feeds
% back ω, position control θ (and ω through Kd).
speed = n - 1;                              % ω, then θ, are the last two states
measured = n;
kd = q.Kd;
if string(q.mode) == "speed"
    measured = speed;
    kd = 0;
end
hasIntegral = q.Ki ~= 0;
G = @(x, u) [dlab.sims.dcmotor.dynamics(x(1:n), [u; 0], m); -x(measured) * ones(hasIntegral, 1)];
H = @(x, ~) -q.Kp * x(measured) - kd * x(speed) + hasIntegral * q.Ki * x(end);
loop = struct("G", G, "X0", zeros(n + hasIntegral, 1), "U0", 0, "H", H, "Name", "the motor voltage");
end
