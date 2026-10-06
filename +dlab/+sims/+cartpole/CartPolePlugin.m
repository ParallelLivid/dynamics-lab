classdef CartPolePlugin < dlab.core.TimeDomainPlugin
    %CARTPOLEPLUGIN Balance an inverted pendulum on a cart with PID or LQR
    %   control, within a motor's force limit. Solved by simulateCartPole.

    properties (Constant)
        Id = "cartpole"
        Title = "Inverted Pendulum on a Cart"
        Category = "Controls & Vehicles"
        Summary = "Balance a pole on a moving cart: open-loop instability, PID, LQR, and motor limits."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        SettleBand = 1            % degrees
        CartWidth = 0.4           % m (drawing)
        CartHeight = 0.16
        WheelRadius = 0.05
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isPid = @(p) p.controller == "pid";
            isLqr = @(p) p.controller == "lqr";
            specs = [
                P("M", Label="Cart mass", Units="kg", Default=1, Min=1e-3, Max=1e4, Group="Cart and pole", ...
                    Description="The cart alone, without the pole.")
                P("m", Label="Pole mass", Units="kg", Default=0.1, Min=1e-4, Max=1e4, Group="Cart and pole", ...
                    Description="The whole rod, or the point mass at its end.")
                P("l", Label="Pivot to pole centre of mass", Units="m", Default=0.5, Min=0.01, Max=100, ...
                    Group="Cart and pole", Description="A uniform rod is 2l long (l is half its length); " + ...
                    "a point mass sits l from the pivot.")
                P("poleType", Label="Pole", Type="choice", Default="rod", Choices=["rod" "point"], ...
                    ChoiceLabels=["Uniform rod" "Point mass"], Group="Cart and pole", ...
                    Description="Uniform rod: length 2l, inertia m (2l)²/12 about its centre. Point mass: " + ...
                    "all of m at distance l, on a massless rod.")
                P("b", Label="Cart friction", Units="N·s/m", Default=0.1, Min=0, Max=1e4, Group="Cart and pole", ...
                    Description="Viscous friction on the cart, a force −b ẋ. The pivot turns freely.")
                P("g", Label="Gravity", Units="m/s²", Default=9.81, Min=0.01, Max=100, Group="Cart and pole", ...
                    Description="9.81 m/s² on Earth.")
                P("theta0", Label="Initial tilt", Units="°", Default=5, Min=-89, Max=89, Group="Start", ...
                    Description="From upright; positive leans toward +x.")
                P("thetad0", Label="Initial tilt rate", Units="°/s", Default=0, Min=-1e4, Max=1e4, Group="Start", ...
                    Description="Positive tips the pole toward +x.")
                P("x0", Label="Initial cart position", Units="m", Default=0, Min=-100, Max=100, Group="Start", ...
                    Description="Must be on the track, within ± half the track length.")
                P("xd0", Label="Initial cart speed", Units="m/s", Default=0, Min=-100, Max=100, Group="Start", ...
                    Description="Positive toward +x.")
                P("controller", Label="Controller", Type="choice", Default="lqr", Choices=["none" "pid" "lqr"], ...
                    ChoiceLabels=["None" "PID" "LQR"], Group="Controller", ...
                    Description="PID: on the pole angle, plus a PD loop on the cart (Kx, Kv). LQR: full-state " + ...
                    "feedback F = −K (s − s_ref), with K from the weights below.")
                P("Kp", Label="Angle Kp", Units="N/rad", Default=40, Min=-1e5, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPid, Description="F = Kp θ + Ki ∫θ dt + Kd θ' + Kx (x − x_ref) + Kv ẋ, θ in rad.")
                P("Ki", Label="Angle Ki", Units="N/(rad·s)", Default=0, Min=-1e5, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPid, Description="On ∫θ dt. The linear model ties ∫θ dt to the cart's and " + ...
                    "pole's speeds, so this adds a neutral mode (a pole at 0).")
                P("Kd", Label="Angle Kd", Units="N·s/rad", Default=8, Min=-1e5, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPid, Description="On the tilt rate θ'.")
                P("Kx", Label="Cart Kx", Units="N/m", Default=1, Min=-1e5, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPid, Description="Positive: the cart first moves away to lean the pole " + ...
                    "toward the target.")
                P("Kv", Label="Cart Kv", Units="N·s/m", Default=2, Min=-1e5, Max=1e5, Group="Controller", ...
                    VisibleWhen=isPid, Description="On the cart speed ẋ (positive, like Kx).")
                P("qx", Label="LQR weight: position", Default=10, Min=0, MinInclusive=false, Max=1e8, ...
                    Group="Controller", VisibleWhen=isLqr, Description="Weight on x² (m²) in the cost " + ...
                    "∫ (sᵀ Q s + r F²) dt. Must be positive: nothing else holds the cart in place.")
                P("qxd", Label="LQR weight: cart speed", Default=1, Min=0, Max=1e8, Group="Controller", ...
                    VisibleWhen=isLqr, Description="Weight on ẋ² ((m/s)²).")
                P("qtheta", Label="LQR weight: angle", Default=100, Min=0, Max=1e8, Group="Controller", ...
                    VisibleWhen=isLqr, Description="Weight on θ² (θ in rad).")
                P("qthetad", Label="LQR weight: angle rate", Default=1, Min=0, Max=1e8, Group="Controller", ...
                    VisibleWhen=isLqr, Description="Weight on θ'² ((rad/s)²).")
                P("r", Label="LQR weight: force", Default=0.1, Min=1e-8, Max=1e8, Group="Controller", ...
                    VisibleWhen=isLqr, Description="Weight on F² (N²). Larger r makes control effort " + ...
                    "expensive: gentler forces.")
                P("Fmax", Label="Motor force limit", Units="N", Default=20, Min=0, Max=1e5, Group="Actuator", ...
                    VisibleWhen=@(p) p.controller ~= "none", ...
                    Description="The controller's force is clipped to ±Fmax; the disturbance is not.")
                P("xref", Label="Cart target position", Type="schedule", Units="m", Default=0, Min=-100, Max=100, ...
                    Group="Commands", VisibleWhen=@(p) p.controller ~= "none", ...
                    Description="Where the controller takes the cart (a step moves it); kept on the track.")
                P("disturbance", Label="Disturbance force", Type="schedule", Units="N", Default=0, Min=-1e4, ...
                    Max=1e4, Group="Commands", Description="Pushes the cart, on top of the motor (e.g. a pulse: a kick).")
                P("track", Label="Track length", Units="m", Default=4, Min=0.2, Max=1000, Group="Track", ...
                    Description="The run ends when the cart's centre reaches an end, ± half this length.")
                P("allowFall", Label="Keep going after the pole falls", Type="logical", Default=false, ...
                    Group="Track", Description="Otherwise the run ends when the pole passes horizontal (|θ| = 90°).")
                P("tspan", Label="Duration", Units="s", Default=8, Min=0.01, Max=1e4, Group="Simulation", ...
                    MarksCustom=false, Description="Length of the run; it ends sooner at a fall or an end stop.")
                P("dt", Label="Output step", Units="s", Default=0.01, Min=1e-4, Max=1, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of the samples; the solver's own steps are at " + ...
                    "most 0.01 s.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Falls without control", "Values", struct("controller", "none", "tspan", 3));
            list(end+1) = struct("Name", "PID: balances, cart drifts", "Values", struct( ...
                "controller", "pid", "Kp", 40, "Ki", 1, "Kd", 8, "Kx", 0, "Kv", 0));
            list(end+1) = struct("Name", "PID + cart loop", "Values", struct( ...
                "controller", "pid", "Kp", 40, "Ki", 0, "Kd", 8, "Kx", 1, "Kv", 2));
            list(end+1) = struct("Name", "LQR: balance and return", "Values", struct());
            list(end+1) = struct("Name", "LQR: move the cart 1 m (reference step)", "Values", struct( ...
                "theta0", 0, "xref", S("step", Value=0, Amplitude=1, Start=1)));
            list(end+1) = struct("Name", "Weak motor (saturation)", "Values", struct("theta0", 10, "Fmax", 2));
            list(end+1) = struct("Name", "Kick test (disturbance pulse)", "Values", struct( ...
                "theta0", 0, "disturbance", S("pulse", Value=0, Amplitude=10, Start=1, Width=0.1)));
        end

        function result = solve(obj, p)
            q = obj.engineParams(p);
            q.progressFcn = obj.progressMonitor();
            result = dlab.sims.cartpole.simulateCartPole(q);
            result.params = p;
            result.Fmax = p.Fmax;
        end

        function titles = outputTabs(~, ~)
            titles = ["Angle and position" "Control force" "Phase portrait" "Gains and poles"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            grid = uigridlayout(containers{"Angle and position"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.theta = dlab.ui.axesIn(grid, t, Row=1, Title="Pole angle (from upright)", XLabel="Time (s)", ...
                YLabel="θ (°)");
            obj.Ax.x = dlab.ui.axesIn(grid, t, Row=2, Title="Cart position", XLabel="Time (s)", YLabel="x (m)");
            obj.Ax.force = dlab.ui.axesIn(containers{"Control force"}, t, Title="Motor force", ...
                XLabel="Time (s)", YLabel="Force (N)");
            obj.Ax.phase = dlab.ui.axesIn(containers{"Phase portrait"}, t, Title="Pole phase portrait", ...
                XLabel="θ (°)", YLabel="θ' (°/s)");
            grid = uigridlayout(containers{"Gains and poles"}, [1 2], Padding=0, ColumnWidth={"2x", "1x"}, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.poles = dlab.ui.axesIn(grid, t, Column=1, Title="Poles (s-plane)", XLabel="Real (1/s)", ...
                YLabel="Imaginary (rad/s)");
            obj.Ax.gains = uitextarea(grid, Editable="off", FontName=t.MonoFont, FontSize=t.FontSize.md, ...
                BackgroundColor=t.Surface, FontColor=t.Text);
            obj.Ax.gains.Layout.Column = 2;
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Cart and pole", XLabel="x (m)", YLabel="");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;

            ax = obj.Ax.theta;
            dlab.ui.clearAxes(ax);
            yline(ax, obj.SettleBand * [-1 1], ":", Color=t.TextMuted, HandleVisibility="off");
            plot(ax, r.t, rad2deg(r.theta), Color=t.series(1), LineWidth=1.5);
            hold(ax, "off");

            ax = obj.Ax.x;
            dlab.ui.clearAxes(ax);
            if params.controller ~= "none"
                plot(ax, r.t, r.xref, "--", Color=t.TextMuted, LineWidth=1.2, DisplayName="Target");
            end
            plot(ax, r.t, r.x, Color=t.series(2), LineWidth=1.5, DisplayName="Cart");
            half = params.track / 2;
            yline(ax, half * [-1 1], "-", Color=t.Danger, Alpha=0.5, HandleVisibility="off");    % track ends
            hold(ax, "off");
            ax.YLimitMethod = "padded";          % the track ends inside the plot, not on its frame
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.force;
            dlab.ui.clearAxes(ax);
            if params.controller ~= "none" && isfinite(params.Fmax) && params.Fmax < 1e4
                band = params.Fmax;
                patch(ax, [r.t(1) r.t(end) r.t(end) r.t(1)], [-band -band band band], t.series(3), ...
                    FaceAlpha=0.08, EdgeColor="none", DisplayName="Motor limit ±Fmax");
            end
            plot(ax, r.t, r.Fcommand, "--", Color=t.TextMuted, LineWidth=1.1, DisplayName="Commanded");
            plot(ax, r.t, r.F, Color=t.series(1), LineWidth=1.5, DisplayName="Applied");
            if any(r.disturbance ~= 0)
                plot(ax, r.t, r.disturbance, Color=t.series(4), LineWidth=1.3, DisplayName="Disturbance");
            end
            hold(ax, "off");
            ax.XLimitMethod = "tight";           % no empty strip after a fall
            ax.Title.String = "Motor force";
            if params.controller == "none"
                ax.Title.String = "Motor force (no controller)";
            end
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.phase;
            dlab.ui.clearAxes(ax);
            plot(ax, rad2deg(r.theta), rad2deg(r.thetad), Color=t.series(1), LineWidth=1.3);
            plot(ax, rad2deg(r.theta(1)), rad2deg(r.thetad(1)), "o", MarkerFaceColor=t.series(2), ...
                MarkerEdgeColor=t.Text);
            hold(ax, "off");
            axis(ax, "padded");

            ax = obj.Ax.poles;
            dlab.ui.clearAxes(ax);
            xline(ax, 0, ":", Color=t.TextMuted, HandleVisibility="off");
            yline(ax, 0, ":", Color=t.TextMuted, HandleVisibility="off");
            plot(ax, real(r.openPoles), imag(r.openPoles), "x", Color=t.Danger, MarkerSize=11, LineWidth=2, ...
                DisplayName="Open loop");
            if params.controller ~= "none"
                plot(ax, real(r.closedPoles), imag(r.closedPoles), "o", Color=t.series(3), MarkerSize=9, ...
                    LineWidth=1.8, DisplayName="Closed loop");
            end
            hold(ax, "off");
            axis(ax, "padded");                  % no marker cut in half at the frame
            dlab.ui.legend(ax, t, "Location", "best");
            obj.Ax.gains.Value = gainText(r, params);

            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.theta, run.Result.t, rad2deg(run.Result.theta), run);
                dlab.ui.overlayLine(obj.Ax.x, run.Result.t, run.Result.x, run);
                dlab.ui.overlayLine(obj.Ax.force, run.Result.t, run.Result.F, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = ["theta" "x" "force" "phase" "poles"]
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            obj.Ax.gains.Value = "";
            delete(allchild(obj.Anim.axes));
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "cart")
                return
            end
            a = obj.Anim;
            t = obj.Theme;
            k = dlab.core.frameAt(r.t, simTime);
            x = r.x(k);
            h = obj.CartHeight;
            w = obj.CartWidth;
            rw = obj.WheelRadius;
            [cx, cy] = dlab.ui.Schematic.rect([x, 2 * rw + h / 2], w / 2, h / 2);
            set(a.cart, XData=cx, YData=cy);
            angle = -x / rw;
            [w1x, w1y] = dlab.ui.Schematic.wheel([x - w / 3, rw], rw, 3, angle);
            [w2x, w2y] = dlab.ui.Schematic.wheel([x + w / 3, rw], rw, 3, angle);
            set(a.wheels, XData=[w1x NaN w2x], YData=[w1y NaN w2y]);
            pivot = [x, 2 * rw + h];
            tip = pivot + a.poleLength * [sin(r.theta(k)), cos(r.theta(k))];
            set(a.pole, XData=[pivot(1) tip(1)], YData=[pivot(2) tip(2)]);
            set(a.bob, XData=tip(1), YData=tip(2));
            set(a.pivot, XData=pivot(1), YData=pivot(2));
            F = r.F(k);
            [lx, ly, hx, hy] = deal(NaN);
            if F ~= 0
                % Pushing on the cart's side, the arrow's tip at the cart.
                start = [x - sign(F) * w / 2 - a.forceScale * F, 2 * rw + h / 2];
                [lx, ly, hx, hy] = dlab.ui.Schematic.arrow(start, [a.forceScale * F, 0], 0.06);
            end
            color = t.series(3);
            if r.saturated(k)
                color = t.Warning;
            end
            set(a.force, XData=lx, YData=ly, Color=color);
            set(a.head, XData=hx, YData=hy, FaceColor=color);
            kick = r.disturbance(k);
            if kick ~= 0
                set(a.flash, XData=x + [-1 1 1 -1] * w * 0.7, YData=[0 0 1 1] * (2 * rw + h) * 1.4, Visible="on");
            else
                set(a.flash, Visible="off");
            end
            set(a.target, XData=r.xref(k) * [1 1]);
            a.readout.String = sprintf("t = %.2f s   θ = %+.2f°   F = %+.2f N", simTime, rad2deg(r.theta(k)), F);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.x, r.xd, rad2deg(r.theta), rad2deg(r.thetad), r.Fcommand, r.F, r.disturbance, ...
                r.xref, VariableNames=["time" "x" "cart_speed" "theta" "theta_rate" "force_commanded" ...
                "force_applied" "disturbance" "x_target"]);
            T.Properties.VariableUnits = ["s" "m" "m/s" "deg" "deg/s" "N" "N" "N" "m"];
        end

        function T = summaryTable(obj, r)
            controlled = isControlled(r);
            settled = settlingTime(r, deg2rad(obj.SettleBand));
            unsettled = "— (θ not within 1° at the end)";
            if r.termination == "fell" || (isfield(r, "fallTime") && isfinite(r.fallTime))
                unsettled = "— (the pole fell)";
            elseif r.termination == "endstop"
                unsettled = "— (the cart hit the end stop)";
            end
            weights = gradient(r.t);
            rows = {
                "Settling time (θ within 1°)", settled, "s", displayOr(settled, unsettled)
                "Max |θ|", rad2deg(max(abs(r.theta))), "°", ""
                "Max |F|", max(abs(r.F)), "N", ""
                "Time saturated", 100 * sum(weights(r.saturated)) / max(sum(weights), eps), "%", ""
            };
            if controlled
                rows(end+1, :) = {"Final x error", abs(r.x(end) - r.xref(end)), "m", ""};
            end
            rows = [rows
                {"Largest cart excursion", max(abs(r.x - r.x(1))), "m", ""
                 "Open-loop unstable pole", max(real(r.openPoles)), "1/s", ""}];
            if controlled
                rows(end+1, :) = {"Slowest closed-loop pole", slowest(r.closedPoles), "1/s", ""};
                move = r.xref(end) - r.x(1);
                if abs(move) > 1e-9
                    overshoot = max(0, max(sign(move) * (r.x - r.xref(end)))) / abs(move);
                    rows(end+1, :) = {"Cart overshoot", 100 * overshoot, "%", ""};
                end
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                VariableNames=["Quantity" "Value" "Units" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            notes = strings(1, 0);
            level = "success";
            switch r.termination
                case "fell"
                    notes(end+1) = sprintf("the pole fell at t = %.2f s", r.t(end));
                    level = "warning";
                case "endstop"
                    notes(end+1) = sprintf("the cart hit the end stop at t = %.2f s", r.t(end));
                    level = "warning";
                otherwise
                    if isfield(r, "fallTime") && isfinite(r.fallTime)
                        % allowFall: the run went on after the fall.
                        notes(end+1) = sprintf("the pole fell past horizontal at t = %.2f s", r.fallTime);
                        level = "warning";
                    end
            end
            unstable = slowest(r.closedPoles);
            if isControlled(r) && unstable > 0
                notes(end+1) = sprintf("the linear closed loop is unstable (a pole at +%.3g 1/s)", unstable);
                level = "warning";
            end
            note = strjoin(notes, "; ");
        end

        function lin = linearization(obj, p)
            q = obj.engineParams(p);
            model = struct('M', q.M, 'm', q.m, 'l', q.l, 'I', 0, 'b', q.b, 'g', q.g);
            if q.poleType == "rod"
                model.I = q.m * (2 * q.l)^2 / 12;
            end
            names = ["x" "ẋ" "θ" "θ'"];
            % control(s): the controller's force for state s (with ∫θ last
            % when the PID has an integral); integral(s): the ∫θ rate, or
            % nothing. The input u is a disturbance force on the cart.
            integral = @(s) zeros(0, 1);
            switch p.controller
                case "lqr"
                    [A, B] = dlab.sims.cartpole.linearModel(model);
                    K = dlab.physics.lqr(A, B, diag([q.qx q.qxd q.qtheta q.qthetad]), q.r);
                    control = @(s) -K * s(1:4);
                    reference = "upright at rest, LQR on (force limit ignored)";
                case "pid"
                    control = @(s) q.Kp * s(3) + q.Kd * s(4) + q.Kx * s(1) + q.Kv * s(2);
                    if q.Ki ~= 0
                        control = @(s) q.Kp * s(3) + q.Kd * s(4) + q.Kx * s(1) + q.Kv * s(2) + q.Ki * s(5);
                        integral = @(s) s(3);
                        names(end+1) = "∫θ";
                    end
                    reference = "upright at rest, PID on (force limit ignored)";
                otherwise
                    control = @(~) 0;
                    reference = "upright at rest, no control";
            end
            G = @(s, u) [dlab.sims.cartpole.dynamics(s(1:4), control(s) + u, model); integral(s)];
            lin = struct("F", @(s) G(s, 0), "X0", zeros(numel(names), 1), "StateNames", names, ...
                "Reference", reference, "Classify", @modeNames, "Scale", [], ...
                "G", G, "U0", 0, "InputNames", "Disturbance force", "InputUnits", "N", ...
                "H", @(s, ~) s(1:4), "OutputNames", ["Cart position" "Cart velocity" "Pole angle" "Pole rate"], ...
                "OutputUnits", ["m" "m/s" "rad" "rad/s"]);
            if p.controller ~= "none"
                % Broken where the controller's force enters: inject a force
                % u, and what returns is the force the controller asks for.
                lin.Loop = struct("G", @(s, u) [dlab.sims.cartpole.dynamics(s(1:4), u, model); integral(s)], ...
                    "X0", zeros(numel(names), 1), "U0", 0, "H", @(s, ~) control(s), "Name", "the cart force");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "LQR: move the cart 1 m (reference step)", "Tab", "Animation", "Time", 1.6);
        end

        function description = about(~)
            description = join([
                "θ from upright (positive leaning toward +x), D = (M + m)(I + m l²) − m² l² cos² θ:"
                "  ẍ  = [(I + m l²)(F − b ẋ + m l θ'² sin θ) − m² l² g sin θ cos θ] / D"
                "  θ'' = [(M + m) m g l sin θ − m l cos θ (F − b ẋ + m l θ'² sin θ)] / D"
                ""
                "PID:  F = Kp θ + Ki ∫θ + Kd θ' + Kx (x − x_ref) + Kv ẋ"
                "LQR:  F = −K (s − s_ref), K minimizing ∫ (sᵀ Q s + r F²) dt on the upright linearization"
                ""
                "l is the pivot to the pole's centre of mass (half a uniform rod's length), I the pole's " + ...
                "inertia about its centre (m (2l)²/12 for the rod, 0 for a point mass)."
                ""
                "The motor's force is clipped to ±Fmax; the disturbance is added on top. The run ends " + ...
                "if the cart reaches an end of the track, or when the pole falls past horizontal " + ...
                "(unless the run is set to keep going after a fall)."
            ], newline);
        end
    end

    methods (Access = private)
        function q = engineParams(~, p)
            q = struct("M", p.M, "m", p.m, "l", p.l, "poleType", char(p.poleType), "b", p.b, "g", p.g, ...
                "x0", p.x0, "xd0", p.xd0, "theta0", deg2rad(p.theta0), "thetad0", deg2rad(p.thetad0), ...
                "controller", char(p.controller), "Kp", p.Kp, "Ki", p.Ki, "Kd", p.Kd, "Kx", p.Kx, "Kv", p.Kv, ...
                "qx", p.qx, "qxd", p.qxd, "qtheta", p.qtheta, "qthetad", p.qthetad, "r", p.r, "Fmax", p.Fmax, ...
                "xref", dlab.core.Schedule.toFunction(p.xref, [-p.track p.track] / 2), ...
                "disturbance", dlab.core.Schedule.toFunction(p.disturbance), "track", p.track, ...
                "allowFall", logical(p.allowFall), "tspan", p.tspan, "dt", p.dt);
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            half = params.track / 2;
            [gx, gy] = dlab.ui.Schematic.hatch([-half - 0.1, 0], [half + 0.1, 0], 30, 0.05);
            plot(ax, gx, gy, Color=t.TextMuted, LineWidth=1);
            stop = 2 * obj.WheelRadius + obj.CartHeight;
            plot(ax, [-half -half NaN half half] + [-1 -1 NaN 1 1] * obj.CartWidth / 2, ...
                [0 stop NaN 0 stop], Color=t.Danger, LineWidth=3);
            a.target = plot(ax, [0 0], [-0.08 -0.02], Color=t.series(4), LineWidth=3);
            a.flash = patch(ax, NaN, NaN, t.series(4), FaceAlpha=0.25, EdgeColor="none", Visible="off");
            a.cart = patch(ax, NaN, NaN, t.series(2), EdgeColor=t.Text, LineWidth=1.5);
            a.wheels = plot(ax, NaN, NaN, Color=t.Text, LineWidth=1.5);
            a.poleLength = 2 * params.l;
            if params.poleType == "point"
                a.poleLength = params.l;
            end
            a.pole = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=4);
            bobSize = 6;
            if params.poleType == "point"
                bobSize = 16;
            end
            a.bob = plot(ax, NaN, NaN, "o", MarkerSize=bobSize, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            a.pivot = plot(ax, NaN, NaN, "o", MarkerSize=6, MarkerFaceColor=t.Text, MarkerEdgeColor=t.Text);
            a.force = plot(ax, NaN, NaN, LineWidth=2.5);
            a.head = patch(ax, NaN, NaN, t.series(3), EdgeColor="none");
            a.forceScale = 0.5 / max([max(abs(r.F)), 1]);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            top = stop + a.poleLength + 0.2;
            set(ax, XLim=[-half - 0.4, half + 0.4], YLim=[-max(0.4, 0.3 * top), top]);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function tf = isControlled(r)
% True unless the run had no controller (older results have no params).
tf = ~isfield(r, "params") || r.params.controller ~= "none";
end

function v = slowest(poles)
% The largest real part, with rounding noise around a pole at 0 read as 0.
v = max(real(poles));
if abs(v) < 1e-9 * max(1, max(abs(poles)))
    v = 0;
end
end

function text = displayOr(value, fallback)
% "" (show the number) when VALUE is finite, else FALLBACK.
text = "";
if ~isfinite(value)
    text = fallback;
end
end

function t = settlingTime(r, band)
% When θ last left the band (NaN unless the run finished inside it).
t = NaN;
if r.termination ~= "completed" || abs(r.theta(end)) > band
    return
end
outside = find(abs(r.theta) > band, 1, "last");
if isempty(outside)
    t = 0;
else
    t = r.t(min(outside + 1, numel(r.t)));
end
end

function text = gainText(r, params)
switch params.controller
    case "lqr"
        lines = ["Controller: LQR"; "F = −K (s − s_ref)"; "s = [x ẋ θ θ']"];
        lines(end+1) = "K = [" + strjoin(compose("%.4g", r.K), "  ") + "]";
    case "pid"
        lines = ["Controller: PID"; "F = Kp θ + Ki ∫θ + Kd θ'"; "    + Kx (x − x_ref) + Kv ẋ"];
        lines(end+1) = sprintf("Kp = %.4g, Ki = %.4g", params.Kp, params.Ki);
        lines(end+1) = sprintf("Kd = %.4g", params.Kd);
        lines(end+1) = sprintf("Kx = %.4g, Kv = %.4g", params.Kx, params.Kv);
    otherwise
        lines = "Controller: none";
end
lines = lines(:)';
lines(end+1) = "";
lines(end+1) = "Open-loop poles:";
lines = [lines(:); compose("  %s", poleStrings(r.openPoles))];    % a column from here on
if params.controller ~= "none"
    lines(end+1) = "Closed-loop poles:";
    lines = [lines; compose("  %s", poleStrings(r.closedPoles))];
end
text = lines(:);
end

function s = poleStrings(p)
s = strings(numel(p), 1);
tiny = 1e-9 * max(1, max(abs(p)));      % rounding noise around a pole at 0
for k = 1:numel(p)
    if abs(p(k)) < tiny
        s(k) = "0";
    elseif abs(imag(p(k))) < 1e-9
        s(k) = sprintf("%.4g", real(p(k)));
    else
        signs = ["+" "−"];
        s(k) = sprintf("%.4g %s %.4gi", real(p(k)), signs(1 + (imag(p(k)) < 0)), abs(imag(p(k))));
    end
end
end

function labels = modeNames(lambda, ~)
%MODENAMES Topple, cart drift, oscillation, or settling.
labels = strings(numel(lambda), 1);
scale = max(1, max(abs(lambda)));
for k = 1:numel(lambda)
    if abs(lambda(k)) < 1e-7 * scale
        labels(k) = "Cart drift (neutral)";
    elseif abs(imag(lambda(k))) > 1e-9 * scale
        labels(k) = "Oscillation";
    elseif real(lambda(k)) > 0
        labels(k) = "Topple (unstable)";
    else
        labels(k) = "Settling";
    end
end
end
