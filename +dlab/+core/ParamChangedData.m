classdef (ConstructOnLoad) ParamChangedData < event.EventData
    %PARAMCHANGEDDATA Event data for ParamPanel.ValueChanged.

    properties
        Name (1,1) string
        OldValue
        NewValue
    end

    methods
        function data = ParamChangedData(name, oldValue, newValue)
            if nargin > 0
                data.Name = name;
                data.OldValue = oldValue;
                data.NewValue = newValue;
            end
        end
    end
end
