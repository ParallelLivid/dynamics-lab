function elements = cart2kep(position,velocity,mu)
%CART2KEP Classical orbital elements from position and velocity.
%   elements = dlab.physics.cart2kep(r, v, mu) returns
%   [a, e, i, RAAN, argp, nu] with angles in radians in [0, 2π).
%   a is Inf for a parabolic trajectory and negative for a hyperbola.
%   Equatorial orbits use RAAN = 0 and measure periapsis from +X;
%   circular orbits use argp = 0 and the orbital phase as nu.
position = position(:);
velocity = velocity(:);
radius = norm(position);
speed = norm(velocity);
angularMomentum = cross(position,velocity);
angularMomentumMagnitude = norm(angularMomentum);
eccentricityVector = cross(velocity,angularMomentum)/mu-position/radius;
eccentricity = norm(eccentricityVector);

energy = 0.5*speed^2-mu/radius;
energyTolerance = 10*eps(mu/radius);
if abs(energy) <= energyTolerance
    semiMajorAxis = Inf;
else
    semiMajorAxis = -mu/(2*energy);
end

inclination = atan2(norm(angularMomentum(1:2)),angularMomentum(3));
node = cross([0;0;1],angularMomentum);
nodeMagnitude = norm(node);
if angularMomentumMagnitude == 0
    elements = [semiMajorAxis,eccentricity,NaN,NaN,NaN,NaN];
    return
end
normal = angularMomentum/angularMomentumMagnitude;
if nodeMagnitude > 1e-12*angularMomentumMagnitude
    raan = wrap(atan2(node(2),node(1)));
    reference = node/nodeMagnitude;
else
    raan = 0;
    reference = [1;0;0];
end

% Equatorial orbits use periapsis longitude; circular orbits use orbital phase.
if eccentricity > 1e-10
    periapsis = eccentricityVector/eccentricity;
    argPeriapsis = orientedAngle(reference,periapsis,normal);
    trueAnomaly = orientedAngle(periapsis,position/radius,normal);
else
    argPeriapsis = 0;
    trueAnomaly = orientedAngle(reference,position/radius,normal);
end
elements = [semiMajorAxis,eccentricity,inclination,raan,argPeriapsis,trueAnomaly];
end

function angle = orientedAngle(first,second,normal)
angle = wrap(atan2(dot(normal,cross(first,second)),dot(first,second)));
end

function angle = wrap(angle)
% Into [0, 2π): mod of a tiny negative angle rounds to 2π itself, which
% read as 360° for an orbit that starts at 0°.
angle = mod(angle,2*pi);
if angle >= 2*pi - 4*eps(2*pi)
    angle = 0;
end
end
