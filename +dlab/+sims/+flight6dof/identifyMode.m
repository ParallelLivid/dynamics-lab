function id = identifyMode(t, state, airspeed, mode, startTime, expected)
%IDENTIFYMODE Fit a dynamic mode to a simulated response.
%   id = identifyMode(t, state, airspeed, mode, startTime) fits the free
%   response after STARTTIME (the end of the excitation) with damped
%   exponentials (dlab.physics.fitDampedResponse) and reports the mode:
%
%     mode             signal         kind
%     'phugoid'        airspeed       oscillation
%     'dutchroll'      yaw rate r     oscillation
%     'rollsubsidence' roll rate p    decay
%     'spiral'         bank angle φ   slow decay or growth
%
%   The fit allows a few extra terms (a steady value, a neighbouring
%   mode), but no more than the response supports: when the fit splits a
%   real mode into a near-real pair (ζ > 0.99, gone long before one
%   cycle), it is refitted with one term fewer. Of the fitted poles of
%   the right kind, the one nearest
%   EXPECTED (a pole of the linear model, optional) is the mode, or else
%   the one with the largest amplitude.
%
%   STATE has the 12 Euler-angle columns. id: mode, signal, t, y (the
%   signal fitted), fit, ok, message, and, when ok, pole, naturalFrequency
%   (rad/s), dampingRatio, period (s, damped; NaN for real modes),
%   timeConstant (s, 1/|Re λ|), and rSquared.
if nargin < 6
    expected = NaN;
end
switch mode
    case 'phugoid'
        % Six terms: after a pitch input, airspeed also carries the faster
        % longitudinal transients (five leave the phugoid ~12 % off).
        [signal, column, poles, oscillatory] = deal('airspeed (m/s)', 0, 6, true);
    case 'dutchroll'
        [signal, column, poles, oscillatory] = deal('yaw rate r (rad/s)', 6, 5, true);
    case 'rollsubsidence'
        [signal, column, poles, oscillatory] = deal('roll rate p (rad/s)', 4, 5, false);
    case 'spiral'
        [signal, column, poles, oscillatory] = deal('bank angle φ (rad)', 7, 5, false);
    otherwise
        error('flightSim:Identify', 'Unknown mode "%s".', mode);
end
id = struct('mode', mode, 'signal', signal, 't', [], 'y', [], 'fit', [], 'ok', false, 'message', '', ...
    'pole', NaN, 'naturalFrequency', NaN, 'dampingRatio', NaN, 'period', NaN, 'timeConstant', NaN, ...
    'rSquared', NaN);
if column == 0
    values = airspeed;
else
    values = state(:, column);
end
window = t >= startTime;
% At least a second and 20 samples: shorter than any of these modes.
if nnz(window) < 20 || t(end) - startTime < 1
    id.message = 'The run ends too soon after the excitation; make it longer.';
    return
end
id.t = t(window);
id.y = values(window);
if max(abs(id.y - id.y(end))) < 1e-9 * max(1, max(abs(id.y)))
    id.message = 'There is no response to fit; excite the mode (a doublet or a pulse).';
    return
end
for n = poles:-1:1
    try
        [lambda, amplitudes, fit, rSquared] = dlab.physics.fitDampedResponse(id.t, id.y, n);
    catch failure
        id.message = failure.message;
        return
    end
    zeta = -real(lambda) ./ max(abs(lambda), eps);
    if ~any(abs(imag(lambda)) > 1e-6 & zeta > 0.99)
        break                               % no real mode split in two
    end
end
id.fit = fit;
id.rSquared = rSquared;
if oscillatory
    candidates = find(imag(lambda) > 1e-6);
else
    candidates = find(abs(imag(lambda)) <= 1e-6);
end
if isempty(candidates)
    id.message = 'The response does not show this kind of mode (oscillating or not).';
    return
end
if isfinite(expected)
    [~, k] = min(abs(lambda(candidates) - expected));
else
    [~, k] = max(abs(amplitudes(candidates)));
end
pole = lambda(candidates(k));
id.pole = pole;
id.naturalFrequency = abs(pole);
id.dampingRatio = -real(pole) / abs(pole);
if oscillatory
    id.period = 2 * pi / imag(pole);
end
id.timeConstant = 1 / max(abs(real(pole)), eps);
id.ok = rSquared > 0.9;
if ~id.ok
    id.message = sprintf('The fit is poor (R² = %.2f); excite the mode more cleanly or run longer.', rSquared);
end
end
