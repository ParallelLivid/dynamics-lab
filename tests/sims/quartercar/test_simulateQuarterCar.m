function tests = test_simulateQuarterCar
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = car()
road = struct('type', 'bump', 'height', 0.06, 'length', 1, 'start', 2, 'wavelength', 5, ...
    'isoClass', 3, 'seed', 1);
p = struct('ms', 300, 'mu', 40, 'ks', 20000, 'cs', 1500, 'kt', 200000, 'ct', 0, 'V', 20 / 3.6, ...
    'road', road, 'liftoff', true, 'tspan', 3, 'dt', 0.002, 'g', 9.81);
end

function testNaturalFrequencies(testCase)
% Independent reference: the roots of det(K − ω² M) = 0, worked by hand.
% The roots of det(K − ω² M) = 0 for the 2 × 2 undamped problem.
p = car();
r = dlab.sims.quartercar.simulateQuarterCar(p);
a = p.ms * p.mu;
b = -(p.ks * p.mu + (p.ks + p.kt) * p.ms);
c = p.ks * p.kt;
w2 = sort([(-b - sqrt(b^2 - 4 * a * c)) / (2 * a); (-b + sqrt(b^2 - 4 * a * c)) / (2 * a)]);
verifyEqual(testCase, r.frequencies, sqrt(w2) / (2 * pi), 'RelTol', 1e-10);
end

function testStaticResponseIsOne(testCase)
r = dlab.sims.quartercar.simulateQuarterCar(car());
verifyEqual(testCase, r.response.body(1), 1, 'AbsTol', 0.01, 'At low frequency the body follows the road.');
verifyLessThan(testCase, r.response.travel(1), 0.02);
end

function testSteadySineMatchesFrequencyResponse(testCase)
p = car();
p.road.type = 'sine';
p.road.height = 0.01;
p.road.start = 0;
p.road.wavelength = 5;
p.V = 5;                                    % 1 Hz
p.tspan = 20;
p.dt = 0.005;
r = dlab.sims.quartercar.simulateQuarterCar(p);
late = r.t > 12;
amplitude = (max(r.zs(late)) - min(r.zs(late))) / 2;
M = diag([p.ms p.mu]);
K = [p.ks -p.ks; -p.ks p.ks + p.kt];
C = [p.cs -p.cs; -p.cs p.cs + p.ct];
w = 2 * pi;
X = (-w^2 * M + 1i * w * C + K) \ [0; p.kt];
verifyEqual(testCase, amplitude, 0.01 * abs(X(1)), 'RelTol', 0.005);
verifyFalse(testCase, any(r.airborne));
end

function testFasterBumpIsHarsher(testCase)
p = car();
p.V = 10 / 3.6;
slow = dlab.sims.quartercar.simulateQuarterCar(p);
p.V = 60 / 3.6;
fast = dlab.sims.quartercar.simulateQuarterCar(p);
verifyGreaterThan(testCase, max(abs(fast.bodyAccel)), 2 * max(abs(slow.bodyAccel)));
verifyFalse(testCase, any(slow.airborne));
end

function testWheelLiftsOffAggressiveBump(testCase)
p = car();
p.V = 80 / 3.6;
r = dlab.sims.quartercar.simulateQuarterCar(p);
verifyTrue(testCase, any(r.airborne));
verifyGreaterThanOrEqual(testCase, min(r.tireForce), 0, 'The tire cannot pull the road.');
p.liftoff = false;
r = dlab.sims.quartercar.simulateQuarterCar(p);
verifyLessThan(testCase, min(r.tireForce), 0, 'Without lift-off the tire pulls.');
end

function testRandomRoad(testCase)
road = car().road;
road.type = 'random';
road.start = 0;
road.seed = 7;
ds = 0.02;
s = (0:ds:4000)';
z = dlab.sims.quartercar.roadProfile(road, s);
verifyEqual(testCase, dlab.sims.quartercar.roadProfile(road, s), z, 'The same seed gives the same road.');
road.seed = 8;
verifyNotEqual(testCase, dlab.sims.quartercar.roadProfile(road, s), z);
% Band-averaged spectrum: slope −2, and G(0.1 cycles/m) = 256e-6 m³ for class C.
N = numel(z);
P = abs(fft(z - mean(z))).^2 / N^2;
n = (0:N - 1)' / (N * ds);
edges = 2.^(-4:0.5:1);
centers = sqrt(edges(1:end-1) .* edges(2:end));
density = zeros(size(centers));
for k = 1:numel(centers)
    band = n >= edges(k) & n < edges(k + 1);
    density(k) = 2 * sum(P(band)) / (edges(k + 1) - edges(k));
end
fit = polyfit(log(centers), log(density), 1);
verifyEqual(testCase, fit(1), -2, 'AbsTol', 0.2);
verifyEqual(testCase, exp(polyval(fit, log(0.1))), 256e-6, 'RelTol', 0.15);
end

function testRoadSlopes(testCase)
% The height is the integral of the slope (no jumps), for every road.
types = {'bump', 'pothole', 'step', 'sine', 'random'};
s = (0:0.001:6)';
for k = 1:numel(types)
    road = car().road;
    road.type = types{k};
    [z, slope] = dlab.sims.quartercar.roadProfile(road, s);
    integral = [0; cumsum((slope(1:end-1) + slope(2:end)) / 2 * 0.001)];
    verifyLessThan(testCase, max(abs(z - integral)), 0.001 * max(abs(slope)), types{k});    % one step at a kink
end
end

function testRejectsBadInput(testCase)
p = car();
p.ms = 0;
verifyError(testCase, @() dlab.sims.quartercar.simulateQuarterCar(p), 'quartercar:InvalidParameter');
p = car();
p.road.type = 'cobbles';
verifyError(testCase, @() dlab.sims.quartercar.simulateQuarterCar(p), 'quartercar:InvalidParameter');
end

function testRejectsTooManySamples(testCase)
% 600 s at 10 µs would be 6·10⁷ samples (gigabytes): refused, and the
% message names the output step.
p = car();
[p.tspan, p.dt] = deal(600, 1e-5);
verifyError(testCase, @() dlab.sims.quartercar.simulateQuarterCar(p), 'quartercar:TooManySamples');
end

function testAgainstAnIndependentIntegration(testCase)
% scipy solve_ivp (RK45, rtol 1e-10, steps ≤ 0.2 ms) of the same model
% with its own road, sampled every 2 ms: the defaults over the 6 cm bump
% at 20 km/h, and the worn dampers at 40 km/h (lift-off, 0.172–0.174 s).
r = dlab.sims.quartercar.simulateQuarterCar(car());
W = r.staticLoad;
verifyEqual(testCase, sqrt(mean(r.bodyAccel.^2)), 1.37178, 'RelTol', 1e-4);
verifyEqual(testCase, max(abs(r.bodyAccel)), 7.89139, 'RelTol', 1e-4);
verifyEqual(testCase, 100 * max(abs(r.travel)), 4.87182, 'RelTol', 1e-4);
verifyEqual(testCase, sqrt(mean((r.tireForce - W).^2)) / W, 0.144333, 'RelTol', 1e-4);
verifyEqual(testCase, min(r.tireForce), 849.348, 'RelTol', 1e-4);
p = car();
[p.cs, p.V] = deal(300, 40 / 3.6);
r = dlab.sims.quartercar.simulateQuarterCar(p);
verifyEqual(testCase, sqrt(mean(r.bodyAccel.^2)), 1.54740, 'RelTol', 1e-3);
verifyEqual(testCase, max(abs(r.bodyAccel)), 6.74779, 'RelTol', 1e-4);
verifyEqual(testCase, sum(diff(r.t) .* r.airborne(1:end-1)), 0.173, 'AbsTol', 0.002);
end

function testWithoutLiftoffTheTirePullsInstead(testCase)
% Lift-off off: a negative load is "pulling", not "airborne".
p = car();
[p.V, p.liftoff] = deal(80 / 3.6, false);
r = dlab.sims.quartercar.simulateQuarterCar(p);
verifyFalse(testCase, any(r.airborne));
verifyTrue(testCase, any(r.pulling));
verifyEqual(testCase, r.pulling, r.tireForce < 0);
verifyEqual(testCase, min(r.tireForce), -9263.7, 'RelTol', 1e-3);    % scipy: −9263.725 N
end

function testKerbRaisesTheCar(testCase)
% A 10 cm kerb: after it both masses sit 10 cm higher, on the static load.
p = car();
[p.road.type, p.road.height, p.tspan] = deal('step', 0.1, 5);
r = dlab.sims.quartercar.simulateQuarterCar(p);
verifyEqual(testCase, [r.zs(end) r.zu(end)], [0.1 0.1], 'AbsTol', 1e-4);
verifyEqual(testCase, r.tireForce(end), r.staticLoad, 'RelTol', 1e-3);
end
