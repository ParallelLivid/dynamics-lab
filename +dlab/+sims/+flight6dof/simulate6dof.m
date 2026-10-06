function result = simulate6dof(config)
%SIMULATE6DOF Validate configuration and integrate the flight model.
%   Optional config.sim.progressFcn: @(fraction) stop; returning true
%   stops the integration early (reported like a timeout).
%   Optional config.sim.attitude: 'euler' (the default, 12 states, with the
%   pitch-limit event) or 'quaternion' (13 states, no pitch limit). Either
%   way result.state has the 12 Euler-angle columns (angles from the
%   quaternion are unwrapped); quaternion runs add result.quaternion.
%   Optional config.wind (see windAt): a steady wind. result.airspeed,
%   result.alpha, and result.beta are the air data at every sample.
%   Optional config.autopilot (see autopilotLaw), used when its field
%   active is true: altitude, heading, and speed holds on top of the
%   pilot's inputs. Either way result.controls (n×4: throttle, elevator,
%   aileron, rudder) holds the controls applied at each sample.

    validateConfig(config);
    useQuaternion = isQuaternion(config);
    wind = [];
    if isfield(config, 'wind')
        wind = config.wind;
    end
    initial = config.initial;
    attitude0 = [deg2rad(initial.phi0); deg2rad(initial.theta0); deg2rad(initial.psi0)];
    if useQuaternion
        attitude0 = dlab.physics.Quaternion.fromEuler(attitude0(1), attitude0(2), attitude0(3));
    end
    state0 = [initial.u0; initial.v0; initial.w0; ...
        initial.p0; initial.q0; initial.r0; ...
        attitude0; 0; 0; -initial.alt0];
    autopilot = [];
    if isfield(config, 'autopilot') && ~isempty(config.autopilot) && config.autopilot.active
        autopilot = config.autopilot;
        state0 = [state0; 0; 0];                     % the integrals of the altitude and speed errors
    end
    downIndex = 12 + useQuaternion;                  % the state's "down" (−altitude)
    equations = @(time, value) dlab.sims.flight6dof.dynamics(time, value, config.control, ...
        config.aircraft, wind, autopilot);

    startTime = tic;
    timedOut = false;
    options = odeset('RelTol', config.sim.RelTol, ...
        'AbsTol', config.sim.AbsTol, 'MaxStep', config.sim.MaxStep, ...
        'OutputFcn', @stopOnTimeout, 'Events', @stopEvents);
    solver = str2func(config.sim.Solver);
    [t, state, eventTime, eventState, eventIndex] = solver(equations, [0 config.duration], state0, options);

    % The controls applied, from the same law the dynamics used.
    controls = zeros(numel(t), 4);
    for k = 1:numel(t)
        [~, ~, controls(k, :)] = equations(t(k), state(k, :).');
    end
    integrals = zeros(numel(t), 0);
    if ~isempty(autopilot)
        integrals = state(:, end-1:end);
        state = state(:, 1:end-2);
        if ~isempty(eventState)
            eventState = eventState(:, 1:end-2);
        end
    end

    quaternion = [];
    if useQuaternion
        quaternion = state(:, 7:10) ./ vecnorm(state(:, 7:10), 2, 2);
        state = toEulerColumns(state, true);
        if ~isempty(eventState)
            eventState = toEulerColumns(eventState, false);
        end
    end
    result = struct('t', t, 'state', state, 'eventTime', eventTime, ...
        'eventState', eventState, 'eventIndex', eventIndex, ...
        'solveTime', toc(startTime), 'config', config);
    [result.airspeed, result.alpha, result.beta] = airData(state, wind);
    if useQuaternion
        result.quaternion = quaternion;
    end
    result.controls = controls;
    result.autopilot = autopilot;
    result.autopilotIntegrals = integrals;
    if timedOut
        result.termination = 'timeout';
    elseif isempty(eventIndex)
        result.termination = 'completed';
    elseif eventIndex(end) == 1
        result.termination = 'ground contact';
    elseif eventIndex(end) == 2
        result.termination = 'maximum airspeed';
    else
        result.termination = 'attitude limit';
    end

    function stop = stopOnTimeout(time, ~, flag)
        stop = false;
        if isempty(flag) && toc(startTime) >= config.sim.TIMEOUT
            timedOut = true;
            stop = true;
        elseif isempty(flag) && isfield(config.sim, 'progressFcn') && ~isempty(config.sim.progressFcn)
            stop = config.sim.progressFcn(time(end) / config.duration);
        end
    end

    function [value, isterminal, direction] = stopEvents(~, valueState)
        altitude = -valueState(downIndex);
        speed = norm(valueState(1:3));
        if ~isempty(wind)
            speed = airspeedOf(valueState(1:downIndex), wind);
        end
        if useQuaternion
            pitchMargin = 1;          % no attitude limit
        else
            pitchMargin = deg2rad(config.sim.attitudeLimitDeg) - abs(valueState(8));
        end
        value = [altitude - config.sim.groundAltitude; ...
            config.sim.Vmax - speed; pitchMargin];
        isterminal = [1; 1; 1];
        direction = [-1; -1; -1];
    end
end

function validateConfig(config)
    validatestring(config.sim.Solver, {'ode45','ode113'});
    validateattributes(config.duration, {'numeric'}, ...
        {'scalar','real','finite','positive'});
    validateattributes([config.aircraft.m config.aircraft.Ix ...
        config.aircraft.Iy config.aircraft.Iz config.aircraft.S], ...
        {'numeric'}, {'real','finite','positive'});
    speed0 = norm([config.initial.u0 config.initial.v0 config.initial.w0]);
    if speed0 >= config.sim.Vmax
        error('flightSim:InitialOverspeed', ...
            'Initial airspeed must be below Vmax.');
    end
    if config.initial.alt0 <= config.sim.groundAltitude
        error('flightSim:InitialAltitude', ...
            'Initial altitude must be above ground altitude.');
    end
    if ~isQuaternion(config) && abs(config.initial.theta0) >= config.sim.attitudeLimitDeg
        error('flightSim:InitialAttitude', ...
            'Initial pitch must be inside the attitude limit.');
    end
end

function tf = isQuaternion(config)
    tf = isfield(config.sim, 'attitude') && strcmpi(config.sim.attitude, 'quaternion');
end

function out = toEulerColumns(state, unwrapAngles)
% 13-column quaternion states as the 12-column Euler layout.
    n = size(state, 1);
    angles = zeros(n, 3);
    for k = 1:n
        [phi, theta, psi] = dlab.physics.Quaternion.toEuler(state(k, 7:10)');
        angles(k, :) = [phi, theta, psi];
    end
    if unwrapAngles && n > 1
        angles(:, [1 3]) = unwrap(angles(:, [1 3]));
    end
    out = [state(:, 1:6), angles, state(:, 11:13)];
end

function [airspeed, alpha, beta] = airData(state, wind)
% Air-relative speed, angle of attack, and sideslip at each sample
% (12-column Euler layout).
    n = size(state, 1);
    air = state(:, 1:3);
    if ~isempty(wind) && (wind.speed ~= 0 || wind.vertical ~= 0)
        for k = 1:n
            R = dlab.physics.eulerToDcm(state(k, 7), state(k, 8), state(k, 9));
            air(k, :) = air(k, :) - (R.' * dlab.sims.flight6dof.windAt(wind, max(-state(k, 12), 0))).';
        end
    end
    airspeed = vecnorm(air, 2, 2);
    alpha = atan2(air(:, 3), air(:, 1));
    beta = asin(max(min(air(:, 2) ./ max(airspeed, eps), 1), -1));
end

function speed = airspeedOf(state, wind)
% Airspeed of one integration state (12 or 13 columns).
    if numel(state) == 13
        R = dlab.physics.Quaternion.toDcm(state(7:10));
    else
        R = dlab.physics.eulerToDcm(state(7), state(8), state(9));
    end
    speed = norm(state(1:3) - R.' * dlab.sims.flight6dof.windAt(wind, max(-state(end), 0)));
end
