classdef (Abstract) TimeDomainPlugin < dlab.core.Plugin
    %TIMEDOMAINPLUGIN A simulator whose result evolves in time.
    %   The shell adds an "Animation" tab with a playback bar and calls
    %   drawFrame for each playback tick.

    methods (Abstract)
        t = timeVector(obj, result)
        %TIMEVECTOR Column of sample times for RESULT.

        buildAnimation(obj, parent, theme)
        %BUILDANIMATION Create the animation graphics inside PARENT
        %   (an empty uigridlayout).

        drawFrame(obj, simTime)
        %DRAWFRAME Update the animation for playback time SIMTIME.
        %   Called up to ~30 times per second; update existing graphics
        %   objects (XData, YData, ...) rather than replotting. Use
        %   dlab.core.frameAt to pick the sample.
    end

    methods
        function kind = kind(~)
            kind = "time";
        end

        function buildPlaybackControls(~, ~, ~)
            %BUILDPLAYBACKCONTROLS Optional controls placed in the playback
            %   bar (e.g. Orbit's 3D / 2D projection selector).
        end

        function rate = playbackRate(~, ~)
            %PLAYBACKRATE Simulated seconds per wall-clock second at 1×.
            %   1 = real time. Long simulations (an orbit lasting hours)
            %   return more, e.g. duration / 20 to play in about 20 s.
            rate = 1;
        end
    end
end
