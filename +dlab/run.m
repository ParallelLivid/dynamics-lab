function out = run(simulatorId, varargin)
%RUN Solve a Dynamics Lab simulator from code, without the window.
%   out = dlab.run("pendulum")                          default inputs
%   out = dlab.run("pendulum", theta0=60, L=2)          change some inputs
%   out = dlab.run("projectile", Preset="Baseball")     start from a preset
%   out = dlab.run("orbit", Scenario="leo.json")        start from a scenario file
%
%   Inputs use the names shown in each simulator's scenario files (the
%   ParamSpec names; dlab.simulators lists them). Values are checked
%   exactly as in the app. OUT has fields:
%     Simulator   the simulator id
%     Params      the inputs used
%     Result      the engine's raw result
%     Data        the sampled results as a table (the CSV export)
%     Summary     key results (the Summary tab)
%     Metrics     the numeric key results (Quantity, Value, Units)
%
%   See also dlab.sweep, dlab.simulators, DynamicsLab.
arguments
    simulatorId (1,1) string
end
arguments (Repeating)
    varargin
end
[preset, scenario, overrides] = splitOptions(varargin);
plugin = dlab.core.Headless.plugin(simulatorId, dlab.sims.registry());
cleanup = onCleanup(@() delete(plugin));
params = dlab.core.Headless.params(plugin, overrides, Preset=preset, Scenario=scenario);
out = dlab.core.Headless.solve(plugin, params);
end

function [preset, scenario, rest] = splitOptions(args)
preset = "";
scenario = "";
rest = {};
for k = 1:2:numel(args)
    name = string(args{k});
    if k + 1 > numel(args)
        error("dlab:run:overrides", "Input ""%s"" has no value.", name);
    end
    switch name
        case "Preset"
            preset = string(args{k + 1});
        case "Scenario"
            scenario = string(args{k + 1});
        otherwise
            rest(end+1:end+2) = {name, args{k + 1}};
    end
end
end
