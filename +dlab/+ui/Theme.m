classdef Theme
    %THEME Design tokens shared by the shell and every simulator plugin.
    %   Code outside this file never writes RGB literals; it reads tokens:
    %
    %       theme = dlab.ui.Theme.dark();
    %       panel.BackgroundColor = theme.Surface;
    %       plot(ax, t, x, Color=theme.Series(1,:));
    %
    %   Text/background pairs meet WCAG AA (4.5:1) and every series color
    %   reaches 3:1 against the axes background; tests/core/TestTheme.m
    %   enforces both.

    properties (SetAccess = immutable)
        Name (1,1) string

        % Surfaces
        Background (1,3) double     % figure / outermost
        Surface (1,3) double        % panels, header, status bar
        SurfaceRaised (1,3) double  % fields, cards, buttons
        Border (1,3) double

        % Text
        Text (1,3) double
        TextMuted (1,3) double

        % Semantic
        Accent (1,3) double         % primary action, highlights
        OnAccent (1,3) double       % text drawn on Accent
        Success (1,3) double
        Warning (1,3) double
        Danger (1,3) double
        OnDanger (1,3) double

        % Plots
        AxesBackground (1,3) double
        AxesForeground (1,3) double % tick labels, axis lines, titles
        Grid (1,3) double
        Series (8,3) double         % categorical plot colors, in order
    end

    properties (SetAccess = private)
        FontSize = struct("sm", 10, "md", 12, "lg", 14, "xl", 18)
        ControlHeight = 26
        TextSize (1,1) string = "normal"    % one of TextSizes (the user's setting)
    end

    properties (Constant)
        MonoFont = "Consolas"
        Spacing = struct("xs", 4, "sm", 8, "md", 12, "lg", 16)
        Names = ["dark" "light"]
        TextSizes = ["normal" "large" "larger"]
        TextScales = [1 1.15 1.3]
    end

    methods (Static)
        function theme = dark()
            theme = dlab.ui.Theme("dark", ...
                Background     = [0.10 0.11 0.14], ...
                Surface        = [0.14 0.16 0.20], ...
                SurfaceRaised  = [0.19 0.21 0.27], ...
                Border         = [0.27 0.30 0.38], ...
                Text           = [0.92 0.94 0.97], ...
                TextMuted      = [0.64 0.68 0.76], ...
                Accent         = [0.35 0.72 0.95], ...
                OnAccent       = [0.05 0.08 0.12], ...
                Success        = [0.36 0.85 0.52], ...
                Warning        = [1.00 0.70 0.28], ...
                Danger         = [1.00 0.45 0.45], ...
                OnDanger       = [0.10 0.04 0.04], ...
                AxesBackground = [0.08 0.09 0.12], ...
                AxesForeground = [0.74 0.78 0.85], ...
                Grid           = [0.30 0.34 0.42], ...
                Series = [           % told apart with colour-blind vision too (TestTheme)
                    0.35 0.72 0.95   % blue
                    1.00 0.62 0.25   % orange
                    0.50 1.00 0.55   % green
                    0.80 0.25 0.30   % red
                    0.56 0.38 0.78   % purple
                    0.65 0.95 0.00   % lime
                    0.02 0.70 0.52   % teal
                    0.98 0.56 0.82]);% pink
        end

        function theme = light()
            theme = dlab.ui.Theme("light", ...
                Background     = [0.95 0.95 0.97], ...
                Surface        = [0.99 0.99 1.00], ...
                SurfaceRaised  = [1.00 1.00 1.00], ...
                Border         = [0.80 0.82 0.87], ...
                Text           = [0.11 0.13 0.17], ...
                TextMuted      = [0.38 0.42 0.49], ...
                Accent         = [0.10 0.42 0.80], ...
                OnAccent       = [1.00 1.00 1.00], ...
                Success        = [0.10 0.50 0.24], ...
                Warning        = [0.66 0.38 0.00], ...
                Danger         = [0.76 0.14 0.17], ...
                OnDanger       = [1.00 1.00 1.00], ...
                AxesBackground = [1.00 1.00 1.00], ...
                AxesForeground = [0.25 0.28 0.34], ...
                Grid           = [0.80 0.82 0.86], ...
                Series = [           % told apart with colour-blind vision too (TestTheme)
                    0.10 0.42 0.80   % blue
                    0.85 0.40 0.02   % orange
                    0.17 0.60 0.35   % green
                    0.60 0.00 0.30   % crimson
                    0.30 0.10 0.56   % violet
                    0.42 0.30 0.00   % brown (dark gold)
                    0.00 0.43 0.48   % teal
                    0.78 0.22 0.54]);% pink
        end

        function theme = byName(name, textSize)
            %BYNAME Theme.byName("dark") or Theme.byName("light"), with text
            %   at TEXTSIZE ("normal", "large", or "larger").
            arguments
                name (1,1) string {mustBeMember(name, ["dark" "light"])}
                textSize (1,1) string {mustBeMember(textSize, ["normal" "large" "larger"])} = "normal"
            end
            theme = dlab.ui.Theme.(name)().withTextSize(textSize);
        end

        function ratio = contrast(a, b)
            %CONTRAST WCAG 2 contrast ratio between two sRGB colors.
            la = relativeLuminance(a);
            lb = relativeLuminance(b);
            ratio = (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
        end
    end

    methods
        function color = series(obj, k)
            %SERIES k-th categorical color, cycling past the palette size.
            color = obj.Series(mod(k - 1, size(obj.Series, 1)) + 1, :);
        end

        function map = sequentialMap(obj, n)
            %SEQUENTIALMAP N×3 colormap for magnitudes (heatmaps, speeds):
            %   from just off the axes background, through Accent, toward
            %   the text color. Lightness changes monotonically, so it
            %   reads in order in both themes.
            arguments
                obj
                n (1,1) double {mustBeInteger, mustBePositive} = 256
            end
            stops = [blend(obj.AxesBackground, obj.Accent, 0.18); obj.Accent; blend(obj.Accent, obj.Text, 0.65)];
            map = ramp(stops, n);
        end

        function map = divergingMap(obj, n)
            %DIVERGINGMAP N×3 colormap for signed values (displacement,
            %   elevation): Series 1 for negative, the axes background in
            %   the middle (zero), Series 4 for positive.
            arguments
                obj
                n (1,1) double {mustBeInteger, mustBePositive} = 256
            end
            stops = [obj.series(1); blend(obj.AxesBackground, obj.Grid, 0.25); obj.series(4)];
            map = ramp(stops, n);
        end

        function other = toggled(obj)
            %TOGGLED The opposite theme, at the same text size.
            if obj.Name == "dark"
                other = dlab.ui.Theme.light();
            else
                other = dlab.ui.Theme.dark();
            end
            other = other.withTextSize(obj.TextSize);
        end

        function points = scaled(obj, points)
            %SCALED A font size given for normal text (for example a plot
            %   label's 9 points), scaled for the user's text size.
            points = points * obj.TextScales(obj.TextSizes == obj.TextSize);
        end

        function obj = withTextSize(obj, textSize)
            %WITHTEXTSIZE This theme with text (and control rows) scaled for
            %   TEXTSIZE, one of TextSizes.
            arguments
                obj
                textSize (1,1) string {mustBeMember(textSize, ["normal" "large" "larger"])}
            end
            scale = obj.TextScales(obj.TextSizes == textSize);
            base = struct("sm", 10, "md", 12, "lg", 14, "xl", 18);
            for field = string(fieldnames(base))'
                obj.FontSize.(field) = round(base.(field) * scale);
            end
            obj.ControlHeight = round(26 * scale);
            obj.TextSize = textSize;
        end
    end

    methods (Access = private)
        function obj = Theme(name, tokens)
            arguments
                name (1,1) string
                tokens.Background; tokens.Surface; tokens.SurfaceRaised; tokens.Border
                tokens.Text; tokens.TextMuted
                tokens.Accent; tokens.OnAccent; tokens.Success; tokens.Warning
                tokens.Danger; tokens.OnDanger
                tokens.AxesBackground; tokens.AxesForeground; tokens.Grid; tokens.Series
            end
            obj.Name = name;
            for field = string(fieldnames(tokens))'
                obj.(field) = tokens.(field);
            end
        end
    end
end

function luminance = relativeLuminance(rgb)
linear = rgb / 12.92;
high = rgb > 0.04045;
linear(high) = ((rgb(high) + 0.055) / 1.055) .^ 2.4;
luminance = linear * [0.2126; 0.7152; 0.0722];
end

function color = blend(a, b, fraction)
color = (1 - fraction) * a + fraction * b;
end

function map = ramp(stops, n)
% Piecewise-linear colormap through STOPS (rows), N entries.
positions = linspace(0, 1, size(stops, 1));
map = interp1(positions, stops, linspace(0, 1, n)');
map = min(max(map, 0), 1);
end
