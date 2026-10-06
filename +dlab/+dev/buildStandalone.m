function results = buildStandalone(options)
%BUILDSTANDALONE Compile Dynamics Lab into a Windows app and an installer.
%   dlab.dev.buildStandalone                 build dist/app and dist/installer
%   dlab.dev.buildStandalone(Installer=false)  the executable only
%   Also available as "buildtool package".
%
%   Needs MATLAB Compiler (Home > Add-Ons). End users need only the free
%   MATLAB Runtime for this MATLAB release; the installer downloads it
%   ("web" delivery). Test the result on a PC without MATLAB installed.
arguments
    options.Installer (1,1) logical = true
    options.OutputDir (1,1) string = string(fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "dist"))
end
if ~license("test", "Compiler") || isempty(ver("compiler"))
    error("dlab:dev:noCompiler", ['MATLAB Compiler is not installed. Install it from ' ...
        'Home > Add-Ons > Get Add-Ons ("MATLAB Compiler"); your license includes it.']);
end
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
resources = fullfile(root, "resources");
% The splash shows the version, so draw it for this one (and the icon if missing).
dlab.dev.generateBranding(Icon=~isfile(fullfile(resources, "icon.png")));

% The registry lists plugins as function handles, so dependency analysis
% finds every simulator; resources (thumbnails, icon) are added explicitly.
% The dev tools (this file among them) cannot run in the MATLAB Runtime.
code = dir(fullfile(root, "+dlab"));
code = string({code.name});
code(startsWith(code, ".") | code == "+dev") = [];
buildOptions = compiler.build.StandaloneApplicationOptions(fullfile(root, "DynamicsLab.m"), ...
    ExecutableName="DynamicsLab", ...
    ExecutableVersion=dlab.version(), ...
    ExecutableIcon=fullfile(resources, "icon.png"), ...
    ExecutableSplashScreen=fullfile(resources, "splash.png"), ...
    AdditionalFiles=[fullfile(root, "+dlab", code), resources], ...
    OutputDir=fullfile(options.OutputDir, "app"), ...
    Verbose="off");
fprintf("Compiling Dynamics Lab %s ...\n", dlab.version());
results = compiler.build.standaloneWindowsApplication(buildOptions);
fprintf("Executable: %s\n", fullfile(options.OutputDir, "app", "DynamicsLab.exe"));

if options.Installer
    compiler.package.installer(results, ...
        ApplicationName="Dynamics Lab", ...
        Version=dlab.version(), ...
        Summary="Interactive physics simulators", ...
        RuntimeDelivery="web", ...
        InstallerName="DynamicsLabInstaller", ...
        OutputDir=fullfile(options.OutputDir, "installer"));
    fprintf("Installer: %s\n", fullfile(options.OutputDir, "installer"));
end
end
