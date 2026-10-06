function file = buildToolbox(options)
%BUILDTOOLBOX Package Dynamics Lab as an installable MATLAB toolbox (.mltbx).
%   dlab.dev.buildToolbox                  dist/toolbox/DynamicsLab.mltbx
%   Also available as "buildtool toolbox".
%
%   Base MATLAB only. Installing the file (double-click, or
%   matlab.addons.install) puts DynamicsLab on the path; type DynamicsLab
%   to start. Attach it to a GitHub release; File Exchange picks it up from
%   there when the repository is linked.
arguments
    options.OutputDir (1,1) string = string(fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "dist"))
end
% Keep this identifier for every release: MATLAB uses it to upgrade an
% installed copy in place rather than install a second one.
identifier = "2c5c2959-f5f3-4fe9-91b9-c44728adc353";
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
resources = fullfile(root, "resources");
if ~isfile(fullfile(resources, "icon.png"))
    dlab.dev.generateBranding();
end

% What the app needs to run, and nothing else: no tests, docs, or dev tools.
code = dir(fullfile(root, "+dlab", "**", "*.m"));
code(contains({code.folder}, fullfile("+dlab", "+dev"))) = [];
assets = dir(fullfile(resources, "**", "*.*"));
assets([assets.isdir]) = [];
files = [fullfile(string({code.folder}), string({code.name})), ...
    fullfile(string({assets.folder}), string({assets.name})), ...
    fullfile(root, ["DynamicsLab.m" "README.md"])];
if isfile(fullfile(root, "LICENSE"))
    files(end+1) = fullfile(root, "LICENSE");
end

opts = matlab.addons.toolbox.ToolboxOptions(root, identifier, ...
    ToolboxName="Dynamics Lab", ...
    ToolboxVersion=dlab.version(), ...
    Summary="27 interactive physics and engineering simulators in one app", ...
    Description="Mechanics, controls and vehicles, aerospace, structures, and continuum " + ...
        "simulators with one interface: animations, plots, sweeps, maps, optimization, " + ...
        "Monte Carlo, modes, Bode plots, and guided lessons. Type DynamicsLab to start.", ...
    AuthorName="Nathan Peterson", ...
    ToolboxImageFile=fullfile(resources, "icon.png"), ...
    ToolboxFiles=files, ...
    ToolboxMatlabPath=root, ...
    MinimumMatlabRelease="R2025b", ...
    OutputFile=fullfile(options.OutputDir, "toolbox", "DynamicsLab.mltbx"));
if ~isfolder(fullfile(options.OutputDir, "toolbox"))
    mkdir(fullfile(options.OutputDir, "toolbox"));
end
matlab.addons.toolbox.packageToolbox(opts);
file = opts.OutputFile;
fprintf("Toolbox: %s (%d files)\n", file, numel(files));
end
