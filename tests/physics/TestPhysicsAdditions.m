classdef TestPhysicsAdditions < matlab.unittest.TestCase
    %TESTPHYSICSADDITIONS Riccati/LQR, body constants, the extended
    %   atmosphere, response fitting, and modal responses (dlab.physics).

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function atmosphereKeepsTheInputShape(testCase)
            % A column of altitudes gives columns (not a broadcast matrix).
            h = [0; 5000; 30000; 90000];
            [rho, T, p, a] = dlab.physics.atmosphere(h, Extended=true);
            for value = {rho, T, p, a}
                testCase.verifySize(value{1}, [4 1]);
            end
            testCase.verifyEqual(rho', dlab.physics.atmosphere(h', Extended=true), RelTol=1e-15);
            testCase.verifySize(dlab.physics.atmosphere(zeros(2, 3)), [2 3]);
        end

        function riccatiMatchesTheDoubleIntegrator(testCase)
            % Q = I, R = 1: X = [√3 1; 1 √3], K = [1 √3].
            [X, ok, residual] = dlab.physics.care([0 1; 0 0], [0; 1], eye(2), 1);
            testCase.verifyTrue(ok);
            testCase.verifyLessThan(residual, 1e-12);
            testCase.verifyEqual(X, [sqrt(3) 1; 1 sqrt(3)], AbsTol=1e-12);
            [K, ~, poles] = dlab.physics.lqr([0 1; 0 0], [0; 1], eye(2), 1);
            testCase.verifyEqual(K, [1 sqrt(3)], AbsTol=1e-12);
            testCase.verifyTrue(all(real(poles) < 0));
        end

        function riccatiMatchesTheScalarFormula(testCase)
            % a = b = q = r = 1: X = 1 + √2.
            testCase.verifyEqual(dlab.physics.care(1, 1, 1, 1), 1 + sqrt(2), AbsTol=1e-12);
        end

        function riccatiSolvesLargerSystems(testCase)
            rng(1);
            A = randn(6);
            B = randn(6, 2);
            [X, ok, residual] = dlab.physics.care(A, B, eye(6), eye(2));
            testCase.verifyTrue(ok);
            testCase.verifyLessThan(residual, 1e-10);
            testCase.verifyEqual(X, X', AbsTol=1e-12);
            testCase.verifyTrue(all(eig(X) > 0));
        end

        function riccatiRejectsUnstabilizablePairs(testCase)
            % The first state is unstable and the input cannot reach it.
            testCase.verifyError(@() dlab.physics.care([1 0; 0 -1], [0; 1], eye(2), 1), ...
                "dlab:physics:care");
        end

        function bodyConstantsMatchTheOrbitCatalog(testCase)
            earth = dlab.physics.bodyConstants("Earth");
            testCase.verifyEqual(earth.mu, 398600.4418);
            testCase.verifyEqual(earth.radius, 6371);
            testCase.verifyEqual(earth.g0, 9.8203, AbsTol=1e-4);
            testCase.verifyEqual(earth.J2, 1.08263e-3);
            names = dlab.physics.bodyConstants("names");
            testCase.verifyEqual(numel(names), 10);
            for name = names
                c = dlab.physics.bodyConstants(name);
                testCase.verifyEqual(c.g0, 1000 * c.mu / c.radius^2, "RelTol", 1e-12, name);
            end
            testCase.verifyError(@() dlab.physics.bodyConstants("Pluto"), "dlab:physics:body");
        end

        function extendedAtmosphereKeepsTheStandardBelow86km(testCase)
            h = [0 5000 11000 20000 50000 86000];
            testCase.verifyEqual(dlab.physics.atmosphere(h, Extended=true), dlab.physics.atmosphere(h));
            near = dlab.physics.atmosphere(86000 + [-1e-6 1e-6], Extended=true);
            testCase.verifyEqual(near(2), near(1), RelTol=1e-8);
            rho = dlab.physics.atmosphere(86000:1000:1e6, Extended=true);
            testCase.verifyTrue(all(diff(rho) < 0), "Density falls with altitude.");
            testCase.verifyLessThan(rho(end), 1e-20);
        end

        function dampedOscillationIsRecovered(testCase)
            rng(2);
            t = (0:0.01:10)';
            [wn, zeta] = deal(2, 0.1);
            y = exp(-zeta * wn * t) .* sin(wn * sqrt(1 - zeta^2) * t) + 0.01 * randn(size(t));
            [poles, ~, ~, r2] = dlab.physics.fitDampedResponse(t, y, 2);
            testCase.verifyEqual(abs(poles(1)), wn, RelTol=0.01);
            testCase.verifyEqual(-real(poles(1)) / abs(poles(1)), zeta, AbsTol=0.005);
            testCase.verifyGreaterThan(r2, 0.99);
        end

        function decayAndTwoModesAreRecovered(testCase)
            t = (0:0.01:10)';
            pole = dlab.physics.fitDampedResponse(t, 3 * exp(-t / 2.5), 1);
            testCase.verifyEqual(-1 / pole, 2.5, RelTol=1e-6);
            y = exp(-0.1 * t) .* cos(2 * t) + 0.5 * exp(-0.3 * t) .* cos(5 * t);
            poles = dlab.physics.fitDampedResponse(t, y, 4);
            testCase.verifyEqual(sort(abs(imag(poles))), [2; 2; 5; 5], AbsTol=1e-6);
            testCase.verifyEqual(sort(-real(poles)), [0.1; 0.1; 0.3; 0.3], AbsTol=1e-6);
        end

        function modalResponseMatchesIntegration(testCase)
            A = [0 1 0 0; -20 -0.5 10 0.2; 0 0 0 1; 10 0.2 -10 -0.3];
            x0 = [0.1; 0; -0.05; 0];
            t = (0:0.01:10)';
            [~, expected] = ode45(@(~, x) A * x, t, x0, odeset(RelTol=1e-11, AbsTol=1e-13));
            testCase.verifyEqual(dlab.physics.modalResponse(A, x0, t), expected, AbsTol=1e-9);
            % Critically damped: repeated eigenvalue, uses the expm fallback.
            A = [0 1; -1 -2];
            [~, expected] = ode45(@(~, x) A * x, t, [1; 0], odeset(RelTol=1e-11, AbsTol=1e-13));
            testCase.verifyEqual(dlab.physics.modalResponse(A, [1; 0], t), expected, AbsTol=1e-9);
        end
    end
end
