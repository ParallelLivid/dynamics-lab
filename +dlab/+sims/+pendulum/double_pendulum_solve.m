function [sol, errMsg] = double_pendulum_solve(p, progressFcn)
%DOUBLE_PENDULUM_SOLVE Damped double pendulum (two point masses on rods).
%   [sol, errMsg] = double_pendulum_solve(p) with fields
%     L1 L2 m1 m2   upper and lower rod lengths (m) and bob masses (kg)
%     b             joint damping (N·m·s) at the pivot and at the elbow
%     g             gravity (m/s²)
%     theta1 theta2 initial angles from straight down (deg)
%     omega1 omega2 initial angular velocities (rad/s)
%     tspan dt      duration and output step (s)
%     twin          also run a second pendulum whose θ2 starts delta higher
%     delta         twin's initial difference in θ2 (deg)
%     lyapunov      estimate the largest Lyapunov exponent (Benettin method)
%
%   sol: t, theta1, theta2, omega1, omega2 (rad, rad/s), theta1Deg,
%   theta2Deg, bob positions x1 y1 x2 y2, energies KE PE E (PE = 0
%   hanging), twin (the same angle and position fields, or []),
%   separation (phase-space distance to the twin), bobSeparation (distance
%   between the lower bobs), divergenceTime (lower bobs 10 % of the total
%   length apart; NaN if never), poincare (k×2 [θ2 ω2] whenever θ1 passes
%   0 moving forward), and lyapunov (struct exponent, t, lambda, or []).
%
%   Optional PROGRESSFCN: @(fraction) stop; returning true stops early.
%   Errors are returned in ERRMSG (as pendulum_solve does).
sol = [];
errMsg = '';
if nargin < 2
    progressFcn = [];
end
try
    names = {'L1', 'L2', 'm1', 'm2', 'g', 'tspan', 'dt'};
    for k = 1:numel(names)
        validateattributes(p.(names{k}), {'numeric'}, {'real', 'finite', 'scalar', 'positive'}, mfilename, names{k});
    end
    names = {'b', 'delta'};
    for k = 1:numel(names)
        validateattributes(p.(names{k}), {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, names{k});
    end
    names = {'theta1', 'theta2', 'omega1', 'omega2'};
    for k = 1:numel(names)
        validateattributes(p.(names{k}), {'numeric'}, {'real', 'finite', 'scalar'}, mfilename, names{k});
    end
    if p.dt >= p.tspan
        error('The output step must be smaller than the duration.');
    end
catch exception
    errMsg = exception.message;
    return
end

c = struct('L1', p.L1, 'L2', p.L2, 'm1', p.m1, 'm2', p.m2, 'b', p.b, 'g', p.g);
rhs = @dlab.sims.pendulum.double_pendulum_rhs;
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan
    t(end + 1, 1) = p.tspan;
end
y0 = [deg2rad(p.theta1); deg2rad(p.theta2); p.omega1; p.omega2];
twin = logical(p.twin);
lyap = logical(p.lyapunov);
mainShare = 1;
if lyap
    mainShare = 0.6;          % progress: main run, then the Lyapunov loop
end

options = odeset('RelTol', 1e-10, 'AbsTol', 1e-12, 'Events', @poincareEvent);
if ~isempty(progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(@(fraction) progressFcn(mainShare * fraction), [0 p.tspan]));
end
if twin
    start = [y0; y0 + [0; deg2rad(p.delta); 0; 0]];
    [tOut, Y, ~, ye] = ode45(@(~, y) [rhs(y(1:4), c); rhs(y(5:8), c)], t, start, options);
else
    [tOut, Y, ~, ye] = ode45(@(~, y) rhs(y, c), t, y0, options);
end
n = numel(tOut);
sol.t = tOut;
sol = addKinematics(sol, Y(:, 1:4), c);

sol.twin = [];
sol.separation = [];
sol.bobSeparation = [];
sol.divergenceTime = NaN;
if twin
    other = addKinematics(struct(), Y(:, 5:8), c);
    sol.twin = rmfield(other, {'KE', 'PE', 'E'});
    sol.separation = sqrt(sum((Y(:, 5:8) - Y(:, 1:4)).^2, 2));
    sol.bobSeparation = hypot(other.x2 - sol.x2, other.y2 - sol.y2);
    apart = find(sol.bobSeparation > 0.1 * (p.L1 + p.L2), 1);
    if ~isempty(apart)
        sol.divergenceTime = tOut(apart);
    end
end

% Poincaré section: θ1 passes 0 (not π) moving forward.
sol.poincare = zeros(0, 2);
if ~isempty(ye)
    near = cos(ye(:, 1)) > 0;
    sol.poincare = [wrapToPiLocal(ye(near, 2)), ye(near, 4)];
end

sol.lyapunov = [];
if lyap && n == numel(t)
    sol.lyapunov = benettin(rhs, y0, c, p.tspan, progressFcn, mainShare);
end
end

% ------------------------------------------------------------------ model
function sol = addKinematics(sol, Y, c)
sol.theta1 = Y(:, 1);
sol.theta2 = Y(:, 2);
sol.omega1 = Y(:, 3);
sol.omega2 = Y(:, 4);
sol.theta1Deg = rad2deg(Y(:, 1));
sol.theta2Deg = rad2deg(Y(:, 2));
sol.x1 = c.L1 * sin(Y(:, 1));
sol.y1 = -c.L1 * cos(Y(:, 1));
sol.x2 = sol.x1 + c.L2 * sin(Y(:, 2));
sol.y2 = sol.y1 - c.L2 * cos(Y(:, 2));
w1 = Y(:, 3);
w2 = Y(:, 4);
sol.KE = 0.5 * (c.m1 + c.m2) * c.L1^2 * w1.^2 + 0.5 * c.m2 * c.L2^2 * w2.^2 ...
    + c.m2 * c.L1 * c.L2 * w1 .* w2 .* cos(Y(:, 1) - Y(:, 2));
sol.PE = (c.m1 + c.m2) * c.g * c.L1 * (1 - cos(Y(:, 1))) + c.m2 * c.g * c.L2 * (1 - cos(Y(:, 2)));
sol.E = sol.KE + sol.PE;
end

function [value, isTerminal, direction] = poincareEvent(~, y)
% sin θ1 rising: θ1 through 0 forwards (or through π backwards; filtered).
value = sin(y(1));
isTerminal = 0;
direction = 1;
end

function L = benettin(rhs, y0, c, tspan, progressFcn, mainShare)
%BENETTIN Largest Lyapunov exponent: follow a nearby trajectory, rescale
%   the separation back to d0 every tau seconds, and average the log growth.
tau = 0.25;
d0 = 1e-8;
steps = ceil(tspan / tau - 1e-9);
options = odeset('RelTol', 1e-10, 'AbsTol', 1e-13);
y = y0;
direction = [1; 1; 0; 0] / sqrt(2);
yp = y0 + d0 * direction;
total = 0;
history = zeros(steps, 2);
for k = 1:steps
    t0 = (k - 1) * tau;
    t1 = min(k * tau, tspan);
    [~, Y] = ode45(@(~, z) [rhs(z(1:4), c); rhs(z(5:8), c)], [t0 t1], [y; yp], options);
    y = Y(end, 1:4)';
    yp = Y(end, 5:8)';
    gap = yp - y;
    distance = norm(gap);
    total = total + log(distance / d0);
    yp = y + gap * (d0 / distance);
    history(k, :) = [t1, total / t1];
    if ~isempty(progressFcn) && progressFcn(mainShare + (1 - mainShare) * k / steps)
        history = history(1:k, :);
        break
    end
end
L = struct('exponent', history(end, 2), 't', history(:, 1), 'lambda', history(:, 2));
end

function a = wrapToPiLocal(a)
a = mod(a + pi, 2 * pi) - pi;
end
