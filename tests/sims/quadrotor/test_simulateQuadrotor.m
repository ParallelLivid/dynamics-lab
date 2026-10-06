function tests = test_simulateQuadrotor
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
p = struct('m', 1, 'L', 0.2, 'Ixx', 0.01, 'Iyy', 0.01, 'Izz', 0.018, 'kf', 1e-5, 'km', 1.5e-7, ...
    'tauMotor', 0.03, 'Tmax', 6, 'kd', 0.02, 'g', 9.81, 'controller', 'position', ...
    'KpXY', 1.5, 'KdXY', 2.2, 'KiXY', 0.3, 'KpZ', 4, 'KdZ', 3.2, 'KiZ', 0.5, ...
    'KrRP', 144, 'KwRP', 19, 'KrYaw', 9, 'KwYaw', 5, 'maxTilt', deg2rad(30), 'band', 1, 'aIntMax', 3, ...
    'offThrust', 1, 'mission', 'setpoint', 'reference', @(t) [0; 0; 3; 0], 'waypoints', zeros(0, 5), ...
    'cruiseSpeed', 2, 'attitudeCommand', @(t) [0; 0], 'wind', [], 'pos0', [0; 0; 3], 'vel0', zeros(3, 1), ...
    'euler0', zeros(3, 1), 'omega0', zeros(3, 1), 'failRotor', 0, 'failTime', 0, 'failScale', 0, ...
    'crashSpeed', 1, 'tEnd', 5, 'dt', 0.02);
end

function [A, B, C] = linearModel(lin)
A = dlab.physics.jacobian(@(x) lin.G(x, lin.U0), lin.X0, Scale=lin.Scale);
B = dlab.physics.jacobian(@(u) lin.G(lin.X0, u), lin.U0);
C = dlab.physics.jacobian(@(x) lin.H(x, lin.U0), lin.X0, Scale=lin.Scale);
end

function testHoverThrustIsAQuarterOfTheWeight(testCase)
% Golden: steady hover needs T = m g / 4 from every rotor, exactly.
for c = [1 0; 1.7 deg2rad(30)]'
    p = base();
    p.m = c(1);
    p.euler0 = [0; 0; c(2)];
    p.reference = @(t) [0; 0; 3; c(2)];
    r = dlab.sims.quadrotor.simulateQuadrotor(p);
    verifyEqual(testCase, r.termination, "completed");
    verifyEqual(testCase, r.hoverThrust, p.m * p.g / 4, 'RelTol', 1e-15);
    verifyEqual(testCase, r.thrust(end, :), repmat(p.m * p.g / 4, 1, 4), 'AbsTol', 1e-9);
    verifyEqual(testCase, r.pos(end, :), [0 0 3], 'AbsTol', 1e-9);
    verifyFalse(testCase, any(r.saturated));
end
[model, ~] = dlab.sims.quadrotor.airframe(base());
[T, saturated] = dlab.sims.quadrotor.mixer([model.m * model.g; 0; 0; 0], model);
verifyEqual(testCase, T, repmat(model.m * model.g / 4, 4, 1), 'The mixer splits pure lift equally.');
verifyFalse(testCase, saturated);
end

function testMixerInvertsAndPrioritises(testCase)
[model, ~] = dlab.sims.quadrotor.airframe(base());
% Within the limits it is the exact inverse of the allocation matrix.
wrench = [12; 0.05; -0.08; 0.01];
[T, saturated] = dlab.sims.quadrotor.mixer(wrench, model);
verifyEqual(testCase, model.A * T, wrench, 'AbsTol', 1e-12);
verifyFalse(testCase, saturated);
% Too much yaw: roll, pitch, and thrust are kept; yaw is cut.
wrench = [12; 0.2; 0.1; 0.5];
[T, saturated] = dlab.sims.quadrotor.mixer(wrench, model);
achieved = model.A * T;
verifyTrue(testCase, saturated);
verifyEqual(testCase, achieved(1:3), wrench(1:3), 'AbsTol', 1e-12);
verifyGreaterThan(testCase, achieved(4), 0);
verifyLessThan(testCase, achieved(4), wrench(4));
verifyTrue(testCase, all(T >= 0 & T <= model.Tmax));
% Full thrust plus a roll torque: the collective gives way, roll is kept.
wrench = [4 * model.Tmax; 0.3; 0; 0];
T = dlab.sims.quadrotor.mixer(wrench, model);
achieved = model.A * T;
verifyEqual(testCase, achieved(2), 0.3, 'AbsTol', 1e-12);
verifyLessThan(testCase, achieved(1), wrench(1));
verifyLessThanOrEqual(testCase, max(T), model.Tmax);
end

function testAttitudeStepMatchesLinearization(testCase)
% A 2° roll command: the full nonlinear run against the closed loop's
% linearization (expm of the augmented system), which also checks G and H.
p = base();
p.controller = 'attitude';
p.pos0 = [0; 0; 10];
p.reference = @(t) [0; 0; 10; 0];
step = deg2rad(2);
p.attitudeCommand = @(t) [step * (t >= 0.2); 0];
p.tEnd = 1.5;
p.dt = 0.01;
r = dlab.sims.quadrotor.simulateQuadrotor(p);
lin = dlab.sims.quadrotor.hoverLinearization(p, [0 0 10 0]);
verifyEqual(testCase, lin.OutputNames, ["Roll" "Pitch" "Yaw" "z"]);
[A, B, C] = linearModel(lin);
n = size(A, 1);
du = [step; 0; 0; 0];
roll = zeros(numel(r.t), 1);
for k = 1:numel(r.t)
    tau = r.t(k) - 0.2;
    if tau > 0
        E = expm([A, B * du; zeros(1, n + 1)] * tau);
        roll(k) = C(1, :) * E(1:n, end);
    end
end
verifyLessThan(testCase, max(abs(r.euler(:, 1) - roll)), 0.02 * step, ...
    'The nonlinear roll follows the linear model within 2 % of the step.');
verifyEqual(testCase, r.euler(end, 1), step, 'AbsTol', 1e-3 * step);
% The inner loop is θ'' + Kw θ' + Kr θ = Kr θc behind the rotor lag: with
% a fast rotor its roll poles tend to the roots of s² + Kw s + Kr.
p.tauMotor = 0.002;
A = linearModel(dlab.sims.quadrotor.hoverLinearization(p, [0 0 10 0]));
poles = eig(A);
for target = roots([1 p.KwRP p.KrRP]).'
    verifyLessThan(testCase, min(abs(poles - target)) / abs(target), 0.05);
end
end

function testFreeFall(testCase)
% Golden: rotors off, no drag: z = z0 − g t²/2, hitting the ground at
% t = √(2 z0 / g) with speed g t.
p = base();
[p.controller, p.offThrust, p.kd, p.pos0, p.tEnd] = deal('off', 0, 0, [1; 2; 20], 5);
r = dlab.sims.quadrotor.simulateQuadrotor(p);
verifyEqual(testCase, r.pos(:, 3), 20 - p.g * r.t.^2 / 2, 'AbsTol', 1e-8);
verifyEqual(testCase, r.pos(:, 1:2), repmat([1 2], numel(r.t), 1), 'AbsTol', 1e-12);
verifyEqual(testCase, r.termination, "crashed");
verifyEqual(testCase, r.t(end), sqrt(2 * 20 / p.g), 'AbsTol', 1e-7);
verifyEqual(testCase, r.contactSpeed, sqrt(2 * 20 * p.g), 'RelTol', 1e-7);
end

function testTorqueFreeSpinConservesAngularMomentum(testCase)
% Golden: equal rotor thrusts give no torque, so H = R I ω is constant in
% the world and |I ω| and the rotational energy stay fixed.
p = base();
[p.controller, p.offThrust, p.kd, p.pos0, p.tEnd] = deal('off', 1, 0, [0; 0; 100], 3);
[p.Ixx, p.Iyy, p.Izz] = deal(0.01, 0.015, 0.02);
p.omega0 = [0.3; -0.2; 2];
r = dlab.sims.quadrotor.simulateQuadrotor(p);
I = [p.Ixx p.Iyy p.Izz];
H = zeros(numel(r.t), 3);
for k = 1:numel(r.t)
    H(k, :) = (dlab.physics.Quaternion.toDcm(r.quat(k, :)') * (I .* r.omega(k, :))')';
end
verifyEqual(testCase, H, repmat(H(1, :), numel(r.t), 1), 'AbsTol', 1e-7 * norm(H(1, :)));
verifyEqual(testCase, vecnorm(I .* r.omega, 2, 2), repmat(norm(I .* p.omega0'), numel(r.t), 1), ...
    'RelTol', 1e-7);
energy = sum(I .* r.omega.^2, 2) / 2;
verifyEqual(testCase, energy, repmat(energy(1), numel(r.t), 1), 'RelTol', 1e-7);
verifyGreaterThan(testCase, max(abs(r.omega(:, 1) - p.omega0(1))), 0.01, 'The rates do change (it tumbles).');
end

function testMotorFailureSpinsUp(testCase)
p = base();
[p.pos0, p.reference, p.failRotor, p.failTime, p.failScale, p.tEnd] = deal([0; 0; 10], @(t) [0; 0; 10; 0], ...
    1, 2, 0, 8);
r = dlab.sims.quadrotor.simulateQuadrotor(p);
before = r.t < 2;
verifyLessThan(testCase, max(abs(r.omega(before, 3))), 1e-9);
verifyGreaterThan(testCase, max(abs(r.omega(~before, 3))), 3, 'The yaw rate grows after the failure.');
verifyEqual(testCase, r.thrust(r.t > 2.2, 1), zeros(nnz(r.t > 2.2), 1), 'AbsTol', 1e-12);
verifyEqual(testCase, r.termination, "crashed");
again = dlab.sims.quadrotor.simulateQuadrotor(p);
verifyEqual(testCase, again, r, 'Runs are deterministic.');
end

function testClosedLoopLinearization(testCase)
p = base();
lin = dlab.sims.quadrotor.hoverLinearization(p, [1 -2 3 0.4]);
verifyEqual(testCase, numel(lin.StateNames), numel(lin.X0));
verifyEqual(testCase, lin.InputNames(1:4), ["Setpoint x" "Setpoint y" "Setpoint z" "Setpoint yaw"]);
verifyEqual(testCase, lin.OutputNames, ["x" "y" "z" "Yaw"]);
verifyLessThan(testCase, norm(lin.G(lin.X0, lin.U0)), 1e-9, 'Hover at the setpoint is an equilibrium.');
[A, B, C] = linearModel(lin);
verifyLessThan(testCase, max(real(eig(A))), 0, 'The closed loop is stable.');
dc = -C / A * B;
verifyEqual(testCase, dc(:, 1:4), eye(4), 'AbsTol', 1e-6, 'Each output follows its setpoint.');
verifyEqual(testCase, dc(:, 5), zeros(4, 1), 'AbsTol', 1e-6, 'The integral removes a steady push.');
% Without integrals a steady force F leaves the offset F / (m Kp).
p.KiXY = 0;
p.KiZ = 0;
lin = dlab.sims.quadrotor.hoverLinearization(p, [0 0 3 0]);
verifyEqual(testCase, numel(lin.X0), 16);
[A, B, C] = linearModel(lin);
dc = -C / A * B;
verifyEqual(testCase, dc(1, 5), 1 / (p.m * p.KpXY), 'RelTol', 1e-6);
p.controller = 'off';
verifyEmpty(testCase, dlab.sims.quadrotor.hoverLinearization(p, [0 0 3 0]), 'Open loop: no equilibrium.');
end

function testWaypointPath(testCase)
W = [0 0 3 0 1; 4 0 3 -3 * pi / 2 0];          % −270° is +90°, the short way
path = dlab.sims.quadrotor.missionPath([0 0 0], 0, W, 2);
verifyEqual(testCase, path.endTime, 4.5, 'AbsTol', 1e-12);
verifyEqual(testCase, path.fcn(0.75), [0; 0; 1.5; 0; 0; 0; 2], 'AbsTol', 1e-12);
verifyEqual(testCase, path.fcn(2), [0; 0; 3; 0; 0; 0; 0], 'AbsTol', 1e-12, 'Holding at the first waypoint.');
verifyEqual(testCase, path.fcn(3.5), [2; 0; 3; pi / 4; 2; 0; 0], 'AbsTol', 1e-12);
verifyEqual(testCase, path.fcn(100), [4; 0; 3; pi / 2; 0; 0; 0], 'AbsTol', 1e-12);
% The whole box: the quadrotor finishes near the last waypoint.
p = base();
[p.mission, p.pos0, p.tEnd] = deal('waypoints', [0; 0; 0], 20);
p.waypoints = [0 0 3 0 1; 4 0 3 0 1; 4 4 3 pi/2 1; 0 4 3 pi 1; 0 0 3 3*pi/2 1];
r = dlab.sims.quadrotor.simulateQuadrotor(p);
verifyEqual(testCase, r.termination, "completed");
verifyLessThan(testCase, r.stats.finalError, 0.1);
verifyEqual(testCase, r.euler(end, 3), 3 * pi / 2, 'AbsTol', 0.02, 'The nose turned through each corner.');
end

function testHeightStepSettles(testCase)
p = base();
p.reference = @(t) [0; 0; 3 + 3 * (t >= 1); 0];
p.tEnd = 8;
r = dlab.sims.quadrotor.simulateQuadrotor(p);
verifyLessThan(testCase, r.stats.settlingTime, 3);
verifyLessThan(testCase, r.stats.overshoot, 10);
verifyEqual(testCase, r.stats.timeSaturated, 0);
% A weak quadrotor (thrust-to-weight 1.43) saturates on a big climb.
p.Tmax = 3.5;
p.reference = @(t) [0; 0; 3 + 17 * (t >= 1); 0];
p.tEnd = 12;
r = dlab.sims.quadrotor.simulateQuadrotor(p);
verifyGreaterThan(testCase, r.stats.timeSaturated, 1);
verifyLessThanOrEqual(testCase, r.stats.peakThrust, p.Tmax);
end

function testRejectsBadInput(testCase)
p = base();
p.m = 0;
verifyError(testCase, @() dlab.sims.quadrotor.simulateQuadrotor(p), 'quadrotor:InvalidParameter');
p = base();
p.failRotor = 5;
verifyError(testCase, @() dlab.sims.quadrotor.simulateQuadrotor(p), 'quadrotor:InvalidParameter');
p = base();
p.controller = 'autopilot';
verifyError(testCase, @() dlab.sims.quadrotor.simulateQuadrotor(p), 'quadrotor:InvalidParameter');
end
