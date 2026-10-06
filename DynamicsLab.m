function app = DynamicsLab(simulatorId, options)
%DYNAMICSLAB Open Dynamics Lab.
%   DynamicsLab                           open the Home screen
%   DynamicsLab("pendulum")               open a simulator directly
%   DynamicsLab(Scenario="my.json")       open a saved scenario in its simulator
%   app = DynamicsLab(...)                also return the dlab.core.Shell
%
%   Options (mainly for tests and scripting):
%     Scenario="file.json"      load this scenario (opens its simulator)
%     Theme="light"             override the saved theme for this session
%     Visible=false             build the window without showing it
%     Plugins={@MyPlugin}       use these plugins instead of the registry
%
%   To solve without the window, see dlab.run and dlab.sweep.
arguments
    simulatorId (1,1) string = ""
    options.Scenario (1,1) string = ""
    options.Theme (1,1) string = ""
    options.Visible (1,1) logical = true
    options.Plugins cell = dlab.sims.registry()
end
shell = dlab.core.Shell(Plugins=options.Plugins, Theme=options.Theme, Visible=options.Visible);
if options.Scenario ~= "" && simulatorId == ""
    simulatorId = dlab.core.ScenarioIO.read(options.Scenario).simulator;
end
if simulatorId ~= ""
    shell.open(simulatorId);
end
if options.Scenario ~= ""
    shell.View.loadScenario(options.Scenario, Confirm=false);
end
if nargout > 0
    app = shell;
end
if isdeployed
    % A compiled app exits when this function returns; keep it alive
    % until the window closes.
    waitfor(shell.Figure);
end
end
