classdef RocketPlugin < dlab.core.TimeDomainPlugin
    %ROCKETPLUGIN A multi-stage rocket from the pad toward orbit: gravity
    %   turn, max-Q, staging, and the Δv budget with gravity, drag, and
    %   steering losses. Solved by simulateAscent.

    properties (Constant)
        Id = "rocket"
        Title = "Rocket Ascent"
        Category = "Aerospace"
        Summary = "Launch to orbit: gravity turn, max-Q, staging, and where the Δv goes."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        EarthRadius = 6371e3
        PlaySeconds = 30
        FlashSeconds = 1.5           % of playback
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
            specs = [
                P("stages", Label="Stages", Type="table", Group="Vehicle", MinRows=1, MaxRows=3, ...
                    Description="From the bottom up. Each stage drops when its propellant runs out.", Columns=[
                        C("dry", Label="Dry mass", Units="kg", Min=0, MinInclusive=false, Default=1000)
                        C("prop", Label="Propellant", Units="kg", Min=0, MinInclusive=false, Default=10000)
                        C("thrust", Label="Thrust (vacuum)", Units="kN", Min=0, MinInclusive=false, Default=200)
                        C("ispVac", Label="Isp vacuum", Units="s", Min=1, Default=320)
                        C("ispSl", Label="Isp sea level", Units="s", Min=1, Default=280)
                        C("delay", Label="Coast before ignition", Units="s", Min=0, Default=0)
                    ], Default=launcherStages())
                P("payload", Label="Payload", Units="kg", Default=15000, Min=0, Max=1e7, Group="Vehicle", ...
                    Description="Carried to the end, on top of the last stage.")
                P("diameter", Label="Diameter", Units="m", Default=3.7, Min=0.05, Max=50, Group="Vehicle", ...
                    Description="Sets the frontal area for drag.")
                P("cdScale", Label="Drag scale", Default=1, Min=0, Max=10, Group="Vehicle", ...
                    Description="Multiplies a generic Cd(Mach) curve (0.3 subsonic, 0.6 just above Mach 1). 0: no drag.")
                P("kickAltitude", Label="Pitch-over altitude", Units="m", Default=300, Min=0, Max=1e6, Group="Guidance", ...
                    Description="The rocket rises straight up to here, then pitches over.")
                P("kickAngle", Label="Pitch-over angle", Units="°", Default=7.5, Min=0, Max=60, Group="Guidance", ...
                    Description="Tilt from vertical over 5 s; then the first stage follows a gravity turn.")
                P("usePitchProgram", Label="Fly a pitch program instead", Type="logical", Default=false, Group="Guidance", ...
                    Description="Steer every stage by a flight-path angle against time, instead of the gravity turn " + ...
                    "and the upper stages' climb control.")
                P("pitchProgram", Label="Flight-path angle", Type="schedule", Units="°", Default=90, Min=-10, Max=90, ...
                    Group="Guidance", VisibleWhen=@(p) p.usePitchProgram, Description="Thrust angle above the horizon.")
                P("cutoffAtTarget", Label="Cut off at the target orbit", Type="logical", Default=true, Group="Mission", ...
                    Description="Stop the last stage when it has the energy of a circular orbit at the target " + ...
                    "altitude (or, with one stage, an apoapsis there); otherwise burn everything.")
                P("targetApoapsis", Label="Target altitude", Units="km", Default=200, Min=50, Max=1e5, Group="Mission", ...
                    VisibleWhen=@(p) p.cutoffAtTarget, Description="The orbit's altitude to aim for.")
                P("circularize", Label="Circularize at the apoapsis", Type="logical", Default=true, Group="Mission", ...
                    VisibleWhen=@(p) p.cutoffAtTarget, Description="With the last stage's remaining propellant.")
                P("rotation", Label="Launch east with the Earth's rotation", Type="logical", Default=false, ...
                    Group="Mission", Description="Start with the ground's eastward speed (the air turns along).")
                P("latitude", Label="Launch latitude", Units="°", Default=28.5, Min=0, Max=90, Group="Mission", ...
                    VisibleWhen=@(p) p.rotation, Description="The ground moves east at 465 cos(latitude) m/s " + ...
                    "(408 m/s at Cape Canaveral's 28.5°).")
                P("throttle", Label="Throttle", Type="schedule", Default=1, Min=0, Max=1, Group="Throttle", ...
                    Description="A dip around max-Q (a throttle bucket) lowers the peak aerodynamic load.")
                P("maxTime", Label="Time limit", Units="s", Default=2000, Min=1, Max=1e5, Group="Simulation", ...
                    MarksCustom=false, Description="The run ends here if nothing else ends it first " + ...
                    "(after a cutoff, the coast to the apoapsis may go on past it).")
                P("dt", Label="Output step", Units="s", Default=1, Min=0.01, Max=100, Group="Simulation", ...
                    Description="Spacing of saved samples; ode45 picks its own steps, and events are found exactly.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            list = struct("Name", {}, "Values", {});
            sounding = table(300, 1200, 60, 260, 230, 0, VariableNames=["dry" "prop" "thrust" "ispVac" "ispSl" "delay"]);
            list(end+1) = struct("Name", "Sounding rocket (single stage, vertical)", "Values", struct( ...
                "stages", sounding, "payload", 100, "diameter", 0.5, "kickAngle", 0, "cutoffAtTarget", false, ...
                "maxTime", 700, "dt", 0.5));
            list(end+1) = struct("Name", "Small launcher to LEO (2 stages)", "Values", struct());
            heavy = table([131000; 36000; 11000], [2160000; 444000; 107000], [38700; 5100; 1000], [304; 421; 421], ...
                [263; 200; 200], [0; 2; 2], VariableNames=["dry" "prop" "thrust" "ispVac" "ispSl" "delay"]);
            list(end+1) = struct("Name", "Heavy launcher, 3 stages (Saturn V-like, approximate)", "Values", struct( ...
                "stages", heavy, "payload", 45000, "diameter", 10.1, "kickAltitude", 500, "kickAngle", 2, ...
                "targetApoapsis", 185, "maxTime", 1200));
            list(end+1) = struct("Name", "Too steep: gravity-loss demo", "Values", struct("kickAngle", 4));
            list(end+1) = struct("Name", "Too shallow: drag-loss demo", "Values", struct("kickAngle", 14));
            list(end+1) = struct("Name", "Max-Q throttle bucket", "Values", struct("kickAngle", 5, ...
                "throttle", S("pulse", Value=1, Amplitude=-0.3, Start=40, Width=35)));
        end

        function result = solve(obj, p)
            target = Inf;
            if p.cutoffAtTarget
                target = p.targetApoapsis;
            end
            program = [];
            if p.usePitchProgram
                program = dlab.core.Schedule.toFunction(p.pitchProgram, [-10 90]);
            end
            q = struct("stages", dlab.core.TableColumn.toTable(obj.stageColumns(), p.stages), ...
                "payload", p.payload, "diameter", p.diameter, "cdScale", p.cdScale, ...
                "kickAltitude", p.kickAltitude, "kickAngle", p.kickAngle, "pitchProgram", program, ...
                "throttle", dlab.core.Schedule.toFunction(p.throttle, [0 1]), "targetApoapsis", target, ...
                "circularize", p.cutoffAtTarget && p.circularize, "latitude", p.latitude, ...
                "rotation", logical(p.rotation), "gravity", true, "maxTime", p.maxTime, "dt", p.dt, ...
                "progressFcn", obj.progressMonitor());
            result = dlab.sims.rocket.simulateAscent(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Trajectory" "Altitude and speed" "Dynamic pressure" "Acceleration" "Mass and staging" ...
                "Δv budget" "Orbit"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.trajectory = dlab.ui.axesIn(containers{"Trajectory"}, t, Title="Altitude against downrange", ...
                XLabel="Downrange (km)", YLabel="Altitude (km)");
            grid = uigridlayout(containers{"Altitude and speed"}, [3 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.altitude = dlab.ui.axesIn(grid, t, Row=1, Title="Altitude", XLabel="Time (s)", YLabel="km");
            obj.Ax.speed = dlab.ui.axesIn(grid, t, Row=2, Title="Speed", XLabel="Time (s)", YLabel="m/s");
            obj.Ax.mach = dlab.ui.axesIn(grid, t, Row=3, Title="Mach number", XLabel="Time (s)", YLabel="");
            obj.Ax.q = dlab.ui.axesIn(containers{"Dynamic pressure"}, t, Title="Dynamic pressure q = ½ρv²", ...
                XLabel="Time (s)", YLabel="kPa");
            obj.Ax.g = dlab.ui.axesIn(containers{"Acceleration"}, t, Title="Sensed acceleration", ...
                XLabel="Time (s)", YLabel="g");
            obj.Ax.mass = dlab.ui.axesIn(containers{"Mass and staging"}, t, Title="Mass", XLabel="Time (s)", ...
                YLabel="t");
            obj.Ax.budget = dlab.ui.axesIn(containers{"Δv budget"}, t, Title="Δv budget", YLabel="m/s");
            obj.Ax.orbit = dlab.ui.axesIn(containers{"Orbit"}, t, Title="The orbit after cutoff", ...
                XLabel="km", YLabel="km");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Ascent", XLabel="km", YLabel="km");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, ~)
            obj.Result = r;
            t = obj.Theme;

            ax = obj.Ax.trajectory;
            dlab.ui.clearAxes(ax);
            plot(ax, r.downrange / 1e3, r.h / 1e3, Color=t.series(1), LineWidth=1.6);
            far = max(r.downrange) / 1e3;
            for group = eventGroups(r)
                k = group.index;
                x = r.downrange(k) / 1e3;
                plot(ax, x, r.h(k) / 1e3, "o", MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Text);
                if far > 0 && x > 0.7 * far       % near the right edge: the label goes to the left
                    text(ax, x, r.h(k) / 1e3, group.label + "  ", Color=t.Text, FontSize=t.FontSize.sm, ...
                        HorizontalAlignment="right", VerticalAlignment="bottom");
                else
                    text(ax, x, r.h(k) / 1e3, "  " + group.label, Color=t.Text, FontSize=t.FontSize.sm);
                end
            end
            iq = maxQIndex(r);
            plot(ax, r.downrange(iq) / 1e3, r.h(iq) / 1e3, "d", MarkerFaceColor=t.Danger, MarkerEdgeColor=t.Text);
            text(ax, r.downrange(iq) / 1e3, r.h(iq) / 1e3, "Max-Q  ", Color=t.Danger, FontSize=t.FontSize.sm, ...
                HorizontalAlignment="right");      % the events are labelled on the right
            hold(ax, "off");

            ax = obj.Ax.altitude;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.h / 1e3, Color=t.series(1), LineWidth=1.4);
            markEvents(ax, r, t);
            hold(ax, "off");
            ax = obj.Ax.speed;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.speed, Color=t.series(2), LineWidth=1.4, DisplayName="Inertial");
            plot(ax, r.t, r.airspeed, "--", Color=t.series(3), LineWidth=1.2, DisplayName="Relative to the air");
            markEvents(ax, r, t);
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "northwest");
            ax = obj.Ax.mach;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.mach, Color=t.series(4), LineWidth=1.4);
            hold(ax, "off");

            ax = obj.Ax.q;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.q / 1e3, Color=t.series(1), LineWidth=1.5);
            plot(ax, r.t(iq), r.q(iq) / 1e3, "d", MarkerFaceColor=t.Danger, MarkerEdgeColor=t.Text);
            text(ax, r.t(iq), r.q(iq) / 1e3, sprintf("  Max-Q %.1f kPa at %.1f km", r.q(iq) / 1e3, r.h(iq) / 1e3), ...
                Color=t.Text, FontSize=t.FontSize.sm);
            hold(ax, "off");
            xlim(ax, [0 max(r.t(find(r.q > 0.001 * max(r.q), 1, "last")), 1)]);

            ax = obj.Ax.g;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.gload, Color=t.series(2), LineWidth=1.4);
            markEvents(ax, r, t);
            hold(ax, "off");

            ax = obj.Ax.mass;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.mass / 1e3, Color=t.series(5), LineWidth=1.5);
            markEvents(ax, r, t);
            hold(ax, "off");
            set(ax, YScale="log");

            obj.drawBudget(r);
            obj.drawOrbit(r);
            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.trajectory, run.Result.downrange / 1e3, run.Result.h / 1e3, run);
                dlab.ui.overlayLine(obj.Ax.q, run.Result.t, run.Result.q / 1e3, run);
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
            if isempty(r) || ~isfield(obj.Anim, "rocket")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            at = [r.x(k) r.y(k)] / 1e3;
            v = [r.vx(k) r.vy(k)];
            up = at / norm(at);
            if norm(v) > 1
                along = v / norm(v);
            else
                along = up;
            end
            side = [-along(2) along(1)];
            len = a.size;
            body = at + len * [0.5 * along; -0.5 * along + 0.12 * side; -0.5 * along - 0.12 * side];
            set(a.rocket, XData=body(:, 1), YData=body(:, 2));
            set(a.trail, XData=r.x(1:k) / 1e3, YData=r.y(1:k) / 1e3);
            if r.thrust(k) > 0
                plume = at - len * along * [0.5; 1.1 + 0.2 * rand()];
                set(a.plume, XData=plume(:, 1), YData=plume(:, 2), Visible="on");
            else
                set(a.plume, Visible="off");
            end
            window = obj.FlashSeconds * obj.playbackRate(r);
            near = find(abs([r.events(2:end).time] - simTime) <= window, 1);
            if isempty(near)
                set(a.flash, Visible="off");
            else
                set(a.flash, XData=at(1), YData=at(2), Visible="on");
            end
            stage = r.stage(k);
            label = "coasting";
            if stage > 0
                label = sprintf("stage %d", stage);
            end
            a.readout.String = sprintf("t = %.0f s   h = %.1f km   v = %.0f m/s   q = %.1f kPa   %s", simTime, ...
                r.h(k) / 1e3, r.speed(k), r.q(k) / 1e3, label);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.h, r.downrange, r.speed, r.airspeed, r.mach, r.q, r.gload, r.mass, r.thrust, ...
                VariableNames=["time" "altitude" "downrange" "speed" "airspeed" "mach" "dynamic_pressure" ...
                "g_load" "mass" "thrust"]);
            T.Properties.VariableUnits = ["s" "m" "m" "m/s" "m/s" "" "Pa" "g" "kg" "N"];
        end

        function T = summaryTable(~, r)
            b = r.budget;
            iq = maxQIndex(r);
            [~, top] = max(r.h);
            rows = {
                "Max-Q", r.q(iq) / 1e3, "kPa"
                "Max-Q altitude", r.h(iq) / 1e3, "km"
                "Max-Q time", r.t(iq), "s"
                "Max acceleration under thrust", max([r.gload(r.stage > 0); 0]), "g"
                "Highest altitude", r.h(top) / 1e3, "km"
            };
            for e = r.events
                % (sscanf would also match "Stage 1 ignition": it returns the
                % number it read before the literal "burnout" fails.)
                stage = regexp(e.label, '^Stage (\d+) burnout$', 'tokens', 'once');
                if ~isempty(stage)
                    rows(end+1:end+2, :) = {"Stage " + stage{1} + " burnout altitude", e.h / 1e3, "km"; ...
                        "Stage " + stage{1} + " burnout speed", e.v, "m/s"};
                end
            end
            rows = [rows; {
                "Ideal Δv (Tsiolkovsky)", b.total, "m/s"
                "Gravity loss", b.gravity, "m/s"
                "Drag loss", b.drag, "m/s"
                "Steering loss", b.steering, "m/s"
                "Back-pressure loss", b.pressure, "m/s"
                "Earth-rotation gain", b.rotation, "m/s"
                "Achieved Δv", b.achieved, "m/s"
                "Circularization Δv", b.circularization, "m/s"
            }];
            if ~strcmp(r.termination, "impact")
                % (After an impact these were the orbit of the state at the
                % ground: a perigee of −6370 km.)
                rows = [rows; {"Perigee", r.orbit.perigee, "km"; "Apogee", r.orbit.apogee, "km"}];
            end
            rows = [rows; {
                "Orbit achieved", double(r.orbitAchieved), ""
                "Payload fraction", 100 * r.params.payload / r.mass(1), "%"
            }];
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = strings(height(T), 1);
            T.Display(T.Quantity == "Orbit achieved") = pick(r.orbitAchieved, "yes", "no");
            T.Display(T.Quantity == "Perigee" & T.Value < 0) = "below the surface: suborbital";
        end

        function [note, level] = resultNote(~, r)
            if r.orbitAchieved
                [note, level] = deal(sprintf("in orbit: %.0f × %.0f km", r.orbit.perigee, r.orbit.apogee), "success");
            elseif strcmp(r.termination, "impact")
                [note, level] = deal("fell back to the ground", "warning");
            else
                [note, level] = deal("no orbit", "warning");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Small launcher to LEO (2 stages)", "Tab", "Δv budget", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "A planar ascent over a spherical Earth: gravity −μ r/|r|³, thrust T(h) = throttle T_vac − p(h) A_e " + ...
                "along the guidance direction, and drag ½ ρ v² C_d(M) A against the air-relative velocity " + ...
                "(ISA atmosphere, extended above 86 km)."
                ""
                "Guidance: straight up to the pitch-over altitude, a pitch-over, then a gravity turn " + ...
                "(thrust along the air-relative velocity); upper stages control their climb rate toward " + ...
                "the target altitude. Or a pitch program."
                ""
                "Δv budget along the velocity: ∫ T/m dt = Δ|v| + gravity loss + drag loss + steering " + ...
                "loss, exactly; Tsiolkovsky's g₀ Isp ln(m₀/m_f) minus ∫ T/m dt is the back-pressure loss."
            ], newline);
        end
    end

    methods (Access = private)
        function columns = stageColumns(obj)
            specs = obj.parameters();
            columns = specs(arrayfun(@(s) s.Name == "stages", specs)).Columns;
        end

        function drawBudget(obj, r)
            t = obj.Theme;
            ax = obj.Ax.budget;
            dlab.ui.clearAxes(ax);
            b = r.budget;
            ideal = zeros(2, numel(b.tsiolkovsky) + 5);
            ideal(1, 1:numel(b.tsiolkovsky)) = b.tsiolkovsky';
            spent = [b.achieved b.gravity b.drag b.steering b.pressure];
            ideal(2, numel(b.tsiolkovsky) + (1:5)) = spent;
            bars = bar(ax, ideal, "stacked", EdgeColor="none");
            names = ["Stage " + (1:numel(b.tsiolkovsky)), "Achieved", "Gravity loss", "Drag loss", ...
                "Steering loss", "Back-pressure loss"];
            for k = 1:numel(bars)
                bars(k).FaceColor = t.series(k);
                bars(k).DisplayName = names(k);
            end
            if r.cutoff || r.orbitAchieved
                k = find(r.t >= r.events(end).time, 1);
                yline(ax, sqrt(3.986004418e14 / norm([r.x(k) r.y(k)])), "--", "Orbital speed there", ...
                    Color=t.TextMuted, HandleVisibility="off");
            end
            hold(ax, "off");
            set(ax, XTick=1:2, XTickLabel=["Ideal (Tsiolkovsky)" "Where it went"]);
            dlab.ui.legend(ax, t, "Location", "eastoutside");
        end

        function drawOrbit(obj, r)
            t = obj.Theme;
            ax = obj.Ax.orbit;
            dlab.ui.clearAxes(ax);
            R = obj.EarthRadius / 1e3;
            [cx, cy] = dlab.ui.Schematic.circle([0 0], R, 180);
            patch(ax, cx, cy, t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.6);
            fell = strcmp(r.termination, "impact");
            if isfinite(r.orbit.a) && ~fell
                % The conic through the last state, from its eccentricity vector.
                mu = 3.986004418e5;
                rv = [r.x(end) r.y(end) 0] / 1e3;
                vv = [r.vx(end) r.vy(end) 0] / 1e3;
                e = cross(vv, cross(rv, vv)) / mu - rv / norm(rv);
                w = atan2(e(2), e(1));
                nu = linspace(0, 2 * pi, 361);
                radius = r.orbit.a * (1 - r.orbit.e^2) ./ (1 + r.orbit.e * cos(nu));
                plot(ax, radius .* cos(nu + w), radius .* sin(nu + w), "--", Color=t.series(3), LineWidth=1.3);
            end
            plot(ax, r.x / 1e3, r.y / 1e3, Color=t.series(1), LineWidth=1.6);
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            if fell
                title(ax, "No orbit: it fell back to the ground");
            elseif isfinite(r.orbit.a)
                title(ax, sprintf("Perigee %.0f km, apogee %.0f km", r.orbit.perigee, r.orbit.apogee));
            else
                title(ax, "Escaping the Earth");
            end
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            R = obj.EarthRadius / 1e3;
            x = r.x / 1e3;
            y = r.y / 1e3;
            span = max([max(x) - min(x), max(y) - min(y), 50]);
            limitsX = [min(x) max(x)] + [-0.1 0.1] * span;
            limitsY = [min(min(y), R) max(y)] + [-0.1 0.1] * span;
            angle = linspace(-pi, pi, 721);
            patch(ax, [R * sin(angle), 0], [R * cos(angle), 0], t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.6);
            plot(ax, x, y, ":", Color=t.Grid);
            a.trail = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=1.6);
            a.plume = patch(ax, NaN, NaN, t.Warning, EdgeColor="none", FaceAlpha=0.8);
            a.rocket = patch(ax, NaN, NaN, t.Text, EdgeColor=t.Text);
            a.flash = plot(ax, NaN, NaN, "p", MarkerSize=24, MarkerFaceColor=t.Warning, MarkerEdgeColor=t.Warning, ...
                Visible="off");
            a.size = 0.04 * span;
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            set(ax, XLim=limitsX, YLim=limitsY);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function T = launcherStages()
T = table([22000; 4000], [400000; 92000], [8200; 700], [311; 348], [282; 300], [0; 3], ...
    VariableNames=["dry" "prop" "thrust" "ispVac" "ispSl" "delay"]);
end

function iq = maxQIndex(r)
% Max-Q of the ascent: up to the highest point or the last engine burn,
% whichever is later. A flight that falls back unpowered (the sounding
% rocket) meets its largest q on the way down (496 kPa at 660 s), which is
% not the ascent's; one that dives under thrust ("Too shallow") is still
% flying its ascent.
[~, top] = max(r.h);
last = find(r.stage > 0, 1, "last");
[~, iq] = max(r.q(1:max([top; last])));
end

function groups = eventGroups(r)
% The events after lift-off, one label per place: events within 5 s of
% each other, or at the same point of the trajectory plot (a vertical
% flight lands where it took off), share a label ("Stage 1 burnout, stage 2
% ignition"), so that their texts do not print over each other.
groups = struct("time", {}, "index", {}, "label", {});
span = [max(abs(r.downrange)), max(r.h)];
for e = r.events(2:end)
    label = string(e.label);
    k = find(r.t >= e.time, 1);
    near = arrayfun(@(g) e.time - g.time <= 5 || ...
        all(abs([r.downrange(k) - r.downrange(g.index), r.h(k) - r.h(g.index)]) <= 0.01 * span), groups);
    j = find(near, 1, "last");
    if isempty(j)
        groups(end+1) = struct("time", e.time, "index", k, "label", label); %#ok<AGROW>
    else
        groups(j).label = groups(j).label + ", " + lower(extractBefore(label, 2)) + extractAfter(label, 1);
    end
end
end

function markEvents(ax, r, t)
for e = r.events(2:end)
    xline(ax, e.time, ":", Color=t.TextMuted, HandleVisibility="off");
end
end

function value = pick(condition, yes, no)
value = no;
if condition
    value = yes;
end
end
