classdef PlaybackController < handle
    %PLAYBACKCONTROLLER The one animation clock used by every simulator.
    %   Playback time advances with wall-clock time multiplied by Speed, so
    %   real-time speed stays correct when frames are dropped on a slow
    %   machine. Listeners receive TimeChanged and redraw for obj.Time.
    %
    %   The clock is injectable and the timer optional, so tests can drive
    %   tick() deterministically:
    %
    %       now = 0;
    %       pc = dlab.core.PlaybackController(Clock=@() now, UseTimer=false);
    %       pc.load(0, 10); pc.play(); now = 0.5; pc.tick();   % pc.Time == 0.5

    events
        TimeChanged    % obj.Time changed (tick, seek, load, restart)
        StateChanged   % IsPlaying changed
    end

    properties
        Speed (1,1) double {mustBePositive} = 1
        TimeScale (1,1) double {mustBePositive} = 1   % simulated seconds per wall second at 1×
        Loop (1,1) logical = false
        OnError function_handle = @(ME) rethrow(ME)  % shell routes timer errors here
    end

    properties (SetAccess = private)
        Time (1,1) double = 0
        StartTime (1,1) double = 0
        EndTime (1,1) double = 0
        IsPlaying (1,1) logical = false
    end

    properties (Constant)
        FramePeriod = 0.033                  % ~30 fps
        Speeds = [0.25 0.5 1 2 4 8]
        TimerTag = "dlab.playback"
    end

    properties (Access = private)
        Clock function_handle
        UseTimer (1,1) logical
        Timer = []
        LastTick (1,1) double = NaN
    end

    methods
        function obj = PlaybackController(options)
            arguments
                options.Clock (1,1) function_handle = dlab.core.PlaybackController.wallClock()
                options.UseTimer (1,1) logical = true
            end
            obj.Clock = options.Clock;
            obj.UseTimer = options.UseTimer;
        end

        function load(obj, startTime, endTime)
            %LOAD Stop and rewind to a new time span.
            arguments
                obj
                startTime (1,1) double {mustBeFinite}
                endTime (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(endTime, startTime)}
            end
            obj.pause();
            obj.StartTime = startTime;
            obj.EndTime = endTime;
            obj.setTime(startTime);
        end

        function play(obj)
            if obj.IsPlaying || obj.EndTime <= obj.StartTime
                return
            end
            if obj.Time >= obj.EndTime
                obj.setTime(obj.StartTime);   % play from the end restarts
            end
            obj.LastTick = obj.Clock();
            obj.IsPlaying = true;
            if obj.UseTimer
                obj.Timer = timer(ExecutionMode="fixedRate", Period=obj.FramePeriod, ...
                    BusyMode="drop", Tag=obj.TimerTag, Name="Dynamics Lab playback", ...
                    TimerFcn=@(~, ~) obj.onTimer());
                start(obj.Timer);
            end
            notify(obj, "StateChanged");
        end

        function pause(obj)
            obj.stopTimer();
            if obj.IsPlaying
                obj.IsPlaying = false;
                notify(obj, "StateChanged");
            end
        end

        function toggle(obj)
            if obj.IsPlaying
                obj.pause();
            else
                obj.play();
            end
        end

        function restart(obj)
            obj.setTime(obj.StartTime);
            obj.LastTick = obj.Clock();
        end

        function seek(obj, t)
            obj.setTime(min(max(t, obj.StartTime), obj.EndTime));
            obj.LastTick = obj.Clock();
        end

        function tick(obj)
            %TICK Advance by the wall time elapsed since the previous tick.
            if ~obj.IsPlaying
                return
            end
            now = obj.Clock();
            elapsed = now - obj.LastTick;
            obj.LastTick = now;
            t = obj.Time + elapsed * obj.Speed * obj.TimeScale;
            if t >= obj.EndTime
                if obj.Loop
                    span = obj.EndTime - obj.StartTime;
                    t = obj.StartTime + mod(t - obj.StartTime, span);
                else
                    obj.setTime(obj.EndTime);
                    obj.pause();
                    return
                end
            end
            obj.setTime(t);
        end

        function delete(obj)
            obj.stopTimer();
        end
    end

    methods (Static)
        function clock = wallClock()
            origin = tic;
            clock = @() toc(origin);
        end

        function stopAll()
            %STOPALL Safety net: remove every playback timer.
            orphans = timerfindall(Tag=dlab.core.PlaybackController.TimerTag);
            if ~isempty(orphans)
                stop(orphans);
                delete(orphans);
            end
        end
    end

    methods (Access = private)
        function setTime(obj, t)
            obj.Time = t;
            notify(obj, "TimeChanged");
        end

        function onTimer(obj)
            try
                obj.tick();
            catch ME
                obj.pause();
                obj.OnError(ME);
            end
        end

        function stopTimer(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            obj.Timer = [];
        end
    end
end
