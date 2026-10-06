function x = modalResponse(A, x0, t)
%MODALRESPONSE Free response of a linear system dx/dt = A x.
%   x = dlab.physics.modalResponse(A, x0, t) returns x(t) = exp(A t) x0 at
%   the times t, one row per time (like ode45). Uses the eigenvectors of
%   A (a sum of modes, exact and fast); falls back to expm at each time
%   when the eigenvectors are nearly dependent (critical damping).
x0 = x0(:);
t = t(:);
[V, D] = eig(A);
lambda = diag(D);
if rcond(V) > 1e-10
    coefficients = V \ x0;
    x = real(exp(t * lambda.') .* coefficients.' * V.');
else
    x = zeros(numel(t), numel(x0));
    for k = 1:numel(t)
        x(k, :) = (expm(A * t(k)) * x0).';
    end
end
end
