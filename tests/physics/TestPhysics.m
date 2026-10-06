classdef TestPhysics < matlab.unittest.TestCase
    %TESTPHYSICS The shared dlab.physics library against reference values.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function atmosphereMatchesIsaTables(testCase)
            % ISA 1976 values (U.S. Standard Atmosphere tables).
            [rho, T, p, a] = dlab.physics.atmosphere([0 11000 20000 32000]);
            testCase.verifyEqual(T, [288.15 216.65 216.65 228.65], AbsTol=1e-9);
            testCase.verifyEqual(p, [101325 22632.06 5474.89 868.02], RelTol=2e-4);
            testCase.verifyEqual(rho, [1.225 0.36392 0.088035 0.013225], RelTol=2e-4);
            testCase.verifyEqual(a(1), 340.294, AbsTol=1e-3);
        end

        function atmosphereIsContinuousAndClamped(testCase)
            boundaries = [11000 20000 32000 47000 51000 71000];
            below = dlab.physics.atmosphere(boundaries - 1e-6);
            above = dlab.physics.atmosphere(boundaries + 1e-6);
            testCase.verifyEqual(above, below, RelTol=1e-8);
            testCase.verifyEqual(dlab.physics.atmosphere(1e6), dlab.physics.atmosphere(86000));
            testCase.verifySize(dlab.physics.atmosphere(zeros(2, 3)), [2 3]);
        end

        function rotationsFollowTheRightHandRule(testCase)
            testCase.verifyEqual(dlab.physics.rotx(pi/2) * [0; 1; 0], [0; 0; 1], AbsTol=1e-15);
            testCase.verifyEqual(dlab.physics.roty(pi/2) * [0; 0; 1], [1; 0; 0], AbsTol=1e-15);
            testCase.verifyEqual(dlab.physics.rotz(pi/2) * [1; 0; 0], [0; 1; 0], AbsTol=1e-15);
        end

        function eulerDcmIsTheProductOfElementaryRotations(testCase)
            [phi, theta, psi] = deal(0.3, -0.7, 2.1);
            R = dlab.physics.eulerToDcm(phi, theta, psi);
            expected = dlab.physics.rotz(psi) * dlab.physics.roty(theta) * dlab.physics.rotx(phi);
            testCase.verifyEqual(R, expected, AbsTol=1e-14);
            testCase.verifyEqual(R' * R, eye(3), AbsTol=1e-14);
        end

        function eulerRatesReduceToBodyRatesWhenLevel(testCase)
            testCase.verifyEqual(dlab.physics.eulerRates(0.1, 0.2, 0.3, 0, 0), [0.1; 0.2; 0.3], AbsTol=1e-15);
        end

        function quaternionsAgreeWithEulerAngles(testCase)
            angles = [0.3 -0.7 2.1];
            q = dlab.physics.Quaternion.fromEuler(angles(1), angles(2), angles(3));
            testCase.verifyEqual(norm(q), 1, AbsTol=1e-15);
            testCase.verifyEqual(dlab.physics.Quaternion.toDcm(q), dlab.physics.eulerToDcm(angles(1), angles(2), angles(3)), AbsTol=1e-14);
            [phi, theta, psi] = dlab.physics.Quaternion.toEuler(q);
            testCase.verifyEqual([phi theta psi], angles, AbsTol=1e-14);
            testCase.verifyEqual(dlab.physics.Quaternion.rotate(q, [1; 0; 0]), dlab.physics.Quaternion.toDcm(q) * [1; 0; 0], AbsTol=1e-15);
            identity = [1; 0; 0; 0];
            testCase.verifyEqual(dlab.physics.Quaternion.multiply(identity, q), q, AbsTol=1e-15);
        end

        function quaternionDerivativeIntegratesARotation(testCase)
            % Constant yaw rate for 1 s turns the attitude by that angle.
            omega = [0; 0; 0.5];
            [~, q] = ode45(@(~, q) dlab.physics.Quaternion.derivative(q, omega), [0 1], [1; 0; 0; 0], ...
                odeset(RelTol=1e-10, AbsTol=1e-12));
            [~, ~, psi] = dlab.physics.Quaternion.toEuler(q(end, :)');
            testCase.verifyEqual(psi, 0.5, AbsTol=1e-8);
        end

        function orbitalElementsRoundTrip(testCase)
            mu = 398600.4418;
            elements = [26600 0.74 deg2rad(63.4) deg2rad(40) deg2rad(270) deg2rad(30)];
            [r, v] = dlab.physics.kep2cart(elements(1), elements(2), elements(3), elements(4), ...
                elements(5), elements(6), mu);
            testCase.verifyEqual(dlab.physics.cart2kep(r, v, mu), elements, RelTol=1e-10);
            energy = 0.5 * norm(v)^2 - mu / norm(r);
            testCase.verifyEqual(energy, -mu / (2 * elements(1)), RelTol=1e-12);
        end

        function gravityIncludesJ2Oblateness(testCase)
            [mu, R, J2] = deal(398600.4418, 6378.137, 1.08263e-3);
            g = @(r) dlab.physics.gravity(r, mu, J2=J2, Radius=R);
            testCase.verifyEqual(dlab.physics.gravity([7000; 0; 0], mu), [-mu / 7000^2; 0; 0], RelTol=1e-15);
            testCase.verifyEqual(g([R; 0; 0]), [-mu / R^2 * (1 + 1.5 * J2); 0; 0], RelTol=1e-12);
            testCase.verifyEqual(g([0; 0; R]), [0; 0; -mu / R^2 * (1 - 3 * J2)], RelTol=1e-12);
        end

        function unitsConvert(testCase)
            c = @dlab.physics.convertUnits;
            testCase.verifyEqual(c(1, "mi", "km"), 1.609344, AbsTol=1e-12);
            testCase.verifyEqual(c(100, "degC", "degF"), 212, AbsTol=1e-9);
            testCase.verifyEqual(c(0, "degC", "K"), 273.15, AbsTol=1e-12);
            testCase.verifyEqual(c(180, "deg", "rad"), pi, AbsTol=1e-15);
            testCase.verifyEqual(c(3.6, "km/h", "m/s"), 1, AbsTol=1e-15);
            testCase.verifyEqual(c([1 2], "kN", "N"), [1000 2000]);
            testCase.verifyError(@() c(1, "m", "s"), "dlab:physics:units");
            testCase.verifyError(@() c(1, "parsec", "m"), "dlab:physics:units");
        end

        function jacobianMatchesAnalyticDerivatives(testCase)
            f = @(x) [x(1)^2; x(1) * x(2); sin(x(2))];
            J = dlab.physics.jacobian(f, [2; 3]);
            testCase.verifyEqual(J, [4 0; 3 2; 0 cos(3)], AbsTol=1e-8);
        end
    end
end
