function tests = testFlightSim
%TESTFLIGHTSIM Verify model invariants and termination behavior.
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function testRotationMatrix(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    state = zeros(12,1);
    state(7:9) = [0.3; -0.4; 1.2];
    [~, rotation] = dlab.sims.flight6dof.dynamics(0, state, zeroControl(), config.aircraft);
    verifyLessThan(testCase, norm(rotation' * rotation - eye(3), 'fro'), 1e-12);
    verifyEqual(testCase, det(rotation), 1, 'AbsTol', 1e-12);
end

function testGravityAtRest(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    derivative = dlab.sims.flight6dof.dynamics(0, [zeros(11,1); -100], ...
        zeroControl(), config.aircraft);
    verifyEqual(testCase, derivative(1:3), [0; 0; 9.81], 'AbsTol', 1e-12);
end

function testLateralDragOpposesVelocity(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    state = zeros(12,1);
    state(2) = 20;
    state(12) = -100;
    derivative = dlab.sims.flight6dof.dynamics(0, state, zeroControl(), config.aircraft);
    verifyEqual(testCase, derivative(1), 0, 'AbsTol', 1e-12);
    verifyLessThan(testCase, derivative(2), 0);
end

function testRateDampingUsesInverseSeconds(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    state = zeros(12,1);
    state(4) = 1;
    derivative = dlab.sims.flight6dof.dynamics(0, state, zeroControl(), config.aircraft);
    verifyEqual(testCase, derivative(4), -config.aircraft.damp_p, ...
        'AbsTol', 1e-12);
end

function testInertiaCoupling(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    state = zeros(12,1);
    state(5:6) = 1;
    derivative = dlab.sims.flight6dof.dynamics(0, state, zeroControl(), config.aircraft);
    expected = (config.aircraft.Iy - config.aircraft.Iz) / config.aircraft.Ix;
    verifyEqual(testCase, derivative(4), expected, 'AbsTol', 1e-12);
end

function testGroundTermination(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    config.duration = 2;
    config.initial = struct('u0',0,'v0',0,'w0',0,'p0',0,'q0',0,'r0',0, ...
        'phi0',0,'theta0',0,'psi0',0,'alt0',1);
    config.control = zeroControl();
    result = dlab.sims.flight6dof.simulate6dof(config);
    verifyEqual(testCase, result.termination, 'ground contact');
    verifyLessThan(testCase, result.t(end), config.duration);
end

function testInitialOverspeedRejected(testCase)
    config = dlab.sims.flight6dof.defaultConfig();
    config.initial.u0 = config.sim.Vmax;
    verifyError(testCase, @() dlab.sims.flight6dof.simulate6dof(config), 'flightSim:InitialOverspeed');
end

function testPresetsComplete(testCase)
    names = {'Straight flight','Glide','Phugoid mode', ...
        'Short-period mode','Dutch roll mode','Roll subsidence mode'};
    for index = 1:numel(names)
        config = dlab.sims.flight6dof.defaultConfig(names{index});
        result = dlab.sims.flight6dof.simulate6dof(config);
        verifyEqual(testCase, result.termination, 'completed');
        verifyEqual(testCase, result.t(end), config.duration, 'AbsTol', 1e-10);
    end
end

function testModeExcitations(testCase)
    phugoid = dlab.sims.flight6dof.simulate6dof(dlab.sims.flight6dof.defaultConfig('Phugoid mode'));
    speed = vecnorm(phugoid.state(:,1:3), 2, 2);
    verifyGreaterThanOrEqual(testCase, turningPoints(speed), 4);

    shortPeriod = dlab.sims.flight6dof.simulate6dof(dlab.sims.flight6dof.defaultConfig('Short-period mode'));
    verifyGreaterThanOrEqual(testCase, zeroCrossings(shortPeriod.state(:,5)), 2);

    dutchRoll = dlab.sims.flight6dof.simulate6dof(dlab.sims.flight6dof.defaultConfig('Dutch roll mode'));
    verifyGreaterThanOrEqual(testCase, zeroCrossings(dutchRoll.state(:,6)), 2);

    rollMode = dlab.sims.flight6dof.simulate6dof(dlab.sims.flight6dof.defaultConfig('Roll subsidence mode'));
    verifyLessThan(testCase, abs(rollMode.state(end,4)), ...
        abs(rollMode.state(1,4)));
end

function count = zeroCrossings(values)
    count = sum(values(1:end-1) .* values(2:end) < 0);
end

function count = turningPoints(values)
    difference = diff(values);
    count = sum(difference(1:end-1) .* difference(2:end) < 0);
end

function control = zeroControl()
    control = struct('throttle',0,'elevator',0,'aileron',0,'rudder',0);
end

function testQuaternionAgreesWithEulerAngles(testCase)
    names = {'Straight flight', 'Glide', 'Phugoid mode', 'Short-period mode', ...
        'Dutch roll mode', 'Roll subsidence mode'};
    for k = 1:numel(names)
        config = dlab.sims.flight6dof.defaultConfig(names{k});
        config.duration = 20;
        config.sim.RelTol = 1e-9;
        config.sim.AbsTol = 1e-11;
        config.sim.TIMEOUT = 300;
        euler = dlab.sims.flight6dof.simulate6dof(config);
        config.sim.attitude = 'quaternion';
        quaternion = dlab.sims.flight6dof.simulate6dof(config);
        t = linspace(0, 20, 401)';
        a = interp1(euler.t, euler.state, t);
        b = interp1(quaternion.t, quaternion.state, t);
        verifyEqual(testCase, b(:, 7:9), a(:, 7:9), 'AbsTol', 1e-5, names{k});
        verifyEqual(testCase, b(:, 10:12), a(:, 10:12), 'AbsTol', 1e-3, names{k});
        verifyEqual(testCase, vecnorm(quaternion.quaternion, 2, 2), ones(numel(quaternion.t), 1), ...
            'AbsTol', 1e-9, names{k});
        verifyFalse(testCase, isfield(euler, 'quaternion'));
    end
end

function testQuaternionAttitudeCanLoop(testCase)
    % 0.06 of pitch torque for 4.5 s at 25 m/s: one loop, past ±90° pitch.
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    [config.initial.u0, config.initial.alt0, config.control.throttle, config.duration] = deal(25, 200, 0.9, 12);
    config.control.elevator = @(t) 0.06 * (t >= 1 & t < 5.5);
    config.sim.TIMEOUT = 300;
    euler = dlab.sims.flight6dof.simulate6dof(config);
    verifyEqual(testCase, euler.termination, 'attitude limit');
    config.sim.attitude = 'quaternion';
    result = dlab.sims.flight6dof.simulate6dof(config);
    verifyEqual(testCase, result.termination, 'completed');
    rotation = rad2deg(trapz(result.t, result.state(:, 5)));
    verifyGreaterThan(testCase, rotation, 330);
    verifyLessThan(testCase, rotation, 400);
    verifyGreaterThan(testCase, max(abs(rad2deg(result.state(:, 8)))), 89, 'Passes the vertical.');
    R = dlab.physics.Quaternion.toDcm(result.quaternion(end, :)');
    verifyLessThan(testCase, abs(asind(-R(3, 1))), 20, 'Ends near level.');
    verifyGreaterThan(testCase, min(-result.state(:, 12)), 150);
end

function testZeroWindChangesNothing(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Dutch roll mode');
    plain = dlab.sims.flight6dof.simulate6dof(config);
    config.wind = struct('speed', 0, 'fromDeg', 0, 'vertical', 0, 'profile', 'uniform', 'refHeight', 10);
    still = dlab.sims.flight6dof.simulate6dof(config);
    verifyEqual(testCase, still.state, plain.state);
    verifyEqual(testCase, still.airspeed, vecnorm(still.state(:, 1:3), 2, 2), 'AbsTol', 1e-12);
end

function testTrimmedAircraftDriftsWithAUniformWind(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    [config.sim.RelTol, config.sim.AbsTol] = deal(1e-9, 1e-11);
    wind = struct('speed', 5, 'fromDeg', 90, 'vertical', 0, 'profile', 'uniform', 'refHeight', 10);
    R = dlab.physics.eulerToDcm(0, deg2rad(config.initial.theta0), 0);
    windBody = R.' * dlab.sims.flight6dof.windAt(wind, 100);
    airRelative = config;
    airRelative.wind = wind;
    airRelative.initial.u0 = config.initial.u0 + windBody(1);
    airRelative.initial.w0 = config.initial.w0 + windBody(3);
    airRelative.initial.v0 = config.initial.v0 + windBody(2);
    r = dlab.sims.flight6dof.simulate6dof(airRelative);
    verifyEqual(testCase, -r.state(:, 12), 100 * ones(numel(r.t), 1), 'AbsTol', 1e-6);
    verifyEqual(testCase, r.airspeed, 20 * ones(numel(r.t), 1), 'AbsTol', 1e-6);
    verifyEqual(testCase, r.state(end, 11), -5 * r.t(end), 'AbsTol', 1e-4, 'An easterly blows it west.');
    groundRelative = config;
    groundRelative.wind = wind;
    g = dlab.sims.flight6dof.simulate6dof(groundRelative);
    verifyGreaterThan(testCase, max(abs(-g.state(:, 12) - 100)), 0.1, 'A sudden wind upsets the trim.');
end

function testWindProfileGrowsWithHeight(testCase)
    wind = struct('speed', 5, 'fromDeg', 0, 'vertical', 2, 'profile', 'powerlaw', 'refHeight', 10);
    w = dlab.sims.flight6dof.windAt(wind, 100);
    verifyEqual(testCase, w, [-5 * 10^(1/7); 0; -2], 'AbsTol', 1e-12);
    wind.profile = 'uniform';
    verifyEqual(testCase, dlab.sims.flight6dof.windAt(wind, 100), [-5; 0; -2], 'AbsTol', 1e-12);
end

function testTrimReproducesStraightFlight(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    [trim, info] = dlab.sims.flight6dof.trim6dof(config.aircraft, 20, 100, 0);
    verifyTrue(testCase, info.converged);
    verifyEqual(testCase, trim.alpha, 0.0261044803493, 'AbsTol', 1e-9);
    verifyEqual(testCase, trim.throttle, 0.6109817636934, 'AbsTol', 1e-9);
    verifyEqual(testCase, trim.elevator, 0, 'AbsTol', 1e-9);
end

function testTrimAtAnotherSpeedHoldsAltitude(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    trim = dlab.sims.flight6dof.trim6dof(config.aircraft, 24, 100, 0);
    [config.initial.u0, config.initial.w0, config.initial.theta0] = deal(trim.u0, trim.w0, trim.theta0);
    [config.control.throttle, config.control.elevator] = deal(trim.throttle, trim.elevator);
    r = dlab.sims.flight6dof.simulate6dof(config);
    verifyEqual(testCase, -r.state(:, 12), 100 * ones(numel(r.t), 1), 'AbsTol', 1e-6);
    climb = dlab.sims.flight6dof.trim6dof(config.aircraft, 20, 100, 5);
    verifyGreaterThan(testCase, climb.throttle, 0.6109817636934, 'Climbing takes more thrust.');
    verifyEqual(testCase, climb.theta0 - rad2deg(climb.alpha), 5, 'AbsTol', 1e-9);
end

function testTrimExplainsImpossibleRequests(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    verifyError(testCase, @() dlab.sims.flight6dof.trim6dof(config.aircraft, 45, 100, 0), 'flightSim:Trim');
    verifyError(testCase, @() dlab.sims.flight6dof.trim6dof(config.aircraft, 3, 100, 0), 'flightSim:Trim');
end

function testDutchRollIsIdentifiedFromADoublet(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    config.control.rudder = @(t) 0.3 * ((t >= 1 & t < 1.5) - (t >= 1.5 & t < 2));
    r = dlab.sims.flight6dof.simulate6dof(config);
    id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, 'dutchroll', 2, complex(-1.0198, 1.9366));
    verifyTrue(testCase, id.ok);
    verifyEqual(testCase, id.period, 2 * pi / 1.9366, 'RelTol', 0.03);
    verifyEqual(testCase, id.dampingRatio, 1.0198 / abs(complex(-1.0198, 1.9366)), 'AbsTol', 0.03);
end

function testRealModesAreIdentified(testCase)
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    config.duration = 8;
    config.control.aileron = @(t) 0.1 * (t >= 1 & t < 1.3);
    r = dlab.sims.flight6dof.simulate6dof(config);
    id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, 'rollsubsidence', 1.3, -1.5);
    verifyTrue(testCase, id.ok);
    verifyEqual(testCase, id.timeConstant, 1 / 1.5, 'RelTol', 0.05);
    verifyTrue(testCase, isnan(id.period));
    config.duration = 60;
    config.control.aileron = @(t) 0.01 * (t >= 1 & t < 2);
    r = dlab.sims.flight6dof.simulate6dof(config);
    id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, 'spiral', 10, -0.0712);
    verifyEqual(testCase, id.timeConstant, 1 / 0.0712, 'RelTol', 0.05);
end

function config = autopilotConfig(altitude, heading, speed)
% Straight, trimmed flight with the given holds (references: 150 m, 90°, 22 m/s).
    config = dlab.sims.flight6dof.defaultConfig('Straight flight');
    config.sim.attitude = 'quaternion';
    config.duration = 60;
    config.autopilot = struct('active', altitude || heading || speed, 'altitude', altitude, ...
        'heading', heading, 'speed', speed, 'altitudeRef', 150, 'headingRef', 90, 'speedRef', 22, ...
        'alphaTrim', config.aircraft.alpha_trim, 'Kh', 0.02, 'Khi', 0.003, 'Khd', 0.03, 'Ktheta', 1, ...
        'Kq', 0.05, 'Kpsi', 1, 'Kphi', 0.1, 'Kp', 0.02, 'Kv', 0.1, 'Kvi', 0.03, 'maxPitch', 15, ...
        'maxBank', 30, 'bandH', 5, 'bandV', 3);
end

function testAutopilotOffChangesNothing(testCase)
    config = autopilotConfig(false, false, false);
    r = dlab.sims.flight6dof.simulate6dof(config);
    r0 = dlab.sims.flight6dof.simulate6dof(rmfield(config, 'autopilot'));
    verifyEqual(testCase, r.t, r0.t);
    verifyEqual(testCase, r.state, r0.state);
    verifyEqual(testCase, r.controls(1, :), [0.6109817636934 0 0 0], 'AbsTol', 1e-12);
end

function testAutopilotHoldsItsReferences(testCase)
    % Climb 50 m, turn 90°, and speed up 2 m/s together; each settles.
    r = dlab.sims.flight6dof.simulate6dof(autopilotConfig(true, true, true));
    verifyEqual(testCase, r.termination, 'completed');
    verifyEqual(testCase, -r.state(end, 12), 150, 'AbsTol', 1);
    verifyEqual(testCase, rad2deg(r.state(end, 9)), 90, 'AbsTol', 1);
    verifyEqual(testCase, r.airspeed(end), 22, 'AbsTol', 0.2);
    verifyLessThan(testCase, max(-r.state(:, 12)), 155, 'Little overshoot: the capture band stops windup.');
    verifyLessThan(testCase, max(abs(rad2deg(r.state(:, 7)))), 36, 'The bank stays near its 30° limit.');
    verifyLessThanOrEqual(testCase, max(abs(r.controls(:, 2:4)), [], 'all'), 1, 'Within the control limits.');
    verifyEqual(testCase, size(r.state, 2), 12, 'The integral states are not in the result.');
end

function testAltitudeHoldRejectsAPitchPulse(testCase)
    % A pitch pulse excites a phugoid; with altitude and speed hold the
    % aircraft returns to 100 m instead of oscillating for minutes.
    config = autopilotConfig(true, false, true);
    [config.autopilot.altitudeRef, config.autopilot.speedRef] = deal(100, 20);
    config.control.elevator = @(t) 0.02 * (t >= 1 & t < 3);
    r = dlab.sims.flight6dof.simulate6dof(config);
    late = r.t > 40;
    verifyLessThan(testCase, max(abs(-r.state(late, 12) - 100)), 0.5);
    open = dlab.sims.flight6dof.defaultConfig('Straight flight');
    [open.duration, open.control.elevator] = deal(60, config.control.elevator);
    r0 = dlab.sims.flight6dof.simulate6dof(open);
    verifyGreaterThan(testCase, max(abs(-r0.state(r0.t > 40, 12) - 100)), 2, 'Without it the phugoid lingers.');
end

function testIdentificationNeedsAResponse(testCase)
    r = dlab.sims.flight6dof.simulate6dof(dlab.sims.flight6dof.defaultConfig('Straight flight'));
    id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, 'dutchroll', 2);
    verifyFalse(testCase, id.ok);
    verifySubstring(testCase, id.message, 'no response');
    id = dlab.sims.flight6dof.identifyMode(r.t, r.state, r.airspeed, 'dutchroll', 19.5);
    verifySubstring(testCase, id.message, 'too soon');
end
