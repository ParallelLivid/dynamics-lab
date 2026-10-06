function C = jacobi(mu, state)
%JACOBI Jacobi constant C = 2Ω − v² of CR3BP states (rows [x y z vx vy vz]),
%   Ω = ½(x² + y²) + (1 − μ)/r₁ + μ/r₂.
x = state(:, 1);
y = state(:, 2);
z = state(:, 3);
r1 = sqrt((x + mu).^2 + y.^2 + z.^2);
r2 = sqrt((x - 1 + mu).^2 + y.^2 + z.^2);
C = x.^2 + y.^2 + 2 * (1 - mu) ./ r1 + 2 * mu ./ r2 - sum(state(:, 4:6).^2, 2);
end
