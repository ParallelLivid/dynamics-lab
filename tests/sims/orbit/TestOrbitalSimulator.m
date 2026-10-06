function tests = TestOrbitalSimulator
%TESTORBITALSIMULATOR Regression tests for the simulator core.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function testCatalog(testCase)
bodies = dlab.sims.orbit.BodyCatalog();
names = fieldnames(bodies);
verifyEqual(testCase,numel(names),11);
for index = 1:numel(names)
    body = bodies.(names{index});
    verifyGreaterThan(testCase,body.mu,0);
    verifyGreaterThan(testCase,body.radius,0);
    verifyGreaterThan(testCase,body.orbit(1)*(1-body.orbit(2)),body.radius);
end
end

function testElementRoundTrip(testCase)
dynamics = dlab.sims.orbit.OrbitalDynamics();
mu = 398600.4418;
expected = [7200,.12,deg2rad(48),deg2rad(25),deg2rad(70),deg2rad(15)];
[position,velocity] = dynamics.kep2cart(expected(1),expected(2), ...
    expected(3),expected(4),expected(5),expected(6),mu);
actual = dynamics.cart2kep(position,velocity,mu);
difference = actual-expected;
difference(3:6) = atan2(sin(difference(3:6)),cos(difference(3:6)));
verifyLessThan(testCase,max(abs(difference)),1e-9);
end

function testParabolicSemiMajorAxis(testCase)
dynamics = dlab.sims.orbit.OrbitalDynamics();
mu = 398600.4418;
position = [7000 0 0];
velocity = [0 sqrt(2*mu/norm(position)) 0];
elements = dynamics.cart2kep(position,velocity,mu);
verifyTrue(testCase,isinf(elements(1)));
verifyEqual(testCase,elements(2),1,"AbsTol",1e-12);
end

function testOneOrbitConservation(testCase)
body = dlab.sims.orbit.BodyCatalog().Earth;
dynamics = dlab.sims.orbit.OrbitalDynamics();
orbit = body.orbit;
[position,velocity] = dynamics.kep2cart(orbit(1),orbit(2), ...
    deg2rad(orbit(3)),deg2rad(orbit(4)),deg2rad(orbit(5)),deg2rad(orbit(6)),body.mu);
options = struct("durationOrbits",1,"sampleStep",30);
result = dlab.sims.orbit.simulateOrbit([position(:);velocity(:)],body,options);
verifyLessThan(testCase,norm(result.state(end,1:3)-position),2e-3);
energyDrift = max(abs(result.energy-result.energy(1)))/abs(result.energy(1));
momentumDrift = max(abs(result.angularMomentum-result.angularMomentum(1))) / result.angularMomentum(1);
verifyLessThan(testCase,energyDrift,1e-9);
verifyLessThan(testCase,momentumDrift,1e-9);
end

function testSurfaceImpact(testCase)
body = dlab.sims.orbit.BodyCatalog().Earth;
state = [body.radius+10;0;0;-1;0;0];
result = dlab.sims.orbit.simulateOrbit(state,body,struct("durationOrbits",1,"sampleStep",1));
verifyTrue(testCase,result.impacted);
verifyLessThanOrEqual(testCase,abs(norm(result.state(end,1:3))-body.radius),1e-5);
end

function testOutputLimit(testCase)
body = dlab.sims.orbit.BodyCatalog().Earth;
state = [7000;0;0;0;sqrt(body.mu/7000);0];
options = struct("durationOrbits",10,"sampleStep",1,"maxOutputPoints",10);
verifyError(testCase,@()dlab.sims.orbit.simulateOrbit(state,body,options),"OrbitSim:TooManyPoints");
end

function testInvalidBody(testCase)
body = dlab.sims.orbit.BodyCatalog().Earth;
body.mu = -1;
state = [7000;0;0;0;7.5;0];
verifyError(testCase,@()dlab.sims.orbit.simulateOrbit(state,body),"OrbitSim:InvalidBody");
end

function testSingularOrientationRoundTrips(testCase)
dynamics = dlab.sims.orbit.OrbitalDynamics();
mu = 398600.4418;
cases = [.2 0; .2 pi; 0 .7; 0 0; 0 pi; .2 1e-14; 0 pi-1e-14];
for index = 1:size(cases,1)
    [r,v] = dynamics.kep2cart(9000,cases(index,1),cases(index,2),1.2,.8,2.1,mu);
    elements = dynamics.cart2kep(r,v,mu);
    [reconstructedR,reconstructedV] = dynamics.kep2cart(elements(1),elements(2), ...
        elements(3),elements(4),elements(5),elements(6),mu);
    verifyEqual(testCase,reconstructedR,r,"AbsTol",1e-7);
    verifyEqual(testCase,reconstructedV,v,"AbsTol",1e-10);
end
end

function testAllPresetsRunAtDefaultDuration(testCase)
bodies = dlab.sims.orbit.BodyCatalog();
dynamics = dlab.sims.orbit.OrbitalDynamics();
names = fieldnames(bodies);
for index = 1:numel(names)
    body = bodies.(names{index});
    orbit = body.orbit;
    angles = deg2rad(orbit(3:6));
    [r,v] = dynamics.kep2cart(orbit(1),orbit(2),angles(1),angles(2),angles(3),angles(4),body.mu);
    result = dlab.sims.orbit.simulateOrbit([r(:);v(:)],body,struct("sampleStep",body.sampleStep));
    verifyLessThanOrEqual(testCase,numel(result.time),20000,names{index});
    verifyFalse(testCase,result.impacted,names{index});
    verifyEqual(testCase,result.time(end),result.requestedDuration);
end
end

function testBoundedEndpointSampling(testCase)
body = dlab.sims.orbit.BodyCatalog().Earth;
state = [7000;0;0;0;12;0];
for step = [100 200]
    options = struct("hyperbolicDuration",100,"sampleStep",step,"maxOutputPoints",2);
    result = dlab.sims.orbit.simulateOrbit(state,body,options);
    verifyEqual(testCase,result.time,[0;100]);
    verifySize(testCase,result.state,[2 6]);
end
options = struct("hyperbolicDuration",100,"sampleStep",30,"maxOutputPoints",4);
verifyError(testCase,@()dlab.sims.orbit.simulateOrbit(state,body,options),"OrbitSim:TooManyPoints");
options.maxOutputPoints = 5;
result = dlab.sims.orbit.simulateOrbit(state,body,options);
verifyEqual(testCase,result.time,[0;30;60;90;100]);
state = [body.radius+10;0;0;-1;0;0];
result = dlab.sims.orbit.simulateOrbit(state,body,struct("sampleStep",1e6,"maxOutputPoints",2));
verifyEqual(testCase,numel(result.time),2);
verifyTrue(testCase,result.impacted);
verifyEqual(testCase,norm(result.state(end,1:3)),body.radius,"AbsTol",1e-5);
end
