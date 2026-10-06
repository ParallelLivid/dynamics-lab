function result = simulateCr3bp(p)
%SIMULATECR3BP A small body moving under two primaries on circular orbits
%   (the circular restricted three-body problem), in the rotating frame.
%   Units: the primaries' separation, their total mass, and 1/(their
%   angular rate), so G = 1 and the period of the primaries is 2π.
%
%   Fields: mu (mass ratio), state0 ([x y z vx vy vz], rotating frame),
%   tspan, dt (output step), radii ([R1 R2]: a collision with a primary
%   ends the run; zeros for none), optional progressFcn.
%
%   result: t, state (n×6), C (Jacobi constant over time), C0, r1, r2
%   (distances to the primaries), inertial (n×3: the position in the
%   non-rotating frame, primaries' centre of mass at the origin), L (the
%   Lagrange points, 5×3), termination ("completed" | "collision1" |
%   "collision2"), and escaped (true if the body went beyond 10 units).
mu = p.mu;
if ~(mu > 0 && mu <= 0.5)
    error('threebody:InvalidParameter', 'The mass ratio must be in (0, 0.5].');
end
if ~(p.tspan > 0 && p.dt > 0)
    error('threebody:InvalidParameter', 'The duration and output step must be positive.');
end
s0 = p.state0(:);
radii = p.radii(:)';
r1 = norm(s0(1:3) - [-mu; 0; 0]);
r2 = norm(s0(1:3) - [1 - mu; 0; 0]);
if r1 <= max(radii(1), 0) || r2 <= max(radii(2), 0) || r1 == 0 || r2 == 0
    error('threebody:InvalidParameter', 'The body starts inside a primary.');
end
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan
    t(end + 1) = p.tspan;
end
if numel(t) < 3
    t = linspace(0, p.tspan, 3)';
end
options = odeset('RelTol', 1e-12, 'AbsTol', 1e-12);
if any(radii > 0)
    options = odeset(options, 'Events', @(~, s) impact(s, mu, radii));
end
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, t));
end
rhs = @(~, s) dlab.sims.threebody.cr3bpRhs(s, mu);
tEvent = [];
if any(radii > 0)
    [tOut, state, tEvent, sEvent, which] = ode113(rhs, t, s0, options);
else
    % Without an Events function, ode113 does not assign the event outputs.
    [tOut, state] = ode113(rhs, t, s0, options);
end
termination = "completed";
if ~isempty(tEvent)
    termination = sprintf("collision%d", which(end));
    if tOut(end) < tEvent(end)
        tOut(end + 1) = tEvent(end);
        state(end + 1, :) = sEvent(end, :);
    end
end
result.t = tOut;
result.state = state;
result.C = dlab.sims.threebody.jacobi(mu, state);
result.C0 = result.C(1);
result.r1 = sqrt((state(:, 1) + mu).^2 + state(:, 2).^2 + state(:, 3).^2);
result.r2 = sqrt((state(:, 1) - 1 + mu).^2 + state(:, 2).^2 + state(:, 3).^2);
c = cos(tOut);
s = sin(tOut);
result.inertial = [state(:, 1) .* c - state(:, 2) .* s, state(:, 1) .* s + state(:, 2) .* c, state(:, 3)];
result.L = dlab.sims.threebody.lagrangePoints(mu);
result.termination = termination;
result.escaped = any(sqrt(sum(state(:, 1:3).^2, 2)) > 10);
result.mu = mu;
end

function [value, terminal, direction] = impact(s, mu, radii)
value = [norm(s(1:3) - [-mu; 0; 0]) - radii(1); norm(s(1:3) - [1 - mu; 0; 0]) - radii(2)];
terminal = [1; 1];
direction = [-1; -1];
end
