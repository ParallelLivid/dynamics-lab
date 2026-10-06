classdef (ConstructOnLoad) StatusData < event.EventData
    %STATUSDATA Event data for a custom input panel's StatusMessage event:
    %   the view shows Message in the status bar at Level
    %   ("info" | "success" | "warning" | "error").

    properties
        Message (1,1) string = ""
        Level (1,1) string = "info"
    end

    methods
        function data = StatusData(message, level)
            if nargin > 0
                data.Message = message;
            end
            if nargin > 1
                data.Level = level;
            end
        end
    end
end
