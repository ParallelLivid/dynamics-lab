classdef ThreeBodyPlugin < dlab.core.TimeDomainPlugin
    %THREEBODYPLUGIN The circular restricted three-body problem (Lagrange
    %   points, zero-velocity curves, the Arenstorf orbit) and the general
    %   N-body problem (figure-8, Lagrange triangle, Pythagorean). Solved
    %   by simulateCr3bp and simulateNBody.

    properties (Constant)
        Id = "threebody"
        Title = "Three-Body Problem"
        Category = "Aerospace"
        Summary = "Lagrange points, zero-velocity curves, and choreographies of three or more bodies."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        CrTabs = ["Trajectory" "Inertial view" "Jacobi constant" "Distances"]
        NTabs = ["Trajectories" "Energy and momentum" "Distances"]
        TrailFraction = 0.15      % of the run
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
            isCr = @(p) p.model == "cr3bp";
            isN = @(p) p.model == "nbody";
            specs = [
                P("model", Label="Model", Type="choice", Default="cr3bp", Choices=["cr3bp" "nbody"], ...
                    ChoiceLabels=["Restricted" "N bodies"], Group="Model", ...
                    Description="Restricted: a small body moving under two primaries on circular orbits, in " + ...
                    "the frame turning with them. N bodies: 2 to 8 point masses under their mutual gravity.")
                P("system", Label="Primaries", Type="choice", Default="custom", ...
                    Choices=["earthmoon" "sunearth" "sunjupiter" "custom"], ...
                    ChoiceLabels=["Earth–Moon" "Sun–Earth" "Sun–Jupiter" "Custom"], Group="Model", ...
                    VisibleWhen=isCr, Description="Sets the mass ratio μ, the primaries' sizes (a collision ends " + ...
                    "the run), and the scales for km and days. Custom: any μ, point primaries.")
                P("mu", Label="Mass ratio μ", Default=0.012277471, Min=1e-9, Max=0.5, Group="Model", ...
                    VisibleWhen=@(p) isCr(p) && p.system == "custom", DisplayFormat="%.6g", ...
                    Description="The smaller primary's share of the total mass.")
                P("x0", Label="x₀", Default=0.994, Min=-10, Max=10, Group="Start (rotating frame)", VisibleWhen=isCr, ...
                    DisplayFormat="%.10g", Description="In units of the primaries' separation.")
                P("y0", Label="y₀", Default=0, Min=-10, Max=10, Group="Start (rotating frame)", VisibleWhen=isCr, ...
                    DisplayFormat="%.10g", Description="Perpendicular to the line of the primaries, in the plane.")
                P("z0", Label="z₀", Default=0, Min=-10, Max=10, Group="Start (rotating frame)", VisibleWhen=isCr, ...
                    DisplayFormat="%.10g", Description="Out of the primaries' plane.")
                P("vx0", Label="ẋ₀", Default=0, Min=-10, Max=10, Group="Start (rotating frame)", VisibleWhen=isCr, ...
                    DisplayFormat="%.10g", Description="Velocity in the rotating frame (separations per time unit).")
                P("vy0", Label="ẏ₀", Default=-2.00158510637908, Min=-10, Max=10, Group="Start (rotating frame)", ...
                    VisibleWhen=isCr, DisplayFormat="%.15g", Description="Velocity in the rotating frame, along y.")
                P("vz0", Label="ż₀", Default=0, Min=-10, Max=10, Group="Start (rotating frame)", VisibleWhen=isCr, ...
                    DisplayFormat="%.10g", Description="Velocity in the rotating frame, along z.")
                P("bodies", Label="Bodies", Type="table", Group="Bodies", MinRows=2, MaxRows=8, VisibleWhen=isN, ...
                    Description="G = 1. One row per body.", Columns=[
                        C("m", Label="Mass", Min=0, MinInclusive=false, Default=1)
                        C("x", Label="x", Default=0)
                        C("y", Label="y", Default=0)
                        C("z", Label="z", Default=0)
                        C("vx", Label="vx", Default=0)
                        C("vy", Label="vy", Default=0)
                        C("vz", Label="vz", Default=0)
                    ], Default=figureEight())
                P("soft", Label="Softening ε", Default=0, Min=0, Max=10, Group="Bodies", VisibleWhen=isN, ...
                    Description="Forces use r² + ε², which tames close encounters (and changes the physics).")
                P("tspan", Label="Duration", Units="time units", Default=17.0652165601580, Min=1e-3, Max=1e5, ...
                    Group="Simulation", MarksCustom=false, DisplayFormat="%.12g", ...
                    Description="Restricted problem: 2π is one orbit of the primaries (27.3 days for Earth–Moon).")
                P("dt", Label="Output step", Units="time units", Default=0.01, Min=1e-5, Max=100, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of saved samples; ode113 picks its own steps.")
                P("linearizeAbout", Label="Modes about", Type="choice", Default="L1", ...
                    Choices=["L1" "L2" "L3" "L4" "L5"], Group="Simulation", VisibleWhen=isCr, ...
                    Description="The Lagrange point the Modes tab linearizes about.")
                P("frame", Label="Animation frame", Type="choice", Default="rotating", Choices=["rotating" "inertial"], ...
                    ChoiceLabels=["Rotating" "Inertial"], Group="Display", Display=true, ...
                    VisibleWhen=isCr, Description="Animate in the frame turning with the primaries, or in a " + ...
                    "fixed frame where they circle.")
                P("showZvc", Label="Shade the forbidden region", Type="logical", Default=true, Group="Display", ...
                    Display=true, VisibleWhen=isCr, Description="Where 2Ω < C the body cannot go (its speed² " + ...
                    "would be negative).")
                P("showLpoints", Label="Show Lagrange points", Type="logical", Default=true, Group="Display", ...
                    Display=true, VisibleWhen=isCr, Description="Mark L1 to L5.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Arenstorf orbit (Earth–Moon)", "Values", struct());
            cr = @(system, s, tspan, about) struct("model", "cr3bp", "system", system, "x0", s(1), "y0", s(2), ...
                "z0", 0, "vx0", s(3), "vy0", s(4), "vz0", 0, "tspan", tspan, "dt", 0.01, "linearizeAbout", about);
            list(end+1) = struct("Name", "Tadpole orbit at L4", "Values", ...
                cr("earthmoon", [0.4262205668 0.8987940463 0 0], 100, "L4"));
            list(end+1) = struct("Name", "Planar Lyapunov orbit at L1", "Values", ...
                cr("earthmoon", [0.8234 0 0 0.126231978668], 2 * 2.7429123958, "L1"));
            list(end+1) = struct("Name", "Through the L1 neck to the Moon", "Values", ...
                cr("earthmoon", [0.6 0 0.3464563987 0.6000800851], 30, "L1"));
            list(end+1) = struct("Name", "Sun–Jupiter Trojan", "Values", ...
                cr("sunjupiter", [0.4530366197 0.8910065242 0 0], 400, "L4"));
            nb = @(bodies, tspan) struct("model", "nbody", "bodies", bodies, "soft", 0, "tspan", tspan, "dt", 0.01);
            list(end+1) = struct("Name", "Figure-8 choreography", "Values", nb(figureEight(), 6.32591398));
            R = 1 / sqrt(3);
            angle = deg2rad([90; 210; 330]);
            triangle = [ones(3, 1), R * cos(angle), R * sin(angle), zeros(3, 1), -sin(angle), cos(angle), zeros(3, 1)];
            % 40 time units: it holds its shape to 2e−5 for 20, then breaks up.
            list(end+1) = struct("Name", "Lagrange equilateral triangle", "Values", nb(triangle, 40));
            pythagorean = [3 1 3 0 0 0 0; 4 -2 -1 0 0 0 0; 5 1 -1 0 0 0 0];
            list(end+1) = struct("Name", "Pythagorean three-body (3-4-5)", "Values", nb(pythagorean, 20));
        end

        function result = solve(obj, p)
            if p.model == "nbody"
                T = dlab.core.TableColumn.toTable(obj.bodyColumns(), p.bodies);
                q = struct("mass", T.m, "pos", [T.x T.y T.z], "vel", [T.vx T.vy T.vz], "soft", p.soft, ...
                    "tspan", p.tspan, "dt", p.dt, "progressFcn", obj.progressMonitor());
                result = dlab.sims.threebody.simulateNBody(q);
                result.isNBody = true;
            else
                sys = systemOf(p);
                q = struct("mu", sys.mu, "state0", [p.x0 p.y0 p.z0 p.vx0 p.vy0 p.vz0], "tspan", p.tspan, ...
                    "dt", p.dt, "radii", sys.radii, "progressFcn", obj.progressMonitor());
                result = dlab.sims.threebody.simulateCr3bp(q);
                result.isNBody = false;
                result.system = sys;
            end
            result.params = p;
        end

        function titles = outputTabs(obj, p)
            titles = obj.CrTabs;
            if p.model == "nbody"
                titles = obj.NTabs;
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax = struct();
            if isKey(containers, "Trajectory")
                obj.Ax.trajectory = dlab.ui.axesIn(containers{"Trajectory"}, t, Title="Rotating frame", ...
                    XLabel="x", YLabel="y");
                obj.Ax.inertial = dlab.ui.axesIn(containers{"Inertial view"}, t, Title="Inertial frame", ...
                    XLabel="X", YLabel="Y");
                obj.Ax.jacobi = dlab.ui.axesIn(containers{"Jacobi constant"}, t, Title="Jacobi constant drift", ...
                    XLabel="Time", YLabel="|C − C₀|");
                obj.Ax.distance = dlab.ui.axesIn(containers{"Distances"}, t, Title="Distance to the primaries", ...
                    XLabel="Time", YLabel="Distance");
            else
                obj.Ax.paths = dlab.ui.axesIn(containers{"Trajectories"}, t, Title="Trajectories", XLabel="x", YLabel="y");
                obj.Ax.drift = dlab.ui.axesIn(containers{"Energy and momentum"}, t, Title="Conservation", ...
                    XLabel="Time", YLabel="Relative change");
                obj.Ax.distance = dlab.ui.axesIn(containers{"Distances"}, t, Title="Distance between bodies", ...
                    XLabel="Time", YLabel="Distance");
            end
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Bodies", XLabel="x", YLabel="y");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            if r.isNBody
                obj.showNBody(r);
            else
                obj.showRestricted(r, params);
            end
            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                if ~run.Result.isNBody && isfield(obj.Ax, "trajectory")
                    dlab.ui.overlayLine(obj.Ax.trajectory, run.Result.state(:, 1), run.Result.state(:, 2), run);
                end
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

        function rate = playbackRate(~, r)
            rate = r.t(end) / 20;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "bodies")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            from = find(r.t >= r.t(k) - obj.TrailFraction * r.t(end), 1);
            if r.isNBody
                for b = 1:numel(r.mass)
                    set(a.trails(b), XData=r.pos(from:k, b, 1), YData=r.pos(from:k, b, 2));
                end
                set(a.bodies, XData=r.pos(k, :, 1), YData=r.pos(k, :, 2));
            else
                mu = r.mu;
                if a.inertial
                    angle = r.t(k);
                    primaries = [-mu 0; 1 - mu 0] * [cos(angle) sin(angle); -sin(angle) cos(angle)];
                    set(a.trails, XData=r.inertial(from:k, 1), YData=r.inertial(from:k, 2));
                    set(a.body, XData=r.inertial(k, 1), YData=r.inertial(k, 2));
                else
                    primaries = [-mu 0; 1 - mu 0];
                    set(a.trails, XData=r.state(from:k, 1), YData=r.state(from:k, 2));
                    set(a.body, XData=r.state(k, 1), YData=r.state(k, 2));
                end
                set(a.bodies, XData=primaries(:, 1), YData=primaries(:, 2));
            end
            a.readout.String = timeLabel(r, simTime);
        end

        function T = exportTable(~, r)
            if r.isNBody
                n = numel(r.mass);
                data = reshape(permute(r.pos(:, :, 1:2), [1 3 2]), numel(r.t), 2 * n);
                names = reshape(["x"; "y"] + (1:n), 1, []);
                T = array2table([r.t, data, r.energy], VariableNames=["time" names "energy"]);
                % Canonical units (G = 1): distance, time, and mass units.
                T.Properties.VariableUnits = ["TU" repmat("DU", 1, 2 * n) "MU*DU^2/TU^2"];
            else
                T = table(r.t, r.state(:, 1), r.state(:, 2), r.state(:, 3), r.state(:, 4), r.state(:, 5), ...
                    r.state(:, 6), r.C, VariableNames=["time" "x" "y" "z" "vx" "vy" "vz" "jacobi"]);
                % DU: the primaries' separation; TU: 1/(their angular rate).
                T.Properties.VariableUnits = ["TU" "DU" "DU" "DU" "DU/TU" "DU/TU" "DU/TU" "DU^2/TU^2"];
            end
        end

        function T = summaryTable(~, r)
            if r.isNBody
                rows = {
                    "Energy drift (relative)", r.drift.energy, ""
                    "Momentum drift (relative)", r.drift.momentum, ""
                    "Angular momentum drift (relative)", r.drift.angular, ""
                    "Closest approach", r.closest, ""
                    "Return error", returnError(r), ""
                };
            else
                sys = r.system;
                L = r.L;
                rows = {
                    "Jacobi constant", r.C0, ""
                    "Jacobi drift", max(abs(r.C - r.C0)), ""
                    "Closest to " + sys.names(1), min(r.r1), ""
                    "Closest to " + sys.names(2), min(r.r2), ""
                    "Return error", returnError(r), ""
                    "C at L1", dlab.sims.threebody.jacobi(r.mu, [L(1, :) 0 0 0]), ""
                    "C at L2", dlab.sims.threebody.jacobi(r.mu, [L(2, :) 0 0 0]), ""
                    "L1 x", L(1, 1), ""
                    "L2 x", L(2, 1), ""
                    "L3 x", L(3, 1), ""
                };
                if isfinite(sys.lengthKm)
                    rows(end+1:end+3, :) = {
                        "Closest to " + sys.names(1) + " in km", min(r.r1) * sys.lengthKm, "km"
                        "Closest to " + sys.names(2) + " in km", min(r.r2) * sys.lengthKm, "km"
                        "Duration in days", r.t(end) * sys.dayPerUnit, "days"};
                end
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function [note, level] = resultNote(~, r)
            [note, level] = deal("", "success");
            if r.isNBody
                return
            end
            switch string(r.termination)
                case "collision1"
                    [note, level] = deal("hit " + r.system.names(1), "warning");
                case "collision2"
                    [note, level] = deal("hit " + r.system.names(2), "warning");
                otherwise
                    if r.escaped
                        note = "escaped (beyond 10 units)";
                    end
            end
        end

        function lin = linearization(~, p)
            lin = [];
            if p.model ~= "cr3bp"
                return
            end
            sys = systemOf(p);
            L = dlab.sims.threebody.lagrangePoints(sys.mu);
            k = find(["L1" "L2" "L3" "L4" "L5"] == p.linearizeAbout, 1);
            mu = sys.mu;
            % The exact linear model (finite differences would blur L4/L5's
            % purely imaginary eigenvalues), checked against cr3bpRhs by the tests.
            % States are offsets from the point, so the differences are exact.
            A = dlab.sims.threebody.cr3bpJacobian(mu, L(k, :));
            reference = sprintf("offsets from rest at %s (x = %.6f, y = %.6f), μ = %.6g", p.linearizeAbout, ...
                L(k, 1), L(k, 2), mu);
            if isfinite(sys.dayPerUnit)
                reference = reference + sprintf("; one time unit is %.4g days", sys.dayPerUnit);
            end
            lin = struct("F", @(s) A * s, "X0", zeros(6, 1), "StateNames", ["δx" "δy" "δz" "δẋ" "δẏ" "δż"], ...
                "Reference", reference, "Classify", @modeNames, "Scale", ones(1, 6), "TimeUnit", "time unit");
        end

        function scene = showcase(~)
            scene = struct("Preset", "Arenstorf orbit (Earth–Moon)", "Tab", "Trajectory", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Restricted problem, rotating with the primaries (separation 1, total mass 1, period 2π):"
                "  ẍ − 2ẏ = ∂Ω/∂x,  ÿ + 2ẋ = ∂Ω/∂y,  z̈ = ∂Ω/∂z,   Ω = ½(x² + y²) + (1 − μ)/r₁ + μ/r₂"
                "The Jacobi constant C = 2Ω − v² is conserved; the body can only be where 2Ω ≥ C."
                ""
                "N bodies (G = 1):  r̈_i = Σ_j m_j (r_j − r_i) / (|r_j − r_i|² + ε²)^(3/2)"
                ""
                "Integrated with ode113 (tolerances 10⁻¹²)."
            ], newline);
        end
    end

    methods (Access = private)
        function columns = bodyColumns(obj)
            specs = obj.parameters();
            columns = specs(arrayfun(@(s) s.Name == "bodies", specs)).Columns;
        end

        function showRestricted(obj, r, params)
            t = obj.Theme;
            sys = r.system;
            ax = obj.Ax.trajectory;
            dlab.ui.clearAxes(ax);
            [xr, yr] = viewRange(r.state(:, 1), r.state(:, 2), r.mu, params.showLpoints, r.L);
            if params.showZvc
                [X, Y, W] = dlab.sims.threebody.zeroVelocity(r.mu, xr, yr, 300);
                forbidden = double(W < r.C0);
                shade = reshape(t.TextMuted, 1, 1, 3) .* ones(size(W));
                image(ax, xr, yr, shade, AlphaData=0.35 * forbidden);
                contour(ax, X, Y, W, [r.C0 r.C0], LineColor=t.TextMuted, LineWidth=1);
            end
            drawPrimaries(ax, [-r.mu 0; 1 - r.mu 0], sys, t);
            if params.showLpoints
                plot(ax, r.L(:, 1), r.L(:, 2), "+", Color=t.series(4), MarkerSize=10, LineWidth=1.5);
                text(ax, r.L(:, 1), r.L(:, 2), "  " + ["L1"; "L2"; "L3"; "L4"; "L5"], Color=t.series(4), ...
                    FontSize=t.FontSize.sm, VerticalAlignment="bottom");
            end
            plot(ax, r.state(:, 1), r.state(:, 2), Color=t.series(1), LineWidth=1.3);
            plot(ax, r.state(1, 1), r.state(1, 2), "o", MarkerFaceColor=t.series(2), MarkerEdgeColor=t.Text);
            hold(ax, "off");
            set(ax, XLim=xr, YLim=yr, YDir="normal");
            daspect(ax, [1 1 1]);
            title(ax, sprintf("Rotating frame: %s, C = %.6f", sys.label, r.C0));

            ax = obj.Ax.inertial;
            dlab.ui.clearAxes(ax);
            angle = linspace(0, 2 * pi, 200);
            plot(ax, -r.mu * cos(angle), -r.mu * sin(angle), ":", Color=t.TextMuted);
            plot(ax, (1 - r.mu) * cos(angle), (1 - r.mu) * sin(angle), ":", Color=t.TextMuted);
            plot(ax, r.inertial(:, 1), r.inertial(:, 2), Color=t.series(1), LineWidth=1.2);
            hold(ax, "off");
            daspect(ax, [1 1 1]);

            ax = obj.Ax.jacobi;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, max(abs(r.C - r.C0), 1e-17), Color=t.series(1), LineWidth=1.3);
            hold(ax, "off");
            set(ax, YScale="log");

            ax = obj.Ax.distance;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.r1, Color=t.series(1), LineWidth=1.3, DisplayName=sys.names(1));
            plot(ax, r.t, r.r2, Color=t.series(2), LineWidth=1.3, DisplayName=sys.names(2));
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function showNBody(obj, r)
            t = obj.Theme;
            n = numel(r.mass);
            ax = obj.Ax.paths;
            dlab.ui.clearAxes(ax);
            for b = 1:n
                plot(ax, r.pos(:, b, 1), r.pos(:, b, 2), Color=t.series(b), LineWidth=1.2, ...
                    DisplayName=sprintf("Body %d (m = %.3g)", b, r.mass(b)));
            end
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            dlab.ui.legend(ax, t, "Location", "eastoutside");

            ax = obj.Ax.drift;
            dlab.ui.clearAxes(ax);
            scale = max(abs(r.energy(1)), realmin);
            plot(ax, r.t, max(abs(r.energy - r.energy(1)) / scale, 1e-17), Color=t.series(1), LineWidth=1.3, ...
                DisplayName="Energy");
            P = sqrt(sum((r.momentum - r.momentum(1, :)).^2, 2));
            plot(ax, r.t, max(P / max(sum(r.mass), realmin), 1e-17), Color=t.series(2), LineWidth=1.3, ...
                DisplayName="Momentum");
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.distance;
            dlab.ui.clearAxes(ax);
            c = 0;
            for i = 1:n - 1
                for j = i + 1:n
                    c = c + 1;
                    d = sqrt(sum((r.pos(:, i, :) - r.pos(:, j, :)).^2, 3));
                    plot(ax, r.t, d, Color=t.series(c), LineWidth=1.2, DisplayName=sprintf("%d–%d", i, j));
                end
            end
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            if r.isNBody
                n = numel(r.mass);
                a.trails = gobjects(n, 1);
                for b = 1:n
                    a.trails(b) = plot(ax, NaN, NaN, Color=t.series(b), LineWidth=1.2);
                end
                sizes = 60 + 240 * (r.mass / max(r.mass)).^(1/3);
                colors = cell2mat(arrayfun(@(b) t.series(b), (1:n)', UniformOutput=false));
                a.bodies = scatter(ax, NaN(1, n), NaN(1, n), sizes, colors, "filled", MarkerEdgeColor=t.Text);
                x = r.pos(:, :, 1);
                y = r.pos(:, :, 2);
                pad = 0.1 * max([range2(x(:)), range2(y(:)), eps]);
                set(ax, XLim=[min(x(:)) max(x(:))] + [-pad pad], YLim=[min(y(:)) max(y(:))] + [-pad pad]);
                title(ax, "Bodies (G = 1)");
            else
                a.inertial = params.frame == "inertial";
                if a.inertial
                    angle = linspace(0, 2 * pi, 200);
                    plot(ax, (1 - r.mu) * cos(angle), (1 - r.mu) * sin(angle), ":", Color=t.Grid);
                    path = r.inertial;
                    limits = max(1.2, 1.1 * max(abs(path(:, 1:2)), [], "all"));
                    set(ax, XLim=[-limits limits], YLim=[-limits limits]);
                    title(ax, "Inertial frame");
                else
                    if params.showLpoints
                        plot(ax, r.L(:, 1), r.L(:, 2), "+", Color=t.series(4), MarkerSize=9, LineWidth=1.3);
                    end
                    [xr, yr] = viewRange(r.state(:, 1), r.state(:, 2), r.mu, params.showLpoints, r.L);
                    set(ax, XLim=xr, YLim=yr);
                    title(ax, "Rotating frame");
                end
                a.trails = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=1.4);
                a.bodies = scatter(ax, [NaN NaN], [NaN NaN], [220 90], [t.series(3); t.TextMuted], "filled", ...
                    MarkerEdgeColor=t.Text);
                a.body = plot(ax, NaN, NaN, "o", MarkerSize=7, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            end
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function T = figureEight()
% Chenciner–Montgomery figure-8 (Simó's initial conditions).
v3 = [-0.93240737 -0.86473146];
T = table([1; 1; 1], [0.97000436; -0.97000436; 0], [-0.24308753; 0.24308753; 0], zeros(3, 1), ...
    [-v3(1) / 2; -v3(1) / 2; v3(1)], [-v3(2) / 2; -v3(2) / 2; v3(2)], zeros(3, 1), ...
    VariableNames=["m" "x" "y" "z" "vx" "vy" "vz"]);
end

function sys = systemOf(p)
% Mass ratio, primary radii (in separations), names, and physical scales.
switch p.system
    case "earthmoon"
        sys = struct("mu", 0.01215058, "lengthKm", 384400, "dayPerUnit", 27.321661 / (2 * pi), ...
            "names", ["Earth" "Moon"], "label", "Earth–Moon");
        sys.radii = [6371 1737.4] / sys.lengthKm;
    case "sunearth"
        sys = struct("mu", 3.0035e-6, "lengthKm", 1.495978707e8, "dayPerUnit", 365.256363 / (2 * pi), ...
            "names", ["Sun" "Earth"], "label", "Sun–Earth");
        sys.radii = [695700 6371] / sys.lengthKm;
    case "sunjupiter"
        sys = struct("mu", 9.5388e-4, "lengthKm", 7.7857e8, "dayPerUnit", 4332.59 / (2 * pi), ...
            "names", ["Sun" "Jupiter"], "label", "Sun–Jupiter");
        sys.radii = [695700 69911] / sys.lengthKm;
    otherwise
        sys = struct("mu", p.mu, "lengthKm", NaN, "dayPerUnit", NaN, "names", ["Primary 1" "Primary 2"], ...
            "label", sprintf("μ = %.6g", p.mu));
        sys.radii = [0 0];
end
end

function [xr, yr] = viewRange(x, y, mu, withL, L)
% A square-ish view of the path, the primaries, and (if shown) L1–L5.
xs = [x; -mu; 1 - mu];
ys = [y; 0; 0];
if withL
    xs = [xs; L(:, 1)];
    ys = [ys; L(:, 2)];
end
pad = 0.08 * max([range2(xs), range2(ys), 0.2]);
xr = [min(xs) max(xs)] + [-pad pad];
yr = [min(ys) max(ys)] + [-pad pad];
end

function drawPrimaries(ax, at, sys, t)
sizes = [14 8];
colors = [t.series(3); t.TextMuted];
for k = 1:2
    plot(ax, at(k, 1), at(k, 2), "o", MarkerSize=sizes(k), MarkerFaceColor=colors(k, :), MarkerEdgeColor=t.Text);
    text(ax, at(k, 1), at(k, 2), "  " + sys.names(k), Color=t.Text, FontSize=t.FontSize.sm, ...
        VerticalAlignment="top");
end
end

function e = returnError(r)
% How far the final state is from the start (the whole state).
if r.isNBody
    first = [reshape(r.pos(1, :, :), 1, []), reshape(r.vel(1, :, :), 1, [])];
    last = [reshape(r.pos(end, :, :), 1, []), reshape(r.vel(end, :, :), 1, [])];
else
    first = r.state(1, :);
    last = r.state(end, :);
end
e = norm(last - first);
end

function label = timeLabel(r, simTime)
label = sprintf("t = %.3f", simTime);
if ~r.isNBody && isfinite(r.system.dayPerUnit)
    label = label + sprintf("  (%.1f days)", simTime * r.system.dayPerUnit);
end
end

function d = range2(values)
d = max(values(:)) - min(values(:));
end

function labels = modeNames(lambda, V)
%MODENAMES Saddle (its growing and its decaying direction), in-plane
%   oscillation (steady, growing, or decaying), or out-of-plane oscillation,
%   by where the eigenvector lives.
labels = strings(numel(lambda), 1);
for k = 1:numel(lambda)
    inPlane = norm(V([1 2 4 5], k));
    outOfPlane = norm(V([3 6], k));
    scale = max(abs(lambda(k)), realmin);
    if outOfPlane > inPlane
        labels(k) = "Out-of-plane oscillation";
    elseif abs(imag(lambda(k))) < 1e-6 * scale && real(lambda(k)) > 0
        labels(k) = "Saddle, growing direction";
    elseif abs(imag(lambda(k))) < 1e-6 * scale
        labels(k) = "Saddle, decaying direction";
    elseif real(lambda(k)) > 1e-6 * scale
        labels(k) = "Growing oscillation (unstable)";
    elseif real(lambda(k)) < -1e-6 * scale
        labels(k) = "Decaying oscillation";
    else
        labels(k) = "In-plane oscillation";
    end
end
end
