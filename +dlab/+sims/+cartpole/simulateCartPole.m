function result = simulateCartPole(p)
%SIMULATECARTPOLE Inverted pendulum on a cart, with PID or LQR control.
%   result = simulateCartPole(p) integrates dlab.sims.cartpole.dynamics
%   (ode45, MaxStep 0.01 s) with the force
%
%     'none'  F = 0
%     'pid'   F = Kp θ + Ki ∫θ dt + Kd θ' + Kx (x − x_ref) + Kv ẋ
%             (positive gains push the cart under the leaning pole)
%     'lqr'   F = −K (s − [x_ref 0 0 0]), K = dlab.physics.lqr(A, B, Q, r)
%             with Q = diag(qx, qxd, qtheta, qthetad) on the upright linearization
%
%   clipped to ±Fmax, plus the disturbance force (not clipped). The run
%   stops when the cart reaches an end of the track (|x| = track/2) or,
%   unless allowFall, when the pole falls past horizontal (|θ| > 90°).
%
%   Fields: M, m, l, poleType ('point' | 'rod': I = m (2l)² / 12), b, g;
%   x0, xd0, theta0, thetad0 (rad); controller, Kp, Ki, Kd, Kx, Kv, qx,
%   qxd, qtheta, qthetad, r; Fmax; xref and disturbance (functions of t);
%   track; allowFall; tspan; dt; optional progressFcn.
%
%   result: t, x, xd, theta, thetad, Fcommand (before the limit), F
%   (applied by the motor), disturbance, xref, saturated (logical),
%   termination ("completed" | "endstop" | "fell"; with allowFall the run
%   goes on past a fall), fallTime (when the pole first passed horizontal,
%   NaN if never), A, B, K (LQR, else
%   []), openPoles, closedPoles (the closed loop, without the limit; with
%   the integral state when Ki ≠ 0), and
%   the model struct (with I).
validate(p);
model = struct('M', p.M, 'm', p.m, 'l', p.l, 'I', 0, 'b', p.b, 'g', p.g);
if strcmpi(p.poleType, 'rod')
    model.I = p.m * (2 * p.l)^2 / 12;
end
[A, B] = dlab.sims.cartpole.linearModel(model);
K = [];
switch lower(p.controller)
    case 'lqr'
        [K, ~, closedPoles] = dlab.physics.lqr(A, B, diag([p.qx p.qxd p.qtheta p.qthetad]), p.r);
    case 'pid'
        G = [p.Kx p.Kv p.Kp p.Kd];
        if p.Ki ~= 0
            closedPoles = eig([A + B * G, B * p.Ki; 0 0 1 0 0]);
        else
            closedPoles = eig(A + B * G);
        end
    otherwise
        closedPoles = eig(A);
end
law = @(time, s) command(time, s, p, K);

t = (0:p.dt:p.tspan)';
if t(end) < p.tspan
    t(end + 1) = p.tspan;
end
s0 = [p.x0; p.xd0; p.theta0; p.thetad0; 0];
options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, 'MaxStep', 0.01, ...
    'Events', @(~, s) stops(s, p));
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, [0 p.tspan]));
end
[tOut, s, tEvent, sEvent, which] = ode45(@(time, s) rhs(time, s, p, model, law), t, s0, options);
termination = "completed";
fallTime = NaN;
if any(which == 2)
    fallTime = tEvent(find(which == 2, 1));
end
% Only a terminal event ends the run: the end stop always, the fall
% unless allowFall (then it is just recorded in fallTime).
if ~isempty(tEvent) && (which(end) == 1 || ~p.allowFall)
    if which(end) == 1
        termination = "endstop";
    else
        termination = "fell";
    end
    if tOut(end) < tEvent(end)
        tOut(end + 1) = tEvent(end);       % make the event the last sample
        s(end + 1, :) = sEvent(end, :);
    end
end

n = numel(tOut);
Fcommand = zeros(n, 1);
disturbance = zeros(n, 1);
xref = zeros(n, 1);
for k = 1:n
    Fcommand(k) = law(tOut(k), s(k, :)');
    disturbance(k) = p.disturbance(tOut(k));
    xref(k) = p.xref(tOut(k));
end
F = min(max(Fcommand, -p.Fmax), p.Fmax);

result.t = tOut;
result.x = s(:, 1);
result.xd = s(:, 2);
result.theta = s(:, 3);
result.thetad = s(:, 4);
result.Fcommand = Fcommand;
result.F = F;
result.disturbance = disturbance;
result.xref = xref;
result.saturated = abs(Fcommand) > p.Fmax;
result.termination = termination;
result.fallTime = fallTime;
result.A = A;
result.B = B;
result.K = K;
result.openPoles = eig(A);
result.closedPoles = closedPoles;
result.model = model;
end

function ds = rhs(time, s, p, model, law)
F = min(max(law(time, s), -p.Fmax), p.Fmax) + p.disturbance(time);
ds = [dlab.sims.cartpole.dynamics(s(1:4), F, model); s(3)];
end

function F = command(time, s, p, K)
switch lower(p.controller)
    case 'pid'
        F = p.Kp * s(3) + p.Ki * s(5) + p.Kd * s(4) + p.Kx * (s(1) - p.xref(time)) + p.Kv * s(2);
    case 'lqr'
        F = -K * (s(1:4) - [p.xref(time); 0; 0; 0]);
    otherwise
        F = 0;
end
end

function [value, terminal, direction] = stops(s, p)
value = [p.track / 2 - abs(s(1)); pi / 2 - abs(s(3))];
terminal = [1; ~p.allowFall];
direction = [-1; -1];
end

function validate(p)
names = {'M', 'm', 'l', 'g', 'track', 'tspan', 'dt'};
for k = 1:numel(names)
    if ~(p.(names{k}) > 0)
        error('cartpole:InvalidParameter', '%s must be positive.', names{k});
    end
end
if ~(p.b >= 0 && p.Fmax >= 0)
    error('cartpole:InvalidParameter', 'Friction and the force limit cannot be negative.');
end
if abs(p.x0) >= p.track / 2
    error('cartpole:InvalidParameter', 'The cart must start on the track.');
end
if strcmpi(p.controller, 'lqr') && ~(all([p.qx p.qxd p.qtheta p.qthetad] >= 0) && p.r > 0)
    error('cartpole:InvalidParameter', 'LQR weights must be non-negative, and r positive.');
end
if strcmpi(p.controller, 'lqr') && ~(p.qx > 0)
    % The cart's position is a neutral mode (an eigenvalue at 0) that no
    % other weight sees, so the Riccati equation has no stabilizing solution.
    error('cartpole:InvalidParameter', ['The LQR position weight must be positive: with qx = 0 ' ...
        'nothing in the cost holds the cart in place, and no gain can.']);
end
if ~any(strcmpi(p.controller, {'none', 'pid', 'lqr'}))
    error('cartpole:InvalidParameter', 'Unknown controller "%s".', p.controller);
end
end
