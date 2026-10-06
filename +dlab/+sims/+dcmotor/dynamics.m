function dx = dynamics(x, u, p)
%DYNAMICS The DC motor's state derivative (no controller, no voltage limit).
%   dx = dynamics(x, u, p) with u = [V; tau_load] (V, N·m) and the motor
%   constants p.R (Ω), p.L (H), p.K (V·s/rad = N·m/A), p.J (kg·m²), and
%   p.b (N·m·s/rad):
%
%     L di/dt = V − R i − K ω
%     J dω/dt = K i − b ω − τ_load
%     dθ/dt   = ω
%
%   With p.L > 0 the state is x = [i; ω; θ]. With p.L = 0 the current
%   follows the voltage at once, i = (V − K ω) / R, and x = [ω; θ].
if p.L > 0
    i = x(1);
    w = x(2);
    dx = [(u(1) - p.R * i - p.K * w) / p.L
          (p.K * i - p.b * w - u(2)) / p.J
          w];
else
    w = x(1);
    i = (u(1) - p.K * w) / p.R;
    dx = [(p.K * i - p.b * w - u(2)) / p.J
          w];
end
end
