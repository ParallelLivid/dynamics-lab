function lgd = legend(ax, tokens, varargin)
%LEGEND Themed legend: dlab.ui.legend(ax, theme, "Location", "best", ...)
lgd = legend(ax, varargin{:});
lgd.TextColor = tokens.Text;
lgd.Color = tokens.Surface;
lgd.EdgeColor = tokens.Border;
end
