classdef TestWithUnits < matlab.unittest.TestCase
    %TESTWITHUNITS dlab.ui.withUnits appends units to labels that have them.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function appendsTheUnit(testCase)
            testCase.verifyEqual(dlab.ui.withUnits("Speed", "m/s"), "Speed (m/s)");
        end

        function noUnitLeavesTheLabel(testCase)
            testCase.verifyEqual(dlab.ui.withUnits("Count", ""), "Count");
        end

        function worksElementwise(testCase)
            text = dlab.ui.withUnits(["Mass" "Ratio" "Time"], ["kg" "" "s"]);
            testCase.verifyEqual(text, ["Mass (kg)" "Ratio" "Time (s)"]);
        end

        function acceptsCharacters(testCase)
            testCase.verifyEqual(dlab.ui.withUnits('Angle', 'deg'), "Angle (deg)");
            testCase.verifyEqual(dlab.ui.withUnits('Angle', ''), "Angle");
        end

        function emptyGivesEmpty(testCase)
            testCase.verifyEqual(dlab.ui.withUnits(strings(1, 0), strings(1, 0)), strings(1, 0));
        end
    end
end
