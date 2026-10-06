# DC Motor Servo

A permanent-magnet DC motor driven in open loop, or as a speed or position servo with P, PI, PD,
or PID control: the motor's time constants, how gains set overshoot and damping, an integral
against a load torque, and what a supply limit does to an integral (windup).

## Model

```text
L di/dt = V − R i − K ω          armature
J dω/dt = K i − b ω − τ_load      rotor (J includes the load)
dθ/dt   = ω
```

K is both the back-EMF constant (V·s/rad) and the torque constant (N·m/A): the same number in SI
units. With L = 0 the current follows the voltage at once, i = (V − K ω)/R, and the speed's step
response is first order with τ = J R / (K² + b R) and steady speed K V / (K² + b R). With L > 0
the motor has two poles, the roots of (J s + b)(L s + R) + K² = 0.

**Control:**

| Mode | Voltage command |
|---|---|
| Open loop | V = the voltage schedule |
| Speed (P, PI) | V = Kp e + Ki ∫e dt, e = ω_ref − ω |
| Position (P, PD, PID) | V = Kp e + Ki ∫e dt − Kd ω, e = θ_ref − θ (derivative on the measured speed: no kick at a reference step) |

The applied voltage is the command clipped to ±Vmax. **Anti-windup:** with *None* the integral
keeps integrating while the voltage is saturated (windup); with *Clamping* it holds whenever the
voltage is saturated and the error has the sign that would push it further into saturation.

**Integration:** classical Runge–Kutta with a fixed step that divides each output interval and is
at most 0.2/|λ| for the fastest pole of the motor and of the linear closed loop. The energy drawn
from the supply, ∫ V i dt, is integrated with the motion (not summed from the samples). A run is
limited to 2 million output samples and 5 million solver steps.

## Inputs

| Group | Inputs |
|---|---|
| Motor | R (Ω), L (mH, 0 allowed), K (V·s/rad), J (kg·m²), b (N·m·s/rad), supply limit Vmax (V) |
| Controller | Mode; speed Kp, Ki; position Kp, Ki, Kd; anti-windup (none or clamping) |
| Commands | Voltage (V, open loop), speed reference (rpm), angle reference (°), load torque (N·m): all schedules |
| Simulation | Duration, output step |

The default motor (R = 2 Ω, L = 5 mH, K = 0.1, J = 10⁻³ kg·m², b = 10⁻⁴ N·m·s/rad, 24 V) has
τ ≈ 0.196 s and an electrical time constant L/R = 2.5 ms.

**Presets:** open loop (a 12 V step); speed loop PI (a 600 rpm step; Ki = 0 for P only); position
P (Kp = 5, about 65 % overshoot); position PD (Kp = 10, Kd = 0.6, the default: 1.7 %); PID with a
12 V supply and a 360° step, without and with anti-windup (about 49 % and 13 % overshoot); and a
0.1 N·m load torque step rejected by PID.

## Outputs

- **Animation:** the rotor as a dial with spokes and a pointer at θ, the reference pointer
  (position control), the load torque as an arc arrow, and bars for the current and the applied
  voltage (amber while saturated) with a line at the commanded voltage.
- **Angle and speed** (with the reference), **Voltage and current** (commanded and applied, the
  ±Vmax band), **Error and power** (the tracking error in ° or rpm; power from the supply V i,
  at the shaft K i ω, and the copper loss R i²), and **Poles** (open- and closed-loop poles of the
  linear loop without the voltage limit, the gains, τ_mech, τ_elec; a far-off electrical pole is
  listed rather than drawn).
- **Modes:** the motor alone at rest (the open-loop plant), with modes named Shaft angle (neutral),
  Mechanical (speed), Electrical (current), or Electromechanical oscillation. The linearization also
  carries the frequency-response fields: G(x, u) with u = [voltage; load torque], U0 = [0; 0], and
  outputs H = [speed; angle].
- **Bode:** the motor alone from the voltage or the load torque to the speed or the angle, and,
  under speed or position control, the loop gain broken at the motor voltage with its gain and
  phase margins: L(s) = (Kp + Ki/s) ω(s)/V(s) for speed control and
  L(s) = (Kp + Ki/s + Kd s) θ(s)/V(s) for position control (the derivative on the measured speed
  gives the same loop as on the error; only the path from the reference differs).
- **Summary:** for a step command (measured up to a later load change, from the value at the step
  to the last sample, as MATLAB's `stepinfo` does; "—" when the output does not move): rise time
  (10–90 %), time to 63 %, overshoot, settling time (2 %); in closed loop the final error (|e| at
  the end of the run, which is the steady-state error only once the response has settled); peak
  current, peak applied voltage, time at the voltage limit, energy used (∫ V i dt), final speed,
  the mechanical and electrical time constants, and in closed loop the lowest damping ratio of the
  closed-loop poles (the least damped motion) and the real part of the slowest closed-loop pole.
  An unstable linear closed loop is flagged in the status line.
- **Export:** time, angle, speed, current, commanded and applied voltage, reference and error (in
  closed loop), load torque, the three powers, and the energy, each with its units.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| L = 0, 12 V step | ω(t) = G V (1 − e^(−t/τ)) within 10⁻⁷; τ = 0.19608 s; time to 63 % = τ, rise = τ ln 9, settling = τ ln 50 (0.2 %) |
| L = 5 mH | poles −394.93 and −5.1654 = roots of (J s + b)(L s + R) + K² = 0; ω(t) matches the two-pole step response within 10⁻⁶ |
| Linear model | equals the Jacobian of the dynamics (L > 0 and L = 0) |
| Position P, L = 0, Kp = 5 | ω_n = 15.811 rad/s, ζ = 0.1613; overshoot = e^(−πζ/√(1−ζ²)) (0.2 %); peak time π/ω_d; settling = the exact second-order 2 % time (2 ms), within half a period of the envelope bound |
| Position P, L = 5 mH | overshoot within 3 % of the dominant pair's formula; settling within its envelope bound |
| Position PD, L = 0, Kp = 10, Kd = 0.6 | ζ = 0.785; overshoot from the formula within 1 % |
| Speed P, Kp = 0.3 | steady error r / (1 + G Kp) (10⁻⁶) |
| Speed PI | zero steady error, also against a constant load; the integral supplies the whole steady voltage |
| Position PD with a 0.1 N·m load | steady error τ R / (K Kp), current τ / K; with Ki = 50 the error vanishes |
| 360° step, 12 V, PID | windup 48.6 % overshoot, clamping 13.5 %; applied voltage within ±Vmax |
| Energy | ∫ V i dt = ½ J ω² + ½ L i² + ∫ (R i² + b ω² + τ ω) dt (10⁻⁵), at the default output step too |
| Loop gain, position P (Kp = 5) | phase margin 16.2° at 15.49 rad/s, gain margin 18.24 dB at √((K² + b R)/(J L)) = 45.17 rad/s |
| Loop gain, PID (Kp = 10, Ki = 60, Kd = 0.6) | phase margin 64.1° (the phase starts just below −180°, not at +180°) |

## Lessons

**Tuning a servo** measures the open-loop time constant, closes a P position loop (65 %
overshoot; ζ ≈ 0.14), adds derivative damping, adds an integral to remove the error a load
torque leaves, and ends with windup at a 12 V supply and its cure by clamping.

**The motor's frequency response** reads the Bode plot: voltage to speed is a first-order lag
(DC gain K / (K² + b R) = 9.8 rad/s per volt, bandwidth 5.15 rad/s ≈ 1/τ), heavier inertia halves
the bandwidth, and voltage to angle integrates, which is why a position servo holds a step
without an integral term.
