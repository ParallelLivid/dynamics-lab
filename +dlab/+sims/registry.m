function plugins = registry()
%REGISTRY Every simulator shown in Dynamics Lab, in Home-screen order.
%   Function handles rather than class-name strings, so MATLAB Compiler's
%   dependency analysis includes each plugin in the standalone build.
%   tests/ArchitectureTest.m fails if a +dlab/+sims/+<id> package exists
%   without an entry here.
%
%   Home lists categories in the order their first simulator appears here:
%   Mechanics, Controls & Vehicles, Aerospace, Structural, Continuum. Keep
%   each category's simulators together.
plugins = {
    @dlab.sims.pendulum.PendulumPlugin
    @dlab.sims.massspring.MassSpringPlugin
    @dlab.sims.projectile.ProjectilePlugin
    @dlab.sims.nonlinear.NonlinearPlugin
    @dlab.sims.attractors.AttractorsPlugin
    @dlab.sims.rigidbody.RigidBodyPlugin
    @dlab.sims.collisions.CollisionsPlugin
    @dlab.sims.dcmotor.DcMotorPlugin
    @dlab.sims.cartpole.CartPolePlugin
    @dlab.sims.quartercar.QuarterCarPlugin
    @dlab.sims.handling.HandlingPlugin
    @dlab.sims.orbit.OrbitPlugin
    @dlab.sims.maneuvers.ManeuversPlugin
    @dlab.sims.flyby.FlybyPlugin
    @dlab.sims.threebody.ThreeBodyPlugin
    @dlab.sims.rocket.RocketPlugin
    @dlab.sims.entry.EntryPlugin
    @dlab.sims.attitude.AttitudePlugin
    @dlab.sims.flight6dof.Flight6dofPlugin
    @dlab.sims.quadrotor.QuadrotorPlugin
    @dlab.sims.truss.TrussPlugin
    @dlab.sims.frame.FramePlugin
    @dlab.sims.column.ColumnPlugin
    @dlab.sims.wave.WavePlugin
    @dlab.sims.membrane.MembranePlugin
    @dlab.sims.heat.HeatPlugin
    @dlab.sims.plate.PlatePlugin
};
end
