classdef TestScenarioIO < matlab.unittest.TestCase
    %TESTSCENARIOIO Scenario files: round trip, tolerance, rejection.

    properties
        Plugin
        Folder
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function setUp(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = string(temp.Folder);
            testCase.Plugin = dlabtest.ToyOscillatorPlugin();
        end
    end

    methods
        function file = writeJson(testCase, s)
            file = fullfile(testCase.Folder, "case.json");
            fid = fopen(file, "w");
            fwrite(fid, jsonencode(s));
            fclose(fid);
        end
    end

    methods (Test)
        function roundTripIsLossless(testCase)
            params = testCase.Plugin.defaultParams();
            params.zeta = 0.3;
            params.drive = "forced";
            params.cycles = 7;
            params.showEnvelope = false;
            file = fullfile(testCase.Folder, "s.json");
            dlab.core.ScenarioIO.save(file, testCase.Plugin, params, "My run");
            [loaded, preset, warnings] = dlab.core.ScenarioIO.load(file, testCase.Plugin);
            testCase.verifyEqual(loaded, params);
            testCase.verifyEqual(preset, "My run");
            testCase.verifyEmpty(warnings);
            raw = jsondecode(fileread(file));
            testCase.verifyEqual(string(raw.simulator), "toy");
            testCase.verifyEqual(string(raw.savedWith), "Dynamics Lab " + dlab.version());
        end

        function missingUnknownAndInvalidFieldsWarn(testCase)
            s = dlab.core.ScenarioIO.toStruct(testCase.Plugin, testCase.Plugin.defaultParams());
            s.params = rmfield(s.params, "x0");
            s.params.zeta = 5;               % out of range
            s.params.colour = "red";         % unknown
            [params, ~, warnings] = dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin);
            defaults = testCase.Plugin.defaultParams();
            testCase.verifyEqual(params.x0, defaults.x0);
            testCase.verifyEqual(params.zeta, defaults.zeta);
            testCase.verifyNumElements(warnings, 3);
            testCase.verifySubstring(strjoin(warnings), "Initial displacement was missing");
            testCase.verifySubstring(strjoin(warnings), "Damping ratio must be in");
            testCase.verifySubstring(strjoin(warnings), """colour""");
        end

        function olderSchemaIsMigrated(testCase)
            s = dlab.core.ScenarioIO.toStruct(testCase.Plugin, testCase.Plugin.defaultParams());
            s.schemaVersion = 1;
            s.params = rmfield(s.params, "zeta");
            s.params.damping = 0.4;
            [params, ~, warnings] = dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin);
            testCase.verifyEqual(params.zeta, 0.4);
            testCase.verifyEmpty(warnings);
        end

        function incompatibleFilesAreRejected(testCase)
            base = dlab.core.ScenarioIO.toStruct(testCase.Plugin, testCase.Plugin.defaultParams());

            s = base; s.simulator = "orbit";
            testCase.verifyError(@() dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin), ...
                "dlab:scenario:wrongSimulator");
            s = base; s.schemaVersion = 99;
            testCase.verifyError(@() dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin), ...
                "dlab:scenario:newerSchema");
            s = base; s.formatVersion = 99;
            testCase.verifyError(@() dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin), ...
                "dlab:scenario:newerFormat");
            s = base; s.format = "something-else";
            testCase.verifyError(@() dlab.core.ScenarioIO.load(testCase.writeJson(s), testCase.Plugin), ...
                "dlab:scenario:format");

            notJson = fullfile(testCase.Folder, "bad.json");
            writelines("{ not json", notJson);
            testCase.verifyError(@() dlab.core.ScenarioIO.load(notJson, testCase.Plugin), "dlab:scenario:notJson");
            testCase.verifyError(@() dlab.core.ScenarioIO.load(fullfile(testCase.Folder, "none.json"), ...
                testCase.Plugin), "dlab:scenario:missing");
        end

        function readReportsSimulatorWithoutAPlugin(testCase)
            s = dlab.core.ScenarioIO.toStruct(testCase.Plugin, testCase.Plugin.defaultParams(), "Light damping");
            raw = dlab.core.ScenarioIO.read(testCase.writeJson(s));
            testCase.verifyEqual(raw.simulator, "toy");
            testCase.verifyEqual(raw.preset, "Light damping");
        end
    end
end
