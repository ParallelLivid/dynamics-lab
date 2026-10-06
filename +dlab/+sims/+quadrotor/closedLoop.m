function [ds, out] = closedLoop(s, ref, att, eta, wind, force, model, ctrl)
%CLOSEDLOOP State derivative of the quadrotor with its controller.
%   [ds, out] = closedLoop(s, ref, att, eta, wind, force, model, ctrl)
%
%   s     20×1 state: position (3, world, z up), velocity (3, world),
%         attitude quaternion (4, body → world, scalar first), body rates
%         (3), controller integrals (3), rotor speeds Ω (4, rad/s)
%   ref   7×1 [x y z yaw vx vy vz]: setpoint and its velocity
%   att   2×1 [roll; pitch] commands (rad), used by the attitude mode
%   eta   4×1 thrust scale of each rotor (1 healthy, 0 failed)
%   wind  3×1 wind velocity (m/s); force: 3×1 external force (N)
%   model, ctrl from dlab.sims.quadrotor.airframe
%
%   Cascade (mode 1, position):
%     a = Kp e + Kd ė + Ki ∫e   (per axis; e = setpoint − position)
%     F_d = m (a + g ẑ), tilted at most maxTilt from vertical
%     thrust = F_d · (body z);  attitude: body z along F_d, heading yaw
%   Attitude (mode 2): roll and pitch commands, altitude held by the z PID.
%   Inner loop (modes 1, 2), with q_e = q_d⁻¹ ⊗ q:
%     τ = ω × Iω + I (−Kr · 2 sign(q_e0) q_e,vec − Kw ω)
%   then the mixer (dlab.sims.quadrotor.mixer). Off (mode 3): every rotor
%   is commanded the fixed thrust ctrl.offThrust.
%
%   Plant: rotor speeds lag their commands, Ω' = (Ω_cmd − Ω)/τ with
%   Ω_cmd = √(T_cmd/kf); Tᵢ = ηᵢ kf Ωᵢ²; drag −kd |v − w| (v − w).
%
%   out (when asked): thrustCmd, saturated, thrust, qd (desired attitude).
pos = s(1:3);
vel = s(4:6);
qr = s(7:10);
w = s(11:13);
integ = s(14:16);
Om = s(17:20);
q = qr / sqrt(qr' * qr);
R = dlab.physics.Quaternion.toDcm(q);

dI = zeros(3, 1);
qd = q;
switch ctrl.mode
    case 1
        e = ref(1:3) - pos;
        a = ctrl.Kp .* e + ctrl.Kd .* (ref(5:7) - vel) + ctrl.Ki .* integ;
        Fd = model.m * (a + [0; 0; model.g]);
        Fd(3) = max(Fd(3), 0.1 * model.m * model.g);        % never ask to be pushed down
        horizontal = hypot(Fd(1), Fd(2));
        limit = Fd(3) * ctrl.tanTilt;
        if horizontal > limit
            Fd(1:2) = Fd(1:2) * (limit / horizontal);
        end
        thrust = max(Fd' * R(:, 3), 0);
        qd = towardThrust(Fd / norm(Fd), ref(4));
        dI = integrate(e, integ, ctrl);
    case 2
        e = ref(3) - pos(3);
        a = ctrl.Kp(3) * e + ctrl.Kd(3) * (ref(7) - vel(3)) + ctrl.Ki(3) * integ(3);
        thrust = max(model.m * (a + model.g) / max(R(3, 3), 0.5), 0);
        qd = dlab.physics.Quaternion.fromEuler(att(1), att(2), ref(4));
        dI = integrate([0; 0; e], integ, ctrl);
end
if ctrl.mode < 3
    qe = dlab.physics.Quaternion.relative(qd, q);
    if qe(1) < 0
        qe = -qe;
    end
    Iw = model.I .* w;
    tau = cross(w, Iw) + model.I .* (-ctrl.Kr .* (2 * qe(2:4)) - ctrl.Kw .* w);
    [thrustCmd, saturated] = dlab.sims.quadrotor.mixer([thrust; tau], model);
else
    thrustCmd = ctrl.offThrust * ones(4, 1);
    saturated = false;
end

T = eta .* model.kf .* Om .* abs(Om);
torque = [model.d * (T(1) - T(2) - T(3) + T(4))
          model.d * (-T(1) - T(2) + T(3) + T(4))
          model.c * (T(1) - T(2) + T(3) - T(4))];
air = vel - wind;
acc = R(:, 3) * (sum(T) / model.m) - [0; 0; model.g] - (model.kd / model.m) * norm(air) * air + force / model.m;
dw = (torque - cross(w, model.I .* w)) ./ model.I;
dq = 0.5 * [-qr(2:4)' * w; qr(1) * w + cross(qr(2:4), w)];
dOm = (sqrt(thrustCmd / model.kf) - Om) / model.tau;
ds = [vel; acc; dq; dw; dI; dOm];
if nargout > 1
    out = struct('thrustCmd', thrustCmd, 'saturated', saturated, 'thrust', T, 'qd', qd);
end
end

function dI = integrate(e, integ, ctrl)
% Integral of the error, only near the setpoint (the capture band) and
% only while the integral term is inside its limit (anti-windup).
dI = e .* (ctrl.Ki > 0) .* (abs(e) < ctrl.band);
full = abs(integ) >= ctrl.iLimit & dI .* integ > 0;
dI(full) = 0;
end

function qd = towardThrust(zd, yaw)
% Attitude with body z along zd and the nose toward heading yaw.
xc = [cos(yaw); sin(yaw); 0];
yd = cross(zd, xc);
yd = yd / norm(yd);
xd = cross(yd, zd);
qd = dlab.physics.Quaternion.fromDcm([xd yd zd]);
end
