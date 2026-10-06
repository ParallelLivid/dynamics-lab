classdef Settings
    %SETTINGS Small persistent preferences (settings.json in user data).
    %
    %       name = dlab.core.Settings.get("theme", "dark");
    %       dlab.core.Settings.set("theme", "light");

    methods (Static)
        function value = get(name, default)
            arguments
                name (1,1) string
                default = []
            end
            all = dlab.core.Settings.readAll();
            if isfield(all, name)
                value = all.(name);
            else
                value = default;
            end
        end

        function set(name, value)
            arguments
                name (1,1) string {mustBeValidVariableName}
                value
            end
            all = dlab.core.Settings.readAll();
            all.(name) = value;
            fid = fopen(dlab.core.Paths.settingsFile(), "w", "n", "UTF-8");
            assert(fid > 0, "dlab:settings:write", "Cannot write settings file.");
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(all, PrettyPrint=true), "char");
        end
    end

    methods (Static, Access = private)
        function all = readAll()
            all = struct();
            file = dlab.core.Paths.settingsFile();
            if ~isfile(file)
                return
            end
            try
                decoded = jsondecode(fileread(file, Encoding="UTF-8"));
                if isstruct(decoded)
                    all = decoded;
                end
            catch
                % A corrupt settings file must never stop the app starting.
            end
        end
    end
end
