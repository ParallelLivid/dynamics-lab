classdef FrequencyPanel < handle
    %FREQUENCYPANEL The "Bode" tab: the Bode response of the model
    %   linearized with inputs (Plugin.linearization with G and U0), from
    %   a chosen input to a chosen output, with its bandwidth; and, when
    %   the linearization names a control loop to break (Loop), the loop
    %   gain with its gain and phase margins.
    %
    %   Input [Voltage ▾]  Output [Speed ▾]                     Frequency in [rad/s ▾]
    %   DC gain 2.1 · bandwidth 5.1 rad/s
    %   ┌ magnitude (dB) against frequency (log) ──────────────────────┐
    %   ┌ phase (deg) against frequency (log) ─────────────────────────┐

    properties (SetAccess = private)
        Grid
        PlotGrid               % the two axes (what Export plot saves)
        InputDropdown
        OutputDropdown
        UnitsDropdown
        NoteLabel
        MagnitudeAxes
        PhaseAxes
        Model = []             % dlab.core.FrequencyResponse.model output
        LoopModel = []         % dlab.core.FrequencyResponse.loop output ([] without a Loop)
        Response = []          % dlab.core.FrequencyResponse.response output
        Markers = struct("Frequency", {}, "Label", {})   % from the linearization (rad/s)
    end

    properties (Constant)
        LoopKey = "Loop"       % the input dropdown's key for the loop gain
        LoopOutput = "Loop gain"
    end

    properties (Access = private)
        Theme
        UnitsChosen (1,1) logical = false   % the user picked the units; keep them
    end

    methods
        function obj = FrequencyPanel(parent, theme)
            t = theme;
            obj.Theme = t;
            obj.Grid = uigridlayout(parent, [3 1], RowHeight={30, "fit", "1x"}, Padding=0, ...
                RowSpacing=t.Spacing.sm, BackgroundColor=t.AxesBackground);
            bar = uigridlayout(obj.Grid, [1 7], ColumnWidth={"fit", 220, "fit", 200, "1x", "fit", 80}, ...
                RowHeight={26}, Padding=[t.Spacing.sm 2 t.Spacing.sm 2], ColumnSpacing=t.Spacing.sm, ...
                BackgroundColor=t.Surface);
            dlab.ui.label(bar, "Input", t, Role="muted");
            obj.InputDropdown = uidropdown(bar, Items={'–'}, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.frequency.input", Enable="off", ...
                ValueChangedFcn=@(~, ~) obj.redraw());
            dlab.ui.label(bar, "Output", t, Role="muted");
            obj.OutputDropdown = uidropdown(bar, Items={'–'}, BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.frequency.output", Enable="off", ...
                ValueChangedFcn=@(~, ~) obj.redraw());
            uilabel(bar, Text="");
            dlab.ui.label(bar, "Frequency in", t, Role="muted");
            obj.UnitsDropdown = uidropdown(bar, Items=["rad/s" "Hz"], BackgroundColor=t.SurfaceRaised, ...
                FontColor=t.Text, Tag="dlab.frequency.units", ValueChangedFcn=@(~, ~) obj.chooseUnits());
            obj.NoteLabel = dlab.ui.label(obj.Grid, "Run the simulation to see its frequency response.", t, ...
                Role="muted", WordWrap="on", Tag="dlab.frequency.note");
            obj.PlotGrid = uigridlayout(obj.Grid, [2 1], Padding=0, RowSpacing=t.Spacing.sm, ...
                BackgroundColor=t.AxesBackground);
            obj.MagnitudeAxes = dlab.ui.axesIn(obj.PlotGrid, t, Title="Magnitude", YLabel="Gain (dB)", Row=1);
            obj.MagnitudeAxes.Tag = "dlab.frequency.magnitude";
            obj.PhaseAxes = dlab.ui.axesIn(obj.PlotGrid, t, Title="Phase", XLabel="Frequency ω (rad/s)", ...
                YLabel="Phase (deg)", Row=2);
            obj.PhaseAxes.Tag = "dlab.frequency.phase";
            set([obj.MagnitudeAxes obj.PhaseAxes], XScale="log");
        end

        function show(obj, lin)
            %SHOW The response of LIN (a Plugin.linearization struct); [] or
            %   a linearization without inputs clears the tab with a note.
            if isempty(lin)
                obj.clear("This configuration has no linearization, so no frequency response.");
                return
            end
            if ~dlab.core.FrequencyResponse.available(lin)
                obj.clear("This configuration's model has no inputs to drive.");
                return
            end
            S = dlab.core.FrequencyResponse.model(lin);
            obj.Model = S;
            obj.LoopModel = [];
            names = S.InputNames;
            units = S.InputUnits;
            labels = strings(1, 0);
            if dlab.core.FrequencyResponse.hasLoop(lin)
                obj.LoopModel = dlab.core.FrequencyResponse.loop(lin);
                names(end+1) = obj.LoopKey;
                units(end+1) = "";
                labels = "Loop gain at " + obj.LoopModel.InputNames;
            end
            keepChoice(obj.InputDropdown, names, units, labels);
            obj.Markers = struct("Frequency", {}, "Label", {});
            if isfield(lin, "Markers") && ~isempty(lin.Markers)
                obj.Markers = lin.Markers;
            end
            if ~obj.UnitsChosen
                obj.UnitsDropdown.Value = "rad/s";
                if isfield(lin, "FrequencyUnits") && string(lin.FrequencyUnits) == "Hz"
                    obj.UnitsDropdown.Value = "Hz";
                end
            end
            obj.redraw();
        end

        function select(obj, input, output)
            %SELECT Show the response from INPUT to OUTPUT (names; the input
            %   "Loop" with the output "Loop gain" for the loop gain).
            if ~ismember(string(input), string(obj.InputDropdown.ItemsData))
                error("dlab:frequency:unknown", "The Bode tab has no %s → %s response.", input, output);
            end
            obj.InputDropdown.Value = char(input);
            obj.offerOutputs();
            if ~ismember(string(output), string(obj.OutputDropdown.ItemsData))
                error("dlab:frequency:unknown", "The Bode tab has no %s → %s response.", input, output);
            end
            obj.OutputDropdown.Value = char(output);
            obj.redraw();
        end

        function clear(obj, note)
            arguments
                obj
                note (1,1) string = "Run the simulation to see its frequency response."
            end
            obj.Model = [];
            obj.LoopModel = [];
            obj.Response = [];
            set([obj.InputDropdown obj.OutputDropdown], Items={'–'}, ItemsData={}, Enable="off");
            delete(allchild(obj.MagnitudeAxes));
            delete(allchild(obj.PhaseAxes));
            obj.NoteLabel.Text = note;
            obj.NoteLabel.FontColor = obj.Theme.TextMuted;
        end
    end

    methods (Access = private)
        function offerOutputs(obj)
            % The outputs of the model, or the single loop gain.
            if string(obj.InputDropdown.Value) == obj.LoopKey
                keepChoice(obj.OutputDropdown, obj.LoopOutput, "");
            else
                keepChoice(obj.OutputDropdown, obj.Model.OutputNames, obj.Model.OutputUnits);
            end
        end

        function chooseUnits(obj)
            obj.UnitsChosen = true;
            obj.redraw();
        end

        function redraw(obj)
            if isempty(obj.Model)
                return
            end
            obj.offerOutputs();
            isLoop = string(obj.InputDropdown.Value) == obj.LoopKey;
            if isLoop
                R = dlab.core.FrequencyResponse.response(obj.LoopModel, 1, 1);
                R.Input = obj.LoopKey;
                R.Output = obj.LoopOutput;
            else
                R = dlab.core.FrequencyResponse.response(obj.Model, obj.InputDropdown.Value, ...
                    obj.OutputDropdown.Value);
            end
            obj.Response = R;
            hertz = string(obj.UnitsDropdown.Value) == "Hz";
            scale = 1;
            unit = "rad/s";
            if hertz
                scale = 1 / (2 * pi);
                unit = "Hz";
            end
            obj.NoteLabel.Text = describe(R, isLoop, scale, unit);
            obj.NoteLabel.FontColor = obj.Theme.TextMuted;

            t = obj.Theme;
            mag = obj.MagnitudeAxes;
            ph = obj.PhaseAxes;
            delete(allchild(mag));
            delete(allchild(ph));
            f = R.Omega * scale;
            semilogx(mag, f, R.Decibels, Color=t.Series(1, :), LineWidth=1.5);
            semilogx(ph, f, R.Phase, Color=t.Series(1, :), LineWidth=1.5);
            if isLoop
                yline(mag, 0, ":", Color=t.TextMuted, HandleVisibility="off");
                yline(ph, -180, ":", Color=t.TextMuted, HandleVisibility="off");
                for ax = [mag ph]
                    if isfinite(R.GainCrossover)
                        xline(ax, R.GainCrossover * scale, "--", Color=t.Series(2, :), HandleVisibility="off");
                    end
                    if isfinite(R.PhaseCrossover)
                        xline(ax, R.PhaseCrossover * scale, "--", Color=t.Series(4, :), HandleVisibility="off");
                    end
                end
            else
                if isfinite(R.Bandwidth)
                    xline(mag, R.Bandwidth * scale, "--", "bandwidth", Color=t.Series(2, :), ...
                        LabelVerticalAlignment="bottom");
                end
                if isfinite(R.PeakFrequency) && R.PeakGain > abs(R.Response(1)) * 1.05
                    xline(mag, R.PeakFrequency * scale, ":", "resonance", Color=t.Series(3, :), ...
                        LabelVerticalAlignment="bottom");
                end
            end
            for k = 1:numel(obj.Markers)
                w = obj.Markers(k).Frequency;
                if w > R.Omega(1) && w < R.Omega(end)
                    xline(mag, w * scale, "-.", obj.Markers(k).Label, Color=t.TextMuted, ...
                        LabelOrientation="horizontal", FontSize=t.FontSize.sm, HandleVisibility="off");
                    xline(ph, w * scale, "-.", Color=t.TextMuted, HandleVisibility="off");
                end
            end
            if isLoop
                title(mag, "Loop gain, the loop broken at " + obj.LoopModel.InputNames);
            else
                title(mag, R.Input + " → " + R.Output);
            end
            xlabel(ph, "Frequency (" + unit + ")");
            set([mag ph], XScale="log", XLim=f([1 end])');
        end
    end
end

function keepChoice(dropdown, names, units, labels)
% Offer NAMES (labelled with their units, or LABELS for the last ones),
% keeping the current choice when it is still offered.
arguments
    dropdown
    names (1,:) string
    units (1,:) string
    labels (1,:) string = strings(1, 0)
end
previous = string(dropdown.Value);
items = names;
items(units ~= "") = names(units ~= "") + " (" + units(units ~= "") + ")";
items(end - numel(labels) + 1:end) = labels;
set(dropdown, Items=cellstr(items), ItemsData=cellstr(names), Enable="on");
if any(names == previous)
    dropdown.Value = char(previous);
end
end

function text = describe(R, isLoop, scale, unit)
% The response's key numbers, frequencies in UNIT (rad/s times SCALE).
f = @(w) sprintf("%.4g %s", w * scale, unit);
parts = strings(0);
if isLoop
    if isfinite(R.PhaseMargin)
        parts(end+1) = sprintf("phase margin %.3g°", R.PhaseMargin) + " at " + f(R.GainCrossover);
    else
        parts(end+1) = "the loop gain never crosses 0 dB (no phase margin)";
    end
    if isfinite(R.GainMargin) && R.GainMargin < 0
        parts(end+1) = sprintf("gain margin %.3g dB", R.GainMargin) + " at " + f(R.PhaseCrossover) + ...
            sprintf(" (the gain may fall by %.3g dB, not rise)", -R.GainMargin);
    elseif isfinite(R.GainMargin)
        parts(end+1) = sprintf("gain margin %.3g dB", R.GainMargin) + " at " + f(R.PhaseCrossover);
    else
        parts(end+1) = "the phase never reaches −180° (gain margin unlimited)";
    end
    text = strjoin(parts, " · ") + ".  Loop gain L = −(signal returned)/(signal injected).";
    return
end
if isinf(R.DCGain)
    parts(end+1) = "DC gain ∞ (the output integrates the input)";
else
    parts(end+1) = sprintf("DC gain %.4g", R.DCGain);
end
if isfinite(R.PeakFrequency)
    parts(end+1) = sprintf("resonance %.4g", R.PeakGain) + " at " + f(R.PeakFrequency);
end
if isfinite(R.Bandwidth)
    parts(end+1) = "bandwidth " + f(R.Bandwidth);
end
text = strjoin(parts, " · ") + ".";
end
