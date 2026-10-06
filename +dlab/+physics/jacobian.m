function J = jacobian(f, x, options)
%JACOBIAN Central-difference Jacobian of a vector function.
%   J = dlab.physics.jacobian(f, x) for f: R^n → R^m returns the m×n
%   matrix of partial derivatives at x. The step for x(k) is
%   RelStep * max(|x(k)|, Scale(k)).
%
%   Options: RelStep (default 1e-6), Scale (n×1 typical magnitudes,
%   default 1).
arguments
    f function_handle
    x (:,1) double
    options.RelStep (1,1) double {mustBePositive} = 1e-6
    options.Scale (:,1) double {mustBePositive} = 1
end
n = numel(x);
scale = options.Scale;
if isscalar(scale)
    scale = repmat(scale, n, 1);
end
f0 = f(x);
J = zeros(numel(f0), n);
for k = 1:n
    h = options.RelStep * max(abs(x(k)), scale(k));
    step = zeros(n, 1);
    step(k) = h;
    J(:, k) = (f(x + step) - f(x - step)) / (2 * h);
end
end
