classdef PlaybackBar < handle
    %PLAYBACKBAR Play / restart / scrub / speed / loop controls for a PlaybackController.
    %   Layout: [▶] [⟲] [━━━●━━━] [ 1.20 / 5.00 s ] [Speed 1×] [☐ Loop] [extras]
    %   The extras cell holds plugin controls (buildPlaybackControls).

    properties (SetAccess = private)
        Grid
        Extras          % uigridlayout for plugin-specific controls
        PlayButton
        RestartButton
        Slider
        TimeLabel
        SpeedDropdown
        LoopCheckbox
    end

    properties (Access = private)
        Controller
        Listeners = event.listener.empty
    end

    methods
        function obj = PlaybackBar(parent, controller, tokens)
            arguments
                parent
                controller (1,1) dlab.core.PlaybackController
                tokens (1,1) dlab.ui.Theme
            end
            obj.Controller = controller;
            t = tokens;
            w = @(px) round(t.scaled(px));         % wider for larger text
            obj.Grid = uigridlayout(parent, [1 8], ...
                ColumnWidth={44, 44, "1x", w(150), w(46), w(70), w(60), "fit"}, RowHeight={w(30)}, ...
                ColumnSpacing=t.Spacing.sm, Padding=[t.Spacing.sm t.Spacing.xs t.Spacing.sm t.Spacing.xs], ...
                BackgroundColor=t.Surface);

            obj.PlayButton = dlab.ui.button(obj.Grid, "▶", t, Kind="primary", ...
                Tag="dlab.playback.play", Tooltip="Play / pause", ...
                Callback=@(~, ~) controller.toggle());
            obj.RestartButton = dlab.ui.button(obj.Grid, "⟲", t, ...
                Tag="dlab.playback.restart", Tooltip="Back to start", ...
                Callback=@(~, ~) controller.restart());
            obj.Slider = uislider(obj.Grid, Limits=[0 1], Value=0, ...
                MajorTicks=[], MinorTicks=[], FontColor=t.TextMuted, Tag="dlab.playback.slider", ...
                ValueChangingFcn=@(~, evt) controller.seek(evt.Value), ...
                ValueChangedFcn=@(src, ~) controller.seek(src.Value));
            obj.TimeLabel = dlab.ui.label(obj.Grid, "", t, Role="mono", ...
                HorizontalAlignment="center", Tag="dlab.playback.time");
            dlab.ui.label(obj.Grid, "Speed", t, Role="muted", HorizontalAlignment="right");
            speeds = dlab.core.PlaybackController.Speeds;
            obj.SpeedDropdown = uidropdown(obj.Grid, Items=compose("%g×", speeds), ItemsData=speeds, ...
                Value=1, BackgroundColor=t.SurfaceRaised, FontColor=t.Text, Tag="dlab.playback.speed", ...
                ValueChangedFcn=@(src, ~) obj.setSpeed(src.Value));
            obj.LoopCheckbox = uicheckbox(obj.Grid, Text="Loop", Value=controller.Loop, ...
                FontColor=t.Text, Tag="dlab.playback.loop", Tooltip="Restart automatically at the end", ...
                ValueChangedFcn=@(src, ~) obj.setLoop(src.Value));
            obj.Extras = uigridlayout(obj.Grid, [1 1], Padding=0, BackgroundColor=t.Surface, ...
                ColumnWidth={"fit"});

            obj.Listeners(1) = listener(controller, "TimeChanged", @(~, ~) obj.showTime());
            obj.Listeners(2) = listener(controller, "StateChanged", @(~, ~) obj.showState());
            obj.refresh();
        end

        function refresh(obj)
            %REFRESH Re-read the controller's span (after load).
            c = obj.Controller;
            hasSpan = c.EndTime > c.StartTime;
            if hasSpan
                obj.Slider.Limits = [c.StartTime c.EndTime];
            else
                obj.Slider.Limits = [0 1];
            end
            enable = matlab.lang.OnOffSwitchState(hasSpan);
            set([obj.PlayButton obj.RestartButton obj.Slider], Enable=enable);
            obj.showTime();
            obj.showState();
        end

        function setEnabled(obj, enabled)
            %SETENABLED Lock the controls (during a busy task) or restore them.
            if enabled
                obj.refresh();
                set([obj.SpeedDropdown obj.LoopCheckbox], Enable="on");
            else
                set([obj.PlayButton obj.RestartButton obj.Slider obj.SpeedDropdown obj.LoopCheckbox], Enable="off");
            end
        end

        function delete(obj)
            delete(obj.Listeners);
        end
    end

    methods (Static)
        function text = formatSpan(t, total)
            %FORMATSPAN "1.50 / 4.00 s", or minutes, hours, or days for long
            %   runs, so the readout always fits.
            units = [1 60 3600 86400];
            names = ["s" "min" "h" "days"];
            limits = [600 3 * 3600 3 * 86400 Inf];
            k = find(total < limits, 1);
            if k == 1 && total < 100
                text = sprintf("%.2f / %.2f s", t, total);
            else
                text = sprintf("%.1f / %.1f %s", t / units(k), total / units(k), names(k));
            end
        end
    end

    methods (Access = private)
        function setSpeed(obj, speed)
            obj.Controller.Speed = speed;
        end

        function setLoop(obj, loop)
            obj.Controller.Loop = loop;
        end

        function showTime(obj)
            c = obj.Controller;
            if c.EndTime > c.StartTime
                obj.Slider.Value = min(max(c.Time, obj.Slider.Limits(1)), obj.Slider.Limits(2));
                obj.TimeLabel.Text = dlab.core.PlaybackBar.formatSpan(c.Time, c.EndTime);
            else
                obj.Slider.Value = 0;
                obj.TimeLabel.Text = "– / – s";
            end
        end

        function showState(obj)
            if obj.Controller.IsPlaying
                obj.PlayButton.Text = "⏸";
            else
                obj.PlayButton.Text = "▶";
            end
        end
    end
end
