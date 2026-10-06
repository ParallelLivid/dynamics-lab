# 2-D Frame and Beam Solver

Beams and rigid frames in the plane: deflections, support reactions, and the bending moment,
shear, and axial force diagrams. The model is entered in tables, and nodes can be dragged on the
Model canvas.

## Model

The direct stiffness method with Euler–Bernoulli beam-column elements: three degrees of freedom
per node (u, v, θ), and the standard 6 × 6 element stiffness

```text
EA/L for stretching;  12EI/L³, 6EI/L², 4EI/L, 2EI/L for bending
```

turned into global axes (`T(c, s)`) and assembled. Supports hold their degrees of freedom (fixed:
u, v, θ; pin: u, v; roller moving in x: v; roller moving in y: u).

**Element loads** (uniform along the element, or a point load at a distance a from its start; in
global or local axes, or uniform per horizontal or vertical **projected** length, as for snow on
a roof) enter as their consistent fixed-end nodal loads. **Hinges** (moment releases at an
element end) are condensed out of the element; a node where every element end is hinged has its
rotation held, as it carries no moment.

**Results:** the nodal displacements, the reactions (K U − F at the held degrees of freedom), and
each element's end forces in its own axes. Along each element the axial force N, shear V, and
moment M are exact for uniform and point loads, and so is the **deflected shape**: the Hermite
cubic through the end displacements plus the fixed-end beam's own deflection under the span load
(for example w x² (L − x)² / 24EI), so mid-span deflections need no extra elements. The maxima
are read at 101 points per element plus the points where a uniform load's shear is zero, so the
moment peaks are exact and the deflection peaks within 10⁻⁵.

A model that can move without resistance (a **mechanism**) is reported with the node and
direction that would move, from the null space of the stiffness matrix.

Sign conventions: N positive in tension; M positive sagging and drawn on the tension side.

## Inputs

| Group | Inputs |
|---|---|
| Geometry | Nodes (x, y in m); elements (start and end node, E in GPa, A in cm², I in cm⁴, hinges at either end) |
| Supports and loads | Supports (node, type); node loads (Fx, Fy in kN, M in kN·m); element loads (element, uniform or point, global, local, or projected, x and y parts, a) |
| Display | Deflection scale (0 = automatic), label the diagrams, show labels, drag snap |

Elements default to steel (E = 200 GPa) with an IPE 300 section (A = 53.8 cm², I = 8356 cm⁴).

**Presets:** a cantilever with a tip load (the default), a simply supported beam under a uniform
load, a fixed-end beam, a propped cantilever, a three-span continuous beam, a portal frame under
wind and gravity loads, and a pinned gable frame under snow.

## Outputs

- **Model:** elements, supports, hinges, loads, and labels. Drag a node to move it (it snaps to
  the grid); each drag is one input change and one undo step.
- **Deflected shape:** the undeformed frame dotted and the deflected one scaled, with the nodal
  displacements.
- **Bending moment, Shear force, Axial force:** each drawn across the elements, positive and
  negative parts in different colours, with each element's extreme value labelled.
- **Results:** tables of nodal displacements and rotations, reactions, and element end forces.
- **Summary:** max |M| (with its element and its position from the element's start), max |V|,
  max |N|, the largest
  displacement, the equilibrium residual (|ΣF| + |ΣM| about the origin over the load scale, about
  10⁻¹⁵), and the degree of static indeterminacy 3m + r − 3j − (hinges), where k hinged ends
  meeting at a node with no other rotational restraint count as k − 1 (one pin).

## Reference results (asserted by the tests)

| Check | Value |
|---|---:|
| Cantilever, tip load P | tip deflection PL³/3EI, rotation PL²/2EI, root moment PL (10⁻¹⁰) |
| Simply supported, uniform load | M = wL²/8 and δ = 5wL⁴/384EI at mid-span (10⁻¹⁰) |
| Fixed–fixed, uniform load | end moments wL²/12, mid-span wL²/24, δ = wL⁴/384EI |
| Propped cantilever, uniform load | prop reaction 3wL/8 |
| Two equal spans, uniform load | middle-support moment wL²/8 |
| Point load at L/3; hinge in a fixed–fixed beam | M = Pab/L and a shear jump of P; zero moment at the hinge |
| Fixed-base portal, side load H, h = L, equal EI | base moments 2Hh/7, top moments 3Hh/14 (slope-deflection) |
| A beam on one pin | a mechanism error naming node B |

## Lesson

**Beams and frames** checks the cantilever formula, compares the simply supported and fixed-end
beams, shows a portal frame swaying, and drags a node to change the frame's shape.
