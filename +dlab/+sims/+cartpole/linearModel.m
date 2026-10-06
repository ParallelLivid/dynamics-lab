function [A, B] = linearModel(p)
%LINEARMODEL The cart-pole linearized about upright at rest:
%   ds/dt = A s + B F, s = [x; ẋ; θ; θ'] (see dynamics).
J = p.I + p.m * p.l^2;
D = (p.M + p.m) * J - (p.m * p.l)^2;
A = [0 1 0 0
     0 -J * p.b / D, -(p.m * p.l)^2 * p.g / D, 0
     0 0 0 1
     0 p.m * p.l * p.b / D, (p.M + p.m) * p.m * p.g * p.l / D, 0];
B = [0; J / D; 0; -p.m * p.l / D];
end
