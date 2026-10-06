function frame = frameAt(times, simTime)
%FRAMEAT Index of the last sample at or before SIMTIME.
%   Plugins call this from drawFrame to map playback time onto their
%   output samples, so playback speed never depends on sample spacing.
%   Decimal output grids and accumulated clock ticks can differ by a few
%   ulps, hence the small tolerance (from MassSpringPlayback).
frame = find(times <= simTime + 8*eps(max(1, abs(simTime))), 1, "last");
if isempty(frame)
    frame = 1;
end
end
