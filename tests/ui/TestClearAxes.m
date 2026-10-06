classdef (TestTags = {'ui'}) TestClearAxes < matlab.unittest.TestCase
    %TESTCLEARAXES dlab.ui.clearAxes empties an axes but keeps its styling.

    properties
        Axes
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function drawSomething(testCase)
            fig = figure(Visible="off");
            testCase.addTeardown(@delete, fig);
            ax = axes(fig);
            dlab.ui.styleAxes(ax, dlab.ui.Theme.dark());
            hold(ax, "on");   % plot with hold off would reset the styling
            plot(ax, 1:3, 1:3, DisplayName="Shown");
            line(ax, 1:3, 3:-1:1, HandleVisibility="off");
            legend(ax);
            hold(ax, "off");
            testCase.Axes = ax;
        end
    end

    methods (Test)
        function removesHiddenChildrenAndTheLegend(testCase)
            ax = testCase.Axes;
            dlab.ui.clearAxes(ax);
            testCase.verifyEmpty(allchild(ax), "Hidden children go too (cla keeps them).");
            testCase.verifyEmpty(ax.Legend);
            testCase.verifyEqual(string(ax.NextPlot), "add", "Hold is on for the next draw.");
        end

        function keepsTheStyling(testCase)
            ax = testCase.Axes;
            before = ax.Color;
            dlab.ui.clearAxes(ax);
            testCase.verifyEqual(ax.Color, before);
            testCase.verifyEqual(string(ax.XGrid), "on");
        end

        function canKeepTheLegend(testCase)
            ax = testCase.Axes;
            legendBefore = ax.Legend;
            dlab.ui.clearAxes(ax, KeepLegend=true);
            testCase.verifyEmpty(allchild(ax));
            testCase.verifyTrue(isgraphics(legendBefore));
            testCase.verifySameHandle(ax.Legend, legendBefore);
            testCase.verifyEqual(string(ax.NextPlot), "add");
        end
    end
end
