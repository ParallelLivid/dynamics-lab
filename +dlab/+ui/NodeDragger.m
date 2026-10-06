classdef NodeDragger < handle
    %NODEDRAGGER Drag points of a model on an axes with the mouse.
    %   Knows nothing about the model: it asks for the node positions,
    %   reports each move (for a light preview), and commits once when the
    %   mouse is released, so an edit is one undo step.
    %
    %       d = dlab.ui.NodeDragger(ax, Nodes=@() xy, OnMove=@(k, xy) ..., ...
    %           OnCommit=@(k, xy) ..., OnCancel=@() ..., Snap=@() 0.5);
    %       d.attach(markerLine)            % press on a marker to drag it
    %       d.dragProgrammatic(2, [3 1])    % tests: the same path as the mouse
    %
    %   While dragging it borrows the figure's WindowButtonMotionFcn and
    %   WindowButtonUpFcn and always gives them back: on release, and if
    %   the axes is deleted mid-drag. A press that moves less than a few
    %   pixels is a click and changes nothing.

    properties
        Nodes = @() zeros(0, 2)     % @() N×2 positions (data units)
        OnMove = @(k, xy) []        % preview while dragging
        OnCommit = @(k, xy) []      % called once on release, if the node moved
        OnCancel = @() []           % called on release without a real move
        Snap = @() 0                % @() grid step (0 = off)
        Enabled = @() true          % @() logical; dragging is ignored when false
        PickRadius (1,1) double = 12        % pixels
        ClickTolerance (1,1) double = 3     % pixels
    end

    properties (SetAccess = private)
        Axes
        Active (1,1) double = 0     % node being dragged (0 = none)
        Start = [NaN NaN]
        Position = [NaN NaN]
    end

    properties (Access = private)
        Figure
        SavedMotion
        SavedUp
        Borrowing (1,1) logical = false
        Listener
    end

    methods
        function obj = NodeDragger(ax, options)
            arguments
                ax
                options.Nodes = @() zeros(0, 2)
                options.OnMove = @(k, xy) []
                options.OnCommit = @(k, xy) []
                options.OnCancel = @() []
                options.Snap = @() 0
                options.Enabled = @() true
            end
            obj.Axes = ax;
            for name = string(fieldnames(options))'
                obj.(name) = options.(name);
            end
            obj.Listener = listener(ax, "ObjectBeingDestroyed", @(~, ~) obj.restore());
        end

        function attach(obj, target)
            %ATTACH Start a drag when TARGET (e.g. the node markers) is pressed.
            set(target, ButtonDownFcn=@(~, ~) obj.press(), HitTest="on", PickableParts="visible");
        end

        function press(obj)
            %PRESS Pick the node under the pointer and start dragging it.
            if ~obj.Enabled() || obj.Active > 0
                return
            end
            point = obj.Axes.CurrentPoint(1, 1:2);
            k = obj.nearest(point);
            if k == 0
                return
            end
            obj.begin(k);
            obj.Figure = ancestor(obj.Axes, "figure");
            obj.SavedMotion = obj.Figure.WindowButtonMotionFcn;
            obj.SavedUp = obj.Figure.WindowButtonUpFcn;
            obj.Borrowing = true;
            obj.Figure.WindowButtonMotionFcn = @(~, ~) obj.moveTo(obj.Axes.CurrentPoint(1, 1:2));
            obj.Figure.WindowButtonUpFcn = @(~, ~) obj.release();
        end

        function moveTo(obj, xy)
            %MOVETO Move the dragged node to XY (snapped), as a preview.
            if obj.Active == 0
                return
            end
            step = obj.Snap();
            if step > 0
                xy = round(xy / step) * step;
            end
            obj.Position = xy;
            obj.OnMove(obj.Active, xy);
        end

        function release(obj)
            %RELEASE End the drag: commit a real move, or cancel a click.
            k = obj.Active;
            obj.restore();
            if k == 0
                return
            end
            moved = obj.pixels(obj.Position - obj.Start) > obj.ClickTolerance;
            obj.Active = 0;
            if moved && all(isfinite(obj.Position))
                obj.OnCommit(k, obj.Position);
            else
                obj.OnCancel();
            end
        end

        function dragProgrammatic(obj, k, xy)
            %DRAGPROGRAMMATIC Drag node K to XY without a mouse (tests and
            %   scripts): the same preview, snap, and commit path.
            if ~obj.Enabled()
                return
            end
            obj.begin(k);
            obj.moveTo(xy);
            obj.release();
        end

        function delete(obj)
            obj.restore();
            delete(obj.Listener);
        end
    end

    methods (Access = private)
        function begin(obj, k)
            nodes = obj.Nodes();
            obj.Active = k;
            obj.Start = nodes(k, :);
            obj.Position = nodes(k, :);
        end

        function k = nearest(obj, point)
            % The node within PickRadius pixels of POINT (0 if none).
            nodes = obj.Nodes();
            k = 0;
            if isempty(nodes)
                return
            end
            distances = arrayfun(@(i) obj.pixels(nodes(i, :) - point), 1:size(nodes, 1));
            [closest, i] = min(distances);
            if closest <= obj.PickRadius
                k = i;
            end
        end

        function d = pixels(obj, delta)
            % Length of a data-space displacement on screen, in pixels.
            ax = obj.Axes;
            box = ax.InnerPosition;
            if ~strcmp(ax.Units, "pixels")
                box = getpixelposition(ax);
            end
            scale = [box(3) / diff(ax.XLim), box(4) / diff(ax.YLim)];
            d = norm(delta .* scale);
        end

        function restore(obj)
            % Give the figure its mouse callbacks back (idempotent).
            if obj.Borrowing && ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.WindowButtonMotionFcn = obj.SavedMotion;
                obj.Figure.WindowButtonUpFcn = obj.SavedUp;
            end
            obj.Borrowing = false;
        end
    end
end
