# Billiards and Gas Collisions

Hard discs in a box: a billiards break, a two-ball collision, Newton's cradle, and a gas of up to
400 discs that relaxes to the Maxwell–Boltzmann distribution, pushes on its walls, and kicks a
heavy tracer about (Brownian motion).

## Model

Discs move in straight lines between collisions; there are no time steps. The engine is
**event-driven**: for each disc it caches the time of its next event (with another disc, from the
quadratic `|Δr + Δv t| = r_i + r_j`, or with a wall, linear) and its partner. It takes the earliest
event, moves every disc to that time, applies the collision, and recomputes the involved discs and
every disc that expected to meet them. In a periodic box the nine nearest images are checked, and
crossing an edge is an event of its own.

Collisions are smooth (no friction or spin): the impulse `J = (1 + e) μ u` acts along the line of
centres (μ the reduced mass, u the approach speed); walls reflect with restitution e_w.
Approaches slower than 10⁻⁶ of the RMS speed are treated as elastic, which prevents inelastic
collapse, and the run stops at the event limit (default 200 000) as a guard.

There is no friction and no spin: billiard balls do not roll to a stop, and there are no pockets.
In a periodic box total momentum is conserved; walls change it.

**Starts:** a 15-ball triangle rack (apex at 0.72 of the table's length, the balls 0.001 r
apart) and a cue ball at a quarter of the length; a moving ball hitting a ball at rest
off-centre (the centres the Off-centre hit, in radii, apart across the motion: 1 radius puts the
line of centres at 30°); five balls in a row (Newton's cradle); or a gas of N discs in shuffled
cells of a grid (jittered by whatever room each cell leaves), all at the speed v0 or
Maxwell-distributed and scaled so that the mean of v² is exactly v0² (either way kT = ½ m v0²),
in random directions, optionally with a heavy tracer disc at the centre. Random numbers come from
a fixed generator seeded by the Random seed, so a seed always gives the same run.

## Inputs

| Group | Inputs |
|---|---|
| Discs | Start (gas, billiards, two balls, Newton's cradle); number (gas); radius, mass; restitution between discs and at the walls |
| Motion | Speed; starting speeds (equal or Maxwell) and seed (gas); cue speed and direction (billiards); off-centre hit (two balls) |
| Tracer | Heavy tracer disc, its mass and radius (multiples of the others') |
| Box | Width, height, walls or periodic edges |
| Simulation | Duration, output step, event limit |
| Display | Colour discs by speed |

**Presets:** a billiards break (pool-ball size and mass on a 2.24 × 1.12 m table), a two-ball
oblique collision, Newton's cradle, a gas relaxing to Maxwell (the default: 100 discs all at
1 m/s), a dense gas (39 % of the area filled), Brownian motion of a heavy tracer, and inelastic
cooling (e = 0.9). The Brownian preset uses a periodic box and runs 60 s, so no wall stops the
tracer.

## Outputs

- **Animation:** every disc (one patch, coloured by speed if chosen), the moving ball highlighted,
  the tracer's trail, and the box (dashed when periodic); the time and kinetic energy above it.
- **Energy and momentum** (kinetic energy and |total momentum| over time, both from zero).
- **Speed distribution** (gas): a histogram of the speeds over the second half of the run (the
  tracer left out), the starting distribution, and the 2-D Maxwell–Boltzmann
  `f(v) = (m v / kT) e^(−m v² / 2kT)` with kT the mean kinetic energy per disc over the same half
  (equipartition in 2-D: ⟨½ m v²⟩ = kT).
- **Pressure** (gas, walls): the measured pressure (wall impulses over the perimeter and the
  time, over the second half of the run, the same half as kT), the ideal gas N kT / A, and
  Henderson's hard-disc equation of state `P A / N kT = (1 + η²/8) / (1 − η)²` (η the packing
  fraction); and the running average from the start.
- **Tracer** (gas with a tracer): its path and its time-averaged mean-square displacement up to an
  eighth of the run (in a periodic box relative to the centre of mass, which drifts at P / M).
  The MSD curves at first (the tracer still remembers its velocity: MSD ≈ 2 kT t² / M), then
  grows in a straight line; D is a quarter of the slope of a line MSD = 4 D t + c fitted over the
  later half of the lags.
- **Collisions:** the disc–disc collision rate over time.
- **Summary:** collisions (total and per disc), wall hits, energy drift (elastic) or energy lost,
  momentum drift (periodic); for two balls the time of the collision, both speeds after it, and
  the angle between their paths; for a gas kT, the Kolmogorov–Smirnov distance from Maxwell, the
  packing fraction, P / P_ideal measured and by Henderson, and the tracer's diffusion coefficient.

### How far to trust the gas numbers

- **Pressure.** Henderson's equation is for an unbounded gas (periodic-box simulations of my own,
  through the virial theorem, agree with it to 0.3 %). In a small box the walls add to the
  measured pressure in proportion to r / L: +4.6 % for the defaults (100 discs), +7 % for the
  dense gas (200 discs); with 1600 discs a quarter the size, +1.2 %.
- **Diffusion.** One tracer in one run gives D only roughly: over 60 s it scatters by about ±50 %
  from seed to seed (a 1500 s simulation of the Brownian preset's gas gives D = 0.0080 m²/s, the
  velocity forgotten in τ ≈ 1.35 s). With walls the MSD levels off once the tracer has crossed
  the box. With no walls the tracer shares the conserved momentum with the gas, so its own
  kinetic energy is kT (1 − M / M_total), 25 % below kT in the preset.
- **Speeds.** The KS distance pools every sample of the second half, which are not independent:
  it measures closeness and is not a test with a p-value.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Head-on, equal masses, e = 1 | velocities exchange (10⁻¹⁴) |
| Head-on, masses 1 and 3 | the textbook 1-D velocities (10⁻¹²) |
| Oblique, equal masses, e = 1, target at rest | the balls leave at 90° (10⁻¹²); energy conserved |
| Oblique, line of centres at 30°, masses 1:1, 1:3, 3:1 | the closed form: the struck ball leaves along the line of centres at 2 m₁/(m₁ + m₂) cos 30° (10⁻¹⁴) |
| Two-ball preset | 90° apart, speeds 0.5 and 0.866 m/s, collision at t = 1 − 0.2 cos 30° s |
| Wall, e_w = 0.7 | the normal velocity reversed and scaled by 0.7; impulse m (1 + e_w) × normal speed |
| Billiards break (e = 0.95, e_w = 0.8) | the energy lost equals the sum over the 123 events (10⁻¹²); elastic, the same break keeps its energy (10⁻¹³) |
| Dense gas, sampled every 2 ms | no pair closer than r_i + r_j, no disc through a wall (10⁻¹²) |
| e = 0.6, one collision | ΔKE = −½ μ (1 − e²) u² (10⁻¹²) |
| Gas, 100 discs, e = 1, walls | energy constant to 10⁻¹²; over 200 collisions per disc; KS distance from Maxwell < 0.05 |
| Dense gas | Henderson's 2.764 exactly; measured P / P_ideal within 12 % of it (the walls add about 7 %) |
| Inelastic cooling | P / P_ideal within 15 % of Henderson; energy lost 97.95 ± 1 % (Haff's law) |
| Brownian preset | D between 0.0015 and 0.03 m²/s; the MSD fitted beyond 3 s |
| Maxwell start | mean v² exactly v0² |
| Periodic gas | total momentum constant to 10⁻¹²; no wall hits |
| Fixed seed | identical runs |
| Newton's cradle | only the last ball moves on |
| Overlapping start | an error naming the discs |

## Lesson

**From collisions to temperature** goes from one oblique collision (the 90° rule) to a gas that
relaxes to Maxwell–Boltzmann, its pressure against the ideal gas and Henderson, Brownian motion,
and inelastic cooling (Haff's law).
