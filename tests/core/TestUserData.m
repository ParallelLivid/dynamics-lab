classdef TestUserData < matlab.unittest.TestCase
    %TESTUSERDATA Paths, Settings, Session, and ErrorLog.

    properties
        Folder
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function isolateUserData(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fullfile(string(temp.Folder), "userdata");
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, testCase.Folder));
        end
    end

    methods (Test)
        function foldersAreCreatedUnderUserData(testCase)
            testCase.verifyEqual(dlab.core.Paths.userData(), testCase.Folder);
            testCase.verifyTrue(isfolder(testCase.Folder));
            testCase.verifyEqual(dlab.core.Paths.scenarios("toy"), fullfile(testCase.Folder, "scenarios", "toy"));
            testCase.verifyTrue(isfolder(dlab.core.Paths.exports()));
            testCase.verifyTrue(isfolder(dlab.core.Paths.logs()));
            testCase.verifyEqual(dlab.core.Paths.thumbnail("no-such-simulator"), "");
        end

        function settingsPersist(testCase)
            testCase.verifyEqual(dlab.core.Settings.get("theme", "dark"), "dark");
            dlab.core.Settings.set("theme", "light");
            dlab.core.Settings.set("count", 3);
            testCase.verifyEqual(string(dlab.core.Settings.get("theme")), "light");
            testCase.verifyEqual(dlab.core.Settings.get("count"), 3);
        end

        function corruptSettingsFallBackToDefaults(testCase)
            writelines("{ broken", dlab.core.Paths.settingsFile());
            testCase.verifyEqual(dlab.core.Settings.get("theme", "dark"), "dark");
            dlab.core.Settings.set("theme", "light");   % and it recovers
            testCase.verifyEqual(string(dlab.core.Settings.get("theme")), "light");
        end

        function sessionStoresStatePerSimulator(testCase)
            session = dlab.core.Session();
            testCase.verifyFalse(session.has("toy"));
            testCase.verifyEmpty(session.get("toy"));
            state = dlab.core.Session.newState(Params=struct("a", 1), Preset="Custom", ...
                Result=struct("t", 1:3), PlaybackTime=0.5);
            session.put("toy", state);
            testCase.verifyTrue(session.has("toy"));
            testCase.verifyEqual(session.get("toy"), state);
            session.remove("toy");
            testCase.verifyFalse(session.has("toy"));
        end

        function errorsBecomeMessagesAndLogEntries(testCase)
            expected = MException("dlab:invalidParameter", "Length must be positive.");
            unexpected = MException("MATLAB:badsubscript", "Index exceeds array bounds.");
            testCase.verifyTrue(dlab.core.ErrorLog.isExpected(expected));
            testCase.verifyEqual(dlab.core.ErrorLog.userMessage(expected), "Length must be positive.");
            testCase.verifyEqual(dlab.core.ErrorLog.userMessage(unexpected), ...
                "Unexpected error: Index exceeds array bounds.");

            file = dlab.core.ErrorLog.write(unexpected, "Run pressed");
            text = fileread(file);
            testCase.verifySubstring(text, "Run pressed");
            testCase.verifySubstring(text, "Index exceeds array bounds.");
            testCase.verifySubstring(text, "Dynamics Lab " + dlab.version());
        end
    end
end
