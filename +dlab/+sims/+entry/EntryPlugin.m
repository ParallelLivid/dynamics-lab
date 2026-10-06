classdef EntryPlugin < dlab.core.TimeDomainPlugin
    %ENTRYPLUGIN A capsule entering the atmosphere: deceleration, heating,
    %   the entry corridor between skipping out and crushing g-loads, and
    %   the Allen–Eggers ballistic solution. Solved by simulateEntry.

    properties (Constant)
        Id = "entry"
        Title = "Atmospheric Entry"
        Category = "Aerospace"
        Summary = "Coming home: deceleration, heating, skip-out, and the entry corridor."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        EarthRadius = 6371      % km, as dlab.physics.bodyConstants("Earth")
        PlaySeconds = 25
        G0 = 9.80665
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
                P("V0", Label="Entry speed", Units="m/s", Default=11000, Min=500, Max=20000, Group="Entry", ...
                    Description="About 7.8 km/s from low orbit, 11 km/s back from the Moon.")
                P("gamma0", Label="Entry flight-path angle", Units="°", Default=-6.5, Min=-90, Max=0, Group="Entry", ...
                    Description="Below the local horizon (negative: descending). Steeper: harder deceleration; " + ...
                    "too shallow: the capsule skips back out.")
                P("h0", Label="Entry altitude", Units="km", Default=120, Min=20, Max=500, Group="Entry", ...
                    Description="Where the run starts (the entry interface). Climbing back above it is a skip-out.")
                P("beta", Label="Ballistic coefficient m/(C_D S)", Units="kg/m²", Default=350, Min=1, Max=1e5, ...
                    Group="Vehicle", Description="Mass per drag area. Higher: it slows lower down, in denser air.")
                P("LD", Label="Lift-to-drag ratio L/D", Default=0.3, Min=0, Max=3, Group="Vehicle", ...
                    Description="0: a ballistic capsule. Apollo and Soyuz fly at about 0.3, offset centre of mass.")
                P("bank", Label="Bank angle", Type="schedule", Units="°", Default=S("step", Value=0, ...
                    Amplitude=90, Start=80), Min=-180, Max=180, Group="Vehicle", ...
                    Description="Rolling the lift vector: 0 lift up, 90 sideways (no vertical lift), 180 lift down. " + ...
                    "Only cos(bank) matters in this planar model, so a bank reversal (60 to −60) changes nothing.")
                P("noseRadius", Label="Nose radius", Units="m", Default=4.7, Min=0.01, Max=20, Group="Vehicle", ...
                    Description="Radius of the heat shield at the stagnation point. Blunter: less heating (q̇ ∝ 1/√r_n).")
                P("atmosphere", Label="Atmosphere", Type="choice", Default="standard", ...
                    Choices=["standard" "exponential"], ChoiceLabels=["Standard" "Exponential"], Group="Atmosphere", ...
                    Description="Standard: Vallado's bands of the CIRA-72 atmosphere, to orbital heights. " + ...
                    "Exponential: ρ₀ e^(−h/H) with ρ₀ = 1.225 kg/m³, the atmosphere of the Allen–Eggers solution.")
                P("scaleHeight", Label="Scale height H", Units="km", Default=7.2, Min=1, Max=20, Group="Atmosphere", ...
                    VisibleWhen=@(p) p.atmosphere == "exponential", ...
                    Description="The height over which the exponential atmosphere's density falls by e.")
                P("stopAtChute", Label="Stop at parachute deploy", Type="logical", Default=true, Group="Stop", ...
                    Description="End the run when the capsule slows below the deploy Mach number.")
                P("chuteMach", Label="Deploy below Mach", Default=0.8, Min=0.1, Max=5, Group="Stop", ...
                    VisibleWhen=@(p) p.stopAtChute, Description="The Mach number at which the parachutes open.")
                P("maxTime", Label="Time limit", Units="s", Default=3000, Min=10, Max=20000, Group="Simulation", ...
                    MarksCustom=false, Description="The run ends here if nothing else ends it first.")
                P("dt", Label="Output step", Units="s", Default=0.5, Min=0.01, Max=10, Group="Simulation", ...
                    Description="Spacing of saved samples; ode45 picks its own steps, and the peaks are refined " + ...
                    "between samples.")
            ];
        end

        function list = presets(~)
            S = @dlab.core.Schedule.make;
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Apollo-like lunar return", "Values", struct());
            list(end+1) = struct("Name", "Soyuz-like ballistic return from the ISS", "Values", struct( ...
                "V0", 7600, "gamma0", -1.5, "beta", 400, "LD", 0, "bank", 0, "noseRadius", 2.2));
            list(end+1) = struct("Name", "Steep ballistic entry (high g)", "Values", struct( ...
                "V0", 7600, "gamma0", -15, "beta", 400, "LD", 0, "bank", 0, "noseRadius", 2.2));
            list(end+1) = struct("Name", "Ballistic, exponential atmosphere (Allen–Eggers)", "Values", struct( ...
                "V0", 7500, "gamma0", -20, "beta", 300, "LD", 0, "bank", 0, "noseRadius", 1, ...
                "atmosphere", "exponential", "dt", 0.1));
            list(end+1) = struct("Name", "Shallow skip-out", "Values", struct("gamma0", -4.5, "bank", 0));
            list(end+1) = struct("Name", "Corridor: too shallow (skips)", "Values", struct("gamma0", -5.6, ...
                "bank", S("step", Value=0, Amplitude=90, Start=80)));
            list(end+1) = struct("Name", "Corridor: too steep (over 10 g)", "Values", struct("gamma0", -7.4, ...
                "bank", S("step", Value=0, Amplitude=90, Start=80)));
        end

        function result = solve(obj, p)
            q = struct("V0", p.V0, "gamma0", p.gamma0, "h0", p.h0 * 1e3, "beta", p.beta, "LD", p.LD, ...
                "bank", dlab.core.Schedule.toFunction(p.bank, [-180 180]), "noseRadius", p.noseRadius, ...
                "atmosphere", char(p.atmosphere), "scaleHeight", p.scaleHeight * 1e3, ...
                "chuteMach", p.chuteMach * logical(p.stopAtChute), "maxTime", p.maxTime, "dt", p.dt, ...
                "progressFcn", obj.progressMonitor());
            result = dlab.sims.entry.simulateEntry(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Altitude–velocity" "Deceleration" "Heating" "Dynamic pressure" "Trajectory"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.map = dlab.ui.axesIn(containers{"Altitude–velocity"}, t, Title="Altitude against speed", ...
                XLabel="Speed (km/s)", YLabel="Altitude (km)");
            obj.Ax.decel = dlab.ui.axesIn(containers{"Deceleration"}, t, Title="Deceleration (aerodynamic load)", ...
                XLabel="Time (s)", YLabel="g");
            grid = uigridlayout(containers{"Heating"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.qdot = dlab.ui.axesIn(grid, t, Row=1, Title="Stagnation-point heating rate (Sutton–Graves)", ...
                XLabel="Time (s)", YLabel="W/cm²");
            obj.Ax.load = dlab.ui.axesIn(grid, t, Row=2, Title="Heat load ∫ q̇ dt", XLabel="Time (s)", ...
                YLabel="kJ/cm²");
            obj.Ax.q = dlab.ui.axesIn(containers{"Dynamic pressure"}, t, Title="Dynamic pressure q = ½ρV²", ...
                XLabel="Time (s)", YLabel="kPa");
            grid = uigridlayout(containers{"Trajectory"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.path = dlab.ui.axesIn(grid, t, Row=1, Title="Altitude against downrange", ...
                XLabel="Downrange (km)", YLabel="Altitude (km)");
            obj.Ax.gamma = dlab.ui.axesIn(grid, t, Row=2, Title="Flight-path angle", XLabel="Time (s)", ...
                YLabel="γ (°)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Entry", XLabel="km", YLabel="km");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, p)
            obj.Result = r;
            t = obj.Theme;
            pk = r.peaks;
            exponential = p.atmosphere == "exponential";

            ax = obj.Ax.map;
            dlab.ui.clearAxes(ax);
            plot(ax, r.V / 1e3, r.h / 1e3, Color=t.series(1), LineWidth=1.6, DisplayName="Simulated");
            if exponential
                % Allen–Eggers: V = V_E exp(−ρ H / (2 β sin|γ_E|)).
                h = linspace(max(min(r.h), 0), p.h0 * 1e3, 400)';
                rho = 1.225 * exp(-h / (p.scaleHeight * 1e3));
                V = p.V0 * exp(-rho * p.scaleHeight * 1e3 / (2 * p.beta * max(sind(-p.gamma0), 1e-6)));
                plot(ax, V / 1e3, h / 1e3, "--", Color=t.series(2), LineWidth=1.3, ...
                    DisplayName="Allen–Eggers (ballistic, no gravity)");
            end
            mark(ax, interp1(r.t, r.V, pk.decelTime) / 1e3, pk.decelAltitude / 1e3, ...
                sprintf("  peak %.1f g", pk.decel), t.Danger, t, "top");
            mark(ax, interp1(r.t, r.V, pk.qdotTime) / 1e3, pk.qdotAltitude / 1e3, ...
                sprintf("  peak heating %.0f W/cm²", pk.qdot / 1e4), t.Warning, t);
            yline(ax, p.h0, ":", "entry interface", Color=t.TextMuted, HandleVisibility="off", ...
                LabelHorizontalAlignment="left", FontSize=t.FontSize.sm);
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "northwest");

            ax = obj.Ax.decel;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.decel, Color=t.series(1), LineWidth=1.5);
            mark(ax, pk.decelTime, pk.decel, sprintf("  %.1f g at %.1f km", pk.decel, pk.decelAltitude / 1e3), ...
                t.Danger, t);
            if exponential && p.LD == 0
                yline(ax, allenEggers(p) / obj.G0, "--", sprintf("Allen–Eggers %.1f g", allenEggers(p) / obj.G0), ...
                    Color=t.series(2), LabelHorizontalAlignment="right", FontSize=t.FontSize.sm);
            end
            hold(ax, "off");

            ax = obj.Ax.qdot;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.qdot / 1e4, Color=t.series(4), LineWidth=1.5);
            mark(ax, pk.qdotTime, pk.qdot / 1e4, sprintf("  %.0f W/cm² at %.1f km", pk.qdot / 1e4, ...
                pk.qdotAltitude / 1e3), t.Warning, t);
            hold(ax, "off");
            ax = obj.Ax.load;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.heatLoad / 1e7, Color=t.series(5), LineWidth=1.5);
            hold(ax, "off");

            ax = obj.Ax.q;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.q / 1e3, Color=t.series(3), LineWidth=1.5);
            mark(ax, pk.qTime, pk.q / 1e3, sprintf("  %.1f kPa at %.1f km", pk.q / 1e3, pk.qAltitude / 1e3), ...
                t.Danger, t);
            hold(ax, "off");

            ax = obj.Ax.path;
            dlab.ui.clearAxes(ax);
            plot(ax, r.downrange / 1e3, r.h / 1e3, Color=t.series(1), LineWidth=1.6);
            k = find(r.t >= pk.decelTime, 1);
            mark(ax, r.downrange(k) / 1e3, pk.decelAltitude / 1e3, "  peak g", t.Danger, t);
            yline(ax, p.h0, ":", Color=t.TextMuted, HandleVisibility="off");
            hold(ax, "off");
            ax = obj.Ax.gamma;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.gamma, Color=t.series(2), LineWidth=1.4);
            yline(ax, 0, ":", Color=t.TextMuted);
            hold(ax, "off");

            obj.setupAnimation(r, p);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.map, r.V / 1e3, r.h / 1e3, run);
                dlab.ui.overlayLine(obj.Ax.decel, r.t, r.decel, run);
                dlab.ui.overlayLine(obj.Ax.qdot, r.t, r.qdot / 1e4, run);
                dlab.ui.overlayLine(obj.Ax.path, r.downrange / 1e3, r.h / 1e3, run);
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
            if isempty(r) || ~isfield(obj.Anim, "capsule")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            at = [r.x(k) r.y(k)] / 1e3;
            theta = r.downrange(k) / (obj.EarthRadius * 1e3);
            up = [sin(theta) cos(theta)];
            east = [cos(theta) -sin(theta)];
            along = cosd(r.gamma(k)) * east + sind(r.gamma(k)) * up;
            side = [-along(2) along(1)];
            s = a.size;
            % A blunt cone flying heat shield first.
            shape = [0.08 0; 0 0.5; -0.75 0.17; -0.75 -0.17; 0 -0.5];
            body = at + s * (shape(:, 1) * along + shape(:, 2) * side);
            set(a.capsule, XData=body(:, 1), YData=body(:, 2));
            set(a.trail, XData=r.x(1:k) / 1e3, YData=r.y(1:k) / 1e3);
            f = r.qdot(k) / max(max(r.qdot), realmin);
            if f > 0.02
                [cx, cy] = dlab.ui.Schematic.circle(at + 0.3 * s * along, s * (0.4 + 0.7 * f), 40);
                set(a.glow, XData=cx, YData=cy, FaceAlpha=0.15 + 0.6 * f, Visible="on");
                wake = at - s * along * [0.6; 1.2 + 2.5 * f];
                set(a.wake, XData=wake(:, 1), YData=wake(:, 2), LineWidth=1 + 5 * f, Visible="on");
            else
                set([a.glow a.wake], Visible="off");
            end
            a.readout.String = sprintf("t = %.0f s   h = %.1f km   V = %.2f km/s   M = %.1f   %.1f g   q̇ = %.0f W/cm²", ...
                r.t(k), r.h(k) / 1e3, r.V(k) / 1e3, r.mach(k), r.decel(k), r.qdot(k) / 1e4);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.h, r.V, r.gamma, r.downrange, r.mach, r.decel, r.qdot, r.heatLoad, r.q, ...
                VariableNames=["time" "altitude" "speed" "flight_path_angle" "downrange" "mach" "deceleration" ...
                "heating_rate" "heat_load" "dynamic_pressure"]);
            T.Properties.VariableUnits = ["s" "m" "m/s" "deg" "m" "" "g" "W/m^2" "J/m^2" "Pa"];
        end

        function T = summaryTable(obj, r)
            pk = r.peaks;
            p = r.params;
            rows = {
                "Peak deceleration", pk.decel, "g"
                "Peak deceleration altitude", pk.decelAltitude / 1e3, "km"
            };
            if p.LD == 0
                % The formula assumes no lift, so it is shown for ballistic runs only.
                rows(end+1, :) = {"Ballistic estimate of peak deceleration (Allen–Eggers)", ...
                    allenEggers(p) / obj.G0, "g"};
            end
            rows = [rows; {
                "Peak heating rate", pk.qdot / 1e4, "W/cm²"
                "Peak heating altitude", pk.qdotAltitude / 1e3, "km"
                "Heat load", r.heatLoad(end) / 1e7, "kJ/cm²"
                "Peak dynamic pressure", pk.q / 1e3, "kPa"
                "Flight time", r.t(end), "s"
                "Downrange", r.downrange(end) / 1e3, "km"
                "Final speed", r.V(end), "m/s"
                "Final altitude", r.h(end) / 1e3, "km"
                "Energy dissipated", r.dragWork(end) / 1e6, "MJ/kg"
                "Skipped out", double(r.skipped), ""
            }];
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = strings(height(T), 1);
            T.Display(T.Quantity == "Skipped out") = pick(r.skipped, "yes", "no");
        end

        function [note, level] = resultNote(~, r)
            switch r.termination
                case "chute"
                    [note, level] = deal(sprintf("parachute deploy at %.1f km, %.0f m/s", r.h(end) / 1e3, ...
                        r.V(end)), "success");
                case "ground"
                    [note, level] = deal(sprintf("reached the ground at %.0f m/s", r.V(end)), "warning");
                case "skip"
                    [note, level] = deal(sprintf("skipped back out of the atmosphere at %.2f km/s", ...
                        r.V(end) / 1e3), "warning");
                otherwise
                    [note, level] = deal("stopped at the time limit", "warning");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Apollo-like lunar return", "Tab", "Animation", "Time", 75);
        end

        function description = about(~)
            description = join([
                "A capsule entering the atmosphere in a vertical plane over a spherical, non-rotating Earth " + ...
                "(μ = 398 600 km³/s², R = 6371 km):"
                "    dV/dt = −D/m − g sin γ,   V dγ/dt = L/m − (g − V²/r) cos γ,"
                "    dh/dt = V sin γ,   ds/dt = (R/r) V cos γ,"
                "with D/m = ρV²/(2β), β = m/(C_D S), L/m = (L/D)(D/m) cos(bank), g = μ/r²."
                ""
                "Heating at the stagnation point (Sutton–Graves): q̇ = 1.7415×10⁻⁴ √(ρ/r_n) V³ W/m², " + ...
                "integrated into the heat load. The deceleration is the aerodynamic load |L + D|/m in g."
                ""
                "Allen–Eggers (ballistic, constant γ, no gravity, exponential atmosphere): " + ...
                "V = V_E exp(−ρH/(2β sin|γ_E|)); peak deceleration V_E² sin|γ_E|/(2eH) where ρ = β sin|γ_E|/H."
                ""
                "The run stops at the ground, at parachute deploy (below the chosen Mach number), or on a " + ...
                "skip-out (climbing back above the entry altitude)."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r, p)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            R = obj.EarthRadius;
            x = r.x / 1e3;
            y = r.y / 1e3;
            span = max([max(x) - min(x), max(y) - min(y), 50]);
            limitsX = [min(x) max(x)] + [-0.08 0.08] * span;
            low = sqrt(R^2 - min(max(abs(limitsX)), R)^2);      % the lowest ground in view
            limitsY = [min(min(y), low) max(y)] + [-0.08 0.12] * span;
            angle = linspace(asin(max(limitsX(1) / R, -1)), asin(min(limitsX(2) / R, 1)), 400);
            patch(ax, [R * sin(angle), R * sin(angle(end)), R * sin(angle(1))], ...
                [R * cos(angle), limitsY(1) - span, limitsY(1) - span], t.Border, EdgeColor=t.TextMuted, FaceAlpha=0.6);
            edge = R + p.h0;
            plot(ax, edge * sin(angle), edge * cos(angle), ":", Color=t.Grid);
            text(ax, edge * sin(angle(1)), edge * cos(angle(1)), "  entry interface", Color=t.TextMuted, ...
                FontSize=t.FontSize.sm, HorizontalAlignment="left", VerticalAlignment="bottom");
            plot(ax, x, y, ":", Color=t.Grid);
            a.trail = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=1.6);
            a.wake = plot(ax, NaN, NaN, Color=t.Warning, LineWidth=2, Visible="off");
            a.glow = patch(ax, NaN, NaN, t.Warning, EdgeColor="none", FaceAlpha=0.5, Visible="off");
            a.capsule = patch(ax, NaN, NaN, t.Text, EdgeColor=t.Text);
            a.size = 0.016 * span;
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
function a = allenEggers(p)
% Peak deceleration of a ballistic entry (m/s²): V_E² sin|γ_E| / (2 e H).
a = p.V0^2 * sind(-p.gamma0) / (2 * exp(1) * p.scaleHeight * 1e3);
end

function mark(ax, x, y, label, color, t, vertical)
if nargin < 7
    vertical = "bottom";
end
plot(ax, x, y, "o", MarkerFaceColor=color, MarkerEdgeColor=t.Text, HandleVisibility="off");
text(ax, x, y, label, Color=t.Text, FontSize=t.FontSize.sm, VerticalAlignment=vertical);
end

function value = pick(condition, yes, no)
value = no;
if condition
    value = yes;
end
end
