classdef TestHistory < matlab.unittest.TestCase
    %TESTHISTORY Undo / redo stack semantics.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function undoAndRedoWalkTheEdits(testCase)
            h = dlab.core.History();
            testCase.verifyFalse(h.canUndo());
            h.record(1);           % edit 1 → 2
            h.record(2);           % edit 2 → 3
            testCase.verifyEqual(h.undo(3), 2);
            testCase.verifyEqual(h.undo(2), 1);
            testCase.verifyEmpty(h.undo(1));
            testCase.verifyEqual(h.redo(1), 2);
            testCase.verifyEqual(h.redo(2), 3);
            testCase.verifyEmpty(h.redo(3));
        end

        function aNewEditClearsRedo(testCase)
            h = dlab.core.History();
            h.record("a");
            h.undo("b");
            testCase.verifyTrue(h.canRedo());
            h.record("a");
            testCase.verifyFalse(h.canRedo());
        end

        function repeatedStatesAreStoredOnce(testCase)
            h = dlab.core.History();
            h.record(struct("x", 1));
            h.record(struct("x", 1));
            testCase.verifyNumElements(h.UndoStack, 1);
        end

        function theStackIsBounded(testCase)
            h = dlab.core.History();
            for k = 1:h.Limit + 20
                h.record(k);
            end
            testCase.verifyNumElements(h.UndoStack, h.Limit);
            testCase.verifyEqual(h.UndoStack{1}, 21);
        end

        function snapshotsRestore(testCase)
            h = dlab.core.History();
            h.record(1);
            h.record(2);
            h.undo(3);
            copy = dlab.core.History(h.snapshot());
            testCase.verifyEqual(copy.undo(2), 1);
            testCase.verifyEqual(copy.redo(1), 2);
        end
    end
end
