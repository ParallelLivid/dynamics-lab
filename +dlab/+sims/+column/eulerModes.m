function e = eulerModes(EI, L, n)
%EULERMODES Euler buckling loads and mode shapes for four end conditions.
%   e = dlab.sims.column.eulerModes(EI, L) with the bending stiffness EI
%   (N·m²) and length L (m); n samples along the column (default 401).
%   Fields of E:
%     names          "pinned" "fixedfree" "fixedpinned" "fixedfixed"
%     labels         readable names
%     K              effective length factors 1, 2, π/β ≈ 0.699, 0.5
%                    (β = 4.4934, the first root of tan β = β)
%     Pcr            π² EI / (K L)² (N)
%     x              n×1 positions x/L from the base (0) to the top (1)
%     modes          n×4 mode shapes φ, largest value 1
%     momentFactors  EI·max|φ''| / P_cr: the largest moment of a column
%                    bowed in its mode, over P times the largest deflection
%                    (1, 1, ≈ 0.733, 1/2)
%
%   The fixed end is at the base. Modes: sin πx (pinned–pinned),
%   1 − cos(πx/2) (fixed–free), (1 − cos 2πx)/2 (fixed–fixed), and
%   β(1 − cos βx) − βx + sin βx (fixed–pinned), with x = x/L.
arguments
    EI (1,1) double {mustBePositive}
    L (1,1) double {mustBePositive}
    n (1,1) double {mustBeInteger, mustBePositive} = 401
end
beta = 4.493409457909064;
e.names = ["pinned" "fixedfree" "fixedpinned" "fixedfixed"];
e.labels = ["Pinned–pinned" "Fixed–free" "Fixed–pinned" "Fixed–fixed"];
e.K = [1 2 pi / beta 0.5];
e.Pcr = pi^2 * EI ./ (e.K * L).^2;
x = linspace(0, 1, n)';
e.x = x;
shape = @(x) beta * (1 - cos(beta * x)) - beta * x + sin(beta * x);
[~, negPeak] = fminbnd(@(x) -shape(x), 0.3, 0.9, optimset("TolX", 1e-12));
peak = -negPeak;
e.modes = [sin(pi * x), 1 - cos(pi * x / 2), shape(x) / peak, (1 - cos(2 * pi * x)) / 2];
% Fixed–pinned: φ'' = β²(β cos βx − sin βx)/peak, whose magnitude peaks at
% √(β² + 1) where βx = π − atan(1/β) (x ≈ 0.65, inside the span).
e.momentFactors = [1 1 sqrt(beta^2 + 1) / peak 0.5];
end
