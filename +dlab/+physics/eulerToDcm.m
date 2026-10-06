function R = eulerToDcm(phi, theta, psi)
%EULERTODCM Body-to-world rotation matrix from 3-2-1 Euler angles (rad).
%   R = dlab.physics.eulerToDcm(phi, theta, psi) maps body-axis vectors to
%   the world (e.g. NED) frame: v_world = R * v_body. It equals
%   rotz(psi) * roty(theta) * rotx(phi), written out in closed form.
arguments
    phi (1,1) double
    theta (1,1) double
    psi (1,1) double
end
R = [
    cos(theta)*cos(psi), ...
    sin(phi)*sin(theta)*cos(psi) - cos(phi)*sin(psi), ...
    cos(phi)*sin(theta)*cos(psi) + sin(phi)*sin(psi);
    cos(theta)*sin(psi), ...
    sin(phi)*sin(theta)*sin(psi) + cos(phi)*cos(psi), ...
    cos(phi)*sin(theta)*sin(psi) - sin(phi)*cos(psi);
    -sin(theta), sin(phi)*cos(theta), cos(phi)*cos(theta)];
end
