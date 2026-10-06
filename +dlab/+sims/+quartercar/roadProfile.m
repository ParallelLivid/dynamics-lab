function [z, slope] = roadProfile(road, s)
%ROADPROFILE Road height z (m) and slope dz/ds at distances S (m).
%   road.type: 'bump' | 'pothole' | 'step' | 'sine' | 'random', with
%     height (m), length (m, bump and pothole), start (m, where the
%     feature begins), wavelength (m, sine), isoClass (1–8 for ISO 8608
%     classes A–H, random), and seed (random).
%
%   Random roads follow ISO 8608: displacement PSD G(n) = G(n0) (n/n0)^−2
%   with n0 = 0.1 cycles/m and G(n0) = 16·4^(class−1) × 10⁻⁶ m³, built as
%   200 cosines at log-spaced spatial frequencies (0.011–2.83 cycles/m)
%   with phases from a fixed-seed generator, so a seed gives one road. It
%   is shifted to start at height 0, so the road has no step.
z = zeros(size(s));
slope = zeros(size(s));
switch lower(road.type)
    case {'bump', 'pothole'}
        direction = 1 - 2 * strcmpi(road.type, 'pothole');
        inside = s >= road.start & s <= road.start + road.length;
        phase = pi * (s(inside) - road.start) / road.length;
        z(inside) = direction * road.height * sin(phase);
        slope(inside) = direction * road.height * pi / road.length * cos(phase);
    case 'step'
        % A raised-cosine ramp over 5 cm (a kerb), so the slope stays finite.
        ramp = 0.05;
        inside = s >= road.start & s < road.start + ramp;
        after = s >= road.start + ramp;
        phase = pi * (s(inside) - road.start) / ramp;
        z(inside) = road.height * (1 - cos(phase)) / 2;
        slope(inside) = road.height * pi / ramp * sin(phase) / 2;
        z(after) = road.height;
    case 'sine'
        on = s >= road.start;
        z(on) = road.height * sin(2 * pi * (s(on) - road.start) / road.wavelength);
        slope(on) = road.height * 2 * pi / road.wavelength * cos(2 * pi * (s(on) - road.start) / road.wavelength);
    case 'random'
        [amplitude, frequency, phase] = randomRoad(road);
        on = s >= road.start;
        distance = s(on);
        angles = 2 * pi * frequency(:) * (distance(:)' - road.start) + phase(:);
        level = sum(amplitude(:) .* cos(phase(:)));      % the height at the start, taken off
        z(on) = (amplitude(:)' * cos(angles))' - level;
        slope(on) = (-(amplitude(:) .* 2 .* pi .* frequency(:))' * sin(angles))';
    otherwise
        error('quartercar:InvalidParameter', 'Unknown road type "%s".', road.type);
end
end

function [amplitude, frequency, phase] = randomRoad(road)
count = 200;
edges = logspace(log10(0.011), log10(2.83), count + 1);
frequency = sqrt(edges(1:end-1) .* edges(2:end));
bandwidth = diff(edges);
n0 = 0.1;
G0 = 16 * 4^(road.isoClass - 1) * 1e-6;
G = G0 * (frequency / n0).^-2;
amplitude = sqrt(2 * G .* bandwidth);
phase = 2 * pi * dlab.physics.uniformSequence(road.seed, count);
end
