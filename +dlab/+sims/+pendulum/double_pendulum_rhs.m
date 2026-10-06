function d = double_pendulum_rhs(y, c)
%DOUBLE_PENDULUM_RHS State derivative of the damped double pendulum.
%   d = double_pendulum_rhs([θ1; θ2; ω1; ω2], c) with c.L1, c.L2, c.m1,
%   c.m2, c.b, c.g. Lagrange's equations M(θ) ω̇ = f(θ, ω):
%
%     M = [(m1+m2) L1²           m2 L1 L2 cos(θ1−θ2)
%          m2 L1 L2 cos(θ1−θ2)   m2 L2²             ]
%     f = [−m2 L1 L2 sin(θ1−θ2) ω2² − (m1+m2) g L1 sin θ1 − b ω1 + b (ω2−ω1)
%           m2 L1 L2 sin(θ1−θ2) ω1² − m2 g L2 sin θ2      − b (ω2−ω1)       ]
%
%   Joint damping b acts at the pivot (on ω1) and at the elbow (on ω2−ω1).
t1 = y(1); t2 = y(2); w1 = y(3); w2 = y(4);
s = sin(t1 - t2);
k = cos(t1 - t2);
M11 = (c.m1 + c.m2) * c.L1^2;
M12 = c.m2 * c.L1 * c.L2 * k;
M22 = c.m2 * c.L2^2;
f1 = -c.m2 * c.L1 * c.L2 * s * w2^2 - (c.m1 + c.m2) * c.g * c.L1 * sin(t1) - c.b * w1 + c.b * (w2 - w1);
f2 = c.m2 * c.L1 * c.L2 * s * w1^2 - c.m2 * c.g * c.L2 * sin(t2) - c.b * (w2 - w1);
determinant = M11 * M22 - M12^2;
d = [w1; w2; (M22 * f1 - M12 * f2) / determinant; (M11 * f2 - M12 * f1) / determinant];
end
