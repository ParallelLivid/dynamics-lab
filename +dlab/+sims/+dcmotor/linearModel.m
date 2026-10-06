function m = linearModel(p)
%LINEARMODEL The motor and its control loop as linear state-space models.
%   m = linearModel(p) with the motor constants (R, L, K, J, b), the mode
%   ('open' | 'speed' | 'position'), and the gains Kp, Ki, Kd (see
%   simulateDcMotor). The voltage limit is ignored. Fields:
%
%     A, B, states   the motor alone: dx/dt = A x + B [V; τ_load], with
%                    x = [i; ω; θ] (or [ω; θ] when L = 0)
%     openPoles      poles of the plant from the voltage to the controlled
%                    variable: the speed (open loop and speed control,
%                    without the θ integrator) or the angle
%     Acl, Bcl, clStates
%                    the closed loop, dx/dt = Acl x + Bcl [reference; τ_load],
%                    with the integral of the error z = ∫ e dt as a state when
%                    Ki ≠ 0 (and without θ under speed control)
%     closedPoles    eig(Acl) (the open-loop poles in open loop)
%     tauMech, tauElec, gain
%                    J R / (K² + b R), L / R, and the steady speed per volt
%                    K / (K² + b R)
if p.L > 0
    A = [-p.R / p.L, -p.K / p.L, 0
         p.K / p.J, -p.b / p.J, 0
         0, 1, 0];
    B = [1 / p.L, 0
         0, -1 / p.J
         0, 0];
    states = ["i" "ω" "θ"];
else
    A = [-(p.K^2 / p.R + p.b) / p.J, 0
         1, 0];
    B = [p.K / (p.J * p.R), -1 / p.J
         0, 0];
    states = ["ω" "θ"];
end
n = numel(states);
Cw = double(states == "ω");
Ct = double(states == "θ");
mode = lower(char(p.mode));
keep = true(1, n);
if ~strcmp(mode, 'position')
    keep = states ~= "θ";                    % θ does not feed back
end
m.A = A;
m.B = B;
m.states = states;
m.openPoles = eig(A(keep, keep));

switch mode
    case 'speed'
        Cy = Cw;
        Kd = 0;
    case 'position'
        Cy = Ct;
        Kd = p.Kd;
    otherwise
        Cy = [];
end
if isempty(Cy)
    Acl = A(keep, keep);
    Bcl = [zeros(nnz(keep), 1), B(keep, 2)];
    clStates = states(keep);
else
    % V = Kp (r − y) + Ki z − Kd ω,  z' = r − y
    Bv = B(:, 1);
    Acl = A - Bv * (p.Kp * Cy + Kd * Cw);
    Bcl = [Bv * p.Kp, B(:, 2)];
    Acl = Acl(keep, keep);
    Bcl = Bcl(keep, :);
    clStates = states(keep);
    if p.Ki ~= 0
        Acl = [Acl, Bv(keep) * p.Ki
               -Cy(keep), 0];
        Bcl = [Bcl; 1, 0];
        clStates(end + 1) = "∫e";
    end
end
m.Acl = Acl;
m.Bcl = Bcl;
m.clStates = clStates;
m.closedPoles = eig(Acl);
m.tauMech = p.J * p.R / (p.K^2 + p.b * p.R);
m.tauElec = p.L / p.R;
m.gain = p.K / (p.K^2 + p.b * p.R);
end
