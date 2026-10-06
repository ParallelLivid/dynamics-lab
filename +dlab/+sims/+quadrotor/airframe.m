function [model, ctrl] = airframe(p)
%AIRFRAME The model and controller structs of a quadrotor, from engine
%   parameters (see simulateQuadrotor for the fields).
%
%   X configuration, body axes x forward, y left, z up. Rotors, numbered
%   clockwise seen from above, at (±d, ±d) with d = L/√2:
%
%     1 front-left  (+d, +d)  spins clockwise
%     2 front-right (+d, −d)  spins counter-clockwise
%     3 rear-right  (−d, −d)  spins clockwise
%     4 rear-left   (−d, +d)  spins counter-clockwise
%
%   Each rotor gives thrust Tᵢ = kf Ωᵢ² along body z and a drag torque
%   Qᵢ = km Ωᵢ² = c Tᵢ (c = km/kf) that turns the body the other way, so
%
%     [F; τx; τy; τz] = A T,   A = [ 1  1  1  1
%                                    d −d −d  d
%                                   −d −d  d  d
%                                    c −c  c −c ]
%
%   model: m, g, I (3×1 principal inertias), L, d, c, kf, km, tau, Tmax, kd,
%   A, Ainv, hoverThrust (m g / 4), hoverSpeed (rad/s), rotorPositions
%   (4×3, body), spin (+1 counter-clockwise).
%   ctrl: mode (1 position, 2 attitude, 3 off), Kp, Kd, Ki (3×1, x y z),
%   Kr, Kw (3×1, roll pitch yaw), tanTilt, band, iLimit, offThrust (N).
d = p.L / sqrt(2);
c = p.km / p.kf;
A = [1 1 1 1; d -d -d d; -d -d d d; c -c c -c];
model = struct('m', p.m, 'g', p.g, 'I', [p.Ixx; p.Iyy; p.Izz], 'L', p.L, 'd', d, 'c', c, ...
    'kf', p.kf, 'km', p.km, 'tau', p.tauMotor, 'Tmax', p.Tmax, 'kd', p.kd, 'A', A, 'Ainv', A \ eye(4), ...
    'hoverThrust', p.m * p.g / 4, 'hoverSpeed', sqrt(p.m * p.g / 4 / p.kf), ...
    'rotorPositions', d * [1 1 0; 1 -1 0; -1 -1 0; -1 1 0], 'spin', [-1; 1; -1; 1]);
modes = {'position', 'attitude', 'off'};
mode = find(strcmpi(char(p.controller), modes), 1);
if isempty(mode)
    error('quadrotor:InvalidParameter', 'Unknown controller "%s" (position, attitude, or off).', ...
        char(p.controller));
end
Ki = [p.KiXY; p.KiXY; p.KiZ];
ctrl = struct('mode', mode, 'Kp', [p.KpXY; p.KpXY; p.KpZ], 'Kd', [p.KdXY; p.KdXY; p.KdZ], 'Ki', Ki, ...
    'Kr', [p.KrRP; p.KrRP; p.KrYaw], 'Kw', [p.KwRP; p.KwRP; p.KwYaw], 'tanTilt', tan(p.maxTilt), ...
    'band', p.band, 'iLimit', p.aIntMax ./ Ki, 'offThrust', p.offThrust * model.hoverThrust);
end
