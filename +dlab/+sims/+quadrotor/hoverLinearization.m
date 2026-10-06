function lin = hoverLinearization(p, hover)
%HOVERLINEARIZATION The closed loop near hover, for small-motion analysis.
%   lin = hoverLinearization(p, hover) describes the quadrotor with its
%   controller on, hovering at HOVER = [x y z yaw] (m, rad) in still air
%   with every rotor healthy. Its rotor limits are not reached there, so
%   the model is smooth. Returns [] for the controller 'off' (the open loop
%   is a chain of integrators: no equilibrium to speak of).
%
%   Attitude is a small rotation δ = [δφ δθ δψ] (rad, body axes) from the
%   hover attitude, q = q_hover ⊗ [√(1 − |δ|²/4); δ/2], so the states are
%   independent (no quaternion constraint). Integrals are states only
%   where their gain is not zero.
%
%   lin: G (@(x, u) dx/dt), H (@(x, u) outputs), X0, U0, StateNames,
%   InputNames, OutputNames, Groups (per state: "horizontal", "altitude",
%   "attitude", "yaw", "integral", "rotor"), Scale.
%     position mode  states x y z vx vy vz δφ δθ δψ p q r [∫ex ∫ey ∫ez] Ω1–4
%                    inputs setpoint x, y, z, yaw and a disturbance force
%                    along x (N); outputs x, y, z, yaw
%     attitude mode  states z vz δφ δθ δψ p q r [∫ez] Ω1–4 (x and y do not
%                    feed back); inputs roll, pitch, yaw commands and
%                    setpoint z; outputs roll, pitch, yaw, z
[model, ctrl] = dlab.sims.quadrotor.airframe(p);
lin = [];
if ctrl.mode == 3
    return
end
hover = hover(:);
qh = [cos(hover(4) / 2); 0; 0; sin(hover(4) / 2)];
integrals = find(ctrl.Ki > 0)';
speed = model.hoverSpeed;
if ctrl.mode == 1
    integrals = integrals(:)';
    names = ["x" "y" "z" "vx" "vy" "vz" "δφ" "δθ" "δψ" "p" "q" "r" "∫ex" "∫ey" "∫ez"];
    groups = ["horizontal" "horizontal" "altitude" "horizontal" "horizontal" "altitude" ...
        "attitude" "attitude" "yaw" "attitude" "attitude" "yaw" "integral" "integral" "integral"];
    names = [names([1:12, 12 + integrals]) "Ω1" "Ω2" "Ω3" "Ω4"];
    groups = [groups([1:12, 12 + integrals]) repmat("rotor", 1, 4)];
    X0 = [hover(1:3); zeros(9 + numel(integrals), 1); speed * ones(4, 1)];
    U0 = [hover; 0];
    expand = @(x, u) fullState(x, 1:6, x(7:9), x(10:12), integrals, x(13:12 + numel(integrals)), ...
        x(end-3:end), zeros(6, 1), qh);
    lin.G = @(x, u) positionRates(x, u, expand, integrals, model, ctrl);
    lin.H = @(x, u) [x(1:3); yawNear(expand(x, u), hover(4))];
    lin.InputNames = ["Setpoint x" "Setpoint y" "Setpoint z" "Setpoint yaw" "Disturbance force x"];
    lin.OutputNames = ["x" "y" "z" "Yaw"];
else
    integrals = integrals(integrals == 3);
    names = ["z" "vz" "δφ" "δθ" "δψ" "p" "q" "r" "∫ez"];
    groups = ["altitude" "altitude" "attitude" "attitude" "yaw" "attitude" "attitude" "yaw" "integral"];
    keep = [1:8, 8 + ones(1, numel(integrals))];
    names = [names(keep) "Ω1" "Ω2" "Ω3" "Ω4"];
    groups = [groups(keep) repmat("rotor", 1, 4)];
    X0 = [hover(3); zeros(7 + numel(integrals), 1); speed * ones(4, 1)];
    U0 = [0; 0; hover(4); hover(3)];
    expand = @(x, ~) fullState(x, [3 6], x(3:5), x(6:8), integrals, x(9:8 + numel(integrals)), ...
        x(end-3:end), [hover(1:2); 0; 0; 0; 0], qh);
    lin.G = @(x, u) attitudeRates(x, u, expand, integrals, model, ctrl);
    lin.H = @(x, u) attitudeOutputs(expand(x, u), hover(4));
    lin.InputNames = ["Roll command" "Pitch command" "Yaw command" "Setpoint z"];
    lin.OutputNames = ["Roll" "Pitch" "Yaw" "z"];
end
lin.X0 = X0;
lin.U0 = U0;
lin.StateNames = names;
lin.Groups = groups;
lin.Scale = [ones(numel(X0) - 4, 1); speed * ones(4, 1)];
end

function s = fullState(x, motion, delta, w, integrals, integ, Om, rest, qh)
% The simulator's 20 states from the reduced ones. MOTION lists which of
% the 6 position and velocity states x(1:numel(motion)) are; REST holds the
% others (for the attitude mode: x and y at hover, and velocities zero).
s = zeros(20, 1);
pv = rest;
if numel(motion) == 6
    pv = x(1:6);
else
    pv(motion) = x(1:2);
end
s(1:6) = pv;
e0 = sqrt(max(1 - (delta' * delta) / 4, 0));
s(7:10) = dlab.physics.Quaternion.multiply(qh, [e0; delta / 2]);
s(11:13) = w;
s(13 + integrals) = integ;
s(17:20) = Om;
end

function dx = positionRates(x, u, expand, integrals, model, ctrl)
s = expand(x, u);
ds = dlab.sims.quadrotor.closedLoop(s, [u(1:4); 0; 0; 0], [0; 0], ones(4, 1), zeros(3, 1), ...
    [u(5); 0; 0], model, ctrl);
dx = [ds(1:6); deltaRate(x(7:9), x(10:12)); ds(11:13); ds(13 + integrals); ds(17:20)];
end

function dx = attitudeRates(x, u, expand, integrals, model, ctrl)
s = expand(x, u);
ds = dlab.sims.quadrotor.closedLoop(s, [s(1:2); u(4); u(3); 0; 0; 0], u(1:2), ones(4, 1), ...
    zeros(3, 1), zeros(3, 1), model, ctrl);
dx = [ds([3 6]); deltaRate(x(3:5), x(6:8)); ds(11:13); ds(13 + integrals); ds(17:20)];
end

function d = deltaRate(delta, w)
% δ = 2 e_vec with e = q_hover⁻¹ ⊗ q, and e' = ½ e ⊗ [0; ω].
e0 = sqrt(max(1 - (delta' * delta) / 4, 0));
d = e0 * w + cross(delta / 2, w);
end

function y = attitudeOutputs(s, yaw0)
[phi, theta, psi] = dlab.physics.Quaternion.toEuler(s(7:10));
y = [phi; theta; yaw0 + mod(psi - yaw0 + pi, 2 * pi) - pi; s(3)];
end

function psi = yawNear(s, yaw0)
[~, ~, psi] = dlab.physics.Quaternion.toEuler(s(7:10));
psi = yaw0 + mod(psi - yaw0 + pi, 2 * pi) - pi;
end
