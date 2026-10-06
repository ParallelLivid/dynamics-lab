function [T, saturated] = mixer(wrench, model)
%MIXER Rotor thrusts for a wanted [F; τx; τy; τz], within 0 ≤ Tᵢ ≤ Tmax.
%   [T, saturated] = mixer(wrench, model) inverts the allocation matrix
%   (see airframe) and, when that asks for more than the rotors can give,
%   gives up in this order of priority:
%
%     1. roll and pitch torque (kept; scaled down only if the spread they
%        need between rotors exceeds Tmax)
%     2. collective thrust (shifted down or up so roll and pitch fit)
%     3. yaw torque (scaled down, from 1 to 0, until every rotor fits)
%
%   Without saturation it is the exact inverse, so equal rotor thrusts
%   F/4 give pure lift. SATURATED is true when anything was given up.
Tmax = model.Tmax;
F = min(max(wrench(1), 0), 4 * Tmax);
saturated = F ~= wrench(1);
base = F / 4;
rollPitch = model.Ainv(:, 2:3) * wrench(2:3);
yaw = model.Ainv(:, 4) * wrench(4);

spread = max(rollPitch) - min(rollPitch);
if spread > Tmax
    rollPitch = rollPitch * (Tmax / spread);
    saturated = true;
end
high = base + max(rollPitch) - Tmax;
low = base + min(rollPitch);
if high > 0
    base = base - high;
    saturated = true;
elseif low < 0
    base = base - low;
    saturated = true;
end
u = base + rollPitch;

k = 1;
for i = 1:4
    if yaw(i) > 0
        k = min(k, (Tmax - u(i)) / yaw(i));
    elseif yaw(i) < 0
        k = min(k, u(i) / -yaw(i));
    end
end
k = max(k, 0);
saturated = saturated || k < 1;
T = min(max(u + k * yaw, 0), Tmax);
end
