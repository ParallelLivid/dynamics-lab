classdef ToyOscillatorPlugin < dlab.core.TimeDomainPlugin
    %TOYOSCILLATORPLUGIN Minimal plugin that exercises the framework.
    %   A damped harmonic oscillator with an analytic solution. It uses
    %   every parameter type, a VisibleWhen rule, an Advanced group, a
    %   MarksCustom=false parameter, presets, a coupled-parameter hook,
    %   a summary table, progress reporting, and an animation. Tests only;
    %   not registered.

    properties (Constant)
        Id = "toy"
        Title = "Toy Oscillator"
        Category = "Test"
        Summary = "Damped harmonic oscillator used to test the framework."
        SchemaVersion = 2
    end

    properties (SetAccess = private)
        Axes                      % struct of uiaxes handles
        Lines                     % struct of line handles
        Result
        SolveCount (1,1) double = 0
    end

    properties
        OnProgress = []           % tests: called with each progress fraction
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            specs = [
                P("omega", Label="Natural frequency", Units="rad/s", Default=2*pi, ...
                    Min=0, MinInclusive=false, Max=100, Group="Oscillator", ...
                    Description="Undamped angular frequency.")
                P("zeta", Label="Damping ratio", Default=0.1, Min=0, Max=1, ...
                    MaxInclusive=false, Group="Oscillator", ...
                    Description="Damping as a fraction of critical.")
                P("x0", Label="Initial displacement", Units="m", Default=1, Group="Initial conditions", ...
                    Description="Displacement at the start.")
                P("drive", Label="Excitation", Type="choice", Default="free", ...
                    Choices=["free" "forced"], ChoiceLabels=["Free" "Forced"], Group="Initial conditions", ...
                    Description="Free: no force. Forced: a harmonic force.")
                P("F", Label="Force amplitude", Units="m", Default=0.5, Min=0, ...
                    Group="Initial conditions", VisibleWhen=@(p) p.drive == "forced", ...
                    Description="Amplitude of the harmonic force.")
                P("cycles", Label="Envelope cycles", Type="integer", Default=3, Min=1, Max=20, ...
                    Group="Initial conditions", ...
                    Description="How many cycles the envelope plot covers.")
                P("showEnvelope", Label="Show envelope", Type="logical", Default=true, Group="Display", ...
                    Display=true, ...
                    Description="Draw the decay envelope.")
                P("duration", Label="Duration", Units="s", Default=5, Min=0, MinInclusive=false, ...
                    Max=1000, Group="Simulation", Advanced=true, MarksCustom=false, ...
                    Description="How long to simulate.")
                P("dt", Label="Output step", Units="s", Default=0.01, Min=0, MinInclusive=false, ...
                    Group="Simulation", Advanced=true, ...
                    Description="Spacing of the saved samples.")
            ];
        end

        function list = presets(~)
            list = struct( ...
                "Name", {"Light damping", "Heavy damping"}, ...
                "Values", {struct("zeta", 0.05), struct("zeta", 0.7, "x0", 2)});
        end

        function params = onParamChanged(~, name, params)
            % Coupled-parameter example: forcing defaults to a finer step.
            if name == "drive" && params.drive == "forced"
                params.dt = min(params.dt, 0.005);
            end
        end

        function result = solve(obj, p)
            if p.dt >= p.duration
                error("dlab:invalidParameter", "Output step must be smaller than the duration.");
            end
            obj.SolveCount = obj.SolveCount + 1;
            for fraction = [0.25 0.5 0.75 1]
                if ~isempty(obj.OnProgress)
                    obj.OnProgress(fraction);
                end
                if obj.progress(fraction)
                    error("dlab:toy:stopped", "Stopped early.");
                end
            end
            t = (0:p.dt:p.duration)';
            if t(end) < p.duration
                t(end+1) = p.duration;
            end
            wd = p.omega * sqrt(1 - p.zeta^2);
            envelope = p.x0 * exp(-p.zeta * p.omega * t);
            x = envelope .* cos(wd * t);
            if p.drive == "forced"
                x = x + p.F * sin(p.omega * t);
            end
            v = gradient(x, t);
            result = struct("t", t, "x", x, "v", v, "envelope", envelope);
        end

        function titles = outputTabs(~, ~)
            titles = ["Displacement" "Phase"];
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            obj.Axes.x = dlab.ui.axesIn(containers{"Displacement"}, theme, ...
                Title="Displacement", XLabel="Time (s)", YLabel="x (m)");
            obj.Lines.x = line(obj.Axes.x, NaN, NaN, Color=theme.series(1), LineWidth=1.5);
            obj.Lines.envelope = line(obj.Axes.x, NaN, NaN, Color=theme.series(2), LineStyle="--");
            obj.Axes.phase = dlab.ui.axesIn(containers{"Phase"}, theme, ...
                Title="Phase portrait", XLabel="x (m)", YLabel="v (m/s)");
            obj.Lines.phase = line(obj.Axes.phase, NaN, NaN, Color=theme.series(3), LineWidth=1.5);
        end

        function showResult(obj, result, params)
            obj.Result = result;
            set(obj.Lines.x, XData=result.t, YData=result.x);
            if params.showEnvelope
                set(obj.Lines.envelope, XData=result.t, YData=result.envelope);
            else
                set(obj.Lines.envelope, XData=NaN, YData=NaN);
            end
            set(obj.Lines.phase, XData=result.x, YData=result.v);
            if isfield(obj.Lines, "trail")
                span = max(abs(result.x)) * 1.1 + eps;
                xlim(obj.Axes.anim, [-span span]);
            end
        end

        function overlayRuns(obj, runs)
            for run = runs(:)'
                dlab.ui.overlayLine(obj.Axes.x, run.Result.t, run.Result.x, run);
            end
        end

        function clearResult(obj)
            obj.Result = [];
            for name = string(fieldnames(obj.Lines))'
                set(obj.Lines.(name), XData=NaN, YData=NaN);
            end
        end

        function T = exportTable(~, result)
            T = table(result.t, result.x, result.v, VariableNames=["t" "x" "v"]);
            T.Properties.VariableUnits = ["s" "m" "m/s"];
        end

        function T = summaryTable(~, result)
            T = table(["Peak displacement"; "Final displacement"], ...
                [max(abs(result.x)); result.x(end)], ["m"; "m"], ...
                VariableNames=["Quantity" "Value" "Units"]);
        end

        function D = distributions(~, result)
            % Every local maximum of x: one value per peak (set-valued).
            x = result.x;
            peaks = x([false; x(2:end-1) > x(1:end-2) & x(2:end-1) >= x(3:end); false]);
            D = table("Peaks", {peaks}, "m", VariableNames=["Quantity" "Values" "Units"]);
        end

        function t = timeVector(~, result)
            t = result.t;
        end

        function buildAnimation(obj, parent, theme)
            obj.Axes.anim = dlab.ui.axesIn(parent, theme, Title="Mass", XLabel="x (m)");
            ylim(obj.Axes.anim, [-1 1]);
            obj.Lines.trail = line(obj.Axes.anim, NaN, NaN, Color=theme.series(1));
            obj.Lines.mass = line(obj.Axes.anim, NaN, NaN, Marker="o", MarkerSize=14, ...
                MarkerFaceColor=theme.Accent, Color=theme.Accent);
        end

        function drawFrame(obj, simTime)
            if isempty(obj.Result)
                return
            end
            k = dlab.core.frameAt(obj.Result.t, simTime);
            set(obj.Lines.mass, XData=obj.Result.x(k), YData=0);
            set(obj.Lines.trail, XData=[0 obj.Result.x(k)], YData=[0 0]);
        end

        function lin = linearization(~, p)
            w = p.omega;
            z = p.zeta;
            lin = struct("F", @(x) [x(2); -w^2 * x(1) - 2 * z * w * x(2)], "X0", [0; 0], ...
                "StateNames", ["x" "v"], "Reference", "rest (x = 0)");
        end

        function params = migrate(~, params, fromVersion)
            % Schema 1 called the damping ratio "damping".
            if fromVersion < 2 && isfield(params, "damping")
                params.zeta = params.damping;
                params = rmfield(params, "damping");
            end
        end
    end
end
