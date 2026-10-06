classdef WavePlugin < dlab.core.TimeDomainPlugin
    %WAVEPLUGIN Vibrating string or beam: standing waves, harmonics, and
    %   how the pluck point and the supports shape the sound. Solved by
    %   modes (simulateWave), exact in time.

    properties (Constant)
        Id = "wave"
        Title = "Vibrating String and Beam"
        Category = "Continuum"
        Summary = "Plucked strings and struck beams: standing waves, harmonics, and mode shapes."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        MaxModesListed = 6
        PlaySeconds = 10
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isString = @(p) p.medium == "string";
            isBeam = @(p) p.medium == "beam";
            specs = [
                P("medium", Label="Medium", Type="choice", Default="string", Choices=["string" "beam"], ...
                    ChoiceLabels=["String" "Beam"], Group="Medium", ...
                    Description="A string resists through tension (ρ u'' = T u_xx); a beam through " + ...
                    "bending stiffness (ρA u'' = −EI u_xxxx), so its overtones are not harmonic.")
                P("L", Label="Length", Units="m", Default=0.65, Min=0.01, Max=100, Group="Medium", ...
                    Description="The vibrating length between the ends.")
                P("tension", Label="Tension", Units="N", Default=70, Min=1e-3, Max=1e7, Group="Medium", ...
                    VisibleWhen=isString, Description="With the mass per length, it sets the wave speed c = √(T/ρ).")
                P("rho", Label="Mass per length", Units="kg/m", Default=0.0006, Min=1e-6, Max=1e3, Group="Medium", ...
                    VisibleWhen=isString, DisplayFormat="%.4g", Description="The string's mass per metre ρ.")
                P("stringBc", Label="Ends", Type="choice", Default="fixedfixed", Choices=["fixedfixed" "fixedfree"], ...
                    ChoiceLabels=["Both fixed" "Fixed–free"], Group="Medium", VisibleWhen=isString, ...
                    Description="Both ends fixed (harmonics n c / 2L), or the far end free to slide " + ...
                    "sideways (odd harmonics (2n − 1) c / 4L).")
                P("EI", Label="Bending stiffness EI", Units="N·m²", Default=0.5, Min=1e-6, Max=1e10, Group="Medium", ...
                    VisibleWhen=isBeam, DisplayFormat="%.4g", Description="Young's modulus times the second moment of area.")
                P("rhoA", Label="Mass per length", Units="kg/m", Default=0.2355, Min=1e-6, Max=1e5, Group="Medium", ...
                    VisibleWhen=isBeam, DisplayFormat="%.4g", Description="The beam's mass per metre ρA.")
                P("beamBc", Label="Supports", Type="choice", Default="cantilever", ...
                    Choices=["pinned" "cantilever" "clamped" "free"], ...
                    ChoiceLabels=["Pinned" "Cantilever" "Clamped" "Free–free"], ...
                    Group="Medium", VisibleWhen=isBeam, Description="Pinned at both ends; a cantilever " + ...
                    "(clamped at x = 0, free at the other end); clamped at both ends; or free at both " + ...
                    "(a bar on soft supports: its drift and spin are left out).")
                P("zeta", Label="Damping ratio", Units="%", Default=0.2, Min=0, Max=50, Group="Medium", ...
                    Description="The same damping ratio for every mode.")
                P("initial", Label="Start", Type="choice", Default="pluck", Choices=["pluck" "strike" "mode" "gaussian"], ...
                    ChoiceLabels=["Pluck" "Strike" "One mode" "Bump"], Group="Excitation", ...
                    Description="Pluck: pulled aside at one point and released (a beam from its deflection " + ...
                    "under a point load). Strike: a Gaussian initial velocity, like a hammer. One mode: " + ...
                    "that mode's shape alone. Bump: a Gaussian displacement.")
                P("height", Label="Amplitude", Units="m or m/s", Default=0.003, Min=-10, Max=10, Group="Excitation", ...
                    Description="Displacement of a pluck, bump, or mode; speed of a strike.", DisplayFormat="%.4g")
                P("position", Label="Position", Units="× L", Default=0.2, Min=0.01, Max=0.99, Group="Excitation", ...
                    VisibleWhen=@(p) p.initial ~= "mode", ...
                    Description="Where the pluck, strike, or bump is, as a fraction of the length from x = 0.")
                P("width", Label="Width", Units="× L", Default=0.03, Min=0.002, Max=1, Group="Excitation", ...
                    VisibleWhen=@(p) ismember(p.initial, ["strike" "gaussian"]), ...
                    Description="The Gaussian's half-width (where it falls to 1/e), as a fraction of the length.")
                P("mode", Label="Mode number", Type="integer", Default=3, Min=1, Max=50, Group="Excitation", ...
                    VisibleWhen=@(p) p.initial == "mode", Description="Which mode starts alone (1 is the fundamental).")
                P("elements", Label="Elements", Type="integer", Default=200, Min=4, Max=800, Group="Numerics", ...
                    Description="Finite elements along the length; more give accurate higher modes.")
                P("tspan", Label="Duration", Units="s", Default=0.02, Min=1e-5, Max=1e4, Group="Simulation", ...
                    MarksCustom=false, DisplayFormat="%.4g", Description="How long to follow the motion.")
                P("dtOut", Label="Output step", Units="s", Default=2e-5, Min=1e-7, Max=100, Group="Simulation", ...
                    DisplayFormat="%.4g", Description="Time between the stored samples. The motion is exact " + ...
                    "at each; the spectrum reaches half the sampling rate.")
                P("probe", Label="Probe position", Units="× L", Default=0.1, Min=0, Max=1, Group="Simulation", ...
                    Description="Where the Probe tab records the motion (like a pickup).")
                P("modesShown", Label="Mode shapes shown", Type="integer", Default=4, Min=1, Max=8, Group="Display", ...
                    Display=true, Description="How many mode shapes the Mode shapes tab draws.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Guitar string (pluck near the bridge)", "Values", struct("position", 0.12));
            list(end+1) = struct("Name", "Pluck at the middle (odd harmonics)", "Values", struct("position", 0.5));
            list(end+1) = struct("Name", "Single mode n = 3 (standing wave)", "Values", struct( ...
                "initial", "mode", "mode", 3, "zeta", 0));
            list(end+1) = struct("Name", "Struck string (piano hammer)", "Values", struct( ...
                "initial", "strike", "height", 2, "position", 0.12, "width", 0.01));
            list(end+1) = struct("Name", "Cantilever beam (a ruler)", "Values", struct( ...
                "medium", "beam", "L", 0.3, "EI", 0.5, "rhoA", 0.2355, "beamBc", "cantilever", ...
                "position", 0.99, "height", 0.02, "elements", 60, "zeta", 1, "tspan", 1, "dtOut", 0.001, "probe", 1));
            list(end+1) = struct("Name", "Free–free bar (a xylophone key)", "Values", struct( ...
                "medium", "beam", "L", 0.3, "EI", 233, "rhoA", 1.08, "beamBc", "free", "initial", "strike", ...
                "height", 1, "position", 0.5, "width", 0.02, "elements", 60, "zeta", 0.5, ...
                "tspan", 0.02, "dtOut", 2e-5, "probe", 0));
        end

        function result = solve(~, p)
            q = struct("medium", char(p.medium), "L", p.L, "elements", p.elements, "tension", p.tension, ...
                "rho", p.rho, "EI", p.EI, "rhoA", p.rhoA, "bc", char(p.stringBc), "initial", char(p.initial), ...
                "height", p.height, "position", p.position, "width", p.width, "mode", p.mode, ...
                "zeta", p.zeta / 100, "tspan", p.tspan, "dtOut", p.dtOut, "probe", p.probe);
            if p.medium == "beam"
                q.bc = char(p.beamBc);
            end
            result = dlab.sims.wave.simulateWave(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Space-time" "Mode content" "Mode shapes" "Energy" "Probe"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.spacetime = dlab.ui.axesIn(containers{"Space-time"}, t, Title="Displacement over space and time", ...
                XLabel="x (m)", YLabel="Time (s)");
            obj.Ax.content = dlab.ui.axesIn(containers{"Mode content"}, t, Title="Energy in each mode", ...
                XLabel="Mode", YLabel="Share of energy (%)");
            obj.Ax.shapes = dlab.ui.axesIn(containers{"Mode shapes"}, t, Title="Mode shapes", ...
                XLabel="x (m)", YLabel="Mode (offset)");
            obj.Ax.energy = dlab.ui.axesIn(containers{"Energy"}, t, Title="Energy", XLabel="Time (s)", ...
                YLabel="Energy (J)");
            grid = uigridlayout(containers{"Probe"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.probe = dlab.ui.axesIn(grid, t, Row=1, Title="Motion at the probe", XLabel="Time (s)", ...
                YLabel="Displacement (m)");
            obj.Ax.spectrum = dlab.ui.axesIn(grid, t, Row=2, Title="Spectrum at the probe", ...
                XLabel="Frequency (Hz)", YLabel="Amplitude (m)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Vibration", XLabel="x (m)", YLabel="Displacement (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            limit = max(abs(r.U(:)));
            limit = max(limit, eps);

            ax = obj.Ax.spacetime;
            dlab.ui.clearAxes(ax);
            imagesc(ax, r.x, r.t, r.U);
            colormap(ax, t.divergingMap());
            clim(ax, [-limit limit]);
            c = colorbar(ax, Color=t.AxesForeground);
            c.Label.String = "Displacement (m)";
            set(ax, YDir="normal", XLim=[r.x(1) r.x(end)], YLim=[r.t(1) r.t(end)]);
            hold(ax, "off");

            ax = obj.Ax.content;
            dlab.ui.clearAxes(ax);
            count = min(numel(r.modalEnergy), 20);
            share = 100 * r.modalEnergy(1:count) / max(sum(r.modalEnergy), realmin);
            bar(ax, 1:count, share, FaceColor=t.series(1), EdgeColor="none");
            labels = compose("%.4g Hz", r.frequencies(1:min(count, 8)));
            text(ax, 1:min(count, 8), share(1:min(count, 8)), "  " + labels, Rotation=90, ...
                FontSize=t.FontSize.sm, Color=t.TextMuted, VerticalAlignment="middle");
            hold(ax, "off");
            xlim(ax, [0.4 count + 0.6]);
            ylim(ax, [0 1.25 * max([share; eps])]);    % room for the frequency labels

            ax = obj.Ax.shapes;
            dlab.ui.clearAxes(ax);
            shown = min(params.modesShown, size(r.shapes, 2));
            for k = 1:shown
                shape = r.shapes(:, k) / max(abs(r.shapes(:, k)));
                plot(ax, r.x, 0.4 * shape + k, Color=t.series(k), LineWidth=1.8, ...
                    DisplayName=sprintf("Mode %d: %.4g Hz", k, r.frequencies(k)));
                plot(ax, r.x([1 end]), [k k], ":", Color=t.Grid, HandleVisibility="off");
            end
            hold(ax, "off");
            set(ax, YDir="reverse", YLim=[0.4 shown + 0.6], YTick=1:shown);
            dlab.ui.legend(ax, t, "Location", "eastoutside");

            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.KE, Color=t.series(1), LineWidth=1.4, DisplayName="Kinetic");
            plot(ax, r.t, r.PE, Color=t.series(2), LineWidth=1.4, DisplayName="Potential");
            plot(ax, r.t, r.E, "--", Color=t.Text, LineWidth=1.8, DisplayName="Total");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.probe;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.probe, Color=t.series(3), LineWidth=1.2);
            hold(ax, "off");
            title(ax, sprintf("Motion at x = %.3g m", params.probe * params.L));
            ax = obj.Ax.spectrum;
            dlab.ui.clearAxes(ax);
            [frequency, amplitude] = dlab.physics.amplitudeSpectrum(r.t, r.probe);
            plot(ax, frequency, amplitude, Color=t.series(3), LineWidth=1.2, DisplayName="Probe spectrum");
            top = r.frequencies(r.frequencies <= max(frequency));
            for f = reshape(top(1:min(end, 8)), 1, [])
                xline(ax, f, ":", Color=t.TextMuted, HandleVisibility="off");
            end
            hold(ax, "off");
            if ~isempty(frequency)
                xlim(ax, [0 max(min(frequency(end), 12 * r.frequencies(1)), eps)]);
            end

            obj.setupAnimation(r, params, limit);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.energy, run.Result.t, run.Result.E, run);
                dlab.ui.overlayLine(obj.Ax.probe, run.Result.t, run.Result.probe, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            colorbar(obj.Ax.spacetime, "off");
            delete(allchild(obj.Anim.axes));
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, r)
            % Slow motion: a whole run (often a few hundredths of a second) in about 10 s.
            rate = r.t(end) / obj.PlaySeconds;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "shape")
                return
            end
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            u = r.U(k, :) + fraction * (r.U(next, :) - r.U(k, :));
            a = obj.Anim;
            set(a.shape, YData=u);
            probeX = r.params.probe * r.params.L;
            set(a.probe, XData=probeX, YData=interp1(r.x, u, probeX));
            a.readout.String = sprintf("t = %.4g s", simTime);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.probe, r.KE, r.PE, r.E, ...
                VariableNames=["time" "probe_displacement" "kinetic_energy" "potential_energy" "total_energy"]);
            T.Properties.VariableUnits = ["s" "m" "J" "J" "J"];
        end

        function T = summaryTable(obj, r)
            f = r.frequencies;
            rows = {"Fundamental frequency", f(1), "Hz"};
            if numel(f) >= 3
                rows(end+1:end+2, :) = {"f2 / f1", f(2) / f(1), ""; "f3 / f1", f(3) / f(1), ""};
            end
            if isfinite(r.c)
                rows(end+1, :) = {"Wave speed", r.c, "m/s"};
            end
            total = sum(r.modalEnergy);
            if total > 0
                [~, dominant] = max(r.modalEnergy);
                rows(end+1, :) = {"Dominant mode", dominant, ""};
                for k = 1:min(obj.MaxModesListed, numel(r.modalEnergy))
                    share = 100 * r.modalEnergy(k) / total;
                    if share < 1e-9
                        share = 0;              % a mode with a node at the start: rounding noise only
                    end
                    rows(end+1, :) = {sprintf("Mode %d energy share", k), share, "%"}; %#ok<AGROW>
                end
                rows(end+1, :) = {"Energy remaining at the end", 100 * r.E(end) / r.E(1), "%"};
            end
            if r.rigid > 0
                rows(end+1, :) = {"Rigid-body modes", r.rigid, ""};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Guitar string (pluck near the bridge)", "Tab", "Space-time", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "String:  ρ ∂²u/∂t² = T ∂²u/∂x²   (wave speed c = √(T/ρ); harmonics f_n = n c / 2L)."
                "Beam:  ρA ∂²u/∂t² = −EI ∂⁴u/∂x⁴   (overtones are not harmonic: 1 : 4 : 9 pinned, " + ...
                "1 : 6.27 : 17.5 cantilever)."
                ""
                "The length is divided into finite elements (linear for a string, Hermite cubics for a " + ...
                "beam). The natural modes come from the generalized eigenvalue problem K φ = ω² M φ, " + ...
                "and the motion is their sum, exact in time, each decaying with the damping ratio. " + ...
                "Where you pluck or strike decides how much each mode gets: a pluck at a node of a " + ...
                "mode cannot excite it."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r, params, limit)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            L = r.x(end);
            yline(ax, 0, ":", Color=t.Grid, HandleVisibility="off");
            supports(ax, params, L, limit, t);
            a = obj.Anim;
            a.shape = plot(ax, r.x, r.U(1, :), Color=t.series(1), LineWidth=2.5);
            a.probe = plot(ax, NaN, NaN, "o", MarkerSize=8, MarkerFaceColor=t.series(3), MarkerEdgeColor=t.Text);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            set(ax, XLim=[-0.05 1.05] * L, YLim=[-1.3 1.3] * limit);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function supports(ax, params, L, limit, t)
% Hatched walls at clamped or fixed ends; triangles at pins.
if params.medium == "string"
    ends = ["fixed" "fixed"];
    if params.stringBc == "fixedfree"
        ends(2) = "free";
    end
else
    switch params.beamBc
        case "pinned",     ends = ["pin" "pin"];
        case "cantilever", ends = ["clamp" "free"];
        case "clamped",    ends = ["clamp" "clamp"];
        otherwise,         ends = ["free" "free"];
    end
end
positions = [0 L];
side = [-1 1];
for k = 1:2
    x0 = positions(k);
    switch ends(k)
        case {"fixed", "clamp"}
            % A wall: a vertical line with ticks on the outside (axes scales differ, so drawn here).
            ticks = linspace(-limit, limit, 7);
            hx = [x0 x0, reshape([x0 * ones(1, 7); x0 + side(k) * 0.03 * L * ones(1, 7); NaN(1, 7)], 1, [])];
            hy = [-limit limit, reshape([ticks; ticks - 0.15 * limit; NaN(1, 7)], 1, [])];
            hx = [hx(1:2) NaN hx(3:end)];
            hy = [hy(1:2) NaN hy(3:end)];
            plot(ax, hx, hy, Color=t.TextMuted, LineWidth=1.2, HandleVisibility="off");
        case "pin"
            plot(ax, x0 + 0.02 * L * [-1 0 1 -1], limit * [-0.25 0 -0.25 -0.25], Color=t.TextMuted, ...
                LineWidth=1.2, HandleVisibility="off");
    end
end
end
