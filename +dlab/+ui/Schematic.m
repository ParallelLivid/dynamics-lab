classdef Schematic
    %SCHEMATIC Geometry of mechanical drawing symbols, in any orientation.
    %   Pure coordinates (no graphics, no colors), so animations create
    %   their objects once and update XData/YData (or Vertices) per frame.
    %   Points are [x y] rows; results are row vectors, NaN-separated where
    %   a symbol has several strokes.
    %
    %       [x, y] = dlab.ui.Schematic.spring([0 0], [0 1], 8, 0.2);
    %       set(springLine, XData=x, YData=y);
    %
    %   3-D shapes (box3, cone3) return Faces/Vertices for patch.

    methods (Static)
        function [x, y] = spring(p1, p2, coils, width)
            %SPRING Zig-zag coil from P1 to P2 with straight leads.
            [u, n, len] = frame(p1, p2);
            if len < 1e-12
                [x, y] = deal([p1(1) p2(1)], [p1(2) p2(2)]);
                return
            end
            lead = 0.12 * len;
            count = 2 * coils;
            along = lead + (0:count) / count * (len - 2 * lead);
            across = [0, width / 2 * (-1) .^ (1:count - 1), 0];
            s = [0, along, len];
            d = [0, across, 0];
            [x, y] = place(p1, u, n, s, d);
        end

        function [x, y] = damper(p1, p2, width)
            %DAMPER Cylinder fixed to P1, piston rod from P2 (as dashpots
            %   are drawn): the piston slides as the length changes.
            [u, n, len] = frame(p1, p2);
            if len < 1e-12
                [x, y] = deal(NaN, NaN);
                return
            end
            h = width / 2;
            base = 0.3 * len;              % cylinder bottom
            top = 0.75 * len;              % cylinder mouth
            piston = 0.55 * len;           % piston face
            s = [0 base NaN base base top NaN base top NaN piston piston NaN piston len];
            d = [0 0 NaN -h h h NaN -h -h NaN -0.8*h 0.8*h NaN 0 0];
            [x, y] = place(p1, u, n, s, d);
        end

        function [x, y] = hatch(p1, p2, count, depth)
            %HATCH Ground or wall line from P1 to P2 with COUNT ticks of
            %   length DEPTH on its right-hand side (below, for left-to-right).
            [u, n, len] = frame(p1, p2);
            s = [0 len];
            d = [0 0];
            ticks = linspace(0, len, max(count, 2));
            for k = 1:numel(ticks)
                s = [s NaN ticks(k) ticks(k) - depth]; %#ok<AGROW>
                d = [d NaN 0 -depth]; %#ok<AGROW>
            end
            [x, y] = place(p1, u, n, s, d);
        end

        function [x, y] = circle(center, radius, count)
            %CIRCLE Closed polygon approximating a circle (patch or line).
            if nargin < 3
                count = 40;
            end
            phi = linspace(0, 2*pi, count + 1);
            x = center(1) + radius * cos(phi);
            y = center(2) + radius * sin(phi);
        end

        function [x, y] = wheel(center, radius, spokes, angle)
            %WHEEL Rim and SPOKES spokes turned by ANGLE (rad), so rolling shows.
            [x, y] = dlab.ui.Schematic.circle(center, radius, 48);
            for k = 0:spokes - 1
                a = angle + 2 * pi * k / spokes;
                x = [x NaN center(1) center(1) + radius * cos(a)]; %#ok<AGROW>
                y = [y NaN center(2) center(2) + radius * sin(a)]; %#ok<AGROW>
            end
        end

        function [x, y] = rect(center, halfWidth, halfHeight, angle)
            %RECT Rectangle corners (patch), turned by ANGLE (rad).
            if nargin < 4
                angle = 0;
            end
            corners = [-halfWidth -halfHeight; halfWidth -halfHeight; halfWidth halfHeight; -halfWidth halfHeight];
            R = [cos(angle) -sin(angle); sin(angle) cos(angle)];
            points = corners * R.';
            x = center(1) + points(:, 1).';
            y = center(2) + points(:, 2).';
        end

        function [lx, ly, hx, hy] = arrow(p, v, headSize)
            %ARROW Shaft from P along V, and a filled head (patch) at its tip.
            tip = p + v;
            len = norm(v);
            if len < 1e-12
                [lx, ly, hx, hy] = deal(NaN, NaN, NaN, NaN);
                return
            end
            headSize = min(headSize, 0.6 * len);
            u = v / len;
            n = [-u(2) u(1)];
            back = tip - headSize * u;
            lx = [p(1) back(1)];
            ly = [p(2) back(2)];
            hx = [tip(1), back(1) + 0.5 * headSize * n(1), back(1) - 0.5 * headSize * n(1)];
            hy = [tip(2), back(2) + 0.5 * headSize * n(2), back(2) - 0.5 * headSize * n(2)];
        end

        function [faces, vertices] = discs(centers, radii, count)
            %DISCS Many circles as ONE patch: faces (N×count) and vertices,
            %   so a whole gas of particles updates with one set call.
            if nargin < 3
                count = 16;
            end
            n = size(centers, 1);
            radii = radii(:) .* ones(n, 1);
            phi = linspace(0, 2*pi, count + 1);
            phi(end) = [];
            vx = centers(:, 1) + radii .* cos(phi);
            vy = centers(:, 2) + radii .* sin(phi);
            vertices = [reshape(vx.', [], 1), reshape(vy.', [], 1)];
            faces = reshape(1:n * count, count, n).';
        end

        function [faces, vertices] = box3(dims)
            %BOX3 Cuboid with side lengths DIMS = [a b c], centred on the origin.
            h = dims(:).' / 2;
            vertices = [-1 -1 -1; 1 -1 -1; 1 1 -1; -1 1 -1; -1 -1 1; 1 -1 1; 1 1 1; -1 1 1] .* h;
            faces = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
        end

        function [faces, vertices] = cone3(radius, height, count)
            %CONE3 Cone with its apex at the origin and its base at z = HEIGHT
            %   (a spinning top on its pivot). Triangles: COUNT sides, COUNT base.
            if nargin < 3
                count = 32;
            end
            phi = (0:count - 1)' / count * 2 * pi;
            rim = [radius * cos(phi), radius * sin(phi), height * ones(count, 1)];
            vertices = [0 0 0; rim; 0 0 height];
            next = [2:count, 1]';
            ring = (1:count)';
            faces = [ones(count, 1), ring + 1, next + 1; (count + 2) * ones(count, 1), next + 1, ring + 1];
        end

        function points = transform(points, R, origin)
            %TRANSFORM Rotate rows of POINTS by R and shift by ORIGIN.
            points = points * R.' + origin(:).';
        end
    end
end

function [u, n, len] = frame(p1, p2)
% Unit vector along P1→P2, its left normal, and the length.
v = p2(:).' - p1(:).';
len = norm(v);
if len < 1e-12
    u = [1 0];
else
    u = v / len;
end
n = [-u(2) u(1)];
end

function [x, y] = place(p1, u, n, s, d)
% Local (along, across) coordinates to world x, y (NaN passes through).
x = p1(1) + s * u(1) + d * n(1);
y = p1(2) + s * u(2) + d * n(2);
end
