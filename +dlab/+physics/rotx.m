function R = rotx(angle)
%ROTX Active rotation by ANGLE (rad) about the x axis: v' = R * v.
%   See also dlab.physics.roty, dlab.physics.rotz.
arguments
    angle (1,1) double
end
c = cos(angle);
s = sin(angle);
R = [1 0 0; 0 c -s; 0 s c];
end
