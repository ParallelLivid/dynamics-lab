classdef TestTimeText < matlab.unittest.TestCase
    %TESTTIMETEXT Units and rounding of dlab.ui.timeText.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function picksTheUnitAtEachThreshold(testCase)
            seconds = [0 45 119 120 750 7199 7200 3 * 86400 - 1 3 * 86400 4.1 * 86400];
            expected = ["0 s" "45 s" "119 s" "2 min" "12.5 min" "120 min" "2 h" "72 h" "3 days" "4.1 days"];
            for k = 1:numel(seconds)
                testCase.verifyEqual(dlab.ui.timeText(seconds(k)), expected(k), ...
                    sprintf("%g s", seconds(k)));
            end
        end

        function fixedStartsAtMinutesWithFixedDecimals(testCase)
            seconds = [0 30 4500 7199 7200 9000 2.1 * 86400 3 * 86400 4.5 * 86400];
            expected = ["0.0 min" "0.5 min" "75.0 min" "120.0 min" "2.00 h" "2.50 h" "50.40 h" ...
                "3.00 days" "4.50 days"];
            for k = 1:numel(seconds)
                testCase.verifyEqual(dlab.ui.timeText(seconds(k), Fixed=true), expected(k), ...
                    sprintf("%g s", seconds(k)));
            end
        end
    end
end
