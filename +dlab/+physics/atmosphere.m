function [density, temperature, pressure, soundSpeed] = atmosphere(altitude, varargin)
%ATMOSPHERE International Standard Atmosphere (ISA, 1976) up to 86 km.
%   [rho, T, p, a] = dlab.physics.atmosphere(h)
%   [rho, T, p, a] = dlab.physics.atmosphere(h, Extended=true)
%
%   h is the geometric altitude in metres (any array; values are clamped
%   to [-1000, 86000] m). Returns density (kg/m³), temperature (K),
%   pressure (Pa), and the speed of sound (m/s), each the size of h.
%
%   With Extended=true, pressure and density keep falling above 86 km as
%   an isothermal layer at the 86 km temperature (scale height about
%   5.5 km). That is a rough model of the thermosphere, adequate where
%   drag is negligible anyway (rocket ascent above about 100 km).
%   Temperature and the speed of sound there follow the kinetic
%   temperature of the U.S. Standard Atmosphere 1976 (NOAA/NASA/USAF,
%   NASA-TM-X-74335): constant to 91 km, then an ellipse to 240 K at
%   110 km, a line to 360 K at 120 km, and an exponential towards 1000 K,
%   shifted by −2.2 K to join this model's 86 km value. The speed of
%   sound keeps sea-level air's γ and R; the falling molecular weight
%   above about 100 km is neglected, so it is low by about 5 % at 120 km
%   and 10 % at 150 km. Density and pressure keep the isothermal fall, so
%   above 86 km ρ = p/(RT) only with the 86 km temperature.
%
%   The layers use the standard lapse rates; the difference between
%   geometric and geopotential altitude is neglected (< 1.4 % at 86 km).
%   Cheap enough to call inside an ODE right-hand side.
persistent layers
if isempty(layers)
    layers = layerTable();
end
extended = false;
for k = 1:2:numel(varargin) - 1
    if strcmpi(varargin{k}, "Extended")
        extended = logical(varargin{k + 1});
    else
        error("dlab:physics:atmosphere", "Unknown option ""%s"".", string(varargin{k}));
    end
end
h = min(max(altitude, -1000), layers.Base(end));
k = discretize(h, [-Inf layers.Base(2:end-1) Inf]);    % layer index of each altitude
% Reshaped to h's size: indexing a row with a column index gives a row.
T0 = reshape(layers.T(k), size(h));
p0 = reshape(layers.P(k), size(h));
L = reshape(layers.Lapse(k), size(h));
dh = h - reshape(layers.Base(k), size(h));
temperature = T0 + L .* dh;
isothermal = L == 0;
pressure = zeros(size(h));
pressure(isothermal) = p0(isothermal) .* exp(-layers.G0 * dh(isothermal) ./ (layers.R * T0(isothermal)));
pressure(~isothermal) = p0(~isothermal) .* (temperature(~isothermal) ./ T0(~isothermal)) ...
    .^ (-layers.G0 ./ (layers.R * L(~isothermal)));
temperature = reshape(temperature, size(h));
pressure = reshape(pressure, size(h));
above = extended & altitude > layers.Base(end);
if any(above(:))
    scaleHeight = layers.R * temperature(above) / layers.G0;
    pressure(above) = pressure(above) .* exp(-(altitude(above) - layers.Base(end)) ./ scaleHeight);
end
density = pressure ./ (layers.R * temperature);
if any(above(:))
    temperature(above) = kineticTemperature(altitude(above) / 1000, layers.T86);
end
soundSpeed = sqrt(1.4 * layers.R * temperature);
end

function T = kineticTemperature(z, T86)
% U.S. Standard Atmosphere 1976 above 86 km (z, geometric km), shifted so
% that it starts from T86 (this model's 86 km temperature).
T = 186.8673 * ones(size(z));
ellipse = z > 91 & z <= 110;
T(ellipse) = 263.1905 - 76.3232 * sqrt(1 - ((z(ellipse) - 91) / 19.9429) .^ 2);
linear = z > 110 & z <= 120;
T(linear) = 240 + 12 * (z(linear) - 110);
upper = z > 120;
r0 = 6356.766;                                   % the standard's Earth radius, km
xi = (z(upper) - 120) * (r0 + 120) ./ (r0 + z(upper));
T(upper) = 1000 - 640 * exp(-0.01875 * xi);
T = T + (T86 - 186.8673);
end

function layers = layerTable()
% Base altitude (m), lapse rate (K/m), and the temperature and pressure at
% each layer's base, integrated up from sea level.
R = 287.05287;          % specific gas constant of dry air, J/(kg·K)
g0 = 9.80665;           % standard gravity, m/s²
base = [0 11000 20000 32000 47000 51000 71000 86000];
lapse = [-0.0065 0 0.001 0.0028 0 -0.0028 -0.002];
T = zeros(1, numel(lapse));
P = zeros(1, numel(lapse));
T(1) = 288.15;
P(1) = 101325;
for k = 1:numel(lapse) - 1
    dh = base(k + 1) - base(k);
    T(k + 1) = T(k) + lapse(k) * dh;
    if lapse(k) == 0
        P(k + 1) = P(k) * exp(-g0 * dh / (R * T(k)));
    else
        P(k + 1) = P(k) * (T(k + 1) / T(k)) ^ (-g0 / (R * lapse(k)));
    end
end
T86 = T(end) + lapse(end) * (base(end) - base(end - 1));
layers = struct("Base", base, "Lapse", lapse, "T", T, "P", P, "R", R, "G0", g0, "T86", T86);
end
