function acceleration = gravity(position, mu, options)
%GRAVITY Gravitational acceleration of a central body.
%   a = dlab.physics.gravity(r, mu)                      point mass
%   a = dlab.physics.gravity(r, mu, J2=1.08263e-3, Radius=6378.137)
%                                                        plus J2 oblateness
%
%   r is a 3×1 position in a body-centred frame whose z axis is the spin
%   axis; units follow mu (km and km³/s² give km/s²). Returns 3×1.
arguments
    position (3,1) double
    mu (1,1) double {mustBePositive}
    options.J2 (1,1) double = 0
    options.Radius (1,1) double {mustBeNonnegative} = 0
end
r = norm(position);
acceleration = -mu / r^3 * position;
if options.J2 ~= 0
    [x, y, z] = deal(position(1), position(2), position(3));
    factor = 1.5 * options.J2 * mu * options.Radius^2 / r^5;
    ratio = 5 * z^2 / r^2;
    acceleration = acceleration + factor * [x * (ratio - 1); y * (ratio - 1); z * (ratio - 3)];
end
end
