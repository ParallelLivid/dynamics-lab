classdef HeatPlugin < dlab.core.TimeDomainPlugin
    %HEATPLUGIN 1-D heat conduction in a rod or wall: explicit, implicit,
    %   and Crank–Nicolson schemes, fixed-temperature, heat-flux, and
    %   convection ends (end temperatures can change during the run), and
    %   the explicit scheme's stability limit.

    properties (Constant)
        Id = "heat"
        Title = "1-D Heat Conduction"
        Category = "Continuum"
        Summary = "Heat spreading through a rod or wall: schemes, stability, and boundary conditions."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        Materials = struct( ...
            "copper",    struct("k", 401,  "rho", 8960, "c", 385), ...
            "aluminium", struct("k", 237,  "rho", 2700, "c", 897), ...
            "steel",     struct("k", 50,   "rho", 7850, "c", 490), ...
            "brick",     struct("k", 0.7,  "rho", 1800, "c", 840), ...
            "water",     struct("k", 0.6,  "rho", 1000, "c", 4186))
        Probes = (1:3) / 4           % fractions of the length (quarter points)
        PlaySeconds = 15
    end

    properties (Access = private)
        Ax struct = struct()
        Plots struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            custom = @(p) p.material == "custom";
            sides = struct("left", "Left end", "right", "Right end");
            specs = [
                P("material", Label="Material", Type="choice", Default="copper", ...
                    Choices=["copper" "aluminium" "steel" "brick" "water" "custom"], ...
                    ChoiceLabels=["Copper" "Aluminium" "Steel" "Brick" "Water" "Custom"], Group="Rod", ...
                    Description="Sets the conductivity k, density ρ, and specific heat c (diffusivity α = k/ρc).")
                P("k", Label="Conductivity k", Units="W/(m·K)", Default=401, Min=0.01, Max=2000, Group="Rod", ...
                    VisibleWhen=custom, Description="How readily the material conducts heat.")
                P("rho", Label="Density ρ", Units="kg/m³", Default=8960, Min=1, Max=30000, Group="Rod", ...
                    VisibleWhen=custom, Description="Mass per volume; with c, the heat stored per degree.")
                P("c", Label="Specific heat c", Units="J/(kg·K)", Default=385, Min=10, Max=20000, Group="Rod", ...
                    VisibleWhen=custom, Description="Heat to warm one kilogram by one degree.")
                P("L", Label="Length", Units="m", Default=1, Min=0.001, Max=100, Group="Rod", ...
                    Description="The rod's length, or a wall's thickness.")
                P("q", Label="Heat source", Units="W/m³", Default=0, Min=-1e8, Max=1e8, Group="Rod", ...
                    Description="Heat generated uniformly in the rod (e.g. electrical heating).")
                endSpecs(P, "left", sides.left)
                endSpecs(P, "right", sides.right)
                P("initial", Label="Initial temperature", Type="choice", Default="sine", ...
                    Choices=["uniform" "step" "sine" "hotspot"], ...
                    ChoiceLabels=["Uniform" "Step" "Sine mode" "Hot spot"], Group="Initial temperature", ...
                    Description="Uniform; a step (hotter left of the position); a sine mode, a standing sine " + ...
                    "on top of the straight line between fixed ends (the exact solution is then known); or a " + ...
                    "Gaussian hot spot.")
                P("T0", Label="Base temperature", Units="°C", Default=20, Min=-273, Max=5000, ...
                    Group="Initial temperature", Description="The starting temperature, before the step, sine, or spot.")
                P("amplitude", Label="Amplitude", Units="°C", Default=50, Min=-5000, Max=5000, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial ~= "uniform", ...
                    Description="How much hotter the step, sine peak, or spot is than the base.")
                P("mode", Label="Sine mode n", Type="integer", Default=1, Min=1, Max=50, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial == "sine", ...
                    Description="Half-waves along the rod: sin(nπx/L), decaying as exp(−α (nπ/L)² t).")
                P("position", Label="Position", Units="× L", Default=0.5, Min=0, Max=1, ...
                    Group="Initial temperature", VisibleWhen=@(p) ismember(p.initial, ["step" "hotspot"]), ...
                    Description="Where the step is, or the hot spot's centre, as a fraction of the length.")
                P("width", Label="Width", Units="× L", Default=0.05, Min=0.005, Max=1, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial == "hotspot", ...
                    Description="The hot spot's half-width (where it falls to 1/e), as a fraction of the length.")
                P("scheme", Label="Scheme", Type="choice", Default="cranknicolson", ...
                    Choices=["explicit" "implicit" "cranknicolson"], ...
                    ChoiceLabels=["Explicit" "Implicit" "Crank–Nicolson"], Group="Numerics", ...
                    Description="Explicit (forward Euler, FTCS) is stable only for r = α Δt / Δx² ≤ ½; implicit " + ...
                    "(backward Euler) and Crank–Nicolson always are. Crank–Nicolson is second-order accurate " + ...
                    "in time, the others first-order.")
                P("N", Label="Grid nodes", Type="integer", Default=51, Min=5, Max=801, Group="Numerics", ...
                    Description="Nodes along the rod, ends included: Δx = L / (N − 1).")
                P("dt", Label="Time step", Units="s", Default=1, Min=1e-6, Max=1e6, Group="Numerics", ...
                    DisplayFormat="%.6g", Description="Shortened slightly, if needed, to land exactly on the " + ...
                    "duration. Sets r = α Δt / Δx².")
                P("tspan", Label="Duration", Units="s", Default=1800, Min=1e-3, Max=1e8, Group="Simulation", ...
                    MarksCustom=false, Description="How long to follow the rod.")
                P("dtOut", Label="Output step", Units="s", Default=30, Min=1e-6, Max=1e7, Group="Simulation", ...
                    Description="Spacing of the saved profiles (rounded to whole time steps).")
                P("showExact", Label="Show the exact solution", Type="logical", Default=true, Group="Display", ...
                    Display=true, Description="When it is known (sine start between fixed, constant end temperatures).")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            alpha = 401 / (8960 * 385);
            dx = 1 / 50;
            list(end+1) = struct("Name", "Cooling bar (sine mode)", "Values", struct());
            list(end+1) = struct("Name", "Explicit at the stability limit (r = 0.5)", "Values", struct( ...
                "scheme", "explicit", "initial", "hotspot", "amplitude", 80, "dt", 0.5 * dx^2 / alpha, "tspan", 900));
            list(end+1) = struct("Name", "Explicit beyond the limit (r = 0.55)", "Values", struct( ...
                "scheme", "explicit", "initial", "hotspot", "amplitude", 80, "dt", 0.55 * dx^2 / alpha, "tspan", 900));
            list(end+1) = struct("Name", "Hot spot spreading (insulated ends)", "Values", struct( ...
                "leftType", "neumann", "rightType", "neumann", "initial", "hotspot", "amplitude", 80, ...
                "tspan", 1200, "dt", 2));
            list(end+1) = struct("Name", "Daily temperature cycle in a brick wall", "Values", struct( ...
                "material", "brick", "k", 0.7, "rho", 1800, "c", 840, "L", 0.3, "N", 31, ...
                "leftT", dlab.core.Schedule.make("sine", Value=15, Amplitude=10, Start=0, Period=86400), ...
                "rightType", "robin", "rightH", 8, "rightTinf", 20, "initial", "uniform", "T0", 17, ...
                "dt", 600, "tspan", 3 * 86400, "dtOut", 1800));
            list(end+1) = struct("Name", "Rod heated at one end, cooled at the other", "Values", struct( ...
                "material", "aluminium", "k", 237, "rho", 2700, "c", 897, "L", 0.2, "leftT", 100, ...
                "rightType", "robin", "rightH", 500, "rightTinf", 20, "initial", "uniform", "T0", 20, ...
                "dt", 0.5, "tspan", 600, "dtOut", 5));
        end

        function params = onParamChanged(obj, name, params)
            % Picking a material fills in its properties.
            if name == "material" && params.material ~= "custom"
                m = obj.Materials.(params.material);
                [params.k, params.rho, params.c] = deal(m.k, m.rho, m.c);
            end
        end

        function result = solve(obj, p)
            q = struct("L", p.L, "N", p.N, "k", p.k, "rho", p.rho, "c", p.c, "q", p.q, ...
                "scheme", char(p.scheme), "dt", p.dt, "tspan", p.tspan, "dtOut", p.dtOut, ...
                "left", endFor(p, "left"), "right", endFor(p, "right"), ...
                "initial", struct("type", char(p.initial), "T0", p.T0, "amplitude", p.amplitude, ...
                    "mode", p.mode, "position", p.position, "width", p.width), ...
                "progressFcn", obj.progressMonitor());
            if p.material ~= "custom"
                m = obj.Materials.(p.material);
                [q.k, q.rho, q.c] = deal(m.k, m.rho, m.c);
            end
            result = dlab.sims.heat.simulateHeat(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Temperature profile" "Space-time" "Probes" "Energy"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.profile = dlab.ui.axesIn(containers{"Temperature profile"}, t, ...
                Title="Temperature along the rod", XLabel="x (m)", YLabel="T (°C)");
            obj.Ax.spacetime = dlab.ui.axesIn(containers{"Space-time"}, t, ...
                Title="Temperature over space and time", XLabel="x (m)", YLabel="Time (s)");
            obj.Ax.probes = dlab.ui.axesIn(containers{"Probes"}, t, Title="Temperature at three points", ...
                XLabel="Time (s)", YLabel="T (°C)");
            obj.Ax.energy = dlab.ui.axesIn(containers{"Energy"}, t, Title="Energy balance", ...
                XLabel="Time (s)", YLabel="Energy (kJ/m²)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Rod", XLabel="x (m)", YLabel="T (°C)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;
            low = min(r.T(:));
            high = max(r.T(:));
            if high - low < 1e-9
                [low, high] = deal(low - 1, high + 1);
            end
            hasExact = ~isempty(r.exact) && params.showExact;

            ax = obj.Ax.profile;
            dlab.ui.clearAxes(ax);
            snapshots = unique(round(linspace(1, numel(r.t), 6)));
            for k = snapshots(1:end-1)
                plot(ax, r.x, r.T(k, :), Color=[t.series(1) 0.3], LineWidth=1, HandleVisibility="off");
            end
            plot(ax, r.x, r.T(1, :), ":", Color=t.TextMuted, LineWidth=1.2, DisplayName="Start");
            plot(ax, r.x, r.T(end, :), Color=t.series(1), LineWidth=2, ...
                DisplayName=sprintf("t = %s", dlab.ui.timeText(r.t(end))));
            if hasExact
                plot(ax, r.x, r.exact(end, :), "--", Color=t.series(2), LineWidth=1.6, DisplayName="Exact");
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
            if ~r.stable
                title(ax, sprintf("Unstable: r = %.3g > ½ (stopped at t = %s)", r.r, dlab.ui.timeText(r.blowupTime)));
            else
                title(ax, sprintf("Temperature along the rod  (r = α Δt / Δx² = %.3g)", r.r));
            end

            ax = obj.Ax.spacetime;
            dlab.ui.clearAxes(ax);
            imagesc(ax, r.x, r.t, r.T);
            colormap(ax, t.sequentialMap());
            clim(ax, [low high]);
            c = colorbar(ax, Color=t.AxesForeground);
            c.Label.String = "T (°C)";
            set(ax, YDir="normal", XLim=[r.x(1) r.x(end)], YLim=[r.t(1) max(r.t(end), r.t(1) + eps)]);
            hold(ax, "off");

            ax = obj.Ax.probes;
            dlab.ui.clearAxes(ax);
            for k = 1:numel(obj.Probes)
                plot(ax, r.t, probe(r, obj.Probes(k)), Color=t.series(k), LineWidth=1.6, ...
                    DisplayName=sprintf("x = %.3g m", obj.Probes(k) * r.x(end)));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, (r.energy - r.energy(1)) / 1000, Color=t.series(1), LineWidth=1.8, ...
                DisplayName="Change in stored heat");
            plot(ax, r.t, r.heatIn / 1000, "--", Color=t.series(2), LineWidth=1.6, ...
                DisplayName="Heat in (ends and source)");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            obj.setupAnimation(r, low, high, hasExact);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.profile, r.x, r.T(end, :), run);
                dlab.ui.overlayLine(obj.Ax.probes, r.t, probe(r, 0.5), run);
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
            rate = max(r.t(end) / obj.PlaySeconds, 1e-3);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "profile")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            T = r.T(k, :) + fraction * (r.T(next, :) - r.T(k, :));
            set(a.profile, YData=T);
            set(a.strip, CData=[T; T]);
            if ~isempty(a.exact)
                E = r.exact(k, :) + fraction * (r.exact(next, :) - r.exact(k, :));
                set(a.exact, YData=E);
            end
            a.readout.String = sprintf("t = %s   T(L/2) = %.2f °C", dlab.ui.timeText(simTime), interp1(r.x, T, r.x(end) / 2));
        end

        function T = exportTable(~, r)
            % One row per (time, position): long format suits any length.
            [X, Tm] = meshgrid(r.x, r.t);
            T = table(Tm(:), X(:), reshape(r.T, [], 1), VariableNames=["time" "x" "temperature"]);
            T.Properties.VariableUnits = ["s" "m" "°C"];
        end

        function T = summaryTable(~, r)
            names = strings(0, 1);
            values = zeros(0, 1);
            units = strings(0, 1);
            add("Mesh Fourier number r", r.r, "");
            add("Stable", double(r.stable), "");
            if string(r.params.scheme) == "explicit"
                add("Stability limit for r", 0.5, "");
            end
            add("Thermal diffusivity", r.alpha, "m²/s");
            add("Final maximum temperature", max(r.T(end, :)), "°C");
            add("Final minimum temperature", min(r.T(end, :)), "°C");
            if r.stable
                settle = settlingTime(r);
                if isfinite(settle)
                    add("Time to steady state (95 %)", settle, "s");
                end
                % Relative to the energy that moves: heat in through the ends
                % and the source, the change in storage, or (insulated ends,
                % where both are ≈ 0) the initial unevenness the rod spreads out.
                T0 = r.T(1, :);
                L = r.x(end) - r.x(1);
                uneven = r.heatCapacity * trapz(r.x, abs(T0 - trapz(r.x, T0) / L));
                scale = max([abs(r.heatIn(end)), max(abs(r.energy - r.energy(1))), uneven]);
                if scale > 1e-12 * max(abs(r.energy))       % else nothing moved: no ratio to give
                    add("Energy balance error", 100 * abs(r.energy(end) - r.energy(1) - r.heatIn(end)) / scale, "%");
                end
                if ~isempty(r.exact)
                    add("Max error vs exact", max(abs(r.T(:) - r.exact(:))), "°C");
                end
                % The swings belong to an end whose temperature cycles (the brick
                % wall), over the last third of the run.
                varying = [varies(r.params, "left") varies(r.params, "right")];
                if any(varying)
                    late = r.t >= r.t(end) * 2 / 3;
                    surface = r.T(late, 1);
                    if ~varying(1)
                        surface = r.T(late, end);
                    end
                    middle = probe(r, 0.5);
                    middle = middle(late);
                    if max(surface) - min(surface) > 1e-9
                        add("Surface temperature swing", max(surface) - min(surface), "°C");
                        add("Swing ratio (middle / surface)", (max(middle) - min(middle)) / (max(surface) - min(surface)), "");
                    end
                end
            end
            T = table(names, values, units, VariableNames=["Quantity" "Value" "Units"]);

            function add(name, value, unit)
                names(end+1, 1) = name;
                values(end+1, 1) = value;
                units(end+1, 1) = unit;
            end
        end

        function [note, level] = resultNote(~, r)
            if r.stable
                [note, level] = deal("", "success");
            else
                [note, level] = deal(sprintf("unstable: r = %.3g > 0.5", r.r), "warning");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Hot spot spreading (insulated ends)", "Tab", "Space-time", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "1-D heat conduction:  ρ c ∂T/∂t = k ∂²T/∂x² + q,  on a grid of N nodes (method of lines)."
                ""
                "Time stepping by the θ-method: explicit (forward Euler, θ = 0), implicit (backward " + ...
                "Euler, θ = 1), or Crank–Nicolson (θ = ½). The explicit scheme is stable only when the " + ...
                "mesh Fourier number r = α Δt / Δx² is at most ½ (α = k / ρc); beyond it the shortest " + ...
                "wavelengths grow every step and the run stops."
                ""
                "Each end has a fixed temperature (which can change during the run, e.g. a daily " + ...
                "cycle), a heat flux into the rod (0 = insulated), or convection to a fluid " + ...
                "(h, T∞). Flux and convection ends use a mirrored ghost node."
                ""
                "With a sine start between fixed, constant end temperatures and no source, the exact " + ...
                "solution is the straight line between the ends plus the sine decaying as " + ...
                "exp(−α (nπ/L)² t), which the profile plot can show."
            ], newline);
        end
    end

    methods (Access = private)
        function setupAnimation(obj, r, low, high, hasExact)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            span = high - low;
            base = low - 0.25 * span;
            top = low - 0.08 * span;
            n = numel(r.x);
            a = obj.Anim;
            % The rod as a strip colored by temperature, under the profile.
            a.strip = surface(ax, [r.x r.x]', [base; top] * ones(1, n), zeros(2, n), [r.T(1, :); r.T(1, :)], ...
                EdgeColor="none", FaceColor="interp", HandleVisibility="off");
            a.exact = gobjects(0);
            if hasExact
                a.exact = plot(ax, r.x, r.exact(1, :), "--", Color=t.series(2), LineWidth=1.4, DisplayName="Exact");
            end
            a.profile = plot(ax, r.x, r.T(1, :), Color=t.series(1), LineWidth=2.5, DisplayName="Temperature");
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            colormap(ax, t.sequentialMap());
            clim(ax, [low high]);
            set(ax, XLim=[r.x(1) r.x(end)], YLim=[base, high + 0.1 * span]);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function specs = endSpecs(P, side, label)
% The inputs of one end: its type and the values that type uses.
typeName = side + "Type";
isType = @(kind) @(p) p.(typeName) == kind;
fixedDefault = 20;
specs = [
    P(typeName, Label=label, Type="choice", Default="dirichlet", Choices=["dirichlet" "neumann" "robin"], ...
        ChoiceLabels=["Fixed T" "Heat flux" "Convection"], Group="Ends", ...
        Description="A fixed temperature (Dirichlet), a heat flux into the rod (Neumann; 0 = insulated), " + ...
        "or convection to a fluid (Robin: flux = h (T∞ − T)).")
    P(side + "T", Label=label + " temperature", Type="schedule", Units="°C", Default=fixedDefault, ...
        Min=-273, Max=5000, Group="Ends", VisibleWhen=isType("dirichlet"), ...
        Description="Can change during the run, e.g. a sine for a daily cycle.")
    P(side + "Flux", Label=label + " heat flux in", Units="W/m²", Default=0, Min=-1e8, Max=1e8, Group="Ends", ...
        VisibleWhen=isType("neumann"), Description="Heat flowing into the rod through this end: 0 = insulated, " + ...
        "negative = flowing out.")
    P(side + "H", Label=label + " h", Units="W/(m²·K)", Default=10, Min=1e-3, Max=1e6, Group="Ends", ...
        VisibleWhen=isType("robin"), Description="Heat-transfer coefficient: still air ≈ 10, water ≈ 500.")
    P(side + "Tinf", Label=label + " fluid temperature", Units="°C", Default=20, Min=-273, Max=5000, Group="Ends", ...
        VisibleWhen=isType("robin"), Description="The temperature T∞ of the air or water around this end.")
];
end

function bc = endFor(p, side)
% The engine's boundary struct for one end.
temperature = dlab.core.Schedule.toFunction(p.(side + "T"), [-273 5000]);
schedule = dlab.core.Schedule.normalize(p.(side + "T"));
if schedule.shape == "constant"
    temperature = schedule.value;          % constant: the exact solution applies
end
bc = struct("type", char(p.(side + "Type")), "T", temperature, "flux", p.(side + "Flux"), ...
    "h", p.(side + "H"), "Tinf", p.(side + "Tinf"));
end

function tf = varies(p, side)
% True when SIDE is a fixed-temperature end following a changing schedule.
tf = p.(side + "Type") == "dirichlet" && dlab.core.Schedule.normalize(p.(side + "T")).shape ~= "constant";
end

function values = probe(r, fraction)
% Temperature history at FRACTION of the length.
values = interp1(r.x, r.T', fraction * r.x(end))';
values = values(:);
end

function t = settlingTime(r)
% First time every node is within 5 % of the way from the start to the end.
change = max(abs(r.T(1, :) - r.T(end, :)));
t = NaN;
if change < 1e-9 || r.t(end) <= 0
    return
end
k = find(max(abs(r.T - r.T(end, :)), [], 2) <= 0.05 * change, 1);
if ~isempty(k) && k < numel(r.t)
    t = r.t(k);
end
end
