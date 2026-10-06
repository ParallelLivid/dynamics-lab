function lbl = label(parent, text, tokens, options)
%LABEL Themed text label.
%   lbl = dlab.ui.label(grid, "Length (m)", theme, Role="body")
%
%   Role: "body", "muted", "heading" (section titles), "title" (large),
%   or "mono" (numeric readouts).
arguments
    parent
    text (1,:) string
    tokens (1,1) dlab.ui.Theme
    options.Role (1,1) string {mustBeMember(options.Role, ["body" "muted" "heading" "title" "mono"])} = "body"
    options.HorizontalAlignment (1,1) string = "left"
    options.Tag (1,1) string = ""
    options.Tooltip (1,1) string = ""
    options.WordWrap (1,1) string = "off"
end
lbl = uilabel(parent, Text=text, FontColor=tokens.Text, FontSize=tokens.FontSize.md, ...
    HorizontalAlignment=options.HorizontalAlignment, Tag=options.Tag, ...
    Tooltip=options.Tooltip, WordWrap=options.WordWrap);
switch options.Role
    case "muted"
        lbl.FontColor = tokens.TextMuted;
        lbl.FontSize = tokens.FontSize.sm + 1;
    case "heading"
        set(lbl, FontColor=tokens.TextMuted, FontSize=tokens.FontSize.sm + 1, FontWeight="bold");
    case "title"
        set(lbl, FontSize=tokens.FontSize.xl, FontWeight="bold");
    case "mono"
        lbl.FontName = tokens.MonoFont;
end
end
