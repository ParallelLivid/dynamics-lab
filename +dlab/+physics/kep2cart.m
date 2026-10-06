function [position,velocity] = kep2cart(a,e,inc,raan,argPeriapsis,trueAnomaly,mu)
%KEP2CART Position and velocity (row vectors) from classical orbital elements.
%   [r, v] = dlab.physics.kep2cart(a, e, i, RAAN, argp, nu, mu)
%   Angles in radians; a, r in length units consistent with mu
%   (e.g. km and km³/s²). Elliptic orbits (0 <= e < 1).
p = a*(1-e^2);
radius = p/(1+e*cos(trueAnomaly));
perifocalPosition = radius*[cos(trueAnomaly);sin(trueAnomaly);0];
perifocalVelocity = sqrt(mu/p)*[-sin(trueAnomaly);e+cos(trueAnomaly);0];

cosRaan = cos(raan); sinRaan = sin(raan);
cosInc = cos(inc); sinInc = sin(inc);
cosArg = cos(argPeriapsis); sinArg = sin(argPeriapsis);
rotation = [
    cosRaan*cosArg-sinRaan*sinArg*cosInc, -cosRaan*sinArg-sinRaan*cosArg*cosInc, sinRaan*sinInc;
    sinRaan*cosArg+cosRaan*sinArg*cosInc, -sinRaan*sinArg+cosRaan*cosArg*cosInc, -cosRaan*sinInc;
    sinArg*sinInc, cosArg*sinInc, cosInc];
position = (rotation*perifocalPosition).';
velocity = (rotation*perifocalVelocity).';
end
