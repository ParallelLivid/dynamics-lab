classdef CollisionsPlugin < dlab.core.TimeDomainPlugin
    %COLLISIONSPLUGIN Billiard balls and a hard-disc gas, simulated event
    %   by event: momentum and energy in collisions, the Maxwell speed
    %   distribution, pressure, and Brownian motion. Solved by
    %   simulateCollisions.

    properties (Constant)
        Id = "collisions"
        Title = "Billiards and Gas Collisions"
        Category = "Mechanics"
        Summary = "Hard discs colliding: billiards, the Maxwell speed distribution, pressure, Brownian motion."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        DiscSides = 20
        TrailSeconds = 5
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isGas = @(p) p.mode == "gas";
            hasTracer = @(p) p.mode == "gas" && p.tracer;
            specs = [
                P("mode", Label="Start", Type="choice", Default="gas", Choices=["gas" "billiards" "twoball" "cradle"], ...
                    ChoiceLabels=["Gas" "Billiards break" "Two balls" "Newton's cradle"], Group="Discs", ...
                    Description="Gas: many discs in a box. Billiards: a cue ball breaks a 15-ball rack. " + ...
                    "Two balls: one hits another at rest, off-centre. Newton's cradle: five balls in a row.")
                P("N", Label="Number of discs", Type="integer", Default=100, Min=1, Max=400, Group="Discs", ...
                    VisibleWhen=isGas, ...
                    Description="How many discs in the gas.")
                P("radius", Label="Radius", Units="m", Default=0.02, Min=1e-4, Max=10, Group="Discs", DisplayFormat="%.4g", ...
                    Description="Radius of every disc.")
                P("mass", Label="Mass", Units="kg", Default=1, Min=1e-6, Max=1e6, Group="Discs", ...
                    Description="Mass of every disc.")
                P("e", Label="Restitution between discs", Default=1, Min=0, Max=1, Group="Discs", ...
                    Description="1: elastic. Less than 1: each collision keeps e of the approach speed " + ...
                    "along the line of centres, and loses 1 − e² of the energy of that motion.")
                P("ew", Label="Restitution at the walls", Default=1, Min=0, Max=1, Group="Discs", ...
                    Description="1: the wall reflects the disc's speed towards it; less than 1: it keeps e_w of it.")
                P("v0", Label="Speed", Units="m/s", Default=1, Min=0, Max=1e4, Group="Motion", ...
                    VisibleWhen=@(p) p.mode ~= "billiards", Description="Gas: every disc's speed at the start, " + ...
                    "or (Maxwell start) the RMS speed; either way kT = ½ m v0². Two balls, cradle: the moving ball's speed.")
                P("velocityInit", Label="Starting speeds", Type="choice", Default="equal", Choices=["equal" "maxwell"], ...
                    ChoiceLabels=["All equal" "Maxwell"], Group="Motion", VisibleWhen=isGas, ...
                    Description="All equal: watch the speeds spread out. Maxwell: start already relaxed.")
                P("seed", Label="Random seed", Type="integer", Default=1, Min=0, Max=1e6, Group="Motion", VisibleWhen=isGas, ...
                    Description="Picks the starting places, directions and speeds; the same seed gives the same run.")
                P("cueSpeed", Label="Cue ball speed", Units="m/s", Default=8, Min=0, Max=100, Group="Motion", ...
                    VisibleWhen=@(p) p.mode == "billiards", ...
                    Description="Speed of the cue ball as it leaves.")
                P("cueAngle", Label="Cue direction", Units="°", Default=0, Min=-180, Max=180, Group="Motion", ...
                    VisibleWhen=@(p) p.mode == "billiards", Description="From +x (0: straight at the rack's apex).")
                P("offset", Label="Off-centre hit", Units="radii", Default=1, Min=0, Max=1.99, Group="Motion", ...
                    VisibleWhen=@(p) p.mode == "twoball", Description="How far apart the centres are across the " + ...
                    "motion. 0: head-on. 1: the line of centres at 30°. Near 2: a glancing touch.")
                P("tracer", Label="Heavy tracer disc", Type="logical", Default=false, Group="Tracer", VisibleWhen=isGas, ...
                    Description="A big, heavy disc at the centre, kicked about by the gas: Brownian motion.")
                P("tracerMass", Label="Tracer mass", Units="× mass", Default=50, Min=1, Max=1e4, Group="Tracer", ...
                    VisibleWhen=hasTracer, ...
                    Description="Mass of the tracer, as a multiple of a gas disc's mass.")
                P("tracerRadius", Label="Tracer radius", Units="× radius", Default=4, Min=1, Max=50, Group="Tracer", ...
                    VisibleWhen=hasTracer, ...
                    Description="Radius of the tracer, as a multiple of a gas disc's radius.")
                P("W", Label="Box width", Units="m", Default=1, Min=1e-3, Max=1e4, Group="Box", ...
                    Description="Inside width of the box.")
                P("H", Label="Box height", Units="m", Default=1, Min=1e-3, Max=1e4, Group="Box", ...
                    Description="Inside height of the box.")
                P("boundary", Label="Edges", Type="choice", Default="walls", Choices=["walls" "periodic"], ...
                    ChoiceLabels=["Walls" "Periodic"], Group="Box", ...
                    Description="Periodic: no walls; a disc leaving one side comes back in on the other (no pressure).")
                P("tspan", Label="Duration", Units="s", Default=20, Min=1e-3, Max=1e5, Group="Simulation", MarksCustom=false, ...
                    Description="How long to simulate.")
                P("dtOut", Label="Output step", Units="s", Default=0.02, Min=1e-5, Max=100, Group="Simulation", ...
                    DisplayFormat="%.4g", ...
                    Description="Spacing of the saved frames; the collisions themselves are found exactly.")
                P("maxEvents", Label="Event limit", Type="integer", Default=200000, Min=10, Max=1e7, Group="Simulation", ...
                    Description="Stop after this many collisions and wall hits.")
                P("colorBySpeed", Label="Colour discs by speed", Type="logical", Default=true, Group="Display", ...
                    Display=true, ...
                    Description="Colour each disc by its speed instead of one colour.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Billiards break", "Values", struct("mode", "billiards", "radius", 0.028575, ...
                "mass", 0.17, "e", 0.95, "ew", 0.8, "W", 2.24, "H", 1.12, "cueSpeed", 8, "cueAngle", 0, ...
                "tspan", 6, "dtOut", 0.01, "colorBySpeed", false));
            list(end+1) = struct("Name", "Two-ball oblique", "Values", struct("mode", "twoball", "radius", 0.1, ...
                "W", 4, "H", 2, "v0", 1, "offset", 1, "tspan", 3, "dtOut", 0.01, "colorBySpeed", false));
            list(end+1) = struct("Name", "Newton's cradle line (5 balls)", "Values", struct("mode", "cradle", ...
                "radius", 0.1, "W", 4, "H", 1, "v0", 1, "tspan", 4, "dtOut", 0.01, "colorBySpeed", false));
            list(end+1) = struct("Name", "Gas: relaxation to Maxwell", "Values", struct());
            list(end+1) = struct("Name", "Dense gas (pressure vs ideal)", "Values", struct("N", 200, "radius", 0.025, ...
                "velocityInit", "maxwell", "tspan", 10));
            list(end+1) = struct("Name", "Brownian motion (heavy tracer)", "Values", struct("N", 150, "radius", 0.015, ...
                "tracer", true, "velocityInit", "maxwell", "boundary", "periodic", "tspan", 60));
            list(end+1) = struct("Name", "Inelastic cooling (e = 0.9)", "Values", struct("e", 0.9, "tspan", 10));
        end

        function result = solve(obj, p)
            s = dlab.sims.collisions.initialState(struct("mode", char(p.mode), "N", p.N, "radius", p.radius, ...
                "mass", p.mass, "W", p.W, "H", p.H, "v0", p.v0, "velocityInit", char(p.velocityInit), ...
                "seed", p.seed, "tracer", logical(p.tracer), "tracerMass", p.tracerMass, ...
                "tracerRadius", p.tracerRadius, "cueSpeed", p.cueSpeed, "cueAngle", p.cueAngle, "offset", p.offset));
            q = struct("pos", s.pos, "vel", s.vel, "radius", s.radius, "mass", s.mass, "e", p.e, "ew", p.ew, ...
                "W", p.W, "H", p.H, "boundary", char(p.boundary), "tspan", p.tspan, "dtOut", p.dtOut, ...
                "maxEvents", p.maxEvents, "progressFcn", obj.progressMonitor());
            result = dlab.sims.collisions.simulateCollisions(q);
            result.tracer = s.tracer;
            result.params = p;
            result.analysis = analyze(result, p);
        end

        function titles = outputTabs(~, p)
            % The speed distribution, pressure and tracer are statistics of
            % a gas: for a handful of balls they mean nothing.
            titles = "Energy and momentum";
            if p.mode == "gas"
                titles(end+1) = "Speed distribution";
                if p.boundary == "walls"
                    titles(end+1) = "Pressure";
                end
                if p.tracer
                    titles(end+1) = "Tracer";
                end
            end
            titles(end+1) = "Collisions";
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax = struct();
            grid = uigridlayout(containers{"Energy and momentum"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.energy = dlab.ui.axesIn(grid, t, Row=1, Title="Kinetic energy", XLabel="Time (s)", YLabel="KE (J)");
            obj.Ax.momentum = dlab.ui.axesIn(grid, t, Row=2, Title="Total momentum", XLabel="Time (s)", ...
                YLabel="|P| (kg·m/s)");
            if isKey(containers, "Speed distribution")
                obj.Ax.speeds = dlab.ui.axesIn(containers{"Speed distribution"}, t, Title="Speed distribution", ...
                    XLabel="Speed (m/s)", YLabel="Probability density (s/m)");
            end
            if isKey(containers, "Pressure")
                grid = uigridlayout(containers{"Pressure"}, [1 2], Padding=0, ColumnSpacing=t.Spacing.sm, ...
                    ColumnWidth={"1x", "2x"}, BackgroundColor=t.AxesBackground);
                obj.Ax.pressureBars = dlab.ui.axesIn(grid, t, Column=1, Title="Pressure (second half)", ...
                    XLabel="P (N/m)");
                obj.Ax.pressure = dlab.ui.axesIn(grid, t, Column=2, Title="Running average", XLabel="Time (s)", ...
                    YLabel="P (N/m)");
            end
            if isKey(containers, "Tracer")
                grid = uigridlayout(containers{"Tracer"}, [1 2], Padding=0, ColumnSpacing=t.Spacing.sm, ...
                    BackgroundColor=t.AxesBackground);
                obj.Ax.tracerPath = dlab.ui.axesIn(grid, t, Column=1, Title="Tracer path", XLabel="x (m)", YLabel="y (m)");
                obj.Ax.msd = dlab.ui.axesIn(grid, t, Column=2, Title="Mean-square displacement", XLabel="Lag (s)", ...
                    YLabel="MSD (m²)");
            end
            obj.Ax.rate = dlab.ui.axesIn(containers{"Collisions"}, t, Title="Collision rate", XLabel="Time (s)", ...
                YLabel="Disc–disc collisions per second");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Discs", XLabel="x (m)", YLabel="y (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            a = r.analysis;

            % Kinetic energy and |P| from zero: a conserved quantity would
            % otherwise fill the axes with its rounding noise.
            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.KE, Color=t.series(1), LineWidth=1.5);
            hold(ax, "off");
            ylim(ax, [0 topOf(r.KE)]);
            ax = obj.Ax.momentum;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.P, Color=t.series(2), LineWidth=1.5);
            hold(ax, "off");
            ylim(ax, [0 topOf(r.P)]);
            if params.boundary == "walls"
                title(ax, "Total momentum (the walls change it)");
            else
                title(ax, "Total momentum (conserved: no walls)");
            end

            if isfield(obj.Ax, "speeds")
                ax = obj.Ax.speeds;
                dlab.ui.clearAxes(ax);
                if ~isempty(a.speeds)
                    edges = linspace(0, max(a.speeds) * 1.05 + eps, 31);
                    late = histcounts(a.speeds, edges, Normalization="pdf");
                    start = histcounts(a.initialSpeeds, edges, Normalization="pdf");
                    m = params.mass;
                    top = max(late);
                    if a.kT > 0
                        top = max(top, sqrt(m / a.kT) * exp(-0.5));   % the Maxwell peak
                    end
                    top = 1.15 * max(top, eps);
                    startName = "At the start";
                    if max(start) <= 2 * top
                        top = max(top, 1.05 * max(start));
                    else
                        % All speeds equal at the start: a spike that would
                        % squash the rest.
                        startName = "At the start (peak off the scale)";
                    end
                    histogram(ax, a.speeds, edges, Normalization="pdf", FaceColor=t.series(1), EdgeColor="none", ...
                        FaceAlpha=0.7, DisplayName="Second half of the run");
                    histogram(ax, a.initialSpeeds, edges, Normalization="pdf", DisplayStyle="stairs", ...
                        EdgeColor=t.TextMuted, LineWidth=1.2, DisplayName=startName);
                    if a.kT > 0
                        v = linspace(0, edges(end), 200);
                        plot(ax, v, m * v / a.kT .* exp(-m * v.^2 / (2 * a.kT)), Color=t.series(3), LineWidth=2, ...
                            DisplayName="Maxwell–Boltzmann (2-D)");
                    end
                    ylim(ax, [0 top]);
                    dlab.ui.legend(ax, t, "Location", "northeast");
                end
                hold(ax, "off");
            end

            if isfield(obj.Ax, "pressure")
                ax = obj.Ax.pressureBars;
                dlab.ui.clearAxes(ax);
                values = [a.pressure a.idealPressure a.hendersonPressure];
                barh(ax, 1:3, values, FaceColor=t.series(4), EdgeColor="none");
                set(ax, YTick=1:3, YTickLabel=["Measured" "Ideal gas" "Henderson"], YDir="reverse", YLim=[0.4 3.6]);
                hold(ax, "off");
                ax = obj.Ax.pressure;
                dlab.ui.clearAxes(ax);
                perimeter = 2 * (params.W + params.H);
                running = r.wallImpulse ./ (perimeter * max(r.t, eps));
                plot(ax, r.t(2:end), running(2:end), Color=t.series(4), LineWidth=1.4, DisplayName="Measured");
                yline(ax, a.idealPressure, "--", Color=t.TextMuted, DisplayName="Ideal gas N kT / A");
                yline(ax, a.hendersonPressure, ":", Color=t.series(3), LineWidth=1.5, DisplayName="Hard discs (Henderson)");
                hold(ax, "off");
                dlab.ui.legend(ax, t, "Location", "best");
            end

            if isfield(obj.Ax, "msd") && r.tracer > 0
                ax = obj.Ax.tracerPath;
                dlab.ui.clearAxes(ax);
                rectangle(ax, Position=[0 0 params.W params.H], EdgeColor=t.TextMuted, ...
                    LineStyle=pick(r.periodic, "--", "-"));
                [px, py] = tracerLine(r, 1:numel(r.t));
                plot(ax, px, py, Color=t.series(2), LineWidth=1.2);
                hold(ax, "off");
                axis(ax, "equal");
                set(ax, XLim=[0 params.W], YLim=[0 params.H]);
                ax = obj.Ax.msd;
                dlab.ui.clearAxes(ax);
                plot(ax, a.lags, a.msd, Color=t.series(2), LineWidth=1.5, DisplayName="Tracer");
                if isfinite(a.diffusion)
                    plot(ax, a.lags, 4 * a.diffusion * a.lags + a.msdOffset, "--", Color=t.Text, ...
                        DisplayName=sprintf("Slope 4 D (fitted from %.3g s): D = %.3g m²/s", a.fitFrom, a.diffusion));
                end
                hold(ax, "off");
                ylim(ax, [0 topOf(a.msd)]);
                dlab.ui.legend(ax, t, "Location", "northwest");
            end

            ax = obj.Ax.rate;
            dlab.ui.clearAxes(ax);
            if ~isempty(a.rateTimes)
                stairs(ax, a.rateTimes, a.rate, Color=t.series(1), LineWidth=1.3);
            end
            hold(ax, "off");

            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.energy, run.Result.t, run.Result.KE, run);
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
            if isempty(r) || ~isfield(obj.Anim, "discs")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            centers = [r.x(k, :)', r.y(k, :)'];
            [~, vertices] = dlab.ui.Schematic.discs(centers, r.radius, obj.DiscSides);
            set(a.discs, Vertices=vertices);
            if a.bySpeed
                set(a.discs, FaceVertexCData=hypot(r.vx(k, :), r.vy(k, :))');
            end
            if r.tracer > 0
                from = find(r.t >= r.t(k) - obj.TrailSeconds, 1);
                [px, py] = tracerLine(r, from:k);
                set(a.trail, XData=px, YData=py);
            end
            a.readout.String = sprintf("t = %.2f s   KE = %.4g J", simTime, r.KE(k));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.KE, r.P, r.wallImpulse, VariableNames=["time" "kinetic_energy" "momentum" ...
                "wall_impulse_total"]);
            T.Properties.VariableUnits = ["s" "J" "kg*m/s" "N*s"];
        end

        function T = summaryTable(~, r)
            p = r.params;
            a = r.analysis;
            n = numel(r.mass);
            rows = {
                "Collisions", r.collisions, "", "%d", ""
                "Collisions per disc", 2 * r.collisions / n, "", "%.4g", ""
            };
            if ~r.periodic
                rows(end+1, :) = {"Wall hits", r.wallHits, "", "%d", ""};
            end
            if p.e == 1 && (p.ew == 1 || r.periodic)
                rows(end+1, :) = {"Energy drift (relative)", max(abs(r.KE - r.KE(1))) / max(r.KE(1), realmin), "", "%.3g", ""};
            else
                rows(end+1, :) = {"Energy lost", 100 * (1 - r.KE(end) / max(r.KE(1), realmin)), "%", "%.4g", ""};
            end
            if r.periodic
                rows(end+1, :) = {"Momentum drift (relative)", max(abs(r.P - r.P(1))) / ...
                    max(r.P(1), sqrt(2 * r.KE(1) * sum(r.mass))), "", "%.3g", ""};
            end
            if p.mode == "twoball"
                rows = [rows; twoBallRows(r)];
            end
            if p.mode == "gas"
                rows(end+1, :) = {"kT (mean energy per disc)", a.kT, "J", "%.4g", ""};
                rows(end+1, :) = numberOr("KS distance from Maxwell", a.ks, "", "%.3g", "— (no motion)");
                rows(end+1, :) = {"Packing fraction", 100 * a.packing, "%", "%.4g", ""};
                if ~r.periodic
                    ratio = NaN;
                    if a.idealPressure > 0
                        ratio = a.pressure / a.idealPressure;
                    end
                    rows(end+1, :) = numberOr("Pressure ratio P / P_ideal", ratio, "", "%.4g", "— (no motion)");
                    rows(end+1, :) = {"Henderson P / P_ideal", henderson(a.packing), "", "%.4g", ""};
                end
                if r.tracer > 0
                    rows(end+1, :) = numberOr("Diffusion coefficient", a.diffusion, "m²/s", "%.3g", ...
                        "— (run too short)");
                end
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            switch r.stopped
                case "maxEvents"
                    [note, level] = deal(sprintf("stopped at the event limit (t = %.3g s)", r.t(end)), "warning");
                case "cancelled"
                    [note, level] = deal("cancelled", "warning");
                otherwise
                    [note, level] = deal(sprintf("%d collisions", r.collisions), "success");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Billiards break", "Tab", "Animation", "Time", 0.4);
        end

        function description = about(~)
            description = join([
                "Hard discs move in straight lines between collisions. The next collision of every " + ...
                "pair is found exactly, from |Δr + Δv t| = r_i + r_j, so there is no time step."
                ""
                "A collision exchanges the impulse J = (1 + e) μ u along the line of centres " + ...
                "(μ the reduced mass, u the approach speed): momentum is conserved, and energy too when e = 1."
                ""
                "Many discs settle into the 2-D Maxwell–Boltzmann speed distribution " + ...
                "f(v) = (m v / kT) exp(−m v² / 2kT), whatever their start. The walls feel a pressure, " + ...
                "above the ideal gas N kT / A because the discs take up room (Henderson's equation of state). " + ...
                "A heavy disc among them wanders randomly (Brownian motion): its mean-square displacement " + ...
                "grows like 4 D t once it has forgotten its velocity, as long as no wall stops it."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            % Walls solid; the edges of a periodic box dashed (discs pass through).
            rectangle(ax, Position=[0 0 params.W params.H], EdgeColor=t.Text, LineWidth=1.5, ...
                LineStyle=pick(r.periodic, "--", "-"));
            centers = [r.x(1, :)', r.y(1, :)'];
            [faces, vertices] = dlab.ui.Schematic.discs(centers, r.radius, obj.DiscSides);
            a.bySpeed = logical(params.colorBySpeed);
            if a.bySpeed
                % Thin edges keep the slowest discs (the colour map's end
                % nearest the background) visible.
                a.discs = patch(ax, Faces=faces, Vertices=vertices, FaceVertexCData=hypot(r.vx(1, :), r.vy(1, :))', ...
                    FaceColor="flat", EdgeColor=t.Border, LineWidth=0.5, CDataMapping="scaled");
                colormap(ax, t.sequentialMap());
                top = max(max(hypot(r.vx, r.vy)));
                clim(ax, [0 max(top, eps)]);
            else
                colors = repmat(t.series(1), size(faces, 1), 1);
                if params.mode == "billiards" || params.mode == "twoball" || params.mode == "cradle"
                    colors(1, :) = t.Text;                     % the cue (moving) ball
                end
                a.discs = patch(ax, Faces=faces, Vertices=vertices, FaceVertexCData=colors, FaceColor="flat", ...
                    EdgeColor=t.Border);
            end
            if r.tracer > 0
                a.trail = plot(ax, NaN, NaN, Color=t.series(2), LineWidth=1.5);
            end
            a.readout = text(ax, 0.01, 0.99, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            % Head room above the box for the readout.
            pad = 0.03 * max(params.W, params.H);
            span = params.H + 2 * pad;
            set(ax, XLim=[-pad params.W + pad], YLim=[-pad params.H + pad + 0.1 * span]);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function a = analyze(r, p)
% Speed statistics, pressure, the tracer's diffusion, and the collision rate.
% kT, the speeds and the pressure all come from the second half of the run.
n = numel(r.mass);
gas = true(1, n);
if r.tracer > 0
    gas(r.tracer) = false;
end
late = r.t >= r.t(end) / 2;
speeds = hypot(r.vx(late, gas), r.vy(late, gas));
a.speeds = speeds(:);
a.initialSpeeds = hypot(r.vx(1, gas), r.vy(1, gas))';
energy = 0.5 * (r.vx(late, gas).^2 + r.vy(late, gas).^2) * r.mass(gas);
a.kT = mean(energy) / max(nnz(gas), 1);
a.ks = dlab.sims.collisions.maxwellDistance(a.speeds, p.mass, a.kT);
area = p.W * p.H;
a.packing = sum(pi * r.radius.^2) / area;
a.idealPressure = n * a.kT / area;
a.hendersonPressure = a.idealPressure * henderson(a.packing);
% Wall impulse per unit length and time, over the same half as kT (in a
% cooling gas a whole-run average would not belong to that kT).
from = find(late, 1);
perimeter = 2 * (p.W + p.H);
if r.t(end) > r.t(from)
    a.pressure = (r.wallImpulse(end) - r.wallImpulse(from)) / (perimeter * (r.t(end) - r.t(from)));
else
    a.pressure = r.wallImpulse(end) / (perimeter * max(r.t(end), eps));
end
[a.lags, a.msd, a.diffusion, a.msdOffset, a.fitFrom] = deal(zeros(0, 1), zeros(0, 1), NaN, NaN, NaN);
if r.tracer > 0 && numel(r.t) > 8
    [x, y] = unwrapped(r, r.tracer);
    [a.lags, a.msd, a.diffusion, a.msdOffset, a.fitFrom] = diffusion(r.t, x, y);
end
pairs = r.events(r.events(:, 3) > 0, 1);
a.rateTimes = zeros(0, 1);
a.rate = zeros(0, 1);
if ~isempty(pairs)
    edges = linspace(0, r.t(end), min(100, max(10, numel(r.t))) + 1)';
    counts = histcounts(pairs, edges)';
    a.rateTimes = edges;
    a.rate = [counts; counts(end)] / (edges(2) - edges(1));
end
end

function Z = henderson(eta)
% Henderson's equation of state for hard discs, P A / N kT.
Z = (1 + eta^2 / 8) / max((1 - eta)^2, realmin);
end

function [x, y] = unwrapped(r, k)
% Disc K's path, with the periodic box's wrapping undone, relative to the
% centre of mass: with no walls the total momentum is conserved, and the
% whole gas drifts at P / M (a drift the MSD would show as ballistic).
x = r.x(:, k);
y = r.y(:, k);
if r.periodic
    total = sum(r.mass);
    x = r.W * unwrap(2 * pi * x / r.W) / (2 * pi) - (r.vx(1, :) * r.mass) / total * r.t;
    y = r.H * unwrap(2 * pi * y / r.H) / (2 * pi) - (r.vy(1, :) * r.mass) / total * r.t;
end
end

function [x, y] = tracerLine(r, rows)
% The tracer's path over ROWS for drawing: in a periodic box the line is
% broken where it leaves one side and comes back in on the other.
x = r.x(rows, r.tracer);
y = r.y(rows, r.tracer);
if r.periodic && numel(x) > 1
    jump = [false; abs(diff(x)) > r.W / 2 | abs(diff(y)) > r.H / 2];
    k = find(jump);
    x = insertNaN(x, k);
    y = insertNaN(y, k);
end
end

function v = insertNaN(v, before)
% A NaN before each index in BEFORE.
for k = flip(before(:)')
    v = [v(1:k - 1); NaN; v(k:end)];
end
end

function [lags, msd, D, offset, fitFrom] = diffusion(t, x, y)
% Time-averaged mean-square displacement up to an eighth of the run (longer
% lags are averaged over too few independent stretches). At short lags the
% tracer still remembers its velocity (MSD ~ t²), so D comes from the slope
% of a straight line, MSD = 4 D t + c, fitted over the later half of the lags.
dt = t(2) - t(1);
if numel(t) > 2 && abs(t(end) - t(end - 1) - dt) > 1e-9 * dt
    % The last sample (cut short by the duration) is off the regular grid.
    [x, y] = deal(x(1:end - 1), y(1:end - 1));
end
count = max(2, floor(numel(x) / 8));
lags = (1:count)' * dt;
msd = zeros(count, 1);
for k = 1:count
    msd(k) = mean((x(1 + k:end) - x(1:end - k)).^2 + (y(1 + k:end) - y(1:end - k)).^2);
end
use = lags >= lags(end) / 2;
coef = [4 * lags(use), ones(nnz(use), 1)] \ msd(use);
[D, offset] = deal(coef(1), coef(2));
fitFrom = lags(find(use, 1));
end

function rows = twoBallRows(r)
% The moving ball (1) and the struck ball (2) just after their collision.
f = r.firstCollision;
if isnan(f.time)
    rows = {"Collision", NaN, "", "", "none (the balls miss)"};
    return
end
v = zeros(2, 2);
v([f.i f.j], :) = [f.vi; f.vj];
speeds = vecnorm(v, 2, 2);
rows = {
    "Time of the collision", f.time, "s", "%.4g", ""
    "Moving ball's speed after", speeds(1), "m/s", "%.4g", ""
    "Struck ball's speed after", speeds(2), "m/s", "%.4g", ""
};
if min(speeds) > 1e-9 * max(speeds)
    angle = acosd(max(-1, min(1, v(1, :) * v(2, :)' / prod(speeds))));
    rows(end+1, :) = {"Angle between the paths after", angle, "°", "%.6g", ""};
else
    rows(end+1, :) = {"Angle between the paths after", NaN, "°", "", "— (one ball stops)"};
end
end

function row = numberOr(name, value, units, format, fallback)
% A Summary row with the value, or text when it is not a finite number.
if isfinite(value)
    row = {name, value, units, format, ""};
else
    row = {name, NaN, units, "", fallback};
end
end

function top = topOf(values)
% The upper limit for an axis that starts at zero.
top = 1.05 * max(values(:));
if ~(top > 0)
    top = 1;
end
end

function out = pick(condition, ifTrue, ifFalse)
if condition
    out = ifTrue;
else
    out = ifFalse;
end
end
