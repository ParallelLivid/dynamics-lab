classdef TestPlayback < matlab.unittest.TestCase
    %TESTPLAYBACK PlaybackController clock behavior and frameAt.

    properties
        Now (1,1) double = 0
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods
        function pc = controller(testCase)
            testCase.Now = 0;
            pc = dlab.core.PlaybackController(Clock=@() testCase.Now, UseTimer=false);
            testCase.addTeardown(@delete, pc);
        end

        function advance(testCase, pc, seconds)
            testCase.Now = testCase.Now + seconds;
            pc.tick();
        end
    end

    methods (Test)
        function followsWallClockTimesSpeed(testCase)
            pc = testCase.controller();
            pc.load(0, 10);
            pc.play();
            testCase.advance(pc, 0.5);
            testCase.verifyEqual(pc.Time, 0.5, AbsTol=1e-12);
            pc.Speed = 4;
            testCase.advance(pc, 0.25);
            testCase.verifyEqual(pc.Time, 1.5, AbsTol=1e-12);
        end

        function timeScaleStretchesLongSimulations(testCase)
            pc = testCase.controller();
            pc.load(0, 3600);
            pc.TimeScale = 180;             % an hour plays in 20 s at 1×
            pc.Speed = 2;
            pc.play();
            testCase.advance(pc, 1);
            testCase.verifyEqual(pc.Time, 360, AbsTol=1e-9);
        end

        function droppedTicksDoNotSlowPlayback(testCase)
            pc = testCase.controller();
            pc.load(0, 10);
            pc.play();
            testCase.advance(pc, 0.9);   % one late tick covering many frames
            testCase.verifyEqual(pc.Time, 0.9, AbsTol=1e-12);
        end

        function stopsAtEndUnlessLooping(testCase)
            pc = testCase.controller();
            pc.load(1, 3);
            testCase.verifyEqual(pc.Time, 1);
            stateChanges = 0;
            l = addlistener(pc, "StateChanged", @(~, ~) countState());
            pc.play();
            testCase.advance(pc, 5);
            testCase.verifyEqual(pc.Time, 3);
            testCase.verifyFalse(pc.IsPlaying);
            testCase.verifyEqual(stateChanges, 2);   % play, then finish

            pc.play();                                % play at end restarts
            testCase.verifyEqual(pc.Time, 1);
            pc.Loop = true;
            testCase.advance(pc, 2.5);
            testCase.verifyEqual(pc.Time, 1.5, AbsTol=1e-12);
            testCase.verifyTrue(pc.IsPlaying);
            delete(l);

            function countState()
                stateChanges = stateChanges + 1;
            end
        end

        function seekClampsAndRestartRewinds(testCase)
            pc = testCase.controller();
            pc.load(0, 2);
            pc.seek(5);
            testCase.verifyEqual(pc.Time, 2);
            pc.seek(-1);
            testCase.verifyEqual(pc.Time, 0);
            pc.seek(1.2);
            pc.restart();
            testCase.verifyEqual(pc.Time, 0);
        end

        function pausedControllerIgnoresTicks(testCase)
            pc = testCase.controller();
            pc.load(0, 2);
            testCase.advance(pc, 1);
            testCase.verifyEqual(pc.Time, 0);
            pc.play();
            pc.pause();
            testCase.advance(pc, 1);
            testCase.verifyEqual(pc.Time, 0);
        end

        function emptySpanDoesNotPlay(testCase)
            pc = testCase.controller();
            pc.load(0, 0);
            pc.play();
            testCase.verifyFalse(pc.IsPlaying);
            testCase.verifyError(@() pc.load(2, 1), "MATLAB:validators:mustBeGreaterThanOrEqual");
        end

        function timeChangedFiresForEveryMove(testCase)
            pc = testCase.controller();
            count = 0;
            l = addlistener(pc, "TimeChanged", @(~, ~) bump());
            pc.load(0, 2);
            pc.seek(1);
            pc.play();
            testCase.advance(pc, 0.1);
            testCase.verifyEqual(count, 3);
            delete(l);
            function bump()
                count = count + 1;
            end
        end

        function realTimerRunsAndCleansUp(testCase)
            pc = dlab.core.PlaybackController();
            pc.load(0, 100);
            pc.play();
            testCase.verifyNotEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
            pause(0.3);
            testCase.verifyGreaterThan(pc.Time, 0.1);
            delete(pc);
            testCase.verifyEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
        end

        function timeReadoutFitsLongRuns(testCase)
            testCase.verifyEqual(dlab.core.PlaybackBar.formatSpan(1.5, 4), "1.50 / 4.00 s");
            testCase.verifyEqual(dlab.core.PlaybackBar.formatSpan(30, 300), "30.0 / 300.0 s");
            testCase.verifyEqual(dlab.core.PlaybackBar.formatSpan(600, 5554), "10.0 / 92.6 min");
            testCase.verifyEqual(dlab.core.PlaybackBar.formatSpan(25905, 86350), "7.2 / 24.0 h");
            testCase.verifyEqual(dlab.core.PlaybackBar.formatSpan(86400, 3.156e7), "1.0 / 365.3 days");
        end

        function frameAtPicksLastSampleNotAfter(testCase)
            times = 0:0.1:3;
            testCase.verifyEqual(dlab.core.frameAt(times, 0), 1);
            testCase.verifyEqual(dlab.core.frameAt(times, 0.099), 1);
            testCase.verifyEqual(dlab.core.frameAt(times, 0.3), 4);      % ulp tolerance
            testCase.verifyEqual(dlab.core.frameAt(times, 0.1 + 0.2), 4);
            testCase.verifyEqual(dlab.core.frameAt(times, 99), numel(times));
            testCase.verifyEqual(dlab.core.frameAt(times, -1), 1);
        end
    end
end
