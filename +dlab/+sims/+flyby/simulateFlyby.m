function result = simulateFlyby(p)
%SIMULATEFLYBY A gravity assist: a hyperbolic pass of a planet (integrated
%   in the planet's frame) patched to heliocentric orbits before and after.
%
%   Planet frame: two-body motion r'' = −μ r / |r|³ (km, km/s), started on
%   the analytic hyperbola with excess speed v∞ and periapsis radius r_p and
%   integrated by ode113 (relative tolerance 10⁻¹²) through periapsis. The
%   turning angle δ is measured from the integrated trajectory: the angle
%   between the incoming asymptote of the first state and the outgoing
%   asymptote of the last (each from that state's osculating hyperbola,
%   which removes the bias of starting at a finite distance). Analytic:
%   δ = 2 asin(1 / (1 + r_p v∞² / μ)).
%
%   Sun frame (patched conic): the planet moves on a circular orbit of
%   radius a at V_p = √(μ_Sun / a). At the encounter the planet is at
%   (0, −a) moving along +x, so in both frames +x is the planet's direction
%   of motion and +y points to the Sun. The heliocentric velocity is
%   V_p + v∞ before and V_p + v∞,out after.
%
%   p: mu, R (planet, km³/s² and km), aOrbit (km), muSun (km³/s²), vinf
%   (km/s), alpha (deg, the direction of v∞,in from the planet's velocity,
%   positive toward the Sun), altitude (km, of the periapsis), pass
%   ('behind': periapsis on the trailing side, which gains speed; 'ahead':
%   the leading side, which loses it), durationFactor (the run spans
%   ± factor · r_p / v∞ around periapsis, at most the sphere of influence),
%   optional samples (default 1501) and progressFcn (@(fraction) stop; a
%   cancel errors with flyby:Cancelled).
%
%   result: t (s from the start), tRel (s from periapsis), r, v (n×2, km,
%   km/s, planet frame), rMag, speed, vHelio, speedHelio, the hyperbola
%   (e, rp, b, sense, eHat, pHat), deltaAnalytic, deltaNumeric, deltaRaw
%   (rad), vInfIn, vInfOut (1×2), dv (1×2), Vp, rSoi, tSoi, before/after
%   heliocentric orbits (helioOrbit structs), energyChange and
%   energyPredicted (km²/s²), closest (km), timeline (the patched-conic
%   heliocentric speed: t, speed, phase 1/2/3), soiPath (the hyperbola
%   across the sphere of influence).
validate(p);
mu = p.mu;
vinf = p.vinf;
rp = p.R + p.altitude;
e = 1 + rp * vinf^2 / mu;
aH = mu / vinf^2;                                 % |a| of the hyperbola
delta = 2 * asin(1 / e);
Vp = sqrt(p.muSun / p.aOrbit);
rSoi = p.aOrbit * (mu / p.muSun)^(2/5);
if rSoi <= 1.01 * rp
    error('flyby:InvalidParameter', ...
        'The periapsis (%.0f km) must be well inside the sphere of influence (%.0f km).', rp, rSoi);
end

% The side: the rotation sense whose Δv points along (behind) or against
% (ahead) the planet's motion.
alpha = deg2rad(p.alpha);
vInfIn = vinf * [cos(alpha) sin(alpha)];
gain = @(s) cos(alpha + s * delta) - cos(alpha);
if strcmp(p.pass, 'behind')
    sense = 1;
    if gain(-1) > gain(1)
        sense = -1;
    end
else
    sense = -1;
    if gain(1) < gain(-1)
        sense = 1;
    end
end
phiE = alpha - sense * (pi / 2 - delta / 2);
eHat = [cos(phiE) sin(phiE)];
pHat = sense * [-eHat(2) eHat(1)];
hyper = struct('mu', mu, 'aH', aH, 'e', e, 'eHat', eHat, 'pHat', pHat);

tau = rp / vinf;
tSoi = timeAtRadius(hyper, rSoi);
T = min(p.durationFactor * tau, tSoi);
samples = 1501;
if isfield(p, 'samples') && ~isempty(p.samples)
    samples = 2 * floor(p.samples / 2) + 1;
end
tRel = timeGrid(T, tau / 20, samples);

% Integrate through periapsis.
[r0, v0] = hyperbolaState(hyper, -T);
vPeri = sqrt(vinf^2 + 2 * mu / rp);
options = odeset('RelTol', 1e-12, 'AbsTol', 1e-13 * [rp rp vPeri vPeri]);
progressFcn = [];
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    progressFcn = p.progressFcn;
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(progressFcn, [-T T]));
end
f = @(~, s) [s(3:4); -mu * s(1:2) / norm(s(1:2))^3];
[tOut, S] = ode113(f, tRel, [r0 v0]', options);
if numel(tOut) < numel(tRel)
    if ~isempty(progressFcn)
        error('flyby:Cancelled', 'The flyby was cancelled.');
    end
    error('flyby:Integration', 'The flyby could not be integrated past t = %.6g s.', tOut(end));
end
r = S(:, 1:2);
v = S(:, 3:4);

% The turning angle from the trajectory.
[inFirst, ~] = asymptotes(r(1, :), v(1, :), mu);
[~, outLast, vinfOut] = asymptotes(r(end, :), v(end, :), mu);
deltaNumeric = angleBetween(inFirst, outLast);
deltaRaw = angleBetween(v(1, :), v(end, :));
vInfOut = vinfOut * outLast;
dv = vInfOut - vInfIn;

% The Sun's frame.
VpVec = [Vp 0];
planetAt = [0 -p.aOrbit];
before = dlab.sims.flyby.helioOrbit(planetAt, VpVec + vInfIn, p.muSun);
after = dlab.sims.flyby.helioOrbit(planetAt, VpVec + vInfOut, p.muSun);
vHelio = VpVec + v;

result.t = tOut - tOut(1);
result.tRel = tOut;
result.r = r;
result.v = v;
result.rMag = sqrt(sum(r.^2, 2));
result.speed = sqrt(sum(v.^2, 2));
result.vHelio = vHelio;
result.speedHelio = sqrt(sum(vHelio.^2, 2));
result.vinf = vinf;
result.rp = rp;
result.e = e;
result.b = rp * sqrt(1 + 2 * mu / (rp * vinf^2));
result.vPeri = vPeri;
result.sense = sense;
result.eHat = eHat;
result.pHat = pHat;
result.center = aH * e * eHat;                    % where the asymptotes cross
result.deltaAnalytic = delta;
result.deltaNumeric = deltaNumeric;
result.deltaRaw = deltaRaw;
result.vInfIn = vInfIn;
result.vInfOut = vInfOut;
result.dv = dv;
result.dvAnalytic = 2 * vinf * sin(delta / 2);
result.Vp = Vp;
result.aOrbit = p.aOrbit;
result.muSun = p.muSun;
result.mu = mu;
result.R = p.R;
result.rSoi = rSoi;
result.tSoi = tSoi;
result.T = T;
result.before = before;
result.after = after;
result.energyChange = after.energy - before.energy;
result.energyPredicted = VpVec * dv';
result.closest = min(result.rMag);
result.periapsisBehind = eHat(1) < 0;             % periapsis on the trailing side
result.timeline = timeline(hyper, VpVec, planetAt, p.muSun, tSoi);
[soiR, ~] = hyperbolaState(hyper, tSoi * sinh(linspace(-6, 6, 801)') / sinh(6));
result.soiPath = soiR;
end

% ---------------------------------------------------------------- helpers
function validate(p)
need = {'mu', 'R', 'aOrbit', 'muSun', 'vinf', 'alpha', 'altitude', 'pass', 'durationFactor'};
for k = 1:numel(need)
    if ~isfield(p, need{k})
        error('flyby:InvalidParameter', 'Missing input "%s".', need{k});
    end
end
positive = {'mu', 'R', 'aOrbit', 'muSun', 'vinf', 'durationFactor'};
for k = 1:numel(positive)
    value = p.(positive{k});
    if ~(isscalar(value) && isnumeric(value) && isfinite(value) && value > 0)
        error('flyby:InvalidParameter', '"%s" must be a positive number.', positive{k});
    end
end
if ~(isscalar(p.altitude) && isfinite(p.altitude) && p.altitude >= 0)
    error('flyby:InvalidParameter', 'The periapsis altitude must be zero or more (no impact).');
end
if ~(isscalar(p.alpha) && isfinite(p.alpha))
    error('flyby:InvalidParameter', 'The direction of v∞ must be a finite angle.');
end
if ~any(strcmp(char(p.pass), {'behind', 'ahead'}))
    error('flyby:InvalidParameter', 'The pass must be "behind" or "ahead".');
end
end

function t = timeGrid(T, finest, n)
% Times from −T to T, symmetric with 0 exactly in the middle, crowded near
% periapsis (t = T sinh(c u) / sinh(c)) so the step there is about FINEST.
half = (n - 1) / 2;
u = (1:half) / half;
ratio = T / (half * finest);
if ratio > 1
    c = fzero(@(c) sinh(c) / c - ratio, [1e-6 60]);
    side = T * sinh(c * u) / sinh(c);
else
    side = T * u;
end
t = [-fliplr(side), 0, side]';
end

function t = timeAtRadius(h, radius)
% Time from periapsis to RADIUS on the hyperbola.
F = acosh((radius / h.aH + 1) / h.e);
t = (h.e * sinh(F) - F) / sqrt(h.mu / h.aH^3);
end

function [r, v] = hyperbolaState(h, t)
% Position and velocity at times T (column) from periapsis.
n = sqrt(h.mu / h.aH^3);
F = keplerHyperbolic(n * t(:), h.e);
ch = cosh(F);
sh = sinh(F);
k = sqrt(h.e^2 - 1);
Fdot = n ./ (h.e * ch - 1);
xp = h.aH * (h.e - ch);
yp = h.aH * k * sh;
r = xp .* h.eHat + yp .* h.pHat;
v = (-h.aH * sh .* Fdot) .* h.eHat + (h.aH * k * ch .* Fdot) .* h.pHat;
end

function F = keplerHyperbolic(M, e)
% Solve e sinh F − F = M by Newton's method from above (monotone: the
% function is convex for F > 0, and odd).
m = abs(M);
F = asinh(m / (e - 1));
for iteration = 1:200
    step = (e * sinh(F) - F - m) ./ (e * cosh(F) - 1);
    F = F - step;
    if all(abs(step) <= 1e-15 * max(1, abs(F)))
        break
    end
end
F = sign(M) .* F;
end

function [inHat, outHat, vinf] = asymptotes(r, v, mu)
% Directions of the incoming and outgoing asymptotes of the hyperbola
% through state (r, v), and its excess speed.
rn = norm(r);
v2 = v * v';
eVec = ((v2 - mu / rn) * r - (r * v') * v) / mu;
ecc = norm(eVec);
eHat = eVec / ecc;
sense = sign(r(1) * v(2) - r(2) * v(1));
pHat = sense * [-eHat(2) eHat(1)];
k = sqrt(ecc^2 - 1);
inHat = (eHat + k * pHat) / ecc;
outHat = (-eHat + k * pHat) / ecc;
vinf = sqrt(v2 - 2 * mu / rn);
end

function angle = angleBetween(a, b)
angle = atan2(abs(a(1) * b(2) - a(2) * b(1)), a * b');
end

function passage = timeline(h, VpVec, planetAt, muSun, tSoi)
% The patched-conic heliocentric speed: inside the sphere of influence the
% hyperbola plus V_p (the planet moving straight on at V_p meanwhile), and
% outside it two-body motion about the Sun, started from the hyperbola's
% state at the sphere's edge so the legs join. Each outside leg lasts as
% long as the passage.
inside = tSoi * sinh(linspace(-4, 4, 401)') / sinh(4);
[~, v] = hyperbolaState(h, inside);
during = sqrt(sum((VpVec + v).^2, 2));
options = odeset('RelTol', 1e-10, 'AbsTol', 1e-6);
f = @(~, s) [s(3:4); -muSun * s(1:2) / norm(s(1:2))^3];
outside = linspace(tSoi, 2 * tSoi, 101)';
[rEdge, vEdge] = hyperbolaState(h, [-tSoi; tSoi]);
start = [planetAt - VpVec * tSoi + rEdge(1, :), VpVec + vEdge(1, :)];
[~, S] = ode45(f, -outside, start', options);
early = flipud(sqrt(sum(S(:, 3:4).^2, 2)));
start = [planetAt + VpVec * tSoi + rEdge(2, :), VpVec + vEdge(2, :)];
[~, S] = ode45(f, outside, start', options);
late = sqrt(sum(S(:, 3:4).^2, 2));
passage.t = [-flipud(outside); inside; outside];
passage.speed = [early; during; late];
passage.phase = [ones(numel(outside), 1); 2 * ones(numel(inside), 1); 3 * ones(numel(outside), 1)];
end
