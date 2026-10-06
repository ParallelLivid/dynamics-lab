classdef ArchitectureTest < matlab.unittest.TestCase
    %ARCHITECTURETEST Structural rules that keep the suite modular.
    %   - every plugin package is registered (and vice versa)
    %   - the framework never depends on a specific simulator
    %   - simulators never depend on each other
    %   - simulators use the shared dlab.ui helpers, not local copies
    %   - the shared physics library depends on base MATLAB only
    %   - colors come from dlab.ui.Theme, never literals
    %   - every simulator is documented: a docs page, a README row, and
    %     Home thumbnails in both themes
    %   - tests that open the app or figures are tagged "ui" (left out of
    %     buildtool fasttest)

    properties
        Root
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.Root = string(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
        end
    end

    methods (Test)
        function everyPluginIsRegistered(testCase)
            files = dir(fullfile(testCase.Root, "+dlab", "+sims", "+*", "*Plugin.m"));
            onDisk = strings(1, 0);
            for f = files'
                [~, package] = fileparts(f.folder);
                onDisk(end+1) = "dlab.sims." + extractAfter(string(package), "+") + "." + erase(f.name, ".m"); %#ok<AGROW>
            end
            registered = reshape(string(cellfun(@func2str, dlab.sims.registry(), UniformOutput=false)), 1, []);
            testCase.verifyEqual(sort(registered), sort(onDisk), ...
                "registry.m and the *Plugin.m files under +dlab/+sims must match.");
        end

        function frameworkDoesNotDependOnSimulators(testCase)
            for file = testCase.files(["+dlab/+core" "+dlab/+ui"])
                code = testCase.code(file);
                uses = regexp(code, "dlab\.sims\.\w+", "match");
                uses = setdiff(uses, "dlab.sims.registry");
                testCase.verifyEmpty(uses, file + " references a simulator.");
            end
        end

        function physicsLibraryIsSelfContained(testCase)
            % Shared physics depends on base MATLAB only, so any engine
            % (and future simulator) can use it.
            for file = testCase.files("+dlab/+physics")
                uses = regexp(testCase.code(file), "dlab\.(?!physics\.)\w+", "match");
                testCase.verifyEmpty(uses, file + " depends on app code.");
            end
        end

        function simulatorsAreIndependent(testCase)
            packages = dir(fullfile(testCase.Root, "+dlab", "+sims", "+*"));
            for p = packages'
                own = extractAfter(string(p.name), "+");
                for file = testCase.files("+dlab/+sims/" + p.name)
                    used = regexp(testCase.code(file), "dlab\.sims\.(\w+)", "tokens");
                    used = unique(string(cellfun(@(c) c{1}, used, UniformOutput=false)));
                    others = setdiff(used, [own "registry"]);
                    testCase.verifyEmpty(others, file + " references another simulator.");
                end
            end
        end

        function simulatorsUseSharedUiHelpers(testCase)
            % Clearing an axes, formatting a duration, quaternion algebra,
            % and section properties live in dlab.ui and
            % dlab.physics; a local copy drifts from the shared one.
            shared = ["fresh" "dlab.ui.clearAxes"; "timeText" "dlab.ui.timeText"; ...
                "durationText" "dlab.ui.timeText"; "quatMultiply" "dlab.physics.Quaternion"; ...
                "quatConj" "dlab.physics.Quaternion"; "fromDcm" "dlab.physics.Quaternion.fromDcm"];
            testCase.verifyEmpty(dir(fullfile(testCase.Root, "+dlab", "+sims", "**", "sectionLibrary.m")), ...
                "Use dlab.physics.sectionLibrary rather than a copy in a simulator.");
            for file = testCase.files("+dlab/+sims")
                code = testCase.code(file);
                for k = 1:size(shared, 1)
                    pattern = "^\s*function\s+(?:[^=\n]*=\s*)?" + shared(k, 1) + "\s*\(";
                    testCase.verifyEmpty(regexp(code, pattern, "match", "lineanchors"), ...
                        file + ": use " + shared(k, 2) + " instead of a local " + shared(k, 1) + ".");
                end
            end
        end

        function textFollowsTheTextSize(testCase)
            % Font sizes in plugins go through the theme (t.FontSize.*, or
            % t.scaled(points)), so the Aa text-size setting reaches them.
            for file = testCase.files("+dlab/+sims")
                code = testCase.code(file);
                testCase.verifyEmpty(regexp(code, "FontSize\s*=\s*\d", "match"), ...
                    file + ": use t.scaled(points) or t.FontSize for font sizes.");
            end
        end

        function everySimulatorIsDocumented(testCase)
            readme = fileread(fullfile(testCase.Root, "README.md"));
            for factory = reshape(dlab.sims.registry(), 1, [])
                plugin = factory{1}();
                id = string(plugin.Id);
                testCase.verifyTrue(isfile(fullfile(testCase.Root, "docs", "sims", id + ".md")), ...
                    id + ": add docs/sims/" + id + ".md.");
                testCase.verifyTrue(contains(readme, "(docs/sims/" + id + ".md)"), ...
                    id + ": add a row to the simulator table in README.md.");
                for theme = ["dark" "light"]
                    testCase.verifyTrue(isfile(fullfile(testCase.Root, "resources", "thumbnails", ...
                        id + "-" + theme + ".png")), id + ": no " + theme + " thumbnail (buildtool images).");
                end
                delete(plugin);
            end
        end

        function everySimulatorIsCheckedAgainstIndependentValues(testCase)
            % A simulator's own tests confirm what its code does; only values
            % worked out apart from it (a closed form, a published result, a
            % separate integration) show that the code is right. Every
            % simulator has a verification sheet with such values, and at
            % least one test that asserts one, marked "% Independent
            % reference: <source>" (see docs/verification/README.md).
            for factory = reshape(dlab.sims.registry(), 1, [])
                plugin = factory{1}();
                id = string(plugin.Id);
                delete(plugin);
                sheet = fullfile(testCase.Root, "docs", "verification", id + ".md");
                testCase.verifyTrue(isfile(sheet), id + ": add docs/verification/" + id + ".md (the sheet template " + ...
                    "is in docs/verification/README.md).");
                if isfile(sheet)
                    text = string(fileread(sheet, Encoding="UTF-8"));
                    section = extractBetween(text, "## Reference values", "## ");
                    rows = 0;
                    if ~isempty(section)
                        rows = nnz(startsWith(strip(splitlines(section(1))), "|")) - 2;   % less the header and rule
                    end
                    testCase.verifyGreaterThan(rows, 0, id + ": the sheet's Reference values table is empty.");
                    testCase.verifySubstring(text, "## Findings", id + ": the sheet has no Findings section.");
                end
                files = dir(fullfile(testCase.Root, "tests", "sims", id, "*.m"));
                marked = arrayfun(@(f) contains(string(fileread(fullfile(f.folder, f.name), Encoding="UTF-8")), ...
                    "% Independent reference:"), files);
                testCase.verifyTrue(any(marked), id + ": mark a test that checks an independent value with " + ...
                    """% Independent reference: <source>"" (tests/sims/" + id + ").");
            end
        end

        function uiTestsAreTagged(testCase)
            % Tests that open the app or figures are slow: tag them "ui".
            found = dir(fullfile(testCase.Root, "tests", "**", "*.m"));
            found(contains({found.folder}, fullfile("tests", "fixtures"))) = [];
            for f = found'
                file = string(fullfile(f.folder, f.name));
                code = testCase.code(file);
                opensWindows = contains(code, "DynamicsLab(") || contains(code, "uifigure(");
                if opensWindows && startsWith(strtrim(code), "classdef")
                    testCase.verifyTrue(contains(code, "TestTags = {'ui'}"), ...
                        file + " opens windows: tag it (classdef (TestTags = {'ui'}) ...).");
                end
            end
        end

        function everyTestFileLoads(testCase)
            % A test file that fails to load (syntax error, sealed-method
            % clash, ...) is otherwise skipped with only a warning.
            found = dir(fullfile(testCase.Root, "tests", "**", "*.m"));
            found(contains({found.folder}, fullfile("tests", "fixtures"))) = [];
            for f = found'
                file = fullfile(f.folder, f.name);
                try
                    suite = matlab.unittest.TestSuite.fromFile(file);
                    testCase.verifyNotEmpty(suite, file + " defines no tests.");
                catch ME
                    testCase.verifyFail(file + " does not load: " + ME.message);
                end
            end
        end

        function colorsComeFromTheTheme(testCase)
            folders = ["+dlab/+core" "+dlab/+ui" "tests/fixtures"];
            candidates = [testCase.files(folders), testCase.pluginFiles()];
            candidates(endsWith(candidates, fullfile("+ui", "Theme.m"))) = [];
            rgbLiteral = "\[\s*(?:0?\.\d+|1(?:\.0+)?|0)\s*[, ]\s*(?:0?\.\d+|1(?:\.0+)?|0)\s*[, ]\s*(?:0?\.\d+|1(?:\.0+)?|0)\s*\]";
            namedColor = "(?i)(?:Color|BackgroundColor|FontColor|ForegroundColor|EdgeColor|FaceColor)\W{1,3}" ...
                + "[""'](?:[rgbcmykw]|red|green|blue|cyan|magenta|yellow|black|white)[""']";
            for file = candidates
                code = testCase.code(file);
                literals = regexp(code, rgbLiteral, "match");
                literals = literals(contains(literals, "."));   % [1 0 0] is usually geometry
                testCase.verifyEmpty(literals, file + ": use theme tokens, not RGB literals.");
                testCase.verifyEmpty(regexp(code, namedColor, "match"), ...
                    file + ": use theme tokens, not named colors.");
            end
        end
    end

    methods (Access = private)
        function list = files(testCase, folders)
            list = strings(1, 0);
            for folder = folders
                found = dir(fullfile(testCase.Root, folder, "**", "*.m"));
                list = [list, string(fullfile({found.folder}, {found.name}))]; %#ok<AGROW>
            end
        end

        function list = pluginFiles(testCase)
            found = dir(fullfile(testCase.Root, "+dlab", "+sims", "**", "*Plugin.m"));
            list = string(fullfile({found.folder}, {found.name}));
        end

        function code = code(~, file)
            %CODE File text with comments removed.
            lines = readlines(file);
            lines = regexprep(lines, "%.*$", "");
            code = strjoin(lines, newline);
        end
    end
end
