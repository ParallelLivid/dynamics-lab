classdef TestTheme < matlab.unittest.TestCase
    %TESTTHEME Contrast and palette rules for both themes.

    properties (TestParameter)
        name = {"dark", "light"}
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function textSizesScaleTextAndRows(testCase)
            normal = dlab.ui.Theme.dark();
            testCase.verifyEqual([normal.FontSize.md normal.ControlHeight], [12 26]);
            larger = dlab.ui.Theme.byName("dark", "larger");
            testCase.verifyEqual([larger.FontSize.sm larger.FontSize.md larger.FontSize.xl], [13 16 23]);
            testCase.verifyEqual(larger.ControlHeight, 34, "Input rows grow with the text.");
            testCase.verifyEqual(larger.toggled().TextSize, "larger", "Switching theme keeps the size.");
            testCase.verifyEqual(larger.withTextSize("normal").FontSize, normal.FontSize);
        end

        function contrastFormulaMatchesWcag(testCase)
            testCase.verifyEqual(dlab.ui.Theme.contrast([0 0 0], [1 1 1]), 21, AbsTol=1e-12);
            testCase.verifyEqual(dlab.ui.Theme.contrast([1 1 1], [1 1 1]), 1, AbsTol=1e-12);
        end

        function textIsReadable(testCase, name)
            theme = dlab.ui.Theme.byName(name);
            surfaces = {theme.Background, theme.Surface, theme.SurfaceRaised};
            for k = 1:numel(surfaces)
                testCase.verifyGreaterThanOrEqual(dlab.ui.Theme.contrast(theme.Text, surfaces{k}), 4.5);
                testCase.verifyGreaterThanOrEqual(dlab.ui.Theme.contrast(theme.TextMuted, surfaces{k}), 4.5);
            end
            testCase.verifyGreaterThanOrEqual(dlab.ui.Theme.contrast(theme.OnAccent, theme.Accent), 4.5);
            testCase.verifyGreaterThanOrEqual(dlab.ui.Theme.contrast(theme.OnDanger, theme.Danger), 4.5);
            testCase.verifyGreaterThanOrEqual( ...
                dlab.ui.Theme.contrast(theme.AxesForeground, theme.AxesBackground), 4.5);
        end

        function statusColorsAreReadable(testCase, name)
            theme = dlab.ui.Theme.byName(name);
            for color = {theme.Accent, theme.Success, theme.Warning, theme.Danger}
                testCase.verifyGreaterThanOrEqual(dlab.ui.Theme.contrast(color{1}, theme.Surface), 4.5);
            end
        end

        function seriesStandOutFromAxes(testCase, name)
            theme = dlab.ui.Theme.byName(name);
            for k = 1:size(theme.Series, 1)
                testCase.verifyGreaterThanOrEqual( ...
                    dlab.ui.Theme.contrast(theme.Series(k,:), theme.AxesBackground), 3, ...
                    sprintf("Series %d", k));
            end
        end

        function seriesSurviveColourBlindness(testCase, name)
            % The plot colours stay apart (CIE76 ΔE) when seen with protanopia,
            % deuteranopia, or tritanopia (Machado et al. 2009, severity 1):
            % the first four, used most, by more.
            series = dlab.ui.Theme.byName(name).Series;
            for vision = ["normal" "protan" "deutan" "tritan"]
                lab = srgbToLab(simulateVision(series, vision));
                testCase.verifyGreaterThan(minDistance(lab(1:4, :)), 15, vision + ", first four");
                testCase.verifyGreaterThan(minDistance(lab(1:6, :)), 12, vision + ", first six");
                testCase.verifyGreaterThan(minDistance(lab), 8, vision + ", all eight");
            end
        end

        function seriesAreDistinct(testCase, name)
            series = dlab.ui.Theme.byName(name).Series;
            n = size(series, 1);
            [i, j] = find(triu(true(n), 1));
            distances = vecnorm(series(i,:) - series(j,:), 2, 2);
            testCase.verifyGreaterThan(min(distances), 0.25);
        end

        function colormapsReadInOrder(testCase, name)
            theme = dlab.ui.Theme.byName(name);
            map = theme.sequentialMap(64);
            testCase.verifySize(map, [64 3]);
            lightness = arrayfun(@(k) luminance(map(k, :)), 1:64);
            steps = diff(lightness);
            testCase.verifyTrue(all(steps > 0) || all(steps < 0), "Sequential map is monotonic in lightness.");
            testCase.verifyGreaterThan(dlab.ui.Theme.contrast(map(1, :), theme.AxesBackground), 1.15, ...
                "The low end stands out from the background.");
            testCase.verifyGreaterThan(dlab.ui.Theme.contrast(map(end, :), theme.AxesBackground), 3);
            diverging = theme.divergingMap(65);
            testCase.verifyEqual(diverging(1, :), theme.series(1), AbsTol=1e-12);
            testCase.verifyEqual(diverging(end, :), theme.series(4), AbsTol=1e-12);
            testCase.verifyLessThan(dlab.ui.Theme.contrast(diverging(33, :), theme.AxesBackground), 1.5, ...
                "Zero sits near the background.");
        end

        function helpers(testCase)
            dark = dlab.ui.Theme.dark();
            testCase.verifyEqual(dark.toggled().Name, "light");
            testCase.verifyEqual(dark.toggled().toggled().Name, "dark");
            testCase.verifyEqual(dark.series(9), dark.series(1));
            testCase.verifyError(@() dlab.ui.Theme.byName("blue"), "MATLAB:validators:mustBeMember");
        end
    end
end

function value = luminance(rgb)
% WCAG relative luminance (as dlab.ui.Theme.contrast uses).
value = (dlab.ui.Theme.contrast(rgb, [0 0 0]) - 1) * 0.05;
end

function d = minDistance(points)
[i, j] = find(triu(true(size(points, 1)), 1));
d = min(vecnorm(points(i, :) - points(j, :), 2, 2));
end

function rgb = simulateVision(rgb, vision)
% Machado, Oliveira & Fernandes (2009), severity 1.0, on linear RGB.
matrices = struct( ...
    "normal", eye(3), ...
    "protan", [0.152286 1.052583 -0.204868; 0.114503 0.786281 0.099216; -0.003882 -0.048116 1.051998], ...
    "deutan", [0.367322 0.860646 -0.227968; 0.280085 0.672501 0.047413; -0.011820 0.042940 0.968881], ...
    "tritan", [1.255528 -0.076749 -0.178779; -0.078411 0.930809 0.147602; 0.004733 0.691367 0.303900]);
linear = toLinear(rgb) * matrices.(vision).';
linear = min(max(linear, 0), 1);
rgb = 1.055 * linear.^(1/2.4) - 0.055;
small = linear <= 0.0031308;
rgb(small) = 12.92 * linear(small);
end

function linear = toLinear(rgb)
linear = ((rgb + 0.055) / 1.055).^2.4;
small = rgb <= 0.04045;
linear(small) = rgb(small) / 12.92;
end

function lab = srgbToLab(rgb)
% sRGB (D65) to CIE L*a*b*.
xyz = toLinear(rgb) * [0.4124 0.3576 0.1805; 0.2126 0.7152 0.0722; 0.0193 0.1192 0.9505].';
xyz = xyz ./ [0.95047 1 1.08883];
f = xyz.^(1/3);
small = xyz <= 0.008856;
f(small) = 7.787 * xyz(small) + 16/116;
lab = [116 * f(:, 2) - 16, 500 * (f(:, 1) - f(:, 2)), 200 * (f(:, 2) - f(:, 3))];
end
