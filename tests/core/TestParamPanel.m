classdef (TestTags = {'ui'}) TestParamPanel < matlab.unittest.TestCase
    %TESTPARAMPANEL The generated input panel and the playback bar.

    properties
        Figure
        Plugin
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Figure = uifigure(Visible="off");
            testCase.addTeardown(@delete, testCase.Figure);
            testCase.Plugin = dlabtest.ToyOscillatorPlugin();
        end
    end

    methods
        function panel = makePanel(testCase)
            specs = testCase.Plugin.parameters();
            panel = dlab.core.ParamPanel(testCase.Figure, specs, ...
                dlab.core.ParamSpec.defaults(specs), dlab.ui.Theme.dark());
        end

        function c = find(testCase, tag)
            c = findall(testCase.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end
    end

    methods (Test)
        function fieldsReflectSpecs(testCase)
            panel = testCase.makePanel();
            testCase.verifyEqual(panel.values(), testCase.Plugin.defaultParams());
            zeta = testCase.find("dlab.param.zeta");
            testCase.verifyClass(zeta, "matlab.ui.control.NumericEditField");
            testCase.verifyEqual(zeta.Limits, [0 1]);
            testCase.verifyFalse(logical(zeta.UpperLimitInclusive));
            testCase.verifyTrue(logical(testCase.find("dlab.param.cycles").RoundFractionalValues));
            drive = testCase.find("dlab.param.drive");
            testCase.verifyEqual(string(drive.Items), ["Free" "Forced"]);
            testCase.verifyEqual(drive.Value, "free");
            envelope = testCase.find("dlab.param.showEnvelope");
            testCase.verifyClass(envelope, "matlab.ui.control.CheckBox");
            testCase.verifyEqual(string(envelope.Text), "Show envelope");
            omega = testCase.find("dlab.param.omega");
            testCase.verifySubstring(string(omega.Tooltip), "Undamped angular frequency.");
        end

        function advancedGroupsStartCollapsed(testCase)
            panel = testCase.makePanel();
            testCase.verifyFalse(panel.isRowShown("duration"));
            testCase.verifyTrue(panel.isRowShown("omega"));
            header = testCase.find("dlab.group.Simulation");
            testCase.verifySubstring(string(header.Text), "▸");
            header.ButtonPushedFcn(header, []);
            testCase.verifyTrue(panel.isRowShown("duration"));
            testCase.verifySubstring(string(header.Text), "▾");
        end

        function visibleWhenFollowsEdits(testCase)
            panel = testCase.makePanel();
            events = dlab.core.ParamChangedData.empty;
            l = listener(panel, "ValueChanged", @(~, evt) recordEvent(evt));
            testCase.verifyFalse(panel.isRowShown("F"));

            drive = testCase.find("dlab.param.drive");
            drive.Value = "forced";
            drive.ValueChangedFcn(drive, []);          % as if the user picked it
            testCase.verifyTrue(panel.isRowShown("F"));
            testCase.verifyEqual(panel.values().drive, "forced");
            testCase.verifyNumElements(events, 1);
            testCase.verifyEqual(events(1).Name, "drive");
            testCase.verifyEqual(events(1).OldValue, "free");
            delete(l);

            function recordEvent(evt)
                events(end+1) = evt;
            end
        end

        function groupsWithNoVisibleRowsDisappear(testCase)
            specs = [dlab.core.ParamSpec("mode", Type="choice", Choices=["a" "b"], Group="Mode")
                     dlab.core.ParamSpec("x", Group="Only B", VisibleWhen=@(p) p.mode == "b")
                     dlab.core.ParamSpec("y", Group="Only B", VisibleWhen=@(p) p.mode == "b")];
            panel = dlab.core.ParamPanel(testCase.Figure, specs, dlab.core.ParamSpec.defaults(specs), ...
                dlab.ui.Theme.dark());
            testCase.verifyFalse(panel.isGroupShown("Only B"));
            testCase.verifyEqual(string(testCase.find("dlab.group.Only B").Visible), "off");
            mode = testCase.find("dlab.param.mode");
            mode.Value = "b";
            mode.ValueChangedFcn(mode, []);
            testCase.verifyTrue(panel.isGroupShown("Only B"));
            testCase.verifyTrue(panel.isRowShown("x"));
        end

        function setValuesIsSilent(testCase)
            panel = testCase.makePanel();
            fired = false;
            l = listener(panel, "ValueChanged", @(~, ~) markFired());
            params = panel.values();
            params.zeta = 0.5;
            params.drive = "forced";
            panel.setValues(params);
            testCase.verifyFalse(fired);
            testCase.verifyEqual(testCase.find("dlab.param.zeta").Value, 0.5);
            testCase.verifyTrue(panel.isRowShown("F"));
            params.zeta = 2;
            testCase.verifyError(@() panel.setValues(params), "dlab:invalidParameter");
            delete(l);
            function markFired()
                fired = true;
            end
        end

        function disablingLocksEveryField(testCase)
            panel = testCase.makePanel();
            panel.setEnabled(false);
            testCase.verifyEqual(string(testCase.find("dlab.param.zeta").Enable), "off");
            testCase.verifyEqual(string(testCase.find("dlab.param.showEnvelope").Enable), "off");
            panel.setEnabled(true);
            testCase.verifyEqual(string(testCase.find("dlab.param.drive").Enable), "on");
        end

        function playbackBarTracksController(testCase)
            wallTime = 0;
            pc = dlab.core.PlaybackController(Clock=@() readClock(), UseTimer=false);
            testCase.addTeardown(@delete, pc);
            bar = dlab.core.PlaybackBar(testCase.Figure, pc, dlab.ui.Theme.light());
            play = testCase.find("dlab.playback.play");
            testCase.verifyEqual(string(play.Enable), "off");   % nothing loaded yet

            pc.load(0, 4);
            bar.refresh();
            testCase.verifyEqual(string(play.Enable), "on");
            testCase.verifyEqual(testCase.find("dlab.playback.slider").Limits, [0 4]);
            play.ButtonPushedFcn(play, []);
            testCase.verifyEqual(string(play.Text), "⏸");
            wallTime = 1.5;
            pc.tick();
            testCase.verifyEqual(string(testCase.find("dlab.playback.time").Text), "1.50 / 4.00 s");
            testCase.verifyEqual(testCase.find("dlab.playback.slider").Value, 1.5);

            speed = testCase.find("dlab.playback.speed");
            speed.Value = 4;
            speed.ValueChangedFcn(speed, []);
            testCase.verifyEqual(pc.Speed, 4);
            loop = testCase.find("dlab.playback.loop");
            loop.Value = true;
            loop.ValueChangedFcn(loop, []);
            testCase.verifyTrue(pc.Loop);

            delete(bar);
            pc.seek(2);   % listeners are gone; must not error

            function t = readClock()
                t = wallTime;
            end
        end
    end
end
