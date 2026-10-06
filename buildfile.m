function plan = buildfile
%BUILDFILE Dynamics Lab build plan.
%   buildtool            run the default tasks (check, test)
%   buildtool check      Code Analyzer over the suite
%   buildtool discover   fail if any test file cannot be loaded (otherwise it
%                        would be skipped with only a warning)
%   buildtool test       run every test under tests/ (after discover)
%   buildtool fasttest   every test except those tagged "ui" (which open the
%                        app or figures): engines, physics, and core logic
%   buildtool ptest      the whole suite as five parts in parallel MATLAB
%                        sessions (testlessons, testcore, testsimsam,
%                        testsimsnz, testconformance; each is a task too)
%   buildtool images     re-render Home thumbnails and README screenshots
%   buildtool package    standalone DynamicsLab.exe + installer in dist/
%                        (needs MATLAB Compiler; runs check and test first)
%   buildtool toolbox    installable toolbox dist/toolbox/DynamicsLab.mltbx
%                        (base MATLAB; runs check first)

import matlab.buildtool.tasks.CodeIssuesTask
import matlab.buildtool.tasks.TestTask
import matlab.unittest.selectors.HasTag

plan = buildplan(localfunctions);

plan("check") = CodeIssuesTask(["+dlab" "tests" "buildfile.m" "DynamicsLab.m"], ...
    WarningThreshold=0, ...
    Description="Fail on any Code Analyzer issue");

plan("test") = TestTask("tests", ...
    SourceFiles="+dlab", ...
    TestResults=fullfile("test-results", "results.xml"), ...
    Description="Run the Dynamics Lab test suite");
plan("test").Dependencies = "discover";

plan("fasttest") = TestTask("tests", ...
    Selector=~HasTag("ui"), ...
    TestResults=fullfile("test-results", "fast-results.xml"), ...
    Description="Run the tests that do not open windows (a few minutes)");
plan("fasttest").Dependencies = "discover";

% The suite in five parts of similar length, which ptest (and CI) run in
% parallel. Together they are exactly the tests "test" runs (discover checks).
for part = testParts()
    plan(part.Name) = TestTask(part.Tests, ...
        TestResults=fullfile("test-results", part.Name + ".xml"), ...
        Description="Run part of the test suite: " + part.Description);
    plan(part.Name).Dependencies = "discover";
end
plan("ptest").Dependencies = "discover";

plan.DefaultTasks = ["check" "test"];
plan("package").Dependencies = ["check" "test"];
plan("toolbox").Dependencies = "check";
end

function discoverTask(~)
% Fail if any test file cannot be loaded (suite discovery would otherwise skip
% it with only a warning, and its tests would silently stop running), or is
% in none of the parts that ptest and CI run.
root = fileparts(mfilename("fullpath"));
files = dir(fullfile(root, "tests", "**", "*.m"));
files(contains({files.folder}, fullfile("tests", "fixtures"))) = [];
problems = strings(0, 1);
for f = files'
    file = string(fullfile(f.folder, f.name));
    try
        if isempty(matlab.unittest.TestSuite.fromFile(file))
            problems(end+1) = file + ": defines no tests"; %#ok<AGROW>
        end
    catch failure
        problems(end+1) = file + ": " + string(failure.message); %#ok<AGROW>
    end
end
inParts = [testParts().Tests];
for f = files'
    file = string(fullfile(f.folder, f.name));
    relative = erase(file, string(root) + filesep);
    if ~any(relative == inParts | startsWith(relative, inParts + filesep))
        problems(end+1) = file + ": in none of the test parts (see testParts in buildfile.m)"; %#ok<AGROW>
    end
end
if ~isempty(problems)
    error("dlab:build:discover", "Test files that do not load:\n%s", strjoin(problems, newline));
end
fprintf("%d test files load.\n", numel(files));
end

function ptestTask(~)
% Run the five test parts at once, in separate MATLAB sessions.
dlab.dev.runTestsInParallel([testParts().Name]);
end

function parts = testParts()
% The suite split into five parts that each take a similar time.
root = fileparts(mfilename("fullpath"));
core = dir(fullfile(root, "tests", "core", "*.m"));
core = fullfile("tests", "core", string({core.name}));
core = core(~endsWith(core, "TestLessons.m"));
sims = dir(fullfile(root, "tests", "sims"));
sims = string({sims([sims.isdir] & ~startsWith({sims.name}, ".")).name});
early = sims(lower(extractBefore(sims, 2)) <= "m");
parts = struct( ...
    "Name", {"testlessons", "testcore", "testsimsam", "testsimsnz", "testconformance"}, ...
    "Tests", {fullfile("tests", "core", "TestLessons.m"), ...
        [core, fullfile("tests", "physics"), fullfile("tests", "ui"), fullfile("tests", "ArchitectureTest.m")], ...
        fullfile("tests", "sims", early), fullfile("tests", "sims", setdiff(sims, early)), ...
        fullfile("tests", "PluginConformanceTest.m")}, ...
    "Description", {"the shipped lessons", "the framework and physics", ...
        "simulators A–M", "simulators N–Z", "every plugin against the contract"});
for k = 1:numel(parts)
    parts(k).Name = string(parts(k).Name);
    parts(k).Tests = reshape(string(parts(k).Tests), 1, []);
end
end

function packageTask(~)
% Compile the standalone app and its installer into dist/.
dlab.dev.buildStandalone();
end

function toolboxTask(~)
% Package the installable toolbox into dist/toolbox/.
dlab.dev.buildToolbox();
end

function imagesTask(~)
% Re-render resources/thumbnails and docs/images from each plugin's showcase.
dlab.dev.generateImages();
end
