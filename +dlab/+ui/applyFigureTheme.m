function applyFigureTheme(fig, tokens)
%APPLYFIGURETHEME Set the figure background and MATLAB's own figure theme
%   (R2025a+) so native popups, scrollbars, and tooltips match the tokens.
arguments
    fig (1,1) matlab.ui.Figure
    tokens (1,1) dlab.ui.Theme
end
fig.Color = tokens.Background;
theme(fig, tokens.Name);
end
