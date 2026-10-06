classdef FlybyPlugin < dlab.core.TimeDomainPlugin
    %FLYBYPLUGIN Gravity assist: a spacecraft's hyperbolic pass of a planet,
    %   integrated in the planet's frame (simulateFlyby) and patched to
    %   heliocentric orbits before and after.

    properties (Constant)
        Id = "flyby"
        Title = "Gravity Assist"
        Category = "Aerospace"
        Summary = "A planetary flyby: no energy gained in the planet's frame, a slingshot in the Sun's."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        PlaySeconds = 20
        AU = 149597870.7          % km (IAU 2012)
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            specs = [
                P("planet", Label="Planet", Type="choice", Default="Jupiter", ...
                    Choices=dlab.sims.flyby.planetData("names"), Group="Encounter", ...
                    Description="Sets the planet's gravity, size, and circular orbit around the Sun.")
                P("vinf", Label="Excess speed v∞", Units="km/s", Default=10.7, Min=0.1, Max=60, Group="Encounter", ...
                    Description="The speed relative to the planet far from it, before and after the pass.")
                P("alpha", Label="Direction of v∞", Units="°", Default=-120, Min=-180, Max=180, Group="Encounter", ...
                    Description="The incoming v∞ measured from the planet's velocity: 0 along it, 180 straight " + ...
                    "back, +90 toward the Sun, −90 away from it. A spacecraft climbing out from the Sun, " + ...
                    "slower than the planet, arrives between −90 and −180.")
                P("altitude", Label="Periapsis altitude", Units="km", Default=277400, Min=0, Max=1e8, ...
                    Group="Encounter", Description="The closest approach above the planet's mean radius.")
                P("pass", Label="Pass", Type="choice", Default="behind", Choices=["behind" "ahead"], ...
                    ChoiceLabels=["Behind" "Ahead"], ...
                    Group="Encounter", Description="Which side of the planet the periapsis lies on, " + ...
                    "seen along its orbit: behind it (its trailing side) the spacecraft gains speed, ahead " + ...
                    "of it it loses speed. This sets which way v∞ turns.")
                P("durationFactor", Label="Duration factor", Units="r_p/v∞", Default=12, Min=2, Max=1e6, ...
                    Group="Simulation", Description="The run lasts from this many r_p/v∞ before periapsis " + ...
                    "to as many after (it starts roughly this many periapsis radii away), at most the " + ...
                    "crossing of the sphere of influence.")
                P("showSoi", Label="Mark the sphere of influence", Type="logical", Default=false, ...
                    Group="Display", Display=true, ...
                    Description="Zooms the planet-frame plot out to the sphere of influence.")
                P("showInset", Label="Heliocentric view in the animation", Type="logical", Default=true, ...
                    Group="Display", Display=true, Description="A small view of the orbits around the Sun " + ...
                    "beside the flyby.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Jupiter assist (Voyager-like)", "Values", struct());
            list(end+1) = struct("Name", "Venus assist (Cassini-like)", "Values", struct("planet", "Venus", ...
                "vinf", 6.6, "alpha", -77, "altitude", 284, "pass", "behind"));
            list(end+1) = struct("Name", "Earth flyby gaining speed (Galileo-like)", "Values", struct( ...
                "planet", "Earth", "vinf", 8.8, "alpha", -100, "altitude", 960, "pass", "behind"));
            list(end+1) = struct("Name", "Slowing down: passing ahead of Venus", "Values", struct( ...
                "planet", "Venus", "vinf", 6.6, "alpha", -77, "altitude", 284, "pass", "ahead"));
            list(end+1) = struct("Name", "Close Jupiter pass (large turning angle)", "Values", struct( ...
                "planet", "Jupiter", "vinf", 6.6, "alpha", -148, "altitude", 4000, "pass", "behind"));
            list(end+1) = struct("Name", "Mars flyby (a small planet turns less)", "Values", struct( ...
                "planet", "Mars", "vinf", 4.2, "alpha", -125, "altitude", 300, "pass", "behind"));
        end

        function result = solve(obj, p)
            d = dlab.sims.flyby.planetData(p.planet);
            q = struct("mu", d.mu, "R", d.radius, "aOrbit", d.a, "muSun", d.muSun, "vinf", p.vinf, ...
                "alpha", p.alpha, "altitude", p.altitude, "pass", char(p.pass), ...
                "durationFactor", p.durationFactor, "progressFcn", obj.progressMonitor());
            result = dlab.sims.flyby.simulateFlyby(q);
            result.planet = d;
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Planet frame" "Velocity diagram" "Heliocentric speed" "Heliocentric orbits"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.planet = dlab.ui.axesIn(containers{"Planet frame"}, t, Title="In the planet's frame", ...
                XLabel="Along the planet's motion (planet radii)", YLabel="Toward the Sun (planet radii)");
            obj.Ax.vectors = dlab.ui.axesIn(containers{"Velocity diagram"}, t, Title="Velocities", ...
                XLabel="Along the planet's motion (km/s)", YLabel="Toward the Sun (km/s)");
            obj.Ax.speed = dlab.ui.axesIn(containers{"Heliocentric speed"}, t, Title="Heliocentric speed", ...
                XLabel="Time from periapsis (days)", YLabel="km/s");
            obj.Ax.helio = dlab.ui.axesIn(containers{"Heliocentric orbits"}, t, Title="Around the Sun", ...
                XLabel="x (AU)", YLabel="y (AU)");
        end

        function buildAnimation(obj, parent, theme)
            grid = uigridlayout(parent, [1 2], Padding=0, ColumnSpacing=theme.Spacing.sm, ...
                BackgroundColor=theme.AxesBackground, ColumnWidth={'3x', '1x'});
            main = dlab.ui.axesIn(grid, theme, Column=1, Title="Flyby (planet frame, to scale)", ...
                XLabel="Planet radii", YLabel="Planet radii");
            side = dlab.ui.axesIn(grid, theme, Column=2, Title="Around the Sun", XLabel="AU", YLabel="AU");
            disableDefaultInteractivity(main);
            disableDefaultInteractivity(side);
            obj.Anim = struct("grid", grid, "axes", main, "side", side);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            obj.drawPlanetFrame(r, params);
            obj.drawVectors(r);
            obj.drawSpeed(r);
            obj.drawOrbits(r);
            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                res = run.Result;
                dlab.ui.overlayLine(obj.Ax.planet, res.r(:, 1) / res.R, res.r(:, 2) / res.R, run);
                path = res.after.path / obj.AU;
                dlab.ui.overlayLine(obj.Ax.helio, path(:, 1), path(:, 2), run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            delete(allchild(obj.Anim.axes));
            delete(allchild(obj.Anim.side));
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, r)
            rate = r.t(end) / obj.PlaySeconds;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "craft")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            R = r.R;
            set(a.trail, XData=r.r(1:k, 1) / R, YData=r.r(1:k, 2) / R);
            set(a.craft, XData=r.r(k, 1) / R, YData=r.r(k, 2) / R);
            [lx, ly, hx, hy] = dlab.ui.Schematic.arrow(r.r(k, :) / R, a.arrowScale * r.v(k, :), a.headSize);
            set(a.arrowLine, XData=lx, YData=ly);
            set(a.arrowHead, XData=hx, YData=hy);
            a.readout.String = sprintf("t − t_p = %+.2f d   r = %.1f R   v = %.2f km/s   heliocentric %.2f km/s", ...
                r.tRel(k) / 86400, r.rMag(k) / R, r.speed(k), r.speedHelio(k));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.tRel, r.r(:, 1), r.r(:, 2), r.v(:, 1), r.v(:, 2), r.rMag, r.speed, r.speedHelio, ...
                VariableNames=["time" "time_from_periapsis" "x" "y" "vx" "vy" "distance" "speed" ...
                "heliocentric_speed"]);
            T.Properties.VariableUnits = ["s" "s" "km" "km" "km/s" "km/s" "km" "km/s" "km/s"];
        end

        function T = summaryTable(obj, r)
            au = obj.AU;
            rows = {
                "Turning angle (integrated)", rad2deg(r.deltaNumeric), "°", "%.6f"
                "Turning angle (analytic)", rad2deg(r.deltaAnalytic), "°", "%.6f"
                "Flyby Δv", norm(r.dv), "km/s", "%.4f"
                "Δv = 2 v∞ sin(δ/2)", r.dvAnalytic, "km/s", "%.4f"
                "Planet-frame speed change", norm(r.vInfOut) - r.vinf, "km/s", "%.2e"
                "Heliocentric speed before", r.before.speed, "km/s", "%.4f"
                "Heliocentric speed after", r.after.speed, "km/s", "%.4f"
                "Speed gained", r.after.speed - r.before.speed, "km/s", "%+.4f"
                "Orbital energy change", r.energyChange, "km²/s²", "%+.3f"
                "Perihelion before", r.before.perihelion / au, "AU", "%.4f"
                "Aphelion before", r.before.aphelion / au, "AU", "%.4f"
                "Perihelion after", r.after.perihelion / au, "AU", "%.4f"
                "Aphelion after", r.after.aphelion / au, "AU", "%.4f"
                "Eccentricity after", r.after.e, "", "%.4f"
                "Closest approach", r.closest, "km", "%.1f"
                "Closest altitude", r.closest - r.R, "km", "%.1f"
                "Hyperbola eccentricity", r.e, "", "%.5f"
                "Periapsis speed", r.vPeri, "km/s", "%.4f"
                "Planet's orbital speed", r.Vp, "km/s", "%.4f"
                "Sphere of influence", r.rSoi, "km", "%.4g"
            };
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                VariableNames=["Quantity" "Value" "Units" "Format"]);
            T.Display = strings(height(T), 1);
            T.Display(~isfinite(T.Value)) = "unbound: leaves the Sun";
        end

        function [note, level] = resultNote(~, r)
            gained = r.after.speed - r.before.speed;
            [note, level] = deal(sprintf("δ = %.2f°, heliocentric speed %+.3f km/s", rad2deg(r.deltaAnalytic), ...
                gained), "success");
            if r.params.pass == "behind" && gained < 0
                [note, level] = deal("v∞ points almost along the planet's motion: either side loses speed", ...
                    "warning");
            elseif ~r.after.bound && r.before.bound
                note = note + ", now escaping the Sun";
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Jupiter assist (Voyager-like)", "Tab", "Planet frame", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Planet frame: two-body motion r̈ = −μ r/|r|³ (ode113, tolerance 10⁻¹²) on a hyperbola " + ...
                "with excess speed v∞ and periapsis r_p. Energy is conserved there: v∞ only turns, by"
                "  δ = 2 asin(1 / (1 + r_p v∞²/μ)),   so   Δv = 2 v∞ sin(δ/2)."
                ""
                "Sun frame (patched conic): the planet moves on a circle at V_p = √(μ_Sun/a). Before the " + ...
                "pass the spacecraft's velocity is V_p + v∞,in, after it V_p + v∞,out, and its energy " + ...
                "per unit mass changes by V_p · (v∞,out − v∞,in)."
                "Passing behind the planet turns v∞ toward the planet's motion (a gain); ahead, away " + ...
                "from it (a loss). The orbits before and after follow from the vis-viva equation."
                ""
                "Sphere of influence: r_SOI = a (m/M)^(2/5). Orbital radii: NASA Planetary Fact Sheet."
            ], newline);
        end
    end

    methods (Access = private)
        function drawPlanetFrame(obj, r, params)
            t = obj.Theme;
            ax = obj.Ax.planet;
            dlab.ui.clearAxes(ax);
            R = r.R;
            name = r.planet.name;
            [cx, cy] = dlab.ui.Schematic.circle([0 0], 1, 120);
            patch(ax, cx, cy, t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.8, DisplayName=name + " (to scale)");
            span = max(r.rMag) / R;
            if params.showSoi
                [sx, sy] = dlab.ui.Schematic.circle([0 0], r.rSoi / R, 240);
                plot(ax, sx, sy, ":", Color=t.series(4), LineWidth=1.2, DisplayName="Sphere of influence");
                plot(ax, r.soiPath(:, 1) / R, r.soiPath(:, 2) / R, ":", Color=t.series(1), ...
                    DisplayName="Path to the sphere's edge");
                span = r.rSoi / R;
            end
            c = r.center / R;
            inHat = r.vInfIn / r.vinf;
            outHat = r.vInfOut / norm(r.vInfOut);
            plot(ax, [c(1) - 1.2 * span * inHat(1), c(1), c(1) + 1.2 * span * outHat(1)], ...
                [c(2) - 1.2 * span * inHat(2), c(2), c(2) + 1.2 * span * outHat(2)], "--", Color=t.TextMuted, ...
                DisplayName="Asymptotes");
            plot(ax, r.r(:, 1) / R, r.r(:, 2) / R, Color=t.series(1), LineWidth=1.8, DisplayName="Spacecraft");
            plot(ax, r.r(1, 1) / R, r.r(1, 2) / R, "s", MarkerSize=7, MarkerFaceColor=t.AxesBackground, ...
                MarkerEdgeColor=t.series(1), LineWidth=1.5, DisplayName="Start");
            peri = r.rp * r.eHat / R;
            plot(ax, peri(1), peri(2), "o", MarkerSize=7, MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Text, ...
                DisplayName="Periapsis");
            text(ax, peri(1), peri(2), sprintf("  periapsis, %.0f km up", r.rp - R), Color=t.Text, FontSize=t.FontSize.sm, ...
                VerticalAlignment="bottom");
            text(ax, 0.02, 0.03, "→ the planet's motion     ↑ the Sun", Units="normalized", Color=t.TextMuted, ...
                FontSize=t.FontSize.sm, VerticalAlignment="bottom");
            hold(ax, "off");
            if params.showSoi
                [xr, yr] = deal(1.1 * span * [-1 1]);
            else
                xs = [r.r(:, 1) / R; -1; 1];
                ys = [r.r(:, 2) / R; -1; 1];
                pad = 0.08 * max(max(xs) - min(xs), max(ys) - min(ys));
                [xr, yr] = deal([min(xs) max(xs)] + [-pad pad], [min(ys) max(ys)] + [-pad pad]);
            end
            set(ax, XLim=xr, YLim=yr);
            daspect(ax, [1 1 1]);
            title(ax, sprintf("%s frame: δ = %.3f° (analytic %.3f°)", name, rad2deg(r.deltaNumeric), ...
                rad2deg(r.deltaAnalytic)));
            dlab.ui.legend(ax, t, "Location", "northeastoutside");
        end

        function drawVectors(obj, r)
            t = obj.Theme;
            ax = obj.Ax.vectors;
            dlab.ui.clearAxes(ax);
            P = [r.Vp 0];
            inTip = P + r.vInfIn;
            outTip = P + r.vInfOut;
            head = 0.05 * max([r.Vp, norm(inTip), norm(outTip)]);
            [cx, cy] = dlab.ui.Schematic.circle(P, r.vinf, 120);
            plot(ax, cx, cy, ":", Color=t.Grid, DisplayName="|v∞| (any turn stays on it)");
            drawArrow(ax, [0 0], P, t.TextMuted, 2, head, "V_p: the planet");
            drawArrow(ax, [0 0], inTip, t.series(2), 1.4, head, "Heliocentric before");
            drawArrow(ax, [0 0], outTip, t.series(1), 1.4, head, "Heliocentric after");
            drawArrow(ax, P, r.vInfIn, t.series(2), 2.4, head, "v∞ in");
            drawArrow(ax, P, r.vInfOut, t.series(1), 2.4, head, "v∞ out");
            drawArrow(ax, inTip, r.dv, t.series(4), 2, head, "Δv");
            labels = {inTip, sprintf("  %.2f km/s", norm(inTip)); outTip, sprintf("  %.2f km/s", norm(outTip))};
            for k = 1:2
                text(ax, labels{k, 1}(1), labels{k, 1}(2), labels{k, 2}, Color=t.Text, FontSize=t.FontSize.sm);
            end
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            title(ax, sprintf("v∞ turns by %.2f°: Δv = %.3f km/s, heliocentric %.2f → %.2f km/s", ...
                rad2deg(r.deltaNumeric), norm(r.dv), r.before.speed, r.after.speed));
            dlab.ui.legend(ax, t, "Location", "northeastoutside");
        end

        function drawSpeed(obj, r)
            t = obj.Theme;
            ax = obj.Ax.speed;
            dlab.ui.clearAxes(ax);
            passage = r.timeline;
            days = passage.t / 86400;
            names = ["Before: around the Sun" "Inside the sphere of influence" "After: around the Sun"];
            colors = [t.series(2); t.series(4); t.series(1)];
            for k = 1:3
                rows = passage.phase == k;
                plot(ax, days(rows), passage.speed(rows), Color=colors(k, :), LineWidth=1.5, DisplayName=names(k));
            end
            plot(ax, r.tRel / 86400, r.speedHelio, Color=colors(2, :), LineWidth=3.5, DisplayName="The integrated run");
            xline(ax, [-1 1] * r.tSoi / 86400, ":", Color=t.TextMuted, HandleVisibility="off");
            yline(ax, sqrt(2) * r.Vp, "--", "Escape from the Sun", Color=t.Danger, LabelHorizontalAlignment="left", ...
                HandleVisibility="off");
            hold(ax, "off");
            title(ax, sprintf("Heliocentric speed: %.3f → %.3f km/s (%+.3f)", r.before.speed, r.after.speed, ...
                r.after.speed - r.before.speed));
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function drawOrbits(obj, r)
            t = obj.Theme;
            ax = obj.Ax.helio;
            dlab.ui.clearAxes(ax);
            au = obj.AU;
            a = r.aOrbit / au;
            [cx, cy] = dlab.ui.Schematic.circle([0 0], a, 240);
            plot(ax, cx, cy, ":", Color=t.TextMuted, DisplayName=r.planet.name + "'s orbit");
            plot(ax, r.before.path(:, 1) / au, r.before.path(:, 2) / au, "--", Color=t.series(2), LineWidth=1.4, ...
                DisplayName="Before");
            plot(ax, r.after.path(:, 1) / au, r.after.path(:, 2) / au, Color=t.series(1), LineWidth=1.8, ...
                DisplayName="After");
            plot(ax, 0, 0, "o", MarkerSize=12, MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Text, DisplayName="Sun");
            plot(ax, 0, -a, "o", MarkerSize=8, MarkerFaceColor=t.series(3), MarkerEdgeColor=t.Text, ...
                DisplayName="Encounter");
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            title(ax, sprintf("Perihelion–aphelion: %s → %s AU", orbitSpan(r.before, au), orbitSpan(r.after, au)));
            dlab.ui.legend(ax, t, "Location", "northeastoutside");
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            side = obj.Anim.side;
            dlab.ui.clearAxes(ax);
            dlab.ui.clearAxes(side);
            a = struct("grid", obj.Anim.grid, "axes", ax, "side", side);
            R = r.R;
            [cx, cy] = dlab.ui.Schematic.circle([0 0], 1, 120);
            patch(ax, cx, cy, t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.8);
            plot(ax, r.r(:, 1) / R, r.r(:, 2) / R, ":", Color=t.series(1), LineWidth=0.8);
            span = 1.1 * max(r.rMag) / R;
            a.headSize = 0.04 * span;
            a.arrowScale = 0.15 * span / r.vPeri;
            a.trail = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=1.8);
            a.arrowLine = plot(ax, NaN, NaN, Color=t.Warning, LineWidth=1.6);
            a.arrowHead = patch(ax, NaN, NaN, t.Warning, EdgeColor="none");
            a.craft = plot(ax, NaN, NaN, "o", MarkerSize=8, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            text(ax, 0.01, 0.02, "→ the planet's motion   ↑ the Sun", Units="normalized", Color=t.TextMuted, ...
                FontSize=t.FontSize.sm, VerticalAlignment="bottom");
            hold(ax, "off");
            set(ax, XLim=[-span span], YLim=[-span span]);
            daspect(ax, [1 1 1]);
            title(ax, sprintf("%s flyby (planet frame, to scale)", r.planet.name));

            au = obj.AU;
            orbitRadius = r.aOrbit / au;
            [cx, cy] = dlab.ui.Schematic.circle([0 0], orbitRadius, 240);
            plot(side, cx, cy, ":", Color=t.TextMuted);
            plot(side, r.before.path(:, 1) / au, r.before.path(:, 2) / au, "--", Color=t.series(2), LineWidth=1.2);
            plot(side, r.after.path(:, 1) / au, r.after.path(:, 2) / au, Color=t.series(1), LineWidth=1.4);
            plot(side, 0, 0, "o", MarkerSize=9, MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Text);
            plot(side, 0, -orbitRadius, "o", MarkerSize=6, MarkerFaceColor=t.series(3), MarkerEdgeColor=t.Text);
            hold(side, "off");
            daspect(side, [1 1 1]);
            if params.showInset
                a.grid.ColumnWidth = {'3x', '1x'};
                side.Visible = "on";
            else
                a.grid.ColumnWidth = {'1x', 0};
                side.Visible = "off";
            end
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function drawArrow(ax, from, vector, color, width, head, name)
[lx, ly, hx, hy] = dlab.ui.Schematic.arrow(from, vector, head);
plot(ax, lx, ly, Color=color, LineWidth=width, DisplayName=name);
patch(ax, hx, hy, color, EdgeColor="none", HandleVisibility="off");
end

function label = orbitSpan(orbit, au)
if orbit.bound
    label = sprintf("%.3f–%.3f", orbit.perihelion / au, orbit.aphelion / au);
else
    label = sprintf("%.3f–∞", orbit.perihelion / au);
end
end
