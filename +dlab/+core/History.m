classdef History < handle
    %HISTORY Undo / redo stack of input states.
    %   The simulator view records the state *before* every user edit
    %   (record), so undo returns to it and redo returns to the edit.
    %   A state is any value; the view stores struct("Params", ..., "Preset", ...).
    %
    %       h = dlab.core.History();
    %       h.record(before);            % then apply the edit
    %       previous = h.undo(current);  % [] when there is nothing to undo
    %       again = h.redo(previous);

    properties (SetAccess = private)
        UndoStack cell = {}
        RedoStack cell = {}
    end

    properties (Constant)
        Limit = 100
    end

    methods
        function obj = History(saved)
            %HISTORY Optionally restore stacks saved with snapshot().
            arguments
                saved = []
            end
            if ~isempty(saved)
                obj.UndoStack = saved.Undo;
                obj.RedoStack = saved.Redo;
            end
        end

        function record(obj, state)
            %RECORD Remember STATE as the point to undo back to. A new
            %   edit invalidates anything that could be redone.
            if ~isempty(obj.UndoStack) && isequaln(obj.UndoStack{end}, state)
                return
            end
            obj.UndoStack{end+1} = state;
            if numel(obj.UndoStack) > obj.Limit
                obj.UndoStack(1) = [];
            end
            obj.RedoStack = {};
        end

        function state = undo(obj, current)
            %UNDO The previous state ([] if none); CURRENT becomes redoable.
            state = [];
            if ~obj.canUndo()
                return
            end
            state = obj.UndoStack{end};
            obj.UndoStack(end) = [];
            obj.RedoStack{end+1} = current;
        end

        function state = redo(obj, current)
            %REDO The state undone last ([] if none); CURRENT becomes undoable.
            state = [];
            if ~obj.canRedo()
                return
            end
            state = obj.RedoStack{end};
            obj.RedoStack(end) = [];
            obj.UndoStack{end+1} = current;
        end

        function tf = canUndo(obj)
            tf = ~isempty(obj.UndoStack);
        end

        function tf = canRedo(obj)
            tf = ~isempty(obj.RedoStack);
        end

        function saved = snapshot(obj)
            saved = struct("Undo", {obj.UndoStack}, "Redo", {obj.RedoStack});
        end
    end
end
