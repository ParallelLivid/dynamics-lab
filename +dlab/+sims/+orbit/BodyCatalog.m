function bodies = BodyCatalog()
%BODYCATALOG Central-body data and default elliptical orbits.
%   Physical constants come from dlab.physics.bodyConstants; this adds the
%   display colors, each body's default orbit, and its output step. The
%   Custom body starts from Earth's constants.

names = ["Mercury","Venus","Earth","Moon","Mars", ...
    "Jupiter","Saturn","Uranus","Neptune","Sun","Custom"];

color = [
    .52 .48 .42; .85 .78 .55; .10 .25 .65; .50 .50 .54; .58 .22 .12;
    .72 .55 .38; .82 .72 .45; .55 .82 .85; .20 .35 .75; .88 .58 .04;
    .35 .15 .55];
ringColor = min(color + 0.18, 1);
altitude = [400,400,407,150,200,2000,2000,1000,1000,148904300,407];
eccentricity = [.08,.01,.01,.02,.01,.01,.01,.01,.01,.0167,.01];
inclination = [7,2.6,28.5,90,28.5,5.1,26.7,97.8,28.3,0,28.5];
sampleStep = [5,15,30,10,20,60,60,30,30,7200,30];

bodies = struct();
for index = 1:numel(names)
    source = names(index);
    if source == "Custom"
        source = "Earth";
    end
    constants = dlab.physics.bodyConstants(source);
    body.mu = constants.mu;
    body.radius = constants.radius;
    body.color = color(index,:);
    body.ringColor = ringColor(index,:);
    body.spinRate = constants.spinRate;
    body.tilt = constants.tilt;
    body.orbit = [constants.radius+altitude(index), eccentricity(index), ...
        inclination(index), 0, 0, 0];
    body.sampleStep = sampleStep(index);
    bodies.(names(index)) = body;
end
end
