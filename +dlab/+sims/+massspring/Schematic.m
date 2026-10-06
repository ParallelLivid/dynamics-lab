classdef Schematic
    %SCHEMATIC Coordinates of the mass-spring drawing primitives.
    %   Pure geometry (no graphics), so the animation can create its
    %   objects once and only update XData/YData each frame. The shapes
    %   follow the original MassSpringApp drawing helpers.

    methods (Static)
        function [x, y] = spring(x1, y1, x2, y2, coils)
            %SPRING Zig-zag between (x1,y1) and (x2,y2).
            span = x2 - x1;
            if abs(span) < 1e-6
                [x, y] = deal([x1 x2], [y1 y2]);
                return
            end
            lead = 0.07;
            amplitude = 0.13;
            n = 4*coils + 1;
            along = linspace(0, 1, n) * (span - 2*lead*span);
            phase = mod((0:n-1) / (n-1) * coils, 1);
            wave = zeros(1, n);
            rising = phase < 0.25;
            middle = phase >= 0.25 & phase < 0.75;
            falling = phase >= 0.75;
            wave(rising) = amplitude * phase(rising) / 0.25;
            wave(middle) = amplitude * (1 - (phase(middle) - 0.25) / 0.5 * 2);
            wave(falling) = -amplitude + amplitude * (phase(falling) - 0.75) / 0.25;
            x = [x1, x1 + lead*span, x1 + lead*span + along, x2 - lead*span, x2];
            y = [y1, y1, y1 + wave, y2, y2];
        end

        function [x, y] = damper(x1, y1, x2, y2)
            %DAMPER Piston-and-cylinder symbol as one NaN-separated polyline.
            span = abs(x2 - x1);
            if span < 1e-8
                [x, y] = deal(NaN, NaN);
                return
            end
            s = sign(x2 - x1);
            yc = min(y1, y2);
            a = x1 + s*0.25*span; b = x1 + s*0.43*span; c = x1 + s*0.66*span; d = x1 + s*0.78*span;
            h = 0.065;
            x = [x1 x1 a NaN a a c c NaN b d NaN b b NaN d x2 x2];
            y = [y1 yc yc NaN yc-h yc+h yc+h yc-h NaN yc yc NaN yc-h yc+h NaN yc yc y2];
        end

        function [x, y] = box(xc, yc, halfWidth, halfHeight)
            %BOX Rectangle (mass) as patch vertices.
            x = xc + halfWidth * [-1 1 1 -1];
            y = yc + halfHeight * [-1 -1 1 1];
        end

        function [px, py, hx, hy] = wall(x, bottom, height, side, width)
            %WALL Wall block plus its hatching (NaN-separated).
            px = [x x+width x+width x];
            py = [bottom bottom bottom+height bottom+height];
            ys = bottom:0.13:bottom+height;
            if side == "left"
                offsets = [x, x - 0.055];
            else
                offsets = [x + width, x + width + 0.055];
            end
            hx = reshape([repmat(offsets', 1, numel(ys)); NaN(1, numel(ys))], 1, []);
            hy = reshape([ys; ys + 0.055; NaN(1, numel(ys))], 1, []);
        end

        function [lx, ly, hx, hy] = arrow(x1, x2, y)
            %ARROW Horizontal arrow: shaft line and head triangle.
            if abs(x2 - x1) < 1e-9
                [lx, ly, hx, hy] = deal(NaN, NaN, NaN, NaN);
                return
            end
            d = sign(x2 - x1) * 0.035;
            lx = [x1 x2];
            ly = [y y];
            hx = [x2, x2 - d, x2 - d];
            hy = [y, y + 0.04, y - 0.04];
        end
    end
end
