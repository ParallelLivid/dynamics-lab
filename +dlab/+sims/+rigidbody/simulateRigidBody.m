function result = simulateRigidBody(p)
%SIMULATERIGIDBODY Torque-free rigid body or heavy symmetric top.
%   result = simulateRigidBody(p) integrates Euler's equations in body
%   axes with an attitude quaternion (scalar first, body to world):
%
%     I ω' = (I ω) × ω + τ          q' = ½ q ⊗ [0; ω]
%
%   p.model 'free': no torque; p.I (principal inertias, kg·m²) and p.omega0
%   (body rates, rad/s). The body starts turned so that its angular
%   momentum points along world z.
%   p.model 'top': a symmetric top on a pivot at the origin (z up), the
%   centre of mass at distance p.l along the body z axis; p.m, p.l, p.g,
%   p.Is (spin axis), p.It (transverse, about the pivot), p.spin (body z
%   rate, rad/s), p.tilt (from vertical, rad), p.precession and
%   p.nutation (initial Euler rates, rad/s). τ = [0 0 l] × (Rᵀ [0 0 −m g]).
%
%   Common fields: tspan, dt (output step), optional progressFcn.
%
%   result: t, q (n×4), omega (n×3, body), L (n×3, world angular momentum
%   about the centre of mass or the pivot), energy, axes (n×3×3: world
%   coordinates of body axes 1–3, axes(:, :, k)), qnormError (|‖q‖ − 1|
%   before normalizing), drift (struct: energy, L (free) or Lz, L3 (top),
%   qnorm: largest relative changes), I (1×3), isTop.
%   Free body: flipAxis (the intermediate axis, by inertia; 0 when two
%   inertias are equal and there is none), flips (turnovers of that axis
%   relative to L, from within 60° of L to within 60° of −L or back; a
%   small wobble is not a flip), and flipTimes (when it crossed
%   perpendicular to L). Top: phi, theta, psi (Z-X-Z Euler angles, φ and ψ
%   unwrapped), precessionRate (mean φ', a straight-line fit of φ), and
%   nutationAmplitude ((max θ − min θ)/2).
validate(p);
isTop = strcmpi(p.model, 'top');
if isTop
    I = [p.It p.It p.Is];
    omega0 = [p.nutation; p.precession * sin(p.tilt); p.spin];
    q0 = [cos(p.tilt / 2); sin(p.tilt / 2); 0; 0];
    weight = p.m * p.g;
    arm = p.l;
else
    I = p.I(:)';
    omega0 = p.omega0(:);
    q0 = alignWithZ(I(:) .* omega0);
    weight = 0;
    arm = 0;
end
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan
    t(end + 1) = p.tspan;
end
if numel(t) < 3
    t = linspace(0, p.tspan, 3)';
end
scale = max(norm(omega0), 1e-6);
options = odeset('RelTol', 1e-11, 'AbsTol', 1e-13 * scale);
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, t));
end
[tOut, y] = ode113(@(~, state) rhs(state, I(:), weight, arm), t, [omega0; q0], options);
n = numel(tOut);
omega = y(:, 1:3);
q = y(:, 4:7) ./ sqrt(sum(y(:, 4:7).^2, 2));

frames = zeros(n, 3, 3);
L = zeros(n, 3);
up = zeros(n, 1);
for k = 1:n
    R = dlab.physics.Quaternion.toDcm(q(k, :)');
    frames(k, :, :) = reshape(R, 1, 3, 3);
    L(k, :) = (R * (I(:) .* omega(k, :)'))';
    up(k) = R(3, 3);
end
energy = 0.5 * sum(I .* omega.^2, 2) + weight * arm * up;

result.t = tOut;
result.q = q;
result.omega = omega;
result.L = L;
result.energy = energy;
result.axes = frames;
result.I = I;
result.isTop = isTop;
result.drift.energy = relativeChange(energy);
result.qnormError = abs(sqrt(sum(y(:, 4:7).^2, 2)) - 1);
result.drift.qnorm = max(result.qnormError);
if isTop
    R13 = frames(:, 1, 3);
    R23 = frames(:, 2, 3);
    R31 = frames(:, 3, 1);
    R32 = frames(:, 3, 2);
    result.theta = acos(min(max(up, -1), 1));
    result.phi = unwrap(atan2(R13, -R23));
    result.psi = unwrap(atan2(R31, R32));
    result.drift.Lz = relativeChange(L(:, 3), norm(L(1, :)));
    result.drift.L3 = relativeChange(I(3) * omega(:, 3), norm(L(1, :)));
    fit = [tOut, ones(n, 1)] \ result.phi;
    result.precessionRate = fit(1);
    result.nutationAmplitude = (max(result.theta) - min(result.theta)) / 2;
    result.flips = 0;
    result.flipTimes = zeros(0, 1);
    result.flipAxis = 0;
else
    result.drift.L = relativeChange(sqrt(sum(L.^2, 2)));
    [result.flips, result.flipTimes, result.flipAxis] = countFlips(tOut, omega, I, L);
end
end

function dy = rhs(state, I, weight, arm)
omega = state(1:3);
q = state(4:7);
torque = [0; 0; 0];
if weight ~= 0
    R = dlab.physics.Quaternion.toDcm(q);
    down = R(3, :)' * -weight;                       % Rᵀ [0 0 −m g]
    torque = cross([0; 0; arm], down);
end
domega = (cross(I .* omega, omega) + torque) ./ I;
dq = dlab.physics.Quaternion.derivative(q, omega) + (1 - q' * q) * q;
dy = [domega; dq];
end

function [flips, flipTimes, k] = countFlips(t, omega, I, L)
% Turnovers of the intermediate axis relative to L (the tennis racket
% flip). A flip is that axis going from mostly along L (component > ½) to
% mostly against it (< −½), or back: every sign change would also count
% the small wobble of a stable spin about either other axis. With two
% equal inertias there is no intermediate axis, and nothing flips.
flips = 0;
flipTimes = zeros(0, 1);
k = 0;
[sorted, order] = sort(I);
if any(diff(sorted) <= 1e-9 * sorted(3))
    return
end
k = order(2);
along = I(k) * omega(:, k) ./ max(sqrt(sum(L.^2, 2)), realmin);   % body axis · L̂
side = zeros(size(along));
side(along > 0.5) = 1;
side(along < -0.5) = -1;
known = find(side ~= 0);
turns = known([false; diff(side(known)) ~= 0]);          % first sample on the new side
flipTimes = zeros(numel(turns), 1);
for j = 1:numel(turns)
    c = find(sign(along(1:turns(j) - 1)) .* sign(along(2:turns(j))) < 0, 1, 'last');
    flipTimes(j) = t(c) - along(c) * (t(c + 1) - t(c)) / (along(c + 1) - along(c));
end
flips = numel(turns);
end

function q = alignWithZ(L)
% The rotation that turns body vector L onto world z (identity for L = 0).
q = [1; 0; 0; 0];
if norm(L) < 1e-12
    return
end
u = L / norm(L);
axis = cross(u, [0; 0; 1]);
s = norm(axis);
c = u(3);
if s < 1e-12
    if c < 0
        q = [0; 1; 0; 0];                            % half turn about x
    end
    return
end
angle = atan2(s, c);
q = [cos(angle / 2); sin(angle / 2) * axis / s];
end

function d = relativeChange(values, reference)
if nargin < 2
    reference = abs(values(1));
end
d = max(abs(values - values(1))) / max(reference, realmin);
end

function validate(p)
if strcmpi(p.model, 'top')
    names = {'m', 'l', 'Is', 'It', 'g'};
    for k = 1:numel(names)
        if ~(p.(names{k}) > 0)
            error('rigidbody:InvalidParameter', '%s must be positive.', names{k});
        end
    end
    if p.Is > 2 * p.It * (1 + 1e-12)
        error('rigidbody:InvalidParameter', ...
            'No real top has these inertias: the spin-axis inertia must be at most twice the inertia across.');
    end
elseif strcmpi(p.model, 'free')
    I = p.I;
    if ~(numel(I) == 3 && all(I > 0))
        error('rigidbody:InvalidParameter', 'The principal inertias must be positive.');
    end
    if any(I > I([2 3 1]) + I([3 1 2]) + 1e-12 * max(I))
        error('rigidbody:InvalidParameter', ...
            'No real body has these inertias: each must be at most the sum of the other two.');
    end
else
    error('rigidbody:InvalidParameter', 'Unknown model "%s".', p.model);
end
if ~(p.tspan > 0 && p.dt > 0)
    error('rigidbody:InvalidParameter', 'The duration and output step must be positive.');
end
end
