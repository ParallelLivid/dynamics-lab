function tests = test_projectile_physics
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end



function testPointMassMatchesClosedForm(testCase)
% Independent reference: the closed-form vacuum trajectory.
p = pointParams();
p.dt = 0.5;
r = dlab.sims.projectile.projectile_physics(p);
tExpected = 2*p.v0*sind(p.theta)/p.g;
xExpected = p.v0*cosd(p.theta)*tExpected;
hExpected = (p.v0*sind(p.theta))^2/(2*p.g);

verifyEqual(testCase,r.impactTime,tExpected,'AbsTol',1e-11);
verifyEqual(testCase,r.range,xExpected,'AbsTol',1e-9);
verifyEqual(testCase,r.maxHeight,hExpected,'AbsTol',1e-10);
verifyEqual(testCase,r.apexTime,tExpected/2,'AbsTol',1e-11);
verifyEqual(testCase,r.Y(end),0);
verifyEqual(testCase,r.impactAngle,-45,'AbsTol',1e-10);
end

function testElevatedPointMassMatchesClosedForm(testCase)
p = pointParams();
p.h0 = 120;
p.theta = 20;
r = dlab.sims.projectile.projectile_physics(p);
vy = p.v0*sind(p.theta);
tExpected = (vy + sqrt(vy^2 + 2*p.g*p.h0))/p.g;
verifyEqual(testCase,r.impactTime,tExpected,'AbsTol',1e-11);
verifyEqual(testCase,r.Y(end),0);
verifyGreaterThan(testCase,r.impactSpeed,p.v0);
end

function testGroundContactIsImmediate(testCase)
p = pointParams();
p.theta = 0;
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase,r.T,0);
verifyEqual(testCase,r.X,0);
verifyEqual(testCase,numel(r.T),1);
end

function testZeroDragConvergesToPointMass(testCase)
p = pointParams();
point = dlab.sims.projectile.projectile_physics(p);
p = dragParams();
p.Cd = 0;
drag = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase,drag.impactTime,point.impactTime,'AbsTol',1e-8);
verifyEqual(testCase,drag.range,point.range,'AbsTol',1e-7);
verifyEqual(testCase,drag.maxHeight,point.maxHeight,'AbsTol',1e-7);
end

function testDragTrajectoryHasPhysicalInvariants(testCase)
p = dragParams();
r = dlab.sims.projectile.projectile_physics(p);
verifyTrue(testCase,all(isfinite([r.T r.X r.Y r.VX r.VY])));
verifyGreaterThan(testCase,diff(r.T),zeros(1,numel(r.T)-1));
verifyGreaterThanOrEqual(testCase,r.Y,-1e-10*ones(size(r.Y)));
verifyGreaterThanOrEqual(testCase,r.VX,-1e-10*ones(size(r.VX)));
verifyLessThan(testCase,r.range,dlab.sims.projectile.projectile_physics(pointParams()).range);
verifyEqual(testCase,r.Y(end),0);
verifyLessThan(testCase,r.impactAngle,0);
end

function testInvalidInputsAreRejected(testCase)
p = pointParams();
p.g = NaN;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:InvalidParameter');

p = pointParams();
p.model = 'unknown';
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:InvalidParameter');

p = dragParams();
p.m = 0;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:InvalidParameter');
end

function testSafetyLimitsAreEnforced(testCase)
p = pointParams();
p.v0 = 5000;
p.g = 0.01;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:TimeLimit');

p = pointParams();
p.maxSteps = 10;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:StepLimit');
end

function testExtremeDragFailsSafely(testCase)
p = dragParams();
p.dt = 0.5;
p.theta = 45;
p.h0 = 1;
p.v0 = 1000;
p.Cd = 2;
p.rho = 1000;
p.m = 0.001;
p.geometry = 'area';
p.area = 1;
p.maxTime = 1;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:NoImpact');
end

function testLongDragDropUsesConfiguredHorizon(testCase)
p = dragParams();
p.h0 = 100;
p.v0 = 0;
p.Cd = 2;
p.rho = 1000;
p.geometry = 'area';
p.area = 1;
p.dt = 0.5;
p.maxTime = 1100;
r = dlab.sims.projectile.projectile_physics(p);
% Exact vertical quadratic-drag drop, evaluated without overflowing cosh.
k = p.rho*p.Cd*p.area/(2*p.m);
expected = (k*p.h0 + log(1+sqrt(1-exp(-2*k*p.h0))))/sqrt(p.g*k);
verifyEqual(testCase,r.impactTime,expected,'AbsTol',1e-3);
verifyEqual(testCase,r.Y(end),0);
p.maxTime = 1000;
verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:NoImpact');
end

function testBudgetCountsActualFlight(testCase)
p = dragParams();
p.Cd = 0;
p.maxSteps = 5000;
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase,r.impactTime,2*p.v0*sind(p.theta)/p.g,'AbsTol',1e-8);
verifyLessThanOrEqual(testCase,numel(r.T),p.maxSteps);
end

function testAdaptiveOutputBudgetBothSolvers(testCase)
for cd = [0.47 100]
    p = dragParams();
    p.Cd = cd;
    p.dt = 0.5;
    r = dlab.sims.projectile.projectile_physics(p);
    % Impact at exactly the budget is allowed; one fewer sample must stop.
    p.maxSteps = numel(r.T);
    bounded = dlab.sims.projectile.projectile_physics(p);
    verifyEqual(testCase,bounded.T,r.T);
    p.maxSteps = numel(r.T)-1;
    verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:StepLimit');
    p.maxSteps = 1;
    verifyError(testCase,@() dlab.sims.projectile.projectile_physics(p),'projectile:StepLimit');
end
end

function p = pointParams()
p = struct('g',9.81,'dt',0.01,'model','point',...
    'theta',45,'h0',0,'v0',50);
end

function p = dragParams()
p = pointParams();
p.model = 'sphere';
p.Cd = 0.47;
p.rho = 1.225;
p.m = 1;
p.geometry = 'radius';
p.radius = 0.05;
p.area = 0.01;
end

function p = airParams()
% The sphere at 60° that the wind, density, and optimal-angle tests start from.
p = struct('g', 9.81, 'dt', 0.01, 'model', 'sphere', 'theta', 60, 'h0', 0, 'v0', 50, ...
    'Cd', 0.47, 'rho', 1.225, 'm', 1, 'geometry', 'radius', 'radius', 0.05);
end

function testStillUniformAirIsUnchanged(testCase)
% The new air options default to the original model exactly.
p = airParams();
r0 = dlab.sims.projectile.projectile_physics(p);
p.windX = 0;
p.windProfile = 'uniform';
p.density = 'constant';
p.siteAltitude = 1000;
r1 = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, r1.X, r0.X);
verifyEqual(testCase, r1.range, 152.29, 'AbsTol', 5e-3);
end

function testStandardAtmosphereThinsWithHeight(testCase)
p = airParams();
r0 = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, dlab.physics.atmosphere(0), 1.225, 'AbsTol', 1e-4);
p.density = 'isa';
p.siteAltitude = 0;
r1 = dlab.sims.projectile.projectile_physics(p);
verifyGreaterThan(testCase, r1.range, r0.range, 'Air above the launch point is thinner.');
verifyLessThan(testCase, r1.range / r0.range - 1, 5e-3);
end

function testBaseballFliesFurtherInDenver(testCase)
p = airParams();
[p.v0, p.theta, p.radius, p.Cd, p.m, p.h0, p.density] = deal(45, 35, 0.0366, 0.35, 0.145, 1, 'isa');
p.siteAltitude = 0;
sea = dlab.sims.projectile.projectile_physics(p);
p.siteAltitude = 1609;
denver = dlab.sims.projectile.projectile_physics(p);
gain = denver.range / sea.range - 1;
verifyGreaterThan(testCase, gain, 0.04);
verifyLessThan(testCase, gain, 0.08);
end

function testTailwindHelpsAndHeadwindHurts(testCase)
p = airParams();
still = dlab.sims.projectile.projectile_physics(p);
p.windX = 5;
tail = dlab.sims.projectile.projectile_physics(p);
p.windX = -5;
head = dlab.sims.projectile.projectile_physics(p);
verifyGreaterThan(testCase, tail.range, still.range);
verifyLessThan(testCase, head.range, still.range);
p.windX = 5;
p.windProfile = 'powerlaw';
shear = dlab.sims.projectile.projectile_physics(p);
verifyNotEqual(testCase, shear.range, tail.range);
end

function testMovingWithTheWindFeelsNoHorizontalDrag(testCase)
% Galilean check: horizontal velocity equal to the wind keeps it exactly.
p = airParams();
w = 8;
p.windX = w;
p.theta = atand(30 / w);
p.v0 = hypot(30, w);
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, r.VX, w * ones(size(r.VX)), 'AbsTol', 1e-10);
end

function testOptimalAngleOfAPointMass(testCase)
p = pointParams();
p.theta = 10;
best = dlab.sims.projectile.optimalAngle(p);
verifyEqual(testCase, best.angle, 45, 'AbsTol', 1e-12);
verifyEqual(testCase, best.range, p.v0^2 / p.g, 'RelTol', 1e-10);
p.h0 = 100;
best = dlab.sims.projectile.optimalAngle(p);
reach = sqrt(p.v0^2 + 2 * p.g * p.h0);
verifyEqual(testCase, best.angle, atand(p.v0 / reach), 'AbsTol', 1e-12);
verifyEqual(testCase, best.range, p.v0 * reach / p.g, 'RelTol', 1e-9);
end

function testOptimalAngleWithDrag(testCase)
p = airParams();
best = dlab.sims.projectile.optimalAngle(p);
angles = best.angle + (-0.5:0.01:0.5);
ranges = arrayfun(@(a) rangeAt(p, a), angles);
[~, i] = max(ranges);
verifyEqual(testCase, best.angle, angles(i), 'AbsTol', 0.02);
verifyLessThan(testCase, best.angle, 45, 'Drag lowers the best angle.');
verifyEqual(testCase, best.angle, 42.3, 'AbsTol', 0.1);
end

function testOptimalAngleSearchCanBeCancelled(testCase)
p = airParams();
verifyError(testCase, @() dlab.sims.projectile.optimalAngle(p, @(f) f > 0.3), 'projectile:Cancelled');
end

function range = rangeAt(p, angle)
p.theta = angle;
r = dlab.sims.projectile.projectile_physics(p);
range = r.range;
end

function testNoSpinKeepsTheOriginalModel(testCase)
% Zero spin runs the original 2-D equations: identical samples.
p = airParams();
r0 = dlab.sims.projectile.projectile_physics(p);
p.backspin = 0;
p.sidespin = 0;
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, r.X, r0.X);
verifyEqual(testCase, r.Y, r0.Y);
verifyEqual(testCase, r.Z, zeros(size(r.X)));
verifyEqual(testCase, r.lateral, 0);
end

function testMagnusCurvesOnACircle(testCase)
% No drag and (almost) no gravity: the Magnus force is perpendicular to the
% velocity, so the speed stays constant and the ball turns on a circle of
% radius R = m v² / F = 2m / (ρ A C_L) (C_L from S = rω/v: Sawicki et al.).
p = struct('g', 0.01, 'dt', 0.001, 'model', 'sphere', 'theta', 0, 'h0', 0.01, 'v0', 30, ...
    'Cd', 0, 'rho', 1.225, 'm', 0.145, 'geometry', 'radius', 'radius', 0.0366, 'sidespin', 3000);
r = dlab.sims.projectile.projectile_physics(p);
S = 0.0366 * (2 * pi / 60 * 3000) / 30;
CL = 0.09 + 0.6 * S;
R = 2 * 0.145 / (1.225 * pi * 0.0366^2 * CL);
radius = hypot(r.X, r.Z - R);                    % centre at (0, R): curving right
verifyEqual(testCase, radius, R * ones(size(radius)), 'RelTol', 1e-5);
verifyEqual(testCase, hypot(r.VX, r.VZ), 30 * ones(size(r.VX)), 'RelTol', 1e-6, 'The speed is constant.');
verifyGreaterThan(testCase, r.lateral, 1, 'Positive sidespin curves to the right.');
end

function testSpinDirections(testCase)
% Backspin carries further and higher, topspin dips, and sidespin moves the
% ball sideways only (to the right for positive, the left for negative).
p = dragParams();
[p.theta, p.v0] = deal(35, 45);
r0 = dlab.sims.projectile.projectile_physics(p);
p.backspin = 2000;
up = dlab.sims.projectile.projectile_physics(p);
verifyGreaterThan(testCase, up.range, r0.range);
verifyGreaterThan(testCase, up.maxHeight, r0.maxHeight);
verifyEqual(testCase, up.lateral, 0);
p.backspin = -2000;
verifyLessThan(testCase, dlab.sims.projectile.projectile_physics(p).range, r0.range);
p.backspin = 0;
p.sidespin = 2000;
right = dlab.sims.projectile.projectile_physics(p);
p.sidespin = -2000;
left = dlab.sims.projectile.projectile_physics(p);
verifyGreaterThan(testCase, right.lateral, 0);
verifyEqual(testCase, left.lateral, -right.lateral, 'RelTol', 1e-6, 'Mirror images.');
verifyEqual(testCase, left.range, right.range, 'RelTol', 1e-6);
end

% ---- Independent reference values (docs/verification/projectile.md)

function testVerticalLaunchLandsWhereItStarted(testCase)
% θ = 90° goes straight up and down: the range is exactly zero (cos 90° = 0
% exactly), with and without drag.
p = pointParams();
p.theta = 90;
verifyEqual(testCase, dlab.sims.projectile.projectile_physics(p).range, 0);
p = dragParams();
p.theta = 90;
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, r.range, 0);
verifyEqual(testCase, r.impactAngle, -90);
end

function testElevatedLaunchMatchesClosedForms(testCase)
% Cliff launch preset: 50 m/s at 15° from 100 m, no air.
p = pointParams();
[p.theta, p.h0] = deal(15, 100);
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, r.range, 290.89587, 'AbsTol', 1e-5);
verifyEqual(testCase, r.maxHeight, 108.53559, 'AbsTol', 1e-5);
verifyEqual(testCase, r.impactSpeed, sqrt(50^2 + 2*9.81*100), 'RelTol', 1e-12);
end

function testTerminalVelocityInALongDrop(testCase)
% Dropped from 3000 m: v(h) = v_t √(1 − exp(−2 g h / v_t²)) and
% t = (v_t / g) arccosh(exp(g h / v_t²)), v_t = √(2 m g / (ρ Cd A)).
p = dragParams();
[p.v0, p.theta, p.h0] = deal(0, 90, 3000);
r = dlab.sims.projectile.projectile_physics(p);
vt = sqrt(2*p.m*p.g/(p.rho*p.Cd*pi*p.radius^2));
verifyEqual(testCase, vt, 65.86999, 'AbsTol', 1e-5);
verifyEqual(testCase, r.impactSpeed, vt*sqrt(1 - exp(-2*p.g*p.h0/vt^2)), 'RelTol', 1e-7);
verifyEqual(testCase, r.impactTime, vt/p.g*acosh(exp(p.g*p.h0/vt^2)), 'RelTol', 1e-7);
end

function testStandardAtmosphereMatchesThe1976Table(testCase)
% U.S. Standard Atmosphere 1976, density at geopotential altitude (the
% engine treats the altitude as geopotential: < 0.1 % at 8 km).
heights = [0 1000 2000 5000 8000 11000];
standard = [1.2250 1.1116 1.0065 0.73612 0.52517 0.36392];
verifyEqual(testCase, dlab.physics.atmosphere(heights), standard, 'RelTol', 1e-4);
end

function testWindMatchesAnIndependentIntegration(testCase)
% Golf ball (70 m/s at 12°), drag on the air-relative velocity; reference
% values from a separate DOP853 integration at 1e-12.
p = airParams();
[p.v0, p.theta, p.radius, p.Cd, p.m] = deal(70, 12, 0.02135, 0.25, 0.0459);
ranges = zeros(1, 3);
winds = [-8 0 8];
for k = 1:3
    p.windX = winds(k);
    ranges(k) = dlab.sims.projectile.projectile_physics(p).range;
end
verifyEqual(testCase, ranges, [117.67781 128.48562 139.09980], 'AbsTol', 1e-4);
end

function testMagnusMatchesAnIndependentIntegration(testCase)
% Positions part-way through the flight against a separate fixed-step RK4
% integration of the same model (F = ½ρA·C_L·|v|²·(ω̂ × v̂)).
p = airParams();
[p.v0, p.theta, p.radius, p.Cd, p.m, p.backspin] = deal(70, 11, 0.02135, 0.25, 0.0459, 2800);
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, [interp1(r.T, r.X, 0.5) interp1(r.T, r.Y, 0.5)], [31.503711 6.390745], 'AbsTol', 2e-3);
p = airParams();
[p.v0, p.theta, p.h0, p.radius, p.Cd, p.m, p.sidespin] = deal(35, 1, 1.8, 0.0366, 0.35, 0.145, -2000);
r = dlab.sims.projectile.projectile_physics(p);
verifyEqual(testCase, interp1(r.T, r.Z, 0.3), -0.206131, 'AbsTol', 2e-4, 'Negative sidespin: to the left.');
verifyEqual(testCase, r.lateral, -1.00648, 'AbsTol', 1e-4);
end

function testSpinParameterUsesTheAirRelativeSpeed(testCase)
% S = r|ω| / |v − w| at launch: into a 5 m/s headwind the air-relative
% speed is 39.99 m/s, not the 35 m/s launch speed.
p = airParams();
[p.v0, p.theta, p.h0, p.radius, p.Cd, p.m, p.sidespin, p.windX] = deal(35, 1, 1.8, 0.0366, 0.35, 0.145, 2000, -5);
r = dlab.sims.projectile.projectile_physics(p);
relative = hypot(35*cosd(1) + 5, 35*sind(1));
S = 0.0366 * (2*pi/60*2000) / relative;
verifyEqual(testCase, r.spinParameter, S, 'RelTol', 1e-12);
verifyEqual(testCase, r.liftCoefficient, 0.09 + 0.6*S, 'RelTol', 1e-12);
verifyEqual(testCase, r.lateral, 1.20206, 'AbsTol', 1e-4);
end
