# Quadrotor

A quadcopter as a rigid body with four rotors, flown by a cascaded controller: position →
tilt and thrust → attitude → torques → rotor thrusts. Hover, height steps, waypoint missions,
wind, rotor saturation, and a motor failure that sends it spinning.

## Model

**Airframe:** the X configuration. Body axes are x forward, y left, z up; the world has z up, with
the ground at z = 0. The rotors sit at (±d, ±d), d = L/√2, numbered clockwise seen from above:

| Rotor | Position | Spins |
|---|---|---|
| 1 front-left | (+d, +d) | clockwise |
| 2 front-right | (+d, −d) | counter-clockwise |
| 3 rear-right | (−d, −d) | clockwise |
| 4 rear-left | (−d, +d) | counter-clockwise |

Each rotor gives thrust Tᵢ = kf Ωᵢ² along body z and a drag torque Qᵢ = km Ωᵢ² = c Tᵢ
(c = km/kf) that yaws the body the other way. Together they give

[F; τx; τy; τz] = A T,  A = [1 1 1 1; d −d −d d; −d −d d d; c −c c −c].

**Dynamics:** 20 states: position and velocity (world), a unit quaternion (body → world), body
rates, three controller integrals, and four rotor speeds.

- m v' = R ẑ ΣTᵢ − m g ẑ − kd |v − w| (v − w)  (w is the wind)
- I ω' = τ − ω × I ω,  q' = ½ q ⊗ [0; ω]
- Ωᵢ' = (Ω_cmd,i − Ωᵢ)/τ: each rotor's speed lags its command (first order)
- A failed rotor's thrust and torque are scaled by the fraction it keeps, from the failure time on.

**Controller** (`closedLoop.m`), per unit mass, so the gains do not depend on the airframe:

1. Position: a = Kp e + Kd ė + Ki ∫e, with Kp, Kd, Ki for x and y and separate ones for z
   (e = setpoint − position; ė uses the setpoint's velocity on waypoint legs). The integrals run
   only within the capture band of the setpoint and add at most the integral limit (anti-windup).
2. Thrust vector F = m (a + g ẑ), with F_z ≥ 0.1 m g and tilted at most the tilt limit from
   vertical. (The limit bounds the command: a lightly damped attitude loop can overshoot it, and
   the aggressive-gains preset tilts to 48° with a 30° limit.) The collective thrust is F · (body z). The target attitude puts body z along F with
   the nose at the setpoint yaw.
3. Attitude, with q_e = q_target⁻¹ ⊗ q: τ = ω × I ω + I (−Kr · 2 sign(q_e0) q_e,vec − Kw ω). Each
   axis is then θ'' + Kw θ' + Kr θ = Kr θ_target behind the rotor lag.
4. Mixer: T = A⁻¹ [F; τ] when it fits within 0 ≤ Tᵢ ≤ Tmax. Otherwise it gives up yaw first,
   then collective thrust, and roll and pitch last: roll and pitch torques are scaled down only
   if their spread between rotors exceeds Tmax, the collective is shifted down (or up) until they
   fit, and the yaw torque is scaled from 1 toward 0 until every rotor is within its limits.

The *attitude* controller takes roll and pitch commands directly and still holds the height. The
*off* controller commands every rotor a fixed share of the hover thrust (0 % is free fall).

**Integration:** `ode45` (RelTol 10⁻⁸, AbsTol 10⁻⁹, maximum step 0.01 s), sampled at the output
step. The run stops when the quadrotor reaches the ground: "crashed" above the crash speed,
"landed" below it.

**Linearization** (`hoverLinearization.m`): the closed loop near hover at the setpoint, in still
air with healthy rotors and no limit reached, so the model is smooth. Attitude is a small rotation
δ from the hover attitude (q = q_hover ⊗ [√(1 − |δ|²/4); δ/2]), which avoids the quaternion's
redundant fourth component. With position control the states are x, y, z, vx, vy, vz, δφ, δθ, δψ,
p, q, r, the integrals whose gain is not zero, and Ω1–Ω4. The open loop (controller off) is a chain
of integrators with no equilibrium to analyse, so the Modes tab is empty then.

## Inputs

| Group | Inputs |
|---|---|
| Mission | Setpoints (x, y, z, yaw: each a constant, step, pulse, ramp, sine, or custom points) or Waypoints (a table of x, y, z, yaw, hold) with a cruise speed |
| Start | Position, yaw, roll, pitch; body rates (advanced) |
| Controller | Position / attitude / off; roll and pitch commands (attitude); rotor thrust (off); tilt limit |
| Controller gains | Horizontal and height Kp, Kd, Ki; roll/pitch and yaw stiffness Kr and damping Kw; integral capture band and limit |
| Airframe | Mass, arm length, rotor thrust limit, rotor time constant; inertias, kf, km, body drag, gravity (advanced) |
| Wind | Wind speed (a schedule: a step is a gust front) and direction |
| Motor failure | Which rotor, when, and the fraction of thrust it keeps |
| Simulation | Duration, output step, crash speed |

The defaults: m = 1 kg, L = 0.2 m, I = (0.01, 0.01, 0.018) kg·m², kf = 10⁻⁵ N/(rad/s)²,
km = 1.5·10⁻⁷ N·m/(rad/s)², τ = 0.03 s, Tmax = 6 N (thrust-to-weight 2.45).

**Presets:** hover (recovering from a 20° tilt), a height step from 3 to 6 m, the box waypoint
mission (the default: take off, fly a 4 m square at 3 m turning the nose along each side), a
7 m/s crosswind gust, a motor failure (rotor 1 stops at 2 s, 10 m up), aggressive gains (a 2 m
step with lightly damped loops), and a saturated climb from 3 to 20 m with 3.5 N rotors.

## Outputs

- **Animation:** the airframe in 3-D (drawn larger than life), its rotor discs coloured by thrust,
  the nose marked, a failed rotor outlined; the trail, its shadow, the waypoints, and the moving
  setpoint.
- **3-D path** (with the planned path and waypoints), **Position** (x, y, z against the setpoint),
  **Attitude** (roll and pitch against the inner loop's target; yaw against its setpoint), and
  **Rotor thrusts** (each rotor, with the limits, the hover thrust, and the time the mixer was
  saturated shaded).
- **Modes:** the closed loop at hover. Modes are named by the states that dominate them: horizontal
  position, height, roll/pitch, yaw, the horizontal or height integral (the slowest modes), or
  rotor lag.
- **Bode:** inputs setpoint x, y, z, yaw and a disturbance force along x; outputs x, y, z, and yaw.
  (With the attitude controller: roll, pitch, and yaw commands and setpoint z, to roll, pitch, yaw,
  and z.)
- **Summary:** termination, hover thrust per rotor (m g / 4), hover rotor speed, thrust-to-weight
  ratio, final position error, maximum tilt, peak rotor thrust, time saturated, maximum yaw rate,
  final height, and, where they apply, the settling time and overshoot of a step and the ground
  contact speed.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Steady hover (m = 1 kg, and m = 1.7 kg at 30° yaw) | every rotor gives m g / 4 within 10⁻⁹ N; the mixer splits pure lift exactly equally |
| Mixer within its limits | A T equals the wanted [F; τ] within 10⁻¹²; saturated, roll, pitch, and thrust are kept and yaw is cut |
| 2° roll command, attitude controller | the nonlinear roll follows the closed-loop linearization (expm) within 2 % of the step |
| Inner loop with a fast rotor (τ = 2 ms) | roll poles within 5 % of the roots of s² + Kw s + Kr |
| Free fall (rotors off, no drag) from 20 m | z = z0 − g t²/2 within 10⁻⁸ m; crashes at t = √(2 z0/g) with speed √(2 g z0) |
| Torque-free spin (rotors at hover thrust, no control) | world angular momentum R I ω and the rotational energy constant within 10⁻⁷ (relative) |
| Rotor 1 stops at 2 s | yaw rate 0 before; above 3 rad/s after; it crashes; two runs are identical |
| Closed loop at hover | an equilibrium; stable; DC gain from each setpoint to its output 1; a steady force leaves no offset with the integral, and F/(m Kp) without it |
| Height step 3 → 6 m | settles (5 %) within 3 s, overshoot under 10 %, never saturated; with 3.5 N rotors a 17 m climb saturates for over 1 s |

## Lesson

**Keeping a quadrotor in the air** finds the hover thrust per rotor (and how it grows with mass),
watches the rotor limit cap a climb and raises it, then stops a motor to see the yaw spin up, and
ends with a damaged rotor that keeps flying.
