function result = simulateWave(p)
%SIMULATEWAVE Vibrating string or Euler–Bernoulli beam, by modes.
%   result = simulateWave(p) discretizes the medium into finite elements
%   (linear elements for a string, Hermite elements with deflection and
%   slope for a beam), finds its natural modes from eig(K, M), and adds
%   them up exactly in time, each decaying with damping ratio zeta.
%
%     medium         'string' (ρ u_tt = T u_xx) or 'beam' (ρA u_tt = −EI u_xxxx)
%     L, elements    length (m) and number of elements
%     tension, rho   string: tension (N) and mass per length (kg/m)
%     EI, rhoA       beam: bending stiffness (N·m²) and mass per length
%     bc             string: 'fixedfixed' | 'fixedfree';
%                    beam: 'pinned' | 'cantilever' | 'clamped' | 'free'
%                    (a free bar's rigid-body motion is left out)
%     initial        'pluck' | 'strike' | 'mode' | 'gaussian'
%     height         displacement amplitude (m), or the strike speed (m/s)
%     position, width  where (× L) and how wide (× L) the shape is
%     mode           mode number for 'mode'
%     zeta           modal damping ratio (all modes)
%     tspan, dtOut   duration and output step (s)
%     probe          probe position (× L)
%
%   result: t, x (nodes), U (numel(t) × nodes), frequencies (Hz, the
%   flexible modes in order), shapes (nodes × modes, deflection), modal
%   energy at the start (per mode), KE, PE, E over time, probe (u at the
%   probe), rigid (number of rigid-body modes), and c (string wave speed).
validate(p);
n = p.elements;
L = p.L;
h = L / n;
x = (0:n)' * h;
isBeam = strcmpi(p.medium, 'beam');
if isBeam
    [K, M] = beamMatrices(n, h, p.EI, p.rhoA);
    perNode = 2;
else
    [K, M] = stringMatrices(n, h, p.tension, p.rho);
    perNode = 1;
end
free = freeDofs(p, n, perNode);
Kf = full(K(free, free));
Mf = full(M(free, free));
Kf = (Kf + Kf') / 2;
Mf = (Mf + Mf') / 2;
[Phi, Lambda] = eig(Kf, Mf);
omega2 = max(diag(Lambda), 0);
[omega2, order] = sort(omega2);
Phi = Phi(:, order);
Phi = Phi ./ sqrt(sum(Phi .* (Mf * Phi), 1));          % mass-normalized
% Only a free bar has rigid-body modes: two (drift and spin), the lowest.
% They are counted from the supports, not by a threshold on ω, which would
% also catch the lowest flexible modes on fine meshes (ω_max grows like n²).
rigid = false(size(omega2));
if strcmpi(p.bc, 'free')
    rigid(1:min(2, end)) = true;
    omega2(rigid) = 0;
end
omega = sqrt(omega2);

% Deflection degrees of freedom (one per node), in the free set.
deflection = (1:perNode:perNode * (n + 1))';
full2free = zeros(perNode * (n + 1), 1);
full2free(free) = 1:numel(free);
W = zeros(n + 1, numel(omega));
inFree = full2free(deflection) > 0;
W(inFree, :) = Phi(full2free(deflection(inFree)), :);

% Initial deflection and velocity on every degree of freedom (a beam's
% slopes from the shapes' exact derivatives).
[u0, v0, slope0, vslope0] = initialShape(p, x, W, omega, rigid);
d0 = zeros(perNode * (n + 1), 1);
dv0 = zeros(perNode * (n + 1), 1);
d0(deflection) = u0;
dv0(deflection) = v0;
if isBeam
    d0(deflection + 1) = slope0;
    dv0(deflection + 1) = vslope0;
end
if isBeam && strcmpi(p.initial, 'pluck')
    % A beam is plucked by pushing it at one point and letting go, so it
    % starts from its static deflection under that point load. (A string's
    % triangle has a kink, which a beam cannot hold: its bending energy grew
    % with the number of elements.)
    d0(:) = 0;
    d0(free) = pluckedBeam(p, n, h, free, Phi, omega2, rigid);
end
if strcmpi(p.initial, 'mode')
    % The mode's own shape on every degree of freedom (a beam's slopes
    % included), so the start excites that mode alone.
    k = chosenMode(p, rigid);
    d0(:) = 0;
    d0(free) = Phi(:, k) * (p.height / max(abs(W(:, k))));
end
q0 = Phi' * (Mf * d0(free));
qd0 = Phi' * (Mf * dv0(free));
if strcmpi(p.bc, 'free')
    % A free bar resting on soft supports: keep the vibration, drop the
    % drift and spin of the whole bar.
    q0(rigid) = 0;
    qd0(rigid) = 0;
end

t = (0:p.dtOut:p.tspan)';
if t(end) < p.tspan
    t(end + 1) = p.tspan;
end
if numel(t) * (n + 1) > 4e6
    error('wave:TooMuchOutput', ...
        'This run would store %d values; increase the output step or use fewer elements.', numel(t) * (n + 1));
end
[Q, Qd] = modalHistory(q0, qd0, omega, rigid, p.zeta, t');
result.t = t;
result.x = x;
result.U = (W * Q)';
result.KE = 0.5 * sum(Qd.^2, 1)';
result.PE = 0.5 * sum(omega2 .* Q.^2, 1)';
result.E = result.KE + result.PE;
result.frequencies = omega(~rigid) / (2 * pi);
result.shapes = W(:, ~rigid);
energy = 0.5 * (omega2 .* q0.^2 + qd0.^2);
result.modalEnergy = energy(~rigid);
result.rigid = nnz(rigid);
result.probe = interp1(x, result.U', p.probe * L)';
result.probe = result.probe(:);
result.c = NaN;
if ~isBeam
    result.c = sqrt(p.tension / p.rho);
end
end

% --------------------------------------------------------------- elements
function [K, M] = stringMatrices(n, h, tension, rho)
% Linear elements; the mass is the average of the consistent and lumped
% matrices, which makes the frequencies fourth-order accurate.
ke = tension / h * [1 -1; -1 1];
me = rho * h * [5 1; 1 5] / 12;
[K, M] = assemble(n, ke, me, 1);
end

function [K, M] = beamMatrices(n, h, EI, rhoA)
% Hermite cubic elements: deflection and slope at each node.
ke = EI / h^3 * [12 6*h -12 6*h; 6*h 4*h^2 -6*h 2*h^2; -12 -6*h 12 -6*h; 6*h 2*h^2 -6*h 4*h^2];
me = rhoA * h / 420 * [156 22*h 54 -13*h; 22*h 4*h^2 13*h -3*h^2; 54 13*h 156 -22*h; -13*h -3*h^2 -22*h 4*h^2];
[K, M] = assemble(n, ke, me, 2);
end

function [K, M] = assemble(n, ke, me, perNode)
dofs = perNode * (n + 1);
size2 = numel(ke);
rows = zeros(n * size2, 1);
cols = rows;
kv = rows;
mv = rows;
for e = 1:n
    idx = perNode * (e - 1) + (1:2 * perNode);
    [cc, rr] = meshgrid(idx, idx);
    span = (e - 1) * size2 + (1:size2);
    rows(span) = rr(:);
    cols(span) = cc(:);
    kv(span) = ke(:);
    mv(span) = me(:);
end
K = sparse(rows, cols, kv, dofs, dofs);
M = sparse(rows, cols, mv, dofs, dofs);
end

function free = freeDofs(p, n, perNode)
% Degrees of freedom left after the supports.
dofs = perNode * (n + 1);
fixed = false(dofs, 1);
first = 1;
last = perNode * n + 1;            % deflection of the last node
switch lower(p.bc)
    case 'fixedfixed'
        fixed([first last]) = true;
    case 'fixedfree'
        fixed(first) = true;
    case 'pinned'
        fixed([first last]) = true;
    case 'cantilever'
        fixed([first first + 1]) = true;
    case 'clamped'
        fixed([first first + 1 last last + 1]) = true;
    case 'free'
        % nothing fixed: two rigid-body modes
end
free = find(~fixed);
end

% ---------------------------------------------------------- initial state
function [u0, v0, slope0, vslope0] = initialShape(p, x, W, omega, rigid)
% Deflection and velocity at the nodes, and their slopes along x (for a
% beam's rotation degrees of freedom).
L = p.L;
a = p.position * L;
u0 = zeros(size(x));
v0 = zeros(size(x));
slope0 = zeros(size(x));
vslope0 = zeros(size(x));
bump = @(x) exp(-((x - a) / (p.width * L)).^2);
bumpSlope = @(x) -2 * (x - a) / (p.width * L)^2 .* bump(x);
switch lower(p.initial)
    case 'pluck'                            % a string's (a beam's: pluckedBeam)
        if any(strcmpi(p.bc, {'fixedfixed', 'pinned', 'clamped'}))
            u0 = p.height * min(x / a, (L - x) / (L - a));
        else
            u0 = p.height * min(x / a, 1);      % the free end follows
        end
    case 'strike'
        v0 = p.height * bump(x);
        vslope0 = p.height * bumpSlope(x);
    case 'gaussian'
        u0 = p.height * bump(x);
        slope0 = p.height * bumpSlope(x);
    case 'mode'
        shape = W(:, chosenMode(p, rigid));
        u0 = p.height * shape / max(abs(shape));
    otherwise
        error('wave:InvalidParameter', 'Unknown initial shape "%s".', p.initial);
end
% Supported points cannot move.
switch lower(p.bc)
    case {'fixedfixed', 'pinned', 'clamped'}
        u0([1 end]) = 0;
        v0([1 end]) = 0;
    case {'fixedfree', 'cantilever'}
        u0(1) = 0;
        v0(1) = 0;
end
if numel(omega) == 0
    error('wave:InvalidParameter', 'No free degrees of freedom.');
end
end

function d = pluckedBeam(p, n, h, free, Phi, omega2, rigid)
% Static deflection (free degrees of freedom) under a point load at the
% pluck position, scaled to p.height there: K⁻¹ F = Φ Ω⁻² Φᵀ F over the
% flexible modes (Φ mass-normalized), which for a free bar is its elastic
% deflection about its rigid-body motion.
a = p.position * p.L;
e = min(floor(a / h) + 1, n);              % the element holding the load
xi = (a - (e - 1) * h) / h;
N = [1 - 3 * xi^2 + 2 * xi^3, h * xi * (1 - xi)^2, 3 * xi^2 - 2 * xi^3, h * (xi^3 - xi^2)];
idx = 2 * (e - 1) + (1:4);
F = zeros(2 * (n + 1), 1);
F(idx) = N;
flexible = ~rigid;
d = Phi(:, flexible) * ((Phi(:, flexible)' * F(free)) ./ omega2(flexible));
everywhere = zeros(2 * (n + 1), 1);
everywhere(free) = d;
d = d * (p.height / (N * everywhere(idx)));      % N·d: the deflection at the load (> 0)
end

function k = chosenMode(p, rigid)
% Index (among all modes) of flexible mode p.mode, or the highest there is.
flexible = find(~rigid);
if isempty(flexible)
    error('wave:InvalidParameter', 'No free degrees of freedom.');
end
k = flexible(min(p.mode, numel(flexible)));
end

function [Q, Qd] = modalHistory(q0, qd0, omega, rigid, zeta, t)
% Each modal coordinate's free response (rows: modes, columns: times).
w = omega;
wd = w * sqrt(max(1 - zeta^2, 0));
decay = exp(-zeta * w * t);
B = (qd0 + zeta * w .* q0) ./ max(wd, eps);
Q = decay .* (q0 .* cos(wd * t) + B .* sin(wd * t));
Qd = decay .* ((-zeta * w .* q0 + wd .* B) .* cos(wd * t) + (-zeta * w .* B - wd .* q0) .* sin(wd * t));
if any(rigid)
    Q(rigid, :) = q0(rigid) + qd0(rigid) * t;
    Qd(rigid, :) = qd0(rigid) * ones(size(t));
end
end

function validate(p)
names = {'L', 'tspan', 'dtOut'};
for k = 1:numel(names)
    v = p.(names{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        error('wave:InvalidParameter', '%s must be a positive number.', names{k});
    end
end
if ~(p.elements >= 2 && p.elements <= 800 && p.elements == round(p.elements))
    error('wave:InvalidParameter', 'Use 2 to 800 elements.');
end
if ~(p.zeta >= 0 && p.zeta < 1)
    error('wave:InvalidParameter', 'The damping ratio must be in [0, 1).');
end
if ~(p.position > 0 && p.position < 1) && any(strcmpi(p.initial, {'pluck'}))
    error('wave:InvalidParameter', 'Pluck somewhere between the ends.');
end
if strcmpi(p.medium, 'beam')
    ok = any(strcmpi(p.bc, {'pinned', 'cantilever', 'clamped', 'free'})) && p.EI > 0 && p.rhoA > 0;
else
    ok = any(strcmpi(p.bc, {'fixedfixed', 'fixedfree'})) && p.tension > 0 && p.rho > 0;
end
if ~ok
    error('wave:InvalidParameter', 'Check the medium, its supports, and its properties.');
end
end
