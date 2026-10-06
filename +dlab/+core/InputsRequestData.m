classdef (ConstructOnLoad) InputsRequestData < event.EventData
    %INPUTSREQUESTDATA Event data for Plugin.InputsRequested: the inputs a
    %   plugin asks the view to set, and a label for the status bar and
    %   the undo history (e.g. "Use optimal angle").

    properties
        Changes struct = struct()
        Label (1,1) string = ""
    end

    methods
        function data = InputsRequestData(changes, label)
            if nargin > 0
                data.Changes = changes;
                data.Label = label;
            end
        end
    end
end
