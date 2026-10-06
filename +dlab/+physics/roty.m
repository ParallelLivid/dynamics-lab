function R = roty(angle)
%ROTY Active rotation by ANGLE (rad) about the y axis: v' = R * v.
%   See also dlab.physics.rotx, dlab.physics.rotz.
arguments
    angle (1,1) double
end
c = cos(angle);
s = sin(angle);
R = [c 0 s; 0 1 0; -s 0 c];
end
