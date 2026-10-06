classdef ProgressRecorder < handle
    %PROGRESSRECORDER Stand-in for the shell's progress callback in tests:
    %   records every fraction and asks to stop once StopAt is reached.

    properties
        Fractions (1,:) double = []
        StopAt (1,1) double = Inf
    end

    methods
        function stop = report(obj, fraction)
            obj.Fractions(end+1) = fraction;
            stop = fraction >= obj.StopAt;
        end
    end
end
