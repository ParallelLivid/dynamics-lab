function u = uniformSequence(seed, count)
%UNIFORMSEQUENCE Reproducible numbers in [0, 1) from a seed.
%   u = dlab.physics.uniformSequence(seed, count) returns a 1×count row
%   from a linear congruential generator (Numerical Recipes constants):
%   the same sequence on every machine and MATLAB version, without
%   touching the global random state. Used where a seed must always give
%   the same scene (collision starts, random roads).
state = mod(round(abs(seed)) * 2654435761 + 12345, 2^32);
u = zeros(1, count);
for k = 1:count
    state = mod(1664525 * state + 1013904223, 2^32);
    u(k) = state / 2^32;
end
end
