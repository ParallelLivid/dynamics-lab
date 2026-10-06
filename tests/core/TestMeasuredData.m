classdef TestMeasuredData < matlab.unittest.TestCase
    %TESTMEASUREDDATA Reading measured CSV files and fitting inputs to them
    %   (dlab.core.MeasuredData), without a window.

    properties
        Folder string
        Fixtures string
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
            testCase.Fixtures = fullfile(root, "tests", "fixtures", "measured");
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = string(temp.Folder);
        end
    end

    methods
        function file = fixture(testCase, name)
            file = fullfile(testCase.Fixtures, name);
        end

        function file = write(testCase, name, lines)
            file = fullfile(testCase.Folder, name);
            writelines(lines, file);
        end
    end

    methods (Test)
        function unitsInColumnNames(testCase)
            D = dlab.core.MeasuredData.read(testCase.fixture("units-in-names.csv"));
            testCase.verifyEqual(D.Name, "units-in-names.csv");
            testCase.verifyEqual(D.Columns, ["x" "v"]);
            testCase.verifyEqual(D.Units, ["mm" "m/s"], "Both (unit) and [unit] are read.");
            testCase.verifyEqual(D.Time, [0; 0.1; 0.2; 0.3], "Milliseconds become seconds.", AbsTol=1e-12);
            testCase.verifyEqual(D.Values, [10 0; 8 -0.5; 4 -1.2; -1 -1.4]);
            testCase.verifyEqual(D.Dropped, 0);
            testCase.verifyFalse(D.Sorted);
        end

        function unitsInSecondHeaderRow(testCase)
            D = dlab.core.MeasuredData.read(testCase.fixture("units-row.csv"));
            testCase.verifyEqual(D.Columns, ["angle" "rate"], "Semicolons separate the fields.");
            testCase.verifyEqual(D.Units, ["deg" "deg/s"]);
            testCase.verifyEqual(D.Time, [0; 0.5; 1]);
            testCase.verifyEqual(D.Values(:, 2), [0; -4; -6]);
        end

        function incompleteRowsAreDroppedAndTimeSorted(testCase)
            D = dlab.core.MeasuredData.read(testCase.fixture("messy.csv"));
            testCase.verifyEqual(D.Columns, ["x" "y"], "The text column is left out; quotes are removed.");
            testCase.verifyEqual(D.Dropped, 3, "No time, or no value: three rows.");
            testCase.verifyTrue(D.Sorted);
            testCase.verifyEqual(D.Time, [0.1; 0.2; 0.3; 0.4]);
            testCase.verifyEqual(D.Values, [1 10; 2 20; 3 30; 4 40], "Values follow their times.");
        end

        function missingCellsStayMissing(testCase)
            file = testCase.write("gaps.csv", ["time,a,b" "0,1,5" "1,,6" "2,3,7"]);
            D = dlab.core.MeasuredData.read(file);
            testCase.verifyEqual(D.Dropped, 0, "A row with any value is kept.");
            [time, value] = dlab.core.MeasuredData.column(D, "a");
            testCase.verifyEqual([time value], [0 1; 2 3], "COLUMN gives only the samples present.");
        end

        function plainNamesAndTimeFoundByName(testCase)
            file = testCase.write("plain.csv", ["x,Time,y" "1,0,2" "3,1,4"]);
            D = dlab.core.MeasuredData.read(file);
            testCase.verifyEqual(D.Columns, ["x" "y"]);
            testCase.verifyEqual(D.Units, ["" ""]);
            testCase.verifyEqual(D.Time, [0; 1], "A column named time is time, wherever it is.");
        end

        function exportedResultsReadBack(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            T = plugin.exportTable(plugin.solve(plugin.defaultParams()));
            file = fullfile(testCase.Folder, "run.csv");
            dlab.core.Exporter.csv(file, T);
            D = dlab.core.MeasuredData.read(file);
            testCase.verifyEqual(D.Columns, ["x" "v"]);
            testCase.verifyEqual(D.Units, ["m" "m/s"]);
            testCase.verifyEqual(D.Values(:, 1), T.x, AbsTol=1e-12);
        end

        function unreadableFilesSayWhy(testCase)
            read = @(file) dlab.core.MeasuredData.read(file);
            testCase.verifyError(@() read(fullfile(testCase.Folder, "absent.csv")), "dlab:measured:read");
            testCase.verifyError(@() read(testCase.fixture("header-only.csv")), "dlab:measured:noData");
            testCase.verifyError(@() read(testCase.write("one.csv", ["time" "1" "2"])), "dlab:measured:columns");
            testCase.verifyError(@() read(testCase.write("text.csv", ["time,x" "a,b" "c,d"])), ...
                "dlab:measured:noData");
            testCase.verifyError(@() read(testCase.write("unit.csv", ["time (kg),x" "0,1" "1,2"])), ...
                "dlab:measured:timeUnit");
            testCase.verifyError(@() read(testCase.write("short.csv", ["time,x" "0,1" ",2"])), ...
                "dlab:measured:rows");
            testCase.verifyError(@() read(testCase.write("empty.csv", "")), "dlab:measured:empty");
            try
                read(testCase.write("timeonly.csv", ["time,x" "0," "1,"]));
                testCase.verifyFail("A file without values is refused.");
            catch failure
                testCase.verifyEqual(string(failure.message), "timeonly.csv has no numeric data besides time.");
            end
        end

        function timeVariableOfExportTables(testCase)
            toy = dlabtest.ToyOscillatorPlugin();
            testCase.verifyEqual(dlab.core.MeasuredData.timeVariable(toy.exportTable(toy.solve(toy.defaultParams()))), "t");
            spring = dlab.sims.massspring.MassSpringPlugin();
            p = springParams(spring);
            testCase.verifyEqual(dlab.core.MeasuredData.timeVariable(spring.exportTable(spring.solve(p))), "time");
            testCase.verifyEqual(dlab.core.MeasuredData.timeVariable(table(1, VariableNames="x")), "");
        end

        function recoversDampingAndStiffnessExactly(testCase)
            % Golden: data from c = 0.3, k = 12; the fit starts at 0.6, 9.
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = springParams(plugin);
            D = springData(plugin, p, 0);
            start = p;
            start.c = 0.6;
            start.k = 9;
            R = dlab.core.MeasuredData.fit(plugin, start, D, springMapping(), ["c" "k"], MaxEvaluations=200);
            testCase.verifyEqual(R.Best, [0.3 12], "Noise-free data gives the true inputs.", RelTol=1e-4);
            testCase.verifyEqual(R.Start, [0.6 9]);
            testCase.verifyLessThan(R.BestRMS, 1e-5);
            testCase.verifyGreaterThan(R.StartRMS, 0.1);
            testCase.verifyEqual([R.Labels; R.Units], ["Damping c" "Stiffness k"; "N·s/m" "N/m"]);
            testCase.verifyEqual(R.ValueUnits, "m");
            testCase.verifyEqual(R.Used, numel(D.Time));
            testCase.verifyEqual(R.Outside, 0);
            testCase.verifyEqual(R.Failed, 0);
            testCase.verifyFalse(R.Cancelled);
            testCase.verifyLessThanOrEqual(R.Evaluations, 200 + 5, "The search, then 2n + 1 runs for the errors.");
            testCase.verifyLessThan(R.StandardErrors, [1e-5 1e-4], "Without noise the errors are tiny.");
        end

        function recoversInputsFromNoisyData(testCase)
            % Uniform noise of standard deviation 0.01 m on a 1 m ringdown.
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = springParams(plugin);
            D = springData(plugin, p, 0.01);
            start = p;
            start.c = 0.6;
            start.k = 9;
            R = dlab.core.MeasuredData.fit(plugin, start, D, springMapping(), ["c" "k"]);
            testCase.verifyEqual(R.BestRMS, 0.01, "The misfit is the noise.", RelTol=0.15);
            testCase.verifyLessThan(abs(R.Best - [0.3 12]), 3 * R.StandardErrors, ...
                "The truth lies within three standard errors.");
            testCase.verifyLessThan(R.StandardErrors, [0.01 0.03], "The errors match the noise level.");
            testCase.verifyGreaterThan(R.StandardErrors, [1e-4 1e-3]);
            testCase.verifyEqual(R.Residuals.Time, D.Time);
            testCase.verifyEqual(sqrt(mean(R.Residuals.Value .^ 2)), R.BestRMS, RelTol=1e-12);
        end

        function startOnALimitMovesInside(testCase)
            % Damping starts at its lower limit, 0; the transform keeps it ≥ 0.
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = springParams(plugin);
            D = springData(plugin, p, 0);
            start = p;
            start.c = 0;
            R = dlab.core.MeasuredData.fit(plugin, start, D, springMapping(), "c");
            testCase.verifyGreaterThan(R.Start, 0);
            testCase.verifyEqual(R.Best, 0.3, RelTol=1e-3);
        end

        function measuredUnitsAreHonoured(testCase)
            % Millimetres against a result in metres: residuals in mm.
            plugin = dlab.sims.massspring.MassSpringPlugin();
            p = springParams(plugin);
            D = springData(plugin, p, 0);
            D.Values = 1000 * D.Values;
            D.Units = "mm";
            start = p;
            start.c = 0.5;
            R = dlab.core.MeasuredData.fit(plugin, start, D, springMapping(), "c");
            testCase.verifyEqual(R.ValueUnits, "mm");
            testCase.verifyEqual(R.Best, 0.3, RelTol=1e-3);
            testCase.verifyEqual(R.Simulated.Best(1), 1000, "The curves are in the data's unit.", RelTol=1e-9);
            D.Units = "kg";
            testCase.verifyError(@() dlab.core.MeasuredData.fit(plugin, start, D, springMapping(), "c"), ...
                "dlab:measured:units");
        end

        function onlyPointsInsideTheSimulatedSpanCount(testCase)
            % The toy run lasts 5 s; measurements run to 8 s.
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            D = toyData(p, (0:0.1:8)');
            start = p;
            start.zeta = 0.2;
            R = dlab.core.MeasuredData.fit(plugin, start, D, toyMapping(), "zeta");
            testCase.verifyEqual(R.Outside, 30, "5.1 s to 8 s are outside.");
            testCase.verifyEqual(R.Used, 51);
            testCase.verifyLessThanOrEqual(max(R.Residuals.Time), 5);
            testCase.verifyEqual(R.Best, 0.1, RelTol=1e-4);
            testCase.verifySubstring(dlab.core.MeasuredData.describe(R), "30 points outside the simulated time");
        end

        function noOverlapIsReportedNotThrown(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            D = toyData(p, (0:0.1:1)');
            D.Time = D.Time + 100;
            R = dlab.core.MeasuredData.fit(plugin, p, D, toyMapping(), "zeta", MaxEvaluations=10);
            testCase.verifyEqual(R.BestRMS, Inf);
            testCase.verifyEqual(R.Best, R.Start);
            testCase.verifyEqual(R.StandardErrors, NaN);
            testCase.verifySubstring(R.Message, "no measured time lies inside the simulated span");
        end

        function failedRunCountsAsLargeMisfit(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            D = toyData(p, (0:0.05:5)');
            start = p;
            start.zeta = 0.2;
            plugin.OnProgress = @(fraction) failSecondSolve(plugin, fraction);
            R = dlab.core.MeasuredData.fit(plugin, start, D, toyMapping(), "zeta");
            testCase.verifyEqual(R.Failed, 1);
            testCase.verifySubstring(R.Message, "1 run failed: The second run fails.");
            testCase.verifyEqual(R.Best, 0.1, "The search carries on past it.", RelTol=1e-4);
            testCase.verifySubstring(dlab.core.MeasuredData.describe(R), "1 failed");
        end

        function cancellingReturnsTheBestSoFar(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            D = toyData(p, (0:0.05:5)');
            start = p;
            start.zeta = 0.2;
            fractions = [];
            previous = @(fraction) false;
            plugin.ProgressFcn = previous;
            R = dlab.core.MeasuredData.fit(plugin, start, D, toyMapping(), "zeta", Progress=@progress);
            testCase.verifyTrue(R.Cancelled);
            testCase.verifyEqual(R.Evaluations, 6, "It stops in the sixth run.");
            testCase.verifyLessThan(R.BestRMS, R.StartRMS, "The best of five finished runs.");
            testCase.verifyTrue(R.Best ~= R.Start);
            testCase.verifyEqual(R.StandardErrors, NaN, "No error estimate after a cancel.");
            testCase.verifySubstring(R.Message, "Cancelled");
            testCase.verifyEqual(plugin.ProgressFcn, previous, "The plugin's progress function is restored.");
            testCase.verifyTrue(all(diff(fractions) >= 0) && all(fractions >= 0 & fractions <= 1));

            function stop = progress(fraction)
                fractions(end+1) = fraction;
                stop = fraction >= 5.5 / (120 + 3);
            end
        end

        function inputsAndColumnsAreChecked(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            p = plugin.defaultParams();
            D = toyData(p, (0:0.1:2)');
            fit = @(mapping, inputs) dlab.core.MeasuredData.fit(plugin, p, D, mapping, inputs);
            testCase.verifyError(@() fit(toyMapping(), "cycles"), "dlab:measured:integer");
            testCase.verifyError(@() fit(toyMapping(), "showEnvelope"), "dlab:sweep:parameter");
            testCase.verifyError(@() fit(toyMapping(), strings(1, 0)), "dlab:measured:inputs");
            testCase.verifyError(@() fit(toyMapping(), ["zeta" "omega" "x0" "F" "dt"]), "dlab:measured:inputs");
            testCase.verifyError(@() fit(struct("Measured", "y", "Simulated", "x"), "zeta"), "dlab:measured:column");
            testCase.verifyError(@() fit(struct("Measured", "x", "Simulated", "q"), "zeta"), ...
                "dlab:measured:simulated");
            testCase.verifyEqual(plugin.ProgressFcn, [], "Restored after an error too.");
        end

        function describeReadsLikeANote(testCase)
            R = struct("Inputs", "c", "Labels", "Damping c", "Units", "N·s/m", "Best", 0.21234, ...
                "StandardErrors", 0.0041, "StartRMS", 0.031, "BestRMS", 0.004, "ValueUnits", "m", ...
                "Evaluations", 61, "Outside", 0, "Failed", 0, "Cancelled", false);
            testCase.verifyEqual(dlab.core.MeasuredData.describe(R), ...
                "Fitted Damping c = 0.212 ± 0.004 N·s/m · RMS 0.031 → 0.004 m · 61 runs");
            R.StandardErrors = 0.012;
            R.Cancelled = true;
            testCase.verifyEqual(dlab.core.MeasuredData.describe(R), ...
                "Fitted Damping c = 0.212 ± 0.012 N·s/m · RMS 0.031 → 0.004 m · 61 runs · cancelled", ...
                "An error starting with 1 keeps two digits.");
            R.StandardErrors = NaN;
            testCase.verifySubstring(dlab.core.MeasuredData.describe(R), "Damping c = 0.2123 N·s/m");
        end
    end
end

function p = springParams(plugin)
% A short single-mass ringdown: c = 0.3 N·s/m, k = 12 N/m, x₀ = 1 m.
p = plugin.defaultParams();
p.t_end = 4;
p.dt = 0.02;
p.c = 0.3;
p.k = 12;
end

function D = springData(plugin, p, sigma)
% "Measured" position every 0.05 s, with uniform noise of standard
% deviation SIGMA from a fixed seed.
T = plugin.exportTable(plugin.solve(p));
time = (0:0.05:4)';
noise = sigma * sqrt(12) * (dlab.physics.uniformSequence(42, numel(time))' - 0.5);
D = measured(time, interp1(T.time, T.position, time) + noise, "m");
end

function mapping = springMapping()
mapping = struct("Measured", "x", "Simulated", "position");
end

function D = toyData(p, time)
% The toy's displacement at TIME, from its formula (so also past the end
% of a run).
wd = p.omega * sqrt(1 - p.zeta ^ 2);
x = p.x0 * exp(-p.zeta * p.omega * time) .* cos(wd * time);
D = measured(time, x, "m");
end

function mapping = toyMapping()
mapping = struct("Measured", "x", "Simulated", "x");
end

function D = measured(time, value, unit)
D = struct("File", "", "Name", "synthetic", "Time", time, "Columns", "x", "Units", unit, ...
    "Values", value, "Dropped", 0, "Sorted", false);
end

function failSecondSolve(plugin, fraction)
if plugin.SolveCount == 2 && fraction == 0.25
    error("dlabtest:fail", "The second run fails.");
end
end
