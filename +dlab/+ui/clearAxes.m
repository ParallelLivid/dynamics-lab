function clearAxes(ax, options)
%CLEARAXES Empty an axes for redrawing but keep its styling.
%   dlab.ui.clearAxes(ax) deletes every child, turns the legend off and
%   sets hold on, ready for the next draw. (reset() would undo the theme,
%   and cla keeps children with HandleVisibility="off".)
%
%   dlab.ui.clearAxes(ax, KeepLegend=true) leaves the legend in place.
arguments
    ax (1,1)
    options.KeepLegend (1,1) logical = false
end
delete(allchild(ax));
if ~options.KeepLegend
    legend(ax, "off");
end
hold(ax, "on");
end
