function ds = dynamics(s, F, p)
%DYNAMICS Cart-pole state derivative. S = [x; ẋ; θ; θ'] (θ from upright,
%   positive leaning toward +x), F the horizontal force on the cart (N),
%   and P with M, m, l (pivot to centre of mass), I (pole inertia about its
%   centre of mass), b (cart friction, N·s/m), g:
%
%     ẍ = [(I + m l²)(F − b ẋ + m l θ'² sin θ) − m² l² g sin θ cos θ] / D
%     θ'' = [(M + m) m g l sin θ − m l cos θ (F − b ẋ + m l θ'² sin θ)] / D
%     D = (M + m)(I + m l²) − m² l² cos² θ
xd = s(2);
theta = s(3);
thetad = s(4);
c = cos(theta);
sn = sin(theta);
J = p.I + p.m * p.l^2;
D = (p.M + p.m) * J - (p.m * p.l * c)^2;
push = F - p.b * xd + p.m * p.l * thetad^2 * sn;
xdd = (J * push - p.m^2 * p.l^2 * p.g * sn * c) / D;
thetadd = ((p.M + p.m) * p.m * p.g * p.l * sn - p.m * p.l * c * push) / D;
ds = [xd; xdd; thetad; thetadd];
end
