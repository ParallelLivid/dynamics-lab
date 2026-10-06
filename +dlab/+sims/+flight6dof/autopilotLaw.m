function [command, integralRates] = autopilotLaw(time, rates, rotation, altitude, climbRate, airspeed, integrals, control, autopilot)
%AUTOPILOTLAW Controls with the autopilot's holds on top of the pilot's inputs.
%   [command, integralRates] = autopilotLaw(t, [p;q;r], R, h, hdot, V,
%   [∫e_h; ∫e_V], control, autopilot) returns command = [throttle elevator
%   aileron rudder] and the rates of the two integral states.
%
%   CONTROL holds the pilot's inputs (numbers or @(t) values): the trim
%   and any doublet. Each hold adds a correction to them:
%
%     altitude   pitch command θc = α_trim + Kh·e_h + Khi·∫e_h − Khd·ḣ
%                (limited to ±maxPitch), then elevator += Kθ(θc − θ) − Kq·q
%     heading    bank command φc = Kψ·(ψref − ψ, wrapped to ±180°)
%                (limited to ±maxBank), then aileron += Kφ(φc − φ) − Kp·p
%     speed      throttle += Kv·e_V + Kvi·∫e_V
%
%   e_h = href − h and e_V = Vref − V. The outputs are clipped to the
%   controls' ranges (throttle 0–1, the rest ±1). An integral runs only
%   near its target (|e_h| < bandH, |e_V| < bandV, the capture band) and
%   while its output is not saturated: during a large change it would
%   otherwise wind up and overshoot.
%
%   AUTOPILOT fields: altitude, heading, speed (logical holds);
%   altitudeRef (m), headingRef (deg), speedRef (m/s); gains Kh, Khi, Khd,
%   Ktheta, Kq, Kpsi, Kphi, Kp, Kv, Kvi; maxPitch, maxBank (deg); bandH (m),
%   bandV (m/s); alphaTrim (rad, the level-flight pitch).
command = [value(control.throttle, time), value(control.elevator, time), ...
    value(control.aileron, time), value(control.rudder, time)];
integralRates = [0; 0];
theta = -asin(max(min(rotation(3, 1), 1), -1));
phi = atan2(rotation(3, 2), rotation(3, 3));
psi = atan2(rotation(2, 1), rotation(1, 1));
a = autopilot;

if a.altitude
    miss = a.altitudeRef - altitude;
    pitch = a.alphaTrim + a.Kh * miss + a.Khi * integrals(1) - a.Khd * climbRate;
    limit = deg2rad(a.maxPitch);
    thetaCommand = min(max(pitch, a.alphaTrim - limit), a.alphaTrim + limit);
    elevator = command(2) + a.Ktheta * (thetaCommand - theta) - a.Kq * rates(2);
    command(2) = min(max(elevator, -1), 1);
    if abs(miss) < a.bandH && thetaCommand == pitch && command(2) == elevator
        integralRates(1) = miss;                 % captured and not saturated: integrate
    end
end
if a.heading
    miss = mod(deg2rad(a.headingRef) - psi + pi, 2 * pi) - pi;
    limit = deg2rad(a.maxBank);
    phiCommand = min(max(a.Kpsi * miss, -limit), limit);
    aileron = command(3) + a.Kphi * (phiCommand - phi) - a.Kp * rates(1);
    command(3) = min(max(aileron, -1), 1);
end
if a.speed
    miss = a.speedRef - airspeed;
    throttle = command(1) + a.Kv * miss + a.Kvi * integrals(2);
    command(1) = min(max(throttle, 0), 1);
    if abs(miss) < a.bandV && command(1) == throttle
        integralRates(2) = miss;
    end
end
end

function v = value(control, time)
if isa(control, 'function_handle')
    v = control(time);
else
    v = control;
end
end
