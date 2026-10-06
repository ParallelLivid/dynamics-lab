function rates = eulerRates(p, q, r, phi, theta)
%EULERRATES 3-2-1 Euler angle rates from body angular rates.
%   rates = dlab.physics.eulerRates(p, q, r, phi, theta) returns
%   [dphi; dtheta; dpsi] (rad/s). Singular at theta = ±90°.
arguments
    p (1,1) double
    q (1,1) double
    r (1,1) double
    phi (1,1) double
    theta (1,1) double
end
dphi = p + (q*sin(phi) + r*cos(phi)) * tan(theta);
dtheta = q*cos(phi) - r*sin(phi);
dpsi = (q*sin(phi) + r*cos(phi)) / cos(theta);
rates = [dphi; dtheta; dpsi];
end
