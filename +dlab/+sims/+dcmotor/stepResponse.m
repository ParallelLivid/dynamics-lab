function s = stepResponse(t, y, window)
%STEPRESPONSE Rise time, overshoot, and settling of a step response.
%   s = stepResponse(t, y, [t0 t1]) for samples y(t) of a response to a
%   step at t0, looked at up to t1 (the end of the run, or a later
%   disturbance). The change is measured from y0 = y(t0) to the final value
%   yf = y(t1), as MATLAB's stepinfo does. Fields (s, % of the change):
%
%     rise       from 10 % to 90 % of the change
%     t63        from t0 to 63.2 % of the change (the time constant of a
%                first-order response)
%     overshoot  100 · max(0, the largest excursion past yf) / |yf − y0|
%     settling   from t0 until y stays within 2 % of the change around yf
%     final, initial
%
%   Times are interpolated between samples. They are NaN when the response
%   does not change (or never reaches the level).
t = t(:);
y = y(:);
t0 = window(1);
t1 = min(window(2), t(end));
inside = t >= t0 & t <= t1;
s = struct('rise', NaN, 't63', NaN, 'overshoot', NaN, 'settling', NaN, 'final', NaN, 'initial', NaN);
if nnz(inside) < 3
    return
end
tw = t(inside);
yw = y(inside);
y0 = interp1(t, y, t0);
yf = yw(end);
change = yf - y0;
s.initial = y0;
s.final = yf;
if ~(abs(change) > 1e-9 * max(1, max(abs(yw))))
    return
end
f = (yw - y0) / change;                        % 0 at the start, 1 at the end
s.rise = crossing(tw, f, 0.9) - crossing(tw, f, 0.1);
s.t63 = crossing(tw, f, 1 - exp(-1)) - t0;
s.overshoot = 100 * max(0, max(f) - 1);
outside = find(abs(f - 1) > 0.02, 1, 'last');
if isempty(outside)
    s.settling = 0;
elseif outside == numel(tw)
    s.settling = NaN;
else
    % Interpolate where it last enters the band.
    a = outside;
    level = 1 + 0.02 * sign(f(a) - 1);
    s.settling = tw(a) + (tw(a + 1) - tw(a)) * (level - f(a)) / (f(a + 1) - f(a)) - t0;
end
end

function tc = crossing(t, f, level)
% First time f reaches LEVEL (rising), linearly interpolated.
k = find(f >= level, 1);
if isempty(k)
    tc = NaN;
elseif k == 1
    tc = t(1);
else
    tc = t(k - 1) + (t(k) - t(k - 1)) * (level - f(k - 1)) / (f(k) - f(k - 1));
end
end
