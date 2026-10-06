classdef (TestTags = {'ui'}) TestNewSimulator < matlab.unittest.TestCase
    %TESTNEWSIMULATOR The scaffold produces simulators that pass the build as
    %   generated: a working plugin and its tests, and the docs page, README
    %   row, lesson, and thumbnails that ArchitectureTest and TestLessons ask for.

    properties
        Scratch
    end

    properties (TestParameter)
        kind = {"time", "static"}
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, fullfile(string(temp.Folder), "userdata")));
        end
    end

    methods (TestMethodSetup)
        function makeScratchRoot(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Scratch = string(temp.Folder);
        end
    end

    methods (Test)
        function generatedPluginWorksEndToEnd(testCase, kind)
            id = "scaffold" + kind;
            files = quietly(@() dlab.dev.newSimulator(id, "Scaffold " + kind + " demo", ...
                Kind=kind, Register=false, Root=testCase.Scratch));
            testCase.verifyTrue(all(isfile(files)));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Scratch));

            className = "dlab.sims." + id + ".Scaffold" + upper(extractBefore(kind, 2)) ...
                + extractAfter(kind, 1) + "DemoPlugin";
            plugin = feval(className);
            testCase.verifyEqual(plugin.kind(), kind);
            result = plugin.solve(plugin.defaultParams());
            testCase.verifyGreaterThan(height(plugin.exportTable(result)), 0);
            S = plugin.summaryTable(result);
            testCase.verifyEqual(string(S.Properties.VariableNames), ["Quantity" "Value" "Units" "Format" "Display"]);
            testCase.verifyClass(S.Value, "double", "Typed summary rows: numbers stay numbers.");
            testCase.verifyTrue(plugin.implements("overlayRuns") && plugin.implements("showcase") ...
                && plugin.implements("about"));
            for spec = plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + ": every generated input has a tooltip.");
            end
            testCase.verifySubstring(fileread(files(4)), "% Independent reference:", ...
                "The engine test is marked as an independent reference.");

            app = DynamicsLab(id, Plugins={str2func(className)}, Visible=false);
            testCase.addTeardown(@() app.close());
            run = findall(app.Figure, Tag="dlab.run");
            run.ButtonPushedFcn(run, []);
            testCase.verifyEmpty(app.LastError);
            testCase.verifyNotEmpty(app.View.Result);

            testCase.verifySubstring(fileread(files(3)), "classdef (TestTags = {'ui'})", ...
                "The app test is tagged ui.");
            outcome = runtests(cellstr(files(3:4)));
            testCase.verifyTrue(all([outcome.Passed]) && numel(outcome) >= 2, "The generated tests pass.");
        end

        function generatedDocsLessonAndThumbnails(testCase)
            files = quietly(@() dlab.dev.newSimulator("docsdemo", "Docs Demo", Register=false, ...
                Root=testCase.Scratch));
            expected = fullfile(testCase.Scratch, ["docs/sims/docsdemo.md"
                "resources/lessons/docsdemo-intro.json"
                "resources/thumbnails/docsdemo-dark.png"
                "resources/thumbnails/docsdemo-light.png"]);
            testCase.verifyEqual(files(5:8), expected);
            testCase.verifyTrue(all(isfile(expected)));
            testCase.verifySubstring(fileread(expected(1)), "# Docs Demo");

            lesson = dlab.core.Lesson.read(expected(2));
            testCase.verifyEqual([lesson.id lesson.simulator], ["docsdemo-intro" "docsdemo"]);
            testCase.verifyNumElements(lesson.steps, 1);
            step = lesson.steps{1};
            testCase.verifyEqual(string(step.check.kind), "run");
            testCase.verifyTrue(step.solution.run, "TestLessons works the step through with its solution.");
            testCase.verifyEqual([step.claims{1}.min step.claims{1}.max], exp(-5) * [0.999 1.001], ...
                "The stub claims the exact final value.", RelTol=1e-12);

            sheet = string(fileread(files(9)));
            testCase.verifyEqual(files(9), fullfile(testCase.Scratch, "docs/verification/docsdemo.md"));
            testCase.verifySubstring(sheet, "# Docs Demo — verification");
            testCase.verifySubstring(sheet, "## Reference values");
            testCase.verifySubstring(sheet, "0.006737947 (exact)");
            testCase.verifySubstring(sheet, "## Findings");

            light = imread(expected(4));
            testCase.verifySize(light, [408 489 3]);
            testCase.verifyNotEqual(imread(expected(3)), light, "One thumbnail per theme.");
        end

        function registrationEditsTheRegistryAndReadme(testCase)
            sims = fullfile(testCase.Scratch, "+dlab", "+sims");
            mkdir(sims);
            copyfile(which("dlab.sims.registry"), fullfile(sims, "registry.m"));
            readme = fullfile(testCase.Scratch, "README.md");
            writelines(["# Lab"
                ""
                "| Simulator | What it covers |"
                "|---|---|"
                "| **Mechanics** | |"
                "| [Pendulum](docs/sims/pendulum.md) | Swings |"
                "| **Structural** | |"
                "| [Truss](docs/sims/truss.md) | Pin joints |"
                "| **Continuum** | |"
                "| [Heat](docs/sims/heat.md) | Conduction |"
                ""
                "More text."], readme);
            original = string(fileread(fullfile(sims, "registry.m")));
            quietly(@() dlab.dev.newSimulator("beam", "Beam Deflection", Kind="static", ...
                Category="Structural", Summary="Bending of beams", Root=testCase.Scratch));
            text = string(fileread(fullfile(sims, "registry.m")));
            testCase.verifySubstring(text, "    @dlab.sims.beam.BeamDeflectionPlugin" + newline + "};");
            testCase.verifyTrue(startsWith(text, extractBefore(original, newline + "};") + newline + ...
                "    @dlab.sims.beam.BeamDeflectionPlugin"), "Appended after the existing entries, which are kept.");

            row = "| [Beam Deflection](docs/sims/beam.md) | Bending of beams |";
            lines = readlines(readme);
            testCase.verifyEqual(find(lines == row), 9, "At the end of the Structural section.");

            quietly(@() dlab.dev.newSimulator("lens", "Lens", Category="Optics", Root=testCase.Scratch));
            lines = readlines(readme);
            testCase.verifyEqual(lines(12:13), ["| **Optics** | |"; "| [Lens](docs/sims/lens.md) | " + ...
                "TODO: one line on what it covers, for the Home card. |"], "A new category ends the table.");
            testCase.verifyEqual(lines(14:15), [""; "More text."], "The rest is kept.");
        end

        function refusesToOverwriteOrBadIds(testCase)
            quietly(@() dlab.dev.newSimulator("twice", "Twice", Register=false, Root=testCase.Scratch));
            testCase.verifyError(@() dlab.dev.newSimulator("twice", "Twice", Register=false, ...
                Root=testCase.Scratch), "dlab:dev:exists");
            [~, ~] = mkdir(fullfile(testCase.Scratch, "docs", "sims"));     % "twice" made it already
            writelines("Mine", fullfile(testCase.Scratch, "docs", "sims", "taken.md"));
            testCase.verifyError(@() dlab.dev.newSimulator("taken", "Taken", Register=false, ...
                Root=testCase.Scratch), "dlab:dev:exists", "An existing docs page is never overwritten.");
            testCase.verifyFalse(isfolder(fullfile(testCase.Scratch, "+dlab", "+sims", "+taken")), ...
                "Nothing is written when it refuses.");
            testCase.verifyError(@() dlab.dev.newSimulator("Bad-Id", "X", Root=testCase.Scratch), "dlab:dev:id");
            testCase.verifyError(@() dlab.dev.newSimulator("quoted", "Say ""hi""", Root=testCase.Scratch), ...
                "dlab:dev:text");
        end
    end
end

function out = quietly(fn) %#ok<INUSD> used by name inside evalc
% Run FN with its printed guidance captured (keeps the test log clean).
[~, out] = evalc("fn()");
end
