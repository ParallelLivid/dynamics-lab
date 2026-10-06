function tests = test_truss_engine
%TEST_TRUSS_ENGINE Regression tests for the numerical solver.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function testSingleBar(testCase)
model = base_model();
model.nodes = [0 0; 2 0];
model.members = [1 2];
model.forces = [2 1000 0];
model.supports = [1 1; 2 3];

result = dlab.sims.truss.truss_engine(model);

verifyTrue(testCase, result.success, char(result.error));
verifyEqual(testCase, result.memberForces, 1000, 'AbsTol', 1e-8);
verifyEqual(testCase, result.U(3), 1e-6, 'AbsTol', 1e-12);
verifyEqual(testCase, sum(result.reactions(:,3)), -1000, 'AbsTol', 1e-8);
end

function testTriangleEquilibrium(testCase)
model = base_model();
model.nodes = [0 0; 4 0; 2 3.464];
model.members = [1 2; 2 3; 1 3];
model.forces = [3 0 -20000];
model.supports = [1 1; 2 3];

result = dlab.sims.truss.truss_engine(model);

verifyTrue(testCase, result.success, char(result.error));
verifyEqual(testCase, result.memberForces(1), 5773.7, 'RelTol', 1e-4);
verifyEqual(testCase, result.memberForces(2:3), [-11547.1; -11547.1], 'RelTol', 1e-4);
horizontalReaction = sum(result.reactions(result.reactions(:,2)==1,3));
verticalReaction = sum(result.reactions(result.reactions(:,2)==2,3));
verifyEqual(testCase, horizontalReaction, 0, 'AbsTol', 1e-7);
verifyEqual(testCase, verticalReaction, 20000, 'AbsTol', 1e-7);
end

function testMechanismIsRejected(testCase)
model = base_model();
model.nodes = [0 0; 1 0; 2 0];
model.members = [1 2; 2 3];
model.forces = [3 0 -1];
model.supports = [1 1; 3 3];

result = dlab.sims.truss.truss_engine(model);

verifyFalse(testCase, result.success);
verifyThat(testCase, result.error, matlab.unittest.constraints.ContainsSubstring("Singular"));
end

function testZeroLengthMemberIsRejected(testCase)
model = base_model();
model.nodes = [0 0; 0 0];
model.members = [1 2];
model.supports = [1 1];

result = dlab.sims.truss.truss_engine(model);

verifyFalse(testCase, result.success);
verifyThat(testCase, result.error, matlab.unittest.constraints.ContainsSubstring("Zero-length"));
end

function testUnsupportedUnknownForceIsRejected(testCase)
model = base_model();
model.nodes = [0 0; 1 0];
model.members = [1 2];
model.supports = [1 1; 2 3];
model.unknownForces = [2 1];

result = dlab.sims.truss.truss_engine(model);

verifyFalse(testCase, result.success);
verifyThat(testCase, result.error, matlab.unittest.constraints.ContainsSubstring("prescribed displacement"));
end

function testOverflowIsRejected(testCase)
model = base_model();
model.nodes = [0 0; 2 0];
model.members = [1 2];
model.supports = [1 1; 2 3];
model.forces = [2 1e308 0; 2 1e308 0];
verify_numerical_failure(testCase, dlab.sims.truss.truss_engine(model));

model.forces = [2 1000 0];
model.E = realmax;
model.A = 2;
verify_numerical_failure(testCase, dlab.sims.truss.truss_engine(model));

model.E = 1e-200;
model.A = 1;
model.forces = [2 1e200 0];
verify_numerical_failure(testCase, dlab.sims.truss.truss_engine(model));
end

function testStrengthCheckYieldAndBuckling(testCase)
% Independent reference: the member forces by the method of joints.
% A two-bar frame: one bar in tension, one in compression. Stress N/A
% against the yield stress; compression against Euler's pi^2 E I / L^2.
model = base_model();
model.nodes = [0 0; 3 0; 0 -4];
model.members = [1 2; 2 3];          % bottom (3 m) and diagonal (5 m), the diagonal below
model.supports = [1 1; 3 1];
model.forces = [2 0 -30000];
model.E = [200e9; 70e9];
model.A = [1e-4; 4e-4];
model.I = [1e-8; 2e-6];
model.yieldStress = [250e6; 270e6];
r = dlab.sims.truss.truss_engine(model);
verifyTrue(testCase, r.success, char(r.error));
% Statics at node 2: the diagonal props it up with 37.5 kN of compression,
% and the bottom bar holds it back with 22.5 kN of tension.
verifyEqual(testCase, r.memberForces, [22500; -37500], 'RelTol', 1e-9);
verifyEqual(testCase, r.stress, [22500 / 1e-4; -37500 / 4e-4], 'RelTol', 1e-9);
Pcr = pi^2 * 70e9 * 2e-6 / 25;
verifyEqual(testCase, r.criticalLoad, [Inf; Pcr], 'RelTol', 1e-12);
verifyEqual(testCase, r.utilization, [225e6 / 250e6; 37500 / Pcr], 'RelTol', 1e-9);
verifyEqual(testCase, r.failureMode, ["yield"; "buckling"], 'Buckling governs: 0.68 against 0.35 for yield.');
verifyEqual(testCase, r.lengths, [3; 5], 'RelTol', 1e-12);
end

function testPerMemberStiffnessSharesTheLoad(testCase)
% Two parallel bars between the same nodes (indeterminate): the load
% splits in proportion to E A.
model = base_model();
model.nodes = [0 0; 2 0];
model.members = [1 2; 1 2];
model.supports = [1 1; 2 3];
model.forces = [2 3000 0];
model.A = [0.01; 0.02];
r = dlab.sims.truss.truss_engine(model);
verifyEqual(testCase, r.memberForces, [1000; 2000], 'RelTol', 1e-9);
end

function testNoCheckWithoutStrengthData(testCase)
model = base_model();
model.nodes = [0 0; 2 0];
model.members = [1 2];
model.forces = [2 -1000 0];
model.supports = [1 1; 2 3];
r = dlab.sims.truss.truss_engine(model);
verifyTrue(testCase, isnan(r.utilization));
verifyEqual(testCase, r.failureMode, "");
end

function testStrengthScaleDividesUtilization(testCase)
% The footbridge (chords governed by yield, web posts by buckling): the
% strength scale divides every utilization and leaves forces and modes alone.
plugin = dlab.sims.truss.TrussPlugin();
params = plugin.defaultParams();
models = dlab.sims.truss.presetModels();
model = models([models.Name] == "Footbridge check (steel tubes)").Model;
for field = string(fieldnames(model))'
    params.(field) = model.(field);
end
nominal = plugin.solve(params);
verifyEqual(testCase, params.strengthScale, 1);
verifyTrue(testCase, all(ismember(["buckling" "yield"], nominal.failureMode)), "Both modes govern somewhere.");
params.strengthScale = 2.5;
stronger = plugin.solve(params);
verifyEqual(testCase, stronger.utilization, nominal.utilization / 2.5);
verifyEqual(testCase, stronger.criticalLoad, nominal.criticalLoad * 2.5);
verifyEqual(testCase, stronger.failureMode, nominal.failureMode);
verifyEqual(testCase, stronger.memberForces, nominal.memberForces);
verifyEqual(testCase, stronger.U, nominal.U);
M = plugin.metrics(stronger);
M0 = plugin.metrics(nominal);
verifyEqual(testCase, M.Value(M.Quantity == "Safety factor"), ...
    2.5 * M0.Value(M0.Quantity == "Safety factor"), RelTol=1e-12);
end

function verify_numerical_failure(testCase, result)
verifyFalse(testCase, result.success);
verifyTrue(testCase, contains(result.error, "Numerical overflow"));
verifyEmpty(testCase, result.U);
verifyEmpty(testCase, result.memberForces);
verifyEmpty(testCase, result.reactions);
end

function model = base_model()
model = struct('nodes',[],'members',[],'forces',[],'supports',[], ...
    'E',200e9,'A',0.01);
end

function testEulerLoadForEveryMember(testCase)
% π² E I / L² for each member, tension or not (the export's column); the
% critical load stays Inf in tension.
model = struct('nodes', [0 0; 4 0; 2 3.464], 'members', [1 2; 2 3; 1 3], 'forces', [3 0 -20000], ...
    'supports', [1 1; 2 3], 'E', 200e9, 'A', 0.01, 'I', 8820e-8, 'yieldStress', 250e6);
r = dlab.sims.truss.truss_engine(model);
L = [4; hypot(2, 3.464); hypot(2, 3.464)];
verifyEqual(testCase, r.eulerLoad, pi^2 * 200e9 * 8820e-8 ./ L.^2, 'RelTol', 1e-12);
verifyEqual(testCase, r.criticalLoad(1), Inf);
end
