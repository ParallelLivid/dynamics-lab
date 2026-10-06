function tests = test_pendulum_solve
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function testRequestedTimes(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(1, 1, 0.1, 30, 0, 9.81, 1.05, 0.2);
verifyEmpty(testCase, errMsg);
verifyEqual(testCase, sol.t(1), 0);
verifyEqual(testCase, sol.t(end), 1.05, 'AbsTol', eps(1.05));
verifyEqual(testCase, diff(sol.t(1:end-1)), 0.2 * ones(5, 1), 'AbsTol', 1e-14);
end

function testTwoPointOutputGrid(testCase)
for damping = [0.1 100]
    for dt = [1 2]
        [sol, errMsg] = dlab.sims.pendulum.pendulum_solve(1, 1, damping, 30, 0, 9.81, 1, dt);
        verifyEmpty(testCase, errMsg);
        verifyEqual(testCase, sol.t, [0; 1]);
        verifySize(testCase, sol.theta, [2 1]);
    end
end
end

function testUndampedEnergyConservation(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(1, 1, 0, 170, 0, 9.81, 20, 0.01);
verifyEmpty(testCase, errMsg);
relativeRange = (max(sol.E) - min(sol.E)) / sol.E(1);
verifyLessThan(testCase, relativeRange, 1e-8);
end

function testSmallAnglePeriod(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(1, 1, 0, 5, 0, 9.81, 20, 0.005);
verifyEmpty(testCase, errMsg);
peaks = find(sol.theta(2:end-1) > sol.theta(1:end-2) & ...
             sol.theta(2:end-1) >= sol.theta(3:end)) + 1;
measuredPeriod = mean(diff(sol.t(peaks)));
expectedPeriod = 2 * pi / sqrt(9.81);
verifyLessThan(testCase, abs(measuredPeriod - expectedPeriod) / expectedPeriod, 1e-3);
end

function testDampedEnergyDoesNotIncrease(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(1, 1, 0.1, 30, 0, 9.81, 15, 0.02);
verifyEmpty(testCase, errMsg);
verifyLessThanOrEqual(testCase, max(diff(sol.E)), 1e-10);
end

function testGeometryMatchesAngle(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(2, 3, 0.2, 40, -1, 9.81, 2, 0.1);
verifyEmpty(testCase, errMsg);
verifyEqual(testCase, hypot(sol.bx, sol.by), 2 * ones(size(sol.t)), 'AbsTol', 1e-12);
end

function testInvalidInputReturnsMessage(testCase)
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(0, 1, 0.1, 30, 0, 9.81, 1, 0.1);
verifyEmpty(testCase, sol);
verifyNotEmpty(testCase, errMsg);
verifySubstring(testCase, errMsg, 'L');
end

function testStiffCase(testCase)
startTime = tic;
[sol, errMsg] = dlab.sims.pendulum.pendulum_solve(0.1, 0.01, 50, 180, 50, 30, 10, 0.001);
verifyEmpty(testCase, errMsg);
verifyEqual(testCase, sol.t(end), 10);
verifyLessThan(testCase, toc(startTime), 5);
end
