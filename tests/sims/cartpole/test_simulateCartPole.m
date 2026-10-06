function tests = test_simulateCartPole
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
p = struct('M', 1, 'm', 0.1, 'l', 0.5, 'poleType', 'rod', 'b', 0.1, 'g', 9.81, 'x0', 0, 'xd0', 0, ...
    'theta0', 5 * pi / 180, 'thetad0', 0, 'controller', 'lqr', 'Kp', 40, 'Ki', 0, 'Kd', 8, 'Kx', 1, ...
    'Kv', 2, 'qx', 10, 'qxd', 1, 'qtheta', 100, 'qthetad', 1, 'r', 0.1, 'Fmax', 20, ...
    'xref', @(t) 0, 'disturbance', @(t) 0, 'track', 4, 'allowFall', false, 'tspan', 8, 'dt', 0.01);
end

function t = settling(r)
last = find(abs(r.theta) > pi / 180, 1, 'last');
t = r.t(last + 1);
end

function testOpenLoopPole(testCase)
p = base();
[p.poleType, p.b, p.controller] = deal('point', 0, 'none');
model = struct('M', p.M, 'm', p.m, 'l', p.l, 'I', 0, 'b', 0, 'g', p.g);
[A, B] = dlab.sims.cartpole.linearModel(model);
verifyEqual(testCase, max(real(eig(A))), sqrt(p.g * (p.M + p.m) / (p.M * p.l)), 'RelTol', 1e-8);
% The linear model is the Jacobian of the nonlinear dynamics at upright.
J = dlab.physics.jacobian(@(s) dlab.sims.cartpole.dynamics(s, 0, model), zeros(4, 1));
verifyEqual(testCase, J, A, 'AbsTol', 1e-6);
G = dlab.physics.jacobian(@(F) dlab.sims.cartpole.dynamics(zeros(4, 1), F, model), 0);
verifyEqual(testCase, G, B, 'AbsTol', 1e-8);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "fell");
verifyEqual(testCase, abs(r.theta(end)), pi / 2, 'AbsTol', 1e-6, 'Stops where the pole is horizontal.');
end

function testLqrBalancesAndReturns(testCase)
p = base();
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "completed");
verifyLessThan(testCase, settling(r), 3);
verifyEqual(testCase, r.closedPoles, eig(r.A - r.B * r.K), 'AbsTol', 1e-10);
verifyLessThan(testCase, max(real(r.closedPoles)), 0);
verifyLessThan(testCase, abs(r.x(end)), 0.01);
[X, ok] = dlab.physics.care(r.A, r.B, diag([10 1 100 1]), 0.1);
verifyTrue(testCase, ok);
residual = r.A' * X + X * r.A - X * r.B * (r.B' * X) / 0.1 + diag([10 1 100 1]);
verifyLessThan(testCase, norm(residual) / norm(X), 1e-10);
end

function testWeakMotorFails(testCase)
p = base();
p.Fmax = 1;
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "fell");
verifyTrue(testCase, any(r.saturated));
verifyLessThanOrEqual(testCase, max(abs(r.F)), 1);
end

function testPidOnAngleLeavesTheCartAdrift(testCase)
p = base();
[p.controller, p.Kx, p.Kv, p.Ki] = deal('pid', 0, 0, 0);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyLessThan(testCase, min(abs(r.closedPoles)), 1e-9, 'Nothing holds the cart position.');
p.Kx = 1;
p.Kv = 2;
r = dlab.sims.cartpole.simulateCartPole(p);
verifyLessThan(testCase, max(real(r.closedPoles)), 0, 'The cart loop makes every pole stable.');
verifyLessThan(testCase, abs(r.x(end)), 0.05);
end

function testRejectsAKick(testCase)
p = base();
p.theta0 = 0;
p.disturbance = @(t) 10 * (t >= 1 & t < 1.1);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyGreaterThan(testCase, max(abs(r.theta)), 2 * pi / 180, 'The kick tilts the pole.');
verifyLessThan(testCase, max(abs(r.theta(r.t >= 4))), pi / 180);
end

function testReferenceStep(testCase)
p = base();
p.theta0 = 0;
p.xref = @(t) double(t >= 1);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.x(end), 1, 'AbsTol', 0.01);
verifyLessThan(testCase, min(r.x(r.t > 1)), 0, 'The cart first backs away to lean the pole forward.');
end

function testEndStop(testCase)
p = base();
[p.controller, p.Kx, p.Kv, p.Ki, p.Kp, p.Kd] = deal('pid', 0, 0, 0, 40, 8);
p.tspan = 30;
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "endstop");
verifyEqual(testCase, abs(r.x(end)), 2, 'AbsTol', 1e-6);
end

function testAllowFallCompletesTheRun(testCase)
% Past horizontal is only recorded when the run may go on.
p = base();
[p.controller, p.theta0, p.allowFall, p.track, p.tspan] = deal('none', 0.2, true, 100, 3);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "completed");
verifyEqual(testCase, r.t(end), 3, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, max(abs(r.theta)), pi / 2);
verifyLessThan(testCase, r.fallTime, 3);
verifyEqual(testCase, abs(interp1(r.t, r.theta, r.fallTime)), pi / 2, 'AbsTol', 1e-3);
p.allowFall = false;
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "fell");
verifyEqual(testCase, r.fallTime, r.t(end), 'AbsTol', 1e-12);
verifyTrue(testCase, isnan(dlab.sims.cartpole.simulateCartPole(base()).fallTime));
end

function testEquationsMatchLagrange(testCase)
% Against Lagrange's equations in mass-matrix form, written out here:
% T = ½(M+m)ẋ² + m l cos θ ẋ θ' + ½(I + m l²)θ'², V = m g l cos θ.
rng(7);
for pole = ["rod" "point"]
    for trial = 1:50
        [M, m, l, b] = deal(0.2 + 3 * rand, 0.05 + 2 * rand, 0.1 + 2 * rand, rand);
        I = (pole == "rod") * m * (2 * l)^2 / 12;
        s = [randn; randn; 3 * randn; 3 * randn];
        F = 10 * randn;
        model = struct('M', M, 'm', m, 'l', l, 'I', I, 'b', b, 'g', 9.81);
        Mm = [M + m, m * l * cos(s(3)); m * l * cos(s(3)), I + m * l^2];
        acc = Mm \ [F - b * s(2) + m * l * sin(s(3)) * s(4)^2; m * 9.81 * l * sin(s(3))];
        verifyEqual(testCase, dlab.sims.cartpole.dynamics(s, F, model), [s(2); acc(1); s(4); acc(2)], ...
            'RelTol', 1e-12, 'AbsTol', 1e-12);
    end
end
end

function testUnstablePoleAndLqrAgainstHandValues(testCase)
% Independent reference: the topple rate and LQR gains worked by hand.
% Rod: I = m (2l)²/12; the frictionless topple rate is
% √((M+m) m g l / ((M+m)(I + m l²) − m² l²)) = 3.973878 1/s. The LQR gain
% from the Hamiltonian's stable eigenvectors (worked out here).
p = base();
[p.b, p.controller] = deal(0, 'none');
r = dlab.sims.cartpole.simulateCartPole(p);
[M, m, l, g] = deal(p.M, p.m, p.l, p.g);
I = m * (2 * l)^2 / 12;
verifyEqual(testCase, max(real(r.openPoles)), sqrt((M + m) * m * g * l / ((M + m) * (I + m * l^2) - m^2 * l^2)), ...
    'RelTol', 1e-10);
verifyEqual(testCase, max(real(r.openPoles)), 3.973878, 'AbsTol', 1e-6);
r = dlab.sims.cartpole.simulateCartPole(base());
Q = diag([10 1 100 1]);
H = [r.A, -r.B * r.B' / 0.1; -Q, -r.A'];
[V, E] = eig(H);
V = V(:, real(diag(E)) < 0);
K = r.B' * real(V(5:8, :) / V(1:4, :)) / 0.1;
verifyEqual(testCase, r.K, K, 'RelTol', 1e-9);
verifyEqual(testCase, r.K, [-10 -12.23461779 -78.10670448 -18.67669977], 'AbsTol', 1e-7);
verifyEqual(testCase, sort(real(r.closedPoles)), [-6.4029305; -6.4029305; -1.3436216; -1.3436216], 'AbsTol', 1e-6);
end

function testPidPolesMatchTheCharacteristicPolynomial(testCase)
% det([(M+m)s² + b s − Kx − Kv s,  m l s² − Kp − Kd s − Ki/s;  m l s²,  J s² − m g l]) = 0.
p = base();
p.controller = 'pid';
for G = [40 0 8 1 2; 40 1 8 0 0; 40 0 8 0 0; 40 1 8 1 2]'
    [p.Kp, p.Ki, p.Kd, p.Kx, p.Kv] = deal(G(1), G(2), G(3), G(4), G(5));
    r = dlab.sims.cartpole.simulateCartPole(p);
    [M, m, l, b, g] = deal(p.M, p.m, p.l, p.b, p.g);
    J = m * (2 * l)^2 / 12 + m * l^2;
    ch = conv(conv([1 0], [M + m, b - p.Kv, -p.Kx]), [J 0 -m * l * g]) - ...
        conv([m * l, -p.Kd, -p.Kp, -p.Ki], [m * l 0 0]);
    expected = roots(ch);
    if p.Ki == 0
        [~, k] = min(abs(expected));
        expected(k) = [];               % the s multiplied in for Ki
    end
    verifyEqual(testCase, sort(r.closedPoles), sort(expected), 'AbsTol', 1e-7);
end
end

function testEnergyAndMomentumWithoutControl(testCase)
% No control, no friction: the pole falls and swings round; energy and
% horizontal momentum stay put (the run goes on past the fall).
for pole = ["rod" "point"]
    p = base();
    [p.controller, p.b, p.allowFall, p.track, p.tspan, p.theta0, p.poleType] = ...
        deal('none', 0, true, 1000, 10, pi / 6, char(pole));
    r = dlab.sims.cartpole.simulateCartPole(p);
    md = r.model;
    J = md.I + md.m * md.l^2;
    E = 0.5 * (md.M + md.m) * r.xd.^2 + md.m * md.l * cos(r.theta) .* r.xd .* r.thetad + ...
        0.5 * J * r.thetad.^2 + md.m * md.g * md.l * cos(r.theta);
    px = (md.M + md.m) * r.xd + md.m * md.l * cos(r.theta) .* r.thetad;
    verifyGreaterThan(testCase, max(abs(r.theta)), pi, 'It swings past hanging.');
    verifyLessThan(testCase, max(abs(E - E(1))) / E(1), 1e-7);
    verifyLessThan(testCase, max(abs(px)), 1e-7);
end
end

function testWeakMotorSaturates(testCase)
% 2 N against a 10° tilt: the cart races under the pole, overshoots, and
% reaches the end stop at 1.5741 s with the pole 43.8° the other way
% (my own integration: 1.57413 s, −43.832°, saturated 98.1 % of the time).
p = base();
[p.theta0, p.Fmax] = deal(10 * pi / 180, 2);
r = dlab.sims.cartpole.simulateCartPole(p);
verifyEqual(testCase, r.termination, "endstop");
verifyEqual(testCase, r.t(end), 1.57413, 'AbsTol', 1e-4);
verifyEqual(testCase, rad2deg(r.theta(end)), -43.832, 'AbsTol', 1e-2);
verifyEqual(testCase, max(abs(r.F)), 2, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, mean(r.saturated), 0.97);
% 2.81 N is the least that catches it (the lesson says so).
p.Fmax = 2.85;
verifyEqual(testCase, dlab.sims.cartpole.simulateCartPole(p).termination, "completed");
p.Fmax = 2.8;
verifyNotEqual(testCase, dlab.sims.cartpole.simulateCartPole(p).termination, "completed");
end

function testRejectsZeroPositionWeight(testCase)
p = base();
p.qx = 0;
verifyError(testCase, @() dlab.sims.cartpole.simulateCartPole(p), 'cartpole:InvalidParameter');
end
