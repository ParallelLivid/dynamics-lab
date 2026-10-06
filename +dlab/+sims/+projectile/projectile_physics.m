function results = projectile_physics(params)
%PROJECTILE_PHYSICS Simulate a projectile until its first ground impact.
%   Uses an analytic point-mass solution and adaptive ODE45 integration for
%   quadratic drag. Returned samples always end exactly at y = 0.
%   Optional params.progressFcn: @(fraction) stop (fraction is NaN: the
%   impact time is not known in advance); returning true stops the solver.
%
%   Optional fields for the drag model (defaults reproduce the original
%   still, uniform air exactly):
%     windX         horizontal wind, m/s (+ blows downrange: a tailwind)
%     windProfile   'uniform' or 'powerlaw' (wind × (y/10 m)^(1/7), a
%                   boundary layer: calmer near the ground)
%     density       'constant' (params.rho) or 'isa' (standard atmosphere
%                   at siteAltitude + y, from dlab.physics.atmosphere)
%     siteAltitude  launch site height above sea level, m (for 'isa')
%   Drag then acts on the velocity relative to the air: F = −½ρCdA|v−w|(v−w).
%
%   Optional spin (sphere model; zero keeps the original equations):
%     backspin      rpm about the horizontal axis across the flight (+ lifts,
%                   − is topspin and makes the ball dip)
%     sidespin      rpm about the vertical axis (+ curves to the right,
%                   looking downrange)
%   With spin the flight is 3-D (z: to the right) and the Magnus force
%   F = ½ρA·C_L·|v−w|²·(ω̂ × v̂) acts across the air-relative velocity, with
%   C_L from the spin parameter S = r|ω|/|v−w| (Sawicki, Hubbard and
%   Stronge, Am. J. Phys. 71, 2003): C_L = 1.5 S for S < 0.1, else
%   0.09 + 0.6 S. The spin rate is taken as constant during the flight.
%   Results then also hold Z and VZ (zero without spin), and spinParameter
%   and liftCoefficient: S and C_L at launch, from the air-relative speed
%   (NaN without spin).

arguments
    params (1,1) struct
end

required = {'g','dt','model','theta','h0','v0'};
for i = 1:numel(required)
    if ~isfield(params,required{i})
        error('projectile:MissingParameter', ...
            'Missing required parameter "%s".',required{i});
    end
end

validateScalar(params.g,     'g',     0,   Inf, false, true);
validateScalar(params.dt,    'dt',    0,   0.5, false, true);
validateScalar(params.theta, 'theta', 0,   90,  true,  true);
validateScalar(params.h0,    'h0',    0,   Inf, true,  true);
validateScalar(params.v0,    'v0',    0,   Inf, true,  true);

model = validateChoice(params.model,{'point','sphere'},'model');
g = params.g;
dt = params.dt;
vx0 = params.v0*cosd(params.theta);    % cosd: exactly 0 at 90°, so a vertical shot has no range
vy0 = params.v0*sind(params.theta);
state0 = [0; params.h0; vx0; vy0];

maxTime = getOptionalLimit(params,'maxTime',3600);
maxSteps = getOptionalLimit(params,'maxSteps',250000);
if maxSteps ~= floor(maxSteps)
    error('projectile:InvalidParameter','maxSteps must be an integer.');
end

% An object already on the ground and not moving upward is not airborne.
if params.h0 == 0 && vy0 <= 0
    results = packageResults(0,state0,model,params,0,0);
    return;
end

switch model
    case 'point'
        discriminant = vy0^2 + 2*g*params.h0;
        tImpact = (vy0 + sqrt(discriminant))/g;
        if tImpact > maxTime
            error('projectile:TimeLimit', ...
                'Predicted flight time %.3g s exceeds the %.3g s safety limit.', ...
                tImpact,maxTime);
        end

        nRegular = floor(tImpact/dt);
        if nRegular + 2 > maxSteps
            error('projectile:StepLimit', ...
                'This run would require more than %d samples. Increase dt or reduce the launch scale.', ...
                maxSteps);
        end

        T = (0:nRegular)*dt;
        if isempty(T) || abs(T(end)-tImpact) > 16*eps(max(1,tImpact))
            T(end+1) = tImpact;
        else
            T(end) = tImpact;
        end

        X = vx0*T;
        Y = params.h0 + vy0*T - 0.5*g*T.^2;
        VX = vx0 + zeros(size(T));
        VY = vy0 - g*T;
        Y(end) = 0;
        states = [X(:),Y(:),VX(:),VY(:)];
        tApex = max(0,vy0/g);
        hApex = params.h0 + vy0*tApex - 0.5*g*tApex^2;
        results = packageResults(T(:),states,model,params,tApex,hApex);

    case 'sphere'
        sphereFields = {'Cd','rho','m','geometry'};
        for i = 1:numel(sphereFields)
            if ~isfield(params,sphereFields{i})
                error('projectile:MissingParameter', ...
                    'Missing required sphere parameter "%s".',sphereFields{i});
            end
        end
        validateScalar(params.Cd, 'Cd',  0, Inf, true, true);
        validateScalar(params.rho,'rho', 0, Inf, true, true);
        validateScalar(params.m,  'm',   0, Inf, false,true);
        air = airOptions(params);
        geometry = validateChoice(params.geometry,{'radius','area'},'geometry');
        if strcmp(geometry,'radius')
            if ~isfield(params,'radius')
                error('projectile:MissingParameter','Missing required parameter "radius".');
            end
            validateScalar(params.radius,'radius',0,Inf,false,true);
            area = pi*params.radius^2;
        else
            if ~isfield(params,'area')
                error('projectile:MissingParameter','Missing required parameter "area".');
            end
            validateScalar(params.area,'area',0,Inf,false,true);
            area = params.area;
        end

        % Count actual output, including the initial sample. Refine=1 makes
        % each accepted step produce one sample, so the callback can stop
        % before another step would exceed the storage budget.
        spin = spinOptions(params,area);
        if spin.active
            state0 = [0; params.h0; 0; vx0; vy0; 0];   % x, y, z, vx, vy, vz
        end
        vyIndex = 4 + spin.active;
        outputCount = 1;
        budgetReached = false;
        dragFactor = 0.5*params.Cd*params.rho*area/params.m;
        dragPerDensity = 0.5*params.Cd*area/params.m;
        magnusPerDensity = 0.5*area/params.m;
        if air.isa
            dragFactor = dragPerDensity*dlab.physics.atmosphere(air.siteAltitude + params.h0);
        end
        options = odeset('RelTol',1e-8,'AbsTol',1e-10, ...
            'MaxStep',dt,'Events',@events,'Refine',1, ...
            'OutputFcn',@limitOutput);
        stiffnessIndex = dragFactor*max(params.v0,1)*dt;
        if stiffnessIndex > 1
            odeSolver = @ode15s;
        else
            odeSolver = @ode45;
        end
        [T,states,TE,YE,IE] = odeSolver(@dynamics,[0 maxTime],state0,options);

        impactEvent = find(IE == 1,1,'last');
        if isempty(impactEvent)
            if budgetReached
                error('projectile:StepLimit', ...
                    'The adaptive solver reached the %d-sample limit before impact.',maxSteps);
            end
            error('projectile:NoImpact', ...
                'No ground impact was found within %.3g s. Reduce the drag scale or increase maxTime.', ...
                maxTime);
        end
        if size(states,1) > maxSteps
            error('projectile:StepLimit','The adaptive solver exceeded %d stored steps.',maxSteps);
        end
        if any(~isfinite(states),'all') || any(~isfinite(T))
            error('projectile:NonFiniteState','The solver produced a non-finite state.');
        end

        impactTime = TE(impactEvent);
        impactState = YE(impactEvent,:);
        if abs(T(end)-impactTime) > 16*eps(max(1,impactTime))
            if numel(T) >= maxSteps
                error('projectile:StepLimit','No sample budget remains for the impact state.');
            end
            T(end+1,1) = impactTime;
            states(end+1,:) = impactState;
        else
            T(end) = impactTime;
            states(end,:) = impactState;
        end
        states(end,2) = 0;

        apexEvent = find(IE == 2 & TE >= 0,1,'first');
        if isempty(apexEvent)
            [hApex,idx] = max(states(:,2));
            tApex = T(idx);
        else
            tApex = TE(apexEvent);
            hApex = YE(apexEvent,2);
        end
        results = packageResults(T,states,model,params,tApex,hApex);
        if spin.active
            % S and C_L at launch, from the speed relative to the air.
            relative = norm([vx0 - windAt(params.h0,air); vy0]);
            results.spinParameter = spin.radius*spin.rate/max(relative,eps);
            results.liftCoefficient = liftCoefficient(results.spinParameter);
        end
end

    function stop = limitOutput(t,~,flag)
        stop = false;
        if strcmp(flag,'init')
            if maxSteps < 2
                error('projectile:StepLimit', ...
                    'An airborne trajectory requires at least two samples.');
            end
        elseif isempty(flag)
            outputCount = outputCount + numel(t);
            budgetReached = outputCount >= maxSteps;
            stop = budgetReached;
            if isfield(params,'progressFcn') && ~isempty(params.progressFcn)
                stop = stop || params.progressFcn(NaN);
            end
        end
    end

    function ds = dynamics(~,s)
        if spin.active
            ds = spinning(s);
            return
        end
        if ~air.active
            speed = hypot(s(3),s(4));
            ds = [s(3); s(4); -dragFactor*speed*s(3); ...
                -g-dragFactor*speed*s(4)];
            return
        end
        % Wind and/or altitude-dependent density: drag on the air-relative velocity.
        relativeX = s(3) - windAt(s(2), air);
        relativeSpeed = hypot(relativeX,s(4));
        factor = dragFactor;
        if air.isa
            factor = dragPerDensity*dlab.physics.atmosphere(air.siteAltitude + max(s(2),0));
        end
        ds = [s(3); s(4); -factor*relativeSpeed*relativeX; ...
            -g-factor*relativeSpeed*s(4)];
    end

    function ds = spinning(s)
        % 3-D flight with drag and the Magnus force on the air-relative velocity.
        velocity = s(4:6);
        relative = velocity - [windAt(s(2),air); 0; 0];
        speed = norm(relative);
        density = params.rho;
        if air.isa
            density = dlab.physics.atmosphere(air.siteAltitude + max(s(2),0));
        end
        acceleration = [0; -g; 0] - dragPerDensity*density*speed*relative;
        if speed > 0
            lift = liftCoefficient(spin.radius*spin.rate/speed);
            acceleration = acceleration + magnusPerDensity*density*lift*speed^2 ...
                * cross(spin.axis, relative/speed);
        end
        ds = [velocity; acceleration];
    end

    function [value,isTerminal,direction] = events(t,s)
        groundValue = s(2);
        if params.h0 == 0 && vy0 > 0 && t <= 1e-12
            groundValue = 1; % Ignore launch contact; detect later descent.
        end
        value = [groundValue; s(vyIndex)];
        isTerminal = [1; 0];
        direction = [-1; -1];
    end
end

function results = packageResults(T,states,model,params,tApex,hApex)
T = T(:).';
if size(states,1) ~= numel(T)
    states = states.';
end
if size(states,2) == 6
    % Spinning: x, y, z, vx, vy, vz.
    states = states(:,[1 2 4 5 3 6]);
else
    states(:,5:6) = 0;
end
results.X = states(:,1).';
results.Y = states(:,2).';
results.VX = states(:,3).';
results.VY = states(:,4).';
results.Z = states(:,5).';
results.VZ = states(:,6).';
results.T = T;
results.model = model;
results.params = params;
results.apexTime = tApex;
results.maxHeight = hApex;
results.impactTime = T(end);
results.range = results.X(end);
results.impactSpeed = hypot(hypot(results.VX(end),results.VY(end)),results.VZ(end));
if results.VZ(end) == 0
    results.impactAngle = atan2d(results.VY(end),results.VX(end));   % the original 2-D value
else
    results.impactAngle = atan2d(results.VY(end),hypot(results.VX(end),results.VZ(end)));
end
results.lateral = results.Z(end);
results.landed = true;
results.spinParameter = NaN;      % set by the caller when the ball spins
results.liftCoefficient = NaN;
end

function spin = spinOptions(params,area)
% Backspin and sidespin (rpm) as a spin vector; ACTIVE is false without
% spin (the original 2-D equations, kept exactly).
backspin = 0;
sidespin = 0;
if isfield(params,'backspin')
    validateScalar(params.backspin,'backspin',-30000,30000,true,true);
    backspin = params.backspin;
end
if isfield(params,'sidespin')
    validateScalar(params.sidespin,'sidespin',-30000,30000,true,true);
    sidespin = params.sidespin;
end
omega = 2*pi/60*[0; -sidespin; backspin];     % rad/s: ẑ × x̂ = ŷ lifts, −ŷ × x̂ = ẑ curves right
spin.active = any(omega ~= 0);
spin.rate = norm(omega);
spin.axis = [0; 0; 1];
if spin.active
    spin.axis = omega/spin.rate;
end
spin.radius = sqrt(area/pi);                    % from the frontal area when given as an area
end

function c = liftCoefficient(S)
% Sawicki, Hubbard and Stronge (2003): a fit to baseball measurements.
if S < 0.1
    c = 1.5*S;
else
    c = 0.09 + 0.6*S;
end
end

function air = airOptions(params)
% Wind and density options of the drag model; ACTIVE is false for still,
% uniform air (the original equations, kept exactly).
air.windX = 0;
if isfield(params,'windX')
    validateScalar(params.windX,'windX',-Inf,Inf,true,true);
    air.windX = params.windX;
end
air.powerLaw = false;
if isfield(params,'windProfile')
    air.powerLaw = strcmp(validateChoice(params.windProfile,{'uniform','powerlaw'},'windProfile'),'powerlaw');
end
air.isa = false;
if isfield(params,'density')
    air.isa = strcmp(validateChoice(params.density,{'constant','isa'},'density'),'isa');
end
air.siteAltitude = 0;
if isfield(params,'siteAltitude')
    validateScalar(params.siteAltitude,'siteAltitude',-1000,80000,true,true);
    air.siteAltitude = params.siteAltitude;
end
air.active = air.windX ~= 0 || air.isa;
end

function w = windAt(y,air)
% Horizontal wind at height y (m above the launch ground).
w = air.windX;
if air.powerLaw
    w = w*(max(y,0.1)/10)^(1/7);
end
end

function validateScalar(value,name,lower,upper,includeLower,includeUpper)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value))
    error('projectile:InvalidParameter','%s must be a finite real scalar.',name);
end
lowerOK = value > lower || (includeLower && value == lower);
upperOK = value < upper || (includeUpper && value == upper);
if ~(lowerOK && upperOK)
    leftBracket = pickBracket(includeLower,'[','(');
    rightBracket = pickBracket(includeUpper,']',')');
    error('projectile:InvalidParameter','%s must be in %s%g, %g%s.', ...
        name,leftBracket,lower,upper,rightBracket);
end
end

function value = getOptionalLimit(params,name,defaultValue)
if isfield(params,name)
    value = params.(name);
else
    value = defaultValue;
end
validateScalar(value,name,0,Inf,false,true);
end

function value = validateChoice(candidate,choices,name)
try
    value = validatestring(candidate,choices,mfilename,name);
catch
    error('projectile:InvalidParameter','%s must be one of: %s.',...
        name,strjoin(choices,', '));
end
end

function value = pickBracket(condition,a,b)
if condition, value = a; else, value = b; end
end
