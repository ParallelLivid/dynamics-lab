function T = sweep(simulatorId, name, values, varargin)
%SWEEP Solve a simulator for a range of one input and tabulate the results.
%   T = dlab.sweep("projectile", "theta", 5:5:85)
%   T = dlab.sweep("pendulum", "theta0", linspace(5, 175, 18), b=0)
%   T = dlab.sweep("projectile", "theta", 10:10:80, Preset="Baseball")
%
%   Each row holds the swept value and the run's key results (the numeric
%   rows of its Summary); VariableUnits holds the units and the "error"
%   column explains any run that failed. Results with many values per
%   run (Poincaré points, for a bifurcation diagram) are in
%   T.Properties.UserData.Sets, one value per row:
%
%       T = dlab.sweep("nonlinear", "A", linspace(0.9, 1.5, 120), model="pendulum");
%       S = T.Properties.UserData.Sets;
%       plot(S.A, S.Value, ".") Other inputs are set as in
%   dlab.run (defaults, Preset=, Scenario=, and name/value pairs).
%
%   See also dlab.run, dlab.simulators.
arguments
    simulatorId (1,1) string
    name (1,1) string
    values (1,:) double
end
arguments (Repeating)
    varargin
end
preset = "";
scenario = "";
overrides = {};
for k = 1:2:numel(varargin)
    option = string(varargin{k});
    if k + 1 > numel(varargin)
        error("dlab:run:overrides", "Input ""%s"" has no value.", option);
    elseif option == "Preset"
        preset = string(varargin{k + 1});
    elseif option == "Scenario"
        scenario = string(varargin{k + 1});
    else
        overrides(end+1:end+2) = {option, varargin{k + 1}};
    end
end
plugin = dlab.core.Headless.plugin(simulatorId, dlab.sims.registry());
cleanup = onCleanup(@() delete(plugin));
params = dlab.core.Headless.params(plugin, overrides, Preset=preset, Scenario=scenario);
S = dlab.core.Sweep.run(plugin, params, name, values(:));
T = dlab.core.Sweep.toTable(S);
T.Properties.UserData = struct("Sets", dlab.core.Sweep.toLongTable(S));
end
