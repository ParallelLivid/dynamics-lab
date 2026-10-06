# Inverted Pendulum on a Cart

Balance a pole upright on a cart that runs on a track: open-loop instability, PID and LQR
control, reference tracking, disturbance rejection, and the effect of a motor's force limit.

## Model

θ is measured from upright (positive leaning toward +x); x is the cart's position. l is the
distance from the pivot to the pole's centre of mass, and I the pole's inertia about its centre
of mass: 0 for a point mass at distance l on a massless rod, m (2l)²/12 for a uniform rod, which
is then **2l long** (l is half its length). From Lagrange's equations with
T = ½ (M + m) ẋ² + m l cos θ ẋ θ' + ½ (I + m l²) θ'² and V = m g l cos θ, and with
D = (M + m)(I + m l²) − m² l² cos² θ:

```text
ẍ  = [(I + m l²)(F − b ẋ + m l θ'² sin θ) − m² l² g sin θ cos θ] / D
θ'' = [(M + m) m g l sin θ − m l cos θ (F − b ẋ + m l θ'² sin θ)] / D
```

F is the horizontal force on the cart (the motor's plus the disturbance); b is viscous friction
on the cart (the pivot turns freely). Linearized about upright at rest, the pole topples at the
rate √((M + m) m g l / ((M + m)(I + m l²) − m² l²)) without friction: 3.974 1/s for the default
uniform rod (M = 1 kg, m = 0.1 kg, l = 0.5 m), 3.971 1/s with the default friction.

**Controllers:**

| Controller | Force |
|---|---|
| None | F = 0 |
| PID on the angle, with a cart PD loop | F = Kp θ + Ki ∫θ dt + Kd θ' + Kx (x − x_ref) + Kv ẋ (positive gains push the cart under the pole) |
| LQR | F = −K (s − [x_ref 0 0 0]), K from `dlab.physics.lqr` on the upright linearization with Q = diag(q_x, q_ẋ, q_θ, q_θ') and R = r (θ in rad, x in m, F in N) |

The integral acts on the angle, which the linear model ties to the speeds: the pole's equation
integrates to m l ẋ + (I + m l²) θ' = m g l ∫θ dt + constant. So Ki adds a neutral mode (a second
closed-loop pole at 0) and works like a small cart-speed gain plus a constant force; it does not
hold the cart. LQR needs q_x > 0: with q_x = 0 nothing in the cost sees the cart's position (a
neutral mode), and the Riccati equation has no stabilizing solution.

The motor's force is clipped to ±Fmax; the disturbance force (a schedule, e.g. a pulse) is added
on top, and the cart's target x_ref is a schedule too (a step moves the cart; it is kept on the
track). Integrated with `ode45` (RelTol 10⁻⁸, AbsTol 10⁻¹⁰, maximum step 0.01 s). The run ends when
the cart's centre reaches an end of the track (±half its length), or when the pole passes
horizontal (|θ| = 90°), unless **Keep going after the pole falls**; then the fall is only
reported.

## Inputs

| Group | Inputs |
|---|---|
| Cart and pole | Cart mass, pole mass, pivot to centre of mass l, uniform rod or point mass, cart friction, gravity |
| Start | Tilt and tilt rate (degrees), cart position and speed |
| Controller | None, PID (Kp, Ki, Kd, Kx, Kv), or LQR (four state weights and r) |
| Actuator | Motor force limit (with a controller) |
| Commands | Cart target position (with a controller), disturbance force (schedules) |
| Track | Length, keep going after a fall |
| Simulation | Duration, output step |

Every input has a tooltip with its meaning and units.

**Presets:** falls without control (in 0.92 s); PID on the angle (balances, but the cart drifts
1.9 m in 8 s); PID with the cart loop; LQR (the default: a 5° start, back within 1° in 0.89 s);
LQR moving the cart 1 m (it first backs away 7 cm); a weak motor (2 N, a 10° start: saturated
98 % of the time, the cart races under the pole, overshoots, and hits the end stop at 1.57 s
with the pole falling back the other way; 2.81 N is the least that catches it); and a kick
(a 10 N, 0.1 s pulse).

## Outputs

- **Animation:** the track with its end stops, the cart on its wheels, the pole (a rod 2l long,
  or a ball at l), the motor force as an arrow (amber while saturated), the target position, and
  a flash during a disturbance.
- **Angle and position** (θ with the ±1° band; x with the target and the track ends), **Control
  force** (commanded and applied, the ±Fmax band, the disturbance), **Phase portrait** (θ, θ'),
  and **Gains and poles** (open- and closed-loop poles in the s-plane, the gains, and the
  controller's law).
- **Modes:** the closed loop with the selected controller (with the integral state when Ki ≠ 0),
  ignoring the force limit. Modes are Topple (unstable), Cart drift (neutral), Oscillation, or
  Settling: without control the pole topples (3.971 1/s), its mirror image settles (−3.977 1/s),
  the cart's speed dies away under friction (−0.091 1/s) and its position drifts (0); with LQR
  every mode settles.
- **Bode:** from the disturbance force to the cart position and velocity and the pole angle and
  rate (rad, rad/s), with the selected controller closed around them (without control the plant
  is unstable, so its frequency response is that of the transfer function, not a steady
  response). With a controller, the loop gain broken at the cart force,
  L(s) = −(the controller's force)/(the injected force): for LQR, L = K (sI − A)⁻¹ B. The open loop
  has the toppling pole, so the phase rises through −180° below the crossover: the gain margin is
  negative, the amount by which the gain may **fall** (LQR guarantees at least a factor ½, −6 dB;
  the defaults allow −10.7 dB) while it may rise without limit, and LQR's phase margin is at least
  60° (65.2° at the defaults).
- **Summary:** settling time (θ within 1° to the end; a dash with the reason when it does not
  settle), max |θ|, max |F|, time saturated, the largest cart excursion, the open-loop unstable
  pole; with a controller also the final x error, the slowest closed-loop pole (its real part),
  and the cart overshoot (for a target step). The status line warns when the pole fell, the cart
  hit an end stop, or the linear closed loop is unstable.
- **Export:** time, x, cart speed, θ and θ' (degrees), commanded and applied force, disturbance,
  and target, each with its units.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Equations of motion | equal Lagrange's equations in mass-matrix form (rod and point mass, random states) to 10⁻¹² |
| Open-loop unstable pole, point mass, no friction | √(g (M + m) / (M l)) (10⁻⁸); the linear model is the Jacobian of the nonlinear one |
| Same, uniform rod | √((M + m) m g l / ((M + m)(I + m l²) − m² l²)) = 3.97388 1/s |
| LQR gain, defaults | K = [−10 −12.2346 −78.1067 −18.6767], equal to the Hamiltonian's stable-eigenvector solution (10⁻⁹); closed-loop poles −1.3436 ± 0.9895i, −6.4029 ± 3.2497i |
| LQR, 5° start (default) | settles within 3 s; Riccati residual < 10⁻¹⁰ |
| LQR loop gain, defaults | \|1 + L\| ≥ 1; phase margin 65.2° at 15.12 rad/s; gain margin −10.70 dB at 3.294 rad/s (≤ −6.02 dB) |
| PID closed-loop poles | the roots of the characteristic polynomial, for four gain sets; PD on the angle alone has a slow unstable pole (+0.0333 1/s) |
| No control, no friction | energy and horizontal momentum conserved to 10⁻⁷ as the pole falls and swings round |
| Weak motor (2 N, 10°) | saturated, end stop at 1.5741 s, θ = −43.83°; 2.85 N catches it, 2.8 N does not |
| Same with Fmax = 1 N | the pole falls |
| PID on the angle only | a closed-loop pole at 0 (the cart drifts); with the cart loop all poles are stable |
| 10 N kick for 0.1 s | the pole is back within 1° by 4 s |
| Reference step of 1 m | the cart first backs away, then ends within 1 cm of the target |

## Lessons

**Balancing a pole** shows the toppling mode, PID on the angle (the cart drifts), LQR doing both
jobs, the effect of the control weight r, and the smallest motor that can still catch a 10° tilt.

**Tuning by search** lets Analyze ▸ Optimize choose r for the fastest recovery within a 5 N force
budget (r ≈ 0.29: 1.05 s), then r and q_x together, which finds a faster recovery by letting the
cart wander three times as far: the search optimizes only what it is asked to.
