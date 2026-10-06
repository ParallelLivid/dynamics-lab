classdef ManeuversPlugin < dlab.core.TimeDomainPlugin
    %MANEUVERSPLUGIN Impulsive orbital maneuvers: Hohmann and bi-elliptic
    %   transfers, plane changes, phasing, and custom burn lists, planned
    %   analytically (planManeuver) and flown (propagateBurns).

    properties (Constant)
        Id = "maneuvers"
        Title = "Orbital Maneuvers"
        Category = "Aerospace"
        Summary = "Hohmann and bi-elliptic transfers, plane changes, and phasing: the Δv budget of a mission."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        Bodies = ["Earth" "Moon" "Mars" "Venus" "Mercury" "Jupiter"]
        PlaySeconds = 20
        FlashSeconds = 0.6            % of playback, around each burn
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(obj)
            P = @dlab.core.ParamSpec;
            C = @dlab.core.TableColumn;
            is = @(varargin) @(p) any(p.maneuver == string(varargin));
            specs = [
                P("body", Label="Central body", Type="choice", Default="Earth", Choices=obj.Bodies, Group="Mission", ...
                    Description="Sets μ and the radius the altitudes are measured from.")
                P("maneuver", Label="Maneuver", Type="choice", Default="hohmann", ...
                    Choices=["hohmann" "bielliptic" "plane" "combined" "phasing" "custom"], ...
                    ChoiceLabels=["Hohmann" "Bi-elliptic" "Plane" "Combined" "Phasing" "Custom"], Group="Mission", ...
                    Description="Hohmann: two burns between circular orbits. Bi-elliptic: three, out beyond the " + ...
                    "target and back. Plane: a pure inclination change. Combined: Hohmann with the plane change " + ...
                    "split optimally between its burns. Phasing: catch a target on the same orbit. Custom: " + ...
                    "your own list of burns.")
                P("alt1", Label="Starting altitude", Units="km", Default=300, Min=1, Max=1e7, Group="Orbits", ...
                    Description="A circular orbit; the start is at its ascending node.")
                P("inc1", Label="Starting inclination", Units="°", Default=0, Min=0, Max=180, Group="Orbits", ...
                    Description="From the body's equator (Cape Canaveral launches go into 28.5°).")
                P("alt2", Label="Target altitude", Units="km", Default=35786, Min=1, Max=1e7, Group="Orbits", ...
                    VisibleWhen=is("hohmann", "bielliptic", "combined"), ...
                    Description="The circular orbit to reach (geostationary: 35 786 km).")
                P("altB", Label="Intermediate apoapsis altitude", Units="km", Default=100000, Min=1, Max=1e8, ...
                    Group="Orbits", VisibleWhen=is("bielliptic", "hohmann", "combined"), ...
                    Description="The bi-elliptic transfer's far point (also used for the comparison in the Δv budget).")
                P("dInc", Label="Inclination change", Units="°", Default=0, Min=-180, Max=180, Group="Orbits", ...
                    VisibleWhen=is("plane", "combined"), Description="Negative lowers the inclination " + ...
                    "(−28.5° makes a Cape Canaveral orbit equatorial).")
                P("phaseAngle", Label="Target ahead by", Units="°", Default=30, Min=-180, Max=180, Group="Orbits", ...
                    VisibleWhen=is("phasing"), Description="Negative: the target is behind.")
                P("phasingRevs", Label="Phasing revolutions", Type="integer", Default=1, Min=1, Max=50, ...
                    Group="Orbits", VisibleWhen=is("phasing"), Description="Laps in the phasing orbit: more laps " + ...
                    "need a smaller change of orbit, so less Δv, but take longer.")
                P("burns", Label="Burns", Type="table", Group="Burns", MinRows=1, MaxRows=10, ...
                    VisibleWhen=is("custom"), Description="Each burn waits for its trigger after the previous one.", ...
                    Columns=[
                        C("at", Label="When", Type="choice", Choices=["time" "periapsis" "apoapsis" "ascending" "descending"])
                        C("value", Label="After (s) or nth", Min=0, Default=1)
                        C("prograde", Label="Prograde", Units="m/s", Default=0)
                        C("normal", Label="Normal", Units="m/s", Default=0)
                        C("radial", Label="Radial", Units="m/s", Default=0)
                    ], Default=table(["time"; "apoapsis"], [0; 1], [500; 500], [0; 0], [0; 0], ...
                        VariableNames=["at" "value" "prograde" "normal" "radial"]))
                P("coastAfter", Label="Coast after the last burn", Units="orbits", Default=1, Min=0, Max=100, ...
                    Group="Simulation", Description="How long to follow the final orbit, in its periods.")
                P("sampleStep", Label="Output step", Units="s", Default=60, Min=0.1, Max=1e6, Group="Simulation", ...
                    Description="Spacing of saved samples; the burns themselves are found exactly.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "LEO to GEO (Hohmann)", "Values", struct());
            list(end+1) = struct("Name", "LEO to GEO with plane change (from Cape Canaveral)", "Values", struct( ...
                "maneuver", "combined", "inc1", 28.5, "dInc", -28.5));
            list(end+1) = struct("Name", "Bi-elliptic beats Hohmann (r₂ = 20 r₁)", "Values", struct( ...
                "maneuver", "bielliptic", "alt2", 20 * 6671 - 6371, "altB", 40 * 6671 - 6371, "sampleStep", 300, ...
                "coastAfter", 0.5));
            list(end+1) = struct("Name", "Phasing: catch up 30°", "Values", struct("maneuver", "phasing", ...
                "alt1", 35786, "phaseAngle", 30, "phasingRevs", 1, "sampleStep", 120));
            list(end+1) = struct("Name", "Lunar-distance transfer", "Values", struct("alt2", 384400 - 6371, ...
                "sampleStep", 600, "coastAfter", 0.25));
            list(end+1) = struct("Name", "Mars orbit Hohmann (around Mars)", "Values", struct("body", "Mars", ...
                "alt1", 300, "alt2", 17032));
        end

        function result = solve(obj, p)
            body = dlab.physics.bodyConstants(p.body);
            burns = [];
            if p.maneuver == "custom"
                burns = dlab.core.TableColumn.toTable(obj.burnColumns(), p.burns);
            end
            plan = dlab.sims.maneuvers.planManeuver(struct("mu", body.mu, "R", body.radius, ...
                "type", char(p.maneuver), "alt1", p.alt1, "alt2", p.alt2, "altB", p.altB, "inc1", p.inc1, ...
                "dInc", p.dInc, "phaseAngle", p.phaseAngle, "phasingRevs", p.phasingRevs, "burns", burns));
            result = dlab.sims.maneuvers.propagateBurns(struct("mu", body.mu, "R", body.radius, ...
                "sampleStep", p.sampleStep, "coastAfter", p.coastAfter, "progressFcn", obj.progressMonitor()), plan);
            result.plan = plan;
            result.body = body;
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Transfer" "3-D view" "Δv budget" "Altitude and speed" "Elements"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.transfer = dlab.ui.axesIn(containers{"Transfer"}, t, Title="In the starting orbit's plane", ...
                XLabel="km", YLabel="km");
            obj.Ax.view3 = dlab.ui.axesIn(containers{"3-D view"}, t, Title="3-D view", XLabel="x (km)", ...
                YLabel="y (km)");
            zlabel(obj.Ax.view3, "z (km)");
            grid = uigridlayout(containers{"Δv budget"}, [1 2], Padding=0, ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.budget = dlab.ui.axesIn(grid, t, Column=1, Title="Δv per burn", YLabel="Δv (km/s)");
            obj.Ax.alternatives = dlab.ui.axesIn(grid, t, Column=2, Title="Alternatives", YLabel="Total Δv (km/s)");
            grid = uigridlayout(containers{"Altitude and speed"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.altitude = dlab.ui.axesIn(grid, t, Row=1, Title="Altitude", XLabel="Time (h)", YLabel="km");
            obj.Ax.speed = dlab.ui.axesIn(grid, t, Row=2, Title="Speed", XLabel="Time (h)", YLabel="km/s");
            grid = uigridlayout(containers{"Elements"}, [3 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.a = dlab.ui.axesIn(grid, t, Row=1, Title="Semi-major axis", XLabel="Time (h)", YLabel="km");
            obj.Ax.e = dlab.ui.axesIn(grid, t, Row=2, Title="Eccentricity", XLabel="Time (h)", YLabel="");
            obj.Ax.i = dlab.ui.axesIn(grid, t, Row=3, Title="Inclination", XLabel="Time (h)", YLabel="°");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Maneuver", XLabel="x (km)", YLabel="y (km)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            hours = r.t / 3600;
            [segments, burnRows] = segmentsOf(r);

            ax = obj.Ax.transfer;
            dlab.ui.clearAxes(ax);
            basis = planeBasis(params.inc1);
            [cx, cy] = dlab.ui.Schematic.circle([0 0], r.body.radius, 90);
            patch(ax, cx, cy, t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.6, DisplayName=params.body);
            inPlane = r.r * basis;
            for k = 1:numel(segments)
                rows = segments{k};
                plot(ax, inPlane(rows, 1), inPlane(rows, 2), Color=t.series(k), LineWidth=1.5, ...
                    DisplayName=segmentName(k, numel(segments), r.burnLog(1).time > r.t(1)));
            end
            scale = 0.15 * max(sqrt(sum(inPlane.^2, 2))) / max([arrayfun(@(b) norm(b.dvInertial), r.burnLog), eps]);
            for k = 1:numel(r.burnLog)
                b = r.burnLog(k);
                at = b.r * basis;
                arrow = b.dvInertial * basis * scale;
                plot(ax, at(1), at(2), "o", MarkerSize=8, MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Text, ...
                    HandleVisibility="off");
                plot(ax, at(1) + [0 arrow(1)], at(2) + [0 arrow(2)], Color=t.Warning, LineWidth=2, ...
                    HandleVisibility="off");
                text(ax, at(1), at(2), sprintf("  %d: %.3f km/s", k, norm(b.dvLocal)), Color=t.Text, ...
                    FontSize=t.FontSize.sm, VerticalAlignment="bottom");
            end
            if ~isempty(r.target)
                target = r.target * basis;
                plot(ax, target(:, 1), target(:, 2), ":", Color=t.TextMuted, DisplayName="Target");
            end
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            dlab.ui.legend(ax, t, "Location", "northeastoutside");

            ax = obj.Ax.view3;
            dlab.ui.clearAxes(ax);
            [sx, sy, sz] = sphere(30);
            R = r.body.radius;
            surf(ax, R * sx, R * sy, R * sz, FaceColor=t.Border, EdgeColor="none", FaceAlpha=0.7);
            for k = 1:numel(segments)
                rows = segments{k};
                plot3(ax, r.r(rows, 1), r.r(rows, 2), r.r(rows, 3), Color=t.series(k), LineWidth=1.4);
            end
            plot3(ax, r.r(burnRows, 1), r.r(burnRows, 2), r.r(burnRows, 3), "o", MarkerFaceColor=t.Warning, ...
                MarkerEdgeColor=t.Text);
            hold(ax, "off");
            axis(ax, "equal");
            view(ax, -30, 25);

            ax = obj.Ax.budget;
            dlab.ui.clearAxes(ax);
            dv = [r.plan.dv; r.plan.total];
            names = ["Burn " + (1:numel(r.plan.dv)), "Total"];
            bar(ax, 1:numel(dv), dv, FaceColor=t.series(1), EdgeColor="none");
            text(ax, 1:numel(dv), dv, compose("%.4f", dv), HorizontalAlignment="center", ...
                VerticalAlignment="bottom", Color=t.Text, FontSize=t.FontSize.sm);
            set(ax, XTick=1:numel(dv), XTickLabel=names);
            hold(ax, "off");

            ax = obj.Ax.alternatives;
            dlab.ui.clearAxes(ax);
            alt = r.plan.alternatives;
            values = [alt.hohmann alt.bielliptic alt.separate alt.combined];
            labels = ["Hohmann" "Bi-elliptic" "Hohmann + plane change at the top" "Combined (optimal split)"];
            show = isfinite(values);
            if any(show)
                bar(ax, 1:nnz(show), values(show), FaceColor=t.series(2), EdgeColor="none");
                text(ax, 1:nnz(show), values(show), compose("%.4f", values(show)), HorizontalAlignment="center", ...
                    VerticalAlignment="bottom", Color=t.Text, FontSize=t.FontSize.sm);
                set(ax, XTick=1:nnz(show), XTickLabel=labels(show));
            else
                text(ax, 0.5, 0.5, "No alternatives for this maneuver.", Units="normalized", ...
                    HorizontalAlignment="center", Color=t.TextMuted);
                set(ax, XTick=[]);
            end
            hold(ax, "off");

            ax = obj.Ax.altitude;
            dlab.ui.clearAxes(ax);
            plot(ax, hours, sqrt(sum(r.r.^2, 2)) - r.body.radius, Color=t.series(1), LineWidth=1.4);
            markBurns(ax, r, t);
            hold(ax, "off");
            ax = obj.Ax.speed;
            dlab.ui.clearAxes(ax);
            plot(ax, hours, sqrt(sum(r.v.^2, 2)), Color=t.series(2), LineWidth=1.4);
            markBurns(ax, r, t);
            hold(ax, "off");

            names = ["a" "e" "i"];
            for k = 1:3
                ax = obj.Ax.(names(k));
                dlab.ui.clearAxes(ax);
                values = r.elements(:, k);
                values(~isfinite(values) | (k == 1 & values < 0)) = NaN;
                plot(ax, hours, values, Color=t.series(k + 2), LineWidth=1.4);
                markBurns(ax, r, t);
                hold(ax, "off");
            end

            obj.setupAnimation(r, segments);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                basis = planeBasis(run.Params.inc1);
                inPlane = run.Result.r * basis;
                dlab.ui.overlayLine(obj.Ax.transfer, inPlane(:, 1), inPlane(:, 2), run);
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

        function rate = playbackRate(obj, r)
            rate = max(r.t(end) / obj.PlaySeconds, 1);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "craft")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            set(a.trail, XData=r.r(1:k, 1), YData=r.r(1:k, 2), ZData=r.r(1:k, 3));
            set(a.craft, XData=r.r(k, 1), YData=r.r(k, 2), ZData=r.r(k, 3));
            if ~isempty(r.target)
                set(a.target, XData=r.target(k, 1), YData=r.target(k, 2), ZData=r.target(k, 3));
            end
            window = obj.FlashSeconds * obj.playbackRate(r);
            times = [r.burnLog.time];
            near = find(abs(times - simTime) <= window, 1);
            if isempty(near)
                set(a.flash, Visible="off");
            else
                at = r.burnLog(near).r;
                set(a.flash, XData=at(1), YData=at(2), ZData=at(3), Visible="on");
            end
            a.readout.String = sprintf("t = %.2f h   altitude %.0f km   %.3f km/s", simTime / 3600, ...
                norm(r.r(k, :)) - r.body.radius, norm(r.v(k, :)));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.r(:, 1), r.r(:, 2), r.r(:, 3), r.v(:, 1), r.v(:, 2), r.v(:, 3), r.elements(:, 1), ...
                r.elements(:, 2), r.elements(:, 3), VariableNames=["time" "x" "y" "z" "vx" "vy" "vz" "a" "e" "i"]);
            T.Properties.VariableUnits = ["s" "km" "km" "km" "km/s" "km/s" "km/s" "km" "" "deg"];
        end

        function T = summaryTable(~, r)
            plan = r.plan;
            rows = cell(0, 3);
            for k = 1:numel(plan.dv)
                rows(end+1, :) = {sprintf("Burn %d Δv", k), plan.dv(k), "km/s"}; %#ok<AGROW>
            end
            rows(end+1, :) = {"Total Δv", plan.total, "km/s"};
            rows(end+1, :) = {"Flown Δv", sum(arrayfun(@(b) norm(b.dvInertial), r.burnLog)), "km/s"};
            if isfinite(plan.transferTime)
                rows(end+1, :) = {"Transfer time", plan.transferTime / 3600, "h"};
            end
            if r.params.maneuver ~= "custom" && r.params.maneuver ~= "phasing"
                rows(end+1, :) = {"Final a error (relative)", r.final.a / plan.target.a - 1, ""};
                rows(end+1, :) = {"Final eccentricity", r.final.e, ""};
                rows(end+1, :) = {"Final inclination error", r.final.i - plan.target.i, "°"};
            else
                rows(end+1:end+3, :) = {"Final a", r.final.a, "km"; "Final eccentricity", r.final.e, ""; ...
                    "Final inclination", r.final.i, "°"};
            end
            alt = plan.alternatives;
            if isfinite(alt.hohmann)
                rows(end+1, :) = {"Hohmann Δv", alt.hohmann, "km/s"};
                % Only with an intermediate apoapsis beyond both orbits (inside
                % the target the "bi-elliptic" transfer was the Hohmann: a saving of 0).
                if isfinite(alt.bielliptic)
                    rows(end+1, :) = {"Bi-elliptic saving", alt.hohmann - alt.bielliptic, "km/s"};
                end
            end
            if isfinite(alt.separate)
                rows(end+1, :) = {"Combined saving", alt.separate - alt.combined, "km/s"};
            end
            if isfinite(plan.split)
                rows(end+1, :) = {"Plane change at the first burn", plan.split, "°"};
            end
            if isfinite(r.miss)
                rows(end+1, :) = {"Rendezvous miss", r.miss, "km"};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function [note, level] = resultNote(~, r)
            [note, level] = deal(sprintf("total Δv %.4f km/s", r.plan.total), "success");
            if r.crashed
                [note, level] = deal("the path goes below the surface", "warning");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "LEO to GEO (Hohmann)", "Tab", "Transfer", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Impulsive burns between two-body coasts (ode45). Circular speed v = √(μ/r); on an " + ...
                "ellipse with semi-major axis a, v = √(μ (2/r − 1/a)) (vis-viva)."
                ""
                "Hohmann: two burns, half an ellipse between circular orbits r₁ and r₂."
                "Bi-elliptic: out to r_b first; cheaper than Hohmann when r₂/r₁ > 15.58 (for any r_b)."
                "Plane change: Δv = 2 v sin(Δi/2), cheapest where v is smallest; combined with the " + ...
                "Hohmann burns it costs less again."
                "Phasing: a slightly smaller or larger orbit for a whole number of turns, to catch a target."
            ], newline);
        end
    end

    methods (Access = private)
        function columns = burnColumns(obj)
            specs = obj.parameters();
            columns = specs(arrayfun(@(s) s.Name == "burns", specs)).Columns;
        end

        function setupAnimation(obj, r, segments)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            [sx, sy, sz] = sphere(30);
            R = r.body.radius;
            surf(ax, R * sx, R * sy, R * sz, FaceColor=t.Border, EdgeColor="none", FaceAlpha=0.8);
            for k = 1:numel(segments)
                rows = segments{k};
                plot3(ax, r.r(rows, 1), r.r(rows, 2), r.r(rows, 3), ":", Color=t.series(k), LineWidth=0.8);
            end
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=1.8);
            a.craft = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=8, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            a.target = plot3(ax, NaN, NaN, NaN, "s", MarkerSize=8, MarkerFaceColor=t.series(4), MarkerEdgeColor=t.Text);
            a.flash = plot3(ax, NaN, NaN, NaN, "p", MarkerSize=22, MarkerFaceColor=t.Warning, ...
                MarkerEdgeColor=t.Warning, Visible="off");
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            axis(ax, "equal");
            if r.params.inc1 == 0 && ~any(r.params.maneuver == ["plane" "combined" "custom"])
                view(ax, 0, 90);
            else
                view(ax, -30, 25);
            end
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function basis = planeBasis(inc1)
% The starting orbit's plane: along the node line, and 90° ahead in the plane.
i = deg2rad(inc1);
basis = [1 0; 0 cos(i); 0 sin(i)];
end

function [segments, burnRows] = segmentsOf(r)
% Sample rows before the first burn, between burns, and after the last.
times = [r.burnLog.time];
burnRows = arrayfun(@(time) find(r.t >= time, 1), times);
edges = unique([1, burnRows, numel(r.t)]);
segments = cell(1, numel(edges) - 1);
for k = 1:numel(edges) - 1
    segments{k} = edges(k):edges(k + 1);
end
if isempty(segments)
    segments = {1:numel(r.t)};
end
end

function name = segmentName(k, count, coastFirst)
if k == count
    name = "Final orbit";
elseif k == 1 && coastFirst
    name = "Before the first burn";
else
    name = sprintf("Transfer leg %d", k - coastFirst);
end
end

function markBurns(ax, r, t)
for b = r.burnLog
    xline(ax, b.time / 3600, ":", Color=t.Warning, HandleVisibility="off");
end
end
