classdef AttractorsPlugin < dlab.core.TimeDomainPlugin
    %ATTRACTORSPLUGIN Strange attractors (Lorenz, Rössler, Chua): a 3-D
    %   trajectory with a growing trail, a twin started 10⁻⁸ away to show
    %   sensitive dependence, the largest Lyapunov exponent, and the
    %   successive maxima (a return map, and set-valued results for
    %   bifurcation sweeps). Solved by simulateAttractor.

    properties (Constant)
        Id = "attractors"
        Title = "Strange Attractors"
        Category = "Mechanics"
        Summary = "Lorenz, Rössler, and Chua: butterflies, sensitive dependence, and Lyapunov exponents."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        ChaosThreshold = 32       % more distinct maxima than this: chaotic
        LambdaThreshold = 0.01    % |λ| below this: zero within the estimate's accuracy
        TrailSeconds = 3          % time units of trail behind the moving point
        PlaybackSeconds = 25      % a run plays in about this many seconds at 1×
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            is = @(name) @(p) p.model == name;
            specs = [
                P("model", Label="System", Type="choice", Default="lorenz", Choices=["lorenz" "rossler" "chua"], ...
                    ChoiceLabels=["Lorenz" "Rössler" "Chua's circuit"], Group="System", ...
                    Description="Lorenz: x' = σ(y − x), y' = x(ρ − z) − y, z' = xy − βz.  Rössler: x' = −y − z, " + ...
                    "y' = x + ay, z' = b + z(x − c).  Chua: x' = α(y − x − f(x)), y' = x − y + z, z' = −βy.")
                P("sigma", Label="σ (Prandtl number)", Default=10, Min=0, MinInclusive=false, Max=100, ...
                    Group="System", VisibleWhen=is("lorenz"), ...
                    Description="Lorenz's σ, the ratio of viscosity to heat diffusion (10 in Lorenz's paper).")
                P("rho", Label="ρ (relative Rayleigh number)", Default=28, Min=0, Max=500, Group="System", ...
                    VisibleWhen=is("lorenz"), Description="The Rayleigh number over its value at the onset " + ...
                    "of convection. For σ = 10, β = 8/3: the wing centres C± are stable below ρ ≈ 24.74; " + ...
                    "the butterfly exists from ρ ≈ 24.06, with periodic windows (such as ρ = 160) above.")
                P("beta", Label="β", Default=8/3, Min=0, MinInclusive=false, Max=20, Group="System", ...
                    VisibleWhen=is("lorenz"), DisplayFormat="%.4g", Description="A geometric factor of the " + ...
                    "convection cell (8/3 in Lorenz's paper).")
                P("a", Label="a", Default=0.2, Min=-1, Max=1, Group="System", VisibleWhen=is("rossler"), ...
                    Description="Rössler's a in y' = x + a y: how strongly the spiral grows.")
                P("b", Label="b", Default=0.2, Min=0, Max=5, Group="System", VisibleWhen=is("rossler"), ...
                    Description="Rössler's b in z' = b + z(x − c).")
                P("c", Label="c", Default=5.7, Min=0, Max=30, Group="System", VisibleWhen=is("rossler"), ...
                    Description="With a = b = 0.2: period-1, -2, -4 … as c grows, chaos from about c = 4.2.")
                P("alpha", Label="α", Default=15.6, Min=0, MinInclusive=false, Max=50, Group="System", ...
                    VisibleWhen=is("chua"), ...
                    Description="Chua's α in x' = α(y − x − f(x)).")
                P("betaChua", Label="β", Default=28, Min=0, MinInclusive=false, Max=100, Group="System", ...
                    VisibleWhen=is("chua"), ...
                    Description="Chua's β in z' = −β y.")
                P("m0", Label="Inner slope m0", Default=-1.143, Min=-5, Max=5, Group="System", ...
                    VisibleWhen=is("chua"), Description="The diode's slope for |x| < 1.")
                P("m1", Label="Outer slope m1", Default=-0.714, Min=-5, Max=5, Group="System", ...
                    VisibleWhen=is("chua"), Description="The diode's slope for |x| > 1.")
                P("x0", Label="Start x", Default=1, Min=-100, Max=100, Group="Start", ...
                    Description="Where the trajectory starts (dimensionless).")
                P("y0", Label="Start y", Default=1, Min=-100, Max=100, Group="Start", ...
                    Description="Where the trajectory starts (dimensionless).")
                P("z0", Label="Start z", Default=1, Min=-100, Max=100, Group="Start", ...
                    Description="Where the trajectory starts (dimensionless).")
                P("delta", Label="Twin offset in x", Default=1e-8, Min=0, MinInclusive=false, Max=1, Group="Start", DisplayFormat="%.3g", ...
                    Description="A second run starts this far away: watch the two separate.")
                P("tspan", Label="Duration", Default=100, Min=1, Max=5000, Group="Simulation", MarksCustom=false, ...
                    Description="How long to simulate, in the model's time units.")
                P("transient", Label="Transient left out", Units="%", Default=10, Min=0, Max=90, Group="Simulation", ...
                    Description="The start of the run, left out of the maxima and the Lyapunov exponent.")
                P("dt", Label="Output step", Default=0.01, Min=1e-4, Max=1, Group="Numerics", ...
                    DisplayFormat="%.3g", ...
                    Description="Spacing of the saved samples, in the model's time units; the solver picks its own steps.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Lorenz butterfly (ρ = 28)", "Values", struct());
            list(end+1) = struct("Name", "Lorenz: settles to a fixed point (ρ = 14)", "Values", struct("rho", 14));
            list(end+1) = struct("Name", "Lorenz: periodic window (ρ = 160)", "Values", struct("rho", 160, "tspan", 60, "transient", 50));
            list(end+1) = struct("Name", "Rössler: period-1 (c = 2.5)", "Values", struct( ...
                "model", "rossler", "c", 2.5, "tspan", 400, "dt", 0.02, "transient", 30));
            list(end+1) = struct("Name", "Rössler: period-2 (c = 3.5)", "Values", struct( ...
                "model", "rossler", "c", 3.5, "tspan", 400, "dt", 0.02, "transient", 30));
            list(end+1) = struct("Name", "Rössler: chaos (c = 5.7)", "Values", struct( ...
                "model", "rossler", "c", 5.7, "tspan", 400, "dt", 0.02, "transient", 20));
            list(end+1) = struct("Name", "Chua double scroll", "Values", struct( ...
                "model", "chua", "x0", 0.7, "y0", 0, "z0", 0, "tspan", 150));
        end

        function result = solve(obj, p)
            q = struct("model", char(p.model), "sigma", p.sigma, "rho", p.rho, "beta", p.beta, ...
                "a", p.a, "b", p.b, "c", p.c, "alpha", p.alpha, "betaChua", p.betaChua, "m0", p.m0, ...
                "m1", p.m1, "x0", p.x0, "y0", p.y0, "z0", p.z0, "delta", p.delta, "tspan", p.tspan, ...
                "dt", p.dt, "transient", p.transient / 100, "progressFcn", obj.progressMonitor());
            result = dlab.sims.attractors.simulateAttractor(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Attractor" "Time series" "Sensitivity" "Return map"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.attractor = dlab.ui.axesIn(containers{"Attractor"}, t, Title="Attractor", ...
                XLabel="x", YLabel="y");
            obj.Ax.time = dlab.ui.axesIn(containers{"Time series"}, t, Title="Coordinates", XLabel="Time");
            grid = uigridlayout(containers{"Sensitivity"}, [2 1], RowHeight={"1x", "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.Surface);
            obj.Ax.separation = dlab.ui.axesIn(grid, t, Title="Distance between the twins", ...
                XLabel="Time", YLabel="|Δ|");
            obj.Ax.lambda = dlab.ui.axesIn(grid, t, Title="Largest Lyapunov exponent (running estimate)", ...
                XLabel="Time", YLabel="λ (1/time)");
            obj.Ax.returnMap = dlab.ui.axesIn(containers{"Return map"}, t, Title="Return map");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Trajectory");
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            X = r.X;
            names = ["x" "y" "z"];

            ax = obj.Ax.attractor;
            dlab.ui.clearAxes(ax);
            plot3(ax, X(~r.steady, 1), X(~r.steady, 2), X(~r.steady, 3), Color=t.Grid, LineWidth=0.6, ...
                DisplayName="Transient");
            width = 0.7;                      % a dense chaotic tangle
            if r.settled || r.distinct <= obj.ChaosThreshold
                width = 1.5;                  % a cycle, drawn over itself
            end
            plot3(ax, X(r.steady, 1), X(r.steady, 2), X(r.steady, 3), Color=t.series(1), LineWidth=width, ...
                DisplayName="Trajectory");
            if ~isempty(r.equilibria)
                E = r.equilibria;
                plot3(ax, E(:, 1), E(:, 2), E(:, 3), "o", MarkerSize=7, MarkerFaceColor=t.series(2), ...
                    MarkerEdgeColor=t.Text, DisplayName="Equilibria");
            end
            hold(ax, "off");
            zlabel(ax, "z");
            view(ax, viewFor(params));
            dlab.ui.legend(ax, t, "Location", "northeast");

            ax = obj.Ax.time;
            dlab.ui.clearAxes(ax);
            for k = 1:3
                plot(ax, r.t, X(:, k), Color=t.series(k), LineWidth=1, DisplayName=names(k));
            end
            if any(~r.steady)
                xline(ax, r.t(find(r.steady, 1)), ":", "end of transient", Color=t.TextMuted, ...
                    LabelOrientation="horizontal", FontSize=t.FontSize.sm, HandleVisibility="off");
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "northoutside", "Orientation", "horizontal");

            ax = obj.Ax.separation;
            dlab.ui.clearAxes(ax);
            separation = r.separation;
            separation(separation <= 0) = NaN;   % identical twins: nothing to draw on a log scale
            semilogy(ax, r.t, separation, Color=t.series(1), LineWidth=1.2, DisplayName="|Δ|");
            if isfield(r, "growthAmplitude") && isfinite(r.growthAmplitude)
                % Slope λ, placed through the twins' exponential growth.
                predicted = r.growthAmplitude * exp(r.lambda * r.t);
                shown = predicted < 2 * r.extent & predicted > 0.1 * params.delta;
                semilogy(ax, r.t(shown), predicted(shown), "--", Color=t.series(2), LineWidth=1.2, ...
                    DisplayName=sprintf("∝ e^{λt}, λ = %.3f", r.lambda));
            end
            if isfinite(r.divergenceTime)
                xline(ax, r.divergenceTime, ":", sprintf("apart at t = %.1f", r.divergenceTime), ...
                    Color=t.TextMuted, LabelOrientation="horizontal", LabelVerticalAlignment="bottom", ...
                    FontSize=t.FontSize.sm, HandleVisibility="off");
            end
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "southeast");

            ax = obj.Ax.lambda;
            dlab.ui.clearAxes(ax);
            plot(ax, r.lambdaT, r.lambdaHistory, Color=t.series(3), LineWidth=1.2);
            yline(ax, 0, ":", Color=t.TextMuted);
            hold(ax, "off");
            if isfinite(r.lambda)
                title(ax, sprintf("Largest Lyapunov exponent: λ ≈ %.4f", r.lambda));
            end

            ax = obj.Ax.returnMap;
            dlab.ui.clearAxes(ax);
            m = r.maxima;
            label = r.sectionName + "_n";
            if numel(m) >= 2
                dots = 14;                    % many points: small
                if r.distinct <= obj.ChaosThreshold
                    dots = 40;                % a cycle's few points: easy to see
                end
                scatter(ax, m(1:end-1), m(2:end), dots, (1:numel(m) - 1)', "filled");
                colormap(ax, t.sequentialMap());
                % At least a tenth of the attractor's size: a cycle is a
                % dot, not a zoom into its slow convergence.
                middle = (min(m) + max(m)) / 2;
                half = 0.65 * max(max(m) - min(m), 0.1 * max(r.extent, eps));
                lo = middle - half;
                hi = middle + half;
                plot(ax, [lo hi], [lo hi], ":", Color=t.TextMuted);
                set(ax, XLim=[lo hi], YLim=[lo hi]);
                title(ax, sprintf("Return map: each maximum of %s against the previous one (%d maxima)", ...
                    r.sectionName, numel(m)));
            else
                title(ax, "Return map: too few maxima (the motion settles, or the run is too short)");
            end
            hold(ax, "off");
            xlabel(ax, "max " + label);
            ylabel(ax, "max " + r.sectionName + "_{n+1}");

            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Ax.time, run.Result.t, run.Result.X(:, 1), run);
                m = run.Result.maxima;
                if numel(m) >= 2
                    h = dlab.ui.overlayLine(obj.Ax.returnMap, m(1:end-1), m(2:end), run);
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
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, r)
            rate = max(r.t(end) / obj.PlaybackSeconds, 0.1);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "trail")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            from = find(r.t >= r.t(k) - obj.TrailSeconds, 1);
            set(a.trail, XData=r.X(from:k, 1), YData=r.X(from:k, 2), ZData=r.X(from:k, 3));
            set(a.point, XData=r.X(k, 1), YData=r.X(k, 2), ZData=r.X(k, 3));
            set(a.twinTrail, XData=r.twin(from:k, 1), YData=r.twin(from:k, 2), ZData=r.twin(from:k, 3));
            set(a.twinPoint, XData=r.twin(k, 1), YData=r.twin(k, 2), ZData=r.twin(k, 3));
            a.readout.String = sprintf("t = %.2f    |Δ| = %.2g", r.t(k), r.separation(k));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.X(:, 1), r.X(:, 2), r.X(:, 3), r.separation, r.steady, ...
                VariableNames=["time" "x" "y" "z" "twin_distance" "after_transient"]);
            T.Properties.VariableUnits = ["time units" "" "" "" "" ""];   % the model is dimensionless
        end

        function T = summaryTable(obj, r)
            rows = {
                "Largest Lyapunov exponent", r.lambda, "1/time"
                "Distinct maxima", r.distinct, ""
                "Attractor size", r.extent, ""
                "Settled at an equilibrium", double(r.settled), ""
            };
            if isfinite(r.divergenceTime)
                rows(end+1, :) = {"Twins apart (10 % of the size)", r.divergenceTime, "time"};
            end
            if r.lambda > obj.LambdaThreshold
                rows(end+1, :) = {"Lyapunov time (1/λ)", 1 / r.lambda, "time"};
            end
            rows(end+1, :) = {"Equilibria", size(r.equilibria, 1), ""};
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = repmat("", height(T), 1);
            T.Display(T.Quantity == "Settled at an equilibrium") = pick(r.settled, "yes", "no");
            if r.settled
                T.Display(T.Quantity == "Distinct maxima") = "— (settled)";
            end
        end

        function D = distributions(~, r)
            D = table("Maxima of " + r.sectionName, {r.maxima}, "", VariableNames=["Quantity" "Values" "Units"]);
        end

        function [note, level] = resultNote(obj, r)
            level = "success";
            if ~r.complete
                [note, level] = deal("cancelled", "warning");
            elseif r.settled
                note = "settles to an equilibrium";
            elseif r.distinct > obj.ChaosThreshold && r.lambda > obj.LambdaThreshold
                note = sprintf("chaotic (λ ≈ %.3f)", r.lambda);
            elseif r.distinct >= 1 && r.distinct <= obj.ChaosThreshold
                note = sprintf("periodic: %d distinct maxima", r.distinct);
            else
                note = sprintf("λ ≈ %.3f", r.lambda);
            end
        end

        function lin = linearization(~, p)
            q = struct("model", char(p.model), "sigma", p.sigma, "rho", p.rho, "beta", p.beta, "a", p.a, ...
                "b", p.b, "c", p.c, "alpha", p.alpha, "betaChua", p.betaChua, "m0", p.m0, "m1", p.m1);
            [F, X0, reference] = equilibriumFor(q);
            if isempty(X0)
                lin = [];             % no equilibrium to linearize about
                return
            end
            lin = struct("F", F, "X0", X0, "StateNames", ["x" "y" "z"], "Reference", reference, ...
                "Classify", @modeNames, "Scale", [], "TimeUnit", "time unit");   % the model is dimensionless
        end

        function scene = showcase(~)
            scene = struct("Preset", "Lorenz butterfly (ρ = 28)", "Tab", "Attractor", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Lorenz:   x' = σ(y − x),  y' = x(ρ − z) − y,  z' = xy − βz"
                "Rössler:  x' = −y − z,  y' = x + ay,  z' = b + z(x − c)"
                "Chua:     x' = α(y − x − f(x)),  y' = x − y + z,  z' = −βy,  " + ...
                "f(x) = m1·x + ½(m0 − m1)(|x + 1| − |x − 1|)"
                ""
                "A twin starts a tiny distance away (in x). On a strange attractor the two separate " + ...
                "exponentially, at the rate of the largest Lyapunov exponent λ, until they are as far " + ...
                "apart as the attractor is wide."
                ""
                "λ is measured properly, not from the twins: the linearized (tangent) equations are " + ...
                "integrated along the trajectory and renormalized every 10 time units (Benettin's " + ...
                "method). λ > 0 means chaos; λ ≈ 0, a periodic orbit; λ < 0, a fixed point."
                ""
                "The return map plots each maximum of z (Lorenz) or x against the previous one. Sweep " + ...
                "ρ or c and plot the maxima (all values) for a bifurcation diagram."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            plot3(ax, r.X(:, 1), r.X(:, 2), r.X(:, 3), Color=t.Grid, LineWidth=0.5);
            a.twinTrail = plot3(ax, NaN, NaN, NaN, Color=t.series(2), LineWidth=1.6);
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.series(1), LineWidth=2);
            a.twinPoint = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=8, MarkerFaceColor=t.series(2), ...
                MarkerEdgeColor=t.Text);
            a.point = plot3(ax, NaN, NaN, NaN, "o", MarkerSize=9, MarkerFaceColor=t.series(1), ...
                MarkerEdgeColor=t.Text);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            pad = 0.05 * max(r.extent, eps);
            set(ax, XLim=[min(r.X(:, 1)) max(r.X(:, 1))] + [-pad pad], ...
                YLim=[min(r.X(:, 2)) max(r.X(:, 2))] + [-pad pad], ...
                ZLim=[min(r.X(:, 3)) max(r.X(:, 3))] + [-pad pad]);
            xlabel(ax, "x");
            ylabel(ax, "y");
            zlabel(ax, "z");
            view(ax, viewFor(params));
            title(ax, "Trajectory (blue) and its twin (started " + sprintf("%.3g", params.delta) + " away)");
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function v = viewFor(params)
switch params.model
    case "lorenz"
        v = [-35 18];
    case "rossler"
        v = [-40 30];
    otherwise
        v = [-25 25];
end
end

function [F, X0, reference] = equilibriumFor(q)
% The free system and the equilibrium the Modes tab looks at: the one the
% motion circles (Lorenz C+, Rössler's inner one, Chua's P+ at the centre
% of a scroll, else the origin). X0 is empty when there is none.
switch q.model
    case 'lorenz'
        F = @(x) [q.sigma * (x(2) - x(1)); x(1) * (q.rho - x(3)) - x(2); x(1) * x(2) - q.beta * x(3)];
        if q.rho > 1
            k = sqrt(q.beta * (q.rho - 1));
            X0 = [k; k; q.rho - 1];
            reference = sprintf("the equilibrium C+ = (%.3g, %.3g, %.3g)", X0);
        else
            X0 = [0; 0; 0];
            reference = "the origin";
        end
    case 'rossler'
        F = @(x) [-x(2) - x(3); x(1) + q.a * x(2); q.b + x(3) * (x(1) - q.c)];
        disc = q.c^2 - 4 * q.a * q.b;
        if q.a == 0 || disc < 0
            [X0, reference] = deal([], "");
            return
        end
        x = (q.c - sqrt(disc)) / 2;
        X0 = [x; -x / q.a; x / q.a];
        reference = sprintf("the inner equilibrium (%.3g, %.3g, %.3g)", X0);
    otherwise
        diode = @(x) q.m1 * x + 0.5 * (q.m0 - q.m1) * (abs(x + 1) - abs(x - 1));
        F = @(x) [q.alpha * (x(2) - x(1) - diode(x(1))); x(1) - x(2) + x(3); -q.betaChua * x(2)];
        X0 = [0; 0; 0];
        reference = "the origin";
        k = (q.m1 - q.m0) / (q.m1 + 1);
        if q.m1 ~= -1 && k > 1
            % P+ = (k, 0, −k), the centre of the right-hand scroll (k = 1
            % would sit on the diode's corner, where the slope jumps).
            X0 = [k; 0; -k];
            reference = sprintf("the equilibrium P+ = (%.3g, 0, %.3g), the centre of a scroll", k, -k);
        end
end
end

function labels = modeNames(lambda, ~)
%MODENAMES Spiralling or straight, in or out.
labels = strings(numel(lambda), 1);
for k = 1:numel(lambda)
    spiral = abs(imag(lambda(k))) > 1e-9;
    if real(lambda(k)) > 1e-9
        labels(k) = "Unstable " + pick(spiral, "spiral (out)", "direction");
    elseif real(lambda(k)) < -1e-9
        labels(k) = "Stable " + pick(spiral, "spiral (in)", "direction");
    else
        labels(k) = "Neutral";
    end
end
end

function s = pick(condition, yes, no)
s = no;
if condition
    s = yes;
end
end
