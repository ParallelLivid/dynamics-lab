classdef ProjectilePlugin < dlab.core.TimeDomainPlugin
    %PROJECTILEPLUGIN Point mass or sphere with quadratic drag, launched
    %   from a height until first ground impact. The drag model can add a
    %   steady wind and air that thins with altitude, and every run can
    %   also find the launch angle with the longest range.
    %
    %   Runs are compared with the shell's "Keep previous runs" option:
    %   overlayRuns draws the kept trajectories behind the current one.

    properties (Constant)
        Id = "projectile"
        Title = "Projectile Motion"
        Category = "Mechanics"
        Summary = "Ballistic trajectories with drag, wind, and spin (curveballs); the optimal launch angle."
        SchemaVersion = 2       % 2: comparison moved to the shell ("compare" input removed)
    end

    properties (Constant, Access = private)
        TailSeconds = 0.75
    end

    properties (Access = private)
        Axes struct = struct()
        Anim struct = struct()
        Latest                  % engine result being shown
        EqualAxes (1,1) logical = true
        OptimalButton           % "Use optimal angle"
        OptimalCache struct = struct("key", [], "best", [])   % last search, by inputs other than theta
        TopView = []            % "Top view" axes (with sidespin), else []
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isDrag = @(p) p.model == "sphere";
            specs = [
                P("model", Label="Model", Type="choice", Default="point", ...
                    Choices=["point" "sphere"], ChoiceLabels=["Point mass" "With drag"], ...
                    Group="Model", Description="Point mass: no air resistance (ideal parabola). " + ...
                    "With drag: a sphere (or a body of given frontal area) with the drag force " + ...
                    "F = ½·Cd·ρ·A·v² opposing its velocity through the air; wind and spin become available.")
                P("v0", Label="Launch speed", Units="m/s", Default=50, Min=0, Max=5000, Group="Launch", ...
                    Description="Speed at launch.")
                P("theta", Label="Launch angle", Units="deg", Default=45, Min=0, Max=90, Group="Launch", ...
                    Description="Measured above the horizontal.")
                P("h0", Label="Launch height", Units="m", Default=0, Min=0, Max=100000, Group="Launch", ...
                    Description="Height above the ground (y = 0).")
                P("g", Label="Gravity", Units="m/s²", Default=9.81, Min=0.01, Max=100, Group="Environment", ...
                    Description="Earth ≈ 9.81, Moon ≈ 1.62, Mars ≈ 3.72 m/s².")
                P("geometry", Label="Size given by", Type="choice", Default="radius", ...
                    Choices=["radius" "area"], ChoiceLabels=["Radius" "Frontal area"], ...
                    Group="Drag", VisibleWhen=isDrag, ...
                    Description="Give the projectile's radius (a sphere: frontal area π r²), or its frontal area directly.")
                P("radius", Label="Radius", Units="m", Default=0.05, Min=1e-4, Max=100, Group="Drag", ...
                    VisibleWhen=@(p) isDrag(p) && p.geometry == "radius", Description="A = π r².")
                P("area", Label="Frontal area", Units="m²", Default=0.01, Min=1e-8, Max=10000, Group="Drag", ...
                    VisibleWhen=@(p) isDrag(p) && p.geometry == "area", ...
                    Description="Area the projectile presents to the air (for a sphere, π r²).")
                P("Cd", Label="Drag coefficient", Default=0.47, Min=0, Max=10, Group="Drag", ...
                    VisibleWhen=isDrag, Description="Smooth sphere ≈ 0.47; streamlined body ≈ 0.04.")
                P("m", Label="Mass", Units="kg", Default=1, Min=1e-4, Max=1e6, Group="Drag", ...
                    VisibleWhen=isDrag, ...
                    Description="Mass of the projectile: a heavier one is slowed less by the same drag.")
                P("density", Label="Air density model", Type="choice", Default="constant", ...
                    Choices=["constant" "isa"], ChoiceLabels=["Constant" "Standard (ISA)"], ...
                    Group="Air", VisibleWhen=isDrag, Description="Standard (ISA): the 1976 standard atmosphere, whose density falls " + ...
                    "with height above sea level (launch site altitude plus the projectile's height).")
                P("rho", Label="Air density", Units="kg/m³", Default=1.225, Min=0, Max=2000, Group="Air", ...
                    VisibleWhen=@(p) isDrag(p) && p.density == "constant", ...
                    Description="Sea-level air ≈ 1.225; 0 disables drag. Buoyancy is not modelled, so " + ...
                    "a fluid nearly as dense as the projectile (water) would need it.")
                P("siteAltitude", Label="Launch site altitude", Units="m", Default=0, Min=-400, Max=8000, ...
                    Group="Air", VisibleWhen=@(p) isDrag(p) && p.density == "isa", ...
                    Description="Height of the ground above sea level, e.g. Denver ≈ 1609 m.")
                P("windX", Label="Wind", Units="m/s", Default=0, Min=-50, Max=50, Group="Air", ...
                    VisibleWhen=isDrag, Description="Horizontal wind: positive blows downrange (a tailwind), " + ...
                    "negative is a headwind. Drag acts on the velocity relative to the air.")
                P("windProfile", Label="Wind profile", Type="choice", Default="uniform", ...
                    Choices=["uniform" "powerlaw"], ChoiceLabels=["Uniform" "Boundary layer"], ...
                    Group="Air", VisibleWhen=@(p) isDrag(p) && p.windX ~= 0, ...
                    Description="Uniform: the same wind at every height. Boundary layer: stronger with " + ...
                    "height, wind × (height / 10 m)^(1/7), as near the ground (the full wind at 10 m).")
                P("backspin", Label="Backspin", Units="rpm", Default=0, Min=-30000, Max=30000, Group="Spin", ...
                    VisibleWhen=isDrag, Description="Spin about the horizontal axis across the flight: backspin " + ...
                    "lifts the ball (the Magnus force), topspin (negative) makes it dip. A golf drive has " + ...
                    "about 2500–3000 rpm.")
                P("sidespin", Label="Sidespin", Units="rpm", Default=0, Min=-30000, Max=30000, Group="Spin", ...
                    VisibleWhen=isDrag, Description="Spin about the vertical axis: positive curves the ball to " + ...
                    "the right (looking downrange), negative to the left. A curveball has about 1500–2500 rpm.")
                P("dt", Label="Time step", Units="s", Default=0.01, Min=0.0005, Max=0.5, Group="Simulation", ...
                    Description="Maximum solver step (drag) or sample interval (point mass).")
                P("findOptimal", Label="Find the optimal angle", Type="logical", Default=true, Group="Analysis", ...
                    Description="Also search for the launch angle with the longest range (exact for a " + ...
                    "point mass; about 30 extra solves with drag). The search is reused while only the launch " + ...
                    "angle changes, so a sweep over the angle searches once.")
                P("equalAxes", Label="Equal axis scales", Type="logical", Default=true, Group="Display", ...
                    Display=true, ...
                    Description="Draw the trajectory with the same scale on both axes, so its shape is true.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Drag example (60°)", "Values", struct("model", "sphere", "theta", 60));
            list(end+1) = struct("Name", "Cliff launch", "Values", struct("h0", 100, "theta", 15));
            list(end+1) = struct("Name", "Moon", "Values", struct("g", 1.62));
            list(end+1) = struct("Name", "Baseball", "Values", struct("model", "sphere", "v0", 45, ...
                "theta", 35, "radius", 0.0366, "Cd", 0.35, "m", 0.145, "h0", 1));
            list(end+1) = struct("Name", "Baseball in Denver (1609 m)", "Values", struct("model", "sphere", ...
                "v0", 45, "theta", 35, "radius", 0.0366, "Cd", 0.35, "m", 0.145, "h0", 1, ...
                "density", "isa", "siteAltitude", 1609));
            list(end+1) = struct("Name", "Golf drive into a headwind", "Values", struct("model", "sphere", ...
                "v0", 70, "theta", 12, "radius", 0.02135, "Cd", 0.25, "m", 0.0459, "windX", -8));
            list(end+1) = struct("Name", "Shot put", "Values", struct("v0", 13.7, "theta", 37, "h0", 2.1));
            list(end+1) = struct("Name", "Golf drive with backspin", "Values", struct("model", "sphere", ...
                "v0", 70, "theta", 11, "radius", 0.02135, "Cd", 0.25, "m", 0.0459, "backspin", 2800));
            list(end+1) = struct("Name", "Curveball (sidespin)", "Values", struct("model", "sphere", ...
                "v0", 35, "theta", 1, "h0", 1.8, "radius", 0.0366, "Cd", 0.35, "m", 0.145, ...
                "sidespin", -2000, "findOptimal", false));
            list(end+1) = struct("Name", "Topspin tennis drive", "Values", struct("model", "sphere", ...
                "v0", 30, "theta", 8, "h0", 1, "radius", 0.0335, "Cd", 0.55, "m", 0.057, "backspin", -2500, ...
                "findOptimal", false));
        end

        function params = migrate(~, params, fromVersion)
            % Version 1 had a "Compare runs" input; the shell's "Keep
            % previous runs" replaces it.
            if fromVersion < 2 && isfield(params, "compare")
                params = rmfield(params, "compare");
            end
        end

        function result = solve(obj, p)
            engineParams = rmfield(p, ["equalAxes" "findOptimal"]);
            for name = ["model" "geometry" "density" "windProfile"]
                engineParams.(name) = char(p.(name));
            end
            engineParams.progressFcn = obj.progressMonitor();
            result = dlab.sims.projectile.projectile_physics(engineParams);
            result.params = rmfield(result.params, "progressFcn");   % results hold data only

            result.optimal = [];
            if p.findOptimal
                best = obj.optimalFor(result.params);
                result.optimal = struct("angle", best.angle, "range", best.range, ...
                    "X", best.result.X, "Y", best.result.Y);
            end
            result.stillAirRange = NaN;
            if p.model == "sphere" && p.windX ~= 0
                still = result.params;
                still.windX = 0;
                calm = dlab.sims.projectile.projectile_physics(still);
                result.stillAirRange = calm.range;
            end
        end

        function titles = outputTabs(~, p)
            titles = ["Position" "Velocity"];
            if p.model == "sphere" && p.sidespin ~= 0
                titles(end+1) = "Top view";          % the ball curves sideways
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            obj.Axes.position = dlab.ui.axesIn(containers{"Position"}, theme, ...
                Title="Position vs time", XLabel="Time (s)", YLabel="Position (m)");
            obj.Axes.velocity = dlab.ui.axesIn(containers{"Velocity"}, theme, ...
                Title="Velocity vs time", XLabel="Time (s)", YLabel="Velocity (m/s)");
            obj.TopView = [];
            if isKey(containers, "Top view")
                obj.TopView = dlab.ui.axesIn(containers{"Top view"}, theme, ...
                    Title="From above: the curve", XLabel="Downrange x (m)", YLabel="To the right z (m)");
            end
        end

        function buildExtraControls(obj, parent, theme)
            obj.OptimalButton = dlab.ui.button(parent, "Use optimal angle", theme, ...
                Tag="dlab.projectile.useOptimal", ...
                Tooltip="Set the launch angle to the best one the last run found", ...
                Callback=@(~, ~) obj.useOptimalAngle());
            obj.OptimalButton.Enable = "off";
        end

        function useOptimalAngle(obj)
            %USEOPTIMALANGLE Set the launch angle to the last run's optimum.
            if isempty(obj.Latest) || ~isfield(obj.Latest, "optimal") || isempty(obj.Latest.optimal)
                return
            end
            obj.requestInputs(struct("theta", round(obj.Latest.optimal.angle, 2)), "Use optimal angle");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Trajectory", XLabel="x (m)", YLabel="y (m)");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax, "tail", gobjects(0), "point", gobjects(0), "readout", gobjects(0), "wind", "");
        end

        function showResult(obj, r, params)
            obj.Latest = r;
            obj.EqualAxes = params.equalAxes;
            t = obj.Theme;
            a = obj.Anim;
            for ax = [a.axes obj.Axes.position obj.Axes.velocity]
                delete(allchild(ax));    % cla would keep HandleVisibility="off" objects
                legend(ax, "off");
                hold(ax, "on");
            end
            plot(a.axes, r.X, r.Y, "--", Color=t.series(1), LineWidth=1.4, DisplayName="Trajectory");
            shown = {r};
            if isfield(r, "optimal") && ~isempty(r.optimal)
                plot(a.axes, r.optimal.X, r.optimal.Y, ":", Color=t.series(3), LineWidth=1.6, ...
                    DisplayName=sprintf("Best angle %.1f°", r.optimal.angle));
                shown{end+1} = r.optimal;
            end
            obj.Anim.wind = "";          % shown in the readout (a corner label hid behind the legend)
            if isfield(params, "windX") && params.model == "sphere" && params.windX ~= 0
                arrow = "→ tailwind";
                if params.windX < 0
                    arrow = "← headwind";
                end
                obj.Anim.wind = sprintf("wind %.1f m/s %s", abs(params.windX), arrow);
            end
            plot(obj.Axes.position, r.T, r.X, Color=t.series(1), LineWidth=1.4, DisplayName="x");
            plot(obj.Axes.position, r.T, r.Y, Color=t.series(2), LineWidth=1.4, DisplayName="y");
            plot(obj.Axes.velocity, r.T, r.VX, Color=t.series(1), LineWidth=1.4, DisplayName="vx");
            plot(obj.Axes.velocity, r.T, r.VY, Color=t.series(2), LineWidth=1.4, DisplayName="vy");
            if isSideways(r)
                plot(obj.Axes.position, r.T, r.Z, Color=t.series(3), LineWidth=1.4, DisplayName="z (to the right)");
                plot(obj.Axes.velocity, r.T, r.VZ, Color=t.series(3), LineWidth=1.4, DisplayName="vz");
            end
            % The label sits at the right end, beyond every landing point (the
            % x-limit is 1.1 times the longest range), clear of launch and arcs.
            yline(a.axes, 0, "-", "Ground", Color=t.TextMuted, HandleVisibility="off", LabelHorizontalAlignment="right");
            accent = t.series(1);
            obj.Anim.tail = plot(a.axes, NaN, NaN, "-", Color=[accent 0.35], LineWidth=3, HandleVisibility="off");
            obj.Anim.point = plot(a.axes, NaN, NaN, "o", MarkerSize=11, MarkerFaceColor=accent, ...
                MarkerEdgeColor=t.Text, LineWidth=1.2, HandleVisibility="off");
            obj.Anim.readout = text(a.axes, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, ...
                FontSize=t.scaled(10), Color=t.TextMuted, VerticalAlignment="top");
            for ax = [a.axes obj.Axes.position obj.Axes.velocity]
                hold(ax, "off");
                dlab.ui.legend(ax, t, "Location", "northeast");
            end
            obj.scaleTrajectoryAxes(shown);
            obj.drawTopView(r);
            obj.drawFrame(r.T(1));
            obj.setOptimalButton(isfield(r, "optimal") && ~isempty(r.optimal));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                r = run.Result;
                dlab.ui.overlayLine(obj.Anim.axes, r.X, r.Y, run);
                dlab.ui.overlayLine(obj.Axes.position, r.T, r.X, run);
                dlab.ui.overlayLine(obj.Axes.position, r.T, r.Y, run);
                dlab.ui.overlayLine(obj.Axes.velocity, r.T, r.VX, run);
                dlab.ui.overlayLine(obj.Axes.velocity, r.T, r.VY, run);
            end
            obj.scaleTrajectoryAxes([{obj.Latest}, {runs.Result}]);   % room for every trajectory
        end

        function clearResult(obj)
            obj.Latest = [];
            obj.setOptimalButton(false);
            for ax = [obj.Anim.axes obj.Axes.position obj.Axes.velocity]
                delete(allchild(ax));
                legend(ax, "off");
            end
            if ~isempty(obj.TopView) && isvalid(obj.TopView)
                delete(allchild(obj.TopView));
            end
        end

        function t = timeVector(~, result)
            t = result.T(:);
        end

        function drawFrame(obj, simTime)
            r = obj.Latest;
            if isempty(r) || ~isvalid(obj.Anim.point)
                return
            end
            k = dlab.core.frameAt(r.T, simTime);
            first = find(r.T >= r.T(k) - obj.TailSeconds, 1, "first");
            set(obj.Anim.point, XData=r.X(k), YData=r.Y(k));
            set(obj.Anim.tail, XData=r.X(first:k), YData=r.Y(first:k));
            lines = [sprintf("t = %.2f s   x = %.2f m   y = %.2f m", r.T(k), r.X(k), r.Y(k))
                sprintf("vx = %.2f m/s   vy = %.2f m/s", r.VX(k), r.VY(k))];
            if isSideways(r)
                lines(1) = lines(1) + sprintf("   z = %.2f m", r.Z(k));
                lines(2) = lines(2) + sprintf("   vz = %.2f m/s", r.VZ(k));
            end
            if strlength(obj.Anim.wind) > 0
                lines(end+1) = obj.Anim.wind;
            end
            obj.Anim.readout.String = join(lines, newline);
        end

        function T = exportTable(~, r)
            T = table(r.T(:), r.X(:), r.Y(:), r.VX(:), r.VY(:), VariableNames=["t" "x" "y" "vx" "vy"]);
            T.Properties.VariableUnits = ["s" "m" "m" "m/s" "m/s"];
            if isfield(r, "Z") && any(r.Z ~= 0)
                T.z = r.Z(:);
                T.vz = r.VZ(:);
                T.Properties.VariableUnits(end-1:end) = ["m" "m/s"];
            end
        end

        function T = summaryTable(~, r)
            speeds = hypot(hypot(r.VX, r.VY), r.VZ);    % with sidespin the ball also moves sideways
            T = table( ...
                ["Flight time"; "Range"; "Maximum height"; "Time to apex"; "Maximum speed"; ...
                 "Impact speed"; "Impact angle"], ...
                [r.impactTime; r.range; r.maxHeight; r.apexTime; max(speeds); r.impactSpeed; r.impactAngle], ...
                ["s"; "m"; "m"; "s"; "m/s"; "m/s"; "deg"], ...
                VariableNames=["Quantity" "Value" "Units"]);
            if isfield(r, "optimal") && ~isempty(r.optimal)
                lost = 0;
                if r.optimal.range > 0
                    lost = 100 * (r.optimal.range - r.range) / r.optimal.range;
                end
                T = [T; table(["Optimal angle"; "Range at optimal angle"; "Range lost vs optimal"], ...
                    [r.optimal.angle; r.optimal.range; lost], ["deg"; "m"; "%"], ...
                    VariableNames=["Quantity" "Value" "Units"])];
            end
            if isfield(r, "stillAirRange") && isfinite(r.stillAirRange)
                T = [T; table("Wind drift", r.range - r.stillAirRange, "m", VariableNames=["Quantity" "Value" "Units"])];
            end
            if isfield(r, "spinParameter") && isfinite(r.spinParameter)
                % S and C_L come from the engine: from the speed relative to the air.
                T = [T; table(["Lateral deflection (+ to the right)"; "Spin parameter S = rω/v at launch"; ...
                    "Lift coefficient at launch"], [r.lateral; r.spinParameter; r.liftCoefficient], ...
                    ["m"; ""; ""], VariableNames=["Quantity" "Value" "Units"])];
            end
        end

        function scene = showcase(~)
            scene = struct("Preset", "Drag example (60°)", "Tab", "Animation", "Time", NaN);
        end

        function description = about(~)
            description = join([
                "Projectile launched from height h₀ until its first ground impact."
                ""
                "Point mass:  x = v₀ cos θ · t,  y = h₀ + v₀ sin θ · t − g t²/2  (exact)."
                "With drag (a sphere):  dv/dt = g − (ρ Cd A / 2m) |v| v, integrated adaptively " + ...
                "(ode45, or ode15s when drag makes the problem stiff); the impact is located exactly."
                ""
                "Spin (sphere): the Magnus force ½ρA·C_L·|v|² acts across the velocity, along ω̂ × v̂. " + ...
                "Backspin lifts, topspin dips, and sidespin curves the ball sideways (the flight is then " + ...
                "3-D: see the Top view). C_L grows with the spin parameter S = rω/v (Sawicki, Hubbard and " + ...
                "Stronge's baseball fit); the spin rate is held constant."
                ""
                "Air: drag acts on the velocity relative to the air, so a steady wind (optionally " + ...
                "stronger with height) carries the projectile; the density can follow the standard " + ...
                "atmosphere from the launch site's altitude. Without drag (point mass) wind has no effect."
                ""
                "The optimal angle is exact for a point mass, atan(v₀ / √(v₀² + 2 g h₀)); with drag it " + ...
                "is searched for (a 5° scan, then fminbnd, golden section with parabolic steps, to 0.01°)."
                ""
                "Assumes flat ground, uniform gravity, a constant drag coefficient, and no buoyancy."
                "Tick ""Keep previous runs"" to compare trajectories."
            ], newline);
        end
    end

    methods (Access = private)
        function best = optimalFor(obj, params)
            %OPTIMALFOR The optimal-angle search for PARAMS. The optimum does
            %   not depend on the launch angle, so the last search is reused
            %   while only theta changes (trying angles, or sweeping theta).
            key = rmfield(params, "theta");
            if ~isempty(obj.OptimalCache.best) && isequaln(obj.OptimalCache.key, key)
                best = obj.OptimalCache.best;
                return
            end
            best = dlab.sims.projectile.optimalAngle(params, obj.progressMonitor());
            obj.OptimalCache = struct("key", key, "best", best);
        end

        function setOptimalButton(obj, enabled)
            if ~isempty(obj.OptimalButton) && isvalid(obj.OptimalButton)
                obj.OptimalButton.Enable = matlab.lang.OnOffSwitchState(enabled);
            end
        end

        function drawTopView(obj, r)
            %DRAWTOPVIEW The flight seen from above (with sidespin).
            ax = obj.TopView;
            if isempty(ax) || ~isvalid(ax)
                return
            end
            t = obj.Theme;
            delete(allchild(ax));
            hold(ax, "on");
            yline(ax, 0, ":", "straight line", Color=t.TextMuted, HandleVisibility="off", ...
                LabelHorizontalAlignment="left");
            plot(ax, r.X, r.Z, Color=t.series(1), LineWidth=1.6);
            plot(ax, r.X(end), r.Z(end), "o", MarkerSize=9, MarkerFaceColor=t.series(2), MarkerEdgeColor=t.Text);
            hold(ax, "off");
            % Seen from above with downrange to the right, the ball's right is
            % down the screen (z down); otherwise the picture is a mirror image.
            ax.YDir = "reverse";
            reach = max(abs(r.Z));
            if reach == 0
                reach = 1;
            end
            ax.YLim = [min(min(r.Z), 0) - 0.15 * reach, max(max(r.Z), 0) + 0.15 * reach];   % the straight line inside
            ax.XLim = [0, max(max(r.X), eps) * 1.05];
            side = "right";
            if r.lateral < 0
                side = "left";
            end
            title(ax, sprintf("From above: %.2f m to the %s", abs(r.lateral), side));
        end

        function scaleTrajectoryAxes(obj, runs)
            ax = obj.Anim.axes;
            xs = cellfun(@(r) max(r.X), runs);
            ys = cellfun(@(r) max(r.Y), runs);
            xMax = positiveOr1(max(xs)) * 1.1;
            % Head room for the readout (top left) and the legend (top right).
            yMax = positiveOr1(max(ys)) * 1.35;
            if obj.EqualAxes
                % A flat throw would otherwise be a thin strip under the readout.
                yMax = max(yMax, 0.3 * xMax);
                axis(ax, "equal");
            else
                axis(ax, "normal");
            end
            set(ax, XLim=[0 xMax], YLim=[0 yMax]);
        end
    end
end

function tf = isSideways(r)
% True when the flight leaves the vertical plane (sidespin).
tf = isfield(r, "Z") && any(r.Z ~= 0);
end

function value = positiveOr1(value)
if isempty(value) || ~isfinite(value) || value <= 0
    value = 1;
end
end
