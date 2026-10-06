function result = frame_engine(model)
%FRAME_ENGINE Linear static analysis of a 2-D frame by the direct
%   stiffness method: Euler–Bernoulli beam-column elements with 3 degrees
%   of freedom per node (u, v, θ).
%
%   model (SI units):
%     nodes         N×2 [x y] (m)
%     elements      M×1 struct: n1, n2, E (Pa), A (m²), I (m⁴),
%                   releaseStart, releaseEnd (logical: a moment hinge at that end)
%     supports      struct array: node, type ('fixed' | 'pin' | 'rollerx' (moves
%                   along x, holds y) | 'rollery' (moves along y, holds x))
%     nodeLoads     K×4 [node Fx Fy M] (N, N·m)
%     elementLoads  struct array: element, kind ('uniform' | 'point'),
%                   direction ('local' | 'global' | 'projected': global per
%                   horizontal length), wx, wy (components: local x/y or
%                   global X/Y; N/m, or N for a point load), a (m from the
%                   start, point loads)
%
%   result: U (3N×1), displacements (N×3), reactions (R×3 [node dof value],
%   dof 1 = Fx, 2 = Fy, 3 = M), endForces (M×6, local [N1 V1 M1 N2 V2 M2],
%   the forces the nodes apply to the element), diagrams (M×1 struct: x,
%   N, V, M along the element (tension and sagging positive), u and v (its
%   local displacements), and points (the deflected shape, global
%   coordinates of the undeformed points plus the displacement)), residual
%   (equilibrium: |ΣF| + |ΣM about the origin| / load scale), indeterminacy
%   (3m + r − 3j − releases, where k hinged ends meeting at an otherwise
%   free node count as k − 1), and maxima (struct: moment, shear, axial,
%   displacement, with the element and position of the moment).
nodes = model.nodes;
nn = size(nodes, 1);
elements = model.elements(:);
ne = numel(elements);
if nn < 2 || ne < 1
    error('frame:InvalidModel', 'The frame needs at least two nodes and one element.');
end
ndof = 3 * nn;
K = zeros(ndof);
F = zeros(ndof, 1);

% Node loads.
for k = 1:size(model.nodeLoads, 1)
    node = checkNode(model.nodeLoads(k, 1), nn, 'A node load');
    F(3 * node - 2:3 * node) = F(3 * node - 2:3 * node) + model.nodeLoads(k, 2:4)';
end

% Element stiffness and the equivalent nodal loads of element loads.
geometry = struct('L', {}, 'c', {}, 's', {}, 'T', {}, 'k', {}, 'f', {}, 'released', {}, 'dofs', {});
loads = model.elementLoads(:);
for e = 1:ne
    el = elements(e);
    n1 = checkNode(el.n1, nn, sprintf('Element %d', e));
    n2 = checkNode(el.n2, nn, sprintf('Element %d', e));
    d = nodes(n2, :) - nodes(n1, :);
    L = norm(d);
    if n1 == n2 || L == 0
        error('frame:InvalidModel', 'Element %d has zero length.', e);
    end
    if ~(el.E > 0 && el.A > 0 && el.I > 0)
        error('frame:InvalidModel', 'Element %d: E, A, and I must be positive.', e);
    end
    c = d(1) / L;
    s = d(2) / L;
    R = [c s 0; -s c 0; 0 0 1];
    T = blkdiag(R, R);
    k = localStiffness(el.E, el.A, el.I, L);
    f = zeros(6, 1);                                 % equivalent nodal loads (local)
    for j = 1:numel(loads)
        if loads(j).element == e
            f = f + fixedEndLoads(loads(j), L, c, s);
        elseif loads(j).element < 1 || loads(j).element > ne
            error('frame:InvalidModel', 'An element load names element %d, which does not exist.', loads(j).element);
        end
    end
    released = [3 * logical(el.releaseStart), 6 * logical(el.releaseEnd)];
    released = released(released > 0);
    [kc, fc] = condense(k, f, released);
    dofs = [3 * n1 - 2:3 * n1, 3 * n2 - 2:3 * n2];
    K(dofs, dofs) = K(dofs, dofs) + T' * kc * T;
    F(dofs) = F(dofs) + T' * fc;
    geometry(e) = struct('L', L, 'c', c, 's', s, 'T', T, 'k', k, 'f', f, 'released', released, 'dofs', dofs);
end

% Supports.
fixed = false(ndof, 1);
supports = model.supports(:);
for k = 1:numel(supports)
    node = checkNode(supports(k).node, nn, 'A support');
    switch lower(char(supports(k).type))
        case 'fixed'
            held = [1 2 3];
        case 'pin'
            held = [1 2];
        case 'rollerx'
            held = 2;
        case 'rollery'
            held = 1;
        otherwise
            error('frame:InvalidModel', 'Unknown support type "%s".', supports(k).type);
    end
    fixed(3 * node - 3 + held) = true;
end
% A node whose every connected element end is hinged has no rotational
% stiffness; its rotation is irrelevant, so hold it (no load can act on it).
loose = ~fixed & abs(diag(K)) == 0;
if any(abs(F(loose)) > 0)
    k = find(loose & abs(F) > 0, 1);
    error('frame:Mechanism', 'A moment acts at node %s, where every element end is hinged.', nodeName(ceil(k / 3)));
end
holdOnly = loose;
free = ~fixed & ~holdOnly;

% Solve, after checking for a mechanism on the scaled matrix.
Kff = K(free, free);
scale = 1 ./ sqrt(abs(diag(Kff)));
scale(~isfinite(scale)) = 1;
scaled = scale .* Kff .* scale';
if isempty(Kff)
    error('frame:Mechanism', 'Every degree of freedom is held: nothing to solve.');
end
if rcond(scaled) < 1e-12
    [V, D] = eig((scaled + scaled') / 2);
    [~, smallest] = min(abs(diag(D)));
    mode = zeros(ndof, 1);
    mode(free) = scale .* V(:, smallest);
    translation = mode;
    translation(3:3:end) = 0;
    if max(abs(translation)) > 1e-6 * max(abs(mode))
        [~, k] = max(abs(translation));
    else
        [~, k] = max(abs(mode));
    end
    names = {'x', 'y', 'rotation'};
    error('frame:Mechanism', ...
        'The frame is a mechanism: node %s can move in %s. Add a support or a member.', ...
        nodeName(ceil(k / 3)), names{k - 3 * (ceil(k / 3) - 1)});
end
U = zeros(ndof, 1);
U(free) = Kff \ F(free);
reactionAll = K * U - F;

result.U = U;
result.displacements = reshape(U, 3, nn)';
rows = find(fixed);
result.reactions = [ceil(rows / 3), rows - 3 * (ceil(rows / 3) - 1), reactionAll(rows)];

% Element end forces and diagrams.
endForces = zeros(ne, 6);
diagrams = struct('x', {}, 'N', {}, 'V', {}, 'M', {}, 'u', {}, 'v', {}, 'points', {});
for e = 1:ne
    g = geometry(e);
    el = elements(e);
    u = g.T * U(g.dofs);
    if ~isempty(g.released)
        % Recover the hinged ends' own rotations (the moment there is zero).
        keep = setdiff(1:6, g.released);
        u(g.released) = g.k(g.released, g.released) \ (g.f(g.released) - g.k(g.released, keep) * u(keep));
    end
    endForces(e, :) = (g.k * u - g.f)';
    diagrams(e) = memberDiagram(endForces(e, :), u, loads([loads.element] == e), g, el, nodes(el.n1, :));
end
result.endForces = endForces;
result.diagrams = diagrams;

% Equilibrium check: applied loads (as equivalent nodal loads) plus reactions.
applied = F;
total = applied + accumulate(result.reactions, ndof);
resultant = [sum(total(1:3:end)), sum(total(2:3:end))];
moment = sum(total(3:3:end)) + sum(nodes(:, 1) .* total(2:3:end) - nodes(:, 2) .* total(1:3:end));
span = max(max(nodes, [], 1) - min(nodes, [], 1));
loadScale = max([norm(applied(1:3:end)) + norm(applied(2:3:end)), norm(applied(3:3:end)) / max(span, eps), ...
    realmin]);
result.residual = (norm(resultant) + abs(moment) / max(span, eps)) / loadScale;
releases = sum(arrayfun(@(g) numel(g.released), geometry));
% At a node where every element end is hinged, k hinges release only k − 1
% moments: the node's own moment equation is then trivial (holdOnly).
pinnedNodes = nnz(holdOnly(3:3:end));
result.indeterminacy = 3 * ne + nnz(fixed) - 3 * nn - releases + pinnedNodes;
result.maxima = maxima(diagrams);
end

% --------------------------------------------------------------- elements
function k = localStiffness(E, A, I, L)
a = E * A / L;
b = 12 * E * I / L^3;
c = 6 * E * I / L^2;
d = 4 * E * I / L;
h = 2 * E * I / L;
k = [ a  0  0 -a  0  0
      0  b  c  0 -b  c
      0  c  d  0 -c  h
     -a  0  0  a  0  0
      0 -b -c  0  b -c
      0  c  h  0 -c  d];
end

function f = fixedEndLoads(load, L, c, s)
% Equivalent nodal loads (local) of one element load: the negative of the
% fixed-end forces.
[qx, qy] = localComponents(load, c, s);
switch lower(char(load.kind))
    case 'uniform'
        f = [qx * L / 2; qy * L / 2; qy * L^2 / 12; qx * L / 2; qy * L / 2; -qy * L^2 / 12];
    case 'point'
        a = load.a;
        if ~(a >= 0 && a <= L)
            error('frame:InvalidModel', 'A point load on element %d is %.4g m along an element %.4g m long.', ...
                load.element, a, L);
        end
        b = L - a;
        f = [qx * b / L
             qy * b^2 * (3 * a + b) / L^3
             qy * a * b^2 / L^2
             qx * a / L
             qy * a^2 * (a + 3 * b) / L^3
             -qy * a^2 * b / L^2];
    otherwise
        error('frame:InvalidModel', 'Unknown element load kind "%s".', load.kind);
end
end

function [qx, qy] = localComponents(load, c, s)
% Load components along and across the element.
switch lower(char(load.direction))
    case 'local'
        qx = load.wx;
        qy = load.wy;
    case {'global', 'projected'}
        wx = load.wx;
        wy = load.wy;
        if strcmpi(load.direction, 'projected') && strcmpi(load.kind, 'uniform')
            % Per unit of horizontal (wy) or vertical (wx) projection.
            wx = wx * abs(s);
            wy = wy * abs(c);
        end
        qx = c * wx + s * wy;
        qy = -s * wx + c * wy;
    otherwise
        error('frame:InvalidModel', 'Unknown load direction "%s".', load.direction);
end
end

function [kc, fc] = condense(k, f, released)
% Static condensation of hinged rotations (their moments are zero).
kc = k;
fc = f;
if isempty(released)
    return
end
keep = setdiff(1:6, released);
kr = k(released, released);
kc = zeros(6);
kc(keep, keep) = k(keep, keep) - k(keep, released) * (kr \ k(released, keep));
fc = zeros(6, 1);
fc(keep) = f(keep) - k(keep, released) * (kr \ f(released));
end

% ---------------------------------------------------------------- diagrams
function d = memberDiagram(ends, u, loads, g, el, start)
% N, V, M and the deflected shape along one element, exact for uniform and
% point loads (the particular solution of the fixed-end beam is added to
% the Hermite interpolation of the end displacements). 101 points, plus
% the zero-shear points where a uniform load's moment peaks, so that the
% maxima are exact for M and within 10⁻⁵ for the deflection (21 points
% missed a propped cantilever's deflection peak by 0.3 %).
L = g.L;
points = linspace(0, L, 101);
for j = 1:numel(loads)
    if strcmpi(loads(j).kind, 'point')
        points = [points, loads(j).a, loads(j).a]; %#ok<AGROW>
    end
end
% Where the shear passes through zero under a uniform load the moment
% peaks: sample it exactly (V = V1 + q x + the point loads already passed).
q = 0;
jumps = zeros(0, 2);                                % [a P]
for j = 1:numel(loads)
    [~, qy] = localComponents(loads(j), g.c, g.s);
    if strcmpi(loads(j).kind, 'uniform')
        q = q + qy;
    else
        jumps(end+1, :) = [loads(j).a, qy]; %#ok<AGROW>
    end
end
if q ~= 0
    edges = unique([0; jumps(:, 1); L]);
    for k = 1:numel(edges) - 1
        passed = sum(jumps(jumps(:, 1) <= edges(k), 2));
        x0 = -(ends(2) + passed) / q;
        if x0 > edges(k) && x0 < edges(k + 1) && min(abs(points - x0)) > 1e-9 * L
            points(end+1) = x0; %#ok<AGROW>
        end
    end
end
x = sort(points(:));
N = -ends(1) * ones(size(x));
V = ends(2) * ones(size(x));
M = -ends(3) + ends(2) * x;
xi = x / L;
v = (1 - 3 * xi.^2 + 2 * xi.^3) * u(2) + L * (xi - 2 * xi.^2 + xi.^3) * u(3) ...
    + (3 * xi.^2 - 2 * xi.^3) * u(5) + L * (-xi.^2 + xi.^3) * u(6);
w = (1 - xi) * u(1) + xi * u(4);
EI = el.E * el.I;
EA = el.E * el.A;
for j = 1:numel(loads)
    [qx, qy] = localComponents(loads(j), g.c, g.s);
    if strcmpi(loads(j).kind, 'uniform')
        N = N - qx * x;
        V = V + qy * x;
        M = M + qy * x.^2 / 2;
        v = v + qy * x.^2 .* (L - x).^2 / (24 * EI);
        w = w + qx * x .* (L - x) / (2 * EA);
    else
        a = loads(j).a;
        b = L - a;
        % The last sample at x = a (it is listed twice) takes the value
        % just after the load, so the diagram shows the jump.
        after = x > a;
        at = find(x == a);
        if numel(at) >= 2
            after(at(end)) = true;
        end
        N(after) = N(after) - qx;
        V(after) = V(after) + qy;
        M = M + qy * max(x - a, 0);
        left = x <= a;
        v(left) = v(left) + qy * b^2 * x(left).^2 .* (3 * a * L - (3 * a + b) * x(left)) / (6 * EI * L^3);
        r = L - x(~left);
        v(~left) = v(~left) + qy * a^2 * r.^2 .* (3 * b * L - (3 * b + a) * r) / (6 * EI * L^3);
        w(left) = w(left) + qx * b * x(left) / (EA * L);
        w(~left) = w(~left) + qx * a * (L - x(~left)) / (EA * L);
    end
end
along = [g.c g.s];
across = [-g.s g.c];
d.x = x;
d.N = N;
d.V = V;
d.M = M;
d.u = w;
d.v = v;
d.points = start + x * along;
d.points = [d.points, w .* along(1) + v .* across(1), w .* along(2) + v .* across(2)];
end

function m = maxima(diagrams)
m = struct('moment', 0, 'momentElement', 0, 'momentX', 0, 'shear', 0, 'axial', 0, 'displacement', 0);
for e = 1:numel(diagrams)
    d = diagrams(e);
    [value, k] = max(abs(d.M));
    if value > abs(m.moment)
        m.moment = d.M(k);
        m.momentElement = e;
        m.momentX = d.x(k);
    end
    m.shear = max(m.shear, max(abs(d.V)));
    m.axial = max(m.axial, max(abs(d.N)));
    m.displacement = max(m.displacement, max(hypot(d.points(:, 3), d.points(:, 4))));
end
end

% ----------------------------------------------------------------- helpers
function node = checkNode(node, nn, what)
if ~(node >= 1 && node <= nn && node == round(node))
    error('frame:InvalidModel', '%s refers to node %g, which does not exist.', what, node);
end
end

function name = nodeName(k)
name = char('A' + mod(k - 1, 26));
if k > 26
    name = sprintf('%s%d', name, floor((k - 1) / 26));
end
end

function R = accumulate(reactions, ndof)
R = zeros(ndof, 1);
for k = 1:size(reactions, 1)
    R(3 * reactions(k, 1) - 3 + reactions(k, 2)) = reactions(k, 3);
end
end
