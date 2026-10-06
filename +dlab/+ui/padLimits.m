function padLimits(parent)
%PADLIMITS Leave a margin above and below the data in 2-D plots.
%   dlab.ui.padLimits(parent) sets YLimitMethod "padded" on every 2-D axes
%   under PARENT whose y limits are automatic, whose y scale is linear, and
%   which holds no image, surface, or contour (those fill their limits). A
%   steady trace then no longer lies on the frame, where it is hard to see
%   (6DOF Flight's 20 m/s airspeed on a 0–20 axis). The view calls it after
%   each showResult; axes with limits a plugin set itself are left alone.
for ax = reshape(findall(parent, Type="axes"), 1, [])
    if ~isequal(ax.View, [0 90]) || ax.YLimMode ~= "auto" || ax.YScale ~= "linear"
        continue
    end
    if any(arrayfun(@fillsItsLimits, ax.Children))
        continue
    end
    ax.YLimitMethod = "padded";
end
end

function tf = fillsItsLimits(h)
tf = isa(h, "matlab.graphics.primitive.Image") || isa(h, "matlab.graphics.chart.primitive.Surface") || ...
    isa(h, "matlab.graphics.primitive.Surface") || isa(h, "matlab.graphics.chart.primitive.Contour");
end
