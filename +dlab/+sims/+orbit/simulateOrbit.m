function result = simulateOrbit(initialState, body, options)
%SIMULATEORBIT Integrate and analyze a two-body trajectory.
%   Optional options.progressFcn: @(fraction) stop; returning true stops
%   the integration early (the result is then partial).
%
%   Optional perturbations (both off by default, which keeps the plain
%   two-body equations exactly):
%     options.J2         oblateness: gravity of the flattened body, about
%                        its spin axis (the frame's z axis turned by
%                        body.tilt about y), with body.J2Radius as the
%                        reference radius (body.radius if it has none)
%     options.dragB      ballistic coefficient Cd·A/m (m²/kg) for drag in
%                        Earth's atmosphere (dlab.physics.thermosphereDensity),
%                        which turns with the body (body.spinRate)
%   With J2 the energy includes the J2 potential, and the angular
%   momentum is its component along the spin axis (both conserved); with
%   drag both fall. result.equatorial holds the elements measured from
%   the body's equator (the frame's when there is no tilt).

arguments
    initialState (6,1) double {mustBeFinite}
    body struct
    options (1,1) struct = struct()
end

validateBody(body);
options = validatedOptions(options);
r0 = initialState(1:3);
v0 = initialState(4:6);
radius0 = norm(r0);
if radius0 <= body.radius
    error("OrbitSim:InsideBody", "Initial position must be above the body surface.");
end

energy0 = 0.5*dot(v0,v0) - body.mu/radius0;
if energy0 < 0
    semiMajorAxis = -body.mu/(2*energy0);
    period = 2*pi*sqrt(semiMajorAxis^3/body.mu);
    duration = options.durationOrbits*period;
    warningText = "";
else
    period = Inf;
    duration = options.hyperbolicDuration;
    warningText = "Open trajectory: using the configured time window.";
end

pointCount = max(2,ceil(duration/options.sampleStep) + 1);
if ~isfinite(pointCount) || pointCount > options.maxOutputPoints
    error("OrbitSim:TooManyPoints", ...
        "Requested %d output points; increase the time step or reduce the duration.", pointCount);
end

time = [(0:pointCount-2)'*options.sampleStep;duration];
dynamics = dlab.sims.orbit.OrbitalDynamics();
toFrame = dlab.physics.roty(deg2rad(body.tilt));   % equatorial axes → frame axes
spinAxis = toFrame(:, 3);
perturbed = options.J2 ~= 0 || options.dragB > 0;
if ~isfield(body, "J2Radius")
    body.J2Radius = body.radius;
end
if perturbed
    equations = @(~, y) perturbedMotion(y, body, options, toFrame, spinAxis);
else
    equations = @(t, y) dynamics.eomTwoBody(t, y, body.mu);
end
solverOptions = odeset( ...
    "RelTol", options.relativeTolerance, ...
    "AbsTol", options.absoluteTolerance, ...
    "Events", @(t,y)dynamics.evtAltitude(t,y,body.radius));
if isfield(options,"progressFcn") && ~isempty(options.progressFcn)
    solverOptions = odeset(solverOptions,"OutputFcn",dlab.physics.odeProgress(options.progressFcn,[0 duration]));
end
solution = ode45(equations, [0 duration], initialState, solverOptions);
% Include the impact endpoint without exceeding the requested sample count.
stopTime = solution.x(end);
time = [time(time < stopTime);stopTime];
state = deval(solution,time).';

position = state(:,1:3);
velocity = state(:,4:6);
radius = vecnorm(position,2,2);
energy = 0.5*sum(velocity.^2,2) - body.mu./radius;
angularMomentum = vecnorm(cross(position,velocity,2),2,2);
if options.J2 ~= 0
    % The J2 potential belongs in the energy, and only the angular
    % momentum about the spin axis is conserved.
    sine = (position*spinAxis)./radius;
    energy = energy + body.mu*options.J2*body.J2Radius^2*(1.5*sine.^2 - 0.5)./radius.^3;
    angularMomentum = cross(position,velocity,2)*spinAxis;
end
elements = zeros(size(state,1),6);
equatorial = zeros(size(state,1),6);
for index = 1:size(state,1)
    elements(index,:) = dynamics.cart2kep(position(index,:),velocity(index,:),body.mu);
    equatorial(index,:) = dynamics.cart2kep(position(index,:)*toFrame,velocity(index,:)*toFrame,body.mu);
end

result.time = time;
result.body = body;
result.state = state;
result.elements = elements;
result.equatorial = equatorial;
result.energy = energy;
result.angularMomentum = angularMomentum;
result.angularMomentumScale = norm(cross(r0,v0));    % for relative drifts (the J2 component can be 0)
result.period = period;
result.requestedDuration = duration;
result.impacted = time(end) < duration*(1-1e-10);
result.warning = warningText;
result.J2 = options.J2;
result.dragB = options.dragB;
end

function derivative = perturbedMotion(y, body, options, toFrame, spinAxis)
% Two-body gravity plus J2 (in equatorial axes) and drag in a turning atmosphere.
r = y(1:3);
v = y(4:6);
distance = norm(r);
acceleration = -body.mu*r/distance^3;
if options.J2 ~= 0
    equatorial = toFrame.'*r;
    total = dlab.physics.gravity(equatorial, body.mu, J2=options.J2, Radius=body.J2Radius);
    acceleration = acceleration + toFrame*(total + body.mu*equatorial/distance^3);
end
if options.dragB > 0
    density = dlab.physics.thermosphereDensity(distance - body.radius);   % kg/m³
    relative = v - body.spinRate*cross(spinAxis, r);                     % km/s, against the air
    % a = −½ ρ B |v|v in m/s² with v in m/s; in km and km/s that is −500 ρ B |v|v.
    acceleration = acceleration - 500*density*options.dragB*norm(relative)*relative;
end
derivative = [v; acceleration];
end

function options = validatedOptions(options)
defaults = struct("durationOrbits",3,"sampleStep",30, ...
    "relativeTolerance",1e-10,"absoluteTolerance",1e-12, ...
    "maxOutputPoints",20000,"hyperbolicDuration",86400,"J2",0,"dragB",0);
names = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~isfield(options,name)
        options.(name) = defaults.(name);
    end
end
values = [options.durationOrbits,options.sampleStep,options.relativeTolerance, ...
    options.absoluteTolerance,options.maxOutputPoints,options.hyperbolicDuration];
if any(~isfinite(values)) || any(values <= 0) || ...
        options.maxOutputPoints ~= floor(options.maxOutputPoints)
    error("OrbitSim:InvalidOptions","Integration options must be finite and positive.");
end
if ~(isfinite(options.J2) && abs(options.J2) < 0.1 && isfinite(options.dragB) && options.dragB >= 0)
    error("OrbitSim:InvalidOptions","J2 must be small (|J2| < 0.1) and the ballistic coefficient non-negative.");
end
end

function validateBody(body)
required = ["mu","radius","spinRate","tilt","color","ringColor"];
if ~all(isfield(body,required))
    error("OrbitSim:InvalidBody", "Body data is incomplete.");
end
values = [body.mu,body.radius,body.spinRate,body.tilt,body.color,body.ringColor];
if any(~isfinite(values)) || body.mu <= 0 || body.radius <= 0
    error("OrbitSim:InvalidBody", "Body values must be finite with positive mu and radius.");
end
if body.tilt < 0 || body.tilt > 180
    error("OrbitSim:InvalidBody", "Axial tilt must be between 0 and 180 degrees.");
end
if any([body.color,body.ringColor] < 0 | [body.color,body.ringColor] > 1)
    error("OrbitSim:InvalidBody", "Body colors must be between zero and one.");
end
end
