classdef HandlingPlugin < dlab.core.TimeDomainPlugin
    %HANDLINGPLUGIN A car's yaw and sideslip response to steering on the
    %   single-track (bicycle) model: understeer, oversteer, the critical
    %   speed, and the tyre limit. Solved by simulateHandling.

    properties (Constant)
        Id = "handling"
        Title = "Vehicle Handling"
        Category = "Controls & Vehicles"
        Summary = "A car turning on the bicycle model: understeer and oversteer, the critical speed, lane changes, and the tyre limit."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        Gravity = 9.81            % m/s², for axle loads and "g" units
        Overhang = 0.85           % m beyond each axle (drawing only)
        HalfWidth = 0.9           % m, half the body width (drawing)
        HalfTrack = 0.78          % m, half the track (drawing)
        WheelHalfLength = 0.33    % m (drawing)
        WheelHalfWidth = 0.11     % m (drawing)
        Snapshots = 8             % cars drawn along the path
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
            specs = [
                P("m", Label="Mass", Units="kg", Default=1500, Min=1, Max=1e6, Group="Car", ...
                    Description="The whole car.")
                P("Iz", Label="Yaw moment of inertia", Units="kg·m²", Default=2500, Min=0.01, Max=1e8, Group="Car", ...
                    Description="About the vertical axis through the centre of mass; roughly m a b for a car.")
                P("a", Label="Centre of mass to front axle", Units="m", Default=1.1, Min=0.05, Max=20, Group="Car", ...
                    Description="Along the car. The rear axle carries the fraction a / L of the weight.")
                P("b", Label="Centre of mass to rear axle", Units="m", Default=1.6, Min=0.05, Max=20, Group="Car", ...
                    Description="The wheelbase is L = a + b. The front axle carries the fraction b / L of the weight.")
                P("Cf", Label="Front cornering stiffness", Units="N/rad", Default=80000, Min=100, Max=1e8, ...
                    Group="Car", Description="Per axle: the lateral force per radian of slip of both front tyres together.")
                P("Cr", Label="Rear cornering stiffness", Units="N/rad", Default=110000, Min=100, Max=1e8, ...
                    Group="Car", Description="Per axle, both rear tyres together. Understeer when b/Cf > a/Cr: the front tyres slip more than the rear.")
                P("tyre", Label="Tyre model", Type="choice", Default="linear", Choices=["linear" "saturating"], ...
                    ChoiceLabels=["Linear" "Saturating"], Group="Tyres", ...
                    Description="Linear: F = −C α, with no limit. Saturating: F = −μ F_z tanh(C α / (μ F_z)), " + ...
                    "never more than the friction limit μ F_z, with the static axle loads.")
                P("mu", Label="Friction coefficient μ", Default=0.9, Min=0.05, Max=3, Group="Tyres", ...
                    VisibleWhen=@(p) p.tyre == "saturating", ...
                    Description="Dry asphalt about 0.9, wet 0.5–0.7, snow 0.2, ice 0.1.")
                P("speed", Label="Speed", Units="km/h", Default=100, Min=5, Max=400, Group="Driving", ...
                    Description="Constant forward speed.")
                P("steer", Label="Steering (road wheels)", Type="schedule", Units="°", ...
                    Default=S("step", Value=0, Amplitude=2, Start=0.5), Min=-30, Max=30, Group="Driving", ...
                    Description="The angle of the front wheels (about 1/15 of the steering-wheel angle); positive turns left.")
                P("tspan", Label="Duration", Units="s", Default=6, Min=0.05, Max=600, Group="Simulation", ...
                    MarksCustom=false, Description="Length of the run; it stops sooner if the sideslip passes 30° (a spin).")
                P("dt", Label="Output step", Units="s", Default=0.01, Min=1e-4, Max=1, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of the samples; the solver's own steps are at most " + ...
                    "0.02 s.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            oversteer = {"a", 1.5, "b", 1.2, "Cf", 90000, "Cr", 75000};
            laneChange = [0 0; 1 0; 1.25 2.4; 1.5 3.4; 1.75 2.4; 2 0; 2.25 -2.4; 2.5 -3.4; 2.75 -2.4; 3 0
                4 0; 4.25 -2.4; 4.5 -3.4; 4.75 -2.4; 5 0; 5.25 2.4; 5.5 3.4; 5.75 2.4; 6 0];
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Family car (understeer): step steer", "Values", struct());
            list(end+1) = struct("Name", "Neutral steer: step steer", "Values", struct( ...
                "a", 1.35, "b", 1.35, "Cf", 90000, "Cr", 90000, "speed", 80, ...
                "steer", S("step", Value=0, Amplitude=1, Start=0.5)));
            list(end+1) = struct("Name", "Oversteer, below the critical speed (70 km/h)", "Values", struct( ...
                oversteer{:}, "speed", 70, "steer", S("step", Value=0, Amplitude=1, Start=0.5)));
            list(end+1) = struct("Name", "Oversteer, above the critical speed (120 km/h)", "Values", struct( ...
                oversteer{:}, "speed", 120, "steer", S("step", Value=0, Amplitude=1, Start=0.5)));
            list(end+1) = struct("Name", "Double lane change (80 km/h)", "Values", struct( ...
                "speed", 80, "steer", S("points", Points=laneChange), "tspan", 7.5));
            list(end+1) = struct("Name", "Tyre limit: understeer (saturating tyres)", "Values", struct( ...
                "tyre", "saturating", "mu", 0.9, "speed", 80, ...
                "steer", S("ramp", Value=0, Amplitude=8, Start=0.5, Width=5)));
            list(end+1) = struct("Name", "Slalom (sine steering, 60 km/h)", "Values", struct( ...
                "speed", 60, "steer", S("sine", Value=0, Amplitude=2, Start=0.5, Period=2), "tspan", 8));
        end

        function result = solve(obj, p)
            q = obj.engineParams(p);
            q.steer = dlab.core.Schedule.toFunction(p.steer, [-30 30]);
            q.steer = @(t) deg2rad(q.steer(t));
            q.progressFcn = obj.progressMonitor();
            result = dlab.sims.handling.simulateHandling(q);
            result.V = q.V;
            result.L = p.a + p.b;
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Path" "Yaw rate and lateral acceleration" "Sideslip and slip angles" "Steering" ...
                "Yaw gain vs speed"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            grid = uigridlayout(containers{"Path"}, [2 1], Padding=0, RowHeight={"2x", "1x"}, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.path = dlab.ui.axesIn(grid, t, Row=1, Title="Path from above (to scale)", ...
                XLabel="x (m, forward at the start)", YLabel="y (m, to the left)");
            obj.Ax.lateral = dlab.ui.axesIn(grid, t, Row=2, Title="Lateral position (y stretched)", ...
                XLabel="x (m)", YLabel="y (m)");
            grid = uigridlayout(containers{"Yaw rate and lateral acceleration"}, [2 1], Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.yaw = dlab.ui.axesIn(grid, t, Row=1, Title="Yaw rate", XLabel="Time (s)", YLabel="r (°/s)");
            obj.Ax.ay = dlab.ui.axesIn(grid, t, Row=2, Title="Lateral acceleration", XLabel="Time (s)", ...
                YLabel="a_y (g)");
            grid = uigridlayout(containers{"Sideslip and slip angles"}, [2 1], Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.beta = dlab.ui.axesIn(grid, t, Row=1, Title="Sideslip angle β (velocity from the car's axis)", ...
                XLabel="Time (s)", YLabel="β (°)");
            obj.Ax.slip = dlab.ui.axesIn(grid, t, Row=2, Title="Tyre slip angles", XLabel="Time (s)", ...
                YLabel="α (°)");
            obj.Ax.steer = dlab.ui.axesIn(containers{"Steering"}, t, Title="Steering angle at the road wheels", ...
                XLabel="Time (s)", YLabel="δ (°)");
            obj.Ax.gain = dlab.ui.axesIn(containers{"Yaw gain vs speed"}, t, ...
                Title="Steady-state yaw-rate gain r/δ (linear)", XLabel="Speed (km/h)", YLabel="r/δ (1/s)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="From above", XLabel="x (m)", YLabel="y (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, ~)
            obj.Result = r;
            t = obj.Theme;
            g = obj.Gravity;

            ax = obj.Ax.path;
            dlab.ui.clearAxes(ax);
            idx = obj.snapshotIndices(r);
            [bodyF, bodyV, wheelF, wheelV] = obj.carShapes(r, idx);
            patch(ax, Faces=bodyF, Vertices=bodyV, FaceColor=t.series(1), FaceAlpha=0.18, ...
                EdgeColor=t.series(1), LineWidth=1, HandleVisibility="off");
            patch(ax, Faces=wheelF, Vertices=wheelV, FaceColor=t.Text, EdgeColor="none", HandleVisibility="off");
            plot(ax, r.x, r.y, Color=t.series(1), LineWidth=1.8, DisplayName="Centre of mass");
            plot(ax, r.x(1), r.y(1), "o", MarkerFaceColor=t.series(2), MarkerEdgeColor=t.Text, ...
                DisplayName="Start");
            hold(ax, "off");
            axis(ax, "equal");
            pad = 3;
            set(ax, XLim=[min(r.x) - pad, max(r.x) + pad], YLim=[min(r.y) - pad, max(r.y) + pad]);
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.lateral;
            dlab.ui.clearAxes(ax);
            plot(ax, r.x, r.y, Color=t.series(1), LineWidth=1.6);
            hold(ax, "off");

            ax = obj.Ax.yaw;
            dlab.ui.clearAxes(ax);
            if all(isfinite(r.rSteady))
                plot(ax, r.t, rad2deg(r.rSteady), "--", Color=t.TextMuted, LineWidth=1.2, ...
                    DisplayName="Linear steady state (gain × δ)");
            end
            plot(ax, r.t, rad2deg(r.r), Color=t.series(1), LineWidth=1.6, DisplayName="Yaw rate");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.ay;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.ay / g, Color=t.series(2), LineWidth=1.6, DisplayName="a_y");
            if r.params.tyre == "saturating"
                yline(ax, r.params.mu * [-1 1], ":", Color=t.Danger, LineWidth=1.2, HandleVisibility="off");
                yline(ax, r.params.mu, ":", "Friction limit μ g", Color=t.Danger, LineWidth=1.2, ...
                    LabelHorizontalAlignment="left", FontSize=t.FontSize.sm, HandleVisibility="off");
            end
            hold(ax, "off");

            ax = obj.Ax.beta;
            dlab.ui.clearAxes(ax);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            plot(ax, r.t, rad2deg(r.beta), Color=t.series(4), LineWidth=1.6);
            hold(ax, "off");

            ax = obj.Ax.slip;
            dlab.ui.clearAxes(ax);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            plot(ax, r.t, rad2deg(r.alphaF), Color=t.series(3), LineWidth=1.6, DisplayName="Front α_f");
            plot(ax, r.t, rad2deg(r.alphaR), Color=t.series(5), LineWidth=1.6, DisplayName="Rear α_r");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.steer;
            dlab.ui.clearAxes(ax);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            plot(ax, r.t, rad2deg(r.delta), Color=t.series(1), LineWidth=1.6);
            hold(ax, "off");

            ax = obj.Ax.gain;
            dlab.ui.clearAxes(ax);
            c = r.gainCurve;
            plot(ax, 3.6 * c.V, c.V / r.L, "--", Color=t.TextMuted, LineWidth=1.2, DisplayName="Neutral steer V/L");
            plot(ax, 3.6 * c.V, c.gain, Color=t.series(1), LineWidth=1.8, DisplayName="This car");
            xline(ax, 3.6 * r.V, "-", "This run", Color=t.series(2), LineWidth=1.2, ...
                LabelOrientation="horizontal", FontSize=t.FontSize.sm, HandleVisibility="off");
            if isfinite(r.characteristicSpeed)
                xline(ax, 3.6 * r.characteristicSpeed, ":", "Characteristic speed", Color=t.TextMuted, ...
                    LabelOrientation="horizontal", LabelVerticalAlignment="bottom", FontSize=t.FontSize.sm, ...
                    HandleVisibility="off");
            elseif isfinite(r.criticalSpeed)
                xline(ax, 3.6 * r.criticalSpeed, "--", "Critical speed", Color=t.Danger, LineWidth=1.2, ...
                    LabelOrientation="horizontal", LabelVerticalAlignment="bottom", FontSize=t.FontSize.sm, ...
                    HandleVisibility="off");
            end
            hold(ax, "off");
            top = max(c.gain(isfinite(c.gain)));
            if ~isfinite(r.criticalSpeed)
                top = max(top, c.V(end) / r.L);
            end
            set(ax, XLim=3.6 * [0 c.V(end)], YLim=[0, min(1.1 * max(top, eps), 4 * c.V(end) / r.L)]);
            dlab.ui.legend(ax, t, "Location", "northwest");

            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                q = run.Result;
                dlab.ui.overlayLine(obj.Ax.path, q.x, q.y, run);
                dlab.ui.overlayLine(obj.Ax.lateral, q.x, q.y, run);
                dlab.ui.overlayLine(obj.Ax.yaw, q.t, rad2deg(q.r), run);
                dlab.ui.overlayLine(obj.Ax.ay, q.t, q.ay / obj.Gravity, run);
                dlab.ui.overlayLine(obj.Ax.beta, q.t, rad2deg(q.beta), run);
                dlab.ui.overlayLine(obj.Ax.slip, q.t, rad2deg(q.alphaF), run);
                dlab.ui.overlayLine(obj.Ax.steer, q.t, rad2deg(q.delta), run);
                dlab.ui.overlayLine(obj.Ax.gain, 3.6 * q.gainCurve.V, q.gainCurve.gain, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            delete(allchild(obj.Anim.axes));
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "body")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            [bodyF, bodyV, ~, wheelV] = obj.carShapes(r, k);
            set(a.body, Faces=bodyF, Vertices=bodyV);
            set(a.wheels, Vertices=wheelV);
            set(a.trail, XData=r.x(1:k), YData=r.y(1:k));

            here = [r.x(k), r.y(k)];
            heading = [cos(r.psi(k)), sin(r.psi(k))];
            left = [-heading(2), heading(1)];
            speedDir = [cos(r.psi(k) + r.beta(k)), sin(r.psi(k) + r.beta(k))];
            [lx, ly, hx, hy] = dlab.ui.Schematic.arrow(here, a.velocityLength * speedDir, 0.8);
            set(a.velocity, XData=lx, YData=ly);
            set(a.velocityHead, XData=hx, YData=hy);
            front = here + r.params.a * heading;
            rear = here - r.params.b * heading;
            [lx, ly, hx, hy] = dlab.ui.Schematic.arrow(front, a.forceScale * r.Ff(k) * left, 0.6);
            set(a.frontForce, XData=lx, YData=ly);
            set(a.frontHead, XData=hx, YData=hy);
            [lx, ly, hx, hy] = dlab.ui.Schematic.arrow(rear, a.forceScale * r.Fr(k) * left, 0.6);
            set(a.rearForce, XData=lx, YData=ly);
            set(a.rearHead, XData=hx, YData=hy);

            w = a.window;
            set(a.axes, XLim=here(1) + w * [-1 1], YLim=here(2) + a.aspect * w * [-1 1]);
            a.readout.String = sprintf("t = %.2f s   δ = %+.1f°   r = %+.1f °/s   a_y = %+.2f g   β = %+.1f°", ...
                simTime, rad2deg(r.delta(k)), rad2deg(r.r(k)), r.ay(k) / obj.Gravity, rad2deg(r.beta(k)));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.x, r.y, rad2deg(r.psi), rad2deg(r.delta), r.v, rad2deg(r.r), r.ay, ...
                rad2deg(r.beta), rad2deg(r.alphaF), rad2deg(r.alphaR), r.Ff, r.Fr, ...
                VariableNames=["time" "x" "y" "heading" "steering" "lateral_velocity" "yaw_rate" ...
                "lateral_acceleration" "sideslip" "slip_front" "slip_rear" "force_front" "force_rear"]);
            T.Properties.VariableUnits = ["s" "m" "m" "deg" "deg" "m/s" "deg/s" "m/s^2" "deg" "deg" "deg" "N" "N"];
        end

        function T = summaryTable(obj, r)
            g = obj.Gravity;
            rows = cell(0, 3);
            if isfinite(r.yawGain)
                rows(end+1, :) = {"Steady-state yaw-rate gain", r.yawGain, "1/s"};
            end
            rows = [rows
                {"Neutral-steer gain V/L", r.V / r.L, "1/s"
                 "Understeer gradient", rad2deg(r.understeerGradient * g), "deg/g"}];
            if isfinite(r.characteristicSpeed)
                rows(end+1, :) = {"Characteristic speed", 3.6 * r.characteristicSpeed, "km/h"};
            elseif isfinite(r.criticalSpeed)
                rows(end+1, :) = {"Critical speed", 3.6 * r.criticalSpeed, "km/h"};
            end
            rows = [rows
                {"Peak lateral acceleration", max(abs(r.ay)) / g, "g"
                 "Peak yaw rate", rad2deg(max(abs(r.r))), "°/s"
                 "Peak sideslip angle", rad2deg(max(abs(r.beta))), "°"
                 "Final heading", rad2deg(r.psi(end)), "°"
                 "Linear model stable", double(r.stable), ""
                 "Spun out", double(r.termination == "spun"), ""}];
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = strings(height(T), 1);
            flags = ismember(T.Quantity, ["Linear model stable" "Spun out"]);
            T.Display(flags) = pick(T.Value(flags) == 1, "yes", "no");
        end

        function [note, level] = resultNote(~, r)
            note = "";
            level = "success";
            if r.termination == "spun"
                note = sprintf("the car spun at t = %.2f s (sideslip past 30°), so the run stops there", r.t(end));
                if r.params.tyre == "linear"
                    note = note + "; linear tyres have no grip limit, so the forces and accelerations " + ...
                        "near the end are far beyond what real tyres give";
                end
                level = "warning";
            elseif ~r.stable
                note = "above the critical speed: the car is unstable and will spin";
                level = "warning";
            end
        end

        function lin = linearization(obj, p)
            q = obj.engineParams(p);
            G = @(x, u) dlab.sims.handling.dynamics(x, u, q);
            lin = struct("F", @(x) G(x, 0), "X0", zeros(2, 1), ...
                "StateNames", ["v (lateral velocity)" "r (yaw rate)"], ...
                "Reference", sprintf("driving straight at %.4g km/h", p.speed), ...
                "Classify", @(lambda, V) modeNames(lambda, V, p.a + p.b), "Scale", [1 0.1], ...
                "G", G, "U0", 0, "InputNames", "Steering", ...
                "InputUnits", "rad", "H", @(x, u) outputs(x, u, q), ...
                "OutputNames", ["Yaw rate" "Lateral acceleration"], "OutputUnits", ["rad/s" "m/s²"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Double lane change (80 km/h)", "Tab", "Animation", "Time", 2.4);
        end

        function description = about(~)
            description = join([
                "Single-track (bicycle) model at constant forward speed V; v lateral velocity, r yaw rate:"
                "  m (v' + V r) = F_f + F_r          I_z r' = a F_f − b F_r"
                "  α_f = (v + a r)/V − δ             α_r = (v − b r)/V"
                "  Linear tyres F = −C α; saturating F = −μ F_z tanh(C α / (μ F_z)), F_zf = m g b/L, F_zr = m g a/L"
                "  Path: X' = V cos ψ − v sin ψ,  Y' = V sin ψ + v cos ψ,  ψ' = r"
                ""
                "Understeer gradient K = (m/L)(b/C_f − a/C_r) (rad per m/s², shown in deg/g). Steady " + ...
                "turning gives r/δ = V / (L + K V²). K > 0 (understeer): the gain is below the neutral " + ...
                "car's V/L and peaks at the characteristic speed √(L/K). K < 0 (oversteer): the gain " + ...
                "grows without bound at the critical speed √(−L/K), above which the car is unstable " + ...
                "and spins. The run stops when the sideslip passes 30°."
                ""
                "Lateral acceleration a_y = v' + V r is shown in g; angles in degrees. The steering " + ...
                "angle is at the road wheels (about 1/15 of the steering-wheel angle)."
            ], newline);
        end
    end

    methods (Access = private)
        function q = engineParams(obj, p)
            q = struct("m", p.m, "Iz", p.Iz, "a", p.a, "b", p.b, "Cf", p.Cf, "Cr", p.Cr, ...
                "V", p.speed / 3.6, "tyre", char(p.tyre), "mu", p.mu, "g", obj.Gravity, ...
                "tspan", p.tspan, "dt", p.dt);
        end

        function idx = snapshotIndices(obj, r)
            n = numel(r.t);
            idx = unique(round(linspace(1, n, obj.Snapshots)));
        end

        function [bodyF, bodyV, wheelF, wheelV] = carShapes(obj, r, idx)
            % Body rectangles and the four wheels (front ones turned by δ)
            % at samples IDX, as patch faces and vertices.
            a = r.params.a;
            b = r.params.b;
            o = obj.Overhang;
            hw = obj.HalfWidth;
            body = [a + o, -hw; a + o, hw; -b - o, hw; -b - o, -hw];
            wl = obj.WheelHalfLength;
            ww = obj.WheelHalfWidth;
            wheel = [wl -ww; wl ww; -wl ww; -wl -ww];
            hubs = [a, -obj.HalfTrack; a, obj.HalfTrack; -b, -obj.HalfTrack; -b, obj.HalfTrack];
            n = numel(idx);
            bodyV = zeros(4 * n, 2);
            wheelV = zeros(16 * n, 2);
            for j = 1:n
                k = idx(j);
                R = rot(r.psi(k));
                origin = [r.x(k), r.y(k)];
                bodyV(4 * j - 3:4 * j, :) = body * R.' + origin;
                for w = 1:4
                    shape = wheel;
                    if w <= 2
                        shape = wheel * rot(r.delta(k)).';
                    end
                    rows = 16 * (j - 1) + 4 * (w - 1) + (1:4);
                    wheelV(rows, :) = (shape + hubs(w, :)) * R.' + origin;
                end
            end
            bodyF = reshape(1:4 * n, 4, n).';
            wheelF = reshape(1:16 * n, 4, 4 * n).';
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            a.trail = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=2);
            [bodyF, bodyV, wheelF, wheelV] = obj.carShapes(r, 1);
            a.body = patch(ax, Faces=bodyF, Vertices=bodyV, FaceColor=t.series(1), FaceAlpha=0.85, ...
                EdgeColor=t.Text, LineWidth=1.2);
            a.wheels = patch(ax, Faces=wheelF, Vertices=wheelV, FaceColor=t.Text, EdgeColor="none");
            a.velocity = plot(ax, NaN, NaN, Color=t.series(2), LineWidth=2);
            a.velocityHead = patch(ax, NaN, NaN, t.series(2), EdgeColor="none");
            a.frontForce = plot(ax, NaN, NaN, Color=t.series(3), LineWidth=2.5);
            a.frontHead = patch(ax, NaN, NaN, t.series(3), EdgeColor="none");
            a.rearForce = plot(ax, NaN, NaN, Color=t.series(5), LineWidth=2.5);
            a.rearHead = patch(ax, NaN, NaN, t.series(5), EdgeColor="none");
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            a.legend = text(ax, 0.01, 0.02, ["Arrows: velocity (sideslip β against the car's axis);" ...
                "front and rear tyre forces"], Units="normalized", FontSize=t.FontSize.sm, ...
                Color=t.TextMuted, VerticalAlignment="bottom");
            hold(ax, "off");
            a.window = max(10, 0.5 * r.V);
            a.aspect = 0.7;
            a.velocityLength = 5;
            % 3 m for half the weight, or for the largest force if larger
            a.forceScale = 3 / max([abs(r.Ff); abs(r.Fr); r.params.m * obj.Gravity / 2]);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function text = pick(condition, yes, no)
% YES where CONDITION holds, else NO (string arrays).
text = repmat(string(no), size(condition));
text(condition) = yes;
end

function R = rot(angle)
R = [cos(angle) -sin(angle); sin(angle) cos(angle)];
end

function y = outputs(x, u, q)
% Yaw rate (rad/s) and lateral acceleration (m/s²).
[~, f] = dlab.sims.handling.dynamics(x, u, q);
y = [x(2); f.ay];
end

function labels = modeNames(lambda, V, L)
%MODENAMES A yaw–sideslip oscillation (complex pair), a spin divergence
%   (unstable real root), or a yaw or sideslip mode by which motion
%   dominates the eigenvector: r L against v (both as speeds).
labels = strings(numel(lambda), 1);
scale = max(1, max(abs(lambda)));
yawShare = abs(V(2, :)) * L ./ (abs(V(2, :)) * L + abs(V(1, :)));
isReal = abs(imag(lambda(:)')) <= 1e-9 * scale;
for k = 1:numel(lambda)
    if ~isReal(k)
        labels(k) = "Yaw–sideslip oscillation";
    elseif real(lambda(k)) > 0
        labels(k) = "Spin divergence (unstable)";
    else
        others = find(isReal & (1:numel(lambda)) ~= k & real(lambda(:)') <= 0);
        if isempty(others)
            yaw = yawShare(k) >= 0.5;
        else
            yaw = yawShare(k) >= max(yawShare(others));
        end
        if yaw
            labels(k) = "Yaw mode";
        else
            labels(k) = "Sideslip mode";
        end
    end
end
end
