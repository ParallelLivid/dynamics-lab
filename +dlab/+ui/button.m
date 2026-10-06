function b = button(parent, text, tokens, options)
%BUTTON Themed push button.
%   b = dlab.ui.button(grid, "Run", theme, Kind="primary", Callback=@(~,~) run())
%
%   Kind: "primary" (main action), "secondary", "danger", or "ghost"
%   (flat, for header/toolbar actions).
arguments
    parent
    text (1,1) string
    tokens (1,1) dlab.ui.Theme
    options.Kind (1,1) string {mustBeMember(options.Kind, ["primary" "secondary" "danger" "ghost"])} = "secondary"
    options.Callback = []
    options.Tag (1,1) string = ""
    options.Tooltip (1,1) string = ""
end
b = uibutton(parent, "push", Text=text, Tag=options.Tag, Tooltip=options.Tooltip, ...
    FontSize=tokens.FontSize.md);
switch options.Kind
    case "primary"
        set(b, BackgroundColor=tokens.Accent, FontColor=tokens.OnAccent, FontWeight="bold");
    case "danger"
        set(b, BackgroundColor=tokens.Danger, FontColor=tokens.OnDanger, FontWeight="bold");
    case "ghost"
        set(b, BackgroundColor=tokens.Surface, FontColor=tokens.Text);
    otherwise
        set(b, BackgroundColor=tokens.SurfaceRaised, FontColor=tokens.Text);
end
if ~isempty(options.Callback)
    b.ButtonPushedFcn = options.Callback;
end
end
