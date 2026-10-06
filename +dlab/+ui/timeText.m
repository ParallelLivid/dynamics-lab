function text = timeText(seconds, options)
%TIMETEXT A duration in s, min, h or days, whichever reads best.
%   text = dlab.ui.timeText(seconds) gives three significant figures:
%   "45 s", "12.5 min", "3.2 h", "4.1 days".
%
%   text = dlab.ui.timeText(seconds, Fixed=true) starts at minutes and
%   uses fixed decimals ("0.8 min", "1.25 h", "2.10 days"), so a running
%   clock keeps its width.
arguments
    seconds (1,1) double
    options.Fixed (1,1) logical = false
end
if options.Fixed
    if seconds < 2 * 3600
        text = sprintf("%.1f min", seconds / 60);
    elseif seconds < 3 * 86400
        text = sprintf("%.2f h", seconds / 3600);
    else
        text = sprintf("%.2f days", seconds / 86400);
    end
elseif seconds < 120
    text = sprintf("%.3g s", seconds);
elseif seconds < 2 * 3600
    text = sprintf("%.3g min", seconds / 60);
elseif seconds < 3 * 86400
    text = sprintf("%.3g h", seconds / 3600);
else
    text = sprintf("%.3g days", seconds / 86400);
end
end
