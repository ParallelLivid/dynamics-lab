function path = missionPath(start, startYaw, waypoints, speed)
%MISSIONPATH A setpoint that flies through waypoints at a cruise speed.
%   path = missionPath(start, startYaw, waypoints, speed) moves the setpoint
%   in straight lines from START (3 values, m) through each waypoint at
%   SPEED (m/s), holding at each one for its hold time. WAYPOINTS is N×5:
%   [x y z yaw hold] (m, m, m, rad, s). The heading turns the short way
%   round, evenly along each leg.
%
%   path.fcn(t) returns [x; y; z; yaw; vx; vy; vz] (the setpoint and its
%   velocity, which the controller uses as feedforward); path.times and
%   path.points (K×4 [x y z yaw]) are the corners; path.endTime is when
%   the setpoint stops at the last waypoint.
if ~(isscalar(speed) && speed > 0)
    error('quadrotor:InvalidParameter', 'The cruise speed must be positive.');
end
if isempty(waypoints) || size(waypoints, 2) ~= 5 || ~all(isfinite(waypoints), 'all')
    error('quadrotor:InvalidParameter', 'Waypoints are rows of [x y z yaw hold], at least one.');
end
if any(waypoints(:, 5) < 0)
    error('quadrotor:InvalidParameter', 'Waypoint hold times cannot be negative.');
end
n = size(waypoints, 1);
times = zeros(2 * n + 1, 1);
points = zeros(2 * n + 1, 4);
points(1, :) = [start(:)' startYaw];
yaw = startYaw;
for k = 1:n
    previous = points(2 * k - 1, :);
    yaw = yaw + mod(waypoints(k, 4) - yaw + pi, 2 * pi) - pi;        % the short way round
    target = [waypoints(k, 1:3) yaw];
    times(2 * k) = times(2 * k - 1) + norm(target(1:3) - previous(1:3)) / speed;
    points(2 * k, :) = target;
    times(2 * k + 1) = times(2 * k) + waypoints(k, 5);
    points(2 * k + 1, :) = target;
end
keep = [diff(times) > 0; true];          % zero-length legs and holds collapse
path.times = times(keep);
path.points = points(keep, :);
path.endTime = times(end - 1);
path.fcn = @(t) evaluate(t, path.times, path.points);
end

function r = evaluate(t, times, points)
k = sum(times <= t);
if k == 0
    r = [points(1, :)'; 0; 0; 0];
elseif k >= numel(times)
    r = [points(end, :)'; 0; 0; 0];
else
    span = times(k + 1) - times(k);
    rate = (points(k + 1, :) - points(k, :)) / span;
    r = [(points(k, :) + (t - times(k)) * rate)'; rate(1:3)'];
end
end
