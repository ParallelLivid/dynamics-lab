function tests = test_simulateAttitude
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
% A 90° yaw slew: I = 30, 40, 50 kg·m², PD gains with ζ = 0.7 about z.
p = struct('I', [30 40 50], 'omega0', [0 0 0], 'q0', [1 0 0 0], ...
    'qTarget', dlab.physics.Quaternion.fromEuler(0, 0, pi / 2), 'mode', 'slew', 'Kp', 0.5, 'Kd', 7, ...
    'tauMax', 0.2, 'hMax', 6, 'thrust', 1, 'disturbance', [0 0 0], 'tspan', 200, 'dt', 0.1);
end

function testFreeBodyConservesEnergyAndMomentum(testCase)
% Torque-free tumbling about the intermediate axis: it flips over, while
% ½ ωᵀIω and the inertial angular momentum stay constant.
p = base();
[p.mode, p.qTarget, p.omega0, p.tspan, p.dt] = deal('free', [1 0 0 0], deg2rad([0.05 10 0.05]), 600, 0.2);
r = dlab.sims.attitude.simulateAttitude(p);
verifyLessThan(testCase, [r.drift.energy r.drift.H], 1e-10);
verifyGreaterThan(testCase, r.maxError, deg2rad(170), 'The body turns over.');
verifyEqual(testCase, r.h, zeros(size(r.h)), 'The wheels stay idle.');
% A gyrostat (spinning wheels, no motor torque) conserves the same two.
p.h0 = [0.5 -0.2 1];
r = dlab.sims.attitude.simulateAttitude(p);
verifyLessThan(testCase, [r.drift.energy r.drift.H], 1e-10);
end

function testSlewMatchesAnIndependentIntegration(testCase)
% Independent reference: a separate rigid body with wheels, integrated in scipy.
% My own rigid body with wheels (scipy DOP853, quaternions written out):
% the 90° yaw slew settles within 0.1° at 107.732 s, peaks at 3.58615 °/s
% with 3.1295 N·m·s in the z wheel; the drift is undefined from rest (it
% read 4e306).
r = dlab.sims.attitude.simulateAttitude(base());
verifyEqual(testCase, r.settleTime, 107.732, 'AbsTol', 2e-3);
verifyEqual(testCase, rad2deg(r.maxRate), 3.58615, 'RelTol', 1e-5);
verifyEqual(testCase, r.maxWheel, 3.1295, 'RelTol', 1e-4);
verifyTrue(testCase, isnan(r.drift.energy) && isnan(r.drift.H));
end

function testBangBangTimeOneAxis(testCase)
% Rest to rest by θ about a principal axis with torque τ: t = 2 √(θ I / τ).
cases = {[0 0 pi/2], 50, 1; [0 pi/4 0], 40, 0.5; [-2*pi/3 0 0], 30, 2};
for k = 1:size(cases, 1)
    [angles, inertia, torque] = cases{k, :};
    p = base();
    [p.mode, p.thrust, p.dt] = deal('bangbang', torque, 0.01);
    p.qTarget = dlab.physics.Quaternion.fromEuler(angles(1), angles(2), angles(3));
    theta = max(abs(angles));
    T = 2 * sqrt(theta * inertia / torque);
    p.tspan = T + 10;
    r = dlab.sims.attitude.simulateAttitude(p);
    verifyEqual(testCase, r.plan.endTime, T, 'RelTol', 1e-12);
    verifyEqual(testCase, r.plan.angle, theta, 'RelTol', 1e-12);
    % The error reaches 0.1° a little before the end: θ_err = ½ α (T − t)².
    alpha = torque / inertia;
    early = sqrt(2 * deg2rad(0.1) / alpha);
    verifyEqual(testCase, r.settleTime, T - early, 'AbsTol', 1e-3);
    verifyLessThan(testCase, rad2deg(r.finalError), 1e-6, 'Lands exactly on the target.');
    verifyEqual(testCase, r.maxRate, sqrt(theta * alpha), 'RelTol', 2e-3, 'Peak rate at the switch.');
    verifyEqual(testCase, r.impulse, torque * T, 'RelTol', 1e-8, 'Full thrust on one axis throughout.');
    verifyLessThan(testCase, r.maxWheel, 1e-9, 'The wheels have nothing to do afterwards.');
end
end

function testBangBangThreeAxisStaysOnTheEigenaxis(testCase)
% The thrusters cancel the gyroscopic torque, so a 150° three-axis slew
% lands on target, with no axis above its thrust.
p = base();
[p.mode, p.dt, p.tspan] = deal('bangbang', 0.01, 40);
p.qTarget = dlab.physics.Quaternion.fromEuler(deg2rad(60), deg2rad(-40), deg2rad(120));
r = dlab.sims.attitude.simulateAttitude(p);
verifyEqual(testCase, rad2deg(r.initialError), 150, 'AbsTol', 0.5);
verifyLessThan(testCase, rad2deg(interp1(r.t, r.error, r.plan.endTime)), 1e-4);
verifyLessThanOrEqual(testCase, max(abs(r.tauThruster(:))), p.thrust * (1 + 1e-12));
verifyGreaterThan(testCase, max(abs(r.tauThruster(:))), 0.95 * p.thrust, 'The busiest axis is near full thrust.');
% ω stays along the eigenaxis (in body axes) during the thrust.
during = r.t > 0.5 & r.t < r.plan.endTime - 0.5;
w = r.omega(during, :);
along = abs(w * r.plan.axis) ./ sqrt(sum(w.^2, 2));
verifyGreaterThan(testCase, min(along), 1 - 1e-8);
end

function testPdHoldIsSecondOrder(testCase)
% A 1° yaw step with ample wheels: I θ'' + Kd θ' + Kp θ = 0, so the
% overshoot is exp(−πζ/√(1−ζ²)) and the ringing period 2π/ω_d, with
% ω_n = √(Kp/I) and ζ = Kd / (2 √(Kp I)).
p = base();
[p.Kp, p.Kd, p.tauMax, p.hMax, p.dt, p.tspan] = deal(0.5, 3, 100, 100, 0.01, 100);
p.qTarget = dlab.physics.Quaternion.fromEuler(0, 0, deg2rad(1));
r = dlab.sims.attitude.simulateAttitude(p);
I = 50;
wn = sqrt(p.Kp / I);
zeta = p.Kd / (2 * sqrt(p.Kp * I));
verifyEqual(testCase, r.overshoot, 100 * exp(-pi * zeta / sqrt(1 - zeta^2)), 'RelTol', 2e-3);
s = r.signedError;
crossings = find(s(1:end-1) .* s(2:end) < 0);
times = r.t(crossings) - s(crossings) .* diff(r.t(crossings + [0 1]), 1, 2) ./ (s(crossings + 1) - s(crossings));
verifyEqual(testCase, mean(diff(times)), pi / (wn * sqrt(1 - zeta^2)), 'RelTol', 1e-3, 'Half a damped period.');
end

function testDisturbanceFillsTheWheelsLinearly(testCase)
% Holding against a constant torque τ_d: the wheel momentum grows at τ_d
% until it reaches the capacity, at about h_max / τ_d.
p = base();
[p.mode, p.qTarget, p.Kp, p.Kd, p.tspan, p.dt] = deal('hold', [1 0 0 0], 1, 10, 900, 0.5);
p.disturbance = [0 0 0.01];
r = dlab.sims.attitude.simulateAttitude(p);
window = r.t >= 200 & r.t <= 550;
fit = [r.t(window), ones(nnz(window), 1)] \ r.h(window, 3);
verifyEqual(testCase, fit(1), 0.01, 'RelTol', 1e-4);
verifyTrue(testCase, r.wasSaturated);
verifyEqual(testCase, r.saturationTime, p.hMax / 0.01, 'RelTol', 2e-3);
verifyLessThanOrEqual(testCase, r.maxWheel, p.hMax * (1 + 1e-9), 'A wheel never exceeds its capacity.');
verifyEqual(testCase, rad2deg(interp1(r.t, r.error, 500)), rad2deg(0.01 / p.Kp), 'RelTol', 1e-3, ...
    'Before saturating: the PD offset τ_d / Kp.');
verifyGreaterThan(testCase, rad2deg(r.maxError), 30, 'Saturated, the body is pushed away.');
end

function testDumpingUnloadsTheWheels(testCase)
p = base();
[p.mode, p.qTarget, p.Kp, p.Kd, p.tspan, p.dt] = deal('hold', [1 0 0 0], 1, 10, 900, 0.5);
[p.disturbance, p.dump, p.dumpTorque] = deal([0.002 0 0.01], true, 0.02);
r = dlab.sims.attitude.simulateAttitude(p);
verifyFalse(testCase, r.wasSaturated);
verifyGreaterThanOrEqual(testCase, r.dumps, 1);
verifyLessThan(testCase, r.maxWheel, 0.85 * p.hMax);
verifyGreaterThan(testCase, r.impulse, 0);
verifyLessThan(testCase, rad2deg(r.maxError), 1);
end

function testDetumbleMovesMomentumIntoTheWheels(testCase)
p = base();
[p.mode, p.qTarget, p.omega0, p.tspan] = deal('detumble', [1 0 0 0], deg2rad([3 -2 4]), 150);
r = dlab.sims.attitude.simulateAttitude(p);
verifyLessThan(testCase, rad2deg(norm(r.omega(end, :))), 1e-3);
verifyLessThan(testCase, r.drift.H, 1e-8, 'No external torque: the total is conserved.');
verifyEqual(testCase, norm(r.h(end, :)), norm(p.I .* p.omega0), 'RelTol', 1e-5);
end

function testQuaternionSignDoesNotMatter(testCase)
p = base();
p.qTarget = dlab.physics.Quaternion.fromEuler(deg2rad(60), deg2rad(-40), deg2rad(120));
p.q0 = dlab.physics.Quaternion.fromEuler(deg2rad(10), deg2rad(5), deg2rad(-20));
p.omega0 = [0.01 -0.02 0.005];
for mode = {'slew', 'bangbang'}
    p.mode = mode{1};
    r = dlab.sims.attitude.simulateAttitude(p);
    for signs = [-1 1; 1 -1; -1 -1]'
        flipped = p;
        flipped.q0 = signs(1) * p.q0;
        flipped.qTarget = signs(2) * p.qTarget;
        f = dlab.sims.attitude.simulateAttitude(flipped);
        verifyEqual(testCase, f.omega, r.omega, 'AbsTol', 1e-9, mode{1});
        verifyEqual(testCase, f.error, r.error, 'AbsTol', 1e-9, mode{1});
        verifyEqual(testCase, f.h, r.h, 'AbsTol', 1e-9, mode{1});
        verifyEqual(testCase, f.settleTime, r.settleTime, 'AbsTol', 1e-6, mode{1});
    end
end
end

function testCancelReturnsEarly(testCase)
p = base();
p.progressFcn = @(fraction) fraction > 0.3;
r = dlab.sims.attitude.simulateAttitude(p);
verifyLessThan(testCase, r.t(end), p.tspan);
end

function testRejectsBadInput(testCase)
id = 'attitude:InvalidParameter';
p = base();
p.I = [1 1 3];
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
p = base();
p.mode = 'spin';
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
p = base();
p.Kd = -1;
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
p = base();
p.hMax = 0;
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
p = base();
p.q0 = [0 0 0 0];
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
p = base();
[p.dump, p.dumpAt, p.dumpStop] = deal(true, 0.1, 0.2);
verifyError(testCase, @() dlab.sims.attitude.simulateAttitude(p), id);
end
