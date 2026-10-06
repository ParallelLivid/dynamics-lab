classdef QuarterCarPlugin < dlab.core.TimeDomainPlugin
    %QUARTERCARPLUGIN One corner of a car on its suspension, driving over
    %   bumps, potholes, and rough roads: ride comfort against road
    %   holding. Solved by simulateQuarterCar.

    properties (Constant)
        Id = "quartercar"
        Title = "Quarter-Car Suspension"
        Category = "Controls & Vehicles"
        Summary = "A car's suspension over bumps and rough roads: comfort, suspension travel, and road holding."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        IsoClasses = ["A" "B" "C" "D" "E" "F" "G" "H"]
        WheelRadius = 0.3         % m, drawing only
        SpringLength = 0.45       % m, hub to body at rest (drawing only)
        ViewHalfWidth = 2         % m of road shown each side of the car
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(obj)
            P = @dlab.core.ParamSpec;
            isFeature = @(p) ismember(p.road, ["bump" "pothole"]);
            specs = [
                P("ms", Label="Body mass (quarter)", Units="kg", Default=300, Min=1, Max=1e5, Group="Car", ...
                    Description="A quarter of the body: the sprung mass carried by one wheel.")
                P("mu", Label="Wheel mass", Units="kg", Default=40, Min=0.5, Max=1e4, Group="Car", ...
                    Description="Wheel, tire, brake, and hub: the unsprung mass.")
                P("ks", Label="Suspension spring", Units="N/m", Default=20000, Min=1, Max=1e8, Group="Car", ...
                    Description="Between body and wheel. With the body mass it sets the body-bounce " + ...
                    "frequency (about 1–1.5 Hz in a car).")
                P("cs", Label="Damper", Units="N·s/m", Default=1500, Min=0, Max=1e6, Group="Car", ...
                    Description="Between body and wheel. Damping ratio c_s / 2√(k_s m_s): about 0.2–0.4 " + ...
                    "in a car; the Summary shows it.")
                P("kt", Label="Tire stiffness", Units="N/m", Default=200000, Min=1, Max=1e9, Group="Car", ...
                    Description="The tire as a spring, about ten times the suspension spring; with the " + ...
                    "wheel mass it sets the wheel-hop frequency (about 10–15 Hz).")
                P("ct", Label="Tire damping", Units="N·s/m", Default=0, Min=0, Max=1e5, Group="Car", ...
                    Description="Usually small; often left at 0.")
                P("speed", Label="Speed", Units="km/h", Default=20, Min=0, Max=300, Group="Road", ...
                    Description="The wheel meets the road at distance s = V t.")
                P("road", Label="Road", Type="choice", Default="bump", ...
                    Choices=["bump" "pothole" "step" "sine" "random"], ...
                    ChoiceLabels=["Bump" "Pothole" "Kerb (step)" "Wavy (sine)" "Rough (ISO)"], Group="Road", ...
                    Description="Bump or pothole: a half sine. Kerb: a step up over 5 cm. Wavy: a sine. " + ...
                    "Rough: random, with the ISO 8608 spectrum of a road class.")
                P("height", Label="Height", Units="cm", Default=6, Min=0, Max=50, Group="Road", ...
                    VisibleWhen=@(p) p.road ~= "random", ...
                    Description="Bump height, pothole depth, kerb height, or wave amplitude.")
                P("length", Label="Length", Units="m", Default=1, Min=0.05, Max=50, Group="Road", ...
                    VisibleWhen=isFeature, Description="Along the road, as a half sine.")
                P("wavelength", Label="Wavelength", Units="m", Default=5, Min=0.1, Max=200, Group="Road", ...
                    VisibleWhen=@(p) p.road == "sine", ...
                    Description="The wheel meets the waves at speed / wavelength (Hz).")
                P("isoClass", Label="Road class", Type="choice", Default="C", Choices=obj.IsoClasses, ...
                    ChoiceLabels=["A (v. good)" "B (good)" "C (average)" "D (poor)" "E (v. poor)" ...
                    "F" "G" "H"], Group="Road", VisibleWhen=@(p) p.road == "random", ...
                    Description="ISO 8608 roughness, from A (very good) to H: each class has four times " + ...
                    "the PSD of the one before (about twice the height).")
                P("seed", Label="Road seed", Type="integer", Default=1, Min=0, Max=1e6, Group="Road", ...
                    VisibleWhen=@(p) p.road == "random", Description="Each seed is a different stretch of road.")
                P("start", Label="Distance to the feature", Units="m", Default=2, Min=0, Max=1000, Group="Road", ...
                    Description="Flat road before the bump (or the start of the waves or roughness).")
                P("liftoff", Label="Tire can leave the road", Type="logical", Default=true, Group="Road", ...
                    Description="The tire can push on the road but not pull: the wheel lifts off when the load reaches zero.")
                P("tspan", Label="Duration", Units="s", Default=3, Min=0.01, Max=600, Group="Simulation", ...
                    MarksCustom=false, Description="Length of the run. The RMS values in the Summary " + ...
                    "are over the whole run, flat road included.")
                P("dt", Label="Output step", Units="s", Default=0.002, Min=1e-5, Max=1, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Spacing of the samples (at most 2 million); the " + ...
                    "solver's own steps are shorter when the car or the road needs it.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Passenger car over a speed bump (20 km/h)", "Values", struct());
            list(end+1) = struct("Name", "Sports car (stiff)", "Values", struct( ...
                "ms", 250, "mu", 35, "ks", 45000, "cs", 3500, "kt", 250000, "speed", 40));
            list(end+1) = struct("Name", "Truck (heavy, soft)", "Values", struct( ...
                "ms", 4000, "mu", 400, "ks", 200000, "cs", 18000, "kt", 1600000, "speed", 30, "height", 8, ...
                "length", 1.5));
            list(end+1) = struct("Name", "Worn dampers", "Values", struct("cs", 300, "speed", 40));
            list(end+1) = struct("Name", "Rough road (ISO class D, 80 km/h)", "Values", struct( ...
                "road", "random", "isoClass", "D", "speed", 80, "start", 0, "tspan", 10, "dt", 0.002));
            list(end+1) = struct("Name", "Resonance: wheel hop", "Values", struct( ...
                "road", "sine", "height", 1, "wavelength", 1.5, "speed", 64, "start", 0, "tspan", 4));
        end

        function result = solve(obj, p)
            road = struct("type", char(p.road), "height", p.height / 100, "length", p.length, ...
                "start", p.start, "wavelength", p.wavelength, ...
                "isoClass", find(obj.IsoClasses == p.isoClass, 1), "seed", p.seed);
            if p.road == "pothole"
                road.height = abs(road.height);
            end
            q = struct("ms", p.ms, "mu", p.mu, "ks", p.ks, "cs", p.cs, "kt", p.kt, "ct", p.ct, ...
                "V", p.speed / 3.6, "road", road, "liftoff", logical(p.liftoff), "tspan", p.tspan, ...
                "dt", p.dt, "g", 9.81, "progressFcn", obj.progressMonitor());
            result = dlab.sims.quartercar.simulateQuarterCar(q);
            result.distance = q.V * result.t;
            result.V = q.V;
            result.road = road;
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Body and wheel" "Body acceleration" "Suspension travel and tire load" ...
                "Road profile"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.motion = dlab.ui.axesIn(containers{"Body and wheel"}, t, Title="Body, wheel, and road", ...
                XLabel="Time (s)", YLabel="Height (cm)");
            obj.Ax.accel = dlab.ui.axesIn(containers{"Body acceleration"}, t, Title="Body acceleration", ...
                XLabel="Time (s)", YLabel="Acceleration (m/s²)");
            grid = uigridlayout(containers{"Suspension travel and tire load"}, [2 1], Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.travel = dlab.ui.axesIn(grid, t, Row=1, Title="Suspension travel (body − wheel)", ...
                XLabel="Time (s)", YLabel="Travel (cm)");
            obj.Ax.tire = dlab.ui.axesIn(grid, t, Row=2, Title="Tire load", XLabel="Time (s)", YLabel="Force (N)");
            obj.Ax.road = dlab.ui.axesIn(containers{"Road profile"}, t, Title="Road profile", ...
                XLabel="Distance (m)", YLabel="Height (cm)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Quarter car", XLabel="Road (m, relative to the car)", ...
                YLabel="Height (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, ~)
            obj.Result = r;
            t = obj.Theme;

            ax = obj.Ax.motion;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, 100 * r.zr, Color=t.TextMuted, LineWidth=1.2, DisplayName="Road under the tire");
            plot(ax, r.t, 100 * r.zu, Color=t.series(2), LineWidth=1.4, DisplayName="Wheel");
            plot(ax, r.t, 100 * r.zs, Color=t.series(1), LineWidth=1.8, DisplayName="Body");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.accel;
            dlab.ui.clearAxes(ax);
            rms = sqrt(mean(r.bodyAccel.^2));
            plot(ax, r.t, r.bodyAccel, Color=t.series(1), LineWidth=1.2, DisplayName="Body acceleration");
            yline(ax, rms, "--", Color=t.series(3), LineWidth=1.2, DisplayName=sprintf("±RMS = %.3g m/s²", rms));
            yline(ax, -rms, "--", Color=t.series(3), LineWidth=1.2, HandleVisibility="off");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.travel;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, 100 * r.travel, Color=t.series(4), LineWidth=1.3);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            hold(ax, "off");

            ax = obj.Ax.tire;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.tireForce, Color=t.series(2), LineWidth=1.3, DisplayName="Tire load");
            yline(ax, r.staticLoad, "--", Color=t.TextMuted, DisplayName="Static load");
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            if any(r.airborne)
                plot(ax, r.t(r.airborne), zeros(nnz(r.airborne), 1), ".", Color=t.Danger, MarkerSize=8, ...
                    DisplayName="Wheel off the road");
            end
            if any(pulling(r))
                plot(ax, r.t(pulling(r)), r.tireForce(pulling(r)), ".", Color=t.Danger, MarkerSize=8, ...
                    DisplayName="Tire pulling the road");
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.road;
            dlab.ui.clearAxes(ax);
            [s, z] = obj.roadSamples(r, 0, max(r.distance(end), 1));
            plot(ax, s, 100 * z, Color=t.TextMuted, LineWidth=1.4);
            hold(ax, "off");
            xlim(ax, [s(1) s(end)]);

            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.motion, run.Result.t, 100 * run.Result.zs, run);
                dlab.ui.overlayLine(obj.Ax.accel, run.Result.t, run.Result.bodyAccel, run);
                dlab.ui.overlayLine(obj.Ax.travel, run.Result.t, 100 * run.Result.travel, run);
                dlab.ui.overlayLine(obj.Ax.tire, run.Result.t, run.Result.tireForce, run);
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

        function rate = playbackRate(~, ~)
            % Half speed: a bump is over in a fraction of a second.
            rate = 0.5;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "body")
                return
            end
            k = dlab.core.frameAt(r.t, simTime);
            a = obj.Anim;
            here = r.distance(k);
            R = obj.WheelRadius;
            [s, z] = obj.roadSamples(r, here - obj.ViewHalfWidth, here + obj.ViewHalfWidth);
            x = s - here;
            set(a.road, XData=[x(1); x; x(end)], YData=[-0.4; z; -0.4]);
            set(a.surface, XData=x, YData=z);

            hub = [0, R + r.zu(k)];
            [wx, wy] = dlab.ui.Schematic.wheel(hub, R, 5, -here / R);
            set(a.wheel, XData=wx, YData=wy);
            [tx, ty] = dlab.ui.Schematic.spring([0.42, r.zr(k)], [0.42, hub(2)], 4, 0.08);
            set(a.tireSpring, XData=[tx NaN 0 0.42], YData=[ty NaN hub(2) hub(2)]);
            set(a.axle, XData=[-0.22 0.22], YData=hub(2) * [1 1]);
            bottom = R + obj.SpringLength + r.zs(k);
            [sx, sy] = dlab.ui.Schematic.spring([-0.14, hub(2)], [-0.14, bottom], 6, 0.12);
            set(a.spring, XData=sx, YData=sy);
            [dx, dy] = dlab.ui.Schematic.damper([0.14, hub(2)], [0.14, bottom], 0.1);
            set(a.damper, XData=dx, YData=dy);
            [bx, by] = dlab.ui.Schematic.rect([0, bottom + 0.15], 0.55, 0.15);
            set(a.body, XData=bx, YData=by);
            if r.airborne(k)
                a.wheel.Color = obj.Theme.Danger;
            else
                a.wheel.Color = obj.Theme.Text;
            end
            a.readout.String = sprintf("t = %.2f s   body %+.1f cm   wheel %+.1f cm   tire %.0f N", ...
                simTime, 100 * r.zs(k), 100 * r.zu(k), r.tireForce(k));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.distance, r.zr, r.zs, r.zu, r.bodyAccel, r.travel, r.tireForce, ...
                VariableNames=["time" "distance" "road" "body" "wheel" "body_acceleration" ...
                "suspension_travel" "tire_load"]);
            T.Properties.VariableUnits = ["s" "m" "m" "m" "m" "m/s^2" "m" "N"];
        end

        function T = summaryTable(~, r)
            p = r.params;
            accel = r.bodyAccel;
            left = any(r.airborne);
            rows = {
                "RMS body acceleration", sqrt(mean(accel.^2)), "m/s²", ""
                "Peak body acceleration", max(abs(accel)), "m/s²", ""
                "Max suspension travel", 100 * max(abs(r.travel)), "cm", ""
                "RMS dynamic tire load / static", sqrt(mean((r.tireForce - r.staticLoad).^2)) / r.staticLoad, "", ""
                "Minimum tire load", min(r.tireForce), "N", ""
                "Wheel left the road", double(left), "", pick(left, "yes", "no")
                "Time off the road", duration(r, r.airborne), "s", ""
            };
            if any(pulling(r))
                rows(end+1, :) = {"Time the tire pulled the road", duration(r, pulling(r)), "s", ""};
            end
            rows = [rows
                {"Body bounce frequency (undamped)", r.frequencies(1), "Hz", ""
                 "Wheel hop frequency (undamped)", r.frequencies(2), "Hz", ""
                 "Suspension damping ratio", p.cs / (2 * sqrt(p.ks * p.ms)), "", ""
                 "Static tire load", r.staticLoad, "N", ""}];
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                VariableNames=["Quantity" "Value" "Units" "Display"]);
        end

        function [note, level] = resultNote(~, r)
            note = "";
            level = "success";
            if any(r.airborne)
                note = sprintf("the wheel left the road for %.3g s (no grip while airborne)", ...
                    duration(r, r.airborne));
                level = "warning";
            elseif any(pulling(r))
                note = sprintf("the tire pulled the road (a negative load) for %.3g s: a real wheel " + ...
                    "would lift off (allow it under Road)", duration(r, pulling(r)));
                level = "warning";
            end
        end

        function lin = linearization(~, p)
            % State [z_s; ż_s; z_u; w] with w = ż_u − (c_t/m_u) z_r, so that the
            % road height z_r enters as a plain input although the tire
            % damper feels its rate (the Bode tab's G(x, u) has no u̇). At
            % z_r = 0, w is ż_u and this is the usual model.
            M = diag([p.ms p.mu]);
            K = [p.ks -p.ks; -p.ks p.ks + p.kt];
            G = @(x, zr) quarterCar(x, zr, p);
            lin = struct("F", @(x) G(x, 0), "X0", zeros(4, 1), "StateNames", ["z_s" "ż_s" "z_u" "ż_u"], ...
                "Reference", "at rest on a flat road", "Classify", @(lambda, V) modeNames(lambda, V, p), ...
                "Scale", [0.01 0.1 0.01 0.1], ...
                "G", G, "U0", 0, "InputNames", "Road height", "InputUnits", "m", ...
                "H", @(x, zr) bodyOutputs(x, zr, p), ...
                "OutputNames", ["Body height" "Body acceleration" "Suspension travel" "Tire deflection"], ...
                "OutputUnits", ["m" "m/s²" "m" "m"], "FrequencyUnits", "Hz");
            % Mark the undamped body-bounce and wheel-hop frequencies, and
            % where a wavy road excites the car.
            w = sort(sqrt(eig(K, M)));
            lin.Markers = struct("Frequency", num2cell(w'), "Label", {"Body bounce", "Wheel hop"});
            if p.road == "sine" && p.speed > 0
                lin.Markers(end+1) = struct("Frequency", 2 * pi * (p.speed / 3.6) / p.wavelength, "Label", "Road");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Passenger car over a speed bump (20 km/h)", "Tab", "Animation", "Time", 0.55);
        end

        function description = about(~)
            description = join([
                "m_s z_s'' = −k_s (z_s − z_u) − c_s (z_s' − z_u')"
                "m_u z_u'' =  k_s (z_s − z_u) + c_s (z_s' − z_u') + F − W"
                "F = W − k_t (z_u − z_r) − c_t (z_u' − z_r')      (the tire load, F ≥ 0 with lift-off)"
                ""
                "One corner of a car: the body (sprung mass m_s) rides on the suspension spring and " + ...
                "damper above the wheel (unsprung mass m_u), which rides on the tire. Heights are " + ...
                "measured from rest, and W = (m_s + m_u) g is the static tire load; the road height z_r " + ...
                "is met at distance s = V t."
                ""
                "Two natural frequencies matter: body bounce (about 1–1.5 Hz in a car) and wheel hop " + ...
                "(about 10–15 Hz). Soft damping isolates the body from high frequencies but lets " + ...
                "bounce and hop ring; stiff damping holds the wheel down but passes bumps to the " + ...
                "body. Comfort is judged by the body acceleration, road holding by how much the tire " + ...
                "load varies."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = obj.Anim;
            a.road = patch(ax, NaN, NaN, t.Border, EdgeColor="none", FaceAlpha=0.6);
            a.surface = plot(ax, NaN, NaN, Color=t.TextMuted, LineWidth=2);
            a.tireSpring = plot(ax, NaN, NaN, Color=t.series(2), LineWidth=1.4);
            a.wheel = plot(ax, NaN, NaN, Color=t.Text, LineWidth=2.2);
            a.axle = plot(ax, NaN, NaN, Color=t.Text, LineWidth=3);
            a.spring = plot(ax, NaN, NaN, Color=t.series(4), LineWidth=1.6);
            a.damper = plot(ax, NaN, NaN, Color=t.series(3), LineWidth=1.6);
            a.body = patch(ax, NaN, NaN, t.series(1), EdgeColor=t.Text, LineWidth=1.5, FaceAlpha=0.9);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            top = obj.WheelRadius + obj.SpringLength + 0.3 + max([r.zs; 0]) + 0.15;
            set(ax, XLim=obj.ViewHalfWidth * [-1 1], YLim=[-0.4 max(top, 1.3)]);
            daspect(ax, [1 1 1]);
            obj.Anim = a;
        end

        function [s, z] = roadSamples(~, r, from, to)
            s = linspace(from, to, 600)';
            z = dlab.sims.quartercar.roadProfile(r.road, s);
            z(s < 0) = 0;
        end
    end
end

% ---------------------------------------------------------------- helpers
function mask = pulling(r)
% Samples with a negative tire load (lift-off off); older results have none.
mask = false(size(r.t));
if isfield(r, "pulling")
    mask = r.pulling;
end
end

function s = duration(r, mask)
% Time spent where MASK is true (each sample stands for the step after it).
s = sum(diff(r.t) .* mask(1:end-1));
end

function text = pick(condition, yes, no)
text = no;
if condition
    text = yes;
end
end

function labels = modeNames(lambda, V, p)
%MODENAMES Body bounce when the body has most of the mode's kinetic energy.
labels = strings(numel(lambda), 1);
for k = 1:numel(lambda)
    body = p.ms * abs(V(2, k))^2;
    wheel = p.mu * abs(V(4, k))^2;
    if body >= wheel
        labels(k) = "Body bounce";
    else
        labels(k) = "Wheel hop";
    end
end
end

function dx = quarterCar(x, zr, p)
% The linear quarter car with road height ZR as an input (state as in
% linearization: the last is ż_u − (c_t/m_u) z_r).
zuDot = x(4) + p.ct / p.mu * zr;
spring = p.ks * (x(1) - x(3)) + p.cs * (x(2) - zuDot);
dx = [x(2)
      -spring / p.ms
      zuDot
      (spring - p.kt * (x(3) - zr) - p.ct * zuDot) / p.mu];
end

function y = bodyOutputs(x, zr, p)
% Body height, body acceleration, suspension travel, and tire deflection
% (wheel above the road; times k_t it is the dynamic tire load when the
% tire has no damping).
dx = quarterCar(x, zr, p);
y = [x(1); dx(2); x(1) - x(3); x(3) - zr];
end
