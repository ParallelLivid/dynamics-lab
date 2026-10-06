function R = rotz(angle)
%ROTZ Active rotation by ANGLE (rad) about the z axis: v' = R * v.
%   See also dlab.physics.rotx, dlab.physics.roty.
arguments
    angle (1,1) double
end
c = cos(angle);
s = sin(angle);
R = [c -s 0; s c 0; 0 0 1];
end
