function [dstate, rotation, command] = dynamics(time, state, control, aircraft, wind, autopilot)
%DYNAMICS Evaluate the rigid-body equations in body and NED axes.
%   Each control (throttle, elevator, aileron, rudder) is a number or a
%   function of time, @(t) value, for inputs that change during the run.
%
%   12 states: u v w, p q r, Euler angles φ θ ψ, and north/east/down.
%   13 states: the same with a unit quaternion [q0 q1 q2 q3] (scalar
%   first, body to NED) in place of the Euler angles, which has no
%   singularity at θ = ±90°. Its norm is held at 1 by a small correction.
%
%   Optional WIND (steady; see windAt): u, v, w stay the velocity over the
%   ground, and the aerodynamics use the velocity relative to the air.
%
%   Optional AUTOPILOT (see autopilotLaw), when its field active is true:
%   the state then ends with two more entries, the integrals of the
%   altitude and speed errors, and the controls are the pilot's inputs
%   plus the autopilot's corrections. COMMAND returns the controls applied
%   ([throttle elevator aileron rudder]).

    useAutopilot = nargin >= 6 && ~isempty(autopilot) && autopilot.active;
    extra = 2 * useAutopilot;                     % integral states at the end
    u = state(1); v = state(2); w = state(3);
    p = state(4); q = state(5); r = state(6);
    useQuaternion = numel(state) - extra == 13;
    if useQuaternion
        attitude = state(7:10);
        rotation = dlab.physics.Quaternion.toDcm(attitude);
        down = state(13);
    else
        phi = state(7); theta = state(8); psi = state(9);
        rotation = dlab.physics.eulerToDcm(phi, theta, psi);
        down = state(12);
    end

    m = aircraft.m;
    Ix = aircraft.Ix; Iy = aircraft.Iy; Iz = aircraft.Iz;
    velocityBody = [u; v; w];
    airBody = velocityBody;
    if nargin >= 5 && ~isempty(wind) && (wind.speed ~= 0 || wind.vertical ~= 0)
        airBody = velocityBody - rotation.' * dlab.sims.flight6dof.windAt(wind, max(-down, 0));
    end
    airspeed = norm(airBody);
    if airspeed > eps
        beta = asin(max(min(airBody(2) / airspeed, 1), -1));
    else
        beta = 0;
    end

    alpha = atan2(airBody(3), airBody(1));
    alphaLimit = deg2rad(60);
    alphaEffective = alphaLimit * tanh(alpha / alphaLimit);
    % The wing's α-dependent forces come from the chordwise flow (u, w):
    % weighted by its share of the dynamic pressure, cos²β. Flying sideways
    % (|β| → 90°) α becomes the angle of a vanishing vector and jumps
    % about; the weight takes those terms smoothly to zero instead. It is 1
    % without sideslip, and flat there, so trim and the linear model are
    % unchanged.
    chordwise = (airBody(1)^2 + airBody(3)^2) / max(airBody.' * airBody, realmin);
    liftCoefficient = chordwise * aircraft.CLmax * ...
        tanh(aircraft.CLa * alphaEffective / aircraft.CLmax);
    dragCoefficient = aircraft.CD0 + chordwise * aircraft.CDa2 * alphaEffective^2;

    altitude = max(-down, 0);
    density = dlab.physics.atmosphere(altitude);     % ISA 1976

    dynamicArea = 0.5 * density * airspeed^2 * aircraft.S;
    lift = dynamicArea * liftCoefficient;
    drag = dynamicArea * dragCoefficient;

    if airspeed > eps
        dragForce = -drag * airBody / airspeed;
    else
        dragForce = zeros(3, 1);
    end
    liftDirection = [sin(alpha); 0; -cos(alpha)];
    aeroForce = dragForce + lift * liftDirection;

    if useQuaternion
        gravityForce = m * 9.81 * (rotation.' * [0; 0; 1]);
    else
        gravityForce = m * 9.81 * [
            -sin(theta);
            sin(phi) * cos(theta);
            cos(phi) * cos(theta)];
    end
    velocityNed = rotation * velocityBody;
    if useAutopilot
        [command, integralRates] = dlab.sims.flight6dof.autopilotLaw(time, [p; q; r], rotation, -down, ...
            -velocityNed(3), airspeed, state(end-1:end), control, autopilot);
    else
        command = [controlValue(control.throttle, time), controlValue(control.elevator, time), ...
            controlValue(control.aileron, time), controlValue(control.rudder, time)];
    end
    thrustForce = [aircraft.Tmax * command(1); 0; 0];
    totalForce = aeroForce + gravityForce + thrustForce;

    du = totalForce(1) / m + r*v - q*w;
    dv = totalForce(2) / m + p*w - r*u;
    dw = totalForce(3) / m + q*u - p*v;

    rollMoment = aircraft.Kctrl * command(3);
    pitchMoment = aircraft.Kctrl * command(2);
    yawMoment = aircraft.Kctrl * command(4);
    dp = (rollMoment + (Iy - Iz)*q*r) / Ix ...
        - aircraft.damp_p*p - aircraft.roll_beta*beta;
    dq = (pitchMoment + (Iz - Ix)*p*r) / Iy ...
        - aircraft.damp_q*q ...
        - aircraft.pitch_alpha*chordwise*(alphaEffective - aircraft.alpha_trim);
    dr = (yawMoment + (Ix - Iy)*p*q) / Iz ...
        - aircraft.damp_r*r + aircraft.yaw_beta*beta;

    if useQuaternion
        normError = 1 - attitude.' * attitude;
        attitudeRates = dlab.physics.Quaternion.derivative(attitude, [p; q; r]) + normError * attitude;
    else
        attitudeRates = dlab.physics.eulerRates(p, q, r, phi, theta);
    end
    dstate = [du; dv; dw; dp; dq; dr; attitudeRates; velocityNed];
    if useAutopilot
        dstate = [dstate; integralRates];
    end
end

function value = controlValue(control, time)
if isa(control, 'function_handle')
    value = control(time);
else
    value = control;
end
end
