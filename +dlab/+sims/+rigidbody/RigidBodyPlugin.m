classdef RigidBodyPlugin < dlab.core.TimeDomainPlugin
    %RIGIDBODYPLUGIN Rotation in 3-D: a tumbling free body (the tennis
    %   racket theorem) and a heavy spinning top (precession and
    %   nutation). Solved by simulateRigidBody.

    properties (Constant)
        Id = "rigidbody"
        Title = "Rigid-Body Rotation"
        Category = "Mechanics"
        Summary = "Tumbling bodies and spinning tops: the intermediate-axis flip, precession, and nutation."
        SchemaVersion = 1
    end

    properties (Constant, Access = private)
        FreeTabs = ["Angular velocity" "Angular momentum" "Conservation" "Polhode" "Axis trace"]
        TopTabs = ["Angular velocity" "Angular momentum" "Conservation" "Nutation and precession" "Axis trace"]
        TrailSeconds = 3
        TopHeight = 1          % drawing: cone height (pivot to rim)
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            isFree = @(p) p.model == "free";
            isTop = @(p) p.model == "top";
            specs = [
                P("model", Label="Body", Type="choice", Default="free", Choices=["free" "top"], ...
                    ChoiceLabels=["Free body" "Spinning top"], Group="Body", ...
                    Description="A body tumbling freely with no torque, or a heavy symmetric top on a pivot.")
                P("I1", Label="Inertia I₁", Units="kg·m²", Default=1, Min=1e-6, Max=1e6, Group="Body", ...
                    VisibleWhen=isFree, Description="Principal moment of inertia about the centre of mass. " + ...
                    "Each of I₁, I₂, I₃ must be at most the sum of the other two (equal: a flat plate).")
                P("I2", Label="Inertia I₂", Units="kg·m²", Default=2, Min=1e-6, Max=1e6, Group="Body", VisibleWhen=isFree, ...
                    Description="Principal moment of inertia about the centre of mass.")
                P("I3", Label="Inertia I₃", Units="kg·m²", Default=2.5, Min=1e-6, Max=1e6, Group="Body", VisibleWhen=isFree, ...
                    Description="Principal moment of inertia about the centre of mass.")
                P("w1", Label="Spin ω₁", Units="rad/s", Default=0.001, Min=-1000, Max=1000, Group="Start", ...
                    VisibleWhen=isFree, Description="Initial angular velocity in body axes.")
                P("w2", Label="Spin ω₂", Units="rad/s", Default=10, Min=-1000, Max=1000, Group="Start", VisibleWhen=isFree, ...
                    Description="Initial angular velocity in body axes.")
                P("w3", Label="Spin ω₃", Units="rad/s", Default=0.001, Min=-1000, Max=1000, Group="Start", VisibleWhen=isFree, ...
                    Description="Initial angular velocity in body axes.")
                P("spinAxis", Label="Spin axis", Type="choice", Default="auto", ...
                    Choices=["auto" "1" "2" "3"], ChoiceLabels=["Auto" "Axis 1" "Axis 2" "Axis 3"], ...
                    Group="Start", VisibleWhen=isFree, ...
                    Description="The steady spin the Modes tab linearizes about, and the axis the Axis trace " + ...
                    "follows. Auto: the body axis nearest the angular momentum (largest |I_k ω_k|).")
                P("m", Label="Mass", Units="kg", Default=0.5, Min=1e-4, Max=1e4, Group="Body", VisibleWhen=isTop, ...
                    Description="The motion depends on the mass, gravity, and pivot distance only through m g l.")
                P("l", Label="Pivot to centre of mass", Units="m", Default=0.04, Min=1e-4, Max=100, Group="Body", ...
                    VisibleWhen=isTop, Description="Distance from the pivot (the tip) to the centre of mass, along the spin axis.")
                P("Is", Label="Inertia about the spin axis", Units="kg·m²", Default=2e-4, Min=1e-9, Max=1e4, ...
                    Group="Body", VisibleWhen=isTop, DisplayFormat="%.4g", ...
                    Description="I_s: at most twice the inertia across (a flat disc has exactly twice).")
                P("It", Label="Inertia across, about the pivot", Units="kg·m²", Default=1e-3, Min=1e-9, Max=1e4, ...
                    Group="Body", VisibleWhen=isTop, DisplayFormat="%.4g", ...
                    Description="I_t about an axis through the pivot, across the spin axis: the inertia about " + ...
                    "the centre of mass plus m l².")
                P("spin", Label="Spin rate", Units="rad/s", Default=200, Min=-1e4, Max=1e4, Group="Start", VisibleWhen=isTop, ...
                    Description="ω₃, the spin component along the top's axis (it stays constant). Upright, the " + ...
                    "top is stable above ω₃ = 2√(I_t m g l)/I_s.")
                P("tilt", Label="Tilt", Units="°", Default=30, Min=0, Max=179, Group="Start", VisibleWhen=isTop, ...
                    Description="Initial angle of the spin axis from the upward vertical.")
                P("precession", Label="Initial precession rate", Units="rad/s", Default=0, Min=-1000, Max=1000, ...
                    Group="Start", VisibleWhen=isTop, Description="φ' at the start: how fast the axis turns about the vertical.")
                P("nutation", Label="Initial nutation rate", Units="rad/s", Default=0, Min=-1000, Max=1000, ...
                    Group="Start", VisibleWhen=isTop, Description="θ' at the start: how fast the tilt grows.")
                P("g", Label="Gravity", Units="m/s²", Default=9.81, Min=0.01, Max=100, Group="Body", VisibleWhen=isTop, ...
                    Description="Gravitational acceleration (the top's weight acts at its centre of mass).")
                P("tspan", Label="Duration", Units="s", Default=10, Min=0.01, Max=1e4, Group="Simulation", MarksCustom=false, ...
                    Description="How long to simulate.")
                P("dt", Label="Output step", Units="s", Default=0.01, Min=1e-5, Max=10, Group="Simulation", ...
                    DisplayFormat="%.4g", ...
                    Description="Spacing of the saved samples; the solver picks its own steps.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Tennis racket (Dzhanibekov effect)", "Values", struct("tspan", 20));
            list(end+1) = struct("Name", "Stable spin: major axis", "Values", struct("w1", 0.1, "w2", 0.1, "w3", 10));
            list(end+1) = struct("Name", "Stable spin: minor axis", "Values", struct("w1", 10, "w2", 0.1, "w3", 0.1));
            list(end+1) = struct("Name", "Symmetric body: free precession", "Values", struct( ...
                "I1", 2, "I2", 2, "I3", 3, "w1", 0.5, "w2", 0, "w3", 4));
            top = struct("model", "top", "m", 0.5, "l", 0.04, "Is", 2e-4, "It", 1e-3, "g", 9.81, ...
                "tilt", 30, "precession", 0, "nutation", 0, "tspan", 5, "dt", 0.005);
            list(end+1) = struct("Name", "Spinning top: fast", "Values", withFields(top, "spin", 400));
            list(end+1) = struct("Name", "Spinning top: looping nutation", "Values", withFields(top, ...
                "spin", 80, "precession", -3, "tspan", 4));
            list(end+1) = struct("Name", "Sleeping top", "Values", withFields(top, "spin", 300, "tilt", 2, ...
                "precession", 0, "tspan", 4));
        end

        function result = solve(obj, p)
            q = struct("model", char(p.model), "I", [p.I1 p.I2 p.I3], "omega0", [p.w1 p.w2 p.w3], ...
                "m", p.m, "l", p.l, "g", p.g, "Is", p.Is, "It", p.It, "spin", p.spin, ...
                "tilt", deg2rad(p.tilt), "precession", p.precession, "nutation", p.nutation, ...
                "tspan", p.tspan, "dt", p.dt, "progressFcn", obj.progressMonitor());
            result = dlab.sims.rigidbody.simulateRigidBody(q);
            result.params = p;
            result.spinAxis = spinAxisOf(p);
        end

        function titles = outputTabs(obj, p)
            titles = obj.FreeTabs;
            if p.model == "top"
                titles = obj.TopTabs;
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax = struct();
            obj.Ax.omega = dlab.ui.axesIn(containers{"Angular velocity"}, t, Title="Angular velocity (body axes)", ...
                XLabel="Time (s)", YLabel="ω (rad/s)");
            obj.Ax.L = dlab.ui.axesIn(containers{"Angular momentum"}, t, Title="Angular momentum (world axes)", ...
                XLabel="Time (s)", YLabel="L (kg·m²/s)");
            obj.Ax.drift = dlab.ui.axesIn(containers{"Conservation"}, t, Title="Conservation (relative change)", ...
                XLabel="Time (s)", YLabel="Relative change");
            if isKey(containers, "Polhode")
                obj.Ax.polhode = dlab.ui.axesIn(containers{"Polhode"}, t, ...
                    Title="Polhode: ω in body axes, on the energy and momentum ellipsoids", ...
                    XLabel="ω₁ (rad/s)", YLabel="ω₂ (rad/s)");
                zlabel(obj.Ax.polhode, "ω₃ (rad/s)");
            end
            if isKey(containers, "Nutation and precession")
                grid = uigridlayout(containers{"Nutation and precession"}, [2 1], Padding=0, ...
                    RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
                obj.Ax.nutation = dlab.ui.axesIn(grid, t, Row=1, Title="Tilt from vertical (nutation)", ...
                    XLabel="Time (s)", YLabel="θ (°)");
                obj.Ax.precession = dlab.ui.axesIn(grid, t, Row=2, Title="Precession rate", ...
                    XLabel="Time (s)", YLabel="φ' (rad/s)");
            end
            obj.Ax.trace = dlab.ui.axesIn(containers{"Axis trace"}, t, Title="Axis trace on the unit sphere", ...
                XLabel="x", YLabel="y");
            zlabel(obj.Ax.trace, "z");
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme, Title="Rigid body");
            disableDefaultInteractivity(ax);
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            t = obj.Theme;

            ax = obj.Ax.omega;
            dlab.ui.clearAxes(ax);
            for k = 1:3
                plot(ax, r.t, r.omega(:, k), Color=t.series(k), LineWidth=1.4, DisplayName=sprintf("ω_%d", k));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");

            ax = obj.Ax.L;
            dlab.ui.clearAxes(ax);
            names = ["L_x" "L_y" "L_z"];
            for k = 1:3
                plot(ax, r.t, r.L(:, k), Color=t.series(k), LineWidth=1.4, DisplayName=names(k));
            end
            hold(ax, "off");
            dlab.ui.legend(ax, t, "Location", "best");
            if ~r.isTop
                title(ax, "Angular momentum (world axes): constant without torque");
            end

            ax = obj.Ax.drift;
            dlab.ui.clearAxes(ax);
            tiny = 1e-17;           % log axes: exact zeros drawn here
            E = r.energy;
            plot(ax, r.t, max(abs(E - E(1)) / max(abs(E(1)), realmin), tiny), Color=t.series(1), ...
                LineWidth=1.3, DisplayName="Energy");
            if r.isTop
                Lref = max(norm(r.L(1, :)), realmin);
                plot(ax, r.t, max(abs(r.L(:, 3) - r.L(1, 3)) / Lref, tiny), Color=t.series(2), LineWidth=1.3, ...
                    DisplayName="L_z (vertical)");
                L3 = r.I(3) * r.omega(:, 3);
                plot(ax, r.t, max(abs(L3 - L3(1)) / Lref, tiny), Color=t.series(3), LineWidth=1.3, ...
                    DisplayName="L_3 (spin axis)");
            else
                Ln = sqrt(sum(r.L.^2, 2));
                plot(ax, r.t, max(abs(Ln - Ln(1)) / max(Ln(1), realmin), tiny), Color=t.series(2), ...
                    LineWidth=1.3, DisplayName="|L|");
            end
            plot(ax, r.t, max(r.qnormError, tiny), Color=t.series(4), LineWidth=1.3, DisplayName="‖q‖ − 1");
            hold(ax, "off");
            set(ax, YScale="log");
            dlab.ui.legend(ax, t, "Location", "best");

            if isfield(obj.Ax, "polhode")
                obj.drawPolhode(r);
            end
            if isfield(obj.Ax, "nutation")
                ax = obj.Ax.nutation;
                dlab.ui.clearAxes(ax);
                plot(ax, r.t, rad2deg(r.theta), Color=t.series(1), LineWidth=1.3);
                hold(ax, "off");
                ax = obj.Ax.precession;
                dlab.ui.clearAxes(ax);
                plot(ax, r.t, gradient(r.phi, r.t), Color=t.series(2), LineWidth=1.2, DisplayName="φ'");
                yline(ax, r.precessionRate, "--", Color=t.Text, DisplayName=sprintf("Mean %.4g rad/s", r.precessionRate));
                steady = steadyPrecession(params);
                if isfinite(steady)
                    yline(ax, steady, "-.", Color=t.series(4), LineWidth=1.2, ...
                        DisplayName=sprintf("Steady %.4g rad/s", steady));
                end
                if isfinite(gyroscopic(params))
                    yline(ax, gyroscopic(params), ":", Color=t.series(3), LineWidth=1.4, ...
                        DisplayName="m g l / (I_s ω_s)");
                end
                hold(ax, "off");
                dlab.ui.legend(ax, t, "Location", "northoutside", "Orientation", "horizontal");
            end

            ax = obj.Ax.trace;
            dlab.ui.clearAxes(ax);
            [sx, sy, sz] = sphere(24);
            surf(ax, sx, sy, sz, FaceColor="none", EdgeColor=t.Grid, EdgeAlpha=0.35);
            tip = traceAxis(r);
            plot3(ax, tip(:, 1), tip(:, 2), tip(:, 3), Color=t.series(1), LineWidth=1.5);
            plot3(ax, tip(1, 1), tip(1, 2), tip(1, 3), "o", MarkerFaceColor=t.series(2), MarkerEdgeColor=t.Text);
            hold(ax, "off");
            axis(ax, "equal");
            set(ax, XLim=[-1.1 1.1], YLim=[-1.1 1.1], ZLim=[-1.1 1.1]);
            view(ax, -35, 25);
            if r.isTop
                title(ax, "Path of the spin axis (the top's tip)");
            else
                title(ax, sprintf("Path of body axis %d (the spin axis)", r.spinAxis));
            end

            obj.setupAnimation(r);
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                for k = 1:3
                    dlab.ui.overlayLine(obj.Ax.omega, run.Result.t, run.Result.omega(:, k), run);
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

        function rate = playbackRate(~, r)
            % Real time for a top (its precession is what to watch); fast
            % free bodies slowed down so that their tumbling can be followed.
            rate = 1;
            if ~r.isTop
                rate = min(1, 10 / max(max(sqrt(sum(r.omega.^2, 2))), eps));
            end
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "body")
                return
            end
            a = obj.Anim;
            k = dlab.core.frameAt(r.t, simTime);
            R = reshape(r.axes(k, :, :), 3, 3);
            set(a.body, Vertices=dlab.ui.Schematic.transform(a.vertices, R, [0 0 0]));
            if isfield(a, "rim")
                set(a.rim, Vertices=dlab.ui.Schematic.transform(a.rimVertices, R, [0 0 0]));
                axle = R(:, 3) * a.axleEnds;
                set(a.axle, XData=axle(1, :), YData=axle(2, :), ZData=axle(3, :));
            end
            w = R * r.omega(k, :)';
            w = a.omegaScale * w;
            set(a.omega, XData=[0 w(1)], YData=[0 w(2)], ZData=[0 w(3)]);
            L = a.LScale * r.L(k, :);
            set(a.L, XData=[0 L(1)], YData=[0 L(2)], ZData=[0 L(3)]);
            from = find(r.t >= r.t(k) - obj.TrailSeconds, 1);
            tip = a.tipLength * traceAxis(r, from:k);
            set(a.trail, XData=tip(:, 1), YData=tip(:, 2), ZData=tip(:, 3));
            a.readout.String = sprintf("t = %.3f s   |ω| = %.3g rad/s", simTime, norm(r.omega(k, :)));
        end

        function T = exportTable(~, r)
            T = table(r.t, r.omega(:, 1), r.omega(:, 2), r.omega(:, 3), r.q(:, 1), r.q(:, 2), r.q(:, 3), ...
                r.q(:, 4), r.L(:, 1), r.L(:, 2), r.L(:, 3), r.energy, VariableNames=["time" "omega_1" ...
                "omega_2" "omega_3" "q_w" "q_x" "q_y" "q_z" "L_x" "L_y" "L_z" "energy"]);
            T.Properties.VariableUnits = ["s" "rad/s" "rad/s" "rad/s" "" "" "" "" "kg*m^2/s" "kg*m^2/s" ...
                "kg*m^2/s" "J"];
        end

        function T = summaryTable(~, r)
            p = r.params;
            rows = {"Energy drift (relative)", r.drift.energy, ""};
            notes = strings(0, 2);                       % Quantity, text shown instead of the value
            if r.isTop
                rows(end+1:end+2, :) = {"L_z drift (relative)", r.drift.Lz, ""; "L_3 drift (relative)", r.drift.L3, ""};
                rate = r.precessionRate;
                if max(r.theta) < 1e-9
                    rate = NaN;
                    notes(end+1, :) = ["Precession rate", "— (upright: no precession)"];
                end
                rows(end+1, :) = {"Precession rate", rate, "rad/s"};
                [steady, why] = steadyPrecession(p);
                rows(end+1, :) = {"Steady precession at the start tilt", steady, "rad/s"};
                if ~isfinite(steady)
                    notes(end+1, :) = ["Steady precession at the start tilt", why];
                end
                rows(end+1, :) = {"Gyroscopic estimate m g l / (I_s ω_s)", gyroscopic(p), "rad/s"};
                if ~isfinite(gyroscopic(p))
                    notes(end+1, :) = ["Gyroscopic estimate m g l / (I_s ω_s)", "— (no spin)"];
                end
                rows(end+1, :) = {"Nutation amplitude", rad2deg(r.nutationAmplitude), "°"};
                rows(end+1, :) = {"Largest tilt", rad2deg(max(r.theta)), "°"};
            else
                rows(end+1, :) = {"|L| drift (relative)", r.drift.L, ""};
                if r.flipAxis == 0
                    rows(end+1, :) = {"Flips", NaN, ""};
                    notes(end+1, :) = ["Flips", "— (two inertias equal: no intermediate axis)"];
                else
                    rows(end+1, :) = {"Flips", r.flips, ""};
                end
                if r.flips >= 2
                    rows(end+1, :) = {"Time between flips", mean(diff(r.flipTimes)), "s"};
                end
                [stable, word] = spinStability(r.I, r.spinAxis);
                rows(end+1:end+2, :) = {"Spin axis", r.spinAxis, ""; "Spin axis stable", stable, ""};
                notes(end+1, :) = ["Spin axis stable", word];
            end
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), ...
                VariableNames=["Quantity" "Value" "Units"]);
            T.Display = repmat("", height(T), 1);
            for k = 1:size(notes, 1)
                T.Display(T.Quantity == notes(k, 1)) = notes(k, 2);
            end
        end

        function lin = linearization(~, p)
            lin = [];
            if p.model ~= "free"
                return
            end
            I = [p.I1; p.I2; p.I3];
            k = spinAxisOf(p);
            w0 = [p.w1; p.w2; p.w3];
            X0 = zeros(3, 1);
            X0(k) = w0(k);
            if abs(X0(k)) < 1e-9
                X0(k) = max(norm(w0), 1);
            end
            lin = struct("F", @(w) cross(I .* w, w) ./ I, "X0", X0, "StateNames", ["ω₁" "ω₂" "ω₃"], ...
                "Reference", sprintf("steady spin about axis %d at %.4g rad/s", k, X0(k)), ...
                "Classify", @modeNames, "Scale", abs(X0(k)) * [1 1 1]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Tennis racket (Dzhanibekov effect)", "Tab", "Animation", "Time", 2.8);
        end

        function description = about(~)
            description = join([
                "Euler's equations in body axes, with an attitude quaternion:"
                "  I ω' = (I ω) × ω + τ,      q' = ½ q ⊗ [0; ω]"
                ""
                "Free body: τ = 0, so the energy and the angular momentum L (fixed in space) are " + ...
                "constant. Spin about the axis of largest or smallest inertia is stable; spin about " + ...
                "the intermediate axis is not, and the body flips over and over (the tennis racket " + ...
                "theorem, or Dzhanibekov effect)."
                ""
                "Spinning top: τ = r_cm × (m g) about the pivot. A fast top precesses slowly at about " + ...
                "m g l / (I_s ω_s) while it nutates (nods) up and down."
            ], newline);
        end
    end

    methods (Access = private)
        function drawPolhode(obj, r)
            t = obj.Theme;
            ax = obj.Ax.polhode;
            dlab.ui.clearAxes(ax);
            I = r.I;
            E = 0.5 * sum(I .* r.omega(1, :).^2);
            L = norm(I .* r.omega(1, :));
            [sx, sy, sz] = sphere(40);
            energy = sqrt(2 * E ./ I);
            momentum = L ./ I;
            surf(ax, energy(1) * sx, energy(2) * sy, energy(3) * sz, FaceColor=t.series(1), FaceAlpha=0.12, ...
                EdgeColor="none", DisplayName="Energy ellipsoid");
            surf(ax, momentum(1) * sx, momentum(2) * sy, momentum(3) * sz, FaceColor=t.series(2), FaceAlpha=0.12, ...
                EdgeColor="none", DisplayName="Momentum ellipsoid");
            plot3(ax, r.omega(:, 1), r.omega(:, 2), r.omega(:, 3), Color=t.series(3), LineWidth=2, ...
                DisplayName="ω (the polhode)");
            hold(ax, "off");
            axis(ax, "equal");
            view(ax, -35, 25);
            dlab.ui.legend(ax, t, "Location", "northeastoutside");
        end

        function setupAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            dlab.ui.clearAxes(ax);
            a = struct("axes", ax);
            if r.isTop
                h = obj.TopHeight;
                radius = 0.45 * h;
                [faces, vertices] = dlab.ui.Schematic.cone3(radius, h);
                a.vertices = vertices;
                a.body = patch(ax, Faces=faces, Vertices=vertices, FaceColor=t.series(1), EdgeColor="none", ...
                    FaceAlpha=0.9);
                [cx, cy] = dlab.ui.Schematic.circle([0 0], radius, 48);
                a.rimVertices = [cx(:), cy(:), h * ones(numel(cx), 1)];
                a.rim = patch(ax, Faces=[1:numel(cx), 1], Vertices=a.rimVertices, FaceColor="none", ...
                    EdgeColor=t.Text, LineWidth=1.5);
                a.axleEnds = [h 1.3 * h];                        % the axle above the rim, along body z
                a.axle = plot3(ax, [0 0], [0 0], a.axleEnds, Color=t.Text, LineWidth=2, HandleVisibility="off");
                a.tipLength = 1.3 * h;
                limit = 1.6 * h;
                % A top whose rim would dip below its tip turns on a stand
                % (a gyroscope on a pivot): a floor there would cut it.
                floorZ = 0;
                if max(r.theta) + atan(radius / h) > pi / 2
                    floorZ = -1.45 * h;
                    plot3(ax, [0 0], [0 0], [floorZ 0], Color=t.TextMuted, LineWidth=4, ...
                        HandleVisibility="off", Tag="dlab.rigidbody.stand");
                end
                [gx, gy] = meshgrid([-1.5 1.5] * h);
                surf(ax, gx, gy, floorZ * ones(2), FaceColor=t.Border, FaceAlpha=0.35, EdgeColor=t.Grid, ...
                    HandleVisibility="off", Tag="dlab.rigidbody.floor");
                set(ax, XLim=[-limit limit], YLim=[-limit limit], ZLim=[min(-0.2, floorZ - 0.15) limit]);
            else
                I = r.I;
                dims = sqrt(max(I([2 3 1]) + I([3 1 2]) - I, 1e-9 * max(I)));
                dims = 1.6 * dims / max(dims);
                [faces, vertices] = dlab.ui.Schematic.box3(dims);
                a.vertices = vertices;
                colors = [t.series(3); t.series(3); t.series(2); t.series(1); t.series(2); t.series(1)];
                a.body = patch(ax, Faces=faces, Vertices=vertices, FaceColor="flat", FaceVertexCData=colors, ...
                    EdgeColor=t.Text, FaceAlpha=0.85);
                a.tipLength = 1.2;
                set(ax, XLim=[-1.3 1.3], YLim=[-1.3 1.3], ZLim=[-1.3 1.3]);
            end
            Lmax = max(sqrt(sum(r.L.^2, 2)));
            wmax = max(sqrt(sum(r.omega.^2, 2)));
            a.LScale = 1.2 / max(Lmax, realmin);
            a.omegaScale = 1.2 / max(wmax, realmin);
            a.L = plot3(ax, NaN, NaN, NaN, Color=t.Text, LineWidth=2.5, DisplayName="L");
            a.omega = plot3(ax, NaN, NaN, NaN, Color=t.series(5), LineWidth=2, DisplayName="ω");
            a.trail = plot3(ax, NaN, NaN, NaN, Color=t.Accent, LineWidth=1.2, DisplayName="Axis trail");
            a.readout = text(ax, 0.01, 0.98, "", Units="normalized", FontName=t.MonoFont, FontSize=t.scaled(10), ...
                Color=t.TextMuted, VerticalAlignment="top");
            hold(ax, "off");
            daspect(ax, [1 1 1]);
            view(ax, -35, 20);
            xlabel(ax, "x");
            ylabel(ax, "y");
            zlabel(ax, "z");
            dlab.ui.legend(ax, t, [a.L a.omega a.trail], "Location", "northeast");
            obj.Anim = a;
        end
    end
end

% ---------------------------------------------------------------- helpers
function s = withFields(s, varargin)
for k = 1:2:numel(varargin)
    s.(varargin{k}) = varargin{k + 1};
end
end

function k = spinAxisOf(p)
% The chosen axis, or the body axis nearest the angular momentum.
if p.spinAxis == "auto"
    [~, k] = max(abs([p.I1 p.I2 p.I3] .* [p.w1 p.w2 p.w3]));
else
    k = double(p.spinAxis);
end
end

function rate = gyroscopic(p)
% The fast-top estimate m g l / (I_s ω₃); NaN without spin.
rate = NaN;
if p.spin ~= 0
    rate = p.m * p.g * p.l / (p.Is * p.spin);
end
end

function [rate, why] = steadyPrecession(p)
% Steady precession at the start tilt θ: the slow root of
%   I_t cos θ Ω² − I_s ω₃ Ω + m g l = 0
% (the one that tends to m g l / (I_s ω₃) for a fast top). NaN, with the
% reason, when the top cannot precess steadily there.
rate = NaN;
why = "";
a = p.It * cosd(p.tilt);
b = p.Is * p.spin;
mgl = p.m * p.g * p.l;
discriminant = b^2 - 4 * a * mgl;
if p.tilt == 0
    why = "— (upright)";
elseif discriminant < 0
    why = "none: too slow at this tilt";
elseif b ~= 0
    rate = 2 * mgl / (b + sign(b) * sqrt(discriminant));
elseif a < 0
    rate = sqrt(-mgl / a);                       % no spin, hanging: a conical pendulum
else
    why = "none: no spin";
end
end

function [stable, word] = spinStability(I, k)
% Steady spin about axis K: stable about the largest or smallest inertia,
% unstable about the intermediate one, neutral when another inertia
% equals it (the spin then drifts towards the other axis).
others = I([1:k - 1, k + 1:3]);
if any(abs(others - I(k)) <= 1e-9 * max(I))
    [stable, word] = deal(NaN, "neutral (equal inertias)");
elseif I(k) > max(others) || I(k) < min(others)
    [stable, word] = deal(1, "yes");
else
    [stable, word] = deal(0, "no");
end
end

function tip = traceAxis(r, rows)
% World coordinates of the traced body axis (the top's spin axis, or the
% free body's spin axis), at ROWS.
if nargin < 2
    rows = 1:numel(r.t);
end
column = 3;
if ~r.isTop
    column = r.spinAxis;
end
tip = r.axes(rows, :, column);
end

function labels = modeNames(lambda, ~)
%MODENAMES Wobble (stable), tumble (unstable, with its decaying partner),
%   or the neutral spin itself.
labels = strings(numel(lambda), 1);
scale = max(1, max(abs(lambda)));
for k = 1:numel(lambda)
    if abs(lambda(k)) < 1e-9 * scale
        labels(k) = "Spin (neutral)";
    elseif abs(imag(lambda(k))) > abs(real(lambda(k)))
        labels(k) = "Wobble (stable)";
    elseif real(lambda(k)) > 0
        labels(k) = "Tumble (unstable)";
    else
        labels(k) = "Tumble (decaying)";             % the saddle's other direction
    end
end
end
