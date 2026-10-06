"""The video's running order and captions (45 s)."""


def build(g):
    App = g["AppScene"]
    T = 4.8
    membrane = App("membrane", "Continuum", "Vibrating membrane",
                   "A drum struck off-centre, solved by finite differences", T, play=(0.0, 0.45))
    return [
        App("pendulum", "Mechanics", "Double pendulum",
            "The butterfly effect: a twin started a millionth of a degree away soon takes its own path", T),
        App("quadrotor", "Controls & vehicles", "Quadrotor",
            "A waypoint mission flown by cascaded position and attitude loops", T),
        App("rocket", "Aerospace", "Rocket ascent",
            "A two-stage launch to low Earth orbit: gravity turn, max-Q, and staging", T),
        App("truss", "Structures", "2-D truss solver",
            "A steel footbridge: member forces, with a yield and buckling check of every member", T),
        membrane,
        g["GridScene"](membrane, "27 simulators, one app",
                       "Mechanics, controls, aerospace, structures, and continuum", seconds=6.4),
        g["FeatureScene"](12.0),
        g["OutroScene"](5.0),
    ]
