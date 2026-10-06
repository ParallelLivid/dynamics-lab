function w = windAt(wind, altitude)
%WINDAT Steady wind velocity in north-east-down axes (m/s) at ALTITUDE (m).
%   WIND fields:
%     speed      horizontal wind speed (m/s)
%     fromDeg    direction it blows FROM, clockwise from north (deg)
%     vertical   vertical wind, positive up (m/s)
%     profile    'uniform', or 'powerlaw': speed × (altitude / refHeight)^(1/7),
%                a boundary layer that is calmer near the ground
%     refHeight  reference height of the power law (m)
speed = wind.speed;
if strcmpi(wind.profile, 'powerlaw')
    speed = speed * (max(altitude, 1) / wind.refHeight)^(1/7);
end
w = [-speed * cosd(wind.fromDeg); -speed * sind(wind.fromDeg); -wind.vertical];
end
