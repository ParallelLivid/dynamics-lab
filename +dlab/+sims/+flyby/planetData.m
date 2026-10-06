function data = planetData(name)
%PLANETDATA A planet's constants for a flyby: gravity, size, and orbit.
%   d = dlab.sims.flyby.planetData("Jupiter") returns a struct with
%     name       the planet's name
%     mu         gravitational parameter (km³/s²)
%     radius     mean radius (km)
%     muSun      the Sun's gravitational parameter (km³/s²)
%     a          mean orbital radius: the semi-major axis (km)
%     meanSpeed  mean orbital speed (km/s), as tabulated
%     Vp         the circular-orbit speed √(μ_Sun / a) (km/s), which the
%                model uses so the planet's orbit is an exact circle
%     rSoi       the sphere of influence a (μ / μ_Sun)^(2/5) (km)
%   dlab.sims.flyby.planetData("names") returns the planets' names.
%
%   mu, radius, a, and meanSpeed come from dlab.physics.bodyConstants.
%   The circular speed agrees with the tabulated mean speed within 1.1 %
%   (Mercury, the most eccentric) and within 0.3 % for the others.
names = ["Mercury" "Venus" "Earth" "Mars" "Jupiter" "Saturn" "Uranus" "Neptune"];
name = string(name);
if name == "names"
    data = names;
    return
end
if ~any(names == name)
    error("flyby:InvalidParameter", "Unknown planet ""%s"".", name);
end
body = dlab.physics.bodyConstants(name);
sun = dlab.physics.bodyConstants("Sun");
a = body.semiMajor;
data = struct("name", name, "mu", body.mu, "radius", body.radius, "muSun", sun.mu, "a", a, ...
    "meanSpeed", body.orbitSpeed, "Vp", sqrt(sun.mu / a), "rSoi", a * (body.mu / sun.mu)^(2/5));
end
