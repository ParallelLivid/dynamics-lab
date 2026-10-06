function tests = test_simulateRigidBody
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = free(I, omega0)
p = struct('model', 'free', 'I', I, 'omega0', omega0, 'm', 1, 'l', 1, 'g', 9.81, 'Is', 1, 'It', 1, ...
    'spin', 0, 'tilt', 0, 'precession', 0, 'nutation', 0, 'tspan', 10, 'dt', 0.01);
end

function p = top(spin)
p = free([1 1 1], [0 0 0]);
[p.model, p.m, p.l, p.Is, p.It, p.spin, p.tilt, p.tspan, p.dt] = ...
    deal('top', 0.5, 0.04, 2e-4, 1e-3, spin, 0.5, 3, 0.002);
end

function testSymmetricBodyPrecessesInTheBodyFrame(testCase)
% With I₁ = I₂, ω₁ + iω₂ turns at (I₃ − I₁)/I₁ · ω₃ in body axes.
r = dlab.sims.rigidbody.simulateRigidBody(free([2 2 3], [0.5 0 4]));
angle = unwrap(atan2(r.omega(:, 2), r.omega(:, 1)));
fit = [r.t, ones(size(r.t))] \ angle;
verifyEqual(testCase, fit(1), (3 - 2) / 2 * 4, 'RelTol', 1e-8);
verifyEqual(testCase, r.omega(:, 3), 4 * ones(size(r.t)), 'RelTol', 1e-9);
end

function testDzhanibekovFlips(testCase)
I = [1 2 3];
w = [1e-3 10 1e-3];
r = dlab.sims.rigidbody.simulateRigidBody(free(I, w));
verifyGreaterThanOrEqual(testCase, r.flips, 3);
% Between flips, ω₂ ∝ sn goes through half its period: 2K(k) / rate.
E = 0.5 * sum(I .* w.^2);
L2 = sum((I .* w).^2);
m = (I(2) - I(1)) * (2 * E * I(3) - L2) / ((I(3) - I(2)) * (L2 - 2 * E * I(1)));
rate = sqrt((I(3) - I(2)) * (L2 - 2 * E * I(1)) / prod(I));
verifyEqual(testCase, mean(diff(r.flipTimes)), 2 * ellipke(m) / rate, 'RelTol', 0.02);
verifyLessThan(testCase, [r.drift.energy r.drift.L], 1e-9);
verifyEqual(testCase, r.L(:, 3), norm(I .* w) * ones(size(r.t)), 'RelTol', 1e-9, 'L starts along z and stays.');
end

function testFastTopPrecession(testCase)
% The gyroscopic estimate's error falls as 1/ω²: about 0.7 % at 800 rad/s.
p = top(800);
p.tspan = 2;
r = dlab.sims.rigidbody.simulateRigidBody(p);
verifyEqual(testCase, r.precessionRate, p.m * p.g * p.l / (p.Is * p.spin), 'RelTol', 0.02);
verifyLessThan(testCase, [r.drift.energy r.drift.Lz r.drift.L3], 1e-8);
verifyLessThan(testCase, r.nutationAmplitude, 0.01, 'A fast top barely nods.');
end

function testSteadyPrecessionHasNoNutation(testCase)
% Start at the exact (slow) steady precession rate of the heavy top:
% m g l = φ' (I_s ω₃ − I_t φ' cos θ), with ω₃ the body spin component.
p = top(150);
c = cos(p.tilt);
phiDot = (p.Is * p.spin - sqrt((p.Is * p.spin)^2 - 4 * p.It * c * p.m * p.g * p.l)) / (2 * p.It * c);
p.precession = phiDot;
r = dlab.sims.rigidbody.simulateRigidBody(p);
verifyLessThan(testCase, r.nutationAmplitude, 1e-6);
end

function testTorqueFreeConservation(testCase)
% Energy, the angular-momentum vector in space (it starts along z), |L| in
% the body, and a proper rotation (orthonormal, det 1) all along.
I = [1 2 2.5];
w = [1e-3 10 1e-3];
r = dlab.sims.rigidbody.simulateRigidBody(free(I, w));
Lnorm = norm(I .* w);
verifyEqual(testCase, r.L, repmat([0 0 Lnorm], numel(r.t), 1), 'AbsTol', 1e-9 * Lnorm);
verifyEqual(testCase, sqrt(sum((I .* r.omega).^2, 2)), Lnorm * ones(size(r.t)), 'RelTol', 1e-10);
verifyLessThan(testCase, r.drift.energy, 1e-9);
verifyEqual(testCase, sqrt(sum(r.q.^2, 2)), ones(size(r.t)), 'AbsTol', 1e-14);
verifyLessThan(testCase, r.drift.qnorm, 1e-9);
for k = [1 round(numel(r.t) / 2) numel(r.t)]
    R = reshape(r.axes(k, :, :), 3, 3);
    verifyEqual(testCase, R' * R, eye(3), 'AbsTol', 1e-13);
    verifyEqual(testCase, det(R), 1, 'AbsTol', 1e-13);
end
end

function testAgainstAnIndependentIntegration(testCase)
% ω(t) of the tennis racket I = 1, 2, 3 from my own integration (SciPy
% DOP853, RelTol 1e-12, with a rotation matrix instead of a quaternion).
r = dlab.sims.rigidbody.simulateRigidBody(free([1 2 3], [1e-3 10 1e-3]));
verifyEqual(testCase, interp1(r.t, r.omega, 2), [-8.2587465806 -5.638537569 4.7681896314], 'AbsTol', 1e-6);
verifyEqual(testCase, r.omega(end, :), [-0.058973739 -9.9998261534 0.0340582926], 'AbsTol', 1e-5);
verifyEqual(testCase, r.flipTimes', [1.8894145510 5.4401398446 8.9908651402], 'AbsTol', 1e-5);
end

function testIntermediateAxisNeedNotBeAxis2(testCase)
r = dlab.sims.rigidbody.simulateRigidBody(free([2 1 2.5], [10 1e-3 1e-3]));
verifyEqual(testCase, r.flipAxis, 1);
verifyEqual(testCase, r.flips, 2, 'Axis 1 crosses perpendicular to L at 2.156 and 7.115 s (mine).');
verifyEqual(testCase, r.flipTimes', [2.1563328808 7.1146120467], 'AbsTol', 1e-4);
r = dlab.sims.rigidbody.simulateRigidBody(free([2 2 3], [10 0 0.01]));
verifyEqual(testCase, [r.flipAxis r.flips], [0 0], 'No intermediate axis.');
end

function testSpaceConeRate(testCase)
% A symmetric body's axis 3 turns about L at |L| / I₁ = 6.0208 rad/s.
r = dlab.sims.rigidbody.simulateRigidBody(free([2 2 3], [0.5 0 4]));
axis3 = squeeze(r.axes(:, :, 3));
fit = [r.t, ones(size(r.t))] \ unwrap(atan2(axis3(:, 2), axis3(:, 1)));
verifyEqual(testCase, fit(1), norm([2 2 3] .* [0.5 0 4]) / 2, 'RelTol', 1e-9);
verifyEqual(testCase, acosd(axis3(:, 3)), acosd(12 / norm([1 0 12])) * ones(size(r.t)), 'AbsTol', 1e-7, ...
    'The body cone half-angle stays fixed.');
end

function testHeavyTopAgainstEulerAngles(testCase)
% My own integration of the heavy top in Z-X-Z Euler angles (Lagrange's
% equation for θ with the conserved momenta p_φ, p_ψ; SciPy DOP853,
% RelTol 1e-12) for the looping-nutation preset.
p = top(80);
[p.precession, p.tilt, p.tspan, p.dt] = deal(-3, pi / 6, 4, 0.005);
r = dlab.sims.rigidbody.simulateRigidBody(p);
verifyEqual(testCase, interp1(r.t, r.theta, [1 2]), [1.7158982073 0.9413743571], 'AbsTol', 1e-7);
verifyEqual(testCase, r.precessionRate, 8.42257, 'RelTol', 1e-5);
verifyEqual(testCase, rad2deg(r.nutationAmplitude), 43.4225, 'RelTol', 1e-5);
verifyEqual(testCase, rad2deg(max(r.theta)), 116.845, 'RelTol', 1e-5);
verifyLessThan(testCase, [r.drift.energy r.drift.Lz r.drift.L3], 1e-9);
end

function testFastSteadyPrecessionHasNoNutation(testCase)
% The fast root of the steady-precession quadratic is steady too.
p = top(200);
p.tilt = pi / 6;
c = cos(p.tilt);
b = p.Is * p.spin;
p.precession = (b + sqrt(b^2 - 4 * p.It * c * p.m * p.g * p.l)) / (2 * p.It * c);   % 40.609 rad/s
r = dlab.sims.rigidbody.simulateRigidBody(p);
verifyLessThan(testCase, r.nutationAmplitude, 1e-6);
verifyEqual(testCase, r.precessionRate, 40.60917813, 'RelTol', 1e-7);
end

function testNutationFrequency(testCase)
% A fast top nods at about I_s ω₃ / I_t: 80 rad/s at 400 rad/s; my
% integration gives a period of 0.0830 s (75.7 rad/s; the approximation's
% error falls as 1/ω₃²: 1.3 % at 800 rad/s).
p = top(400);
[p.tilt, p.tspan, p.dt] = deal(pi / 6, 2, 0.0005);
r = dlab.sims.rigidbody.simulateRigidBody(p);
peaks = r.t(islocalmax(r.theta));
verifyEqual(testCase, mean(diff(peaks)), 0.0830017, 'RelTol', 2e-3);
end

function testRejectsBadInput(testCase)
verifyError(testCase, @() dlab.sims.rigidbody.simulateRigidBody(free([1 1 3], [1 1 1])), ...
    'rigidbody:InvalidParameter');
p = top(10);
p.Is = 0;
verifyError(testCase, @() dlab.sims.rigidbody.simulateRigidBody(p), 'rigidbody:InvalidParameter');
p = top(10);
p.Is = 2.1 * p.It;
verifyError(testCase, @() dlab.sims.rigidbody.simulateRigidBody(p), 'rigidbody:InvalidParameter', ...
    'I_s at most 2 I_t (a flat disc).');
end
