# Spacecraft Attitude Control

A rigid spacecraft with three reaction wheels and a set of thrusters. Leave it alone to tumble,
detumble it, slew it to a target with a quaternion PD controller or a bang-bang thruster
maneuver, and hold it against a disturbance torque until the wheels saturate (or dump their
momentum with the thrusters).

## Model

```text
I ω' = −ω × (I ω + h) − τ_w + τ_thr + τ_d      Euler's equations with wheels (I = diag(Iₓ, Iᵧ, I_z))
h'   = τ_w                                     wheel momentum, one wheel per body axis
q'   = ½ q ⊗ [0; ω]                            attitude quaternion, body to world (scalar first)
```

τ_w is the torque the motors put on the wheels; the body feels −τ_w. Each wheel gives at most
±τ_max, and a wheel at ±h_max (top speed) cannot take more momentum in that direction: it is
**saturated** until the controller asks it to unload. τ_d is a constant disturbance in body axes.

| Mode | Control |
|---|---|
| Free | None. Energy ½ ωᵀIω and the inertial angular momentum R (I ω + h) are constant. |
| Detumble | τ = −Kd ω on the wheels. The body stops; its momentum ends up in the wheels. |
| Slew (PD) | Error quaternion q_e = q_target⁻¹ ⊗ q; τ = −Kp · 2 sign(q_e0) q_e,vec − Kd ω. 2 q_e,vec is the error angle for small errors, so about one axis I θ'' + Kd θ' + Kp θ = 0: ωn = √(Kp/I), ζ = Kd / (2 √(Kp I)). The sign(q_e0) takes the short way round, and makes the law the same for q and −q. |
| Bang-bang | Rest to rest about the eigenaxis e of the error, angle θ: acceleration α for θ/2, then −α. The thrusters (throttled) give I α e plus the gyroscopic torque ω × (I ω + h), so the rotation stays about e; α = τ_thr / maxᵢ(Iᵢ\|eᵢ\| + θ \|(e × I e)ᵢ\|) keeps every axis within its thrust. About a principal axis this is t = 2 √(θ I / τ_thr). The wheels' PD holds the target afterwards. |
| Hold | The PD law with the start attitude as the target. A constant τ_d leaves an offset τ_d / Kp and fills the wheels at the rate τ_d. |

**Momentum dumping** (detumble, slew, hold): when a wheel passes the chosen fraction of h_max,
that axis fires its thrusters against the wheel's momentum (−τ_dump sign(hᵢ)) until it is down to
10 %; the PD loop holds the attitude while the wheel unloads.

Integrated with `ode45` (relative tolerance 10⁻¹⁰) in segments: the bang-bang switch times, a
wheel reaching or leaving its limit, and the start and end of each dump are located exactly by
event functions. The quaternion's norm is held at 1 by a small correction term. The pointing error
is the eigenaxis angle 2 atan2(‖q_e,vec‖, |q_e0|).

## Inputs

| Group | Inputs |
|---|---|
| Mode | Free, detumble, slew (PD), slew (bang-bang), hold |
| Spacecraft | Principal inertias Iₓ, Iᵧ, I_z (each at most the sum of the other two) |
| Start | Roll, pitch, yaw (3-2-1 Euler angles, °); body rates ωₓ, ωᵧ, ω_z (°/s) |
| Target | Roll, pitch, yaw (the slews) |
| Controller | Kp (N·m/rad, PD modes), Kd (N·m·s/rad) |
| Reaction wheels | Torque limit τ_max, momentum capacity h_max (per wheel) |
| Thrusters | Torque per axis (bang-bang); momentum dumping on/off, the level it starts at (%), dumping torque |
| Disturbance | τₓ, τᵧ, τ_z (N·m, body axes; not in free mode) |
| Simulation | Duration, output step |

**Presets:** a free tumble about the intermediate axis (I = 30, 40, 50 kg·m², 10 °/s about y), a
detumble from (3, −2, 4) °/s, a 90° yaw slew on the wheels (the defaults: Kp = 0.5, Kd = 7,
ζ = 0.7 about z), a large three-axis slew (to roll 60°, pitch −40°, yaw 120°: a 150° eigenaxis
turn), a bang-bang 90° yaw slew on 1 N·m thrusters, a hold against (0.002, 0, 0.01) N·m until
the z wheel saturates, and the same hold with momentum dumping.

## Outputs

- **Animation** (3-D): the spacecraft (a box with sides from the inertias, and solar panels),
  its body axes (x red, y green, z blue), the target axes as dashed ghosts, the thruster torque
  while firing, and, in an inset at the lower left, three bars of each wheel's momentum against
  its capacity ±h_max (orange when saturated; no inset in free motion). Animation export records
  the inset too. Each run plays in about 20 s.
- **Pointing error:** the eigenaxis angle to the target (to the start attitude in the free,
  detumble, and hold modes), on linear and log scales with the 0.1° band and the time it is
  reached; bang-bang switch and end times marked.
- **Body rates**, **Euler angles** (3-2-1, with the targets dashed; they are singular at ±90° pitch, gimbal lock, while the model itself uses quaternions), **Wheel momentum** (with
  ±h_max and the dumping level), **Torques** (wheel torque on the body within ±τ_max; thruster and
  disturbance torques), and **Conservation** (free mode: relative change of energy and of the
  inertial momentum vector, on log axes).
- **Modes:** linearized about the target at rest under the PD hold (states the error angles
  φ = 2 q_e,vec and ω; wheels at zero momentum, limits ignored). Each mode is named by its axis:
  Roll/Pitch/Yaw oscillation or settling, or drift (neutral) in the detumble mode, which has no
  attitude loop. Not available in free mode.
- **Bode** (frequency response): inputs are a torque about x, y, or z (a commanded torque and a
  disturbance enter the same way), outputs the error angles φₓ, φᵧ, φ_z (rad).
- **Summary:** slew time (within 0.1° from then on), initial and final pointing error, overshoot
  (along the initial error axis, % of the initial error), max and final rate, max wheel momentum
  and the % of capacity used, wheels saturated (yes or no) and when, the bang-bang time 2√(θ/α) and α,
  thruster impulse ∫ Σ|τ| dt, momentum dumps, and (free mode) energy and momentum drift.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Free tumble about the intermediate axis (I = 30, 40, 50; ω = (0.05, 10, 0.05) °/s; 600 s), also with spinning wheels | energy and inertial momentum drift < 10⁻¹⁰; it turns over (> 170°) |
| Bang-bang about one principal axis: 90° about z (I = 50, τ = 1), 45° about y (40, 0.5), 120° about x (30, 2) | maneuver time 2 √(θ I / τ) (10⁻¹²); within 0.1° at T − √(2 · 0.1° / α) (10⁻³ s); peak rate √(θ α); impulse τ T |
| Bang-bang 150° three-axis slew | on target at the end of the maneuver (< 10⁻⁴ °); ω stays on the eigenaxis; no axis above its thrust |
| PD, 1° yaw step, Kp = 0.5, Kd = 3, I = 50 (ζ = 0.3) | overshoot 100 exp(−πζ/√(1 − ζ²)) = 37.2 % (0.2 %); zero crossings π/ω_d apart (0.1 %) |
| Modes for the defaults | ωn = √(Kp/Iᵢ) and ζ = Kd / (2 √(Kp Iᵢ)) on each axis (10⁻⁶); B = [0; diag(1/I)]; F(x) = G(x, U0) |
| Hold against τ_d = 0.01 N·m about z (Kp = 1) | wheel momentum grows at τ_d (10⁻⁴); saturates at h_max / τ_d = 600 s; offset τ_d / Kp before that |
| Detumble from (3, −2, 4) °/s | rates to zero; inertial momentum conserved (10⁻⁸); final wheel momentum ‖I ω₀‖ |
| q and −q for the start and target, PD and bang-bang | identical rates, errors, and wheel momenta (10⁻⁹) |

## Lesson

**Pointing a spacecraft** tumbles a spacecraft about its intermediate axis, detumbles it (and
finds the momentum in the wheels), tunes the PD slew's damping, compares a bang-bang thruster
slew, and holds against a disturbance until a wheel saturates.
