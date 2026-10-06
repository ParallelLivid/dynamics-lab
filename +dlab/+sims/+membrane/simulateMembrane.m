function result = simulateMembrane(p)
%SIMULATEMEMBRANE Vibrating membrane (a drum head), by modes.
%   result = simulateMembrane(p) discretizes a stretched membrane with
%   fixed edges by finite differences, finds its lowest natural modes with
%   eigs on the sparse Laplacian, and adds them up exactly in time, each
%   decaying with damping ratio zeta.
%
%     ρ ∂²u/∂t² = T ∇²u,   c = √(T/ρ),   u = 0 on the edge
%
%     shape          'rectangle' (a × b, the 5-point Laplacian on a square
%                    grid) or 'circle' (radius R, a polar grid: rings at
%                    r = (i − ½)Δr and equally spaced angles, finite
%                    volumes, so no node sits at the singular centre)
%     a, b, R        size (m)
%     tension, rho   tension per length (N/m) and areal density (kg/m²)
%     grid           grid intervals across the longer side or the diameter
%     modes          number of modes kept (the lowest)
%     initial        'strike' (Gaussian initial velocity), 'pluck'
%                    (Gaussian displacement), or 'mode' (one mode)
%     height         strike speed (m/s), or displacement (m)
%     position       [x y] of the strike or pluck, as fractions of the
%                    bounding box (for a circle [0.5 0.5] is the centre)
%     width          Gaussian width, as a fraction of the larger side
%                    (rectangle) or of the diameter (circle)
%     mode           [m n]: rectangle, half-waves along x and y; circle,
%                    nodal diameters m (≥ 0) and nodal circles n (≥ 1,
%                    counting the rim)
%     zeta           modal damping ratio (every mode)
%     tspan, dtOut   duration and output step (s)
%     probe          [x y] of the probe, fractions of the bounding box
%     progressFcn    optional @(fraction) stop
%
%   result: t, Q (modal coordinates, modes × times), frequencies (Hz,
%   ascending), labels ([m n] per mode), analytic (the continuum value
%   of each mode, Hz), distinct (first mode of each label), shapes (nodes
%   × modes, mass-normalized), x, y (node coordinates), plotX, plotY (a
%   surface grid including the edge), plotShapes (shapes on that grid),
%   innerRows, innerCols (the grid without the fixed edge), outline,
%   modalEnergy, KE, PE, E, probe (displacement at the probe), probeXY,
%   startXY, maxDisplacement, fullEnergy (the start's energy before
%   truncation), captured (%), axisymmetric (% of the energy in m = 0
%   modes; circle only, else NaN), c, h, and nodes.
validate(p);
c = sqrt(p.tension / p.rho);
progress(p, 0.02);
if strcmpi(p.shape, 'circle')
    g = circleGrid(p.R, p.grid);
else
    g = rectangleGrid(p.a, p.b, p.grid);
end
n = numel(g.w);

% Lowest modes of −∇²: the symmetric form A = W^(-½) S W^(-½) with the
% (diagonal) node areas W, so ψ are orthonormal and φ = W^(-½) ψ / √ρ
% are mass-normalized (φ' M φ = 1, M = ρ W).
scale = 1 ./ sqrt(g.w);
A = spdiags(scale, 0, n, n) * g.S * spdiags(scale, 0, n, n);
A = (A + A') / 2;
k = min(p.modes, n);
if n <= 600 || k >= n - 2
    [Psi, lambda] = eig(full(A), 'vector');
else
    start = mod((1:n)' * 0.6180339887498949, 1) - 0.5;   % generic, reproducible
    [Psi, lambda] = eigs(A, k, 'smallestabs', 'StartVector', start, 'Tolerance', 1e-13);
    lambda = diag(lambda);
end
[lambda, order] = sort(real(lambda));
Psi = real(Psi(:, order));
lambda = lambda(1:k);
Psi = Psi(:, 1:k);
Phi = scale .* Psi / sqrt(p.rho);
if progress(p, 0.6)
    error('membrane:Cancelled', 'Cancelled.');
end

% Name the modes (and pick clean shapes inside degenerate pairs).
if strcmpi(p.shape, 'circle')
    [Phi, labels] = labelCircle(Phi, lambda, g);
    besselRoots = arrayfun(@(m, j) besselZero(m, j), labels(:, 1), labels(:, 2));
    analytic = c * besselRoots / (2 * pi * p.R);
else
    [Phi, labels] = labelRectangle(Phi, lambda, g, p.rho);
    analytic = c / 2 * sqrt((labels(:, 1) / p.a).^2 + (labels(:, 2) / p.b).^2);
end
% Each mode's largest deflection positive, so shapes are reproducible.
[~, peak] = max(abs(Phi), [], 1);
Phi = Phi .* sign(Phi(sub2ind(size(Phi), peak, 1:k)));
omega = c * sqrt(max(lambda, 0));
[~, firstOfLabel] = unique(labels, 'rows', 'stable');
distinct = false(k, 1);
distinct(firstOfLabel) = true;

% Initial state on the nodes and its modal coordinates.
M = p.rho * g.w;
startXY = g.toXY(p.position);
probeXY = g.toXY(p.probe);
u0 = zeros(n, 1);
v0 = zeros(n, 1);
w = p.width * g.size;
bump = p.height * exp(-((g.x - startXY(1)).^2 + (g.y - startXY(2)).^2) / w^2);
switch lower(p.initial)
    case 'strike'
        v0 = bump;
        fullEnergy = 0.5 * sum(M .* v0.^2);
    case 'pluck'
        u0 = bump;
        fullEnergy = 0.5 * p.tension * (u0' * g.S * u0);
    otherwise
        chosen = find(labels(:, 1) == p.mode(1) & labels(:, 2) == p.mode(2), 1);
        if isempty(chosen)
            error('membrane:InvalidParameter', ...
                'Mode (%d, %d) is not among the %d modes kept; keep more modes or refine the grid.', ...
                p.mode(1), p.mode(2), k);
        end
        u0 = p.height * Phi(:, chosen) / max(abs(Phi(:, chosen)));
        fullEnergy = 0.5 * p.tension * (u0' * g.S * u0);
end
q0 = Phi' * (M .* u0);
qd0 = Phi' * (M .* v0);
modalEnergy = 0.5 * (omega.^2 .* q0.^2 + qd0.^2);

% Probe: the grid point nearest the probe (the centre of a circle is the
% mean of the innermost ring, as in the plots).
P = g.plotMap;
inside = find(any(P, 2));
[~, nearest] = min((g.plotX(inside) - probeXY(1)).^2 + (g.plotY(inside) - probeXY(2)).^2);
probeRow = P(inside(nearest), :) * Phi;
plotShapes = full(P * Phi);

% Modal superposition, exact in time.
t = (0:p.dtOut:p.tspan)';
if t(end) < p.tspan - 1e-12 * p.tspan
    t(end + 1) = p.tspan;
end
if numel(t) > 2e5
    error('membrane:TooMuchOutput', ...
        'This run would store %d time samples; increase the output step or shorten the run.', numel(t));
end
nt = numel(t);
Q = zeros(k, nt);
Qd = zeros(k, nt);
maxDisplacement = 0;
chunk = 250;
for first = 1:chunk:nt
    idx = first:min(first + chunk - 1, nt);
    [Q(:, idx), Qd(:, idx)] = modalHistory(q0, qd0, omega, p.zeta, t(idx)');
    maxDisplacement = max(maxDisplacement, max(abs(plotShapes * Q(:, idx)), [], 'all'));
    if progress(p, 0.6 + 0.4 * idx(end) / nt)
        error('membrane:Cancelled', 'Cancelled.');
    end
end

result.t = t;
result.Q = Q;
result.frequencies = omega / (2 * pi);
result.labels = labels;
result.analytic = analytic;
result.distinct = distinct;
result.shapes = Phi;
result.x = g.x;
result.y = g.y;
result.plotX = g.plotX;
result.plotY = g.plotY;
result.plotShapes = plotShapes;
result.innerRows = g.innerRows;
result.innerCols = g.innerCols;
result.outline = g.outline;
result.modalEnergy = modalEnergy;
result.KE = 0.5 * sum(Qd.^2, 1)';
result.PE = 0.5 * sum(omega.^2 .* Q.^2, 1)';
result.E = result.KE + result.PE;
result.probe = (probeRow * Q)';
result.probeXY = [g.plotX(inside(nearest)) g.plotY(inside(nearest))];
result.startXY = startXY;
result.maxDisplacement = maxDisplacement;
result.fullEnergy = fullEnergy;
result.captured = 100 * sum(modalEnergy) / max(fullEnergy, realmin);
result.axisymmetric = NaN;
if strcmpi(p.shape, 'circle')
    result.axisymmetric = 100 * sum(modalEnergy(labels(:, 1) == 0)) / max(sum(modalEnergy), realmin);
end
result.c = c;
result.h = g.h;
result.nodes = n;
result.shape = lower(char(p.shape));
end

% ------------------------------------------------------------------ grids
function g = rectangleGrid(a, b, cells)
% The 5-point Laplacian on the interior nodes of an nx × ny grid. Node
% (iy, ix) is number iy + (ix − 1)(ny − 1).
if a >= b
    nx = cells;
    ny = max(2, round(cells * b / a));
else
    ny = cells;
    nx = max(2, round(cells * a / b));
end
hx = a / nx;
hy = b / ny;
second = @(m, h) spdiags(ones(m - 1, 1) * [-1 2 -1], -1:1, m - 1, m - 1) / h^2;
Ix = speye(nx - 1);
Iy = speye(ny - 1);
Lap = kron(second(nx, hx), Iy) + kron(Ix, second(ny, hy));   % −∇²
g.w = hx * hy * ones((nx - 1) * (ny - 1), 1);
g.S = hx * hy * Lap;                                          % W (−∇²), symmetric
[X, Y] = meshgrid((1:nx - 1) * hx, (1:ny - 1)' * hy);
g.x = X(:);
g.y = Y(:);
g.nx = nx;
g.ny = ny;
[g.plotX, g.plotY] = meshgrid((0:nx) * hx, (0:ny)' * hy);
[rows, cols] = ndgrid(2:ny, 2:nx);
plotIndex = sub2ind([ny + 1, nx + 1], rows(:), cols(:));
g.plotMap = sparse(plotIndex, 1:numel(plotIndex), 1, (ny + 1) * (nx + 1), numel(plotIndex));
g.innerRows = 2:ny;
g.innerCols = 2:nx;
g.outline = [0 a a 0 0; 0 0 b b 0];
g.size = max(a, b);
g.h = max(hx, hy);
g.toXY = @(f) [f(1) * a, f(2) * b];
end

function g = circleGrid(R, cells)
% Polar finite volumes: Nr rings at r_i = (i − ½)Δr (the rim, u = 0, is
% at r = (Nr + ½)Δr = R) and Nθ = 4 Nr angles. Node (i, j) is number
% i + (j − 1) Nr. The flux through r = 0 vanishes, so the centre needs no
% special node; the scheme is second order.
Nr = max(2, round(cells / 2));
Nt = 4 * Nr;
dr = R / (Nr + 0.5);
dt = 2 * pi / Nt;
r = ((1:Nr)' - 0.5) * dr;
inner = r - dr / 2;                 % r_{i−½} (0 at the centre)
outer = r + dr / 2;                 % r_{i+½} (R at the rim)
Dr = spdiags([[-inner(2:end); 0], inner + outer, [0; -outer(1:end-1)]], -1:1, Nr, Nr) * (dt / dr);
Ct = spdiags(ones(Nt, 1) * [-1 2 -1], -1:1, Nt, Nt);
Ct(1, Nt) = -1;
Ct(Nt, 1) = -1;
g.S = kron(speye(Nt), Dr) + kron(Ct, spdiags(dr ./ (r * dt), 0, Nr, Nr));
g.w = kron(ones(Nt, 1), r * dr * dt);
theta = (0:Nt - 1) * dt;
[RR, TT] = ndgrid(r, theta);
g.x = RR(:) .* cos(TT(:));
g.y = RR(:) .* sin(TT(:));
g.r = r;
g.theta = theta;
g.Nr = Nr;
g.Nt = Nt;
% Plot grid: the centre, the rings, the rim; the first angle repeated.
radii = [0; r; R];
angles = [theta 2 * pi];
[PR, PT] = ndgrid(radii, angles);
g.plotX = PR .* cos(PT);
g.plotY = PR .* sin(PT);
rowsAll = Nr + 2;
[ii, jj] = ndgrid(1:Nr, 1:Nt + 1);
node = ii + (mod(jj - 1, Nt)) * Nr;
plotIndex = sub2ind([rowsAll, Nt + 1], ii + 1, jj);
centre = sub2ind([rowsAll, Nt + 1], ones(1, Nt + 1), 1:Nt + 1);
[cr, cn] = ndgrid(centre, (0:Nt - 1) * Nr + 1);
g.plotMap = sparse([plotIndex(:); cr(:)], [node(:); cn(:)], ...
    [ones(numel(node), 1); ones(numel(cr), 1) / Nt], rowsAll * (Nt + 1), Nr * Nt);
g.innerRows = 1:Nr + 1;
g.innerCols = 1:Nt + 1;
ring = linspace(0, 2 * pi, 181);
g.outline = R * [cos(ring); sin(ring)];
g.size = 2 * R;
g.h = dr;
g.toXY = @(f) [(2 * f(1) - 1) * R, (2 * f(2) - 1) * R];
end

% --------------------------------------------------------------- labelling
function [Phi, labels] = labelRectangle(Phi, lambda, g, rho)
% (m, n) from the discrete sine transform: the grid's exact eigenvectors
% are sin(mπx/a) sin(nπy/b) sampled at the nodes. Inside a degenerate
% cluster (a square's (1,2) and (2,1)) eigs returns any mix, so those
% are replaced by the pure products.
nx = g.nx;
ny = g.ny;
Sx = sin(pi * (1:nx - 1)' * (1:nx - 1) / nx);
Sy = sin(pi * (1:ny - 1)' * (1:ny - 1) / ny);
k = numel(lambda);
labels = zeros(k, 2);
for cluster = clusters(lambda)
    members = cluster{1};
    weight = zeros(ny - 1, nx - 1);
    for j = members
        C = Sy' * reshape(Phi(:, j), ny - 1, nx - 1) * Sx;      % (n, m)
        weight = weight + C.^2;
    end
    [~, best] = sort(weight(:), 'descend');
    [nn, mm] = ind2sub(size(weight), best(1:numel(members)));
    [~, byM] = sortrows([mm nn]);
    mm = mm(byM);
    nn = nn(byM);
    for q = 1:numel(members)
        j = members(q);
        labels(j, :) = [mm(q) nn(q)];
        if numel(members) > 1
            v = kron(Sx(:, mm(q)), Sy(:, nn(q)));
            Phi(:, j) = v / sqrt(rho * sum(g.w .* v.^2));
        end
    end
end
end

function [Phi, labels] = labelCircle(Phi, lambda, g)
% m from the angular Fourier content; a cos/sin pair is rotated so that
% the first is pure cos(mθ) and the second pure sin(mθ). n counts the
% distinct frequencies with the same m.
Nr = g.Nr;
Nt = g.Nt;
k = numel(lambda);
labels = zeros(k, 2);
counts = zeros(Nt, 1);
for cluster = clusters(lambda)
    members = cluster{1};
    ms = zeros(size(members));
    for q = 1:numel(members)
        ms(q) = angularOrder(Phi(:, members(q)), g);
    end
    if numel(members) == 2 && ms(1) == ms(2) && ms(1) > 0
        m = ms(1);
        sinContent = @(v) sum(g.r .* (reshape(v, Nr, Nt) * sin(m * g.theta')));
        s1 = sinContent(Phi(:, members(1)));
        s2 = sinContent(Phi(:, members(2)));
        alpha = atan2(-s1, s2);
        pair = Phi(:, members) * [cos(alpha) -sin(alpha); sin(alpha) cos(alpha)];
        Phi(:, members) = pair;
        counts(m + 1) = counts(m + 1) + 1;
        labels(members, :) = [m m; counts(m + 1) counts(m + 1)]';
    else
        for q = 1:numel(members)
            m = ms(q);
            counts(m + 1) = counts(m + 1) + 1;
            labels(members(q), :) = [m counts(m + 1)];
        end
    end
end
end

function m = angularOrder(v, g)
% The angular wavenumber with the most (area-weighted) energy. A real
% shape's spectrum is symmetric, so wavenumbers 0 … Nθ/2 suffice.
F = abs(fft(reshape(v, g.Nr, g.Nt), [], 2)).^2;
power = g.r' * F;
[~, best] = max(power(1:floor(g.Nt / 2) + 1));
m = best - 1;
end

function groups = clusters(lambda)
% Runs of (numerically) equal eigenvalues, as a cell row of index rows.
groups = {};
j = 1;
k = numel(lambda);
while j <= k
    last = j;
    while last < k && abs(lambda(last + 1) - lambda(j)) <= 1e-7 * abs(lambda(j))
        last = last + 1;
    end
    groups{end + 1} = j:last; %#ok<AGROW>
    j = last + 1;
end
end

function z = besselZero(m, n)
% The n-th positive zero of J_m: bracket by scanning, refine with fzero.
step = 0.1;
x = 0.1;
f = besselj(m, x);
found = 0;
while true
    xNext = x + step;
    fNext = besselj(m, xNext);
    if sign(fNext) ~= sign(f) && fNext ~= 0
        found = found + 1;
        if found == n
            z = fzero(@(s) besselj(m, s), [x xNext]);
            return
        end
    end
    x = xNext;
    f = fNext;
end
end

% ------------------------------------------------------------------- time
function [Q, Qd] = modalHistory(q0, qd0, omega, zeta, t)
% Each modal coordinate's free response (rows: modes, columns: times).
w = omega;
wd = w * sqrt(1 - zeta^2);
decay = exp(-zeta * w * t);
B = (qd0 + zeta * w .* q0) ./ max(wd, eps);
Q = decay .* (q0 .* cos(wd * t) + B .* sin(wd * t));
Qd = decay .* ((-zeta * w .* q0 + wd .* B) .* cos(wd * t) + (-zeta * w .* B - wd .* q0) .* sin(wd * t));
end

function stop = progress(p, fraction)
stop = false;
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    stop = p.progressFcn(fraction);
end
end

function validate(p)
bad = @(varargin) error('membrane:InvalidParameter', varargin{:});
if ~any(strcmpi(p.shape, {'rectangle', 'circle'}))
    bad('The shape must be ''rectangle'' or ''circle''.');
end
positive = {'tension', 'rho', 'tspan', 'dtOut', 'width'};
if strcmpi(p.shape, 'circle')
    positive = [positive {'R'}];
else
    positive = [positive {'a', 'b'}];
end
for k = 1:numel(positive)
    v = p.(positive{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        bad('%s must be a positive number.', positive{k});
    end
end
if ~(isscalar(p.grid) && p.grid >= 4 && p.grid <= 400 && p.grid == round(p.grid))
    bad('Use a grid of 4 to 400 intervals.');
end
if ~(isscalar(p.modes) && p.modes >= 1 && p.modes <= 500 && p.modes == round(p.modes))
    bad('Keep 1 to 500 modes.');
end
if ~(isscalar(p.zeta) && p.zeta >= 0 && p.zeta < 1)
    bad('The damping ratio must be in [0, 1).');
end
if ~any(strcmpi(p.initial, {'strike', 'pluck', 'mode'}))
    bad('Unknown start "%s".', p.initial);
end
if ~(isscalar(p.height) && isfinite(p.height))
    bad('The amplitude must be a finite number.');
end
inShape = @(f) numel(f) == 2 && all(isfinite(f)) && ...
    ((strcmpi(p.shape, 'circle') && norm(2 * f(:) - 1) < 1) || ...
     (~strcmpi(p.shape, 'circle') && all(f > 0 & f < 1)));
if ~strcmpi(p.initial, 'mode') && ~inShape(p.position)
    bad('Strike or pluck inside the membrane.');
end
if ~inShape(p.probe)
    bad('Put the probe inside the membrane.');
end
if strcmpi(p.initial, 'mode')
    m = p.mode;
    lowest = 1;
    if strcmpi(p.shape, 'circle')
        lowest = 0;
    end
    if ~(numel(m) == 2 && all(m == round(m)) && m(1) >= lowest && m(2) >= 1)
        if lowest == 1
            bad('A rectangle''s mode numbers m and n start at 1.');
        else
            bad('A circle''s modes have m ≥ 0 nodal diameters and n ≥ 1 nodal circles.');
        end
    end
end
end
