classdef NonlinearPlugin < dlab.core.TimeDomainPlugin
    %NONLINEARPLUGIN Driven nonlinear oscillators (Duffing, Van der Pol,
    %   and the driven damped pendulum): limit cycles, jumps, period
    %   doubling, and chaos, seen in Poincaré sections and spectra. Solved
    %   by simulateOscillator.

    properties (Constant)
        Id = "nonlinear"
        Title = "Nonlinear Oscillators"
        Category = "Mechanics"
        Summary = "Duffing, Van der Pol, and the driven pendulum: limit cycles, period doubling, and chaos."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        ChaosThreshold = 32       % more distinct section points than this: chaotic (or quasi-periodic)
        TrailSeconds = 12         % Van der Pol animation trail (time units)
        PlaybackRate = 3          % time units per second
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Marker                    % the moving ball on the Potential tab
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isDuffing = @(p) p.model == "duffing";
            isForced = @(p) p.A ~= 0 && p.omega > 0;
            specs = [
                P("model", Label="Model", Type="choice", Default="duffing", ...
                    Choices=["duffing" "vanderpol" "pendulum"], ...
                    ChoiceLabels=["Duffing" "Van der Pol" "Pendulum"], Group="Model", ...
                    Description="Duffing: x'' + δx' + αx + βx³ = A cos ωt.  Van der Pol: x'' − μ(1 − x²)x' + x = " + ...
                    "A cos ωt.  Pendulum: θ'' + θ'/q + sin θ = A cos ωt.")
                P("delta", Label="Damping δ", Default=0.3, Min=0, Max=100, Group="Model", VisibleWhen=isDuffing, ...
                    Description="The damping force is δx' (per unit mass).")
                P("alpha", Label="Linear stiffness α", Default=-1, Min=-100, Max=100, Group="Model", ...
                    VisibleWhen=isDuffing, Description="Negative α with positive β makes a double well.")
                P("beta", Label="Cubic stiffness β", Default=1, Min=-100, Max=100, Group="Model", ...
                    VisibleWhen=isDuffing, Description="β > 0 hardens the spring, β < 0 softens it.")
                P("mu", Label="Nonlinearity μ", Default=1, Min=0, Max=50, Group="Model", ...
                    VisibleWhen=@(p) p.model == "vanderpol", ...
                    Description="Negative damping for |x| < 1, positive outside: a self-sustained oscillation.")
                P("q", Label="Quality factor q", Default=2, Min=0.05, Max=1000, Group="Model", ...
                    VisibleWhen=@(p) p.model == "pendulum", Description="The damping is θ'/q.")
                P("A", Label="Forcing amplitude A", Default=0.5, Min=-100, Max=100, Group="Forcing", ...
                    Description="The right-hand side A cos ωt (a torque for the pendulum). Zero turns the forcing off.")
                P("omega", Label="Forcing frequency ω", Units="rad/s", Default=1.2, Min=0, Max=100, Group="Forcing", ...
                    Description="Zero makes the forcing a constant force A.")
                P("x0", Label="Initial x (θ)", Default=1, Min=-100, Max=100, Group="Start", ...
                    Description="The starting position (the pendulum's angle in rad, 0 hanging down).")
                P("v0", Label="Initial x' (θ')", Default=0, Min=-100, Max=100, Group="Start", ...
                    Description="The starting velocity (rad/s for the pendulum).")
                P("periods", Label="Duration", Units="forcing periods", Type="integer", Default=300, Min=1, ...
                    Max=20000, Group="Simulation", VisibleWhen=isForced, MarksCustom=false, ...
                    Description="The run, in periods of the forcing 2π/ω.")
                P("tspan", Label="Duration", Units="s", Default=200, Min=0.1, Max=1e5, Group="Simulation", ...
                    VisibleWhen=@(p) ~isForced(p), MarksCustom=false, Description="The run, when unforced.")
                P("transient", Label="Transient left out", Units="%", Default=50, Min=0, Max=95, Group="Simulation", ...
                    Description="The start of the run, left out of the Poincaré section, spectrum, and amplitudes.")
                P("samplesPerPeriod", Label="Samples per period", Type="integer", Default=60, Min=8, Max=1000, ...
                    Group="Numerics", Description="Output samples per forcing period (per 2π s when unforced).")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Duffing: chaotic double well", "Values", struct());
            list(end+1) = struct("Name", "Duffing: hardening resonance", "Values", struct( ...
                "delta", 0.1, "alpha", 1, "beta", 0.1, "A", 0.5, "omega", 1.2, "x0", 0, "v0", 0, ...
                "periods", 150, "transient", 60, "samplesPerPeriod", 40));
            list(end+1) = struct("Name", "Van der Pol: limit cycle", "Values", struct( ...
                "model", "vanderpol", "mu", 1, "A", 0, "x0", 0.5, "v0", 0, "tspan", 200, "transient", 50));
            list(end+1) = struct("Name", "Van der Pol: relaxation (μ = 5)", "Values", struct( ...
                "model", "vanderpol", "mu", 5, "A", 0, "x0", 0.5, "v0", 0, "tspan", 200, "transient", 40, ...
                "samplesPerPeriod", 200));
            list(end+1) = struct("Name", "Van der Pol: entrainment", "Values", struct( ...
                "model", "vanderpol", "mu", 1, "A", 1, "omega", 1.1, "x0", 0.5, "v0", 0, "periods", 200, ...
                "transient", 50));
            pendulum = struct("model", "pendulum", "q", 2, "omega", 2/3, "x0", 0, "v0", 0, "periods", 200, ...
                "transient", 50, "samplesPerPeriod", 40);
            list(end+1) = struct("Name", "Driven pendulum: period-1", "Values", withField(pendulum, "A", 0.9));
            list(end+1) = struct("Name", "Driven pendulum: period-2", "Values", withField(pendulum, "A", 1.07));
            list(end+1) = struct("Name", "Driven pendulum: chaos (A = 1.5)", "Values", withField(pendulum, "A", 1.5));
        end

        function result = solve(obj, p)
            q = struct("model", char(p.model), "delta", p.delta, "alpha", p.alpha, "beta", p.beta, ...
                "mu", p.mu, "q", p.q, "A", p.A, "omega", p.omega, "x0", p.x0, "v0", p.v0, ...
                "periods", p.periods, "tspan", p.tspan, "transient", p.transient / 100, ...
                "samplesPerPeriod", p.samplesPerPeriod, "progressFcn", obj.progressMonitor());
            result = dlab.sims.nonlinear.simulateOscillator(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Time series" "Phase portrait" "Poincaré map" "Spectrum" "Potential"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.time = dlab.ui.axesIn(containers{"Time series"}, t, Title="Motion", XLabel="Time (s)", YLabel="x");
            obj.Ax.phase = dlab.ui.axesIn(containers{"Phase portrait"}, t, Title="Phase portrait", ...
                XLabel="x", YLabel="x'");
            obj.Ax.section = dlab.ui.axesIn(containers{"Poincaré map"}, t, Title="Poincaré section", ...
                XLabel="x", YLabel="x'");
            obj.Ax.spectrum = dlab.ui.axesIn(containers{"Spectrum"}, t, Title="Spectrum (after the transient)", ...
                XLabel="Angular frequency (rad/s)", YLabel="Amplitude");
            obj.Ax.potential = dlab.ui.axesIn(containers{"Potential"}, t, Title="Potential energy", ...
                XLabel="x", YLabel="V(x)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Oscillator");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            [xName, vName] = stateNames(params);
            isPendulum = params.model == "pendulum";

            ax = obj.Ax.time;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t(~r.steady), r.x(~r.steady), Color=t.Grid, LineWidth=1, DisplayName="Transient");
            plot(ax, r.t(r.steady), r.x(r.steady), Color=t.series(1), LineWidth=1.2, DisplayName=xName);
            hold(ax, "off");
            ylabel(ax, xName);
            dlab.ui.legend(ax, t, "Location", "northoutside", "Orientation", "horizontal");

            ax = obj.Ax.phase;
            dlab.ui.clearAxes(ax);
            [px, pv] = phaseCurve(r.x, r.v, isPendulum);
            transient = ~r.steady;
            plot(ax, px(transient), pv(transient), Color=t.Grid, LineWidth=0.8, DisplayName="Transient");
            plot(ax, px(r.steady), pv(r.steady), Color=t.series(1), LineWidth=1, DisplayName="After the transient");
            if ~isempty(r.poincare)
                plot(ax, r.poincare(:, 1), r.poincare(:, 2), ".", Color=t.series(2), MarkerSize=10, ...
                    DisplayName="Poincaré points");
            end
            hold(ax, "off");
            xlabel(ax, xName);
            ylabel(ax, vName);
            dlab.ui.legend(ax, t, "Location", "northoutside", "Orientation", "horizontal");

            ax = obj.Ax.section;
            dlab.ui.clearAxes(ax);
            if ~isempty(r.poincare)
                scatter(ax, r.poincare(:, 1), r.poincare(:, 2), 12, (1:size(r.poincare, 1))', "filled");
                colormap(ax, t.sequentialMap());
                sectionLimits(ax, r.poincare, px(r.steady), pv(r.steady));
            else
                set(ax, XLimMode="auto", YLimMode="auto");
            end
            hold(ax, "off");
            xlabel(ax, xName);
            ylabel(ax, vName);
            if r.forced
                title(ax, sprintf("Poincaré section: once per forcing period (%d points)", size(r.poincare, 1)));
            else
                title(ax, sprintf("Poincaré section: at each maximum of %s (%d points)", xName, size(r.poincare, 1)));
            end

            ax = obj.Ax.spectrum;
            dlab.ui.clearAxes(ax);
            s = r.spectrum;
            if ~isempty(s.omega)
                plot(ax, s.omega(2:end), s.magnitude(2:end), Color=t.series(1), LineWidth=1.2);
                if r.forced
                    marks = params.omega ./ [1 2 3];
                    names = ["ω" "ω/2" "ω/3"];
                    % ω/3's label to the left of its line, so it never runs into ω/2's.
                    sides = ["right" "right" "left"];
                    for k = 1:3
                        xline(ax, marks(k), ":", names(k), Color=t.TextMuted, LabelOrientation="horizontal", ...
                            LabelHorizontalAlignment=sides(k), FontSize=t.FontSize.sm);
                    end
                end
                top = 5 * max([params.omega * r.forced, r.dominantFrequency, 1]);
                set(ax, YScale="log", XLim=[0 min(top, s.omega(end))]);
            end
            hold(ax, "off");
            if isPendulum
                title(ax, "Spectrum of θ' (after the transient)");
            end

            obj.drawPotential(r, params);
            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.time, run.Result.t, run.Result.x, run);
                if ~isempty(run.Result.poincare)
                    h = dlab.ui.overlayLine(obj.Ax.section, run.Result.poincare(:, 1), run.Result.poincare(:, 2), run);
                    set(h, LineStyle="none", Marker=".", MarkerSize=8);
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
            obj.Marker = [];
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, ~)
            rate = obj.PlaybackRate;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "kind")
                return
            end
            k = dlab.core.frameAt(r.t, simTime);
            a = obj.Anim;
            x = r.x(k);
            v = r.v(k);
            switch a.kind
                case "well"
                    set(a.ball, XData=x, YData=r.potential(x));
                case "phase"
                    from = find(r.t >= r.t(k) - obj.TrailSeconds, 1);
                    set(a.trail, XData=r.x(from:k), YData=r.v(from:k));
                    set(a.ball, XData=x, YData=v);
                case "pendulum"
                    bob = [sin(x), -cos(x)];
                    set(a.rod, XData=[0 bob(1)], YData=[0 bob(2)]);
                    set(a.ball, XData=bob(1), YData=bob(2));
                    drive = r.params.A * cos(r.params.omega * r.t(k));
                    scale = 0.5 / max(abs(r.params.A), eps);
                    [lx, ly, hx, hy] = dlab.ui.Schematic.arrow([0 1.25], [drive * scale 0], 0.08);
                    set(a.arrow, XData=lx, YData=ly);
                    set(a.head, XData=hx, YData=hy);
            end
            if ~isempty(obj.Marker) && isvalid(obj.Marker) && ~isempty(r.potential)
                if r.params.model == "pendulum"
                    x = wrapAngle(x);                  % the Potential tab shows one turn
                end
                set(obj.Marker, XData=x, YData=r.potential(x));
            end
            a.readout.String = sprintf("t = %.2f s", simTime);
        end

        function T = exportTable(~, r)
            T = table(r.t, r.x, r.v, r.steady, VariableNames=["time" "x" "velocity" "after_transient"]);
            T.Properties.VariableUnits = ["s" "" "1/s" ""];
            if r.params.model == "pendulum"
                T.Properties.VariableNames(2) = "theta";
                T.Properties.VariableUnits(2:3) = ["rad" "rad/s"];
            end
        end

        function T = summaryTable(~, r)
            p = r.params;
            angle = "";
            if p.model == "pendulum"
                angle = "rad";
            end
            rows = {
                "Distinct Poincaré points", r.distinct, ""
                "Largest Poincaré spread", r.spread, ""
                "Steady amplitude", r.amplitude, angle
                "Dominant frequency", r.dominantFrequency, "rad/s"
            };
            if r.forced
                rows(end+1, :) = {"Forcing frequency", p.omega, "rad/s"};
            else
                if p.model == "vanderpol" && ~isempty(r.poincare)
                    rows(end+1, :) = {"Limit-cycle amplitude", mean(r.poincare(:, 1)), ""};
                end
                if isfinite(r.cyclePeriod)
                    rows(end+1, :) = {"Cycle period", r.cyclePeriod, "s"};
                end
            end
            if ~isempty(r.energy)
                rows(end+1, :) = {"Energy at the end", r.energy(end), ""};
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Format = repmat("", height(T), 1);
            T.Display = repmat("", height(T), 1);
            if isfield(r, "overTheTop") && r.overTheTop
                T.Display(T.Quantity == "Steady amplitude") = "— (turns over the top)";
            end
            if isnan(r.dominantFrequency)
                if isfield(r, "atRest") && r.atRest
                    T.Display(T.Quantity == "Dominant frequency") = "— (at rest)";
                else
                    T.Display(T.Quantity == "Dominant frequency") = "— (too few samples)";
                end
            end
        end

        function D = distributions(~, r)
            name = "Poincaré x";
            units = "";
            if r.params.model == "pendulum"
                name = "Poincaré θ";
                units = "rad";
            end
            values = zeros(0, 1);
            if ~isempty(r.poincare)
                values = r.poincare(:, 1);
            end
            D = table(name, {values}, units, VariableNames=["Quantity" "Values" "Units"]);
        end

        function [note, level] = resultNote(obj, r)
            level = "success";
            if ~r.complete
                [note, level] = deal("cancelled", "warning");
            elseif isfield(r, "atRest") && r.atRest
                note = "settles to rest";
            elseif ~r.forced && size(r.poincare, 1) < 2 && isfield(r, "overTheTop") && r.overTheTop
                note = "turns over the top (θ has no maxima)";
            elseif size(r.poincare, 1) < 2
                note = "too short for a Poincaré section";
            elseif r.distinct > obj.ChaosThreshold
                note = sprintf("chaotic or quasi-periodic (%d distinct section points)", r.distinct);
            elseif r.forced
                note = sprintf("period-%d", r.distinct);
            elseif r.distinct == 1
                note = "a periodic cycle";
            else
                note = sprintf("%d different maxima", r.distinct);
            end
        end

        function lin = linearization(~, p)
            switch p.model
                case "duffing"
                    F = @(s) [s(2); -p.delta * s(2) - p.alpha * s(1) - p.beta * s(1)^3];
                    X0 = [0; 0];
                    reference = "x = 0, forcing off";
                    if p.alpha < 0 && p.beta > 0 && p.x0 ~= 0
                        X0 = [sign(p.x0) * sqrt(-p.alpha / p.beta); 0];
                        reference = sprintf("the bottom of the well at x = %.4g, forcing off", X0(1));
                    end
                    names = ["x" "x'"];
                case "vanderpol"
                    F = @(s) [s(2); p.mu * (1 - s(1)^2) * s(2) - s(1)];
                    X0 = [0; 0];
                    reference = "x = 0, forcing off";
                    names = ["x" "x'"];
                otherwise
                    F = @(s) [s(2); -s(2) / p.q - sin(s(1))];
                    X0 = [0; 0];
                    reference = "hanging straight down, forcing off";
                    names = ["θ" "θ'"];
            end
            lin = struct("F", F, "X0", X0, "StateNames", names, "Reference", reference, ...
                "Classify", @modeNames, "Scale", []);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Duffing: chaotic double well", "Tab", "Phase portrait", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Duffing:        x'' + δ x' + α x + β x³ = A cos ωt"
                "Van der Pol:    x'' − μ (1 − x²) x' + x = A cos ωt"
                "Pendulum:       θ'' + θ'/q + sin θ = A cos ωt"
                ""
                "A Poincaré section samples the motion once per forcing period (or, unforced, at each " + ...
                "maximum): a periodic motion leaves one point, a period-2 motion two, and chaos a " + ...
                "fractal cloud. Sweep the forcing amplitude and plot the Poincaré values (all values) " + ...
                "to draw a bifurcation diagram."
                ""
                "Time is in seconds, with the natural frequency of the Van der Pol oscillator and the " + ...
                "pendulum scaled to 1 rad/s (the Duffing's is √α); x is in any unit the coefficients " + ...
                "suit, θ in rad."
                ""
                "Integrated with the classical Runge–Kutta method, with substeps between samples so " + ...
                "that each step is a small fraction of the local time scale."
            ], newline);
        end
    end

    methods (Access = private)
        function drawPotential(obj, r, params)
            t = obj.Theme;
            ax = obj.Ax.potential;
            dlab.ui.clearAxes(ax);
            obj.Marker = [];
            if isempty(r.potential)
                text(ax, 0.5, 0.5, "Van der Pol has no potential well: it is self-excited " + ...
                    "(negative damping for |x| < 1).", Units="normalized", HorizontalAlignment="center", ...
                    Color=t.TextMuted, FontSize=t.FontSize.md);
                set(ax, XTick=[], YTick=[]);
                hold(ax, "off");
                return
            end
            set(ax, XTickMode="auto", YTickMode="auto");
            [lo, hi] = potentialRange(r, params);
            s = linspace(lo, hi, 400);
            plot(ax, s, r.potential(s), Color=t.TextMuted, LineWidth=1.6);
            obj.Marker = plot(ax, NaN, NaN, "o", MarkerSize=10, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
            hold(ax, "off");
            [xName] = stateNames(params);
            xlabel(ax, xName);
            if params.model == "pendulum"
                ylabel(ax, "V(θ) = 1 − cos θ");
            else
                ylabel(ax, "V(x)");
            end
            xlim(ax, [lo hi]);
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            [xName, vName] = stateNames(params);
            switch params.model
                case "duffing"
                    a.kind = "well";
                    [lo, hi] = potentialRange(r, params);
                    s = linspace(lo, hi, 400);
                    V = r.potential(s);
                    plot(ax, s, V, Color=t.TextMuted, LineWidth=2);
                    a.ball = plot(ax, NaN, NaN, "o", MarkerSize=16, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
                    set(ax, XLim=[lo hi], YLim=[min(V) max(V)] + [-0.1 0.1] * max(range2(V), eps), ...
                        DataAspectRatioMode="auto");
                    xlabel(ax, xName);
                    ylabel(ax, "V(x)");
                    title(ax, "Ball in the potential well");
                case "vanderpol"
                    a.kind = "phase";
                    plot(ax, r.x(r.steady), r.v(r.steady), Color=t.Grid, LineWidth=0.8);
                    a.trail = plot(ax, NaN, NaN, Color=t.series(1), LineWidth=1.8);
                    a.ball = plot(ax, NaN, NaN, "o", MarkerSize=10, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
                    pad = 0.1 * max([range2(r.x), range2(r.v), eps]);
                    set(ax, XLim=[min(r.x) max(r.x)] + [-pad pad], YLim=[min(r.v) max(r.v)] + [-pad pad], ...
                        DataAspectRatioMode="auto");
                    xlabel(ax, xName);
                    ylabel(ax, vName);
                    title(ax, "Phase plane");
                otherwise
                    a.kind = "pendulum";
                    [cx, cy] = dlab.ui.Schematic.circle([0 0], 1, 90);
                    plot(ax, cx, cy, ":", Color=t.Grid);
                    plot(ax, 0, 0, "o", MarkerSize=6, MarkerFaceColor=t.Text, MarkerEdgeColor=t.Text);
                    a.rod = plot(ax, NaN, NaN, Color=t.Text, LineWidth=2.5);
                    a.ball = plot(ax, NaN, NaN, "o", MarkerSize=18, MarkerFaceColor=t.series(1), MarkerEdgeColor=t.Text);
                    a.arrow = plot(ax, NaN, NaN, Color=t.series(2), LineWidth=2);
                    a.head = patch(ax, NaN, NaN, t.series(2), EdgeColor="none");
                    text(ax, 0, 1.45, "drive torque", HorizontalAlignment="center", Color=t.TextMuted, ...
                        FontSize=t.FontSize.sm);
                    set(ax, XLim=[-1.6 1.6], YLim=[-1.3 1.6]);
                    daspect(ax, [1 1 1]);
                    xlabel(ax, "");
                    ylabel(ax, "");
                    title(ax, "Driven pendulum");
            end
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function s = withField(s, name, value)
s.(name) = value;
end

function [xName, vName] = stateNames(params)
if params.model == "pendulum"
    [xName, vName] = deal("θ (rad)", "θ' (rad/s)");
else
    [xName, vName] = deal("x", "x'");
end
end

function [px, pv] = phaseCurve(x, v, wrap)
% The pendulum's angle wrapped to (−π, π], with breaks where it wraps.
px = x;
pv = v;
if ~wrap
    return
end
px = mod(x + pi, 2 * pi) - pi;
jumps = [false; abs(diff(px)) > pi];
px(jumps) = NaN;
pv(jumps) = NaN;
end

function [lo, hi] = potentialRange(r, params)
% The range the motion covers, with some margin (at least the wells).
lo = min(r.x);
hi = max(r.x);
if params.model == "pendulum"
    % One turn: the angle is shown wrapped to (−π, π].
    lo = -pi;
    hi = pi;
elseif params.alpha < 0 && params.beta > 0
    well = sqrt(-params.alpha / params.beta);
    lo = min(lo, -1.6 * well);
    hi = max(hi, 1.6 * well);
end
pad = 0.1 * max(hi - lo, 1);
lo = lo - pad;
hi = hi + pad;
end

function sectionLimits(ax, points, x, v)
% Limits around the section points, at least a tenth of the motion's size
% on each axis, so a periodic orbit shows as separate dots rather than its
% rounding noise magnified a billion times.
x = x(isfinite(x));
v = v(isfinite(v));
least = 0.1 * [range2([x; points(:, 1)]), range2([v; points(:, 2)])];
lo = min(points, [], 1);
hi = max(points, [], 1);
half = max(0.55 * (hi - lo), least / 2);
half(half <= 0) = 1;
middle = (lo + hi) / 2;
set(ax, XLim=middle(1) + [-1 1] * half(1), YLim=middle(2) + [-1 1] * half(2));
end

function a = wrapAngle(a)
a = mod(a + pi, 2 * pi) - pi;
end

function d = range2(values)
d = max(values(:)) - min(values(:));
end

function labels = modeNames(lambda, ~)
%MODENAMES Oscillation, settling, or (with eigenvalues of both signs) a saddle.
labels = strings(numel(lambda), 1);
saddle = any(real(lambda) > 1e-9) && any(real(lambda) < -1e-9) && all(abs(imag(lambda)) < 1e-9);
for k = 1:numel(lambda)
    if abs(imag(lambda(k))) > 1e-9
        labels(k) = "Oscillation";
    elseif saddle
        labels(k) = "Unstable (saddle)";
    elseif real(lambda(k)) < 0
        labels(k) = "Settling";
    else
        labels(k) = "Growing";
    end
end
end
