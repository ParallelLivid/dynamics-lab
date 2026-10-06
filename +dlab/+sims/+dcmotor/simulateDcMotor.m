function result = simulateDcMotor(p)
%SIMULATEDCMOTOR A permanent-magnet DC motor in open loop or under PID control.
%   result = simulateDcMotor(p) integrates the armature and the rotor
%   (see dlab.sims.dcmotor.dynamics; K is both the back-EMF and the torque
%   constant, equal in SI units):
%
%     L di/dt = V − R i − K ω,   J dω/dt = K i − b ω − τ_load,   dθ/dt = ω
%
%   with the voltage V chosen by p.mode:
%
%     'open'      V = command(t)
%     'speed'     V = Kp e + Ki ∫e dt,           e = ω_ref − ω  (P or PI)
%     'position'  V = Kp e + Ki ∫e dt − Kd ω,    e = θ_ref − θ  (P, PD, PID;
%                 the derivative acts on the measured speed, so a reference
%                 step gives no derivative kick)
%
%   and clipped to ±Vmax. With antiWindup 'clamping' the integral stops
%   while the voltage is saturated and the error would drive it further
%   into saturation; with 'none' it keeps integrating (windup). L = 0 makes
%   the current follow the voltage at once: i = (V − K ω) / R.
%
%   Classical Runge–Kutta with a fixed step that divides every output
%   interval and resolves the fastest pole of the motor and of the loop.
%
%   Fields: R (Ω), L (H), K (V·s/rad), J (kg·m²), b (N·m·s/rad), Vmax (V);
%   mode, Kp, Ki, Kd, antiWindup; command (function of t: the voltage in
%   open loop, else the reference speed in rad/s or angle in rad); load
%   (function of t, N·m); tspan, dt (s); optional stepWindow [t0 t1] (the
%   step metrics below) and progressFcn.
%
%   result: t, i, omega, theta, integral (∫e dt), Vcmd (before the limit),
%   V (applied), reference and error (NaN in open loop), load, saturated
%   (logical), power (V i, from the supply), shaftPower (K i ω),
%   copperLoss (R i²), energy (∫ V i dt so far, J: integrated with the
%   motion, not from the samples), the fields of
%   dlab.sims.dcmotor.linearModel (A, B, openPoles, Acl, closedPoles,
%   tauMech, tauElec, gain, ...), and step (dlab.sims.dcmotor.stepResponse
%   of the controlled variable over stepWindow: the speed in open loop and
%   under speed control, the angle under position control; empty without
%   a stepWindow).
p = validate(p);
lin = dlab.sims.dcmotor.linearModel(p);

samples = floor(p.tspan / p.dt) + 1;
if samples > 2e6
    error('dcmotor:TooManySamples', ['This run asks for %.3g output samples (at most 2 million); ' ...
        'lengthen the output step or shorten the run.'], samples);
end
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan - 1e-12 * p.tspan
    t(end + 1) = p.tspan;
end
progressFcn = [];
if isfield(p, 'progressFcn')
    progressFcn = p.progressFcn;
end
[t, s] = integrate(p, t, maxStep(p, lin), progressFcn);
r = p.command(t);
tau = p.load(t);
[~, out] = rhsAll(s, r(:), tau(:), p);

result.t = t;
result.i = out.i;
result.omega = s(:, 2);
result.theta = s(:, 3);
result.integral = s(:, 4);
result.energy = s(:, 5);
result.Vcmd = out.Vcmd;
result.V = out.V;
if strcmp(p.mode, 'open')
    result.reference = nan(size(t));
else
    result.reference = r(:);
end
result.error = out.e;
result.load = tau(:);
result.saturated = abs(out.Vcmd) > p.Vmax;
result.power = out.V .* out.i;
result.shaftPower = p.K * out.i .* result.omega;
result.copperLoss = p.R * out.i.^2;
for name = fieldnames(lin)'
    result.(name{1}) = lin.(name{1});
end
result.step = [];
if isfield(p, 'stepWindow') && ~isempty(p.stepWindow)
    if strcmp(p.mode, 'position')
        y = result.theta;
    else
        y = result.omega;
    end
    result.step = dlab.sims.dcmotor.stepResponse(t, y, p.stepWindow);
end
end

function [t, x] = integrate(p, t, hMax, progressFcn)
% The command and the load are known in advance, so they are evaluated at
% every stage time of an output interval at once. A cancel (progressFcn
% returning true) ends the run early. States [i ω θ z E], E = ∫ V i dt.
x = zeros(numel(t), 5);
y = zeros(1, 5);
reported = 0;
for k = 1:numel(t) - 1
    span = t(k + 1) - t(k);
    n = ceil(span / hMax - 1e-9);
    h = span / n;
    times = t(k) + h * (0:2 * n)' / 2;           % steps and half steps
    r = p.command(times);
    tau = p.load(times);
    for j = 1:n
        a = 2 * j - 1;                            % index of the step's start
        k1 = rhsAll(y, r(a), tau(a), p);
        k2 = rhsAll(y + h / 2 * k1, r(a + 1), tau(a + 1), p);
        k3 = rhsAll(y + h / 2 * k2, r(a + 1), tau(a + 1), p);
        k4 = rhsAll(y + h * k3, r(a + 2), tau(a + 2), p);
        y = y + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
    end
    x(k + 1, :) = y;
    % Every 2 % of the run: a report costs about as much as a sample.
    if ~isempty(progressFcn) && t(k + 1) >= reported + 0.02 * t(end)
        reported = t(k + 1);
        if progressFcn(t(k + 1) / t(end))
            t = t(1:k + 1);
            x = x(1:k + 1, :);
            return
        end
    end
end
end

function [d, out] = rhsAll(s, r, tau, p)
% Derivatives for rows of states S = [i ω θ z E], with the controller
% (E, the energy drawn from the supply, grows at V i).
w = s(:, 2);
z = s(:, 4);
switch p.mode
    case 'speed'
        e = r - w;
        Vcmd = p.Kp * e + p.Ki * z;
    case 'position'
        e = r - s(:, 3);
        Vcmd = p.Kp * e + p.Ki * z - p.Kd * w;
    otherwise
        e = nan(size(w));
        Vcmd = r + zeros(size(w));
end
V = min(max(Vcmd, -p.Vmax), p.Vmax);
if p.L > 0
    i = s(:, 1);
    di = (V - p.R * i - p.K * w) / p.L;
else
    i = (V - p.K * w) / p.R;
    di = zeros(size(w));
end
dw = (p.K * i - p.b * w - tau) / p.J;
dz = e;
if strcmp(p.mode, 'open')
    dz = zeros(size(w));
elseif strcmp(p.antiWindup, 'clamping')
    frozen = abs(Vcmd) > p.Vmax & e .* Vcmd > 0;
    dz(frozen) = 0;
end
d = [di, dw, w, dz, V .* i];
if nargout > 1
    out = struct('i', i, 'Vcmd', Vcmd, 'V', V, 'e', e);
end
end

function h = maxStep(p, lin)
% Resolve the fastest pole of the motor (saturated: open loop) and of the
% closed loop, and every output interval.
fastest = max(abs([eig(lin.A); lin.closedPoles]));
h = min(0.2 / max(fastest, eps), p.dt);
steps = p.tspan / h;
if steps > 5e6
    error('dcmotor:TooStiff', ['This motor and controller need %.3g time steps; shorten the run, ' ...
        'lower the gains, or set the inductance to 0.'], steps);
end
end

function p = validate(p)
names = {'R', 'K', 'J', 'tspan', 'dt', 'Vmax'};
for k = 1:numel(names)
    v = p.(names{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        error('dcmotor:InvalidParameter', '%s must be a positive number.', names{k});
    end
end
names = {'L', 'b'};
for k = 1:numel(names)
    v = p.(names{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0)
        error('dcmotor:InvalidParameter', '%s must be zero or positive.', names{k});
    end
end
p.mode = lower(char(p.mode));
if ~any(strcmp(p.mode, {'open', 'speed', 'position'}))
    error('dcmotor:InvalidParameter', 'Unknown mode "%s" (open, speed, or position).', p.mode);
end
p.antiWindup = lower(char(p.antiWindup));
if ~any(strcmp(p.antiWindup, {'none', 'clamping'}))
    error('dcmotor:InvalidParameter', 'Unknown anti-windup "%s" (none or clamping).', p.antiWindup);
end
gains = [p.Kp p.Ki p.Kd];
if ~all(isfinite(gains))
    error('dcmotor:InvalidParameter', 'The gains must be finite.');
end
if p.dt > p.tspan
    error('dcmotor:InvalidParameter', 'The output step must not be longer than the duration.');
end
if ~isa(p.command, 'function_handle') || ~isa(p.load, 'function_handle')
    error('dcmotor:InvalidParameter', 'The command and the load must be functions of time.');
end
end
