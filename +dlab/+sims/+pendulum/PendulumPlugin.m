classdef PendulumPlugin < dlab.core.TimeDomainPlugin
    %PENDULUMPLUGIN Damped nonlinear pendulum, single or double.
    %   Reference implementation of a Dynamics Lab plugin: the engines
    %   (pendulum_solve, double_pendulum_solve) know nothing of the app and
    %   this class adapts them to the shell. The double pendulum adds the
    %   tools of chaos: a twin started a hair apart, its divergence and a
    %   Lyapunov exponent, and a Poincaré section.

    properties (Constant)
        Id = "pendulum"
        Title = "Pendulum"
        Category = "Mechanics"
        Summary = "Single and double pendulums: phase portraits, energy, and chaos."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        MaxPlotPoints = 5000        % plots are downsampled; animation uses every sample
        TrailSeconds = 3
        BobRadius = 0.06            % fraction of the (total) length
        ViewMargin = 1.25           % axes half-width as a multiple of the (total) length
        SingleTabs = ["Angle & velocity" "Phase portrait" "Energy"]
        DoubleTabs = ["Angles" "Phase portrait" "Energy" "Divergence" "Poincaré section"]
    end

    properties (Access = private)
        Axes struct = struct()
        Plots struct = struct()
        Anim struct = struct()
        Result
        Linear struct = struct("t", [], "theta", [])   % small-angle solution being shown (columns per angle)
        Length (1,1) double = 1
        Lengths (1,2) double = [1 1]
        TrailSamples (1,1) double = 150
        Circle (2,:) double
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isDouble = @(p) p.model == "double";
            specs = [
                P("model", Label="Pendulum", Type="choice", Default="single", Choices=["single" "double"], ...
                    ChoiceLabels=["Single" "Double"], Group="Model", ...
                    Description="A double pendulum hangs a second rod and bob from the first: a classic " + ...
                    "chaotic system.")
                P("L", Label="Length", Units="m", Default=1, Min=0.1, Max=10, Group="Pendulum", ...
                    Description="Distance from the pivot to the centre of the bob (the upper rod of a double pendulum).")
                P("m", Label="Bob mass", Units="kg", Default=1, Min=0.01, Max=100, Group="Pendulum", ...
                    Description="Mass of the (upper) bob.")
                P("L2", Label="Lower length", Units="m", Default=1, Min=0.1, Max=10, Group="Pendulum", ...
                    VisibleWhen=isDouble, Description="Lower rod, from the upper bob to the lower bob.")
                P("m2", Label="Lower bob mass", Units="kg", Default=1, Min=0.001, Max=100, Group="Pendulum", ...
                    VisibleWhen=isDouble, ...
                    Description="Mass of the lower bob.")
                P("b", Label="Damping", Units="N·m·s", Default=0.1, Min=0, Max=50, Group="Pendulum", ...
                    Description="Rotational damping coefficient; torque = −b·ω (at both joints of a double pendulum).")
                P("theta0", Label="Initial angle", Units="deg", Default=30, Min=-180, Max=180, ...
                    Group="Initial conditions", Description="Measured from straight down (the upper rod's angle).")
                P("omega0", Label="Initial angular velocity", Units="rad/s", Default=0, Min=-50, Max=50, ...
                    Group="Initial conditions", ...
                    Description="Angular velocity of the (upper) rod at the start.")
                P("theta20", Label="Lower initial angle", Units="deg", Default=0, Min=-180, Max=180, ...
                    Group="Initial conditions", VisibleWhen=isDouble, ...
                    Description="The lower rod's angle, also measured from straight down.")
                P("omega20", Label="Lower angular velocity", Units="rad/s", Default=0, Min=-50, Max=50, ...
                    Group="Initial conditions", VisibleWhen=isDouble, ...
                    Description="Angular velocity of the lower rod at the start.")
                P("twin", Label="Run a twin pendulum", Type="logical", Default=true, Group="Chaos", ...
                    VisibleWhen=isDouble, Description="A second double pendulum whose lower angle starts " + ...
                    "a tiny amount higher, drawn faintly, to show sensitive dependence on initial conditions.")
                P("delta", Label="Twin's head start", Units="deg", Default=1e-3, Min=1e-9, Max=10, Group="Chaos", ...
                    VisibleWhen=@(p) isDouble(p) && p.twin, DisplayFormat="%.3g", ...
                    Description="How much higher the twin's lower angle starts: the tiny difference that chaos magnifies.")
                P("lyapunov", Label="Estimate the Lyapunov exponent", Type="logical", Default=false, Group="Chaos", ...
                    VisibleWhen=isDouble, Description="Benettin's method: how fast nearby starts separate " + ...
                    "(1/s; above zero means chaos). Roughly doubles the solve time.")
                P("g", Label="Gravity", Units="m/s²", Default=9.81, Min=0.1, Max=30, Group="Environment", ...
                    Description="Gravitational acceleration: Earth 9.81, Moon 1.62, Mars 3.72 m/s².")
                P("tspan", Label="Duration", Units="s", Default=15, Min=1, Max=300, Group="Simulation", ...
                    MarksCustom=false, ...
                    Description="How long to simulate.")
                P("dt", Label="Output step", Units="s", Default=0.02, Min=0.001, Max=1, Group="Simulation", ...
                    Description="Spacing of the saved samples. The solver chooses its own internal steps.")
                P("showLinear", Label="Show small-angle model", Type="logical", Default=true, Group="Display", ...
                    Display=true, Description="Overlay the linear model (sin θ ≈ θ) from the same start, " + ...
                    "to see where the approximation breaks down.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Small swing (5°)", "Values", struct("theta0", 5, "b", 0));
            list(end+1) = struct("Name", "Large swing (170°)", "Values", struct("theta0", 170, "b", 0.05));
            list(end+1) = struct("Name", "Undamped", "Values", struct("b", 0));
            list(end+1) = struct("Name", "Heavily damped", "Values", struct("b", 3));
            list(end+1) = struct("Name", "Over the top", ...
                "Values", struct("theta0", 0, "omega0", 7, "b", 0.1));
            list(end+1) = struct("Name", "Double: gentle (normal modes)", "Values", struct( ...
                "model", "double", "theta0", 5, "theta20", 5, "b", 0, "tspan", 20));
            list(end+1) = struct("Name", "Double: chaotic", "Values", struct( ...
                "model", "double", "theta0", 120, "theta20", -20, "b", 0, "tspan", 30));
            list(end+1) = struct("Name", "Double: butterfly effect", "Values", struct( ...
                "model", "double", "theta0", 150, "theta20", 150, "b", 0, "twin", true, "delta", 1e-6, "tspan", 20));
            list(end+1) = struct("Name", "Double: Poincaré section", "Values", struct( ...
                "model", "double", "theta0", 90, "theta20", 0, "b", 0, "twin", false, "tspan", 60));
        end

        function result = solve(obj, p)
            if p.model == "double"
                q = struct("L1", p.L, "L2", p.L2, "m1", p.m, "m2", p.m2, "b", p.b, "g", p.g, ...
                    "theta1", p.theta0, "theta2", p.theta20, "omega1", p.omega0, "omega2", p.omega20, ...
                    "tspan", p.tspan, "dt", p.dt, "twin", p.twin, "delta", p.delta, "lyapunov", p.lyapunov);
                [result, message] = dlab.sims.pendulum.double_pendulum_solve(q, obj.progressMonitor());
            else
                [result, message] = dlab.sims.pendulum.pendulum_solve( ...
                    p.L, p.m, p.b, p.theta0, p.omega0, p.g, p.tspan, p.dt, obj.progressMonitor());
            end
            if ~isempty(message)
                error("dlab:invalidParameter", "%s", message);
            end
            result.model = p.model;
            result.params = p;          % the small-angle comparison needs the inputs
        end

        function titles = outputTabs(obj, params)
            titles = obj.SingleTabs;
            if params.model == "double"
                titles = obj.DoubleTabs;
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            obj.Axes = struct();
            obj.Plots = struct();
            if isKey(containers, "Angles")
                obj.buildDoubleOutputs(containers, theme);
            else
                obj.buildSingleOutputs(containers, theme);
            end
        end

        function buildAnimation(obj, parent, theme)
            t = theme;
            ax = dlab.ui.axesIn(parent, t, Title="Pendulum");
            set(ax, XTickLabel={}, YTickLabel={}, DataAspectRatio=[1 1 1], Box="off");
            disableDefaultInteractivity(ax);
            ax.Toolbar.Visible = "off";
            hold(ax, "on");
            a.ceiling = patch(ax, NaN, NaN, t.Surface, EdgeColor=t.Border);
            a.ghost = line(ax, NaN, NaN, Color=[t.Accent 0.15], LineWidth=1.2);
            a.pivot = line(ax, 0, 0, LineStyle="none", Marker="o", MarkerSize=7, ...
                MarkerFaceColor=t.TextMuted, MarkerEdgeColor=t.Border);
            a.linRod = line(ax, NaN, NaN, Color=[t.series(5) 0.55], LineWidth=1.5, LineStyle="--");
            a.linBob = patch(ax, NaN, NaN, t.series(5), FaceAlpha=0.35, EdgeColor="none");
            a.twinRods = line(ax, NaN, NaN, Color=[t.series(2) 0.45], LineWidth=1.5);
            a.twinBob = patch(ax, NaN, NaN, t.series(2), FaceAlpha=0.45, EdgeColor="none");
            a.trail = line(ax, NaN, NaN, Color=[t.Accent 0.75], LineWidth=2);
            a.rod = line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=2.5);
            a.rod2 = line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=2.4);
            a.bob = patch(ax, NaN, NaN, t.Accent, EdgeColor=t.AxesBackground);
            a.bob2 = patch(ax, NaN, NaN, t.Accent, EdgeColor=t.AxesBackground);
            a.time = text(ax, NaN, NaN, "", FontName=t.MonoFont, FontSize=t.scaled(11), Color=t.TextMuted);
            a.angle = text(ax, NaN, NaN, "", FontName=t.MonoFont, FontSize=t.scaled(12), ...
                Color=t.Accent, FontWeight="bold");
            hold(ax, "off");
            a.axes = ax;
            obj.Anim = a;
            obj.setAnimationVisible(false);
            phi = linspace(0, 2*pi, 60);
            obj.Circle = [cos(phi); sin(phi)];
        end

        function showResult(obj, result, params)
            obj.Result = result;
            if isDoubleResult(result)
                obj.showDouble(result, params);
            else
                obj.showSingle(result, params);
            end
        end

        function overlayRuns(obj, runs)
            showingDouble = isfield(obj.Axes, "angles");
            for run = runs(:)'
                r = run.Result;
                if isDoubleResult(r) ~= showingDouble
                    continue                % kept runs of the other model don't fit these axes
                end
                k = sampleIndices(numel(r.t), obj.MaxPlotPoints);
                if showingDouble
                    dlab.ui.overlayLine(obj.Axes.angles, r.t(k), r.theta2Deg(k), run);
                    dlab.ui.overlayLine(obj.Axes.phase, r.theta2Deg(k), r.omega2(k), run);
                    dlab.ui.overlayLine(obj.Axes.energy, r.t(k), r.E(k), run);
                    dlab.ui.overlayLine(obj.Anim.axes, r.x2(k), r.y2(k), run);
                else
                    dlab.ui.overlayLine(obj.Axes.theta, r.t(k), r.thetaDeg(k), run);
                    dlab.ui.overlayLine(obj.Axes.omega, r.t(k), r.omega(k), run);
                    dlab.ui.overlayLine(obj.Axes.phase, r.thetaDeg(k), r.omega(k), run);
                    dlab.ui.overlayLine(obj.Axes.energy, r.t(k), r.E(k), run);
                    dlab.ui.overlayLine(obj.Anim.axes, r.bx(k), r.by(k), run);
                end
            end
        end

        function clearResult(obj)
            obj.Result = [];
            obj.Linear = struct("t", [], "theta", []);
            for name = string(fieldnames(obj.Plots))'
                h = obj.Plots.(name);
                if isempty(h) || ~all(isgraphics(h))
                    continue
                end
                if name == "phase"
                    delete(h);
                    obj.Plots.phase = gobjects(0);
                else
                    set(h, XData=NaN, YData=NaN);
                end
            end
            obj.setAnimationVisible(false);
        end

        function t = timeVector(~, result)
            t = result.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r)
                return
            end
            % Interpolate the angles between samples so motion stays smooth
            % whatever the output step (rod lengths stay exact).
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            between = @(v) v(k) + fraction * (v(next) - v(k));
            a = obj.Anim;
            first = max(1, k - obj.TrailSamples + 1);
            a.time.String = sprintf("t = %.2f s", simTime);

            if isDoubleResult(r)
                [L1, L2] = deal(obj.Lengths(1), obj.Lengths(2));
                radius = obj.BobRadius * (L1 + L2) / 2;
                theta1 = between(r.theta1);
                theta2 = between(r.theta2);
                [x1, y1, x2, y2] = bobs(L1, L2, theta1, theta2);
                set(a.rod, XData=[0 x1], YData=[0 y1]);
                set(a.rod2, XData=[x1 x2], YData=[y1 y2]);
                obj.placeBob(a.bob, x1, y1, radius);
                obj.placeBob(a.bob2, x2, y2, radius);
                set(a.trail, XData=[r.x2(first:k); x2], YData=[r.y2(first:k); y2]);
                if ~isempty(r.twin)
                    [u1, v1, u2, v2] = bobs(L1, L2, between(r.twin.theta1), between(r.twin.theta2));
                    set(a.twinRods, XData=[0 u1 u2], YData=[0 v1 v2]);
                    obj.placeBob(a.twinBob, u2, v2, 0.8 * radius);
                end
                a.angle.String = sprintf("θ₁ = %.1f°  θ₂ = %.1f°", rad2deg(theta1), rad2deg(theta2));
                if ~isempty(obj.Linear.t)
                    lin = interp1(obj.Linear.t, obj.Linear.theta, simTime, "linear", "extrap");
                    [l1, m1, l2, m2] = bobs(L1, L2, lin(1), lin(2));
                    set(a.linRod, XData=[0 l1 l2], YData=[0 m1 m2]);
                    obj.placeBob(a.linBob, l2, m2, radius);
                end
                return
            end

            theta = between(r.theta);
            x = obj.Length * sin(theta);
            y = -obj.Length * cos(theta);
            radius = obj.BobRadius * obj.Length;
            set(a.rod, XData=[0 x], YData=[0 y]);
            obj.placeBob(a.bob, x, y, radius);
            set(a.trail, XData=[r.bx(first:k); x], YData=[r.by(first:k); y]);
            a.angle.String = sprintf("θ = %.1f°", rad2deg(theta));

            % Ghost of the small-angle model, when shown.
            if ~isempty(obj.Linear.t)
                thetaLin = interp1(obj.Linear.t, obj.Linear.theta(:, 1), simTime, "linear", obj.Linear.theta(end, 1));
                xl = obj.Length * sin(thetaLin);
                yl = -obj.Length * cos(thetaLin);
                set(a.linRod, XData=[0 xl], YData=[0 yl]);
                obj.placeBob(a.linBob, xl, yl, radius);
            end
        end

        function T = exportTable(~, result)
            if isDoubleResult(result)
                T = table(result.t, result.theta1Deg, result.theta2Deg, result.omega1, result.omega2, ...
                    result.KE, result.PE, result.E, VariableNames=["time" "angle1" "angle2" ...
                    "angular_velocity1" "angular_velocity2" "kinetic_energy" "potential_energy" "total_energy"]);
                T.Properties.VariableUnits = ["s" "deg" "deg" "rad/s" "rad/s" "J" "J" "J"];
                if ~isempty(result.twin)
                    T.twin_angle2 = rad2deg(result.twin.theta2);
                    T.separation = result.separation;
                    T.Properties.VariableUnits = ["s" "deg" "deg" "rad/s" "rad/s" "J" "J" "J" "deg" ""];
                end
                return
            end
            T = table(result.t, result.thetaDeg, result.omega, result.KE, result.PE, result.E, ...
                VariableNames=["time" "angle" "angular_velocity" "kinetic_energy" ...
                    "potential_energy" "total_energy"]);
            T.Properties.VariableUnits = ["s" "deg" "rad/s" "J" "J" "J"];
        end

        function T = summaryTable(~, result)
            if isDoubleResult(result)
                T = doubleSummary(result);
                return
            end
            E0 = result.E(1);
            lost = NaN;
            if E0 > 0
                lost = 100 * (E0 - result.E(end)) / E0;
            end
            measured = measuredPeriod(result.t, result.theta);
            % Times the bob passes straight over the top (θ through an odd
            % multiple of 180°); the angle keeps counting through full turns.
            turns = nnz(diff(floor((result.thetaDeg + 180) / 360)));
            T = table( ...
                ["Peak angle"; "Final angle"; "Period (measured)"; "Passes over the top"; "Initial energy"; ...
                 "Final energy"; "Energy dissipated"; "Samples"], ...
                [max(abs(result.thetaDeg)); result.thetaDeg(end); measured; turns; ...
                 E0; result.E(end); lost; numel(result.t)], ...
                ["deg"; "deg"; "s"; ""; "J"; "J"; "%"; ""], ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Format = repmat("", height(T), 1);
            T.Display = repmat("", height(T), 1);
            if isnan(measured)
                T.Display(T.Quantity == "Period (measured)") = "— (no complete swings)";
            end
            if isfield(result, "params")
                extra = smallAngleRows(result, measured);
                extra.Format = repmat("", height(extra), 1);
                extra.Display = repmat("", height(extra), 1);
                T = [T; extra];
            end
        end

        function D = distributions(~, result)
            % Poincaré points (θ₁ passing 0 forwards): sweeping the start
            % shows the move from order to chaos.
            D = table(strings(0, 1), cell(0, 1), strings(0, 1), VariableNames=["Quantity" "Values" "Units"]);
            if isDoubleResult(result)
                D = table(["Poincaré θ₂"; "Poincaré ω₂"], ...
                    {rad2deg(result.poincare(:, 1)); result.poincare(:, 2)}, ["deg"; "rad/s"], ...
                    VariableNames=["Quantity" "Values" "Units"]);
            end
        end

        function lin = linearization(~, p)
            if p.model == "double"
                % About hanging straight down: two normal modes.
                c = struct("L1", p.L, "L2", p.L2, "m1", p.m, "m2", p.m2, "b", p.b, "g", p.g);
                lin = struct("F", @(x) dlab.sims.pendulum.double_pendulum_rhs(x, c), "X0", zeros(4, 1), ...
                    "StateNames", ["θ₁" "θ₂" "ω₁" "ω₂"], "Reference", "both rods hanging straight down", ...
                    "Classify", @doublePendulumModes, "Scale", []);
                return
            end
            % About the nearest equilibrium: hanging, or balanced upside
            % down when the start is above the horizontal.
            damping = p.b / (p.m * p.L^2);
            stiffness = p.g / p.L;
            if abs(p.theta0) > 90
                x0 = [pi; 0];
                reference = "the upside-down balance point (θ = 180°)";
            else
                x0 = [0; 0];
                reference = "hanging straight down (θ = 0)";
            end
            lin = struct("F", @(x) [x(2); -damping * x(2) - stiffness * sin(x(1))], "X0", x0, ...
                "StateNames", ["θ" "ω"], "Reference", reference, "Classify", @pendulumModes, "Scale", []);
        end

        function scene = showcase(~)
            scene = struct("Preset", "", "Tab", "Phase portrait", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Damped nonlinear pendulum, single or double."
                ""
                "Single:  θ'' + b/(m L²) θ' + g/L sin θ = 0"
                ""
                "L is the length, m the bob mass, b the rotational damping, and g gravity. " + ...
                "θ is measured from straight down. ode45 is used for ordinary cases and " + ...
                "ode15s for strongly damped (stiff) ones. Potential energy is zero at the " + ...
                "lowest point."
                ""
                "Double: two point masses on light rods, from Lagrange's equations, with damping " + ...
                "b at both joints. Its motion is chaotic for large swings: a twin started a " + ...
                "tiny amount apart soon does something completely different. The Divergence tab " + ...
                "shows how fast (the Lyapunov exponent); the Poincaré section samples the lower " + ...
                "rod each time the upper rod swings forward through the vertical."
                ""
                "The dashed small-angle model replaces sin θ by θ (the linear model on the Modes tab)."
            ], newline);
        end
    end

    methods (Access = private)
        function buildSingleOutputs(obj, containers, theme)
            t = theme;
            grid = uigridlayout(containers{"Angle & velocity"}, [2 1], Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Axes.theta = dlab.ui.axesIn(grid, t, Row=1, Title="Angular displacement", ...
                XLabel="Time (s)", YLabel="θ (deg)");
            obj.Axes.omega = dlab.ui.axesIn(grid, t, Row=2, Title="Angular velocity", ...
                XLabel="Time (s)", YLabel="ω (rad/s)");
            for name = ["theta" "omega"]
                yline(obj.Axes.(name), 0, LineStyle="--", Color=t.Grid, HandleVisibility="off");
            end
            obj.Plots.theta = line(obj.Axes.theta, NaN, NaN, Color=t.series(1), LineWidth=1.6);
            obj.Plots.omega = line(obj.Axes.omega, NaN, NaN, Color=t.series(2), LineWidth=1.6);
            obj.Plots.thetaLin = line(obj.Axes.theta, NaN, NaN, Color=t.series(5), LineWidth=1.3, LineStyle="--");
            obj.Plots.omegaLin = line(obj.Axes.omega, NaN, NaN, Color=t.series(5), LineWidth=1.3, LineStyle="--");
            dlab.ui.legend(obj.Axes.theta, t, [obj.Plots.theta obj.Plots.thetaLin], ...
                {"Simulated", "Small-angle model"}, "Location", "northeast");

            obj.Axes.phase = dlab.ui.axesIn(containers{"Phase portrait"}, t, ...
                Title="Phase portrait (θ vs ω)", XLabel="θ (deg)", YLabel="ω (rad/s)");
            faded = 0.55 * t.Grid + 0.45 * t.series(3);    % early samples stay visible
            colormap(obj.Axes.phase, colorRamp(faded, t.series(3)));
            obj.Plots.phase = gobjects(0);
            hold(obj.Axes.phase, "on");
            obj.Plots.start = line(obj.Axes.phase, NaN, NaN, LineStyle="none", Marker="o", ...
                MarkerSize=9, MarkerFaceColor=t.series(2), MarkerEdgeColor="none", DisplayName="Start");
            obj.Plots.finish = line(obj.Axes.phase, NaN, NaN, LineStyle="none", Marker="s", ...
                MarkerSize=8, MarkerFaceColor=t.Danger, MarkerEdgeColor="none", DisplayName="End");
            obj.Plots.phaseLin = line(obj.Axes.phase, NaN, NaN, Color=t.series(5), LineWidth=1.2, ...
                LineStyle="--", HandleVisibility="off");
            hold(obj.Axes.phase, "off");
            dlab.ui.legend(obj.Axes.phase, t, [obj.Plots.start obj.Plots.finish], ...
                {"Start", "End"}, "Location", "northeast");

            obj.buildEnergyAxes(containers{"Energy"}, t);
        end

        function buildDoubleOutputs(obj, containers, theme)
            t = theme;
            obj.Axes.angles = dlab.ui.axesIn(containers{"Angles"}, t, Title="Rod angles", ...
                XLabel="Time (s)", YLabel="Angle (deg)");
            yline(obj.Axes.angles, 0, LineStyle="--", Color=t.Grid, HandleVisibility="off");
            obj.Plots.theta1 = line(obj.Axes.angles, NaN, NaN, Color=t.series(1), LineWidth=1.5);
            obj.Plots.theta2 = line(obj.Axes.angles, NaN, NaN, Color=t.series(2), LineWidth=1.5);
            obj.Plots.twin2 = line(obj.Axes.angles, NaN, NaN, Color=[t.series(2) 0.4], LineWidth=1.2);
            obj.Plots.theta1Lin = line(obj.Axes.angles, NaN, NaN, Color=t.series(5), LineWidth=1.2, LineStyle="--");
            obj.Plots.theta2Lin = line(obj.Axes.angles, NaN, NaN, Color=t.series(7), LineWidth=1.2, LineStyle="--");
            dlab.ui.legend(obj.Axes.angles, t, ...
                [obj.Plots.theta1 obj.Plots.theta2 obj.Plots.twin2 obj.Plots.theta1Lin obj.Plots.theta2Lin], ...
                {"θ₁ upper", "θ₂ lower", "θ₂ twin", "θ₁ small-angle", "θ₂ small-angle"}, "Location", "northeast");

            obj.Axes.phase = dlab.ui.axesIn(containers{"Phase portrait"}, t, ...
                Title="Phase portrait (θ₂ vs ω₂)", XLabel="θ₂ (deg)", YLabel="ω₂ (rad/s)");
            obj.Plots.phase2 = line(obj.Axes.phase, NaN, NaN, Color=t.series(3), LineWidth=1.1);
            obj.Plots.phase1 = line(obj.Axes.phase, NaN, NaN, Color=[t.series(1) 0.5], LineWidth=1);
            dlab.ui.legend(obj.Axes.phase, t, [obj.Plots.phase2 obj.Plots.phase1], ...
                {"Lower rod (θ₂, ω₂)", "Upper rod (θ₁, ω₁)"}, "Location", "northeast");

            obj.buildEnergyAxes(containers{"Energy"}, t);

            grid = uigridlayout(containers{"Divergence"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Axes.divergence = dlab.ui.axesIn(grid, t, Row=1, Title="Distance from the twin", ...
                XLabel="Time (s)", YLabel="log₁₀ separation");
            obj.Plots.separation = line(obj.Axes.divergence, NaN, NaN, Color=t.series(4), LineWidth=1.5);
            obj.Plots.growth = line(obj.Axes.divergence, NaN, NaN, Color=t.Text, LineStyle="--", LineWidth=1.2);
            dlab.ui.legend(obj.Axes.divergence, t, [obj.Plots.separation obj.Plots.growth], ...
                {"Phase-space separation", "Exponential growth fit"}, "Location", "southeast");
            obj.Axes.lyapunov = dlab.ui.axesIn(grid, t, Row=2, Title="Lyapunov exponent estimate", ...
                XLabel="Time (s)", YLabel="λ (1/s)");
            yline(obj.Axes.lyapunov, 0, LineStyle="--", Color=t.Grid, HandleVisibility="off");
            obj.Plots.lyapunov = line(obj.Axes.lyapunov, NaN, NaN, Color=t.series(5), LineWidth=1.5);

            obj.Axes.poincare = dlab.ui.axesIn(containers{"Poincaré section"}, t, ...
                Title="Poincaré section (each time θ₁ passes 0 moving forward)", ...
                XLabel="θ₂ (deg)", YLabel="ω₂ (rad/s)");
            obj.Plots.poincare = line(obj.Axes.poincare, NaN, NaN, LineStyle="none", Marker=".", ...
                MarkerSize=10, Color=t.series(1));
        end

        function buildEnergyAxes(obj, container, t)
            obj.Axes.energy = dlab.ui.axesIn(container, t, ...
                Title="Mechanical energy", XLabel="Time (s)", YLabel="Energy (J)");
            obj.Plots.kinetic = line(obj.Axes.energy, NaN, NaN, Color=t.series(1), ...
                LineWidth=1.4, DisplayName="Kinetic");
            obj.Plots.potential = line(obj.Axes.energy, NaN, NaN, Color=t.series(2), ...
                LineWidth=1.4, DisplayName="Potential");
            obj.Plots.total = line(obj.Axes.energy, NaN, NaN, Color=t.Text, ...
                LineWidth=1.8, LineStyle="--", DisplayName="Total");
            dlab.ui.legend(obj.Axes.energy, t, "Location", "northeast");
        end

        function showSingle(obj, result, params)
            k = sampleIndices(numel(result.t), obj.MaxPlotPoints);
            t = result.t(k);

            set(obj.Plots.theta, XData=t, YData=result.thetaDeg(k));
            set(obj.Plots.omega, XData=t, YData=result.omega(k));

            delete(obj.Plots.phase);
            hold(obj.Axes.phase, "on");
            progress = linspace(0, 1, numel(k))';
            obj.Plots.phase = patch(obj.Axes.phase, [result.thetaDeg(k); NaN], [result.omega(k); NaN], ...
                [progress; NaN], EdgeColor="interp", FaceColor="none", LineWidth=1.4, ...
                HandleVisibility="off");
            hold(obj.Axes.phase, "off");
            uistack(obj.Plots.phase, "bottom");
            set(obj.Plots.start, XData=result.thetaDeg(1), YData=result.omega(1));
            set(obj.Plots.finish, XData=result.thetaDeg(end), YData=result.omega(end));
            obj.showEnergy(result, k);

            % Animation geometry for this run.
            obj.Length = params.L;
            limit = obj.ViewMargin * params.L;
            obj.frameAnimation(limit);
            a = obj.Anim;
            set(a.ghost, XData=result.bx(k), YData=result.by(k));
            obj.showLinearSingle(result, params, k);
            obj.TrailSamples = min(numel(result.t), max(60, round(obj.TrailSeconds / params.dt)));
            obj.setAnimationVisible(true);
            set([a.rod2 a.bob2 a.twinRods a.twinBob], Visible="off");
            % A ceiling only when the bob stays below the pivot; a pendulum
            % that swings higher turns on an axle.
            a.ceiling.Visible = matlab.lang.OnOffSwitchState(all(result.by <= 0));
            obj.drawFrame(result.t(1));
        end

        function showDouble(obj, r, params)
            k = sampleIndices(numel(r.t), obj.MaxPlotPoints);
            t = r.t(k);
            set(obj.Plots.theta1, XData=t, YData=r.theta1Deg(k));
            set(obj.Plots.theta2, XData=t, YData=r.theta2Deg(k));
            set(obj.Plots.phase2, XData=r.theta2Deg(k), YData=r.omega2(k));
            set(obj.Plots.phase1, XData=r.theta1Deg(k), YData=r.omega1(k));
            obj.showEnergy(r, k);
            if isempty(r.twin)
                set([obj.Plots.twin2 obj.Plots.separation obj.Plots.growth], XData=NaN, YData=NaN);
                title(obj.Axes.divergence, "Distance from the twin (tick ""Run a twin pendulum"")");
            else
                set(obj.Plots.twin2, XData=t, YData=rad2deg(r.twin.theta2(k)));
                set(obj.Plots.separation, XData=t, YData=log10(max(r.separation(k), realmin)));
                [rate, fitTimes, fitValues] = growthFit(r);
                set(obj.Plots.growth, XData=fitTimes, YData=fitValues);
                heading = "Distance from the twin";
                if isfinite(rate)
                    heading = heading + sprintf("  (grows like e^{%.2f t})", rate);
                end
                title(obj.Axes.divergence, heading);
            end
            if isempty(r.lyapunov)
                set(obj.Plots.lyapunov, XData=NaN, YData=NaN);
                title(obj.Axes.lyapunov, "Lyapunov exponent estimate (tick ""Estimate the Lyapunov exponent"")");
            else
                set(obj.Plots.lyapunov, XData=r.lyapunov.t, YData=r.lyapunov.lambda);
                title(obj.Axes.lyapunov, sprintf("Lyapunov exponent estimate: λ ≈ %.3f 1/s", r.lyapunov.exponent));
            end
            if isempty(r.poincare)
                set(obj.Plots.poincare, XData=NaN, YData=NaN);
            else
                set(obj.Plots.poincare, XData=rad2deg(r.poincare(:, 1)), YData=r.poincare(:, 2));
            end

            % Animation geometry for this run.
            obj.Lengths = [params.L params.L2];
            obj.Length = params.L + params.L2;
            obj.frameAnimation(obj.ViewMargin * obj.Length);
            a = obj.Anim;
            set(a.ghost, XData=r.x2(k), YData=r.y2(k));
            obj.showLinearDouble(r, params, k);
            obj.TrailSamples = min(numel(r.t), max(60, round(obj.TrailSeconds / params.dt)));
            obj.setAnimationVisible(true);
            twinVisible = matlab.lang.OnOffSwitchState(~isempty(r.twin));
            set([a.twinRods a.twinBob], Visible=twinVisible);
            above = [r.y1; r.y2];
            if ~isempty(r.twin)
                above = [above; r.twin.y1; r.twin.y2];
            end
            a.ceiling.Visible = matlab.lang.OnOffSwitchState(all(above <= 0));
            obj.drawFrame(r.t(1));
        end

        function showEnergy(obj, result, k)
            t = result.t(k);
            set(obj.Plots.kinetic, XData=t, YData=result.KE(k));
            set(obj.Plots.potential, XData=t, YData=result.PE(k));
            set(obj.Plots.total, XData=t, YData=result.E(k));
        end

        function frameAnimation(obj, limit)
            a = obj.Anim;
            set(a.axes, XLim=[-limit limit], YLim=[-limit limit]);
            set(a.ceiling, XData=[-limit limit limit -limit], YData=limit * [0.02 0.02 0.10 0.10]);
            set(a.time, Position=[-0.95 * limit, 0.22 * limit, 0]);
            set(a.angle, Position=[-0.95 * limit, 0.14 * limit, 0]);
        end

        function placeBob(obj, bob, x, y, radius)
            set(bob, XData=radius * obj.Circle(1,:) + x, YData=radius * obj.Circle(2,:) + y);
        end

        function setAnimationVisible(obj, visible)
            a = obj.Anim;
            set([a.ceiling a.ghost a.pivot a.trail a.rod a.bob a.time a.angle a.linRod a.linBob ...
                a.rod2 a.bob2 a.twinRods a.twinBob], Visible=matlab.lang.OnOffSwitchState(visible));
        end

        function showLinearSingle(obj, result, params, k)
            %SHOWLINEARSINGLE Overlay the small-angle model (samples K on plots).
            if ~showsLinear(params)
                obj.hideLinear(["thetaLin" "omegaLin" "phaseLin"]);
                return
            end
            x = smallAngleSolution(params, result.t);
            obj.Linear = struct("t", result.t, "theta", x(:, 1));
            set(obj.Plots.thetaLin, XData=result.t(k), YData=rad2deg(x(k, 1)));
            set(obj.Plots.omegaLin, XData=result.t(k), YData=x(k, 2));
            set(obj.Plots.phaseLin, XData=rad2deg(x(k, 1)), YData=x(k, 2));
        end

        function showLinearDouble(obj, result, params, k)
            if ~showsLinear(params)
                obj.hideLinear(["theta1Lin" "theta2Lin"]);
                return
            end
            x = doubleSmallAngleSolution(params, result.t);
            obj.Linear = struct("t", result.t, "theta", x(:, 1:2));
            set(obj.Plots.theta1Lin, XData=result.t(k), YData=rad2deg(x(k, 1)));
            set(obj.Plots.theta2Lin, XData=result.t(k), YData=rad2deg(x(k, 2)));
        end

        function hideLinear(obj, names)
            for name = names
                set(obj.Plots.(name), XData=NaN, YData=NaN);
            end
            set([obj.Anim.linRod obj.Anim.linBob], XData=NaN, YData=NaN);
            obj.Linear = struct("t", [], "theta", []);
        end
    end
end

% ---------------------------------------------------------------- helpers
function tf = isDoubleResult(result)
tf = isfield(result, "model") && result.model == "double";
end

function tf = showsLinear(params)
tf = isfield(params, "showLinear") && params.showLinear;
end

function [x1, y1, x2, y2] = bobs(L1, L2, theta1, theta2)
x1 = L1 * sin(theta1);
y1 = -L1 * cos(theta1);
x2 = x1 + L2 * sin(theta2);
y2 = y1 - L2 * cos(theta2);
end

function labels = pendulumModes(lambda, ~)
labels = repmat("Swing", numel(lambda), 1);
isReal = abs(imag(lambda)) <= 1e-9 * max(1, max(abs(lambda)));
labels(isReal & real(lambda) < 0) = "Settle";
labels(isReal & real(lambda) > 0) = "Topple";
end

function labels = doublePendulumModes(lambda, V)
%DOUBLEPENDULUMMODES In-phase (rods swing together) or anti-phase.
labels = repmat("Settle", numel(lambda), 1);
for k = 1:numel(lambda)
    if abs(imag(lambda(k))) > 1e-9 * max(1, abs(lambda(k)))
        if real(V(1, k) * conj(V(2, k))) > 0
            labels(k) = "In-phase swing";
        else
            labels(k) = "Anti-phase swing";
        end
    elseif real(lambda(k)) > 0
        labels(k) = "Topple";
    end
end
end

function x = smallAngleSolution(p, t)
%SMALLANGLESOLUTION θ'' + b/(m L²) θ' + (g/L) θ = 0 from the same start:
%   columns θ (rad) and ω (rad/s) at the times t.
A = [0 1; -p.g / p.L, -p.b / (p.m * p.L^2)];
x = dlab.physics.modalResponse(A, [deg2rad(p.theta0); p.omega0], t);
end

function A = doubleSmallAngleMatrix(p)
% Linear double pendulum about hanging: M θ'' + C θ' + K θ = 0.
M = [(p.m + p.m2) * p.L^2, p.m2 * p.L * p.L2; p.m2 * p.L * p.L2, p.m2 * p.L2^2];
K = diag([(p.m + p.m2) * p.g * p.L, p.m2 * p.g * p.L2]);
C = p.b * [2 -1; -1 1];
A = [zeros(2) eye(2); -(M \ K), -(M \ C)];
end

function x = doubleSmallAngleSolution(p, t)
%DOUBLESMALLANGLESOLUTION Columns θ1, θ2 (rad), ω1, ω2 of the linear model.
x0 = [deg2rad(p.theta0); deg2rad(p.theta20); p.omega0; p.omega20];
x = dlab.physics.modalResponse(doubleSmallAngleMatrix(p), x0, t);
end

function T = smallAngleRows(result, measured)
%SMALLANGLEROWS Summary rows comparing the run with the small-angle model;
%   rows that do not apply (e.g. no oscillation) are left out.
p = result.params;
w2 = p.g / p.L;
c = p.b / (p.m * p.L^2);
names = strings(0, 1);
values = zeros(0, 1);
units = strings(0, 1);
linear = NaN;
if w2 - c^2 / 4 > 0
    linear = 2 * pi / sqrt(w2 - c^2 / 4);
    [names(end+1, 1), values(end+1, 1), units(end+1, 1)] = deal("Small-angle period", linear, "s");
end
reference = measured;
if p.b == 0
    % Amplitude from the energy, then T = 4 √(L/g) K(sin²(θmax/2)).
    cosMax = cos(deg2rad(p.theta0)) - p.omega0^2 / (2 * w2);
    if cosMax > -1
        exact = 4 / sqrt(w2) * ellipke(sin(acos(cosMax) / 2)^2);
        [names(end+1, 1), values(end+1, 1), units(end+1, 1)] = deal("Exact period (undamped)", exact, "s");
        reference = exact;
    end
end
if isfinite(linear) && isfinite(reference)
    [names(end+1, 1), values(end+1, 1), units(end+1, 1)] = deal("Small-angle period error", ...
        100 * (reference - linear) / reference, "%");
end
x = smallAngleSolution(p, result.t);
[names(end+1, 1), values(end+1, 1), units(end+1, 1)] = deal("Max deviation from small-angle model", ...
    max(abs(rad2deg(result.theta - x(:, 1)))), "deg");
T = table(names, values, units, VariableNames=["Quantity" "Value" "Units"]);
end

function T = doubleSummary(r)
%DOUBLESUMMARY Key numbers of a double-pendulum run (rows that do not
%   apply are left out, so every metric is a finite number).
p = r.params;
E0 = r.E(1);
rows = {
    "Peak upper angle", max(abs(r.theta1Deg)), "deg"
    "Peak lower angle", max(abs(r.theta2Deg)), "deg"
    "Initial energy", E0, "J"
    "Final energy", r.E(end), "J"
    "Lower rod flips", flips(r.theta2), ""
    "Poincaré points", size(r.poincare, 1), ""
    "Samples", numel(r.t), ""
};
scale = max([abs(E0), max(abs(r.KE)), 1e-12]);
if p.b == 0
    rows(end+1, :) = {"Energy drift (relative)", max(abs(r.E - E0)) / scale, ""};
elseif E0 > 0
    rows(end+1, :) = {"Energy dissipated", 100 * (E0 - r.E(end)) / E0, "%"};
end
if ~isempty(r.twin)
    rows(end+1, :) = {"Diverged", double(isfinite(r.divergenceTime)), ""};
    if isfinite(r.divergenceTime)
        rows(end+1, :) = {"Divergence time", r.divergenceTime, "s"};
    end
    rate = growthFit(r);
    if isfinite(rate)
        rows(end+1, :) = {"Divergence growth rate", rate, "1/s"};
    end
end
if ~isempty(r.lyapunov)
    rows(end+1, :) = {"Lyapunov exponent", r.lyapunov.exponent, "1/s"};
end
lambda = eig(doubleSmallAngleMatrix(p));
frequencies = sort(unique(round(abs(imag(lambda(abs(imag(lambda)) > 1e-9))), 12)));
if numel(frequencies) == 2
    rows(end+1, :) = {"In-phase period (small-angle)", 2 * pi / frequencies(1), "s"};
    rows(end+1, :) = {"Anti-phase period (small-angle)", 2 * pi / frequencies(2), "s"};
end
x = doubleSmallAngleSolution(p, r.t);
rows(end+1, :) = {"Max deviation from small-angle model", max(abs(rad2deg(r.theta2 - x(:, 2)))), "deg"};
T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
    VariableNames=["Quantity" "Value" "Units"]);
end

function count = flips(theta)
% Times the rod passes straight up (θ crosses an odd multiple of 180°).
count = sum(abs(diff(floor((theta + pi) / (2 * pi)))));
end

function [rate, times, values] = growthFit(r)
%GROWTHFIT Exponential growth rate of the twin separation, fitted while it
%   is well above its start and below saturation; the fitted line in log₁₀.
rate = NaN;
times = NaN;
values = NaN;
if isempty(r.separation)
    return
end
s = r.separation;
growing = s > 10 * s(1) & s < 0.1;
first = find(growing, 1);
if isempty(first)
    return                       % never grew (a regular, non-chaotic pair)
end
last = find(growing, 1, "last");
if last - first < 5
    return
end
span = first:last;
coefficients = polyfit(r.t(span), log(s(span)), 1);
rate = coefficients(1);
times = r.t(span([1 end]));
values = polyval(coefficients, times) / log(10);
end

function period = measuredPeriod(t, theta)
%MEASUREDPERIOD Mean time between upward zero crossings of the angle
%   (NaN with fewer than two, e.g. a full rotation or a heavily damped run).
upward = find(theta(1:end-1) < 0 & theta(2:end) >= 0);
if numel(upward) < 2
    period = NaN;
    return
end
% Interpolate each crossing between its two samples.
crossings = t(upward) - theta(upward) .* (t(upward + 1) - t(upward)) ./ (theta(upward + 1) - theta(upward));
period = mean(diff(crossings));
end

function idx = sampleIndices(n, maxPoints)
idx = unique(round(linspace(1, n, min(n, maxPoints))))';
end

function map = colorRamp(from, to)
%COLORRAMP 256-entry colormap from one theme color to another (phase
%   portrait: early samples faint, late samples bright).
weights = linspace(0, 1, 256)';
map = (1 - weights) .* from + weights .* to;
end
