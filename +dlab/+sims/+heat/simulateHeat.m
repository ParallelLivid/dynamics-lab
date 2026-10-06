function result = simulateHeat(p)
%SIMULATEHEAT 1-D heat conduction by finite differences (method of lines).
%   result = simulateHeat(p) solves  ρc ∂T/∂t = k ∂²T/∂x² + q  on [0, L]
%   with the θ-method: explicit (forward Euler, FTCS), implicit (backward
%   Euler), or Crank–Nicolson. Fields of P:
%
%     L, N              rod length (m) and number of nodes, ends included
%     k, rho, c         conductivity (W/m/K), density, specific heat
%     q                 uniform heat source (W/m³)
%     scheme            'explicit' | 'implicit' | 'cranknicolson'
%     dt, tspan, dtOut  time step, duration, output spacing (s)
%     left, right       boundary structs: type 'dirichlet' (temperature T,
%                       a number or @(t) value), 'neumann' (heat flux into
%                       the rod, W/m²; 0 = insulated), or 'robin'
%                       (convection: h, W/m²/K, to a fluid at Tinf)
%     initial           struct: type 'uniform' | 'step' | 'sine' |
%                       'hotspot'; T0 (base, °C), amplitude (°C), mode
%                       (sine), position and width (fractions of L)
%     progressFcn       optional @(fraction) stop
%
%   result: t, x, T (numel(t) × N), r (mesh Fourier number α Δt/Δx²),
%   stable, blowupTime, energy (stored, J/m²), heatIn (cumulative heat
%   in through the ends and from the source, J/m²), exact (or []),
%   dt (the step used, which lands exactly on tspan), alpha, and
%   heatCapacity (ρc, J/m³/K).
%   An explicit run that goes unstable stops early (stable = false).
validate(p);
N = p.N;
L = p.L;
dx = L / (N - 1);
x = (0:N - 1)' * dx;
alpha = p.k / (p.rho * p.c);
steps = ceil(p.tspan / p.dt - 1e-9);
if steps > 2e6
    error('heat:TooManySteps', 'This run needs %d time steps; increase the time step.', steps);
end
dt = p.tspan / steps;
r = alpha * dt / dx^2;
weightsByScheme = struct('explicit', 0, 'implicit', 1, 'cranknicolson', 0.5);
theta = weightsByScheme.(lower(p.scheme));

% dT/dt = A T + b(t) at every node; Dirichlet nodes are set directly.
e = ones(N, 1);
A = spdiags([e -2*e e], -1:1, N, N);
[A, leftGain] = boundaryRow(A, 1, 2, p.left, p.k, dx);
[A, rightGain] = boundaryRow(A, N, N - 1, p.right, p.k, dx);
A = (alpha / dx^2) * A;
source = p.q / (p.rho * p.c);
fixed = false(N, 1);
fixed(1) = strcmpi(p.left.type, 'dirichlet');
fixed(N) = strcmpi(p.right.type, 'dirichlet');
A(fixed, :) = 0;

I = speye(N);
lhs = I - theta * dt * A;
rhs = I + (1 - theta) * dt * A;
lhs(fixed, :) = I(fixed, :);
rhs(fixed, :) = 0;

T = initialTemperature(p, x);
T(1) = fixedValue(p.left, 0, T(1));
T(N) = fixedValue(p.right, 0, T(N));

every = max(1, round(p.dtOut / dt));
outputs = unique([0:every:steps, steps]);
times = outputs' * dt;
stored = zeros(numel(outputs), N);
stored(1, :) = T';
heatIn = zeros(numel(outputs), 1);
weights = [0.5; ones(N - 2, 1); 0.5] * dx;
scale = 1 + max(abs(T)) + boundaryScale(p.left) + boundaryScale(p.right);
stable = true;
blowupTime = NaN;
inflow = 0;
halfCell = p.rho * p.c * dx / 2;
next = 2;
for n = 1:steps
    t0 = (n - 1) * dt;
    t1 = n * dt;
    before = T;
    flowBefore = boundaryFlow(p.left, T, 1, 2, p.k, dx, t0) + boundaryFlow(p.right, T, N, N - 1, p.k, dx, t0);
    b = (1 - theta) * forcing(p, leftGain, rightGain, N, t0, source) + theta * forcing(p, leftGain, rightGain, N, t1, source);
    v = rhs * T + dt * b;
    v(1) = fixedValue(p.left, t1, v(1));
    v(N) = fixedValue(p.right, t1, v(N));
    if theta == 0
        T = v;
    else
        T = lhs \ v;
    end
    flowAfter = boundaryFlow(p.left, T, 1, 2, p.k, dx, t1) + boundaryFlow(p.right, T, N, N - 1, p.k, dx, t1);
    % The heat in over the step, weighted in time as the scheme weights it
    % (so the balance closes for every scheme). A fixed-temperature end's
    % flux reaches the first interior node; the heat that changes its own
    % half cell (and less the source there) also comes through the end.
    inflow = inflow + dt * ((1 - theta) * flowBefore + theta * flowAfter) + dt * p.q * L;
    for i = find(fixed)'
        inflow = inflow + halfCell * (T(i) - before(i)) - dt * p.q * dx / 2;
    end
    if ~all(isfinite(T)) || max(abs(T)) > 1e3 * scale
        stable = false;
        blowupTime = t1;
        stored(next, :) = T';
        heatIn(next) = inflow;
        times = [times(1:next - 1); t1];
        stored = stored(1:next, :);
        heatIn = heatIn(1:next);
        break
    end
    if next <= numel(outputs) && n == outputs(next)
        stored(next, :) = T';
        heatIn(next) = inflow;
        next = next + 1;
        if isfield(p, 'progressFcn') && ~isempty(p.progressFcn) && p.progressFcn(n / steps)
            times = times(1:next - 1);
            stored = stored(1:next - 1, :);
            heatIn = heatIn(1:next - 1);
            break
        end
    end
end

result.t = times;
result.x = x;
result.T = stored;
result.r = r;
result.dt = dt;
result.alpha = alpha;
result.heatCapacity = p.rho * p.c;
result.stable = stable;
result.blowupTime = blowupTime;
result.energy = p.rho * p.c * (stored * weights);
result.heatIn = heatIn;
result.exact = exactSolution(p, x, times, alpha);
end

% ------------------------------------------------------------- the model
function [A, gain] = boundaryRow(A, i, inner, bc, k, dx)
% Row I of the second-difference matrix for a flux or convection end
% (a ghost node mirrored across the end); GAIN multiplies the boundary
% heat flux into the rod in the forcing term.
gain = 0;
switch lower(bc.type)
    case 'neumann'
        A(i, inner) = 2;
        gain = 2 * dx / k;
    case 'robin'
        A(i, inner) = 2;
        A(i, i) = -2 - 2 * dx * bc.h / k;
        gain = 2 * dx / k;
end
end

function b = forcing(p, leftGain, rightGain, N, t, source)
% Constant and time-dependent terms of dT/dt (boundary fluxes, sources).
alpha = p.k / (p.rho * p.c);
dx = p.L / (N - 1);
b = source * ones(N, 1);
b(1) = b(1) + alpha / dx^2 * leftGain * boundaryInput(p.left, t);
b(N) = b(N) + alpha / dx^2 * rightGain * boundaryInput(p.right, t);
end

function value = boundaryInput(bc, t)
% Heat flux (Neumann) or h·T∞ (Robin) driving the end.
switch lower(bc.type)
    case 'neumann'
        value = evaluate(bc.flux, t);
    case 'robin'
        value = bc.h * evaluate(bc.Tinf, t);
    otherwise
        value = 0;
end
end

function value = fixedValue(bc, t, current)
if strcmpi(bc.type, 'dirichlet')
    value = evaluate(bc.T, t);
else
    value = current;
end
end

function flow = boundaryFlow(bc, T, i, inner, k, dx, t)
% Heat flowing into the rod through end I (W/m²).
switch lower(bc.type)
    case 'neumann'
        flow = evaluate(bc.flux, t);
    case 'robin'
        flow = bc.h * (evaluate(bc.Tinf, t) - T(i));
    otherwise
        % Fixed temperature: the flux into the first interior node (the
        % end half cell is added in the step).
        flow = k * (T(i) - T(inner)) / dx;
end
end

function value = evaluate(v, t)
if isa(v, 'function_handle')
    value = v(t);
else
    value = v;
end
end

function s = boundaryScale(bc)
switch lower(bc.type)
    case 'dirichlet'
        s = abs(evaluate(bc.T, 0));
    case 'robin'
        s = abs(evaluate(bc.Tinf, 0));
    otherwise
        s = 0;
end
end

function T = initialTemperature(p, x)
ic = p.initial;
L = p.L;
base = ic.T0 * ones(size(x));
if strcmpi(p.left.type, 'dirichlet') && strcmpi(p.right.type, 'dirichlet') && strcmpi(ic.type, 'sine')
    % On top of the straight line between the two end temperatures.
    TL = evaluate(p.left.T, 0);
    TR = evaluate(p.right.T, 0);
    base = TL + (TR - TL) * x / L;
end
switch lower(ic.type)
    case 'uniform'
        T = base;
    case 'step'
        T = base + ic.amplitude * (x < ic.position * L);
    case 'sine'
        T = base + ic.amplitude * sin(ic.mode * pi * x / L);
    case 'hotspot'
        T = base + ic.amplitude * exp(-((x - ic.position * L) / (ic.width * L)).^2);
    otherwise
        error('heat:InvalidParameter', 'Unknown initial condition "%s".', ic.type);
end
end

function exact = exactSolution(p, x, t, alpha)
% Fixed constant end temperatures, no source, sine start: the sine decays
% as exp(−α (nπ/L)² t) on top of the straight-line steady state.
exact = [];
if ~(strcmpi(p.left.type, 'dirichlet') && strcmpi(p.right.type, 'dirichlet') ...
        && strcmpi(p.initial.type, 'sine') && p.q == 0 ...
        && ~isa(p.left.T, 'function_handle') && ~isa(p.right.T, 'function_handle'))
    return
end
lambda = alpha * (p.initial.mode * pi / p.L)^2;
steady = p.left.T + (p.right.T - p.left.T) * x' / p.L;
exact = steady + exp(-lambda * t) * (p.initial.amplitude * sin(p.initial.mode * pi * x' / p.L));
end

function validate(p)
positive = {'L', 'k', 'rho', 'c', 'dt', 'tspan', 'dtOut'};
for k = 1:numel(positive)
    v = p.(positive{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        error('heat:InvalidParameter', '%s must be a positive number.', positive{k});
    end
end
if ~(isscalar(p.N) && p.N >= 3 && p.N == round(p.N))
    error('heat:InvalidParameter', 'The rod needs at least 3 nodes.');
end
if ~any(strcmpi(p.scheme, {'explicit', 'implicit', 'cranknicolson'}))
    error('heat:InvalidParameter', 'Unknown scheme "%s".', p.scheme);
end
if p.dt > p.tspan
    error('heat:InvalidParameter', 'The time step must not exceed the duration.');
end
sides = {p.left, p.right};
for k = 1:2
    if ~any(strcmpi(sides{k}.type, {'dirichlet', 'neumann', 'robin'}))
        error('heat:InvalidParameter', 'Unknown boundary type "%s".', sides{k}.type);
    end
    if strcmpi(sides{k}.type, 'robin') && ~(sides{k}.h > 0)
        error('heat:InvalidParameter', 'A convection end needs a positive heat-transfer coefficient.');
    end
end
end
