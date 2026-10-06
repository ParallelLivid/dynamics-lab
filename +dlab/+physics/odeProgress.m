function fcn = odeProgress(progressFcn, tspan)
%ODEPROGRESS An ODE OutputFcn that reports progress through a run.
%   fcn = dlab.physics.odeProgress(progressFcn, tspan) returns
%   @(t, y, flag) stop for odeset's OutputFcn. After each step it calls
%   progressFcn(fraction), with the fraction of TSPAN covered (its first
%   to last element, as for ode45), and returns its answer, so a true
%   from progressFcn (a cancel) stops the solver. Returns [] (no output
%   function) when progressFcn is empty.
%
%   Report on every step: the caller (dlab.core.Plugin.progress) decides
%   how often to pass reports on.
if isempty(progressFcn)
    fcn = [];
    return
end
t0 = tspan(1);
span = tspan(end) - tspan(1);
fcn = @report;

    function stop = report(t, ~, flag)
        stop = false;
        if isempty(flag) && ~isempty(t)
            stop = progressFcn((t(end) - t0) / span);
        end
    end
end
