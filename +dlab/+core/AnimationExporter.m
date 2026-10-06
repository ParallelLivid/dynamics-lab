classdef AnimationExporter
    %ANIMATIONEXPORTER Record a simulator's animation to MP4 or GIF.
    %   Frames are drawn by the plugin's own drawFrame and captured from
    %   the screen, so the video looks exactly like playback.
    %
    %       info = dlab.core.AnimationExporter.write(file, "gif", @(t) plugin.drawFrame(t), ...
    %           target, 0, 10, TimeScale=1, Progress=@(f) false);
    %
    %   TARGET is the animation's grid (or any container), its axes, or
    %   one axes in a grid layout, which stands for every axes in that
    %   grid. With one axes the frame is its plot box. With several (a
    %   side view, an inset) the frame is the screen area covering all of
    %   them, titles and tick labels included, so each is recorded where
    %   it sits on screen.
    %
    %   The video runs at the current playback speed (TimeScale = simulated
    %   seconds per second of video). Long runs are capped at MaxFrames, so
    %   they play faster than real time.

    properties (Constant)
        Formats = ["mp4" "gif"]
    end

    methods (Static)
        function tf = canWrite(format)
            %CANWRITE Whether this MATLAB can write FORMAT ("mp4" needs a
            %   platform MPEG-4 encoder; GIF always works).
            arguments
                format (1,1) string
            end
            if format == "gif"
                tf = true;
            else
                tf = ismember("MPEG-4", string({VideoWriter.getProfiles().Name}));
            end
        end

        function info = write(file, format, draw, target, startTime, endTime, options)
            arguments
                file (1,1) string
                format (1,1) string {mustBeMember(format, ["mp4" "gif"])}
                draw (1,1) function_handle
                target
                startTime (1,1) double
                endTime (1,1) double
                options.TimeScale (1,1) double {mustBePositive} = 1
                options.FrameRate (1,1) double = NaN         % default: 25 (MP4) or 15 (GIF)
                options.MaxFrames (1,1) double = NaN         % default: 450 (MP4) or 240 (GIF)
                options.Progress = []
            end
            fps = options.FrameRate;
            if isnan(fps)
                fps = 25 * (format == "mp4") + 15 * (format == "gif");
            end
            cap = options.MaxFrames;
            if isnan(cap)
                cap = 450 * (format == "mp4") + 240 * (format == "gif");   % about 18 s / 16 s
            end
            seconds = (endTime - startTime) / options.TimeScale;
            n = min(cap, max(2, ceil(seconds * fps) + 1));
            times = linspace(startTime, endTime, n);
            info = struct("Frames", 0, "FrameRate", fps, "Cancelled", false, "Capped", ceil(seconds * fps) + 1 > cap);
            capture = captureFcn(target);

            writer = [];
            if format == "mp4"
                writer = VideoWriter(file, "MPEG-4");
                writer.FrameRate = fps;
                writer.Quality = 95;
                open(writer);
            end
            try
                info = record(info);
            catch ME
                if ~isempty(writer)
                    close(writer);
                end
                rethrow(ME);
            end
            if ~isempty(writer)
                close(writer);
            end
            if info.Cancelled && isfile(file)
                delete(file);
            end

            function info = record(info)
                % Draw, capture, and write each frame.
                frameSize = [];
                for k = 1:n
                    if ~isempty(options.Progress) && options.Progress((k - 1) / n)
                        info.Cancelled = true;
                        break
                    end
                    draw(times(k));
                    drawnow
                    frame = capture();
                    if isempty(frameSize)
                        frameSize = size(frame, [1 2]);
                        frameSize = frameSize - mod(frameSize, 2);   % MPEG-4 wants even sizes
                    end
                    frame = fitFrame(frame, frameSize);
                    if format == "mp4"
                        writeVideo(writer, frame);
                    else
                        [indexed, map] = rgb2ind(frame, 256, "nodither");
                        if k == 1
                            imwrite(indexed, map, file, "gif", LoopCount=Inf, DelayTime=1 / fps);
                        else
                            imwrite(indexed, map, file, "gif", WriteMode="append", DelayTime=1 / fps);
                        end
                    end
                    info.Frames = k;
                end
            end
        end
    end
end

function capture = captureFcn(target)
% A function returning the current frame of TARGET's axes.
if isscalar(target) && target.Type == "axes" && isa(target.Parent, "matlab.ui.container.GridLayout")
    target = target.Parent;      % an inset or side view shares the grid
end
axes = findall(target, Type="axes");
if isempty(axes)
    error("dlab:animation:noAxes", "There are no axes to record.");
end
if isscalar(axes)
    capture = @() getframe(axes).cdata;
else
    capture = @() captureRegion(axes);
end
end

function frame = captureRegion(axes)
% The part of the figure's frame covering all of AXES (their outer boxes).
fig = ancestor(axes(1), "figure");
whole = getframe(fig).cdata;
boxes = zeros(numel(axes), 4);
for k = 1:numel(axes)
    boxes(k, :) = getpixelposition(axes(k), true);      % [left bottom width height], from 1
end
left = min(boxes(:, 1));
right = max(boxes(:, 1) + boxes(:, 3)) - 1;
bottom = min(boxes(:, 2));
top = max(boxes(:, 2) + boxes(:, 4)) - 1;
% Figure pixels to frame pixels (more than one on a high-DPI screen).
inner = getpixelposition(fig);
scale = [size(whole, 2) / inner(3), size(whole, 1) / inner(4)];
rows = size(whole, 1) - round(top * scale(2)) + 1 : size(whole, 1) - round((bottom - 1) * scale(2));
columns = round((left - 1) * scale(1)) + 1 : round(right * scale(1));
rows = rows(rows >= 1 & rows <= size(whole, 1));
columns = columns(columns >= 1 & columns <= size(whole, 2));
frame = whole(rows, columns, :);
end

function frame = fitFrame(frame, frameSize)
% Crop or pad (by repeating the edge) to exactly FRAMESIZE; captured
% frames can differ by a pixel when the layout settles.
rows = min(size(frame, 1), frameSize(1));
columns = min(size(frame, 2), frameSize(2));
frame = frame(1:rows, 1:columns, :);
if rows < frameSize(1)
    frame(end+1:frameSize(1), :, :) = repmat(frame(end, :, :), frameSize(1) - rows, 1, 1);
end
if columns < frameSize(2)
    frame(:, end+1:frameSize(2), :) = repmat(frame(:, end, :), 1, frameSize(2) - columns, 1);
end
end
