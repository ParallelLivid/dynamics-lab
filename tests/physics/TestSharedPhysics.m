classdef TestSharedPhysics < matlab.unittest.TestCase
    %TESTSHAREDPHYSICS Physics shared between simulators: the section
    %   library, the amplitude spectrum, quaternion helpers, planetary
    %   orbits, and the atmosphere above 86 km (dlab.physics).

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function sectionsMatchHandFormulas(testCase)
            lib = dlab.physics.sectionLibrary();
            % D = 100 mm, t = 10 mm: tube π/4(10² − 8²), π/64(10⁴ − 8⁴);
            % box 10² − 8², (10⁴ − 8⁴)/12; rod and bar from D alone.
            expected = [pi / 4 * 36, pi / 64 * 5904
                        pi / 4 * 100, pi / 64 * 1e4
                        36, 492
                        100, 1e4 / 12];
            for shape = 1:4
                [A, I, c] = lib.properties(shape, 100, 10);
                testCase.verifyEqual([A I], expected(shape, :), lib.ShapeNames(shape), RelTol=1e-14);
                testCase.verifyEqual(c, 50, lib.ShapeNames(shape));
                [A2, I2, c2] = lib.properties(lib.ShapeNames(shape), 100, 10);
                testCase.verifyEqual([A2 I2 c2], [A I c], "By name or by index.");
            end
        end

        function sectionsRejectImpossibleShapes(testCase)
            lib = dlab.physics.sectionLibrary();
            for args = {{1, 100, 50}, {3, 100, 60}, {1, 100, 0}, {2, 0, 0}, {5, 100, 10}, {"custom", 100, 10}, {"oval", 100, 10}}
                [A, I, c] = lib.properties(args{1}{:});
                testCase.verifyTrue(all(isnan([A I c])), "Not a section: NaN.");
            end
        end

        function sectionMaterialsAndDefault(testCase)
            lib = dlab.physics.sectionLibrary();
            testCase.verifyEqual(lib.E, [200 69 11 NaN]);
            testCase.verifyEqual(lib.Yield, [250 276 21 NaN]);
            testCase.verifyEqual(numel(lib.Default), numel(lib.Columns));
            testCase.verifyEqual(lib.Default, [1 5 200 250 0 0 100 8820]);
            % The default's I is about a 273 × 12.7 mm tube's.
            [~, I] = lib.properties("tube", 273, 12.7);
            testCase.verifyEqual(I, lib.Default(8), RelTol=0.01);
        end

        function spectrumShowsASinusoidsAmplitude(testCase)
            % 5 Hz falls on a bin (df = 0.1 Hz); the offset is removed.
            t = (0:999)' * 0.01;
            [f, A, peak] = dlab.physics.amplitudeSpectrum(t, 1 + 2.5 * sin(2 * pi * 5 * t));
            testCase.verifySize(f, [500 1]);
            testCase.verifySize(A, [500 1]);
            testCase.verifyEqual(f(2), 0.1, AbsTol=1e-12);
            [top, k] = max(A);
            testCase.verifyEqual(f(k), 5, AbsTol=1e-12);
            testCase.verifyEqual(top, 2.5, RelTol=2e-3);
            testCase.verifyLessThan(A(1), 1e-3, "The mean is removed.");
            testCase.verifyEqual(peak, 5, AbsTol=1e-6);
        end

        function spectrumPeakIsRefinedBetweenBins(testCase)
            t = (0:999)' * 0.01;
            [f, ~, peak] = dlab.physics.amplitudeSpectrum(t', sin(2 * pi * 5.03 * t'));
            testCase.verifySize(f, [500 1], "Columns for row input.");
            testCase.verifyEqual(peak, 5.03, AbsTol=0.005);
        end

        function spectrumOfTooFewSamplesIsEmpty(testCase)
            [f, A, peak] = dlab.physics.amplitudeSpectrum(0:6, sin(0:6));
            testCase.verifyEmpty(f);
            testCase.verifyEmpty(A);
            testCase.verifyTrue(isnan(peak));
        end

        function quaternionErrorAndConjugate(testCase)
            multiply = @dlab.physics.Quaternion.multiply;
            toDcm = @dlab.physics.Quaternion.toDcm;
            rng(3);
            for k = 1:50
                a = randn(4, 1);
                a = a / norm(a);
                b = randn(4, 1);
                b = b / norm(b);
                testCase.verifyEqual(multiply(dlab.physics.Quaternion.conjugate(a), a), [1; 0; 0; 0], AbsTol=1e-15);
                qe = dlab.physics.Quaternion.relative(a, b);
                testCase.verifyEqual(multiply(a, qe), b, "a ⊗ (a⁻¹ ⊗ b) = b", AbsTol=1e-15);
                % The error rotates b's axes into a's: R_e = R_aᵀ R_b.
                testCase.verifyEqual(toDcm(qe), toDcm(a)' * toDcm(b), AbsTol=1e-14);
            end
            % 90° about z from the identity: [cos 45°; 0; 0; sin 45°].
            testCase.verifyEqual(dlab.physics.Quaternion.relative([1; 0; 0; 0], [1; 0; 0; 1] / sqrt(2)), ...
                [1; 0; 0; 1] / sqrt(2), AbsTol=1e-16);
        end

        function quaternionFromDcmRoundTrips(testCase)
            rng(4);
            for k = 1:200
                q = randn(4, 1);
                q = q / norm(q);
                back = dlab.physics.Quaternion.fromDcm(dlab.physics.Quaternion.toDcm(q));
                testCase.verifyEqual(back * sign(back' * q), q, "Up to sign.", AbsTol=1e-14);
            end
            % Reference values, one for each of Shepperd's four branches.
            cases = {[0 -1 0; 1 0 0; 0 0 1], [1; 0; 0; 1] / sqrt(2)
                     diag([1 -1 -1]), [0; 1; 0; 0]
                     diag([-1 1 -1]), [0; 0; 1; 0]
                     diag([-1 -1 1]), [0; 0; 0; 1]};
            for k = 1:size(cases, 1)
                testCase.verifyEqual(dlab.physics.Quaternion.fromDcm(cases{k, 1}), cases{k, 2}, AbsTol=1e-15);
            end
        end

        function planetsCarryTheirOrbits(testCase)
            earth = dlab.physics.bodyConstants("Earth");
            testCase.verifyEqual(earth.semiMajor, 149.598e6);
            testCase.verifyEqual(earth.orbitSpeed, 29.78);
            testCase.verifyEqual(dlab.physics.bodyConstants("Moon").semiMajor, 384400);
            testCase.verifyTrue(isnan(dlab.physics.bodyConstants("Sun").semiMajor));
            muSun = dlab.physics.bodyConstants("Sun").mu;
            for name = ["Mercury" "Venus" "Earth" "Mars" "Jupiter" "Saturn" "Uranus" "Neptune"]
                c = dlab.physics.bodyConstants(name);
                % A near-circular orbit: the mean speed is about √(μ_Sun/a).
                testCase.verifyEqual(sqrt(muSun / c.semiMajor), c.orbitSpeed, name, RelTol=0.011);
            end
        end

        function soundSpeedAbove86kmFollowsTheStandard(testCase)
            % U.S. Standard Atmosphere 1976 kinetic temperatures (K), less
            % the 2.2173 K by which this model's 86 km value is lower.
            shift = 186.8673 - 184.65;
            h = [86 90 100 110 120 150 200 500] * 1e3;
            table = [186.87 186.87 195.08 240.00 360.00 634.39 854.56 999.24];
            [~, T, ~, a] = dlab.physics.atmosphere(h, Extended=true);
            testCase.verifyEqual(T + shift, table, AbsTol=0.05);
            testCase.verifyEqual(a, sqrt(1.4 * 287.05287 * T), RelTol=1e-14);
            % Continuous at the joins (to the standard's rounded
            % constants), and never falling with altitude.
            for join = [86 91 110 120] * 1e3
                [~, ~, ~, an] = dlab.physics.atmosphere(join + [-1e-6 1e-6], Extended=true);
                testCase.verifyEqual(an(2), an(1), join + " m", AbsTol=1e-3);
            end
            [~, ~, ~, a] = dlab.physics.atmosphere(86000:100:1e6, Extended=true);
            testCase.verifyTrue(all(diff(a) >= 0));
            % Without Extended the speed of sound stays the 86 km one.
            [~, ~, ~, a] = dlab.physics.atmosphere([86000 1e5 1e6]);
            testCase.verifyEqual(a, a(1) * [1 1 1]);
        end
    end
end
