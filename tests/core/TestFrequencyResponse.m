classdef TestFrequencyResponse < matlab.unittest.TestCase
    %TESTFREQUENCYRESPONSE The Bode response behind the Bode tab,
    %   against closed forms.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function massSpringMatchesTheReceptance(testCase)
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = plugin.defaultParams();
            p.mode = "single";
            lin = plugin.linearization(p);
            testCase.verifyTrue(dlab.core.FrequencyResponse.available(lin));
            S = dlab.core.FrequencyResponse.model(lin);
            testCase.verifyEqual(S.InputNames, "Force");
            testCase.verifyEqual(S.OutputNames, ["x" "v"]);
            omega = logspace(-1, 2, 50)';
            R = dlab.core.FrequencyResponse.response(S, "Force", "x", omega);
            exact = 1 ./ (p.k - p.m * omega.^2 + 1i * p.c * omega);
            testCase.verifyEqual(R.Response, exact, RelTol=1e-6);
            testCase.verifyEqual(R.DCGain, 1 / p.k, RelTol=1e-6);
            testCase.verifyEqual(R.Phase(1), rad2deg(angle(exact(1))), AbsTol=1e-6);
            testCase.verifyLessThan(R.Phase(end), -170, "Well above resonance the mass lags by 180°.");
        end

        function peakAndBandwidthOfALightlyDampedOscillator(testCase)
            % x'' + 2ζωn x' + ωn² x = u: resonance at ωn√(1 − 2ζ²).
            wn = 3;
            zeta = 0.05;
            lin = oscillator(wn, zeta);
            S = dlab.core.FrequencyResponse.model(lin);
            R = dlab.core.FrequencyResponse.response(S, 1, 1, logspace(-2, 2, 20001)');
            testCase.verifyEqual(R.PeakFrequency, wn * sqrt(1 - 2 * zeta^2), RelTol=1e-3);
            testCase.verifyEqual(R.PeakGain, 1 / (2 * zeta * sqrt(1 - zeta^2) * wn^2), RelTol=1e-3);
            gain = @(w) abs(1 ./ (wn^2 - w.^2 + 2i * zeta * wn * w));
            testCase.verifyEqual(20 * log10(gain(R.Bandwidth) * wn^2), -3, ...
                "The bandwidth is where the gain is 3 dB below its DC value.", AbsTol=0.02);
        end

        function peakIsExactOnTheDefaultGrid(testCase)
            % The default grid is about 1 % apart; the peak is refined
            % between grid points (the quarter car read 1.182 Hz for 1.1893).
            wn = 3;
            zeta = 0.2;
            S = dlab.core.FrequencyResponse.model(oscillator(wn, zeta));
            R = dlab.core.FrequencyResponse.response(S, 1, 1);
            testCase.verifyEqual(R.PeakFrequency, wn * sqrt(1 - 2 * zeta^2), RelTol=1e-6);
            testCase.verifyEqual(R.PeakGain, 1 / (2 * zeta * sqrt(1 - zeta^2) * wn^2), RelTol=1e-9);
        end

        function marginsOfAThirdOrderLoop(testCase)
            % L(s) = 2 / (s (s + 1) (s + 2)): phase −180° at ω = √2, where
            % |L| = 1/3, so the gain margin is 20 log10 3.
            G = @(x, u) [x(2); x(3); -2 * x(2) - 3 * x(3) + u];
            lin = struct("F", @(x) G(x, 0), "X0", zeros(3, 1), "StateNames", ["y" "y'" "y''"], ...
                "Reference", "rest", "G", G, "U0", 0, "InputNames", "u", ...
                "H", @(x, u) 2 * x(1), "OutputNames", "y");
            S = dlab.core.FrequencyResponse.model(lin);
            R = dlab.core.FrequencyResponse.response(S, "u", "y", logspace(-2, 2, 20001)');
            testCase.verifyEqual(R.DCGain, Inf, "A pole at zero integrates a constant input.");
            testCase.verifyEqual(R.PhaseCrossover, sqrt(2), RelTol=1e-3);
            testCase.verifyEqual(R.GainMargin, 20 * log10(3), AbsTol=1e-2);
            L = @(w) 2 ./ (1i * w .* (1i * w + 1) .* (1i * w + 2));
            wc = fzero(@(w) abs(L(w)) - 1, [0.1 1.4]);
            testCase.verifyEqual(R.GainCrossover, wc, RelTol=1e-3);
            testCase.verifyEqual(R.PhaseMargin, 180 + rad2deg(angle(L(wc))), AbsTol=0.05);
        end

        function directFeedthroughAndNamedOutputs(testCase)
            % y = x + 0.5 u through x' = −x + u: H(s) = 1/(s + 1) + 0.5.
            G = @(x, u) -x + u;
            lin = struct("F", @(x) G(x, 0), "X0", 0, "StateNames", "x", "Reference", "rest", ...
                "G", G, "U0", 0, "InputNames", "u", "H", @(x, u) x + 0.5 * u, "OutputNames", "y");
            S = dlab.core.FrequencyResponse.model(lin);
            testCase.verifyEqual(S.D, 0.5, AbsTol=1e-9);
            R = dlab.core.FrequencyResponse.response(S, "u", "y", [0.1; 1; 10]);
            testCase.verifyEqual(R.Response, 1 ./ (1i * [0.1; 1; 10] + 1) + 0.5, RelTol=1e-6);
            testCase.verifyEqual(R.DCGain, 1.5, RelTol=1e-6);
        end

        function linearizationsWithoutInputsAreRefused(testCase)
            lin = struct("F", @(x) -x, "X0", 0, "StateNames", "x", "Reference", "rest");
            testCase.verifyFalse(dlab.core.FrequencyResponse.available(lin));
            testCase.verifyFalse(dlab.core.FrequencyResponse.available([]));
            testCase.verifyError(@() dlab.core.FrequencyResponse.model(lin), "dlab:frequency:noInputs");
            lin = oscillator(1, 0.1);
            lin.InputNames = ["a" "b"];
            testCase.verifyError(@() dlab.core.FrequencyResponse.model(lin), "dlab:frequency:names");
            S = dlab.core.FrequencyResponse.model(oscillator(1, 0.1));
            testCase.verifyError(@() dlab.core.FrequencyResponse.response(S, "nope", 1), ...
                "dlab:frequency:unknown");
        end

        function gridSpansTheEigenvalues(testCase)
            omega = dlab.core.FrequencyResponse.grid(diag([-0.5 -40]));
            testCase.verifyEqual(omega([1 end]), [0.005; 4000], RelTol=1e-12);
            testCase.verifyTrue(issorted(omega));
        end

        function dcMotorLoopMatchesTheHandMargins(testCase)
            % Position P control with no inductance: L(s) = Kp G / (s (τ s + 1)),
            % G = K / (K² + b R), τ = J R / (K² + b R). The phase stays above
            % −180°, so the gain margin is unlimited.
            plugin = dlab.sims.dcmotor.DcMotorPlugin();
            p = plugin.defaultParams();
            [p.mode, p.L, p.Kd, p.Ki] = deal("position", 0, 0, 0);
            lin = plugin.linearization(p);
            testCase.assertTrue(dlab.core.FrequencyResponse.hasLoop(lin));
            R = dlab.core.FrequencyResponse.response(dlab.core.FrequencyResponse.loop(lin), 1, 1, ...
                logspace(-2, 4, 20001)');
            G = p.K / (p.K^2 + p.b * p.R);
            tau = p.J * p.R / (p.K^2 + p.b * p.R);
            wc = fzero(@(w) p.Kp * G - w * sqrt(1 + (w * tau)^2), [1e-3 1e4]);
            testCase.verifyEqual(R.GainCrossover, wc, RelTol=1e-3);
            testCase.verifyEqual(R.PhaseMargin, 90 - atand(wc * tau), AbsTol=0.05);
            testCase.verifyTrue(isnan(R.GainMargin), "Two poles never reach −180°.");

            % With inductance there is a third pole and a finite gain margin.
            p.L = 5;
            lin = plugin.linearization(p);
            R = dlab.core.FrequencyResponse.response(dlab.core.FrequencyResponse.loop(lin), 1, 1, ...
                logspace(-2, 5, 40001)');
            Lh = p.L / 1000;
            L = @(w) p.Kp * p.K ./ (1i * w .* ((p.J * 1i * w + p.b) .* (Lh * 1i * w + p.R) + p.K^2));
            wp = fzero(@(w) angle(-L(w)), [10 1e5]);           % where L reaches −180°
            testCase.verifyEqual(R.PhaseCrossover, wp, RelTol=1e-3);
            testCase.verifyEqual(R.GainMargin, -20 * log10(abs(L(wp))), AbsTol=0.02);
        end

        function loopPhaseStartsOnItsIntegratorsBranch(testCase)
            % Position PID on the default motor: two integrators, and with
            % Ki = 60 the phase starts just below −180°. It was read as
            % +180°, so the phase margin came out 360° too large (424°).
            plugin = dlab.sims.dcmotor.DcMotorPlugin();
            p = plugin.defaultParams();
            [p.Kp, p.Ki, p.Kd] = deal(10, 60, 0.6);
            R = dlab.core.FrequencyResponse.response(dlab.core.FrequencyResponse.loop( ...
                plugin.linearization(p)), 1, 1);
            testCase.verifyEqual(R.Phase(1), -180, AbsTol=1);
            Lh = p.L / 1000;
            s = @(w) 1i * w;
            L = @(w) p.K * (p.Kd * s(w).^2 + p.Kp * s(w) + p.Ki) ./ ...
                (s(w).^2 .* ((p.J * s(w) + p.b) .* (Lh * s(w) + p.R) + p.K^2));
            wc = fzero(@(w) abs(L(w)) - 1, [1 1e3]);
            testCase.verifyEqual(R.GainCrossover, wc, RelTol=1e-3);
            testCase.verifyEqual(R.PhaseMargin, 180 + rad2deg(angle(L(wc))), AbsTol=0.1);
            testCase.verifyEqual(R.PhaseMargin, 64.12, AbsTol=0.05);
            % The cart-pole's LQR loop starts near +90° (= −270°): its margin
            % was 425°, now its true 65°.
            plugin = dlab.sims.cartpole.CartPolePlugin();
            p = plugin.defaultParams();
            p.controller = "lqr";
            R = dlab.core.FrequencyResponse.response(dlab.core.FrequencyResponse.loop( ...
                plugin.linearization(p)), 1, 1);
            testCase.verifyLessThanOrEqual(R.Phase(1), 45);
            testCase.verifyGreaterThan(R.Phase(1), -315);
            testCase.verifyLessThan(R.PhaseMargin, 180);
        end

        function cartPoleLqrKeepsItsGuaranteedMargins(testCase)
            % An LQR loop broken at the plant input has |1 + L(jω)| ≥ 1 at
            % every frequency, so at least 60° of phase margin.
            plugin = dlab.sims.cartpole.CartPolePlugin();
            p = plugin.defaultParams();
            p.controller = "lqr";
            lin = plugin.linearization(p);
            testCase.assertTrue(dlab.core.FrequencyResponse.hasLoop(lin));
            omega = logspace(-3, 3, 4001)';
            R = dlab.core.FrequencyResponse.response(dlab.core.FrequencyResponse.loop(lin), 1, 1, omega);
            testCase.verifyGreaterThanOrEqual(min(abs(1 + R.Response)), 1 - 1e-4);
            testCase.verifyGreaterThanOrEqual(R.PhaseMargin, 60 - 0.1);
            testCase.verifyLessThan(R.PhaseMargin, 180, "Not 360° off (the phase starts near −270°).");
            % Hand values (L = K (jωI − A)⁻¹ B with my own K): PM 65.196° at
            % 15.117 rad/s; the phase rises through −180° at 3.294 rad/s with
            % |L| = 3.427, so the gain may fall to 0.29 (−10.70 dB), and
            % LQR's guarantee says at least to 1/2 (|L| ≥ 2 there).
            testCase.verifyEqual(R.PhaseMargin, 65.196, "AbsTol", 0.01);
            testCase.verifyEqual(R.GainCrossover, 15.117, "RelTol", 1e-3);
            testCase.verifyEqual(R.PhaseCrossover, 3.2944, "RelTol", 1e-3, ...
                "The rising crossing of −180° was missed (gain margin 'unlimited').");
            testCase.verifyEqual(R.GainMargin, -10.699, "AbsTol", 0.01);
            testCase.verifyLessThanOrEqual(R.GainMargin, -20 * log10(2));
            p.controller = "none";
            testCase.verifyFalse(dlab.core.FrequencyResponse.hasLoop(plugin.linearization(p)), ...
                "No controller, no loop.");
        end

        function quarterCarTransmissibilityIncludesTireDamping(testCase)
            % Road height to body height, against (−ω² M + iω C + K) X = [0; k_t + iω c_t] z_r,
            % with the tire damper on (the input enters through its rate).
            plugin = dlab.sims.quartercar.QuarterCarPlugin();
            p = plugin.defaultParams();
            p.ct = 800;
            lin = plugin.linearization(p);
            S = dlab.core.FrequencyResponse.model(lin);
            M = diag([p.ms p.mu]);
            K = [p.ks -p.ks; -p.ks p.ks + p.kt];
            C = [p.cs -p.cs; -p.cs p.cs + p.ct];
            omega = 2 * pi * logspace(-1, log10(30), 40)';
            body = zeros(size(omega));
            travel = zeros(size(omega));
            for k = 1:numel(omega)
                w = omega(k);
                X = (-w^2 * M + 1i * w * C + K) \ [0; p.kt + 1i * w * p.ct];
                body(k) = X(1);
                travel(k) = X(1) - X(2);
            end
            R = dlab.core.FrequencyResponse.response(S, "Road height", "Body height", omega);
            testCase.verifyEqual(R.Response, body, RelTol=1e-5);
            R = dlab.core.FrequencyResponse.response(S, "Road height", "Suspension travel", omega);
            testCase.verifyEqual(R.Response, travel, RelTol=1e-5);
            R = dlab.core.FrequencyResponse.response(S, "Road height", "Body acceleration", omega);
            testCase.verifyEqual(R.Response, -omega.^2 .* body, RelTol=1e-5);
            % The modes are those of the usual model.
            A = [zeros(2) eye(2); -M \ K, -M \ C];
            A = A([1 3 2 4], [1 3 2 4]);
            testCase.verifyEqual(sort(eig(S.A)), sort(eig(A)), RelTol=1e-6);
            names = string({lin.Markers.Label});
            testCase.verifyEqual(names, ["Body bounce" "Wheel hop"]);
            testCase.verifyEqual(lin.FrequencyUnits, "Hz");
        end

        function everyLinearizationWithInputsIsConsistent(testCase)
            % F(x) must equal G(x, U0), and the names must fit the model.
            factories = dlab.sims.registry();
            for k = 1:numel(factories)
                plugin = factories{k}();
                id = plugin.Id;
                if ~plugin.implements("linearization")
                    continue
                end
                lin = plugin.linearization(plugin.defaultParams());
                if ~dlab.core.FrequencyResponse.available(lin)
                    continue
                end
                for x = [lin.X0(:), lin.X0(:) + 0.01 * (1:numel(lin.X0))']
                    testCase.verifyEqual(lin.G(x, lin.U0), lin.F(x), id, AbsTol=1e-9);
                end
                S = dlab.core.FrequencyResponse.model(lin);
                testCase.verifyEqual(size(S.B, 2), numel(lin.U0), id);
            end
        end
    end
end

function lin = oscillator(wn, zeta)
G = @(x, u) [x(2); u - 2 * zeta * wn * x(2) - wn^2 * x(1)];
lin = struct("F", @(x) G(x, 0), "X0", [0; 0], "StateNames", ["x" "v"], "Reference", "rest", ...
    "G", G, "U0", 0, "InputNames", "u");
end
