classdef (TestTags = {'ui'}) TestRunReportUi < matlab.unittest.TestCase
    %TESTRUNREPORTUI Plots in tabs, selected or not, embedded in the run
    %   report as PNG data URIs.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function everyTabIsEmbedded(testCase)
            t = dlab.ui.Theme.dark();
            fig = uifigure(Visible="off", Position=[100 100 640 420], Color=t.Surface);
            testCase.addTeardown(@delete, fig);
            tabs = uitabgroup(uigridlayout(fig, [1 1]));
            titles = ["Trajectory" "Energy" "Phase <plane>"];
            images = struct("Title", {}, "Container", {});
            for k = 1:numel(titles)
                grid = uigridlayout(uitab(tabs, Title=titles(k)), [1 1], BackgroundColor=t.AxesBackground);
                ax = uiaxes(grid, Color=t.AxesBackground, XColor=t.Text, YColor=t.Text);
                plot(ax, 0:0.1:5, sin((0:0.1:5) * k), Color=t.series(k));
                images(k) = struct("Title", titles(k), "Container", grid);
            end
            images(end+1) = struct("Title", "Axes only", "Container", ax);
            images(end+1) = struct("Title", "Closed", "Container", gobjects(1));
            % A new figure lays out its grids only after a moment; until
            % then exportgraphics returns a thumbnail-sized image.
            drawnow
            pause(1)

            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(temp.Folder, "report.html");
            info = struct("Title", "Toy", "Subtitle", "Defaults", "Date", datetime("now"), "Images", images);
            dlab.core.RunReport.write(file, info);
            html = string(fileread(file, Encoding="UTF-8"));

            uris = regexp(html, "<img src=""data:image/png;base64,([A-Za-z0-9+/=]+)"" alt=""([^""]*)"">", "tokens");
            testCase.verifyNumElements(uris, 4, "Three tabs (two not selected) and a bare axes.");
            testCase.verifyEqual(string(cellfun(@(c) c(2), uris)), ...
                ["Trajectory" "Energy" "Phase &lt;plane&gt;" "Axes only"]);
            for k = 1:numel(uris)
                bytes = matlab.net.base64decode(uris{k}(1));
                testCase.verifyEqual(double(bytes(1:8)), [137 80 78 71 13 10 26 10], "PNG signature.");
                width = double(bytes(17:20)) * 256.^(3:-1:0)';
                testCase.verifyGreaterThan(width, 300, uris{k}(2) + " is exported at full size.");
            end
            testCase.verifySubstring(html, "Could not include &quot;Closed&quot;");
            testCase.verifyEqual(tabs.SelectedTab, tabs.Children(1), "Exporting leaves the selection alone.");
        end
    end
end
