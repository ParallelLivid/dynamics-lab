function value = convertUnits(value, from, to)
%CONVERTUNITS Convert between common units of the same kind.
%   v = dlab.physics.convertUnits(10, "km", "mi")
%   v = dlab.physics.convertUnits(300, "K", "degC")
%
%   Supported: length (m km cm mm ft in mi nmi), time (s ms min h day),
%   mass (kg g lb t), speed (m/s km/h mph kn ft/s), force (N kN lbf),
%   pressure (Pa kPa bar atm psi), energy (J kJ cal kWh), angle (rad deg
%   rev), angular rate (rad/s deg/s rpm Hz), temperature (K degC degF).
%   Converting between different kinds is an error.
arguments
    value double
    from (1,1) string
    to (1,1) string
end
if from == to
    return
end
[scaleFrom, offsetFrom, kindFrom] = lookup(from);
[scaleTo, offsetTo, kindTo] = lookup(to);
if kindFrom ~= kindTo
    error("dlab:physics:units", "Cannot convert %s (%s) to %s (%s).", from, kindFrom, to, kindTo);
end
value = ((value + offsetFrom) * scaleFrom) / scaleTo - offsetTo;
end

function [scale, offset, kind] = lookup(unit)
% Each unit: kind, factor to the SI unit, and an additive offset applied
% before scaling (temperatures only).
persistent table
if isempty(table)
    rows = {
        "m" "length" 1;  "km" "length" 1e3;  "cm" "length" 1e-2;  "mm" "length" 1e-3
        "ft" "length" 0.3048;  "in" "length" 0.0254;  "mi" "length" 1609.344;  "nmi" "length" 1852
        "s" "time" 1;  "ms" "time" 1e-3;  "min" "time" 60;  "h" "time" 3600;  "day" "time" 86400
        "kg" "mass" 1;  "g" "mass" 1e-3;  "lb" "mass" 0.45359237;  "t" "mass" 1e3
        "m/s" "speed" 1;  "km/h" "speed" 1/3.6;  "mph" "speed" 0.44704;  "kn" "speed" 1852/3600
        "ft/s" "speed" 0.3048
        "N" "force" 1;  "kN" "force" 1e3;  "lbf" "force" 4.4482216152605
        "Pa" "pressure" 1;  "kPa" "pressure" 1e3;  "bar" "pressure" 1e5;  "atm" "pressure" 101325
        "psi" "pressure" 6894.757293168
        "J" "energy" 1;  "kJ" "energy" 1e3;  "cal" "energy" 4.184;  "kWh" "energy" 3.6e6
        "rad" "angle" 1;  "deg" "angle" pi/180;  "rev" "angle" 2*pi
        "rad/s" "rate" 1;  "deg/s" "rate" pi/180;  "rpm" "rate" 2*pi/60;  "Hz" "rate" 2*pi
        "K" "temperature" 1;  "degC" "temperature" 1;  "degF" "temperature" 5/9
    };
    table = dictionary(string(rows(:, 1)), cellfun(@(kind, scale) {struct("kind", kind, "scale", scale)}, ...
        rows(:, 2), rows(:, 3)));
end
if ~isKey(table, unit)
    error("dlab:physics:units", "Unknown unit ""%s"".", unit);
end
entry = table{unit};
kind = entry.kind;
scale = entry.scale;
offset = 0;
switch unit
    case "degC"
        offset = 273.15;
    case "degF"
        offset = 459.67;
end
end
