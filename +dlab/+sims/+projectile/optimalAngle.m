function best = optimalAngle(params, progressFcn)
%OPTIMALANGLE Launch angle that gives the longest range for PARAMS.
%   best = optimalAngle(params) with the same fields as projectile_physics
%   (params.theta is ignored). Returns a struct with angle (deg), range (m),
%   and result (the projectile_physics result at that angle).
%
%   Point mass: θ* = atan(v₀ / √(v₀² + 2 g h₀)) exactly, with range
%   v₀ √(v₀² + 2 g h₀) / g. With drag: a coarse scan every 5° from 5° to
%   85°, then fminbnd within ±5° of the best to 0.01°.
%
%   Optional PROGRESSFCN: @(fraction) stop. Returning true stops with the
%   error projectile:Cancelled.
if nargin < 2
    progressFcn = [];
end
if isfield(params, 'progressFcn')
    params = rmfield(params, 'progressFcn');
end
params.maxSteps = 250000;
model = validatestring(params.model, {'point', 'sphere'});
if strcmp(model, 'point')
    reach = sqrt(params.v0^2 + 2 * params.g * params.h0);
    if reach == 0
        angle = 45;
    else
        angle = atand(params.v0 / reach);
    end
    params.theta = angle;
    result = dlab.sims.projectile.projectile_physics(params);
    best = struct('angle', angle, 'range', result.range, 'result', result);
    return
end

coarse = 5:5:85;
total = numel(coarse) + 14;
count = 0;
ranges = zeros(size(coarse));
for k = 1:numel(coarse)
    ranges(k) = rangeAt(coarse(k));
end
[~, i] = max(ranges);
low = max(0, coarse(i) - 5);
high = min(90, coarse(i) + 5);
angle = fminbnd(@(theta) -rangeAt(theta), low, high, optimset('TolX', 0.01));
params.theta = angle;
result = dlab.sims.projectile.projectile_physics(params);
best = struct('angle', angle, 'range', result.range, 'result', result);

    function range = rangeAt(theta)
        count = count + 1;
        if ~isempty(progressFcn) && progressFcn(min(count / total, 0.99))
            error('projectile:Cancelled', 'The search for the optimal angle was cancelled.');
        end
        trial = params;
        trial.theta = theta;
        outcome = dlab.sims.projectile.projectile_physics(trial);
        range = outcome.range;
    end
end
