function [sol, errMsg] = pendulum_solve(L, m, b, theta0Deg, omega0, g, duration, dtOut, progressFcn)
%PENDULUM_SOLVE Solve a damped nonlinear pendulum at requested output times.
%   Optional PROGRESSFCN: @(fraction) stop, called as the solver advances;
%   returning true stops the integration early (the result is then partial).

sol = [];
errMsg = '';

try
    validateattributes(L, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'L');
    validateattributes(m, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'm');
    validateattributes(b, {'numeric'}, {'real','finite','scalar','nonnegative'}, mfilename, 'b');
    validateattributes(theta0Deg, {'numeric'}, {'real','finite','scalar'}, mfilename, 'theta0Deg');
    validateattributes(omega0, {'numeric'}, {'real','finite','scalar'}, mfilename, 'omega0');
    validateattributes(g, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'g');
    validateattributes(duration, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'duration');
    validateattributes(dtOut, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'dtOut');

    t = (0:dtOut:duration)';
    if t(end) < duration
        t(end + 1, 1) = duration;
    else
        t(end) = duration;
    end

    dampingRate = b / (m * L^2);
    naturalFrequency = sqrt(g / L);
    solver = @ode45;
    if dampingRate > 20 * naturalFrequency
        solver = @ode15s;
    end

    theta0 = deg2rad(theta0Deg);
    options = odeset('RelTol', 1e-9, 'AbsTol', 1e-11);
    if nargin >= 9 && ~isempty(progressFcn)
        options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(progressFcn, [0 duration]));
    end
    integration = solver(@(~, y) pendulumODE(y, dampingRate, g / L), ...
                         [0 duration], [theta0; omega0], options);
    state = deval(integration, t).';
catch exception
    errMsg = exception.message;
    return
end

theta = state(:, 1);
omega = state(:, 2);

sol.t = t;
sol.theta = theta;
sol.omega = omega;
sol.thetaDeg = rad2deg(theta);
sol.KE = 0.5 * m * (L * omega).^2;
sol.PE = m * g * L * (1 - cos(theta));
sol.E = sol.KE + sol.PE;
sol.bx = L * sin(theta);
sol.by = -L * cos(theta);
end

function derivative = pendulumODE(state, dampingRate, gravityOverLength)
derivative = [state(2); ...
             -dampingRate * state(2) - gravityOverLength * sin(state(1))];
end
