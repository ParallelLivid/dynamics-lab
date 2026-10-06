function plan = planManeuver(p)
%PLANMANEUVER Impulsive maneuver plans between circular orbits.
%   plan = planManeuver(p) with p.mu (km³/s²), p.R (body radius, km), and
%   p.type:
%
%     'hohmann'     alt1 → alt2: a burn at the start, one at the far apsis
%     'bielliptic'  alt1 → altB → alt2: three burns
%     'plane'       a pure plane change of dInc at the start (a node)
%     'combined'    Hohmann with the plane change dInc split between its
%                   two burns (the split chosen by fminbnd)
%     'phasing'     catch a target phaseAngle ahead (or behind, < 0) on the
%                   same orbit after phasingRevs revolutions
%     'custom'      p.burns: a table or struct array with at ('time' |
%                   'periapsis' | 'apoapsis' | 'ascending' | 'descending'),
%                   value (seconds after the previous burn for 'time', else
%                   which occurrence), and prograde, normal, radial (m/s)
%
%   Altitudes in km, angles in degrees. The start is a circular orbit at
%   alt1 and inclination inc1, at its ascending node (on +x) at t = 0.
%
%   plan: burns (struct array: at, value, dv ([prograde normal radial],
%   km/s, along the velocity, the orbit normal, and outward), label),
%   dv (|Δv| per burn, km/s), total, transferTime (s, NaN when not
%   defined), target (a, e, i of the planned final orbit; km, -, deg),
%   r1, r2, inc1 (deg), split (combined: the plane change done at the
%   first burn, deg), alternatives (struct: hohmann, bielliptic,
%   separate, combined totals in km/s where they apply), and phasing
%   (target phase, deg, and rendezvous time, s).
mu = p.mu;
r1 = p.R + p.alt1;
if ~(r1 > p.R && mu > 0)
    error('maneuvers:InvalidParameter', 'The starting orbit must be above the surface.');
end
plan.r1 = r1;
plan.r2 = r1;
plan.inc1 = p.inc1;
plan.split = NaN;
plan.transferTime = NaN;
plan.phasing = struct('angle', NaN, 'time', NaN);
plan.target = struct('a', r1, 'e', 0, 'i', p.inc1);
plan.alternatives = struct('hohmann', NaN, 'bielliptic', NaN, 'separate', NaN, 'combined', NaN);
burns = struct('at', {}, 'value', {}, 'dv', {}, 'label', {});
switch lower(p.type)
    case 'hohmann'
        r2 = checkRadius(p.R + p.alt2, p.R);
        [burns, plan.transferTime] = hohmann(mu, r1, r2);
        plan.r2 = r2;
        plan.target.a = r2;
    case 'bielliptic'
        r2 = checkRadius(p.R + p.alt2, p.R);
        rb = checkRadius(p.R + p.altB, p.R);
        if rb < max(r1, r2)
            error('maneuvers:InvalidParameter', 'The intermediate apoapsis must be beyond both orbits.');
        end
        [burns, plan.transferTime] = bielliptic(mu, r1, rb, r2);
        plan.r2 = r2;
        plan.target.a = r2;
    case 'plane'
        v = sqrt(mu / r1);
        d = deg2rad(p.dInc);
        burns(1) = burn('time', 0, v * [cos(d) - 1, sin(d), 0], 'Plane change');
        plan.target.i = p.inc1 + p.dInc;
    case 'combined'
        r2 = checkRadius(p.R + p.alt2, p.R);
        total = deg2rad(p.dInc);
        cost = @(first) sum(combinedDv(mu, r1, r2, first, total - first));
        if total == 0
            first = 0;
        else
            first = fminbnd(cost, min(0, total), max(0, total), optimset('TolX', 1e-10));
        end
        [dv, a] = combinedDv(mu, r1, r2, first, total - first);
        vp = sqrt(mu * (2 / r1 - 1 / a));
        va = sqrt(mu * (2 / r2 - 1 / a));
        v1 = sqrt(mu / r1);
        v2 = sqrt(mu / r2);
        second = total - first;
        % The start is the ascending node; the far apsis is the descending
        % node, where turning the same way changes the inclination the other way.
        a2 = (r1 + r2) / 2;
        plan.transferTime = pi * sqrt(a2^3 / mu);
        [far, value] = farApsis(r1, r2, plan.transferTime);
        burns(1) = burn('time', 0, [vp * cos(first) - v1, vp * sin(first), 0], ...
            sprintf('Raise and turn %.2f°', rad2deg(first)));
        burns(2) = burn(far, value, [v2 * cos(second) - va, -v2 * sin(second), 0], ...
            sprintf('Circularize and turn %.2f°', rad2deg(second)));
        plan.split = rad2deg(first);
        plan.r2 = r2;
        plan.target.a = r2;
        plan.target.i = p.inc1 + p.dInc;
        plan.alternatives.combined = sum(dv);
    case 'phasing'
        k = round(p.phasingRevs);
        if k < 1
            error('maneuvers:InvalidParameter', 'Use at least one phasing revolution.');
        end
        n = sqrt(mu / r1^3);
        lead = deg2rad(p.phaseAngle);
        period = (2 * pi * k - lead) / (k * n);
        a = (mu * (period / (2 * pi))^2)^(1 / 3);
        if 2 * a - r1 <= p.R
            error('maneuvers:InvalidParameter', 'The phasing orbit would hit the surface: use more revolutions.');
        end
        v = sqrt(mu * (2 / r1 - 1 / a));
        v1 = sqrt(mu / r1);
        burns(1) = burn('time', 0, [v - v1, 0, 0], 'Enter the phasing orbit');
        burns(2) = burn('time', k * period, [v1 - v, 0, 0], 'Back to the circular orbit');
        plan.transferTime = k * period;
        plan.phasing = struct('angle', p.phaseAngle, 'time', k * period);
    case 'custom'
        burns = customBurns(p.burns);
    otherwise
        error('maneuvers:InvalidParameter', 'Unknown maneuver "%s".', p.type);
end
plan.burns = burns;
plan.dv = arrayfun(@(b) norm(b.dv), burns(:));
plan.total = sum(plan.dv);

% The alternatives, for the Δv budget.
if any(strcmpi(p.type, {'hohmann', 'bielliptic', 'combined'}))
    r2 = plan.r2;
    plan.alternatives.hohmann = sum(arrayfun(@(b) norm(b.dv), hohmann(mu, r1, r2)));
    rb = p.R + p.altB;
    if rb > max(r1, r2)          % else there is no bi-elliptic transfer (it would be the Hohmann)
        plan.alternatives.bielliptic = sum(arrayfun(@(b) norm(b.dv), bielliptic(mu, r1, rb, r2)));
    end
    if p.dInc ~= 0
        planeAtTop = 2 * sqrt(mu / max(r1, r2)) * sin(abs(deg2rad(p.dInc)) / 2);
        plan.alternatives.separate = plan.alternatives.hohmann + planeAtTop;
        if isnan(plan.alternatives.combined)
            plan.alternatives.combined = plan.alternatives.separate;
        end
    end
end
end

% ----------------------------------------------------------------- plans
function [burns, time] = hohmann(mu, r1, r2)
a = (r1 + r2) / 2;
v1 = sqrt(mu / r1);
v2 = sqrt(mu / r2);
vp = sqrt(mu * (2 / r1 - 1 / a));
va = sqrt(mu * (2 / r2 - 1 / a));
time = pi * sqrt(a^3 / mu);
[far, value] = farApsis(r1, r2, time);
burns = [burn('time', 0, [vp - v1, 0, 0], 'Transfer burn'), ...
    burn(far, value, [v2 - va, 0, 0], 'Circularize')];
end

function [at, value] = farApsis(r1, r2, halfPeriod)
% Trigger of the second burn of a transfer: the far apsis. Between orbits
% of (nearly) the same radius the transfer orbit is circular and has no
% apsis to find, so the burn waits half a revolution instead.
if abs(r2 - r1) <= 1e-9 * r1
    [at, value] = deal('time', halfPeriod);
elseif r2 < r1
    [at, value] = deal('periapsis', 1);
else
    [at, value] = deal('apoapsis', 1);
end
end

function [burns, time] = bielliptic(mu, r1, rb, r2)
a1 = (r1 + rb) / 2;
a2 = (rb + r2) / 2;
v1 = sqrt(mu / r1);
v2 = sqrt(mu / r2);
burns = [burn('time', 0, [sqrt(mu * (2 / r1 - 1 / a1)) - v1, 0, 0], 'Raise apoapsis to r_b'), ...
    burn('apoapsis', 1, [sqrt(mu * (2 / rb - 1 / a2)) - sqrt(mu * (2 / rb - 1 / a1)), 0, 0], ...
        'Raise periapsis to r₂'), ...
    burn('periapsis', 1, [v2 - sqrt(mu * (2 / r2 - 1 / a2)), 0, 0], 'Circularize')];
time = pi * (sqrt(a1^3 / mu) + sqrt(a2^3 / mu));
end

function [dv, a] = combinedDv(mu, r1, r2, first, second)
% |Δv| of the two burns when each also turns the plane (law of cosines).
a = (r1 + r2) / 2;
v1 = sqrt(mu / r1);
v2 = sqrt(mu / r2);
vp = sqrt(mu * (2 / r1 - 1 / a));
va = sqrt(mu * (2 / r2 - 1 / a));
dv = [sqrt(v1^2 + vp^2 - 2 * v1 * vp * cos(first)), sqrt(va^2 + v2^2 - 2 * va * v2 * cos(second))];
end

function burns = customBurns(T)
if istable(T)
    T = table2struct(T);
end
burns = struct('at', {}, 'value', {}, 'dv', {}, 'label', {});
kinds = {'time', 'periapsis', 'apoapsis', 'ascending', 'descending'};
for k = 1:numel(T)
    at = lower(char(T(k).at));
    if ~any(strcmp(at, kinds))
        error('maneuvers:InvalidParameter', 'Burn %d: unknown trigger "%s".', k, at);
    end
    if ~strcmp(at, 'time') && ~(T(k).value >= 1)
        error('maneuvers:InvalidParameter', 'Burn %d: the occurrence must be at least 1.', k);
    end
    burns(k) = burn(at, T(k).value, [T(k).prograde, T(k).normal, T(k).radial] / 1000, sprintf('Burn %d', k));
end
end

function b = burn(at, value, dv, label)
b = struct('at', at, 'value', value, 'dv', dv, 'label', label);
end

function r = checkRadius(r, R)
if ~(r > R)
    error('maneuvers:InvalidParameter', 'Every orbit must be above the surface.');
end
end
