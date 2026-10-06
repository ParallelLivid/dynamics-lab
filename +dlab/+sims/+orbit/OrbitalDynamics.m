function dynamics = OrbitalDynamics()
%ORBITALDYNAMICS Two-body dynamics and coordinate conversions.
%   The element conversions live in the shared dlab.physics library.
dynamics.eomTwoBody = @eomTwoBody;
dynamics.evtAltitude = @evtAltitude;
dynamics.kep2cart = @kep2cart;
dynamics.cart2kep = @cart2kep;
end

function derivative = eomTwoBody(~,state,mu)
position = state(1:3);
velocity = state(4:6);
derivative = [velocity;-mu/norm(position)^3*position];
end

function [value,terminate,direction] = evtAltitude(~,state,radius)
value = norm(state(1:3))-radius;
terminate = 1;
direction = -1;
end

function [position,velocity] = kep2cart(a,e,inc,raan,argPeriapsis,trueAnomaly,mu)
[position,velocity] = dlab.physics.kep2cart(a,e,inc,raan,argPeriapsis,trueAnomaly,mu);
end

function elements = cart2kep(position,velocity,mu)
elements = dlab.physics.cart2kep(position,velocity,mu);
end
