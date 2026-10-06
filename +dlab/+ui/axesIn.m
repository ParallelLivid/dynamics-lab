function ax = axesIn(parent, tokens, options)
%AXESIN Create a themed uiaxes in a grid layout.
%   ax = dlab.ui.axesIn(grid, theme, Title="Energy", XLabel="Time (s)", ...
%                       YLabel="E (J)", Row=1, Column=1)
arguments
    parent
    tokens (1,1) dlab.ui.Theme
    options.Title (1,1) string = ""
    options.XLabel (1,1) string = ""
    options.YLabel (1,1) string = ""
    options.ZLabel (1,1) string = ""
    options.Row = []
    options.Column = []
end
ax = uiaxes(parent);
if ~isempty(options.Row)
    ax.Layout.Row = options.Row;
end
if ~isempty(options.Column)
    ax.Layout.Column = options.Column;
end
dlab.ui.styleAxes(ax, tokens);
title(ax, options.Title);
xlabel(ax, options.XLabel);
ylabel(ax, options.YLabel);
zlabel(ax, options.ZLabel);
end
