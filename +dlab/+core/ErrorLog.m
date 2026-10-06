classdef ErrorLog
    %ERRORLOG Turn errors into user messages and keep a diagnostic log.
    %   The compiled app has no console, so every unexpected error is
    %   appended, with its full stack, to logs\dynamicslab.log.

    methods (Static)
        function message = userMessage(ME)
            %USERMESSAGE Short text for the status bar or an alert.
            message = string(ME.message);
            if ~dlab.core.ErrorLog.isExpected(ME)
                message = "Unexpected error: " + message;
            end
        end

        function tf = isExpected(ME)
            %ISEXPECTED Errors raised deliberately for the user (bad input).
            tf = startsWith(string(ME.identifier), "dlab:");
        end

        function file = write(ME, context)
            %WRITE Append ME, with stack, to the log. Never throws.
            arguments
                ME (1,1) MException
                context (1,1) string = ""
            end
            file = "";
            try
                file = fullfile(dlab.core.Paths.logs(), "dynamicslab.log");
                fid = fopen(file, "a", "n", "UTF-8");
                if fid < 0
                    return
                end
                closer = onCleanup(@() fclose(fid));
                fprintf(fid, "==== %s  %s  (Dynamics Lab %s, MATLAB %s)\n", ...
                    string(datetime("now", Format="yyyy-MM-dd HH:mm:ss")), context, ...
                    dlab.version(), version("-release"));
                fprintf(fid, "%s\n\n", getReport(ME, "extended", "hyperlinks", "off"));
            catch
                % Logging must never raise a second error.
            end
        end
    end
end
