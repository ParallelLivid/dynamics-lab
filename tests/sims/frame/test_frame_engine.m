function tests = test_frame_engine
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function m = beam(L, n, supports)
% A straight beam of N elements along x, E = 200 GPa, A = 1e-2 m², I = 1e-4 m⁴.
x = linspace(0, L, n + 1)';
m.nodes = [x, zeros(n + 1, 1)];
m.elements = struct('n1', num2cell(1:n)', 'n2', num2cell(2:n + 1)', 'E', 200e9, 'A', 1e-2, 'I', 1e-4, ...
    'releaseStart', false, 'releaseEnd', false);
m.supports = supports;
m.nodeLoads = zeros(0, 4);
m.elementLoads = struct('element', {}, 'kind', {}, 'direction', {}, 'wx', {}, 'wy', {}, 'a', {});
end

function s = support(node, type)
s = struct('node', node, 'type', type);
end

function loads = udl(elements, w)
loads = struct('element', num2cell(elements(:))', 'kind', 'uniform', 'direction', 'global', 'wx', 0, ...
    'wy', -w, 'a', 0);
end

function testCantilever(testCase)
[L, P, EI] = deal(4, 10e3, 200e9 * 1e-4);
m = beam(L, 1, support(1, 'fixed'));
m.nodeLoads = [2 0 -P 0];
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.displacements(2, 2), -P * L^3 / (3 * EI), 'RelTol', 1e-10);
verifyEqual(testCase, r.displacements(2, 3), -P * L^2 / (2 * EI), 'RelTol', 1e-10);
verifyEqual(testCase, r.diagrams(1).M(1), -P * L, 'RelTol', 1e-10, 'Hogging root moment PL.');
verifyLessThan(testCase, r.residual, 1e-9);
verifyEqual(testCase, r.indeterminacy, 0);
end

function testSimplySupportedUdl(testCase)
[L, w, EI] = deal(6, 5e3, 200e9 * 1e-4);
m = beam(L, 1, [support(1, 'pin'), support(2, 'rollerx')]);
m.elementLoads = udl(1, w);
r = dlab.sims.frame.frame_engine(m);
d = r.diagrams(1);
middle = abs(d.x - L / 2) < 1e-12;
verifyEqual(testCase, d.M(middle), w * L^2 / 8, 'RelTol', 1e-10);
verifyEqual(testCase, d.v(middle), -5 * w * L^4 / (384 * EI), 'RelTol', 1e-10, 'Exact mid-span deflection.');
verifyEqual(testCase, r.maxima.moment, w * L^2 / 8, 'RelTol', 1e-10);
end

function testFixedFixedUdl(testCase)
[L, w, EI] = deal(6, 5e3, 200e9 * 1e-4);
m = beam(L, 2, [support(1, 'fixed'), support(3, 'fixed')]);
m.elementLoads = udl(1:2, w);
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.diagrams(1).M(1), -w * L^2 / 12, 'RelTol', 1e-10);
verifyEqual(testCase, r.diagrams(1).M(end), w * L^2 / 24, 'RelTol', 1e-10);
verifyEqual(testCase, r.displacements(2, 2), -w * L^4 / (384 * EI), 'RelTol', 1e-10);
verifyEqual(testCase, r.indeterminacy, 3);
end

function testProppedCantilever(testCase)
[L, w] = deal(5, 4e3);
m = beam(L, 1, [support(1, 'fixed'), support(2, 'rollerx')]);
m.elementLoads = udl(1, w);
r = dlab.sims.frame.frame_engine(m);
prop = r.reactions(r.reactions(:, 1) == 2 & r.reactions(:, 2) == 2, 3);
verifyEqual(testCase, prop, 3 * w * L / 8, 'RelTol', 1e-10);
end

function testContinuousBeam(testCase)
[L, w] = deal(4, 3e3);
m = beam(2 * L, 2, [support(1, 'pin'), support(2, 'rollerx'), support(3, 'rollerx')]);
m.elementLoads = udl(1:2, w);
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.diagrams(1).M(end), -w * L^2 / 8, 'RelTol', 1e-10);
end

function testPointLoadAndHinge(testCase)
% A point load at a third of the span; and a hinge in a fixed-fixed beam,
% where the moment must vanish.
[L, P] = deal(6, 9e3);
m = beam(L, 1, [support(1, 'pin'), support(2, 'rollerx')]);
m.elementLoads = struct('element', 1, 'kind', 'point', 'direction', 'local', 'wx', 0, 'wy', -P, 'a', L / 3);
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.maxima.moment, P * (L / 3) * (2 * L / 3) / L, 'RelTol', 1e-10);
d = r.diagrams(1);
at = find(d.x == L / 3);
verifyEqual(testCase, d.V(at(end)) - d.V(at(1)), -P, 'RelTol', 1e-10, 'The shear jumps by P.');
% Fixed–fixed with a hinge in the middle (two cantilevers meeting at a pin).
m = beam(L, 2, [support(1, 'fixed'), support(3, 'fixed')]);
m.elements(1).releaseEnd = true;
m.elementLoads = udl(1:2, 2e3);
r = dlab.sims.frame.frame_engine(m);
verifyLessThan(testCase, abs(r.diagrams(1).M(end)), 1e-6);
verifyEqual(testCase, r.indeterminacy, 2);
verifyLessThan(testCase, r.residual, 1e-9);
end

function testPortalFrame(testCase)
% Fixed-base portal, lateral load H at the beam level, equal EI and length
% (h = L), members nearly inextensible (A huge). Slope-deflection with
% k = (I_b/L)/(I_c/h) = 1 gives antisymmetric moments:
%   base  M = H h (3k + 1) / (2 (6k + 1)) = 2 H h / 7
%   top   M = H h 3k / (2 (6k + 1))       = 3 H h / 14
[h, H] = deal(4, 10e3);
m.nodes = [0 0; 0 h; h h; h 0];
m.elements = struct('n1', {1, 2, 3}, 'n2', {2, 3, 4}, 'E', 200e9, 'A', 1e3, 'I', 1e-4, ...
    'releaseStart', false, 'releaseEnd', false);
m.supports = [support(1, 'fixed'), support(4, 'fixed')];
m.nodeLoads = [2 H 0 0];
m.elementLoads = struct('element', {}, 'kind', {}, 'direction', {}, 'wx', {}, 'wy', {}, 'a', {});
r = dlab.sims.frame.frame_engine(m);
base = r.reactions(r.reactions(:, 2) == 3, 3);
verifyEqual(testCase, abs(base), [2; 2] * H * h / 7, 'RelTol', 1e-6);
verifyEqual(testCase, abs(r.diagrams(1).M(end)), 3 * H * h / 14, 'RelTol', 1e-6);
verifyLessThan(testCase, r.residual, 1e-7, 'Looser: the huge A makes K ill-conditioned.');
end

function testMechanismIsNamed(testCase)
m = beam(4, 1, support(1, 'pin'));
m.nodeLoads = [2 0 -1e3 0];
verifyError(testCase, @() dlab.sims.frame.frame_engine(m), 'frame:Mechanism');
try
    dlab.sims.frame.frame_engine(m);
catch err
    verifyFalse(testCase, isempty(strfind(err.message, 'node B')), err.message);
end
end

function testThreeHingedFrameIsDeterminate(testCase)
% Both rafters hinged at the apex: one pin there (two hinged ends release
% one moment), so a three-hinged portal is statically determinate.
m.nodes = [0 0; 0 4; 3 5; 6 4; 6 0];
m.elements = struct('n1', {1, 2, 3, 4}, 'n2', {2, 3, 4, 5}, 'E', 200e9, 'A', 1e-2, 'I', 1e-4, ...
    'releaseStart', {false, false, true, false}, 'releaseEnd', {false, true, false, false});
m.supports = [support(1, 'pin'), support(5, 'pin')];
m.nodeLoads = [2 1e3 0 0];
m.elementLoads = struct('element', {}, 'kind', {}, 'direction', {}, 'wx', {}, 'wy', {}, 'a', {});
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.indeterminacy, 0);
verifyLessThan(testCase, max(abs([r.diagrams(2).M(end), r.diagrams(3).M(1)])), 1e-6);
% Hinged at both ends of every member, the frame is a truss: m + r − 2j.
m.nodes = [0 0; 4 0; 2 3];
m.elements = struct('n1', {1, 2, 3}, 'n2', {2, 3, 1}, 'E', 200e9, 'A', 1e-2, 'I', 1e-4, ...
    'releaseStart', true, 'releaseEnd', true);
m.supports = [support(1, 'pin'), support(2, 'rollerx')];
m.nodeLoads = [3 0 -1e3 0];
r = dlab.sims.frame.frame_engine(m);
verifyEqual(testCase, r.indeterminacy, 3 + 3 - 2 * 3);
end

function testProppedCantileverPeakDeflection(testCase)
% Independent reference: the handbook deflection of a propped cantilever.
% w L⁴/EI × 0.0054161 at x = 0.4215 L (the peak between nodes): the
% maxima sampled 21 points per element read 0.3 % low.
p = beam(5, 1, [support(1, 'fixed') support(2, 'rollerx')]);
p.elementLoads = udl(1, 4000);                % 4 kN/m downward
r = dlab.sims.frame.frame_engine(p);
EI = p.elements(1).E * p.elements(1).I;
verifyEqual(testCase, r.maxima.displacement, 0.0054161 * 4000 * 5^4 / EI, 'RelTol', 1e-4);
verifyEqual(testCase, max(r.diagrams(1).M), 9 * 4000 * 5^2 / 128, 'RelTol', 1e-4, ...
    'The sagging peak 9wL²/128 at 5L/8.');
end
