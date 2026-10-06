function h = overlayLine(ax, x, y, run, z)
%OVERLAYLINE A kept run drawn faintly behind the current result.
%   h = dlab.ui.overlayLine(ax, x, y, run)        2-D
%   h = dlab.ui.overlayLine(ax, x, y, run, z)     3-D
%
%   RUN is one element of the struct array a plugin's overlayRuns receives
%   (its Color sets the line colour). The line is dashed, half transparent,
%   kept out of legends, and tagged "dlab.overlay" so the simulator view
%   can remove it before the next redraw.
arguments
    ax (1,1)
    x
    y
    run (1,1) struct
    z = []
end
style = {"Color", [run.Color 0.6], "LineStyle", "--", "LineWidth", 1.2, "Tag", "dlab.overlay", ...
    "HandleVisibility", "off", "PickableParts", "none"};
if isempty(z)
    h = line(ax, x, y, style{:});
else
    h = line(ax, x, y, z, style{:});
end
uistack(h, "bottom");
end
