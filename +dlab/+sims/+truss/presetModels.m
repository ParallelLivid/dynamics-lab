function presets = presetModels()
%PRESETMODELS Named truss models (struct array: Name, Model).
%   Model fields: nodes (N×2, m), members (M×2 node indices, or M×3 with
%   a section index), forces (K×3: node, Fx, Fy in N), supports (S×2:
%   node, type) with type 1 = pin, 2 = roller fixing X, 3 = roller fixing
%   Y, and optionally sections (rows of dlab.physics.sectionLibrary;
%   the default section otherwise).

presets = struct("Name", {}, "Model", {});

% Three-member triangle with one load at the apex.
presets(end+1) = struct("Name", "Simple triangle", "Model", model( ...
    [0 0; 4 0; 2 3.464], [1 2; 2 3; 1 3], [3 0 -20000], [1 1; 2 3]));

presets(end+1) = struct("Name", "Pratt truss (6-panel)", "Model", pratt(6, 1.0, 1.5, -12000));
presets(end+1) = struct("Name", "Warren truss (6-panel)", "Model", warren(6, 1.0, -12000));
presets(end+1) = struct("Name", "Howe truss (6-panel)", "Model", howe(6, 1.0, 1.5, -12000));

% Cantilever fixed by a pin and a horizontal-restraint roller.
presets(end+1) = struct("Name", "Cantilever truss", "Model", model( ...
    [0 0; 0 2; 2 0; 2 2; 4 0; 4 2; 6 0], ...
    [1 2; 1 3; 2 3; 2 4; 3 4; 3 5; 4 5; 4 6; 5 6; 5 7; 6 7], ...
    [7 0 -20000; 5 0 -10000], [1 1; 2 2]));

% Six-node Fink roof truss:      3
%                               /|\
%                              4 | 5
%                             / \|/ \
%                            1---6---2
L = 8;  H = 3;
presets(end+1) = struct("Name", "Roof truss (Fink)", "Model", model( ...
    [0 0; L 0; L/2 H; L/4 H/2; 3*L/4 H/2; L/2 0], ...
    [1 6; 6 2; 1 4; 4 3; 2 5; 5 3; 4 6; 5 6; 3 6], ...
    [3 0 -20000; 4 0 -10000; 5 0 -10000], [1 1; 2 3]));

% Strength checks: sections from dlab.physics.sectionLibrary, a spare
% larger section in each so the failing members can be fixed.
% A 15 m Pratt footbridge in steel tubes: CHS 88.9×4 chords; the 60.3×3.2
% web posts buckle under 40 kN per node, and 76.1×3.2 (S3) would hold.
bridge = pratt(6, 2.5, 2.5, -40000);
web = [false(12, 1); true(13, 1)];
bridge.members(:, 3) = 1 + web;
bridge.sections = [tube(88.9, 4); tube(60.3, 3.2); tube(76.1, 3.2)];
presets(end+1) = struct("Name", "Footbridge check (steel tubes)", "Model", bridge);
% The Fink roof in C24 timber, 75 mm square: its compressed rafters
% buckle under twice the roof load; 100 mm (S2) would hold.
roof = presets(end - 1).Model;
roof.forces = [3 0 -40000; 4 0 -20000; 5 0 -20000];
roof.members(:, 3) = 1;
roof.sections = [square(3, 75); square(3, 100)];
presets(end+1) = struct("Name", "Timber roof check (Fink)", "Model", roof);
end

function s = tube(D, t)
% A steel round tube (outer diameter and wall in mm) as a section row.
lib = dlab.physics.sectionLibrary();
[A, I] = lib.properties(1, D, t);
s = [1 1 lib.E(1) lib.Yield(1) D t A I];
end

function s = square(material, b)
% A solid square section of side b (mm) in the given material.
lib = dlab.physics.sectionLibrary();
[A, I] = lib.properties(4, b, 0);
s = [material 4 lib.E(material) lib.Yield(material) b 0 A I];
end

function m = model(nodes, members, forces, supports)
m = struct("nodes", nodes, "members", members, "forces", forces, "supports", supports);
end

function m = pratt(np, dx, h, P)
% Two node rows with chords and vertical posts; diagonals descend toward midspan.
[nodes, members, off] = postedPanels(np, dx, h);
half = np/2;
for j = 1:half,    members(end+1,:) = [j+1, off+j];   end %#ok<AGROW>
for j = half+1:np, members(end+1,:) = [j,   off+j+1]; end %#ok<AGROW>
m = model(nodes, members, [off + (2:np)', zeros(np-1, 1), P * ones(np-1, 1)], [1 1; np+1 3]);
end

function m = howe(np, dx, h, P)
% As Pratt, but the diagonals ascend toward midspan.
[nodes, members, off] = postedPanels(np, dx, h);
half = np/2;
for j = 1:half,    members(end+1,:) = [j,   off+j+1]; end %#ok<AGROW>
for j = half+1:np, members(end+1,:) = [j+1, off+j];   end %#ok<AGROW>
m = model(nodes, members, [off + (2:np)', zeros(np-1, 1), P * ones(np-1, 1)], [1 1; np+1 3]);
end

function [nodes, members, off] = postedPanels(np, dx, h)
nodes = [(0:np)' * dx, zeros(np+1, 1); (0:np)' * dx, h * ones(np+1, 1)];
off = np + 1;
members = [(1:np)', (2:np+1)'                % bottom chord
           off + (1:np)', off + (2:np+1)'    % top chord
           (1:np+1)', off + (1:np+1)'];      % posts
end

function m = warren(np, dx, P)
% Top nodes sit between bottom-chord panel points.
h = dx * sqrt(3)/2;
nodes = [(0:np)' * dx, zeros(np+1, 1); ((0:np-1)' + 0.5) * dx, h * ones(np, 1)];
BN = np + 1;
members = [(1:np)', (2:np+1)'];
for j = 1:np
    members(end+1,:) = [j,   BN+j]; %#ok<AGROW>
    members(end+1,:) = [j+1, BN+j]; %#ok<AGROW>
end
members = [members; BN + (1:np-1)', BN + (2:np)'];
m = model(nodes, members, [(2:np)', zeros(np-1, 1), P * ones(np-1, 1)], [1 1; np+1 3]);
end
