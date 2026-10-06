classdef MassSpringPlugin < dlab.core.TimeDomainPlugin
    %MASSSPRINGPLUGIN Single or coupled mass-spring-damper systems, with
    %   harmonic forcing and (coupled) wall and mass-to-mass collisions.

    properties (Constant)
        Id = "massspring"
        Title = "Mass-Spring"
        Category = "Mechanics"
        Summary = "Single and coupled spring-damper systems with forcing and collisions."
        SchemaVersion = 2       % 2: forcing profiles (forceShape, Fprofile)
    end

    properties (Constant, Access = private)
        FlashSeconds = 0.25      % how long an impact burst stays visible (simulated time)
        Coils = 8
        SpringY = 0.1            % heights in the animation: mass from −0.28 to 0.28, on the floor
        DamperY = -0.15
    end

    properties (Access = private)
        Ax struct = struct()
        Anim struct = struct()
        Geometry struct = struct()
        Result
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            single = @(p) p.mode == "single";
            coupled = @(p) p.mode == "coupled";
            big = 1e6;
            specs = [
                P("mode", Label="System", Type="choice", Default="single", Choices=["single" "coupled"], ...
                    ChoiceLabels=["Single mass" "Two masses"], Group="System", ...
                    Description="Single mass: one mass on a spring and damper. Two masses: coupled between two " + ...
                    "walls by three springs, with two normal modes.")
                % Single mass
                P("m", Label="Mass m", Units="kg", Default=1, Min=1e-6, Max=big, Group="Single mass", VisibleWhen=single, ...
                    Description="Mass on the spring.")
                P("k", Label="Stiffness k", Units="N/m", Default=10, Min=1e-6, Max=big, Group="Single mass", VisibleWhen=single, ...
                    Description="Spring stiffness: the force per metre of stretch.")
                P("c", Label="Damping c", Units="N·s/m", Default=0.5, Min=0, Max=big, Group="Single mass", VisibleWhen=single, ...
                    Description="A viscous damper: its force is −c v.")
                P("x0", Label="Initial position x₀", Units="m", Default=1, Min=-big, Max=big, Group="Single mass", VisibleWhen=single, ...
                    Description="Displacement from equilibrium (the unstretched spring).")
                P("v0", Label="Initial velocity v₀", Units="m/s", Default=0, Min=-big, Max=big, Group="Single mass", VisibleWhen=single, ...
                    Description="Velocity of the mass at the start.")
                P("forced", Label="External force", Type="logical", Default=false, Group="Forcing", VisibleWhen=single, ...
                    Description="A force on the mass: harmonic, or a profile such as a step or pulse.")
                P("forceShape", Label="Force", Type="choice", Default="harmonic", Choices=["harmonic" "profile"], ...
                    ChoiceLabels=["Harmonic" "Profile"], Group="Forcing", ...
                    VisibleWhen=@(p) single(p) && p.forced, ...
                    Description="Harmonic: F₀ cos(ωf t + φ). Profile: a step, pulse, ramp, … in time.")
                P("F0", Label="Amplitude F₀", Units="N", Default=2, Min=-big, Max=big, Group="Forcing", ...
                    VisibleWhen=@(p) single(p) && p.forced && p.forceShape == "harmonic", ...
                    Description="Amplitude of the harmonic force.")
                P("omega_f", Label="Frequency ωf", Units="rad/s", Default=3, Min=0, Max=big, Group="Forcing", ...
                    VisibleWhen=@(p) single(p) && p.forced && p.forceShape == "harmonic", ...
                    Description="Angular frequency of the harmonic force (2π times its frequency in hertz).")
                P("phi_f", Label="Phase φ", Units="rad", Default=0, Min=-big, Max=big, Group="Forcing", ...
                    VisibleWhen=@(p) single(p) && p.forced && p.forceShape == "harmonic", ...
                    Description="Phase of the harmonic force at t = 0.")
                P("Fprofile", Label="Force profile", Units="N", Type="schedule", ...
                    Default=dlab.core.Schedule.make("step", Value=0, Amplitude=2, Start=1), Min=-big, Max=big, ...
                    Group="Forcing", VisibleWhen=@(p) single(p) && p.forced && p.forceShape == "profile", ...
                    Description="A step shows the step response; a short pulse, the impulse response.")
                % Coupled masses
                P("m1", Label="Mass m₁", Units="kg", Default=1, Min=1e-6, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Mass of the left body, attached to the left wall by k₁.")
                P("m2", Label="Mass m₂", Units="kg", Default=1.5, Min=1e-6, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Mass of the right body, attached to the right wall by k₃.")
                P("k1", Label="Left spring k₁", Units="N/m", Default=8, Min=0, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="From the left wall to m₁. 0 leaves it out.")
                P("k2", Label="Coupling spring k₂", Units="N/m", Default=4, Min=0, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Between the two masses. 0 leaves it out.")
                P("k3", Label="Right spring k₃", Units="N/m", Default=6, Min=0, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="From m₂ to the right wall. 0 leaves it out.")
                P("c1", Label="Damping c₁", Units="N·s/m", Default=0.3, Min=0, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="A damper from the left wall to m₁: force −c₁ v₁.")
                P("c2", Label="Damping c₂", Units="N·s/m", Default=0.3, Min=0, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="A damper from m₂ to the right wall: force −c₂ v₂.")
                P("x1_0", Label="Initial x₁", Units="m", Default=1, Min=-big, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Displacements are measured from equilibrium, positive to the right.")
                P("v1_0", Label="Initial v₁", Units="m/s", Default=0, Min=-big, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Velocity of m₁ at the start.")
                P("x2_0", Label="Initial x₂", Units="m", Default=0, Min=-big, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Position of m₂ at the start, from its rest position.")
                P("v2_0", Label="Initial v₂", Units="m/s", Default=0, Min=-big, Max=big, Group="Coupled masses", VisibleWhen=coupled, ...
                    Description="Velocity of m₂ at the start.")
                P("forced_c", Label="External force on m₁", Type="logical", Default=false, ...
                    Group="Forcing on m₁", VisibleWhen=coupled, ...
                    Description="Push m₁ with a force: harmonic, or a profile such as a step or pulse.")
                P("forceShape_c", Label="Force", Type="choice", Default="harmonic", Choices=["harmonic" "profile"], ...
                    ChoiceLabels=["Harmonic" "Profile"], Group="Forcing on m₁", ...
                    VisibleWhen=@(p) coupled(p) && p.forced_c, ...
                    Description="Harmonic: F₀ cos(ωf t). Profile: a step, pulse, ramp, … in time.")
                P("F0_c", Label="Amplitude F₀", Units="N", Default=1.5, Min=-big, Max=big, Group="Forcing on m₁", ...
                    VisibleWhen=@(p) coupled(p) && p.forced_c && p.forceShape_c == "harmonic", ...
                    Description="Amplitude of the harmonic force on m₁.")
                P("omega_fc", Label="Frequency ωf", Units="rad/s", Default=2, Min=0, Max=big, Group="Forcing on m₁", ...
                    VisibleWhen=@(p) coupled(p) && p.forced_c && p.forceShape_c == "harmonic", ...
                    Description="Angular frequency of the harmonic force on m₁.")
                P("Fprofile_c", Label="Force profile", Units="N", Type="schedule", ...
                    Default=dlab.core.Schedule.make("pulse", Value=0, Amplitude=5, Start=1, Width=0.2), ...
                    Min=-big, Max=big, Group="Forcing on m₁", ...
                    VisibleWhen=@(p) coupled(p) && p.forced_c && p.forceShape_c == "profile", ...
                    Description="The force on m₁ in time: a step, pulse, ramp, … or custom points.")
                P("collision_on", Label="Collisions", Type="logical", Default=false, Group="Collisions", ...
                    VisibleWhen=coupled, Description="Walls and the masses become rigid contacts.")
                P("e_rest", Label="Restitution e", Default=0.8, Min=0, Max=1, Group="Collisions", ...
                    VisibleWhen=@(p) coupled(p) && p.collision_on, Description="1 = elastic, 0 = perfectly plastic.")
                P("coll_wall_clr", Label="Wall clearance", Units="m", Default=2, Min=1e-6, Max=big, Group="Collisions", ...
                    VisibleWhen=@(p) coupled(p) && p.collision_on, ...
                    Description="How far each mass can move toward its wall from equilibrium before it touches.")
                P("coll_eq_sep", Label="Equilibrium separation", Units="m", Default=1.5, Min=1e-6, Max=big, ...
                    Group="Collisions", VisibleWhen=@(p) coupled(p) && p.collision_on, ...
                    Description="Distance between the mass centres at equilibrium.")
                P("coll_gap", Label="Mass–mass contact gap", Units="m", Default=0.4, Min=0, Max=big, Group="Collisions", ...
                    VisibleWhen=@(p) coupled(p) && p.collision_on, Description="Centre distance at which the masses touch.")
                % Simulation
                P("t_end", Label="Duration", Units="s", Default=20, Min=1e-6, Max=big, Group="Simulation", MarksCustom=false, ...
                    Description="How long to simulate.")
                P("dt", Label="Output step", Units="s", Default=0.001, Min=1e-6, Max=big, Group="Simulation", ...
                    Description="Spacing of the saved samples. The solver chooses its own steps, no longer than this with a force profile or collisions.")
            ];
        end

        function list = presets(~)
            list = struct("Name", {}, "Values", {});
            list(end+1) = struct("Name", "Forced near resonance", "Values", struct( ...
                "t_end", 8, "dt", 0.01, "x0", 0.5, "forced", true, "F0", 2, "omega_f", 3));
            list(end+1) = struct("Name", "Critically damped", "Values", struct("c", 2*sqrt(10)));
            list(end+1) = struct("Name", "Beating (weak coupling)", "Values", struct("mode", "coupled", ...
                "m1", 1, "m2", 1, "k1", 10, "k2", 0.5, "k3", 10, "c1", 0, "c2", 0, "x1_0", 1, "t_end", 40, "dt", 0.01));
            list(end+1) = struct("Name", "Free impact (collision)", "Values", struct("mode", "coupled", ...
                "t_end", 3, "dt", 0.005, "k1", 0, "k2", 0, "k3", 0, "c1", 0, "c2", 0, ...
                "x1_0", 0, "v1_0", 0.8, "x2_0", 0, "v2_0", -0.4, "collision_on", true, "e_rest", 0.75));
        end

        function result = solve(obj, p)
            p.progressFcn = obj.progressMonitor();
            if p.forceShape == "profile"
                p.force_fn = dlab.core.Schedule.toFunction(p.Fprofile);
            end
            if p.forceShape_c == "profile"
                p.force_fn_c = dlab.core.Schedule.toFunction(p.Fprofile_c);
            end
            result = dlab.sims.massspring.MassSpringPhysics(p);
        end

        function titles = outputTabs(~, p)
            if p.mode == "single"
                titles = ["Kinematics" "Phase portrait" "Energy" "Spring force" "Frequency response"];
            else
                titles = ["Kinematics" "Phase portrait" "Energy" "Relative displacement"];
            end
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            t = theme;
            obj.Ax = struct();
            g = uigridlayout(containers{"Kinematics"}, [3 1], Padding=0, RowSpacing=t.Spacing.xs, ...
                BackgroundColor=t.AxesBackground);
            for k = 1:3
                obj.Ax.("k" + k) = dlab.ui.axesIn(g, t, Row=k);
            end
            obj.Ax.phaseGrid = uigridlayout(containers{"Phase portrait"}, [1 2], Padding=0, ...
                ColumnSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            obj.Ax.ph1 = dlab.ui.axesIn(obj.Ax.phaseGrid, t, Column=1);
            obj.Ax.ph2 = dlab.ui.axesIn(obj.Ax.phaseGrid, t, Column=2);
            obj.Ax.energy = dlab.ui.axesIn(containers{"Energy"}, t, Title="Mechanical energy", ...
                XLabel="Time (s)", YLabel="Energy (J)");
            if isKey(containers, "Spring force")
                obj.Ax.aux = dlab.ui.axesIn(containers{"Spring force"}, t, ...
                    Title="Spring restoring force  F = −k x", XLabel="Time (s)", YLabel="Force (N)");
                g = uigridlayout(containers{"Frequency response"}, [2 1], Padding=0, ...
                    RowSpacing=t.Spacing.xs, BackgroundColor=t.AxesBackground);
                obj.Ax.fr1 = dlab.ui.axesIn(g, t, Row=1, XLabel="r = ω / ωn", YLabel="|X / X_{st}|");
                obj.Ax.fr2 = dlab.ui.axesIn(g, t, Row=2, Title="Phase lag of x behind the force", ...
                    XLabel="r = ω / ωn", YLabel="Phase lag (deg)");
            else
                obj.Ax.aux = dlab.ui.axesIn(containers{"Relative displacement"}, t, ...
                    Title="Relative displacement", XLabel="Time (s)", YLabel="x₁ − x₂ (m)");
            end
        end

        function buildAnimation(obj, parent, theme)
            ax = dlab.ui.axesIn(parent, theme);
            set(ax, XTick=[], YTick=[], Box="off", XGrid="off", YGrid="off", Visible="off");
            ax.Title.Visible = "on";
            disableDefaultInteractivity(ax);
            ax.Toolbar.Visible = "off";
            obj.Anim = struct("axes", ax);
        end

        function showResult(obj, r, params)
            obj.Result = r;
            if r.mode == "single"
                obj.plotSingle(r, params);
                obj.prepareSingleAnimation(r);
            else
                obj.plotCoupled(r);
                obj.prepareCoupledAnimation(r);
            end
            obj.drawFrame(r.t(1));
        end

        function overlayRuns(obj, runs)
            % Kept runs of the same system (single or coupled) as the current one.
            for run = runs(:)'
                r = run.Result;
                if string(r.mode) ~= string(obj.Result.mode)
                    continue
                end
                if r.mode == "single"
                    signals = {r.x, r.v, r.a};
                    for k = 1:3
                        dlab.ui.overlayLine(obj.Ax.("k" + k), r.t, signals{k}, run);
                    end
                    dlab.ui.overlayLine(obj.Ax.ph1, r.x, r.v, run);
                else
                    pairs = {r.x1, r.x2; r.v1, r.v2; r.a1, r.a2};
                    for k = 1:3
                        dlab.ui.overlayLine(obj.Ax.("k" + k), r.t, pairs{k, 1}, run);
                        dlab.ui.overlayLine(obj.Ax.("k" + k), r.t, pairs{k, 2}, run);
                    end
                    dlab.ui.overlayLine(obj.Ax.ph1, r.x1, r.v1, run);
                    dlab.ui.overlayLine(obj.Ax.ph2, r.x2, r.v2, run);
                end
                dlab.ui.overlayLine(obj.Ax.energy, r.t, r.E, run);
            end
            energyHeadroom(obj.Ax.energy);
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Ax))'
                h = obj.Ax.(name);
                if isa(h, "matlab.ui.control.UIAxes")
                    delete(allchild(h));
                    legend(h, "off");
                end
            end
            delete(allchild(obj.Anim.axes));
            title(obj.Anim.axes, "");
        end

        function t = timeVector(~, r)
            t = r.t;
        end

        function drawFrame(obj, simTime)
            r = obj.Result;
            if isempty(r) || ~isfield(obj.Anim, "masses")
                return
            end
            k = dlab.core.frameAt(r.t, simTime);   % after an impact time: the post-impact state
            if r.mode == "single"
                obj.drawSingleFrame(r, k);
            else
                obj.drawCoupledFrame(r, k);
            end
        end

        function T = exportTable(~, r)
            if r.mode == "single"
                T = table(r.t, r.x, r.v, r.a, r.KE, r.PE, r.E, r.F_ext, VariableNames= ...
                    ["time" "position" "velocity" "acceleration" "kinetic_energy" ...
                     "potential_energy" "total_energy" "external_force"]);
                T.Properties.VariableUnits = ["s" "m" "m/s" "m/s²" "J" "J" "J" "N"];
            else
                event = strings(numel(r.t), 1);
                for c = r.coll_log
                    if event(c.post_idx) == ""
                        event(c.post_idx) = c.type_str;
                    else
                        event(c.post_idx) = event(c.post_idx) + "; " + c.type_str;
                    end
                end
                T = table(r.t, r.x1, r.v1, r.a1, r.x2, r.v2, r.a2, r.q1, r.q2, r.center_gap, ...
                    r.KE, r.PE, r.E, event, VariableNames=["time" "x1" "v1" "a1" "x2" "v2" "a2" ...
                    "q1" "q2" "center_gap" "kinetic_energy" "potential_energy" "total_energy" "event"]);
                T.Properties.VariableUnits = ["s" "m" "m/s" "m/s²" "m" "m/s" "m/s²" "m" "m" "m" "J" "J" "J" ""];
            end
        end

        function T = summaryTable(~, r)
            % Numbers at full precision (metrics reads them); Display shows
            % frequencies in both units and labels the counts.
            hz = @(w) sprintf("%.4g  (%.4g Hz)", w, w / (2*pi));
            rows = cell(0, 5);                  % Quantity, Value, Units, Format, Display
            if r.mode == "single"
                rows(end+1, :) = {"Natural frequency ωn", r.omega_n, "rad/s", "", hz(r.omega_n)};
                rows(end+1, :) = {"Damping ratio ζ", r.zeta, "", "%.4g", ""};
                rows(end+1, :) = {"Damping", NaN, "", "", string(r.damp_type)};
                damped = hz(r.omega_d);
                if r.omega_d == 0
                    damped = "0  (no oscillation)";
                end
                rows(end+1, :) = {"Damped frequency ωd", r.omega_d, "rad/s", "", damped};
                if isinf(r.MF_at_f)
                    rows(end+1, :) = {"Magnification at ωf", NaN, "", "", ...
                        "∞  (undamped resonance: the swing grows without limit)"};
                elseif ~isnan(r.MF_at_f)
                    rows(end+1, :) = {"Magnification at ωf", r.MF_at_f, "", "%.4g", ""};
                end
                rows(end+1, :) = {"Peak displacement", max(abs(r.x)), "m", "%.4g", ""};
            else
                rows(end+1, :) = {"First mode ωn₁", r.omega_n1, "rad/s", "", hz(r.omega_n1)};
                rows(end+1, :) = {"Second mode ωn₂", r.omega_n2, "rad/s", "", hz(r.omega_n2)};
                rows(end+1, :) = {"Peak displacement x₁", max(abs(r.x1)), "m", "%.4g", ""};
                rows(end+1, :) = {"Peak displacement x₂", max(abs(r.x2)), "m", "%.4g", ""};
                rows(end+1, :) = {"Collisions", numel(r.coll_log), "", "%d", ""};
                if ~isempty(r.coll_log)
                    types = [r.coll_log.type_id];
                    names = ["m₁ – left wall" "m₂ – right wall" "m₁ – m₂ impact"];
                    for id = 1:3
                        if any(types == id)
                            % A breakdown for reading, not a separate result.
                            rows(end+1, :) = {"  " + names(id), NaN, "", "", string(nnz(types == id))}; %#ok<AGROW>
                        end
                    end
                end
            end
            rows(end+1, :) = {"Final energy", r.E(end), "J", "%.4g", ""};
            rows(end+1, :) = {"Samples", NaN, "", "", string(numel(r.t))};
            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                string(rows(:, 5)), VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
        end

        function params = migrate(obj, params, fromVersion)
            % Version 1 had harmonic forcing only.
            if fromVersion < 2
                defaults = obj.defaultParams();
                for name = ["forceShape" "forceShape_c" "Fprofile" "Fprofile_c"]
                    params.(name) = defaults.(name);
                end
            end
        end

        function lin = linearization(~, p)
            % The input is a force on the (first) mass: the Bode tab
            % shows the response the forcing frequency ωf sweeps through.
            if p.mode == "single"
                G = @(x, u) [x(2); (u - p.c * x(2) - p.k * x(1)) / p.m];
                lin = struct("F", @(x) G(x, 0), "X0", [0; 0], ...
                    "StateNames", ["x" "v"], "Reference", "equilibrium (x = 0), forcing off", ...
                    "Classify", @(lambda, ~) singleModes(lambda), "Scale", [], ...
                    "G", G, "U0", 0, "InputNames", "Force", "InputUnits", "N", ...
                    "OutputUnits", ["m" "m/s"]);
                return
            end
            G = @(x, u) [x(2)
                         (u - p.c1 * x(2) - p.k1 * x(1) - p.k2 * (x(1) - x(3))) / p.m1
                         x(4)
                         (-p.c2 * x(4) - p.k3 * x(3) + p.k2 * (x(1) - x(3))) / p.m2];
            reference = "equilibrium (x₁ = x₂ = 0), forcing off";
            if p.collision_on
                reference = reference + ", contacts ignored";
            end
            lin = struct("F", @(x) G(x, 0), "X0", zeros(4, 1), "StateNames", ["x₁" "v₁" "x₂" "v₂"], ...
                "Reference", reference, "Classify", @coupledModes, "Scale", [], ...
                "G", G, "U0", 0, "InputNames", "Force on mass 1", "InputUnits", "N", ...
                "OutputUnits", ["m" "m/s" "m" "m/s"]);
        end

        function scene = showcase(~)
            scene = struct("Preset", "Beating (weak coupling)", "Tab", "Animation", "Time", 12);
        end

        function description = about(~)
            description = join([
                "Single mass:  m x'' + c x' + k x = F₀ cos(ωf t + φ)."
                ""
                "Coupled masses:  m₁ x₁'' = F(t) − c₁ x₁' − k₁ x₁ − k₂ (x₁ − x₂)"
                "                 m₂ x₂'' = − c₂ x₂' − k₃ x₂ + k₂ (x₁ − x₂)"
                ""
                "x₁ and x₂ are displacements from equilibrium. With collisions on, both walls and " + ...
                "the mass pair are rigid contacts: impacts apply Newton restitution e, and resting " + ...
                "contact is held while the forces push inward."
            ], newline);
        end
    end

    methods (Access = private)
        % ------------------------------------------------------------ plots
        function plotSingle(obj, r, params)
            t = obj.Theme;
            obj.Ax.phaseGrid.ColumnWidth = {"1x", 0};
            obj.Ax.ph2.Visible = "off";
            labels = ["Position  x(t)" "Velocity  v(t)" "Acceleration  a(t)"];
            units = ["Position (m)" "Velocity (m/s)" "Acceleration (m/s²)"];
            data = {r.x, r.v, r.a};
            for k = 1:3
                ax = obj.Ax.("k" + k);
                dlab.ui.clearAxes(ax);
                plot(ax, r.t, data{k}, Color=t.series(k), LineWidth=1.4);
                yline(ax, 0, "--", Color=t.Grid, HandleVisibility="off");
                obj.label(ax, labels(k), "Time (s)", units(k));
            end

            ax = obj.Ax.ph1;
            dlab.ui.clearAxes(ax);
            plot(ax, r.x, r.v, Color=t.series(1), LineWidth=1.2, DisplayName="Trajectory");
            plot(ax, r.x(1), r.v(1), "o", MarkerSize=9, MarkerFaceColor=t.Success, Color=t.Success, DisplayName="Start");
            plot(ax, r.x(end), r.v(end), "s", MarkerSize=9, MarkerFaceColor=t.Danger, Color=t.Danger, DisplayName="End");
            hold(ax, "off");
            obj.label(ax, "Phase portrait", "Position  x (m)", "Velocity  v (m/s)");
            padLimits(ax);
            dlab.ui.legend(ax, t, "Location", "best");

            obj.plotEnergy(r);

            ax = obj.Ax.aux;
            dlab.ui.clearAxes(ax);
            area(ax, r.t, r.Fspring, FaceColor=t.series(1), FaceAlpha=0.25, EdgeColor="none");
            plot(ax, r.t, r.Fspring, Color=t.series(1), LineWidth=1.4);
            yline(ax, 0, "--", Color=t.Grid, HandleVisibility="off");
            hold(ax, "off");

            ax = obj.Ax.fr1;
            dlab.ui.clearAxes(ax);
            plot(ax, r.fr_r, r.fr_MF, Color=t.series(1), LineWidth=1.4);
            xline(ax, 1, "--", "ω_n", Color=t.series(4), LineWidth=1.2);
            top = min(max(r.fr_MF) * 1.15, 12);
            if ~isnan(r.MF_at_f)
                ratio = params.omega_f / r.omega_n;
                if ratio <= r.fr_r(end)
                    % An undamped resonance (infinite) is marked at the top edge.
                    shown = min(r.MF_at_f, top);
                    plot(ax, ratio, shown, "o", MarkerSize=8, MarkerFaceColor=t.series(2), ...
                        Color=t.series(2), Tag="forcing");
                    text(ax, ratio, shown, "  ω_f", Color=t.series(2), FontWeight="bold", ...
                        VerticalAlignment="top");
                end
            end
            hold(ax, "off");
            title(ax, sprintf("Magnification factor   ζ = %.3f", r.zeta));
            ylim(ax, [0 top]);

            ax = obj.Ax.fr2;
            dlab.ui.clearAxes(ax);
            plot(ax, r.fr_r, r.fr_phase, Color=t.series(2), LineWidth=1.4);
            xline(ax, 1, "--", "ω_n", Color=t.series(4), LineWidth=1.2);
            hold(ax, "off");
            ylim(ax, [-5 185]);
        end

        function plotCoupled(obj, r)
            t = obj.Theme;
            obj.Ax.phaseGrid.ColumnWidth = {"1x", "1x"};
            obj.Ax.ph2.Visible = "on";
            pairs = {r.x1, r.x2; r.v1, r.v2; r.a1, r.a2};
            names = ["x₁" "x₂"; "v₁" "v₂"; "a₁" "a₂"];
            labels = ["Position" "Velocity" "Acceleration"];
            units = ["Position (m)" "Velocity (m/s)" "Acceleration (m/s²)"];
            for k = 1:3
                ax = obj.Ax.("k" + k);
                dlab.ui.clearAxes(ax);
                plot(ax, r.t, pairs{k, 1}, Color=t.series(1), LineWidth=1.4, DisplayName=names(k, 1));
                plot(ax, r.t, pairs{k, 2}, Color=t.series(5), LineWidth=1.4, DisplayName=names(k, 2));
                yline(ax, 0, "--", Color=t.Grid, HandleVisibility="off");
                if k < 3
                    obj.markCollisions(ax, r, pairs{k, 1}, pairs{k, 2});
                end
                hold(ax, "off");
                obj.label(ax, labels(k), "Time (s)", units(k));
                dlab.ui.legend(ax, t, "Location", "best");
            end

            series = {r.x1, r.v1, t.series(1), "Mass 1", "x₁ (m)", "v₁ (m/s)"
                      r.x2, r.v2, t.series(5), "Mass 2", "x₂ (m)", "v₂ (m/s)"};
            for k = 1:2
                ax = obj.Ax.("ph" + k);
                dlab.ui.clearAxes(ax);
                plot(ax, series{k, 1}, series{k, 2}, Color=series{k, 3}, LineWidth=1.2);
                plot(ax, series{k, 1}(1), series{k, 2}(1), "o", MarkerSize=8, ...
                    MarkerFaceColor=t.Success, Color=t.Success);
                hold(ax, "off");
                obj.label(ax, "Phase — " + series{k, 4}, series{k, 5}, series{k, 6});
                padLimits(ax);
            end

            obj.plotEnergy(r);

            ax = obj.Ax.aux;
            dlab.ui.clearAxes(ax);
            area(ax, r.t, r.rel, FaceColor=t.series(2), FaceAlpha=0.25, EdgeColor="none");
            plot(ax, r.t, r.rel, Color=t.series(2), LineWidth=1.4);
            yline(ax, 0, "--", Color=t.Grid, HandleVisibility="off");
            obj.markCollisions(ax, r, r.rel, []);
            hold(ax, "off");
        end

        function plotEnergy(obj, r)
            t = obj.Theme;
            ax = obj.Ax.energy;
            dlab.ui.clearAxes(ax);
            plot(ax, r.t, r.KE, Color=t.series(4), LineWidth=1.4, DisplayName="Kinetic");
            plot(ax, r.t, r.PE, Color=t.series(1), LineWidth=1.4, DisplayName="Potential");
            plot(ax, r.t, r.E, Color=t.series(3), LineWidth=2, DisplayName="Total");
            hold(ax, "off");
            energyHeadroom(ax);
            dlab.ui.legend(ax, t, "Location", "north", "Orientation", "horizontal");
        end

        function markCollisions(obj, ax, r, signal1, signal2)
            %MARKCOLLISIONS Dashed line at each impact, dots on both sides of
            %   the velocity jump.
            colors = obj.collisionColors();
            for c = r.coll_log
                color = colors{min(c.type_id, 3)};
                xline(ax, c.t, "--", Color=[color 0.35], LineWidth=0.9, HandleVisibility="off");
                rows = unique([c.pre_idx, c.post_idx]);
                scatter(ax, r.t(rows), signal1(rows), 28, color, "filled", HandleVisibility="off");
                if ~isempty(signal2)
                    scatter(ax, r.t(rows), signal2(rows), 28, color, "filled", HandleVisibility="off");
                end
            end
        end

        function colors = collisionColors(obj)
            t = obj.Theme;
            colors = {t.series(4), t.series(3), t.series(2)};   % m1–wall, m2–wall, m1–m2
        end

        function label(obj, ax, titleText, xText, yText)
            dlab.ui.styleAxes(ax, obj.Theme);
            title(ax, titleText);
            xlabel(ax, xText);
            ylabel(ax, yText);
        end

        % -------------------------------------------------------- animation
        function prepareSingleAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            delete(allchild(ax));
            g.wallW = 0.06; g.massH = 0.28; g.massW = 0.20;
            span = max(abs(r.x)) * 1.1 + g.massW + 0.3;
            g.xlo = -0.06;
            g.xhi = g.xlo + 2*span + 2*g.massW + 0.6;
            g.anchor = g.xlo + g.wallW;
            g.mid = (g.xlo + g.xhi) / 2;
            g.vScale = 0.18 / max(max(abs(r.v)), eps);
            g.fScale = 0.25 / max(max(abs(r.F_ext)), eps);
            g.showForce = any(r.F_ext ~= 0);
            g.showDamper = ~isfield(r, "damping") || r.damping > 0;
            set(ax, XLim=[g.xlo - 0.05, g.xhi + 0.05], YLim=[-1.1 1.1]);
            obj.Geometry = g;

            hold(ax, "on");
            obj.drawWall(ax, g.xlo, "left", g.wallW);
            line(ax, [g.xlo g.xhi], -g.massH * [1 1], Color=t.Grid, LineWidth=2, Tag="floor");
            a = obj.Anim;
            a.springs = line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.8, Tag="spring");
            a.dampers = line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.4, Tag="damper");
            a.masses = patch(ax, NaN, NaN, t.series(1), EdgeColor=t.Text, LineWidth=1.5, FaceAlpha=0.9, Tag="mass1");
            a.massLabels = text(ax, NaN, 0, "m", HorizontalAlignment="center", FontWeight="bold", ...
                FontSize=t.scaled(11), Color=t.AxesBackground);
            [a.dispLine, a.dispHead, a.dispText] = arrowObjects(ax, t.series(4), t);
            [a.velLine, a.velHead, a.velText] = arrowObjects(ax, t.series(3), t);
            [a.forceLine, a.forceHead, a.forceText] = arrowObjects(ax, t.series(2), t);
            hold(ax, "off");
            obj.Anim = a;
        end

        function drawSingleFrame(obj, r, k)
            g = obj.Geometry;
            a = obj.Anim;
            x = r.x(k);
            xm = g.mid + 0.4 * x;              % displacement drawn at 0.4 scale, as before
            % Spring above the damper, both between the wall and the mass,
            % which rides on the floor.
            [sx, sy] = dlab.sims.massspring.Schematic.spring(g.anchor, obj.SpringY, xm - g.massW, obj.SpringY, obj.Coils);
            set(a.springs, XData=sx, YData=sy);
            [dx, dy] = deal(NaN);
            if g.showDamper
                [dx, dy] = dlab.sims.massspring.Schematic.damper(g.anchor, obj.DamperY, xm - g.massW, obj.DamperY);
            end
            set(a.dampers, XData=dx, YData=dy);
            [bx, by] = dlab.sims.massspring.Schematic.box(xm, 0, g.massW, g.massH);
            set(a.masses, XData=bx, YData=by);
            a.massLabels.Position(1) = xm;

            showArrow(a.dispLine, a.dispHead, a.dispText, abs(x) > 0.01, g.mid, xm, -0.72, ...
                [(g.mid + xm) / 2, -0.58], sprintf("x = %.3f m", x));
            v = r.v(k);
            tip = xm + v * g.vScale;
            showArrow(a.velLine, a.velHead, a.velText, abs(v) > 0.01, xm, tip, g.massH + 0.12, ...
                [(xm + tip) / 2, g.massH + 0.25], sprintf("v = %.2f m/s", v));
            F = r.F_ext(k);
            tip = xm + F * g.fScale;
            showArrow(a.forceLine, a.forceHead, a.forceText, g.showForce && abs(F * g.fScale) > 0.005, ...
                xm, tip, g.massH + 0.44, [(xm + tip) / 2, g.massH + 0.57], sprintf("F = %.2f N", F));
            title(a.axes, sprintf("Single mass-spring-damper    t = %.3f s", r.t(k)));
        end

        function prepareCoupledAnimation(obj, r)
            t = obj.Theme;
            ax = obj.Anim.axes;
            delete(allchild(ax));
            geo = r.geometry;
            % The drawing uses the same physical geometry as collision
            % detection, so drawn blocks touch exactly at contact.
            half = geo.contact_gap / 2;
            if half == 0
                half = 0.015 * geo.eq_sep;
            end
            leftFace = -geo.eq_sep/2 - geo.wall_clearance - half;
            rightFace = geo.eq_sep/2 + geo.wall_clearance + half;
            lo = min([leftFace; min(r.q1 - half); min(r.q2 - half)]);
            hi = max([rightFace; max(r.q1 + half); max(r.q2 + half)]);
            margin = max(0.05 * (hi - lo), eps);
            lo = lo - margin; hi = hi + margin;
            g.map = @(q) 0.04 + 0.92 * (q - lo) / (hi - lo);
            g.xlo = g.map(leftFace);
            g.xhi = g.map(rightFace);
            g.massW = max(0.006, 0.92 * half / (hi - lo));
            g.massH = 0.28;
            g.wallW = 0.025;
            g.springs = true(1, 3);
            g.dampers = true(1, 2);
            if isfield(geo, "springs")
                g.springs = geo.springs;
                g.dampers = geo.dampers;
            end
            set(ax, XLim=[0 1], YLim=[-1.1 1.1]);
            obj.Geometry = g;

            hold(ax, "on");
            obj.drawWall(ax, g.xlo - g.wallW, "left", g.wallW);
            obj.drawWall(ax, g.xhi, "right", g.wallW);
            line(ax, [g.xlo, g.xhi], -g.massH * [1 1], Color=t.Grid, LineWidth=2, Tag="floor");
            a = obj.Anim;
            a.springs = [line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.8, Tag="spring"), ...
                         line(ax, NaN, NaN, Color=t.series(2), LineWidth=1.8, Tag="spring"), ...
                         line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.8, Tag="spring")];
            a.dampers = [line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.4, Tag="damper"), ...
                         line(ax, NaN, NaN, Color=t.TextMuted, LineWidth=1.4, Tag="damper")];
            a.masses = [patch(ax, NaN, NaN, t.series(1), EdgeColor=t.Text, LineWidth=1.5, FaceAlpha=0.9, Tag="mass1"), ...
                        patch(ax, NaN, NaN, t.series(5), EdgeColor=t.Text, LineWidth=1.5, FaceAlpha=0.9, Tag="mass2")];
            a.massLabels = [text(ax, NaN, 0, "m₁", HorizontalAlignment="center", FontWeight="bold", ...
                                 FontSize=t.scaled(10), Color=t.AxesBackground), ...
                            text(ax, NaN, 0, "m₂", HorizontalAlignment="center", FontWeight="bold", ...
                                 FontSize=t.scaled(10), Color=t.AxesBackground)];
            a.positions = [text(ax, NaN, -0.6, "", HorizontalAlignment="center", FontSize=t.scaled(9), FontWeight="bold", Color=t.series(1)), ...
                           text(ax, NaN, -0.6, "", HorizontalAlignment="center", FontSize=t.scaled(9), FontWeight="bold", Color=t.series(5))];
            a.flash = patch(ax, NaN, NaN, t.series(2), EdgeColor=t.series(2), LineWidth=1.2, FaceAlpha=0.25);
            a.flashText = text(ax, NaN, 0.8, "", HorizontalAlignment="center", FontSize=t.scaled(10), FontWeight="bold");
            hold(ax, "off");
            obj.Anim = a;
        end

        function drawCoupledFrame(obj, r, k)
            g = obj.Geometry;
            a = obj.Anim;
            m1 = g.map(r.q1(k));
            m2 = g.map(r.q2(k));
            w = g.massW;
            % Only the springs and dampers that are there (stiffness or
            % damping above zero) are drawn.
            ends = [g.xlo, m1 - w; m1 + w, m2 - w; m2 + w, g.xhi];
            for s = 1:3
                [sx, sy] = deal(NaN);
                if g.springs(s)
                    [sx, sy] = dlab.sims.massspring.Schematic.spring(ends(s, 1), obj.SpringY, ends(s, 2), obj.SpringY, obj.Coils);
                end
                set(a.springs(s), XData=sx, YData=sy);
            end
            ends = [g.xlo, m1 - w; m2 + w, g.xhi];
            for d = 1:2
                [dx, dy] = deal(NaN);
                if g.dampers(d)
                    [dx, dy] = dlab.sims.massspring.Schematic.damper(ends(d, 1), obj.DamperY, ends(d, 2), obj.DamperY);
                end
                set(a.dampers(d), XData=dx, YData=dy);
            end
            centres = [m1 m2];
            values = [r.x1(k) r.x2(k)];
            for m = 1:2
                [bx, by] = dlab.sims.massspring.Schematic.box(centres(m), 0, w, g.massH);
                set(a.masses(m), XData=bx, YData=by);
                a.massLabels(m).Position(1) = centres(m);
                a.positions(m).Position(1) = centres(m);
                a.positions(m).String = sprintf("x%s = %.2f m", char(8320 + m), values(m));
            end

            % Impact burst for FlashSeconds of simulated time after each collision.
            set(a.flash, XData=NaN, YData=NaN);
            a.flashText.String = "";
            colors = obj.collisionColors();
            captions = ["m₁ – wall!" "m₂ – wall!" "Impact!"];
            for c = r.coll_log
                age = r.t(k) - c.t;
                if k >= c.post_idx && age >= 0 && age < obj.FlashSeconds
                    id = min(c.type_id, 3);
                    where = [m1, m2, (m1 + m2) / 2];
                    th = linspace(0, 2*pi, 60);
                    radius = 0.22 + 0.06 * sin(8*th);              % in y units
                    box = getpixelposition(a.axes);                 % keep the burst round
                    squeeze = (diff(a.axes.XLim) / box(3)) / (diff(a.axes.YLim) / box(4));
                    set(a.flash, XData=where(id) + squeeze * radius .* cos(th), YData=radius .* sin(th), ...
                        FaceColor=colors{id}, EdgeColor=colors{id}, FaceAlpha=0.25 * (1 - age / obj.FlashSeconds));
                    set(a.flashText, Position=[where(id) 0.8 0], String=captions(id), Color=colors{id});
                end
            end
            title(a.axes, sprintf("Coupled two-mass system    t = %.3f s", r.t(k)));
        end

        function drawWall(obj, ax, x, side, width)
            t = obj.Theme;
            [px, py, hx, hy] = dlab.sims.massspring.Schematic.wall(x, -1, 2, side, width);
            patch(ax, px, py, t.Border, EdgeColor=t.TextMuted, LineWidth=0.8, FaceAlpha=0.7, Tag="wall");
            line(ax, hx, hy, Color=t.TextMuted, LineWidth=0.8);
        end
    end
end

function energyHeadroom(ax)
% Room above the highest curve (kept runs included) for the one-line
% legend at the top, so the legend hides none of the curves.
lines = findobj(ax, Type="line");
values = [lines.YData];
values = values(isfinite(values));
if isempty(values) || max(values) <= 0
    ylim(ax, "auto");
    return
end
ylim(ax, [min(0, min(values)), 1.18 * max(values)]);
end

function padLimits(ax)
% Leave a margin around a phase portrait, so a path along its edge (a
% constant velocity between impacts) and the start and end markers show.
ax.XLimitMethod = "padded";
ax.YLimitMethod = "padded";
end

function labels = singleModes(lambda)
labels = repmat("Oscillation", numel(lambda), 1);
labels(abs(imag(lambda)) <= 1e-9 * max(1, max(abs(lambda)))) = "Decay";
end

function labels = coupledModes(lambda, V)
%COUPLEDMODES In phase when both masses move the same way in the mode.
labels = strings(numel(lambda), 1);
for k = 1:numel(lambda)
    together = real(V(1, k) * conj(V(3, k))) >= 0;
    if abs(V(1, k)) < 1e-6 * abs(V(3, k)) || abs(V(3, k)) < 1e-6 * abs(V(1, k))
        shape = "one mass";
    elseif together
        shape = "in phase";
    else
        shape = "out of phase";
    end
    if abs(imag(lambda(k))) > 1e-9 * max(1, max(abs(lambda)))
        labels(k) = "Oscillation, " + shape;
    else
        labels(k) = "Decay, " + shape;
    end
end
end

function [shaft, head, label] = arrowObjects(ax, color, t)
shaft = line(ax, NaN, NaN, Color=color, LineWidth=1.8);
head = patch(ax, NaN, NaN, color, EdgeColor=color);
label = text(ax, NaN, NaN, "", HorizontalAlignment="center", FontSize=t.scaled(9), FontWeight="bold", Color=color);
end

function showArrow(shaft, head, label, visible, x1, x2, y, at, caption)
if ~visible
    set([shaft head], XData=NaN, YData=NaN);
    label.String = "";
    return
end
[lx, ly, hx, hy] = dlab.sims.massspring.Schematic.arrow(x1, x2, y);
set(shaft, XData=lx, YData=ly);
set(head, XData=hx, YData=hy);
set(label, Position=[at 0], String=caption);
end
