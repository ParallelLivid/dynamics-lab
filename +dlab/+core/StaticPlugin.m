classdef (Abstract) StaticPlugin < dlab.core.Plugin
    %STATICPLUGIN A solver with no time axis (e.g. the truss solver).
    %   No playback bar. previewInputs lets the plugin draw its model
    %   while the user edits, before anything is solved.

    methods
        function previewInputs(~, ~)
            %PREVIEWINPUTS Draw PARAMS (the unsolved model). Called after
            %   buildOutputs and after every input change.
        end
    end
end
