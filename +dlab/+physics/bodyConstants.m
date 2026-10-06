function constants = bodyConstants(name)
%BODYCONSTANTS Physical constants of the Sun, the planets, and the Moon.
%   c = dlab.physics.bodyConstants("Earth") returns a struct with
%     mu          gravitational parameter (km³/s²)
%     radius      mean radius (km; for the giant planets the equatorial
%                 radius at 1 bar)
%     J2Radius    the reference radius of J2 (km): the equatorial radius
%                 the coefficient is defined with (Earth 6378.137 km)
%     spinRate    sidereal rotation rate (rad/s)
%     tilt        axial tilt (deg)
%     J2          oblateness coefficient
%     g0          surface gravity mu/radius² (m/s²)
%     atmosphere  true when the body has a substantial atmosphere
%     semiMajor   mean orbital radius: the semi-major axis of its orbit
%                 about the Sun, or the Earth for the Moon (km; NaN, Sun)
%     orbitSpeed  mean orbital speed (km/s; NaN for the Sun)
%   c = dlab.physics.bodyConstants() returns every body as fields of one
%   struct; dlab.physics.bodyConstants("names") returns the names.
%
%   Physical constants only (no display colors): orbit, maneuver,
%   rocket, and flyby models share them. Orbital radii and speeds: NASA
%   Planetary Fact Sheet (D. R. Williams, NASA Goddard Space Flight Center,
%   nssdc.gsfc.nasa.gov/planetary/factsheet), semi-major axis (10⁶ km) and
%   mean orbital velocity (km/s).
persistent catalog
if isempty(catalog)
    catalog = buildTable();
end
if nargin == 0
    constants = catalog;
    return
end
name = string(name);
if name == "names"
    constants = string(fieldnames(catalog))';
    return
end
if ~isfield(catalog, name)
    error("dlab:physics:body", "Unknown body ""%s"".", name);
end
constants = catalog.(name);
end

function catalog = buildTable()
names = ["Mercury" "Venus" "Earth" "Moon" "Mars" "Jupiter" "Saturn" "Uranus" "Neptune" "Sun"];
mu = [22032.09, 324858.6, 398600.4418, 4902.8, 42828.30, ...
    126686534, 37931187, 5793966, 6836529, 1.327124e11];
radius = [2439.7, 6051.8, 6371, 1737.4, 3389.5, 71492, 60268, 25559, 24764, 695700];
J2Radius = [2440.5, 6051.8, 6378.137, 1738.0, 3396.19, 71492, 60268, 25559, 24764, 695700];
spinRate = [1.2399e-6, 2.9924e-7, 7.2921150e-5, 2.6617e-6, ...
    7.0882e-5, 1.7585e-4, 1.6378e-4, 1.0124e-4, 1.0834e-4, 2.8653e-6];
tilt = [.034, 177.4, 23.44, 6.68, 25.19, 3.13, 26.73, 97.77, 28.32, 7.25];
J2 = [5.03e-5, 4.458e-6, 1.08263e-3, 2.034e-4, 1.96045e-3, ...
    1.4736e-2, 1.6298e-2, 3.343e-3, 3.411e-3, 2.0e-7];
hasAtmosphere = [false true true false true true true true true true];
semiMajor = [57.909 108.210 149.598 0.3844 227.956 778.479 1432.041 2867.043 4514.953 NaN] * 1e6;
orbitSpeed = [47.36 35.02 29.78 1.022 24.07 13.06 9.68 6.80 5.43 NaN];
catalog = struct();
for k = 1:numel(names)
    catalog.(names(k)) = struct("mu", mu(k), "radius", radius(k), "spinRate", spinRate(k), ...
        "tilt", tilt(k), "J2", J2(k), "J2Radius", J2Radius(k), "g0", 1000 * mu(k) / radius(k)^2, ...
        "atmosphere", hasAtmosphere(k), "semiMajor", semiMajor(k), "orbitSpeed", orbitSpeed(k));
end
end
