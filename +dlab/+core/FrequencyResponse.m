classdef FrequencyResponse
    %FREQUENCYRESPONSE Bode response of a linearized model, input to output (the Bode tab).
    %   A plugin's linearization (see dlab.core.Plugin.linearization) gives
    %   the inputs with three optional fields: G, @(x, u) the state
    %   derivative with inputs u; U0, the nominal inputs; InputNames. And,
    %   optionally, H, @(x, u) the outputs, with OutputNames (the outputs
    %   are the states when H is absent). F(x) must equal G(x, U0).
    %   InputUnits and OutputUnits (string rows) are optional labels;
    %   Markers (struct array: Frequency in rad/s, Label) marks frequencies
    %   on the plot, and FrequencyUnits ("rad/s" or "Hz") sets its axis.
    %
    %   A control loop can be broken for its margins with the field Loop:
    %   a struct with G (@(x, u) the state derivative with the loop opened
    %   and a signal u injected where Name enters), X0, U0 (scalar), H
    %   (@(x, u) the signal that comes back to that point), Name, and
    %   optionally Scale. The loop gain is L = −H/u (negative feedback); its
    %   phase is taken on the branch where it starts between −315° and 45°
    %   (0°, −90°, −180°, or −270° for zero to three integrators), so a
    %   phase just below −180° is not read as +180° (a margin 360° off):
    %       SL = dlab.core.FrequencyResponse.loop(lin);
    %       R = dlab.core.FrequencyResponse.response(SL, 1, 1);  % R.PhaseMargin …
    %
    %       lin = plugin.linearization(params);
    %       S = dlab.core.FrequencyResponse.model(lin);   % A, B, C, D
    %       R = dlab.core.FrequencyResponse.response(S, input, output);
    %
    %   R: Omega (rad/s), Magnitude (|H|), Decibels, Phase (deg, unwrapped),
    %   DCGain, PeakGain, PeakFrequency (a resonance; NaN when the gain
    %   only falls), Bandwidth (rad/s, where the gain first falls 3 dB below
    %   its low-frequency value; NaN if it never does or the output
    %   integrates the input), and the margins read as if the response were the open loop
    %   of a unity-feedback system: GainCrossover and PhaseMargin (deg, at
    %   |H| = 1), PhaseCrossover and GainMargin (dB, at phase −180°, rising
    %   or falling; of several, the one nearest 0 dB). A negative gain
    %   margin is how far the gain may fall, as for a loop around an
    %   unstable plant.

    methods (Static)
        function tf = available(lin)
            %AVAILABLE True when LIN has inputs for a frequency response.
            tf = isstruct(lin) && isfield(lin, "G") && ~isempty(lin.G) && isfield(lin, "U0");
        end

        function tf = hasLoop(lin)
            %HASLOOP True when LIN names a control loop to break (Loop).
            tf = isstruct(lin) && isfield(lin, "Loop") && isstruct(lin.Loop) && ~isempty(lin.Loop);
        end

        function S = loop(lin)
            %LOOP The loop gain of LIN's Loop as a one-input, one-output
            %   model (A, B, C, D): its response is L(s) = −H(s)/u(s).
            l = lin.Loop;
            x0 = l.X0(:);
            u0 = l.U0;
            scale = ones(size(x0));
            if isfield(l, "Scale") && ~isempty(l.Scale)
                scale = l.Scale(:);
            end
            S.A = dlab.physics.jacobian(@(x) l.G(x, u0), x0, Scale=scale);
            S.B = dlab.physics.jacobian(@(u) l.G(x0, u), u0);
            S.C = -dlab.physics.jacobian(@(x) l.H(x, u0), x0, Scale=scale);
            S.D = -dlab.physics.jacobian(@(u) l.H(x0, u), u0);
            S.InputNames = string(l.Name);
            S.OutputNames = "Loop gain";
            S.InputUnits = "";
            S.OutputUnits = "";
            S.IsLoop = true;
        end

        function S = model(lin)
            %MODEL The state-space matrices A, B, C, D of LIN by central
            %   differences at (X0, U0), with InputNames and OutputNames.
            arguments
                lin (1,1) struct
            end
            assert(dlab.core.FrequencyResponse.available(lin), "dlab:frequency:noInputs", ...
                "This linearization has no inputs (G and U0).");
            x0 = lin.X0(:);
            u0 = lin.U0(:);
            scale = ones(size(x0));
            if isfield(lin, "Scale") && ~isempty(lin.Scale)
                scale = lin.Scale(:);
            end
            S.A = dlab.physics.jacobian(@(x) lin.G(x, u0), x0, Scale=scale);
            S.B = dlab.physics.jacobian(@(u) lin.G(x0, u), u0);
            if isfield(lin, "H") && ~isempty(lin.H)
                S.C = dlab.physics.jacobian(@(x) lin.H(x, u0), x0, Scale=scale);
                S.D = dlab.physics.jacobian(@(u) lin.H(x0, u), u0);
                S.OutputNames = string(lin.OutputNames);
            else
                n = numel(x0);
                S.C = eye(n);
                S.D = zeros(n, numel(u0));
                S.OutputNames = string(lin.StateNames);
            end
            S.InputNames = string(lin.InputNames);
            S.InputUnits = unitsOf(lin, "InputUnits", numel(S.InputNames));
            S.OutputUnits = unitsOf(lin, "OutputUnits", numel(S.OutputNames));
            assert(numel(S.InputNames) == size(S.B, 2), "dlab:frequency:names", ...
                "InputNames must name each of the %d inputs.", size(S.B, 2));
            assert(numel(S.OutputNames) == size(S.C, 1), "dlab:frequency:names", ...
                "OutputNames must name each of the %d outputs.", size(S.C, 1));
        end

        function R = response(S, input, output, omega)
            %RESPONSE The response from input INPUT to output OUTPUT
            %   (indices or names) at the frequencies OMEGA (rad/s; chosen
            %   from the eigenvalues when omitted).
            arguments
                S (1,1) struct
                input
                output
                omega (:,1) double = dlab.core.FrequencyResponse.grid(S.A)
            end
            i = indexOf(input, S.InputNames);
            o = indexOf(output, S.OutputNames);
            n = size(S.A, 1);
            H = zeros(numel(omega), 1);
            b = S.B(:, i);
            c = S.C(o, :);
            for k = 1:numel(omega)
                H(k) = c * ((1i * omega(k) * eye(n) - S.A) \ b) + S.D(o, i);
            end
            R.Omega = omega;
            R.Response = H;
            R.Magnitude = abs(H);
            R.Decibels = 20 * log10(max(abs(H), realmin));
            R.Phase = rad2deg(unwrap(angle(H)));
            if isfield(S, "IsLoop") && S.IsLoop && ~isempty(omega)
                R.Phase = R.Phase - 360 * ceil((R.Phase(1) - 45) / 360);
            end
            R.Input = S.InputNames(i);
            R.Output = S.OutputNames(o);
            R.DCGain = dcGain(S, i, o);
            [R.PeakGain, k] = max(R.Magnitude);
            if abs(R.DCGain) < 1e-9 * R.PeakGain
                R.DCGain = 0;                   % rounding left by the finite differences
            end
            R.PeakFrequency = NaN;              % a resonance: a peak above the low-frequency gain
            if k > 1 && k < numel(omega)
                % Between the grid's neighbours, by golden section on log ω.
                gain = @(w) abs(c * ((1i * w * eye(n) - S.A) \ b) + S.D(o, i));
                [R.PeakFrequency, R.PeakGain] = refinePeak(gain, omega(k - 1), omega(k + 1), omega(k), R.PeakGain);
            end
            R.Bandwidth = NaN;                  % an integrating output has no bandwidth
            if isfinite(R.DCGain)
                R.Bandwidth = crossing(omega, R.Decibels - (R.Decibels(1) - 3));
            end
            % Margins, as an open loop: the phase at |H| = 1 and the gain at −180°.
            R.GainCrossover = crossing(omega, R.Decibels);
            R.PhaseMargin = NaN;
            if isfinite(R.GainCrossover)
                R.PhaseMargin = 180 + interp1(omega, R.Phase, R.GainCrossover);
            end
            % The phase may cross −180° rising as well as falling (a loop
            % around an unstable plant starts below −180°): the margin is
            % the crossing nearest 0 dB, negative when the gain may only fall.
            R.PhaseCrossover = NaN;
            R.GainMargin = NaN;
            for w = crossings(omega, R.Phase + 180)'
                margin = -interp1(omega, R.Decibels, w);
                if ~(abs(margin) >= abs(R.GainMargin))
                    [R.PhaseCrossover, R.GainMargin] = deal(w, margin);
                end
            end
        end

        function omega = grid(A, count)
            %GRID Log-spaced frequencies two decades either side of the
            %   model's eigenvalues (rad/s).
            arguments
                A double
                count (1,1) double = 600
            end
            lambda = abs(eig(A));
            lambda = lambda(lambda > 1e-9);
            if isempty(lambda)
                lambda = 1;
            end
            omega = logspace(log10(min(lambda)) - 2, log10(max(lambda)) + 2, count)';
        end
    end
end

function [w, g] = refinePeak(gain, lo, hi, w, g)
% The largest GAIN(ω) between LO and HI (rad/s), starting from the grid's
% best point W with gain G; 40 golden-section steps narrow it by 10⁻⁸.
r = (sqrt(5) - 1) / 2;
[a, z] = deal(log(lo), log(hi));
x1 = z - r * (z - a);
x2 = a + r * (z - a);
[g1, g2] = deal(gain(exp(x1)), gain(exp(x2)));
for step = 1:40
    if g1 > g2
        [z, x2, g2] = deal(x2, x1, g1);
        x1 = z - r * (z - a);
        g1 = gain(exp(x1));
    else
        [a, x1, g1] = deal(x1, x2, g2);
        x2 = a + r * (z - a);
        g2 = gain(exp(x2));
    end
end
if g1 >= g2 && g1 > g
    [w, g] = deal(exp(x1), g1);
elseif g2 > g
    [w, g] = deal(exp(x2), g2);
end
end

function i = indexOf(value, names)
if isnumeric(value)
    i = value;
else
    i = find(names == string(value), 1);
    assert(~isempty(i), "dlab:frequency:unknown", "No input or output named ""%s"".", value);
end
end

function units = unitsOf(lin, field, n)
% Optional units, one per input or output ("" when not given).
units = strings(1, n);
if isfield(lin, field) && ~isempty(lin.(field))
    units = string(lin.(field));
    assert(numel(units) == n, "dlab:frequency:names", "%s must give one unit per name.", field);
end
end

function g = dcGain(S, i, o)
% The steady response to a constant input: Inf when this output integrates
% it. A pole at zero elsewhere in the model (say, a motor's angle when the
% output is its speed) leaves the gain finite, so with a singular A the
% response is read at two very low frequencies instead.
if rcond(S.A) >= 1e-12
    g = S.D(o, i) - S.C(o, :) * (S.A \ S.B(:, i));
    return
end
lambda = abs(eig(S.A));
lambda = lambda(lambda > 1e-9);
w = 1e-6;
if ~isempty(lambda)
    w = 1e-6 * min(lambda);
end
n = size(S.A, 1);
H = @(w) S.C(o, :) * ((1i * w * eye(n) - S.A) \ S.B(:, i)) + S.D(o, i);
% Solving this close to a pole at zero is ill-conditioned on purpose.
quiet = warning("off", "MATLAB:nearlySingularMatrix");
restore = onCleanup(@() warning(quiet));
low = H(w / 10);
if abs(low) > 3 * abs(H(w))
    g = Inf;
else
    g = real(low);
end
end

function x = crossings(omega, values)
% Every frequency where VALUES passes through zero, either way
% (interpolated in log ω).
k = find(sign(values(1:end-1)) .* sign(values(2:end)) < 0 | (values(1:end-1) == 0 & values(2:end) ~= 0));
f = values(k) ./ (values(k) - values(k + 1));
x = exp(log(omega(k)) + f .* (log(omega(k + 1)) - log(omega(k))));
x = x(:);
end

function x = crossing(omega, values)
% The first frequency where VALUES falls through zero (interpolated in log ω).
x = NaN;
k = find(values(1:end-1) >= 0 & values(2:end) < 0, 1);
if isempty(k)
    return
end
f = values(k) / (values(k) - values(k + 1));
x = exp(log(omega(k)) + f * (log(omega(k + 1)) - log(omega(k))));
end
