# Vehicle Handling

A car turning at constant speed on the single-track ("bicycle") model: how the balance between
the front and rear tyres makes it understeer or oversteer, why an oversteering car spins above
its critical speed, a double lane change, and what happens at the tyres' friction limit.

## Model

```text
m (v' + V r) = F_f + F_r              lateral force balance (v lateral velocity, r yaw rate)
I_z r'       = a F_f − b F_r          yaw moment about the centre of mass
α_f = (v + a r)/V − δ                 front slip angle (δ the road-wheel steering angle)
α_r = (v − b r)/V                     rear slip angle
X' = V cos ψ − v sin ψ,  Y' = V sin ψ + v cos ψ,  ψ' = r        the path from above
```

Each axle's two tyres are lumped into one, a distance a (front) and b (rear) from the centre of
mass; L = a + b is the wheelbase. The forward speed V is constant. y and positive angles point
to the left. Tyre force per axle:

- **Linear:** F = −C α, with the axle's cornering stiffness C (N/rad).
- **Saturating:** F = −μ F_z tanh(C α / (μ F_z)), with the static axle loads F_zf = m g b/L and
  F_zr = m g a/L. It has the linear slope at small slip and never exceeds μ F_z.

The lateral acceleration is a_y = v' + V r = (F_f + F_r)/m, and the sideslip angle
β = atan(v/V). The equations are integrated with `ode45` (relative tolerance 10⁻⁸). The run stops
if |β| passes 30°: the car has spun, and a constant-speed, small-angle model no longer applies.

**Linear analysis** (linear tyres, x = [v; r]):

```text
K = (m/L)(b/C_f − a/C_r)              understeer gradient, rad per m/s² (shown in deg/g)
r/δ = V / (L + K V²)                  steady-state yaw-rate gain
V_char = √(L/K)   (K > 0)             characteristic speed: r/δ peaks there, at V/(2L)
V_crit = √(−L/K)  (K < 0)             critical speed: unstable above it
```

K > 0 is understeer (the front tyres need more slip than the rear), K = 0 neutral steer
(r/δ = V/L, as if the tyres did not slip), and K < 0 oversteer. The engine computes the gain from
the steady state of the linear model, −A⁻¹B, and the tests compare it with the formula.

## Inputs

| Group | Inputs |
|---|---|
| Car | Mass, yaw moment of inertia, centre of mass to the front and rear axles, front and rear cornering stiffness (per axle, N/rad) |
| Tyres | Tyre model (linear or saturating); friction coefficient μ (saturating) |
| Driving | Speed (km/h); steering at the road wheels (°, a schedule: step, ramp, sine, doublet, custom points…) |
| Simulation | Duration, output step |

**Presets:** an understeering family car (1500 kg, a = 1.1 m, b = 1.6 m, C_f = 80 kN/rad,
C_r = 110 kN/rad; K = 3.12 °/g) with a 2° step at 100 km/h (the default); a neutral-steer car
(a = b, equal tyres) with a 1° step at 80 km/h; an oversteering car (a = 1.5 m, b = 1.2 m,
C_f = 90 kN/rad, C_r = 75 kN/rad; V_crit = 97.2 km/h) at 70 km/h and at 120 km/h, where it spins;
a double lane change at 80 km/h (custom steering points, about 3.2 m to the left over 45 m, and back);
the tyre limit (saturating tyres, μ = 0.9, steering ramped to 8° at 80 km/h); and a slalom (2°
sine steering every 2 s at 60 km/h).

## Outputs

- **Animation:** the car from above (body and four wheels, the front wheels turned by δ),
  followed by the view, with its path behind it. Arrows show the velocity of the centre of mass
  (its angle to the car's axis is the sideslip β) and the front and rear tyre forces.
- **Path** (from above to scale, with the car drawn at eight instants, and the lateral position
  y against x stretched below it), **Yaw rate and lateral
  acceleration** (yaw rate with the linear steady state gain × δ dashed; a_y in g, with the
  friction limit μ g for saturating tyres), **Sideslip and slip angles**, **Steering**, and
  **Yaw gain vs speed** (r/δ against speed for this car and the neutral car V/L, with the run's
  speed and the characteristic or critical speed marked).
- **Modes:** [v, r] linearized for straight driving. A complex pair is named Yaw–sideslip
  oscillation; real modes are Yaw mode or Sideslip mode by which motion dominates the
  eigenvector (r L against v), and an unstable root is the Spin divergence. The
  frequency-response fields take the steering angle (rad) as the input and give the yaw rate
  (rad/s) and the lateral acceleration (m/s²); the Bode tab shows them with these units.
- **Summary:** the steady-state yaw-rate gain (1/s, when stable), the neutral-steer gain V/L,
  the understeer gradient (deg/g), the characteristic speed (understeer) or critical speed
  (oversteer) in km/h, the peak lateral acceleration (g), the peak yaw rate (°/s), the peak
  sideslip angle (°), the final heading (°), whether the linear model is stable, and whether
  the car spun (yes or no). With linear tyres a spin has no grip limit, so the peaks of a run
  that spun (several g) are not physical; the status line says so.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Family car, 100 km/h | K = (m/L)(b/C_f − a/C_r) = 0.0055556 rad/(m/s²) = 3.123 °/g; r/δ = V/(L + K V²) from −A⁻¹B to 10⁻¹⁰ and at the end of a step-steer run to 10⁻⁵ |
| Family car at V_char = √(L/K) | r/δ = V/(2L), and lower at 0.8 and 1.25 V_char |
| Neutral steer (a = b, C_f = C_r) | K = 0, r/δ = V/L |
| Oversteering car | V_crit = √(−L/K) = 27.0 m/s; eigenvalues stable at 0.95 V_crit, one positive at 1.05 V_crit, det A = 0 at V_crit; a run at 0.8 V_crit settles at V/(L + K V²) (to 10⁻⁵), one at 1.2 V_crit spins |
| Saturating tyres, 0.2° step | yaw rate and a_y within 1 % of the linear model |
| Saturating tyres, 8° at 80 km/h (linear tyres: 1.3 g) | a_y levels off between 0.95 μ g and μ g, with the front slipping more than 1.5 × the rear; at 15° the car slides out, and a_y still never passes μ g |
| Steady turning | the path is a circle of radius \|velocity\|/r (to 10⁻⁵); with no steering, x = V t, y = 0 |
| Step steer, family car at 100 km/h (app) | settles at a_y = V²δ/(L + K V²); peak 3.4 % higher (damping ratio 0.66) |
| Double lane change preset (app) | peak y = 3.25 ± 0.1 m, back to y = 0 ± 0.1 m and heading 0 ± 1° |
| Frequency-response fields | DC gains −C A⁻¹B + D = r/δ and a_y/δ = V r/δ |

## Lesson

**Understeer and oversteer** runs the neutral car (r/δ = V/L), finds the family car's
understeer gradient and the yaw gain at its characteristic speed, drives the oversteering car
past its critical speed until it spins, does a double lane change, and reaches the tyre limit,
where the car understeers.
