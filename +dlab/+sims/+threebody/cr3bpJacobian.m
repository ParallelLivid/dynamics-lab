function A = cr3bpJacobian(mu, point)
%CR3BPJACOBIAN The exact linearization of cr3bpRhs at rest at POINT
%   ([x y z], e.g. a Lagrange point): ds/dt ≈ A (s − s₀) for
%   s = [x y z vx vy vz]. Uses the second derivatives of Ω, so L4/L5's
%   purely imaginary eigenvalues come out without finite-difference noise.
x = point(1);
y = point(2);
z = point(3);
d1 = [x + mu, y, z];
d2 = [x - 1 + mu, y, z];
r1 = norm(d1);
r2 = norm(d2);
k1 = (1 - mu) / r1^3;
k2 = mu / r2^3;
H = -(k1 + k2) * eye(3) + 3 * (1 - mu) * (d1' * d1) / r1^5 + 3 * mu * (d2' * d2) / r2^5;
H(1:2, 1:2) = H(1:2, 1:2) + eye(2);             % the centrifugal ½(x² + y²)
Coriolis = [0 2 0; -2 0 0; 0 0 0];
A = [zeros(3), eye(3); H, Coriolis];
end
