classdef TestRelease < matlab.unittest.TestCase
    %TESTRELEASE Release hygiene: the changelog and the version agree.

    properties
        Root
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.Root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
        end
    end

    methods (Test)
        function changelogMatchesTheVersion(testCase)
            text = fileread(fullfile(testCase.Root, "CHANGELOG.md"));
            versions = regexp(text, "^## \[(\d+\.\d+\.\d+)\]", "tokens", "lineanchors");
            testCase.assertNotEmpty(versions, "CHANGELOG.md lists no versions (""## [x.y.z]"" headings).");
            testCase.verifyEqual(string(versions{1}{1}), dlab.version(), ...
                "The newest CHANGELOG.md entry must be the version in dlab.version.");
            numbers = cellfun(@(v) sum(sscanf(v{1}, "%d.%d.%d")' .* [1e6 1e3 1]), versions);
            testCase.verifyTrue(all(diff(numbers) < 0), "Versions are listed newest first.");
        end

        function versionIsSemantic(testCase)
            testCase.verifyMatches(dlab.version(), "^\d+\.\d+\.\d+$");
        end
    end
end
