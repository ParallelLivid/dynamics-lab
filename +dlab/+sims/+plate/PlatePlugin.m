classdef PlatePlugin < dlab.core.TimeDomainPlugin
    %PLATEPLUGIN 2-D heat conduction in a rectangular plate: the explicit
    %   (FTCS) and ADI (Peaceman–Rachford) schemes, the 2-D stability limit,
    %   fixed-temperature, heat-flux, and convection edges, heat sources,
    %   and the energy balance. Engine: simulatePlate.

    properties (Constant)
        Id = "plate"
        Title = "Heat in a Plate"
        Category = "Continuum"
        Summary = "2-D conduction in a plate: hot spots, edges, heaters, and why explicit steps must be ¼ as big."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        Materials = struct( ...
            "copper",    struct("k", 401,  "rho", 8960, "c", 385), ...
            "aluminium", struct("k", 237,  "rho", 2700, "c", 897), ...
            "steel",     struct("k", 50,   "rho", 7850, "c", 490), ...
            "glass",     struct("k", 1.0,  "rho", 2500, "c", 840))
        Edges = ["left" "right" "bottom" "top"]
        EdgeLabels = ["Left edge (x = 0)" "Right edge (x = a)" "Bottom edge (y = 0)" "Top edge (y = b)"]
        EdgeShort = ["Left" "Right" "Bottom" "Top"]
        Views = ["Heatmap" "Surface"]
        Snapshots = 6
        Contours = 8
        PlaySeconds = 15
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
        ViewMode (1,1) string = "Heatmap"
        ViewDropdown
    end

    methods
        function specs = parameters(obj)
            P = @dlab.core.ParamSpec;
            custom = @(p) p.material == "custom";
            spot = @(p) p.initial == "hotspot";
            edgeSpecs = cell(numel(obj.Edges), 1);
            for k = 1:numel(obj.Edges)
                edgeSpecs{k} = edgeSpecsFor(P, obj.Edges(k), obj.EdgeLabels(k), obj.EdgeShort(k));
            end
            specs = [
                P("material", Label="Material", Type="choice", Default="steel", ...
                    Choices=["copper" "aluminium" "steel" "glass" "custom"], ...
                    ChoiceLabels=["Copper" "Aluminium" "Steel" "Glass" "Custom"], Group="Plate", ...
                    Description="Sets the conductivity k, density ρ, and specific heat c (diffusivity α = k/ρc).")
                P("k", Label="Conductivity k", Units="W/(m·K)", Default=50, Min=0.01, Max=2000, Group="Plate", ...
                    VisibleWhen=custom, Description="How readily the material conducts heat.")
                P("rho", Label="Density ρ", Units="kg/m³", Default=7850, Min=1, Max=30000, Group="Plate", ...
                    VisibleWhen=custom, Description="Mass per volume; with c, the heat stored per degree.")
                P("c", Label="Specific heat c", Units="J/(kg·K)", Default=490, Min=10, Max=20000, Group="Plate", ...
                    VisibleWhen=custom, Description="Heat to warm one kilogram by one degree.")
                P("a", Label="Width a", Units="m", Default=0.2, Min=0.001, Max=100, Group="Plate", ...
                    Description="The plate's side along x.")
                P("b", Label="Height b", Units="m", Default=0.2, Min=0.001, Max=100, Group="Plate", ...
                    Description="The plate's side along y.")
                P("d", Label="Thickness", Units="m", Default=0.005, Min=1e-5, Max=10, Group="Plate", ...
                    DisplayFormat="%.4g", Description="Only scales energies and powers: the faces are insulated, " + ...
                    "so heat flows in the plane of the plate.")
                vertcat(edgeSpecs{:})
                P("initial", Label="Initial temperature", Type="choice", Default="hotspot", ...
                    Choices=["uniform" "hotspot" "mode" "hotedge"], ...
                    ChoiceLabels=["Uniform" "Hot spot" "Mode" "Hot edge"], Group="Initial temperature", ...
                    Description="Uniform; a Gaussian hot spot; a separable mode sin(mπx/a) sin(nπy/b) on top of " + ...
                    "the base temperature (with all four edges fixed at the base temperature and no source the " + ...
                    "exact solution is known); or one edge hot, falling off exponentially into the plate.")
                P("T0", Label="Base temperature", Units="°C", Default=20, Min=-273, Max=5000, ...
                    Group="Initial temperature", Description="The starting temperature, before the spot, mode, or hot edge.")
                P("amplitude", Label="Amplitude", Units="°C", Default=80, Min=-5000, Max=5000, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial ~= "uniform", ...
                    Description="How much hotter the spot's centre, the mode's peak, or the hot edge is.")
                P("spotX", Label="Spot x", Units="× a", Default=0.4, Min=0, Max=1, Group="Initial temperature", ...
                    VisibleWhen=spot, Description="The spot's centre across the width.")
                P("spotY", Label="Spot y", Units="× b", Default=0.55, Min=0, Max=1, Group="Initial temperature", ...
                    VisibleWhen=spot, Description="The spot's centre up the height.")
                P("width", Label="Width", Units="× size", Default=0.15, Min=0.005, Max=1, Group="Initial temperature", ...
                    VisibleWhen=@(p) ismember(p.initial, ["hotspot" "hotedge"]), ...
                    Description="Of the Gaussian spot, or the depth of the hot edge, as a fraction of the longer side.")
                P("modeM", Label="Mode m (along x)", Type="integer", Default=1, Min=1, Max=50, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial == "mode", ...
                    Description="Half-waves across the width.")
                P("modeN", Label="Mode n (along y)", Type="integer", Default=1, Min=1, Max=50, ...
                    Group="Initial temperature", VisibleWhen=@(p) p.initial == "mode", ...
                    Description="Half-waves up the height.")
                P("hotEdge", Label="Hot edge", Type="choice", Default="left", Choices=obj.Edges, ...
                    ChoiceLabels=["Left" "Right" "Bottom" "Top"], Group="Initial temperature", ...
                    VisibleWhen=@(p) p.initial == "hotedge", Description="Which edge starts hot.")
                P("source", Label="Heat source", Type="choice", Default="none", Choices=["none" "uniform" "spot"], ...
                    ChoiceLabels=["None" "Uniform" "Heater"], Group="Heat source", ...
                    Description="Heat generated inside the plate: everywhere, or in a Gaussian spot (an electric heater).")
                P("q", Label="Source strength", Units="W/m³", Default=1e7, Min=-1e10, Max=1e10, Group="Heat source", ...
                    VisibleWhen=@(p) p.source ~= "none", DisplayFormat="%.4g", ...
                    Description="Uniform value, or the peak of the spot.")
                P("sourceX", Label="Heater x", Units="× a", Default=0.5, Min=0, Max=1, Group="Heat source", ...
                    VisibleWhen=@(p) p.source == "spot", Description="The heater's centre across the width.")
                P("sourceY", Label="Heater y", Units="× b", Default=0.5, Min=0, Max=1, Group="Heat source", ...
                    VisibleWhen=@(p) p.source == "spot", Description="The heater's centre up the height.")
                P("sourceWidth", Label="Heater width", Units="× size", Default=0.1, Min=0.005, Max=1, ...
                    Group="Heat source", VisibleWhen=@(p) p.source == "spot", ...
                    Description="The Gaussian heater's half-width, as a fraction of the longer side.")
                P("scheme", Label="Scheme", Type="choice", Default="adi", Choices=["explicit" "adi"], ...
                    ChoiceLabels=["Explicit" "ADI"], Group="Numerics", ...
                    Description="Explicit (FTCS) is stable only for r_x + r_y ≤ ½ (r ≤ ¼ on a square grid); ADI " + ...
                    "(Peaceman–Rachford) is stable for any step and solves one tridiagonal system per grid line.")
                P("nx", Label="Nodes along x", Type="integer", Default=41, Min=5, Max=121, Group="Numerics", ...
                    Description="Edges included: Δx = a / (nx − 1).")
                P("ny", Label="Nodes along y", Type="integer", Default=41, Min=5, Max=121, Group="Numerics", ...
                    Description="Edges included: Δy = b / (ny − 1).")
                P("stepBy", Label="Set the step by", Type="choice", Default="r", Choices=["r" "dt"], ...
                    ChoiceLabels=["r" "Time step"], Group="Numerics", ...
                    Description="Give the step as the mesh Fourier number r = α Δt / Δx² (which decides " + ...
                    "stability), or as a time in seconds.")
                P("r", Label="r = α Δt / Δx²", Default=0.5, Min=1e-4, Max=1000, Group="Numerics", ...
                    VisibleWhen=@(p) p.stepBy == "r", DisplayFormat="%.4g", ...
                    Description="The mesh Fourier number along x. The step is then Δt = r Δx² / α " + ...
                    "(shortened slightly to land on the duration).")
                P("dt", Label="Time step", Units="s", Default=0.1, Min=1e-6, Max=1e6, Group="Numerics", ...
                    VisibleWhen=@(p) p.stepBy == "dt", DisplayFormat="%.6g", ...
                    Description="Shortened slightly, if needed, to land exactly on the duration.")
                P("tspan", Label="Duration", Units="s", Default=60, Min=1e-3, Max=1e8, Group="Simulation", ...
                    MarksCustom=false, Description="How long to follow the plate.")
                P("dtOut", Label="Output step", Units="s", Default=1, Min=1e-6, Max=1e7, Group="Simulation", ...
                    Description="Spacing of the saved fields (whole time steps; at most about 400 are kept).")
                P("probeX", Label="Probe x", Units="× a", Default=0.7, Min=0, Max=1, Group="Simulation", ...
                    Description="Where the Probes tab records the temperature, across the width.")
                P("probeY", Label="Probe y", Units="× b", Default=0.5, Min=0, Max=1, Group="Simulation", ...
                    Description="Where the Probes tab records the temperature, up the height.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Hot spot spreading", "Values", struct());
            list(end+1) = struct("Name", "Separable mode decay", "Values", struct( ...
                "initial", "mode", "amplitude", 50, "scheme", "explicit", "r", 0.2, "tspan", 300, "dtOut", 2));
            list(end+1) = struct("Name", "Cooling fin edge (convection)", "Values", struct( ...
                "material", "aluminium", "k", 237, "rho", 2700, "c", 897, "a", 0.2, "b", 0.04, "nx", 81, "ny", 17, ...
                "leftType", "fixed", "leftT", 100, "rightType", "convection", "rightH", 200, ...
                "bottomType", "convection", "bottomH", 200, "topType", "convection", "topH", 200, ...
                "initial", "uniform", "r", 10, "tspan", 900, "dtOut", 3, "probeX", 1, "probeY", 0.5));
            list(end+1) = struct("Name", "Insulated plate with heater", "Values", struct( ...
                "material", "aluminium", "k", 237, "rho", 2700, "c", 897, ...
                "leftType", "flux", "rightType", "flux", "bottomType", "flux", "topType", "flux", ...
                "initial", "uniform", "source", "spot", "q", 1e7, "sourceX", 0.3, "sourceY", 0.4, ...
                "r", 2, "tspan", 300, "dtOut", 2));
            list(end+1) = struct("Name", "Explicit at the limit (r = 1/4)", "Values", struct( ...
                "scheme", "explicit", "r", 0.25, "width", 0.08, "tspan", 120, "dtOut", 2));
            list(end+1) = struct("Name", "Explicit past the limit (r = 0.3)", "Values", struct( ...
                "scheme", "explicit", "r", 0.3, "width", 0.08, "tspan", 120, "dtOut", 2));
            list(end+1) = struct("Name", "ADI with a large step (r = 5)", "Values", struct( ...
                "scheme", "adi", "r", 5, "width", 0.04, "tspan", 125, "dtOut", 2));
        end

        function params = onParamChanged(obj, name, params)
            % Picking a material fills in its properties.
            if name == "material" && params.material ~= "custom"
                m = obj.Materials.(params.material);
                [params.k, params.rho, params.c] = deal(m.k, m.rho, m.c);
            end
        end

        function result = solve(obj, p)
            [k, rho, c] = deal(p.k, p.rho, p.c);
            if p.material ~= "custom"
                m = obj.Materials.(p.material);
                [k, rho, c] = deal(m.k, m.rho, m.c);
            end
            dt = p.dt;
            if p.stepBy == "r"
                dt = min(p.r * (p.a / (p.nx - 1))^2 * rho * c / k, p.tspan);
            end
            q = struct("a", p.a, "b", p.b, "nx", p.nx, "ny", p.ny, "k", k, "rho", rho, "c", c, "d", p.d, ...
                "scheme", char(p.scheme), "dt", dt, "tspan", p.tspan, "dtOut", p.dtOut, ...
                "left", edgeFor(p, "left"), "right", edgeFor(p, "right"), ...
                "bottom", edgeFor(p, "bottom"), "top", edgeFor(p, "top"), ...
                "initial", struct("type", char(p.initial), "T0", p.T0, "amplitude", p.amplitude, ...
                    "position", [p.spotX p.spotY], "width", p.width, "mode", [p.modeM p.modeN], ...
                    "edge", char(p.hotEdge)), ...
                "source", struct("type", char(p.source), "q", p.q, "position", [p.sourceX p.sourceY], ...
                    "width", p.sourceWidth), ...
                "probe", [p.probeX p.probeY], "progressFcn", obj.progressMonitor());
            result = dlab.sims.plate.simulatePlate(q);
            result.params = p;
        end

        function titles = outputTabs(~, ~)
            titles = ["Temperature field" "Probes" "Energy" "Stability"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax.field = dlab.ui.axesIn(containers{"Temperature field"}, t, Title="Temperature field");
            grid = uigridlayout(containers{"Probes"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.line = dlab.ui.axesIn(grid, t, Row=1, Title="Along the centre line y = b/2", ...
                XLabel="x (m)", YLabel="T (°C)");
            obj.Ax.probes = dlab.ui.axesIn(grid, t, Row=2, Title="Temperature over time", ...
                XLabel="Time (s)", YLabel="T (°C)");
            obj.Ax.energy = dlab.ui.axesIn(containers{"Energy"}, t, Title="Energy balance", ...
                XLabel="Time (s)", YLabel="Energy (kJ)");
            grid = uigridlayout(containers{"Stability"}, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.Ax.growth = dlab.ui.axesIn(grid, t, Row=1, Title="Growth factor per step of each grid mode", ...
                XLabel="Decay rate × time step, λ Δt", YLabel="g per step");
            obj.Ax.decay = dlab.ui.axesIn(grid, t, Row=2, Title="Decay", XLabel="Time (s)");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Plate", XLabel="x (m)", YLabel="y (m)", ZLabel="T (°C)");
            obj.Anim = struct("axes", ax);
        end

        function buildPlaybackControls(obj, parent, theme)
            parent.ColumnWidth = {"fit", 100};
            dlab.ui.label(parent, "View", theme, Role="muted");
            obj.ViewDropdown = uidropdown(parent, Items=obj.Views, Value=obj.ViewMode, ...
                BackgroundColor=theme.SurfaceRaised, FontColor=theme.Text, Tag="dlab.plate.view", ...
                ValueChangedFcn=@(src, ~) obj.setViewMode(src.Value));
        end

        function setViewMode(obj, mode)
            %SETVIEWMODE Show the animation as a heatmap from above or a 3-D surface.
            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["Heatmap" "Surface"])}
            end
            obj.ViewMode = mode;
            if ~isempty(obj.ViewDropdown) && isvalid(obj.ViewDropdown)
                obj.ViewDropdown.Value = mode;
            end
            if isfield(obj.Anim, "axes") && isvalid(obj.Anim.axes)
                applyView(obj.Anim.axes, mode);
                if ~isempty(obj.Result)
                    obj.drawFrame(obj.Anim.time);
                end
            end
        end

        function showResult(obj, r, params)
            obj.Result = r;
            obj.drawField(r, params);
            obj.drawProbes(r);
            obj.drawEnergy(r);
            obj.drawStability(r);
            obj.setupAnimation(r, params);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Ax.line, r.x, r.centreLine(end, :), run);
                dlab.ui.overlayLine(obj.Ax.probes, r.t, r.probe, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                delete(allchild(obj.Ax.(name)));
                legend(obj.Ax.(name), "off");
            end
            colorbar(obj.Ax.field, "off");
            if isfield(obj.Anim, "axes")
                delete(allchild(obj.Anim.axes));
                colorbar(obj.Anim.axes, "off");
            end
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function rate = playbackRate(obj, r)
            rate = max(r.t(end) / obj.PlaySeconds, 1e-6);
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "surface")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            next = min(k + 1, numel(r.t));
            fraction = 0;
            if r.t(next) > r.t(k)
                fraction = min(max((simTime - r.t(k)) / (r.t(next) - r.t(k)), 0), 1);
            end
            T = r.T(:, :, k) + fraction * (r.T(:, :, next) - r.T(:, :, k));
            Z = min(max(T, a.zlim(1)), a.zlim(2));
            if obj.ViewMode == "Heatmap"
                Z = zeros(size(T)) + a.zlim(1);
            end
            set(a.surface, ZData=Z, CData=T);
            probe = r.probe(k) + fraction * (r.probe(next) - r.probe(k));
            if obj.ViewMode == "Heatmap"
                set(a.probe, ZData=a.zlim(2));
            else
                set(a.probe, ZData=min(max(probe, a.zlim(1)), a.zlim(2)));
            end
            a.readout.String = sprintf("t = %s   T(probe) = %.2f °C   max %.2f °C", dlab.ui.timeText(simTime), probe, ...
                max(T(:)));
            obj.Anim.time = simTime;
        end

        function T = exportTable(~, r)
            T = table(r.t, r.probe, r.centre, r.meanT, r.maxT, r.minT, r.energy, r.heatIn, r.generated, ...
                VariableNames=["time" "probe_temperature" "centre_temperature" "mean_temperature" ...
                "max_temperature" "min_temperature" "stored_energy" "heat_in_edges" "heat_generated"]);
            T.Properties.VariableUnits = ["s" "°C" "°C" "°C" "°C" "°C" "J" "J" "J"];
        end

        function T = summaryTable(~, r)
            rows = cell(0, 5);                          % Quantity, Value, Units, Format, Display
            p = r.params;
            explicit = p.scheme == "explicit";
            schemeNames = struct("explicit", "Explicit (FTCS)", "adi", "ADI (Peaceman–Rachford)");
            add("Scheme", NaN, "", "", schemeNames.(p.scheme));
            add("Mesh Fourier number r", r.rx, "", "%.4g", "");
            add("r_x + r_y", r.rx + r.ry, "", "%.4g", "");
            if explicit
                add("Stability limit for r_x + r_y", 0.5, "", "%.3g", "");
            end
            add("Time step", r.dt, "s", "%.4g", "");
            add("Largest stable explicit step", r.dtMax, "s", "%.4g", "");
            if r.stable
                verdict = "Yes";
                if explicit && r.dt > r.dtMax * (1 + 1e-9)
                    verdict = "Not for long: past the limit, errors grow every step";
                end
            else
                verdict = sprintf("No: blew up at t = %s", dlab.ui.timeText(r.blowupTime));
            end
            add("Stable", double(r.stable), "", "", verdict);
            add("Final maximum temperature", r.maxT(end), "°C", "%.4g", "");
            add("Final minimum temperature", r.minT(end), "°C", "%.4g", "");
            add("Final mean temperature", r.meanT(end), "°C", "%.4g", "");
            add("Probe temperature", r.probe(end), "°C", "%.4g", "");
            add("Thermal diffusivity", r.alpha, "m²/s", "%.4g", "");
            if r.stable
                change = r.energy - r.energy(1);
                inflow = r.heatIn + r.generated;
                T0 = r.T(:, :, 1);
                uneven = r.heatCapacity * r.thickness * mean(abs(T0(:) - r.meanT(1))) * area(r);
                scale = max([max(abs(inflow)), max(abs(change)), uneven]);
                if scale > 1e-12 * max(abs(r.energy))
                    add("Energy balance error", 100 * abs(change(end) - inflow(end)) / scale, "%", "%.3g", "");
                end
                add("Heat in through the edges", r.heatIn(end), "J", "%.4g", "");
                if any(r.generated)
                    add("Heat generated", r.generated(end), "J", "%.4g", "");
                end
                if isfinite(r.steadyTime)
                    add("Time to steady state (99 %)", r.steadyTime, "s", "%.4g", "");
                end
                if r.hasExact && r.modeAmplitude(end) > 0 && r.t(end) > 0
                    numeric = -log(r.modeAmplitude(end) / r.modeAmplitude(1)) / r.t(end);
                    add("Decay rate", numeric, "1/s", "%.5g", "");
                    add("Exact decay rate", r.decayRate, "1/s", "%.5g", "");
                    add("Decay-rate error", 100 * (numeric - r.decayRate) / r.decayRate, "%", "%.3g", "");
                    add("Max error vs exact", r.maxError, "°C", "%.3g", "");
                end
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);

            function add(name, value, unit, format, display)
                rows(end+1, :) = {name, value, unit, format, display};
            end
        end

        function [note, level] = resultNote(~, r)
            limitText = sprintf("r_x + r_y = %.3g > ½", r.rx + r.ry);
            if ~r.stable
                [note, level] = deal("unstable: " + limitText + " (explicit)", "warning");
            elseif r.params.scheme == "explicit" && r.dt > r.dtMax * (1 + 1e-9)
                [note, level] = deal("past the explicit stability limit (" + limitText + "): errors grow every step", ...
                    "warning");
            else
                [note, level] = deal("", "success");
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Hot spot spreading", "Tab", "Temperature field", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "2-D heat conduction in a plate a × b:  ρ c ∂T/∂t = k (∂²T/∂x² + ∂²T/∂y²) + q,  " + ...
                "on a grid of nx × ny nodes (the 5-point Laplacian). The faces are insulated."
                ""
                "Explicit (FTCS): each node moves by r_x (T_W − 2T + T_E) + r_y (T_S − 2T + T_N), with " + ...
                "r_x = α Δt / Δx², r_y = α Δt / Δy². It is stable only when r_x + r_y ≤ ½: on a square " + ...
                "grid r ≤ ¼, half the 1-D limit, because each node now has four neighbours. Beyond it " + ...
                "the checkerboard mode grows every step and the run stops."
                ""
                "ADI (Peaceman–Rachford): each step is two half steps, implicit along x then along y, so " + ...
                "each needs only a tridiagonal solve per grid line. It is stable for any step and second " + ...
                "order in time, though very large steps leave the shortest wavelengths ringing."
                ""
                "Each edge has a fixed temperature, a heat flux into the plate (0 = insulated), or " + ...
                "convection to a fluid (h, T∞); flux and convection edges use a mirrored ghost node, " + ...
                "and fixed corners take the average of the two edges. The energy balance compares the " + ...
                "change in stored heat with the heat that came in through the edges and from the source."
                ""
                "A separable start sin(mπx/a) sin(nπy/b) inside four edges fixed at the base temperature " + ...
                "keeps its shape and decays as exp(−α π² (m²/a² + n²/b²) t): the exact solution."
            ], newline);
        end
    end

    methods (Access = private)
        function [low, high, map] = colorRange(obj, r, params)
            % The colour scale: diverging about the base temperature for a
            % signed mode, else sequential over the run (over the start for
            % a run that blew up, so its checkerboard saturates).
            t = obj.Theme;
            if r.stable
                values = r.T(:);
            else
                values = reshape(r.T(:, :, 1), [], 1);
            end
            low = min(values);
            high = max(values);
            map = t.sequentialMap();
            if params.initial == "mode" && (params.modeM > 1 || params.modeN > 1)
                spread = max(abs([low high] - params.T0));
                [low, high] = deal(params.T0 - spread, params.T0 + spread);
                map = t.divergingMap();
            end
            if high - low < 1e-9
                [low, high] = deal(low - 1, high + 1);
            end
        end

        function drawField(obj, r, params)
            % Snapshots in tiles, sharing one colour scale, with contours.
            t = obj.Theme;
            ax = obj.Ax.field;
            dlab.ui.clearAxes(ax);
            colorbar(ax, "off");
            [low, high, map] = obj.colorRange(r, params);
            frames = unique(round(linspace(1, numel(r.t), obj.Snapshots)));
            [X, Y] = meshgrid(r.x, r.y);
            a = r.x(end);
            b = r.y(end);
            columns = 3;
            if a / b > 2
                columns = 2;
            end
            gapX = 0.08 * a;
            gapY = 0.1 * b + 0.08 * max(a, b);
            for q = 1:numel(frames)
                k = frames(q);
                ox = mod(q - 1, columns) * (a + gapX);
                oy = -floor((q - 1) / columns) * (b + gapY);
                T = r.T(:, :, k);
                surface(ax, X + ox, Y + oy, zeros(size(T)), min(max(T, low), high), EdgeColor="none", ...
                    FaceColor="interp", HandleVisibility="off");
                if max(T(:)) - min(T(:)) > 1e-6 * max(1, abs(high))
                    levels = linspace(min(T(:)), max(T(:)), obj.Contours + 2);
                    contour(ax, X + ox, Y + oy, T, levels(2:end-1), LineColor=t.Text, LineWidth=0.6);
                end
                plot(ax, [0 a a 0 0] + ox, [0 0 b b 0] + oy, Color=t.TextMuted, LineWidth=1);
                text(ax, ox + a / 2, oy + b + 0.02 * max(a, b), sprintf("t = %s", dlab.ui.timeText(r.t(k))), ...
                    HorizontalAlignment="center", VerticalAlignment="bottom", Color=t.Text, FontSize=t.FontSize.sm);
            end
            last = numel(frames);
            ox = mod(last - 1, columns) * (a + gapX);
            oy = -floor((last - 1) / columns) * (b + gapY);
            plot(ax, [0 a] + ox, [b b] / 2 + oy, "--", Color=t.TextMuted, LineWidth=1);
            plot(ax, r.probeXY(1) + ox, r.probeXY(2) + oy, "o", MarkerSize=7, MarkerFaceColor=t.series(3), ...
                MarkerEdgeColor=t.Text);
            hold(ax, "off");
            colormap(ax, map);
            clim(ax, [low high]);
            c = colorbar(ax, Color=t.AxesForeground);
            c.Title.String = "T (°C)";      % above the bar: a side label was cut off at Larger text
            c.Title.Color = t.AxesForeground;
            rowsShown = ceil(numel(frames) / columns);
            margin = 0.03 * max(a, b);
            axis(ax, "equal");
            set(ax, XLim=[-margin, (min(columns, numel(frames)) - 1) * (a + gapX) + a + margin], ...
                YLim=[-(rowsShown - 1) * (b + gapY) - margin, b + 0.12 * max(a, b)]);
            ax.XAxis.Visible = "off";
            ax.YAxis.Visible = "off";
            ax.XGrid = "off";
            ax.YGrid = "off";
            if r.stable
                title(ax, sprintf("Temperature field  (%d contours within each snapshot; probe ○, centre line dashed)", ...
                    obj.Contours));
            else
                title(ax, sprintf("Unstable: r_x + r_y = %.3g > ½ (stopped at t = %s)", r.rx + r.ry, ...
                    dlab.ui.timeText(r.blowupTime)));
            end
        end

        function drawProbes(obj, r)
            t = obj.Theme;
            ax = obj.Ax.line;
            dlab.ui.clearAxes(ax);
            frames = unique(round(linspace(1, numel(r.t), obj.Snapshots)));
            if ~r.stable
                frames = frames(1:end-1);
            end
            for q = 1:numel(frames)
                k = frames(q);
                plot(ax, r.x, r.centreLine(k, :), Color=[t.series(1) 0.25 + 0.75 * q / numel(frames)], ...
                    LineWidth=1.2 + 0.6 * (q == numel(frames)), DisplayName=sprintf("t = %s", dlab.ui.timeText(r.t(k))));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.probes;
            dlab.ui.clearAxes(ax);
            shown = 1:numel(r.t);
            if ~r.stable
                shown = shown(1:end-1);
            end
            plot(ax, r.t(shown), r.maxT(shown), ":", Color=t.TextMuted, LineWidth=1.2, DisplayName="Max");
            plot(ax, r.t(shown), r.meanT(shown), "--", Color=t.series(2), LineWidth=1.4, DisplayName="Mean");
            plot(ax, r.t(shown), r.centre(shown), Color=t.series(1), LineWidth=1.6, DisplayName="Centre");
            plot(ax, r.t(shown), r.probe(shown), Color=t.series(3), LineWidth=1.8, ...
                DisplayName=sprintf("Probe (%.3g, %.3g) m", r.probeXY(1), r.probeXY(2)));
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function drawEnergy(obj, r)
            t = obj.Theme;
            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            change = (r.energy - r.energy(1)) / 1000;
            plot(ax, r.t, change, Color=t.series(1), LineWidth=2, DisplayName="Change in stored heat");
            plot(ax, r.t, r.heatIn / 1000, Color=t.series(2), LineWidth=1.4, DisplayName="Heat in through the edges");
            if any(r.generated)
                plot(ax, r.t, r.generated / 1000, Color=t.series(4), LineWidth=1.4, DisplayName="Heat from the source");
            end
            plot(ax, r.t, (r.heatIn + r.generated) / 1000, "--", Color=t.Text, LineWidth=1.4, ...
                DisplayName="Edges + source");
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
            gap = abs(change(end) - (r.heatIn(end) + r.generated(end)) / 1000);
            title(ax, sprintf("Energy balance  (stored − (edges + source) = %.3g J at the end)", 1000 * gap));
            if ~r.stable
                title(ax, "Energy balance (the run blew up)");
            end
        end

        function drawStability(obj, r)
            t = obj.Theme;
            p = r.params;
            ax = obj.Ax.growth;
            dlab.ui.clearAxes(ax);
            [MX, MY] = meshgrid(r.eigX, r.eigY);
            mu = MX(:) + MY(:);
            z = -mu * r.dt;                          % λ Δt ≥ 0
            top = max([z; 2.2]);
            span = linspace(0, top, 400);
            plot(ax, span, exp(-span), Color=t.series(2), LineWidth=1.6, DisplayName="Exact e^{−λΔt}");
            if p.scheme == "explicit"
                g = 1 + mu * r.dt;
                plot(ax, span, 1 - span, ":", Color=t.TextMuted, LineWidth=1.2, DisplayName="Explicit: 1 − λΔt");
            else
                hx = r.dt / 2 * MX(:);
                hy = r.dt / 2 * MY(:);
                g = (1 + hx) .* (1 + hy) ./ ((1 - hx) .* (1 - hy));
            end
            growing = abs(g) > 1 + 1e-12;
            plot(ax, z(~growing), g(~growing), ".", MarkerSize=8, Color=t.series(1), DisplayName="Grid modes");
            if any(growing)
                plot(ax, z(growing), g(growing), ".", MarkerSize=10, Color=t.Danger, DisplayName="Growing modes");
            end
            yline(ax, [-1 1], "--", Color=t.Danger, LineWidth=1, HandleVisibility="off");
            xline(ax, 2, ":", "explicit limit", Color=t.TextMuted, LabelVerticalAlignment="middle", ...
                HandleVisibility="off");
            hold(ax, "off");
            xlim(ax, [0 top * 1.02]);
            ylim(ax, [max(min([g; -1.05]), -3) - 0.05, 1.1]);
            dlab.ui.legend(ax, t, "Location", "best");
            title(ax, sprintf("Growth factor per step of each grid mode  (r_x + r_y = %.3g; explicit needs ≤ ½)", ...
                r.rx + r.ry));

            ax = obj.Ax.decay;
            dlab.ui.clearAxes(ax);
            if r.hasExact
                plot(ax, r.t, abs(r.exactAmplitude), Color=t.series(2), LineWidth=1.6, DisplayName="Exact");
                plot(ax, r.t, abs(r.modeAmplitude), "o", MarkerSize=4, Color=t.series(1), DisplayName="Grid");
                ylabel(ax, "Mode amplitude (°C)");
                title(ax, sprintf("Decay of the (%d, %d) mode: exact rate λ = %.4g 1/s", p.modeM, p.modeN, r.decayRate));
            else
                rate = [NaN; max(abs(diff(reshape(r.T, [], numel(r.t)), 1, 2)), [], 1)' ./ diff(r.t)];
                plot(ax, r.t, rate, Color=t.series(1), LineWidth=1.6, DisplayName="Largest |∂T/∂t|");
                ylabel(ax, "Largest |∂T/∂t| (°C/s)");
                title(ax, "How fast the field is still changing");
            end
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");
        end

        function setupAnimation(obj, r, params)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            colorbar(ax, "off");
            [low, high, map] = obj.colorRange(r, params);
            [X, Y] = meshgrid(r.x, r.y);
            a = obj.Anim;
            a.zlim = [low high];
            a.time = r.t(1);
            a.surface = surface(ax, X, Y, r.T(:, :, 1), r.T(:, :, 1), EdgeColor=t.Grid, EdgeAlpha=0.2, ...
                FaceColor="interp");
            plot3(ax, [0 1 1 0 0] * r.x(end), [0 0 1 1 0] * r.y(end), low * ones(1, 5), Color=t.TextMuted, ...
                LineWidth=1.2);
            a.probe = plot3(ax, r.probeXY(1), r.probeXY(2), low, "o", MarkerSize=7, ...
                MarkerFaceColor=t.series(3), MarkerEdgeColor=t.Text);
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            colormap(ax, map);
            clim(ax, [low high]);
            c = colorbar(ax, Color=t.AxesForeground);
            c.Label.String = "T (°C)";
            span = max(r.x(end), r.y(end));
            set(ax, XLim=[0 r.x(end)], YLim=[0 r.y(end)], ZLim=[low high + 1e-9], ...
                DataAspectRatio=[1 1 (high - low) / (0.5 * span)]);
            applyView(ax, obj.ViewMode);
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function specs = edgeSpecsFor(P, side, label, short)
% The inputs of one edge: its type and the values that type uses.
typeName = side + "Type";
isType = @(kind) @(p) p.(typeName) == kind;
specs = [
    P(typeName, Label=label, Type="choice", Default="fixed", Choices=["fixed" "flux" "convection"], ...
        ChoiceLabels=["Fixed T" "Heat flux" "Convection"], Group="Edges", ...
        Description="A fixed temperature (Dirichlet), a heat flux into the plate (Neumann; 0 = insulated), " + ...
        "or convection to a fluid (Robin: flux = h (T∞ − T)).")
    P(side + "T", Label=short + " temperature", Units="°C", Default=20, Min=-273, Max=5000, Group="Edges", ...
        VisibleWhen=isType("fixed"), Description="The temperature this edge is held at.")
    P(side + "Flux", Label=short + " heat flux in", Units="W/m²", Default=0, Min=-1e8, Max=1e8, Group="Edges", ...
        VisibleWhen=isType("flux"), Description="Heat flowing into the plate through this edge: 0 = insulated, " + ...
        "negative = flowing out.")
    P(side + "H", Label=short + " h", Units="W/(m²·K)", Default=10, Min=1e-3, Max=1e6, Group="Edges", ...
        VisibleWhen=isType("convection"), Description="Heat-transfer coefficient: still air ≈ 10, moving air ≈ 50, water ≈ 500.")
    P(side + "Tinf", Label=short + " fluid temperature", Units="°C", Default=20, Min=-273, Max=5000, Group="Edges", ...
        VisibleWhen=isType("convection"), Description="The temperature T∞ of the air or water at this edge.")
];
end

function edge = edgeFor(p, side)
edge = struct("type", char(p.(side + "Type")), "T", p.(side + "T"), "flux", p.(side + "Flux"), ...
    "h", p.(side + "H"), "Tinf", p.(side + "Tinf"));
end

function value = area(r)
value = r.x(end) * r.y(end);
end

function applyView(ax, mode)
if mode == "Heatmap"
    view(ax, 2);
else
    view(ax, -35, 35);
end
end
