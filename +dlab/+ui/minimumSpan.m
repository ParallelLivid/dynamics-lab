function minimumSpan(ax, span)
%MINIMUMSPAN Show at least SPAN on the y axis.
%   dlab.ui.minimumSpan(ax, span) returns the y limits to automatic and, if
%   they then cover less than SPAN (in the axis's units), widens them to
%   SPAN about their middle. Round-off (a position of 1e−16 m after a pure
%   roll) is then drawn as the flat line it is, not stretched over the
%   whole plot; a real motion keeps its own scale. Call it after plotting,
%   on every redraw (it resets the limits it set last time).
arguments
    ax (1,1)
    span (1,1) double {mustBePositive}
end
ylim(ax, "auto");
limits = ylim(ax);
if diff(limits) < span
    ylim(ax, mean(limits) + [-0.5 0.5] * span);
end
end
