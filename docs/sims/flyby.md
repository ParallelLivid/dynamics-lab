# Gravity Assist

A spacecraft swings past a planet. In the planet's frame it follows a hyperbola and leaves as
fast as it came, only turned; in the Sun's frame the planet's own motion is added, so the turn
becomes a change of speed and of orbit. Passing behind the planet gains speed, passing ahead
loses it.

## Model

**Planet frame.** Two-body motion r̈ = −μ r / |r|³ (km, km/s) in the plane of the encounter.
The spacecraft starts on the analytic hyperbola with excess speed v∞ and periapsis radius
r_p = R + altitude (e = 1 + r_p v∞²/μ, impact parameter b = r_p √(1 + 2μ/(r_p v∞²)),
the start found from the hyperbolic Kepler equation e sinh F − F = n t), and `ode113` (relative
tolerance 10⁻¹²) integrates it through periapsis. The run lasts ± f · r_p/v∞ around periapsis
(f is the duration factor), at most the crossing of the sphere of influence
r_SOI = a (m/M)^(2/5). Output times are crowded near periapsis (t ∝ sinh).

**Turning angle.** The analytic value is δ = 2 asin(1/e). The integrated value is the angle
between the incoming asymptote of the first state and the outgoing asymptote of the last, each
from that state's osculating hyperbola. This removes the bias of starting at a finite distance:
the plain angle between the end velocities (also computed) falls short of δ by an amount that
shrinks as the run starts farther out. The flyby's Δv is v∞,out − v∞,in, of size 2 v∞ sin(δ/2).

**Which way v∞ turns.** "Behind" puts the periapsis on the planet's trailing side, so Δv points
along the planet's motion; "ahead" puts it on the leading side. Either is possible when
δ/2 < |α| < 180° − δ/2 (α is the direction of v∞,in from the planet's velocity); otherwise
both passes gain or both lose, and the app says so.

**Sun frame (patched conic).** The planet moves on a circle of radius a at V_p = √(μ_Sun/a); at
the encounter it is at (0, −a) moving along +x, so in both frames +x is the planet's motion and
+y points to the Sun. The heliocentric velocity is V_p + v∞,in before and V_p + v∞,out after;
the orbits before and after, through the planet's position, follow from the vis-viva equation
(perihelion p/(1 + e), aphelion p/(1 − e), p = h²/μ_Sun). The specific orbital energy changes by
V_p · (v∞,out − v∞,in).

**Heliocentric speed over time.** Inside the sphere of influence: |V_p + v(t)| on the analytic
hyperbola (the planet moving straight on at V_p meanwhile). Outside it: two-body motion about
the Sun (`ode45`), started from the hyperbola's state at the sphere's edge so the legs join.

**Constants.** μ and radii from `dlab.physics.bodyConstants`; the planets' mean orbital radii and
speeds from the NASA Planetary Fact Sheet, kept in `dlab.sims.flyby.planetData`. The model uses
the circular speed √(μ_Sun/a), within 1.1 % of the tabulated mean speed (Mercury) and 0.3 % for
the others.

## Inputs

| Group | Inputs |
|---|---|
| Encounter | Planet (Mercury to Neptune), excess speed v∞, direction of v∞ (0° along the planet's motion, +90° toward the Sun), periapsis altitude, pass (behind: gain; ahead: lose) |
| Simulation | Duration factor (the run spans ± f · r_p/v∞) |
| Display | Mark the sphere of influence; heliocentric view in the animation |

**Presets:** a Voyager-like Jupiter assist (v∞ = 10.7 km/s, 277 400 km altitude, on an orbit
from about 1 to 8 AU; the default), a Cassini-like Venus assist (284 km), a Galileo-like Earth flyby
(960 km) that raises the aphelion from 1.27 to 2.74 AU, the Venus pass flown ahead of the planet
to slow down, a close Jupiter pass (4000 km) that turns v∞ by 154°, and a Mars flyby.

## Outputs

- **Animation:** the spacecraft along the hyperbola in the planet's frame with the planet to
  scale, its velocity as an arrow, and the readout (time from periapsis, distance in planet
  radii, planet-frame and heliocentric speed); beside it, the orbits around the Sun (optional).
- **Planet frame:** the path, the asymptotes, the periapsis, and the planet to scale; optionally
  the sphere of influence and the hyperbola out to it.
- **Velocity diagram:** V_p, v∞ in and out (on the circle of radius v∞), the heliocentric
  velocities before and after, and Δv.
- **Heliocentric speed:** before, inside the sphere of influence, and after, with the integrated
  run highlighted and the Sun's escape speed √2 V_p.
- **Heliocentric orbits:** the planet's orbit and the orbits before and after, Sun-centred (AU).
- **Summary:** δ integrated and analytic (°), the flyby Δv and 2 v∞ sin(δ/2), the planet-frame
  speed change, the heliocentric speeds before and after and the gain, the energy change,
  perihelion and aphelion before and after (AU; "unbound" when the spacecraft leaves the Sun),
  the eccentricity after, the closest approach and altitude, the hyperbola's eccentricity, the
  periapsis speed, V_p, and r_SOI.

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Turning angle, five encounters (Jupiter, Venus, Earth, Jupiter close, Mars) | integrated δ = 2 asin(1/(1 + r_p v∞²/μ)) within 10⁻⁶ rad |
| Planet frame | \|v∞,out\| = \|v∞,in\| within 10⁻⁹ (relative); energy constant within 10⁻⁸; closest approach = r_p |
| Flyby Δv | 2 v∞ sin(δ/2) within 10⁻⁸ (relative) |
| Heliocentric energy | changes by V_p · (v∞,out − v∞,in) |
| Behind / ahead | behind gains and ahead loses for α from 70° to 115° either side; the same \|δ\| |
| Earth → Jupiter Hohmann arrival | 7.413 km/s, v∞ = 5.643 km/s; orbit from 1 AU to Jupiter's; 2.73-year trip |
| Spheres of influence | Earth 925 000 km, Venus 616 000, Mars 577 000, Jupiter 48.2 million (Curtis, Table A.2) |
| Planet speeds | √(μ_Sun/a) within 1.2 % of the fact sheet's mean speeds; a circle at 1 AU takes 365.25 days |
| Voyager-like default (app test) | δ = 98.98°; speed 12.05 → 23.36 km/s; perihelion before 1.02 AU; unbound after |

## Lesson

**The slingshot** shows that nothing is gained in the planet's frame, that the heliocentric speed
still changes, that closer passes turn more, that passing behind gains while passing ahead loses,
and that a Galileo-like Earth flyby raises the aphelion past Mars.
