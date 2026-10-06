function tests = test_simulateDcMotor
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
% The app's default motor: R = 2 Ω, L = 5 mH, K = 0.1, J = 1e-3, b = 1e-4.
p = struct('R', 2, 'L', 5e-3, 'K', 0.1, 'J', 1e-3, 'b', 1e-4, 'Vmax', 24, 'mode', 'open', ...
    'Kp', 0, 'Ki', 0, 'Kd', 0, 'antiWindup', 'none', 'command', @(t) 12 + 0 * t, ...
    'load', @(t) 0 * t, 'tspan', 1, 'dt', 1e-3, 'stepWindow', []);
end

function [wn, zeta] = positionLoop(p)
% The L = 0 position loop with V = Kp e − Kd ω:
% J θ'' + (K²/R + b + K Kd/R) θ' + (K Kp/R) θ = (K Kp/R) θ_ref.
wn = sqrt(p.K * p.Kp / (p.R * p.J));
zeta = (p.K^2 / p.R + p.b + p.K * p.Kd / p.R) / p.J / (2 * wn);
end

function testFirstOrderSpeedStep(testCase)
% Independent reference: the closed-form first-order step response.
% With L = 0 a voltage step gives ω = G V (1 − e^(−t/τ)),
% τ = J R / (K² + b R), G = K / (K² + b R).
p = base();
[p.L, p.tspan, p.stepWindow] = deal(0, 2, [0 2]);
r = dlab.sims.dcmotor.simulateDcMotor(p);
tau = p.J * p.R / (p.K^2 + p.b * p.R);
G = p.K / (p.K^2 + p.b * p.R);
verifyEqual(testCase, r.tauMech, tau, 'RelTol', 1e-12);
verifyEqual(testCase, r.gain, G, 'RelTol', 1e-12);
verifyEqual(testCase, tau, 0.196078431372549, 'RelTol', 1e-12, 'τ = 2e-3 / 0.0102 s.');
exact = 12 * G * (1 - exp(-r.t / tau));
verifyEqual(testCase, r.omega, exact, 'AbsTol', 1e-7 * 12 * G);
verifyEqual(testCase, r.i, (12 - p.K * r.omega) / p.R, 'AbsTol', 1e-9, 'L = 0: i = (V − K ω) / R.');
verifyEqual(testCase, r.step.t63, tau, 'RelTol', 1e-3);
verifyEqual(testCase, r.step.rise, tau * log(9), 'RelTol', 2e-3);
verifyEqual(testCase, r.step.overshoot, 0);
verifyEqual(testCase, r.step.settling, tau * log(50), 'RelTol', 2e-3);
verifyEqual(testCase, r.openPoles, -1 / tau, 'RelTol', 1e-12);
end

function testTwoPolesWithInductance(testCase)
% The poles solve (J s + b)(L s + R) + K² = 0, and the speed step response
% is ω = G V [1 + (p2 e^(p1 t) − p1 e^(p2 t)) / (p1 − p2)].
p = base();
p.tspan = 0.5;
r = dlab.sims.dcmotor.simulateDcMotor(p);
poles = sort(roots([p.J * p.L, p.J * p.R + p.b * p.L, p.b * p.R + p.K^2]));
verifyEqual(testCase, sort(r.openPoles), poles, 'RelTol', 1e-10);
verifyEqual(testCase, poles, [-394.9346; -5.165412], 'RelTol', 1e-6);
p1 = poles(1);
p2 = poles(2);
G = p.K / (p.K^2 + p.b * p.R);
exact = 12 * G * (1 + (p2 * exp(p1 * r.t) - p1 * exp(p2 * r.t)) / (p1 - p2));
verifyEqual(testCase, r.omega, exact, 'AbsTol', 1e-6 * 12 * G);
verifyEqual(testCase, sort(r.closedPoles), poles, 'RelTol', 1e-10, 'Open loop: closed = open.');
end

function testLinearModelIsTheJacobian(testCase)
for L = [5e-3 0]
    p = base();
    p.L = L;
    m = dlab.sims.dcmotor.linearModel(p);
    x0 = zeros(numel(m.states), 1);
    A = dlab.physics.jacobian(@(x) dlab.sims.dcmotor.dynamics(x, [0; 0], p), x0);
    B = dlab.physics.jacobian(@(u) dlab.sims.dcmotor.dynamics(x0, u, p), [0; 0]);
    verifyEqual(testCase, A, m.A, 'AbsTol', 1e-6 * norm(m.A));
    verifyEqual(testCase, B, m.B, 'AbsTol', 1e-6 * norm(m.B));
end
end

function testPositionPIsSecondOrder(testCase)
% L = 0 and P control: overshoot e^(−πζ/√(1−ζ²)), peak time π/ω_d, and the
% exact 2 % settling time of the second-order step response.
p = base();
[p.L, p.mode, p.Kp, p.tspan, p.dt] = deal(0, 'position', 5, 4, 5e-4);
p.command = @(t) 1 + 0 * t;
p.stepWindow = [0 4];
r = dlab.sims.dcmotor.simulateDcMotor(p);
[wn, zeta] = positionLoop(p);
verifyEqual(testCase, [wn zeta], [15.8114 0.16128], 'RelTol', 1e-4);
verifyEqual(testCase, sort(r.closedPoles), sort(roots([1, 2 * zeta * wn, wn^2])), 'RelTol', 1e-10);
overshoot = 100 * exp(-pi * zeta / sqrt(1 - zeta^2));
verifyEqual(testCase, r.step.overshoot, overshoot, 'RelTol', 2e-3);
wd = wn * sqrt(1 - zeta^2);
[~, k] = max(r.theta);
verifyEqual(testCase, r.t(k), pi / wd, 'AbsTol', p.dt);
% The analytic response, settled when it last leaves the ±2 % band.
tf = (0:1e-6:4)';
y = 1 - exp(-zeta * wn * tf) / sqrt(1 - zeta^2) .* sin(wd * tf + acos(zeta));
settled = tf(find(abs(y - 1) > 0.02, 1, 'last') + 1);
verifyEqual(testCase, r.step.settling, settled, 'AbsTol', 2e-3);
% The envelope rule ln(50/√(1−ζ²))/(ζ ω_n) bounds it within half a period π/ω_d.
envelope = log(50 / sqrt(1 - zeta^2)) / (zeta * wn);
verifyGreaterThan(testCase, r.step.settling, envelope - pi / wd);
verifyLessThanOrEqual(testCase, r.step.settling, envelope);
end

function testPositionPWithInductanceMatchesDominantPoles(testCase)
% With L = 5 mH the third (electrical) pole is far away: the dominant pair
% still predicts the overshoot within 3 %, and the settling time within the
% half period of its envelope.
p = base();
[p.mode, p.Kp, p.tspan] = deal('position', 5, 4);
p.command = @(t) pi / 2 + 0 * t;
p.stepWindow = [0 4];
r = dlab.sims.dcmotor.simulateDcMotor(p);
pair = r.closedPoles(imag(r.closedPoles) > 0);
zeta = -real(pair) / abs(pair);
verifyEqual(testCase, r.step.overshoot, 100 * exp(-pi * zeta / sqrt(1 - zeta^2)), 'RelTol', 0.03);
envelope = log(50 / sqrt(1 - zeta^2)) / -real(pair);
verifyGreaterThan(testCase, r.step.settling, envelope - pi / imag(pair));
verifyLessThanOrEqual(testCase, r.step.settling, envelope);
verifyEqual(testCase, r.error(end), 0, 'AbsTol', 1e-3, 'A type-1 loop: no steady error to a step.');
end

function testPDAddsDamping(testCase)
p = base();
[p.L, p.mode, p.Kp, p.Kd, p.tspan, p.dt] = deal(0, 'position', 10, 0.6, 1, 2e-4);
p.command = @(t) 1 + 0 * t;
p.stepWindow = [0 1];
r = dlab.sims.dcmotor.simulateDcMotor(p);
[~, zeta] = positionLoop(p);
verifyEqual(testCase, zeta, 0.7849, 'AbsTol', 1e-4);
verifyEqual(testCase, r.step.overshoot, 100 * exp(-pi * zeta / sqrt(1 - zeta^2)), 'RelTol', 0.01);
end

function testSpeedPLeavesASteadyError(testCase)
% P speed control: ω_ss = r G Kp / (1 + G Kp).
p = base();
[p.mode, p.Kp, p.tspan] = deal('speed', 0.3, 2);
p.command = @(t) 60 + 0 * t;
r = dlab.sims.dcmotor.simulateDcMotor(p);
G = p.K / (p.K^2 + p.b * p.R);
verifyEqual(testCase, r.error(end), 60 / (1 + G * p.Kp), 'RelTol', 1e-6);
end

function testSpeedPIHasNoSteadyError(testCase)
p = base();
[p.mode, p.Kp, p.Ki, p.tspan] = deal('speed', 0.3, 3, 3);
p.command = @(t) 60 + 0 * t;
r = dlab.sims.dcmotor.simulateDcMotor(p);
verifyLessThan(testCase, abs(r.error(end)), 1e-6 * 60);
verifyLessThan(testCase, max(real(r.closedPoles)), 0);
% ... and against a constant load torque.
p.load = @(t) 0.05 + 0 * t;
r = dlab.sims.dcmotor.simulateDcMotor(p);
verifyLessThan(testCase, abs(r.error(end)), 1e-6 * 60);
verifyEqual(testCase, r.integral(end) * p.Ki, ...
    60 * (p.K^2 + p.b * p.R) / p.K + 0.05 * p.R / p.K, 'RelTol', 1e-6, ...
    'The integral supplies the whole steady voltage.');
end

function testLoadTorqueAndPosition(testCase)
% PD holds a load τ with the error τ R / (K Kp); the integral removes it.
p = base();
[p.mode, p.Kp, p.Kd, p.tspan] = deal('position', 10, 0.6, 2);
p.command = @(t) 0 * t;
p.load = @(t) 0.1 * (t >= 0.2);
r = dlab.sims.dcmotor.simulateDcMotor(p);
verifyEqual(testCase, r.error(end), 0.1 * p.R / (p.K * p.Kp), 'RelTol', 1e-6);
verifyEqual(testCase, r.i(end), 0.1 / p.K, 'RelTol', 1e-6, 'The motor carries the load: i = τ / K.');
p.Ki = 50;
r = dlab.sims.dcmotor.simulateDcMotor(p);
verifyLessThan(testCase, abs(r.error(end)), 1e-4);
end

function testWindupAndClamping(testCase)
% A 360° step with a 12 V supply: the integral winds up while saturated.
p = base();
[p.mode, p.Kp, p.Ki, p.Kd, p.Vmax, p.tspan] = deal('position', 10, 50, 0.6, 12, 1.5);
p.command = @(t) 2 * pi * (t >= 0.05);
p.stepWindow = [0.05 1.5];
wound = dlab.sims.dcmotor.simulateDcMotor(p);
p.antiWindup = 'clamping';
clamped = dlab.sims.dcmotor.simulateDcMotor(p);
verifyTrue(testCase, any(wound.saturated) && any(clamped.saturated));
verifyLessThanOrEqual(testCase, max(abs([wound.V; clamped.V])), 12);
verifyGreaterThan(testCase, max(abs(wound.Vcmd)), 12);
verifyGreaterThan(testCase, wound.step.overshoot, 2 * clamped.step.overshoot, ...
    'Windup overshoots far more than clamping.');
verifyEqual(testCase, wound.step.overshoot, 48.6, 'AbsTol', 1);
verifyEqual(testCase, clamped.step.overshoot, 13.5, 'AbsTol', 1);
verifyGreaterThan(testCase, max(wound.integral), 1.5 * max(clamped.integral));
end

function testEnergyBalance(testCase)
% ∫ V i dt = ½ J ω² + ½ L i² + ∫ (R i² + b ω² + τ ω) dt.
p = base();
[p.mode, p.Kp, p.Kd, p.Ki, p.dt, p.tspan] = deal('position', 10, 0.6, 20, 1e-4, 1);
p.command = @(t) pi * (t >= 0.05);
p.load = @(t) 0.05 * (t >= 0.5);
r = dlab.sims.dcmotor.simulateDcMotor(p);
stored = 0.5 * p.J * r.omega(end)^2 + 0.5 * p.L * r.i(end)^2;
lost = trapz(r.t, r.copperLoss + p.b * r.omega.^2 + r.load .* r.omega);
verifyEqual(testCase, r.energy(end), stored + lost, 'RelTol', 1e-5);
% The energy is integrated with the motion, so the app's coarser output
% step gives the same numbers (a sum over its samples was 0.1 % low). The
% command and the load act from t = 0, so both grids see the same inputs;
% the solver steps differ (h = 0.2/395 s against 10⁻⁴ s) where the voltage
% leaves the limit, hence 10⁻⁴.
[p.command, p.load] = deal(@(t) pi + 0 * t, @(t) 0.05 + 0 * t);
fine = dlab.sims.dcmotor.simulateDcMotor(p);
p.dt = 1e-3;
coarse = dlab.sims.dcmotor.simulateDcMotor(p);
verifyEqual(testCase, coarse.energy, interp1(fine.t, fine.energy, coarse.t), 'AbsTol', 1e-4 * fine.energy(end));
stored = 0.5 * p.J * fine.omega(end)^2 + 0.5 * p.L * fine.i(end)^2;
lost = trapz(fine.t, fine.copperLoss + p.b * fine.omega.^2 + fine.load .* fine.omega);
verifyEqual(testCase, coarse.energy(end), stored + lost, 'RelTol', 1e-4);
end

function testStepResponseHelper(testCase)
t = (0:1e-4:20)';
s = dlab.sims.dcmotor.stepResponse(t, 3 - 2 * exp(-t), [0 20]);
verifyEqual(testCase, [s.t63 s.rise s.settling], [1 log(9) log(50)], 'AbsTol', 1e-6);
verifyEqual(testCase, [s.initial s.overshoot], [1 0], 'AbsTol', 1e-6);
s = dlab.sims.dcmotor.stepResponse(t, ones(size(t)), [0 20]);
verifyTrue(testCase, isnan(s.rise) && isnan(s.overshoot), 'No change: nothing to measure.');
end

function testRejectsBadInput(testCase)
p = base();
p.R = 0;
verifyError(testCase, @() dlab.sims.dcmotor.simulateDcMotor(p), 'dcmotor:InvalidParameter');
p = base();
p.mode = 'torque';
verifyError(testCase, @() dlab.sims.dcmotor.simulateDcMotor(p), 'dcmotor:InvalidParameter');
p = base();
p.L = -1;
verifyError(testCase, @() dlab.sims.dcmotor.simulateDcMotor(p), 'dcmotor:InvalidParameter');
% Both within their own ranges, together 10⁹ samples: refused at once.
p = base();
[p.tspan, p.dt] = deal(1000, 1e-6);
verifyError(testCase, @() dlab.sims.dcmotor.simulateDcMotor(p), 'dcmotor:TooManySamples');
end

function testCancelStopsEarly(testCase)
p = base();
p.progressFcn = @(fraction) fraction > 0.3;
r = dlab.sims.dcmotor.simulateDcMotor(p);
verifyLessThan(testCase, r.t(end), 0.5);
end
