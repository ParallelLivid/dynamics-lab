function result = simulatePlate(p)
%SIMULATEPLATE 2-D transient heat conduction in a rectangular plate.
%   result = simulatePlate(p) solves  ρc ∂T/∂t = k ∇²T + q  on the
%   rectangle 0 ≤ x ≤ a, 0 ≤ y ≤ b by finite differences on an nx × ny
%   grid of nodes (edges included), stepping in time with the explicit
%   FTCS scheme or the Peaceman–Rachford ADI scheme (two half steps, each
%   implicit along one direction: tridiagonal solves along grid lines).
%   The faces of the plate are insulated; heat enters and leaves through
%   its four edges. Fields of P:
%
%     a, b              plate size along x and y (m)
%     nx, ny            grid nodes along x and y (≥ 3), edges included
%     k, rho, c         conductivity (W/m/K), density, specific heat
%     d                 thickness (m), for energies in J and powers in W
%     scheme            'explicit' | 'adi'
%     dt, tspan, dtOut  time step, duration, output spacing (s)
%     left, right,      edge structs (x = 0, x = a, y = 0, y = b): type
%     bottom, top       'fixed' (temperature T), 'flux' (heat flux into
%                       the plate, W/m²; 0 = insulated), or 'convection'
%                       (h, W/m²/K, to a fluid at Tinf)
%     initial           struct: type 'uniform' | 'hotspot' | 'mode' |
%                       'hotedge'; T0 (base, °C), amplitude (°C),
%                       position ([x y] fractions of a, b), width
%                       (fraction of max(a, b)), mode ([m n] half-waves),
%                       edge ('left' | 'right' | 'bottom' | 'top')
%     source            struct: type 'none' | 'uniform' | 'spot'; q (peak
%                       W/m³), position, width (as for the initial spot)
%     probe             [x y] of the probe, fractions of a and b
%     progressFcn       optional @(fraction) stop
%
%   result: t, x (row), y (column), T (ny × nx × numel(t), T(j, i) at
%   (x(i), y(j))), dt (the step used, which lands exactly on tspan), rx,
%   ry (α Δt/Δx², α Δt/Δy²), alpha, heatCapacity (ρc), thickness,
%   dtMax (the largest stable explicit step for this grid and these
%   edges), eigX, eigY (eigenvalues of the 1-D operators on the free
%   nodes, 1/s; the plate's are their sums), stable, blowupTime,
%   termination ('completed' | 'unstable' | 'cancelled'), energy
%   (stored, J, relative to 0 °C), heatIn (cumulative heat in through the
%   edges, J), generated (cumulative heat from the source, J), probe,
%   probeXY, centre (temperature at the centre), centreLine (numel(t) × nx,
%   along y = b/2), maxT, minT, meanT, steadyTime (first time within 1 % of
%   a final steady state, else NaN), and, for a mode start inside four
%   edges fixed at T0 with no source: hasExact, decayRate (exact λ),
%   modeAmplitude (the mode's amplitude in the solution), exactAmplitude,
%   and maxError (largest |T − exact| over the saved times, °C).
%   An explicit run that goes unstable stops early (stable = false).
validate(p);
[a, b, nx, ny] = deal(p.a, p.b, p.nx, p.ny);
dx = a / (nx - 1);
dy = b / (ny - 1);
x = (0:nx - 1) * dx;
y = (0:ny - 1)' * dy;
alpha = p.k / (p.rho * p.c);
steps = ceil(p.tspan / p.dt - 1e-9);
if steps * nx * ny > 5e8
    error('plate:TooManySteps', ['This run needs %d time steps on a %d × %d grid; ' ...
        'increase the time step or use a coarser grid.'], steps, nx, ny);
end
dt = p.tspan / steps;
adi = strcmpi(p.scheme, 'adi');

% 1-D operators with a mirrored ghost node at both ends (Gx, Gy), the
% convection terms on the diagonal (rx, ry), and the boundary forcing.
edges = {p.left, p.right, p.bottom, p.top};
[Gx, rxDiag, fixedX] = lineOperator(nx, dx, alpha, p.k, p.left, p.right);
[Gy, ryDiag, fixedY] = lineOperator(ny, dy, alpha, p.k, p.bottom, p.top);
fixed = fixedY | fixedX';                         % ny × nx: Dirichlet nodes
free = ~fixed;
Tfix = fixedField(p, nx, ny);
Bx = zeros(ny, nx);
Bx(:, 1) = 2 * alpha / (p.k * dx) * edgeInput(p.left);
Bx(:, nx) = 2 * alpha / (p.k * dx) * edgeInput(p.right);
By = zeros(ny, nx);
By(1, :) = 2 * alpha / (p.k * dy) * edgeInput(p.bottom);
By(ny, :) = 2 * alpha / (p.k * dy) * edgeInput(p.top);
q = sourceField(p.source, x, y, a, b);
S = q / (p.rho * p.c);
B = Bx + By + S;
GxT = Gx.';
rxRow = rxDiag.';

% Stability: the eigenvalues of the free-node operator are μx + μy.
Ox = Gx + spdiags(rxDiag, 0, nx, nx);
Oy = Gy + spdiags(ryDiag, 0, ny, ny);
eigX = sort(real(eig(full(Ox(~fixedX, ~fixedX)))));
eigY = sort(real(eig(full(Oy(~fixedY, ~fixedY)))));
dtMax = 2 / (abs(min(eigX)) + abs(min(eigY)));

if adi
    Mx = speye(nx) - dt / 2 * Ox;
    My = speye(ny) - dt / 2 * Oy;
    Mx(fixedX, :) = 0;
    Mx(fixedX, fixedX) = speye(nnz(fixedX));
    My(fixedY, :) = 0;
    My(fixedY, fixedY) = speye(nnz(fixedY));
    solveX = decomposition(Mx);
    solveY = decomposition(My);
end

% Energy bookkeeping (trapezoidal node areas, which the ghost-node
% operators conserve exactly): heat through fixed edges is what keeps
% their nodes at temperature.
wx = [0.5, ones(1, nx - 2), 0.5] * dx;
wy = [0.5; ones(ny - 2, 1); 0.5] * dy;
W = wy * wx;
C = p.rho * p.c * p.d;
rxField = repmat(rxRow, ny, 1);
ryField = repmat(ryDiag, 1, nx);
flowX = @(T, LX) C * (sum(W(free) .* (T(free) .* rxField(free) + Bx(free))) - sum(W(fixed) .* LX(fixed)));
flowY = @(T, LY) C * (sum(W(free) .* (T(free) .* ryField(free) + By(free))) - sum(W(fixed) .* LY(fixed)));
fixedSourceLoss = C * sum(W(fixed) .* S(fixed));
generation = C * sum(W(:) .* S(:));             % W

T = initialField(p, x, y);
T(fixed) = Tfix(fixed);
every = max([1, round(p.dtOut / dt), ceil(steps / 400)]);
outputs = unique([0:every:steps, steps]);
times = outputs' * dt;
count = numel(outputs);
stored = zeros(ny, nx, count);
stored(:, :, 1) = T;
heatIn = zeros(count, 1);
generated = zeros(count, 1);
scale = 1 + max(abs(T(:))) + edgeScale(edges) ...
    + max(abs(q(:))) * p.tspan / (p.rho * p.c) + fluxScale(edges, a, b, p.tspan, C / p.d);
stable = true;
blowupTime = NaN;
termination = 'completed';
inflow = 0;
next = 2;
LY = Gy * T;
for n = 1:steps
    if adi
        flowYBefore = flowY(T, LY);
        rhs = T + dt / 2 * (LY + ryDiag .* T + B);
        rhs(:, fixedX) = Tfix(:, fixedX);
        half = (solveX \ rhs.').';
        half(fixed) = Tfix(fixed);
        LX = half * GxT;
        rhs = half + dt / 2 * (LX + half .* rxRow + B);
        rhs(fixedY, :) = Tfix(fixedY, :);
        T = solveY \ rhs;
        T(fixed) = Tfix(fixed);
        LY = Gy * T;
        inflow = inflow + dt * (flowX(half, LX) + 0.5 * (flowYBefore + flowY(T, LY)) - fixedSourceLoss);
    else
        LX = T * GxT;
        inflow = inflow + dt * (flowX(T, LX) + flowY(T, LY) - fixedSourceLoss);
        T = T + dt * (LX + LY + T .* rxRow + ryDiag .* T + B);
        T(fixed) = Tfix(fixed);
        LY = Gy * T;
    end
    if ~all(isfinite(T(:))) || max(abs(T(:))) > 1e3 * scale
        stable = false;
        blowupTime = n * dt;
        termination = 'unstable';
        stored(:, :, next) = T;
        heatIn(next) = inflow;
        generated(next) = n * dt * generation;
        times = [times(1:next - 1); n * dt];
        [stored, heatIn, generated] = deal(stored(:, :, 1:next), heatIn(1:next), generated(1:next));
        break
    end
    if next <= count && n == outputs(next)
        stored(:, :, next) = T;
        heatIn(next) = inflow;
        generated(next) = n * dt * generation;
        next = next + 1;
        if isfield(p, 'progressFcn') && ~isempty(p.progressFcn) && p.progressFcn(n / steps)
            termination = 'cancelled';
            times = times(1:next - 1);
            [stored, heatIn, generated] = deal(stored(:, :, 1:next - 1), heatIn(1:next - 1), generated(1:next - 1));
            break
        end
    end
end
frames = numel(times);
flat = reshape(stored, ny * nx, frames);
result.t = times;
result.x = x;
result.y = y;
result.T = stored;
result.dt = dt;
result.rx = alpha * dt / dx^2;
result.ry = alpha * dt / dy^2;
result.alpha = alpha;
result.heatCapacity = p.rho * p.c;
result.thickness = p.d;
result.dtMax = dtMax;
result.eigX = eigX;
result.eigY = eigY;
result.stable = stable;
result.blowupTime = blowupTime;
result.termination = termination;
result.energy = C * (W(:)' * flat)';
result.heatIn = heatIn;
result.generated = generated;
result.probeXY = [p.probe(1) * a, p.probe(2) * b];
result.probe = pointHistory(stored, x, y, result.probeXY);
result.centre = pointHistory(stored, x, y, [a b] / 2);
result.centreLine = reshape(interp1(y, stored, b / 2), nx, frames)';
result.maxT = max(flat, [], 1)';
result.minT = min(flat, [], 1)';
result.meanT = (W(:)' * flat)' / (a * b);
result.steadyTime = steadyTime(result, stable, a, b, alpha);
result = exactSolution(result, p, x, y, W, alpha);
end

% ------------------------------------------------------------- the model
function [G, r, fixedEnds] = lineOperator(n, h, alpha, k, first, last)
% α ∂²/∂s² on a line of N nodes with a mirrored ghost node at both ends
% (any edge type), the convection terms α·(−2h_c/(k h)) for the diagonal,
% and which ends are fixed.
e = ones(n, 1);
G = spdiags([e -2*e e], -1:1, n, n);
G(1, 2) = 2;
G(n, n - 1) = 2;
G = (alpha / h^2) * G;
r = zeros(n, 1);
ends = {first, last};
index = [1 n];
fixedEnds = false(n, 1);
for s = 1:2
    switch lower(ends{s}.type)
        case 'convection'
            r(index(s)) = -2 * alpha * ends{s}.h / (k * h);
        case 'fixed'
            fixedEnds(index(s)) = true;
    end
end
end

function value = edgeInput(edge)
% Heat flux into the plate (flux edge) or h·T∞ (convection edge), W/m².
switch lower(edge.type)
    case 'flux'
        value = edge.flux;
    case 'convection'
        value = edge.h * edge.Tinf;
    otherwise
        value = 0;
end
end

function Tfix = fixedField(p, nx, ny)
% The temperature of every fixed node; where two fixed edges meet, the
% corner takes their average.
total = zeros(ny, nx);
count = zeros(ny, nx);
edges = {p.left, p.right, p.bottom, p.top};
rows = {1:ny, 1:ny, 1, ny};
cols = {1, nx, 1:nx, 1:nx};
for s = 1:4
    if strcmpi(edges{s}.type, 'fixed')
        total(rows{s}, cols{s}) = total(rows{s}, cols{s}) + edges{s}.T;
        count(rows{s}, cols{s}) = count(rows{s}, cols{s}) + 1;
    end
end
Tfix = total ./ max(count, 1);
end

function q = sourceField(source, x, y, a, b)
switch lower(source.type)
    case 'uniform'
        q = source.q * ones(numel(y), numel(x));
    case 'spot'
        w = source.width * max(a, b);
        q = source.q * exp(-((x - source.position(1) * a).^2 + (y - source.position(2) * b).^2) / w^2);
    otherwise
        q = zeros(numel(y), numel(x));
end
end

function T = initialField(p, x, y)
ic = p.initial;
[a, b] = deal(p.a, p.b);
T = ic.T0 * ones(numel(y), numel(x));
switch lower(ic.type)
    case 'uniform'
    case 'hotspot'
        w = ic.width * max(a, b);
        T = T + ic.amplitude * exp(-((x - ic.position(1) * a).^2 + (y - ic.position(2) * b).^2) / w^2);
    case 'mode'
        T = T + ic.amplitude * sin(ic.mode(2) * pi * y / b) * sin(ic.mode(1) * pi * x / a);
    case 'hotedge'
        w = ic.width * max(a, b);
        distances = struct('left', x + 0 * y, 'right', a - x + 0 * y, 'bottom', y + 0 * x, 'top', b - y + 0 * x);
        T = T + ic.amplitude * exp(-distances.(lower(ic.edge)) / w);
    otherwise
        error('plate:InvalidParameter', 'Unknown initial temperature "%s".', ic.type);
end
end

function s = edgeScale(edges)
s = 0;
for k = 1:4
    switch lower(edges{k}.type)
        case 'fixed'
            s = max(s, abs(edges{k}.T));
        case 'convection'
            s = max(s, abs(edges{k}.Tinf));
    end
end
end

function s = fluxScale(edges, a, b, tspan, rhoC)
% A generous bound on the temperature rise from prescribed edge fluxes.
lengths = [b b a a];
s = 0;
for k = 1:4
    if strcmpi(edges{k}.type, 'flux')
        s = s + abs(edges{k}.flux) * lengths(k) * tspan / (rhoC * a * b);
    end
end
end

% ---------------------------------------------------------------- outputs
function values = pointHistory(stored, x, y, xy)
frames = size(stored, 3);
values = zeros(frames, 1);
for k = 1:frames
    values(k) = interp2(x, y, stored(:, :, k), xy(1), xy(2));
end
end

function t = steadyTime(r, stable, a, b, alpha)
% The first output time within 1 % of the final field, if the final field
% is steady (it changes by less than 1 % of the run's change over the
% slowest diffusion time max(a, b)²/(π² α)).
t = NaN;
frames = numel(r.t);
if ~stable || frames < 3
    return
end
final = r.T(:, :, end);
change = max(abs(r.T(:, :, 1) - final), [], 'all');
if change < 1e-9
    return
end
rate = max(abs(final - r.T(:, :, end - 1)), [], 'all') / (r.t(end) - r.t(end - 1));
if rate * max(a, b)^2 / (pi^2 * alpha) > 0.01 * change
    return
end
distance = squeeze(max(abs(r.T - final), [], [1 2]));
k = find(distance <= 0.01 * change, 1);
t = r.t(k);
end

function r = exactSolution(r, p, x, y, W, alpha)
% Mode start, all four edges fixed at T0, no source: the mode decays as
% exp(−α π² (m²/a² + n²/b²) t) and keeps its shape.
r.hasExact = false;
r.decayRate = NaN;
r.modeAmplitude = [];
r.exactAmplitude = [];
r.maxError = NaN;
ic = p.initial;
edges = {p.left, p.right, p.bottom, p.top};
allFixed = all(cellfun(@(e) strcmpi(e.type, 'fixed') && e.T == ic.T0, edges));
if ~(strcmpi(ic.type, 'mode') && allFixed && strcmpi(p.source.type, 'none'))
    return
end
shape = sin(ic.mode(2) * pi * y / p.b) * sin(ic.mode(1) * pi * x / p.a);
lambda = alpha * pi^2 * ((ic.mode(1) / p.a)^2 + (ic.mode(2) / p.b)^2);
frames = numel(r.t);
amplitude = zeros(frames, 1);
worst = 0;
norm2 = sum(W .* shape.^2, 'all');
for k = 1:frames
    deviation = r.T(:, :, k) - ic.T0;
    amplitude(k) = sum(W .* deviation .* shape, 'all') / norm2;
    worst = max(worst, max(abs(deviation - ic.amplitude * exp(-lambda * r.t(k)) * shape), [], 'all'));
end
r.hasExact = true;
r.decayRate = lambda;
r.modeAmplitude = amplitude;
r.exactAmplitude = ic.amplitude * exp(-lambda * r.t);
r.maxError = worst;
end

function validate(p)
positive = {'a', 'b', 'k', 'rho', 'c', 'd', 'dt', 'tspan', 'dtOut'};
for k = 1:numel(positive)
    v = p.(positive{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        error('plate:InvalidParameter', '%s must be a positive number.', positive{k});
    end
end
for name = {'nx', 'ny'}
    v = p.(name{1});
    if ~(isscalar(v) && v >= 3 && v == round(v))
        error('plate:InvalidParameter', 'The grid needs at least 3 nodes along each side (%s).', name{1});
    end
end
if ~any(strcmpi(p.scheme, {'explicit', 'adi'}))
    error('plate:InvalidParameter', 'Unknown scheme "%s".', p.scheme);
end
if p.dt > p.tspan
    error('plate:InvalidParameter', 'The time step must not exceed the duration.');
end
names = {'left', 'right', 'bottom', 'top'};
for k = 1:4
    edge = p.(names{k});
    if ~any(strcmpi(edge.type, {'fixed', 'flux', 'convection'}))
        error('plate:InvalidParameter', 'Unknown type "%s" for the %s edge.', edge.type, names{k});
    end
    if strcmpi(edge.type, 'convection') && ~(edge.h > 0)
        error('plate:InvalidParameter', 'A convection edge (%s) needs a positive heat-transfer coefficient.', names{k});
    end
end
if strcmpi(p.initial.type, 'mode') && ~all(p.initial.mode >= 1 & p.initial.mode == round(p.initial.mode))
    error('plate:InvalidParameter', 'Mode numbers must be whole numbers of at least 1.');
end
if ~any(strcmpi(p.source.type, {'none', 'uniform', 'spot'}))
    error('plate:InvalidParameter', 'Unknown heat source "%s".', p.source.type);
end
end
