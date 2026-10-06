function orbit = helioOrbit(r, v, mu, rMax)
%HELIOORBIT The planar Keplerian orbit through position R (1×2, km) with
%   velocity V (1×2, km/s) about a body with parameter MU (km³/s²).
%
%   orbit: speed (km/s), energy (specific, km²/s²), a (km; Inf when
%   parabolic, negative when hyperbolic), e, h (km²/s, positive when
%   counterclockwise), perihelion and aphelion (km; aphelion Inf when
%   unbound), period (s; Inf when unbound), bound (logical), and path
%   (m×2, km): the orbit drawn out to RMAX (default: 4 |r|) from the
%   central body, from the vis-viva equation and the orbit equation
%   r = p / (1 + e cos ν).
if nargin < 4
    rMax = 4 * norm(r);
end
rn = norm(r);
v2 = v * v';
energy = v2 / 2 - mu / rn;
h = r(1) * v(2) - r(2) * v(1);
eVec = ((v2 - mu / rn) * r - (r * v') * v) / mu;
e = norm(eVec);
p = h^2 / mu;
orbit.speed = sqrt(v2);
orbit.energy = energy;
orbit.e = e;
orbit.h = h;
orbit.perihelion = p / (1 + e);
orbit.bound = energy < 0;
if orbit.bound
    orbit.a = -mu / (2 * energy);
    orbit.aphelion = p / (1 - e);
    orbit.period = 2 * pi * sqrt(orbit.a^3 / mu);
else
    orbit.a = Inf;
    if energy > 0
        orbit.a = -mu / (2 * energy);
    end
    orbit.aphelion = Inf;
    orbit.period = Inf;
end

% The path, in the orbit's own frame (ê toward perihelion).
if e < 1e-9
    eHat = r / rn;
else
    eHat = eVec / e;
end
pHat = sign(h + (h == 0)) * [-eHat(2) eHat(1)];
limit = pi;
if e >= 1
    limit = acos(-1 / e) * (1 - 1e-6);
end
reach = (p / rMax - 1) / max(e, eps);         % cos ν where r = rMax
if reach > -1 && reach < 1
    limit = min(limit, acos(reach));
end
nu = linspace(-limit, limit, 721)';
radius = p ./ (1 + e * cos(nu));
orbit.path = (radius .* cos(nu)) .* eHat + (radius .* sin(nu)) .* pHat;
end
