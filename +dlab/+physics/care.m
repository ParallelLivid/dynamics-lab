function [X, ok, residual] = care(A, B, Q, R)
%CARE Stabilizing solution of the continuous algebraic Riccati equation.
%   [X, ok, residual] = dlab.physics.care(A, B, Q, R) solves
%
%       Aᵀ X + X A − X B R⁻¹ Bᵀ X + Q = 0
%
%   for the symmetric X that makes A − B R⁻¹ Bᵀ X stable, using the
%   matrix sign function of the Hamiltonian matrix, whose stable invariant
%   subspace gives X. A stands in for the Control System Toolbox's care,
%   which Dynamics Lab cannot use.
%
%   OK is true when the relative residual is below 1e-8 and every
%   closed-loop eigenvalue has a negative real part. Errors with
%   dlab:physics:care when no stabilizing solution exists (for example,
%   an unstabilizable pair or eigenvalues on the imaginary axis).
n = size(A, 1);
if ~isequal(size(A), [n n]) || size(B, 1) ~= n || ~isequal(size(Q), [n n]) ...
        || ~isequal(size(R), [size(B, 2) size(B, 2)])
    error("dlab:physics:care", "care: A (n×n), B (n×m), Q (n×n), and R (m×m) must agree.");
end
Q = (Q + Q.') / 2;
R = (R + R.') / 2;
G = B * (R \ B.');
H = [A, -G; -Q, -A.'];
if nnz(real(eig(H)) < 0) ~= n
    error("dlab:physics:care", ...
        "No stabilizing solution: the pair (A, B) is not stabilizable, or (A, Q) has unobservable modes on the imaginary axis.");
end
% Matrix sign function by the scaled Newton iteration (Byers, 1987). The
% stable invariant subspace of H is the null space of sign(H) + I, which
% gives X from [W12; W22 + I] X = −[W11 + I; W21].
W = H;
for iteration = 1:100
    scale = abs(det(W))^(-1 / (2 * n));
    if ~isfinite(scale) || scale <= 0
        scale = 1;
    end
    next = (scale * W + inv(scale * W)) / 2;
    converged = norm(next - W, 1) <= 1e-13 * norm(next, 1);
    W = next;
    if converged
        break
    end
end
I = eye(n);
lhs = [W(1:n, n+1:end); W(n+1:end, n+1:end) + I];
rhs = -[W(1:n, 1:n) + I; W(n+1:end, 1:n)];
if rank(lhs) < n
    error("dlab:physics:care", "No stabilizing solution: the Riccati subspace is singular.");
end
X = lhs \ rhs;
X = (X + X.') / 2;

residual = norm(A.' * X + X * A - X * G * X + Q, 1) / max(norm(Q, 1), 1);
closedLoop = eig(A - G * X);
ok = residual < 1e-8 && all(real(closedLoop) < 0);
end
