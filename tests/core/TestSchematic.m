classdef TestSchematic < matlab.unittest.TestCase
    %TESTSCHEMATIC Geometry of the shared drawing symbols (dlab.ui.Schematic).

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function springsAndDampersJoinTheirEnds(testCase)
            for ends = {[0 0; 0 2], [1 1; 4 -3]}
                p = ends{1};
                [x, y] = dlab.ui.Schematic.spring(p(1, :), p(2, :), 6, 0.3);
                testCase.verifyEqual([x(1) y(1); x(end) y(end)], p, AbsTol=1e-12);
                [x, y] = dlab.ui.Schematic.damper(p(1, :), p(2, :), 0.2);
                testCase.verifyEqual([x(1) y(1); x(end) y(end)], p, AbsTol=1e-12);
            end
            % A vertical spring stays within half its width of the axis.
            [x, ~] = dlab.ui.Schematic.spring([0 0], [0 2], 6, 0.3);
            testCase.verifyEqual(max(abs(x)), 0.15, AbsTol=1e-12);
        end

        function arrowsEndAtTheTip(testCase)
            [lx, ly, hx, hy] = dlab.ui.Schematic.arrow([0 0], [2 0], 0.3);
            testCase.verifyEqual([lx; ly], [0 1.7; 0 0], AbsTol=1e-12);
            testCase.verifyEqual(hx(1), 2);
            testCase.verifyEqual(hy(2:3), [0.15 -0.15], AbsTol=1e-12);
            [lx, ~, ~, ~] = dlab.ui.Schematic.arrow([0 0], [0 0], 0.3);
            testCase.verifyTrue(isnan(lx), "A zero arrow draws nothing.");
        end

        function discsFormOnePatch(testCase)
            [faces, vertices] = dlab.ui.Schematic.discs([0 0; 2 2; 4 0], 0.5, 12);
            testCase.verifySize(faces, [3 12]);
            testCase.verifySize(vertices, [36 2]);
            testCase.verifyEqual(vertices(13, :), [2.5 2], AbsTol=1e-12);
            centroid = mean(vertices(faces(2, :), :), 1);
            testCase.verifyEqual(centroid, [2 2], AbsTol=1e-12);
        end

        function solidsAreClosed(testCase)
            [faces, vertices] = dlab.ui.Schematic.box3([1 2 3]);
            testCase.verifyEqual(max(vertices), [0.5 1 1.5]);
            testCase.verifySize(faces, [6 4]);
            [faces, vertices] = dlab.ui.Schematic.cone3(1, 2, 8);
            testCase.verifySize(faces, [16 3]);
            testCase.verifyEqual(max(faces(:)), size(vertices, 1));
            testCase.verifyEqual(vertices(1, :), [0 0 0], "The apex is the pivot.");
            % Every edge is shared by exactly two triangles (a closed surface).
            edges = sort([faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])], 2);
            [~, ~, id] = unique(edges, "rows");
            testCase.verifyTrue(all(accumarray(id, 1) == 2));
        end

        function wheelsAndHatchesHaveTheirStrokes(testCase)
            [x, ~] = dlab.ui.Schematic.wheel([0 0], 1, 4, 0);
            testCase.verifyEqual(nnz(isnan(x)), 4, "Rim plus four spokes.");
            [x, y] = dlab.ui.Schematic.hatch([0 0], [4 0], 5, 0.2);
            testCase.verifyEqual(nnz(isnan(x)), 5);
            testCase.verifyLessThanOrEqual(max(y), 0, "Ticks hang below a left-to-right line.");
        end
    end
end
