classdef TestOdeProgress < matlab.unittest.TestCase
    %TESTODEPROGRESS The shared ODE progress callback
    %   (dlab.physics.odeProgress): fractions of the span, and a cancel
    %   that stops the solver.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function reportsTheFractionOfTheSpan(testCase)
            seen = [];
            fcn = dlab.physics.odeProgress(@record, [-2 0 2]);
            testCase.verifyFalse(fcn([-2 2], [0 0], 'init'), "No report on init.");
            testCase.verifyFalse(fcn(-1, 0, ''));
            testCase.verifyFalse(fcn([0 1], [0 0], ''), "Refined steps: the last time counts.");
            testCase.verifyFalse(fcn([], [], 'done'), "No report when done.");
            testCase.verifyEqual(seen, [0.25 0.75]);

            function stop = record(fraction)
                seen(end + 1) = fraction;
                stop = false;
            end
        end

        function passesTheAnswerBack(testCase)
            fcn = dlab.physics.odeProgress(@(fraction) fraction >= 0.5, [0 10]);
            testCase.verifyFalse(fcn(4, 0, ''));
            testCase.verifyTrue(fcn(5, 0, ''), "A true from progressFcn stops the solver.");
        end

        function noProgressFcnGivesNoOutputFcn(testCase)
            testCase.verifyEmpty(dlab.physics.odeProgress([], [0 1]));
        end

        function progressRisesToOneThroughASolve(testCase)
            seen = [];
            options = odeset("OutputFcn", dlab.physics.odeProgress(@record, [0 3]));
            ode45(@(t, y) -y, [0 3], 1, options);
            testCase.verifyNotEmpty(seen);
            testCase.verifyTrue(all(diff(seen) > 0), "Fractions only grow.");
            testCase.verifyEqual(seen(end), 1, AbsTol=1e-12);

            function stop = record(fraction)
                seen(end + 1) = fraction;
                stop = false;
            end
        end

        function aCancelEndsTheSolveEarly(testCase)
            options = odeset("OutputFcn", dlab.physics.odeProgress(@(fraction) fraction >= 0.4, [0 10]), ...
                "MaxStep", 0.1);
            [t, ~] = ode45(@(t, y) -y, [0 10], 1, options);
            testCase.verifyGreaterThanOrEqual(t(end), 4);
            testCase.verifyLessThan(t(end), 4.2, "The solver stops at the step that asked.");
        end
    end
end
