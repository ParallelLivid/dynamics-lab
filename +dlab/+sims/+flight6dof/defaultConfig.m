function config = defaultConfig(presetName)
%DEFAULTCONFIG Return simulator settings and a named flight preset.
%   "Straight flight" (and the mode presets built on it) is trimmed for level
%   flight at 20 m/s and 100 m in the ISA atmosphere: angle of attack
%   0.0261044803493 rad (= pitch), throttle 0.6109817636934, and alpha_trim
%   equal to the effective angle of attack, so the forces and the pitching
%   moment balance. The "Phugoid mode" keeps that attitude at 23 m/s.

    if nargin == 0
        presetName = 'Straight flight';
    end

    config.sim.TIMEOUT = 30;
    config.sim.MAX_PTS = 2000;
    config.sim.Vmax = 300;
    config.sim.groundAltitude = 0;
    config.sim.attitudeLimitDeg = 85;
    config.sim.RelTol = 1e-4;
    config.sim.AbsTol = 1e-6;
    config.sim.MaxStep = 0.1;
    config.sim.Solver = 'ode45';

    config.aircraft = struct( ...
        'm', 1.0, 'Ix', 0.02, 'Iy', 0.02, 'Iz', 0.04, ...
        'S', 0.5, 'Tmax', 20.0, 'CLa', 3.0, 'CD0', 0.1, ...
        'CDa2', 1.0, 'CLmax', 1.5, 'Kctrl', 1.0, ...
        'damp_p', 1.5, 'damp_q', 2.0, 'damp_r', 1.5, ...
        'alpha_trim', 0.02609907456477, 'pitch_alpha', 6.0, ...
        'roll_beta', 0.8, 'yaw_beta', 4.0);

    config.graphs = struct('show3d', true, 'showAirspeed', true, ...
        'showAlt', true, 'showEuler', false, 'showRates', false, ...
        'showGT', false);
    config.duration = 20;

    switch lower(string(presetName))
        case "straight flight"
            config.initial = initialState( ...
                19.993185948, 0.52203031321, 1.4956765504, 100);
            config.control = controlInput(0.6109817636934);
        case "glide"
            config.aircraft.pitch_alpha = 0;
            config.initial = initialState(18, 0.594, 0, 100);
            config.control = controlInput(0);
        case "phugoid mode"
            config.duration = 120;
            config.aircraft.CD0 = 0.02;
            config.aircraft.CDa2 = 0.2;
            config.initial = initialState( ...
                23*cos(0.0261044803493), 23*sin(0.0261044803493), ...
                1.4956765504, 100);
            config.control = controlInput(0.1219);
        case "short-period mode"
            config.duration = 15;
            config.aircraft.damp_q = 0.2;
            config.graphs.showEuler = true;
            config.graphs.showRates = true;
            config.initial = initialState( ...
                19.993185948, 0.52203031321, 1.4956765504, 100);
            config.initial.q0 = 0.25;
            config.control = controlInput(0.6109817636934);
        case "dutch roll mode"
            config.duration = 20;
            config.graphs.showEuler = true;
            config.graphs.showRates = true;
            config.graphs.showGT = true;
            config.initial = initialState( ...
                19.993185948, 0.52203031321, 1.4956765504, 100);
            config.initial.v0 = 2;
            config.initial.r0 = 0.25;
            config.control = controlInput(0.6109817636934);
        case "roll subsidence mode"
            config.duration = 6;
            config.graphs.showEuler = true;
            config.graphs.showRates = true;
            config.initial = initialState( ...
                19.993185948, 0.52203031321, 1.4956765504, 100);
            config.initial.p0 = 0.5;
            config.control = controlInput(0.6109817636934);
        otherwise
            error('flightSim:UnknownPreset', 'Unknown preset: %s', presetName);
    end
    config.preset = char(presetName);
end

function initial = initialState(u, w, pitchDeg, altitude)
    initial = struct('u0', u, 'v0', 0, 'w0', w, ...
        'p0', 0, 'q0', 0, 'r0', 0, 'phi0', 0, ...
        'theta0', pitchDeg, 'psi0', 0, 'alt0', altitude);
end

function control = controlInput(throttle)
    control = struct('throttle', throttle, 'elevator', 0, ...
        'aileron', 0, 'rudder', 0);
end
