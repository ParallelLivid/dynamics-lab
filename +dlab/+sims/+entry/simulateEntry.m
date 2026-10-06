function result = simulateEntry(p)
%SIMULATEENTRY Planar atmospheric entry of a capsule over a spherical,
%   non-rotating Earth.
%
%   States: altitude h, speed V, flight-path angle γ (negative descending),
%   downrange s along the surface, the heat load Q = ∫ q̇ dt per unit area
%   of the stagnation point, and the drag work per unit mass W = ∫ (D/m) V dt.
%
%       dV/dt   = −D/m − g sin γ
%       V dγ/dt = L/m − (g − V²/r) cos γ
%       dh/dt   = V sin γ
%       ds/dt   = (R/r) V cos γ
%
%   with r = R + h, g = μ/r², D/m = ρV²/(2β), L/m = (L/D)(D/m) cos σ (σ is
%   the bank angle), and the Sutton–Graves stagnation heating
%   q̇ = k √(ρ/r_n) V³, k = 1.7415e-4 (SI). Lift does no work, so the
%   specific energy V²/2 − μ/r falls by exactly W.
%
%   Fields of P:
%     V0 (m/s), gamma0 (deg, ≤ 0), h0 (m): the entry state
%     beta        ballistic coefficient m/(C_D S), kg/m²
%     LD          lift-to-drag ratio (≥ 0)
%     bank        @(t) bank angle (deg): 0 lift up, 180 lift down
%     noseRadius  m (for the heating)
%     atmosphere  'standard' (dlab.physics.thermosphereDensity) or
%                 'exponential' (rho0 exp(−h/H))
%     scaleHeight m (H, exponential);  rho0 (kg/m³, optional, 1.225)
%     chuteMach   stop when the Mach number falls below it (0: off); the
%                 speed of sound is dlab.physics.atmosphere's (extended
%                 above 86 km)
%     maxTime, dt (s);  optional progressFcn
%     gravity     logical (true; false only for tests)
%     curvature   logical (true; false: a flat Earth, for tests: no V²/r
%                 term and ds/dt = V cos γ)
%
%   result: t, h, V, gamma (deg), downrange (m), x, y (m, in the plane,
%   Earth's centre at the origin, entry above (0, R)), rho, mach, decel
%   (aerodynamic acceleration, g), qdot (W/m²), heatLoad (J/m²), q
%   (dynamic pressure, Pa), dragWork (J/kg), energy (specific mechanical
%   energy, J/kg), peaks (struct: decel, decelTime, decelAltitude, qdot,
%   qdotTime, qdotAltitude, q, qTime, qAltitude), termination ('ground',
%   'chute', 'skip', 'time', 'cancelled'), skipped (logical).
c = constants();
validate(p);
gravityOn = ~isfield(p, 'gravity') || logical(p.gravity);
curved = ~isfield(p, 'curvature') || logical(p.curvature);
rho0 = 1.225;
if isfield(p, 'rho0')
    rho0 = p.rho0;
end
bank = p.bank;
if isnumeric(bank)
    value = bank;
    bank = @(t) value;
end
ctx = struct('mu', c.mu * gravityOn, 'R', c.R, 'beta', p.beta, 'LD', p.LD, 'bank', bank, ...
    'rn', p.noseRadius, 'exponential', strcmp(p.atmosphere, 'exponential'), 'H', p.scaleHeight, ...
    'rho0', rho0, 'curved', curved, 'k', c.suttonGraves);

state0 = [p.h0; p.V0; deg2rad(p.gamma0); 0; 0; 0];
times = 0:p.dt:p.maxTime;
if times(end) < p.maxTime
    times(end + 1) = p.maxTime;
end
if numel(times) == 2
    times = [0, p.maxTime / 2, p.maxTime];
end
progress = [];
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    progress = p.progressFcn;
end
cancelled = false;
options = odeset('RelTol', 1e-9, 'AbsTol', [1e-4; 1e-6; 1e-11; 1e-4; 1e-2; 1e-3], ...
    'MaxStep', max(10 * p.dt, 1), ...
    'Events', @(t, s) stops(t, s, ctx, p), 'OutputFcn', @report);
[T, S, tEvent, sEvent, which] = ode45(@(t, s) rhs(t, s, ctx), times, state0, options);
if ~isempty(tEvent) && T(end) < tEvent(end)
    T = [T; tEvent(end)];
    S = [S; sEvent(end, :)];
end

termination = 'time';
if cancelled
    termination = 'cancelled';
elseif ~isempty(which)
    names = {'ground', 'chute', 'skip'};
    termination = names{which(end)};
end

% ------------------------------------------------------------- outputs
result.t = T;
result.h = S(:, 1);
result.V = S(:, 2);
result.gamma = rad2deg(S(:, 3));
result.downrange = S(:, 4);
theta = S(:, 4) / c.R;
radius = c.R + S(:, 1);
result.x = radius .* sin(theta);
result.y = radius .* cos(theta);
rho = density(S(:, 1), ctx);
result.rho = rho;
[~, ~, ~, sound] = dlab.physics.atmosphere(max(S(:, 1), 0), 'Extended', true);
result.mach = S(:, 2) ./ reshape(sound, [], 1);
result.decel = aeroAcceleration(S(:, 2), rho, ctx) / c.g0;
result.qdot = ctx.k * sqrt(rho / ctx.rn) .* S(:, 2).^3;
result.heatLoad = S(:, 5);
result.q = 0.5 * rho .* S(:, 2).^2;
result.dragWork = S(:, 6);
result.energy = 0.5 * S(:, 2).^2 - ctx.mu ./ radius;
result.peaks = peaksOf(result);
result.termination = termination;
result.skipped = strcmp(termination, 'skip');

    function stop = report(t, y, flag)
        stop = false;
        if isempty(flag) && ~isempty(progress)
            h = y(1, end);
            fraction = max(t(end) / p.maxTime, min(max((p.h0 - h) / p.h0, 0), 1));
            stop = progress(fraction);
            cancelled = cancelled || stop;
        end
    end
end

% ------------------------------------------------------------ dynamics
function ds = rhs(t, s, ctx)
h = s(1);
V = max(s(2), 1e-6);
gamma = s(3);
r = ctx.R + h;
rho = density(h, ctx);
drag = rho * V^2 / (2 * ctx.beta);                 % D/m
lift = ctx.LD * drag * cosd(ctx.bank(t));          % vertical component of L/m
g = ctx.mu / r^2;
centrifugal = 0;
surface = 1;
if ctx.curved
    centrifugal = V^2 / r;
    surface = ctx.R / r;
end
ds = [V * sin(gamma)
      -drag - g * sin(gamma)
      (lift - (g - centrifugal) * cos(gamma)) / V
      surface * V * cos(gamma)
      ctx.k * sqrt(rho / ctx.rn) * V^3
      drag * V];
end

function a = aeroAcceleration(V, rho, ctx)
% |L + D|/m, what the crew feels: the bank only tilts the lift.
a = rho .* V.^2 / (2 * ctx.beta) * sqrt(1 + ctx.LD^2);
end

function rho = density(h, ctx)
if ctx.exponential
    rho = ctx.rho0 * exp(-h / ctx.H);
else
    rho = dlab.physics.thermosphereDensity(h / 1e3);
end
end

function [value, terminal, direction] = stops(~, s, ctx, p)
% Ground, parachute deploy (Mach below chuteMach), and skip-out (climbing
% back above the entry altitude).
h = s(1);
chute = 1;
if p.chuteMach > 0
    [~, ~, ~, sound] = dlab.physics.atmosphere(max(h, 0), 'Extended', true);
    chute = s(2) - p.chuteMach * sound;
end
value = [h; chute; h - p.h0 - 1];
terminal = [1; 1; 1];
direction = [-1; -1; 1];
if ~ctx.curved && ctx.mu == 0
    value(3) = -1;          % a straight line never climbs back
end
end

% ------------------------------------------------------------- results
function peaks = peaksOf(r)
[peaks.decel, peaks.decelTime, peaks.decelAltitude] = peakOf(r.t, r.decel, r.h);
[peaks.qdot, peaks.qdotTime, peaks.qdotAltitude] = peakOf(r.t, r.qdot, r.h);
[peaks.q, peaks.qTime, peaks.qAltitude] = peakOf(r.t, r.q, r.h);
end

function [peak, when, where] = peakOf(t, y, h)
% The maximum of samples Y, refined by a parabola through three samples.
[peak, k] = max(y);
when = t(k);
where = h(k);
if k == 1 || k == numel(y)
    return
end
tt = t(k-1:k+1);
yy = y(k-1:k+1);
A = [tt.^2, tt, ones(3, 1)];
if rcond(A) < 1e-14
    return
end
coef = A \ yy;
if coef(1) >= 0
    return
end
tPeak = -coef(2) / (2 * coef(1));
if tPeak < tt(1) || tPeak > tt(3)
    return
end
when = tPeak;
peak = max(polyval(coef, tPeak), peak);
where = interp1(tt, h(k-1:k+1), tPeak);
end

% ---------------------------------------------------------- utilities
function c = constants()
earth = dlab.physics.bodyConstants("Earth");
c = struct('mu', earth.mu * 1e9, 'R', earth.radius * 1e3, 'g0', 9.80665, 'suttonGraves', 1.7415e-4);
end

function validate(p)
positive = {'V0', 'h0', 'beta', 'noseRadius', 'scaleHeight', 'maxTime', 'dt'};
for k = 1:numel(positive)
    v = p.(positive{k});
    if ~(isscalar(v) && isfinite(v) && v > 0)
        error('entry:InvalidParameter', '%s must be a positive number.', positive{k});
    end
end
if ~(isscalar(p.gamma0) && p.gamma0 <= 0 && p.gamma0 >= -90)
    error('entry:InvalidParameter', 'The entry flight-path angle must be between −90° and 0° (descending).');
end
if ~(isscalar(p.LD) && p.LD >= 0 && isfinite(p.LD))
    error('entry:InvalidParameter', 'The lift-to-drag ratio must be zero or positive.');
end
if ~(isscalar(p.chuteMach) && p.chuteMach >= 0)
    error('entry:InvalidParameter', 'The parachute Mach number must be zero (off) or positive.');
end
if ~any(strcmp(p.atmosphere, {'standard', 'exponential'}))
    error('entry:InvalidParameter', 'The atmosphere must be ''standard'' or ''exponential''.');
end
end
