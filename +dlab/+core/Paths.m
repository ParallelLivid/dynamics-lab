classdef Paths
    %PATHS Where Dynamics Lab reads resources and writes user data.
    %   Nothing is ever written next to the code: a compiled app's install
    %   folder is read-only. User data lives in Documents\DynamicsLab,
    %   overridable with the DYNAMICSLAB_USERDATA environment variable
    %   (tests point it at a temporary folder).

    properties (Constant)
        EnvironmentVariable = "DYNAMICSLAB_USERDATA"
    end

    methods (Static)
        function folder = userData()
            folder = string(getenv(dlab.core.Paths.EnvironmentVariable));
            if folder == ""
                folder = fullfile(dlab.core.Paths.documents(), "DynamicsLab");
            end
            dlab.core.Paths.ensure(folder);
        end

        function folder = scenarios(simulatorId)
            arguments
                simulatorId (1,1) string
            end
            folder = dlab.core.Paths.ensure(fullfile(dlab.core.Paths.userData(), "scenarios", simulatorId));
        end

        function folder = exports()
            folder = dlab.core.Paths.ensure(fullfile(dlab.core.Paths.userData(), "exports"));
        end

        function folder = logs()
            folder = dlab.core.Paths.ensure(fullfile(dlab.core.Paths.userData(), "logs"));
        end

        function folder = session()
            %SESSION The inputs each simulator was last left with.
            folder = dlab.core.Paths.ensure(fullfile(dlab.core.Paths.userData(), "session"));
        end

        function folder = lessons()
            %LESSONS The user's own lesson files (shipped ones are in resources).
            folder = dlab.core.Paths.ensure(fullfile(dlab.core.Paths.userData(), "lessons"));
        end

        function file = settingsFile()
            file = fullfile(dlab.core.Paths.userData(), "settings.json");
        end

        function folder = resources()
            %RESOURCES Read-only assets shipped with the app (inside the
            %   CTF archive when compiled; mfilename resolves there too).
            repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            folder = string(fullfile(repoRoot, "resources"));
        end

        function file = thumbnail(simulatorId, themeName)
            %THUMBNAIL A simulator's card image for the theme ("<id>-dark.png"),
            %   else "<id>.png", else "".
            arguments
                simulatorId (1,1) string
                themeName (1,1) string = "dark"
            end
            folder = fullfile(dlab.core.Paths.resources(), "thumbnails");
            for name = [simulatorId + "-" + themeName, simulatorId] + ".png"
                file = fullfile(folder, name);
                if isfile(file)
                    return
                end
            end
            file = "";
        end
    end

    methods (Static, Access = private)
        function folder = documents()
            if ispc
                try
                    % Honors Documents redirection (e.g. into OneDrive).
                    folder = string(winqueryreg("HKEY_CURRENT_USER", ...
                        "Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders", "Personal"));
                catch
                    folder = "";
                end
                if folder == ""
                    folder = fullfile(string(getenv("USERPROFILE")), "Documents");
                end
            else
                folder = fullfile(string(getenv("HOME")), "Documents");
            end
        end

        function folder = ensure(folder)
            if ~isfolder(folder)
                mkdir(folder);
            end
        end
    end
end
