function [trim, info] = trim6dof(aircraft, speed, altitude, gammaDeg)
%TRIM6DOF Wings-level trim: forces and pitching moment in balance.
%   [trim, info] = trim6dof(aircraft, V, h, gamma) finds the angle of
%   attack α, throttle, and pitch-torque command (elevator) for steady
%   flight at airspeed V (m/s) and altitude h (m) along flight-path angle
%   gamma (deg; 0 = level, > 0 climbing), with no sideslip or rotation.
%   Newton's method on du/dt = dw/dt = dq/dt = 0 (dlab.physics.jacobian).
%
%   trim: u0, w0 (m/s), theta0 (deg), alpha (rad), throttle, elevator.
%   info: converged, iterations, residual. Errors (flightSim:Trim) when
%   no trim exists within the controls' range or below the stall.
if ~(isscalar(speed) && speed > 0 && isfinite(speed))
    error('flightSim:Trim', 'The trim speed must be positive.');
end
gamma = deg2rad(gammaDeg);
residual = @(z) balance(z, aircraft, speed, altitude, gamma);
z = [aircraft.alpha_trim; 0.5; 0];
r = residual(z);
for iterations = 1:50
    if norm(r) < 1e-10
        break
    end
    J = dlab.physics.jacobian(residual, z, Scale=[0.1; 1; 1]);
    step = -(J \ r);
    shrink = 1;
    while shrink > 1e-4
        candidate = z + shrink * step;
        rc = residual(candidate);
        if norm(rc) < norm(r)
            break
        end
        shrink = shrink / 2;
    end
    z = candidate;
    r = rc;
end
info = struct('converged', norm(r) < 1e-8, 'iterations', iterations, 'residual', norm(r));
[alpha, throttle, elevator] = deal(z(1), z(2), z(3));
stall = aircraft.CLmax / aircraft.CLa;
if ~info.converged
    error('flightSim:Trim', 'No trim found at %.1f m/s and %.0f m.', speed, altitude);
elseif abs(alpha) > stall
    error('flightSim:Trim', ...
        'Trim at %.1f m/s would need %.1f° angle of attack, beyond the stall (%.1f°). Fly faster.', ...
        speed, rad2deg(alpha), rad2deg(stall));
elseif throttle > 1
    error('flightSim:Trim', 'Trim at %.1f m/s needs %.0f %% throttle; try a lower speed or a descent.', ...
        speed, 100 * throttle);
elseif throttle < 0
    error('flightSim:Trim', ...
        'Trim at %.1f m/s would need negative thrust; try a steeper descent (a glide needs none).', speed);
elseif abs(elevator) > 1
    error('flightSim:Trim', 'Trim at %.1f m/s needs a pitch torque of %.2f, beyond ±1.', speed, elevator);
end
trim = struct('u0', speed * cos(alpha), 'w0', speed * sin(alpha), ...
    'theta0', rad2deg(alpha + gamma), 'alpha', alpha, 'throttle', throttle, 'elevator', elevator);
end

function r = balance(z, aircraft, speed, altitude, gamma)
% Body accelerations du, dw and pitch acceleration dq for z = [α; δt; δe].
alpha = z(1);
state = [speed * cos(alpha); 0; speed * sin(alpha); 0; 0; 0; 0; alpha + gamma; 0; 0; 0; -altitude];
control = struct('throttle', z(2), 'elevator', z(3), 'aileron', 0, 'rudder', 0);
d = dlab.sims.flight6dof.dynamics(0, state, control, aircraft);
r = d([1 3 5]);
end
