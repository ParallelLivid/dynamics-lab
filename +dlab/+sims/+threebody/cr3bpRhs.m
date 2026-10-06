function ds = cr3bpRhs(s, mu)
%CR3BPRHS The circular restricted three-body equations in the rotating
%   frame, s = [x y z vx vy vz]: ẍ − 2ẏ = Ω_x, ÿ + 2ẋ = Ω_y, z̈ = Ω_z.
x = s(1);
y = s(2);
z = s(3);
r1 = sqrt((x + mu)^2 + y^2 + z^2);
r2 = sqrt((x - 1 + mu)^2 + y^2 + z^2);
a1 = (1 - mu) / r1^3;
a2 = mu / r2^3;
ds = [s(4); s(5); s(6)
      2 * s(5) + x - a1 * (x + mu) - a2 * (x - 1 + mu)
      -2 * s(4) + y - (a1 + a2) * y
      -(a1 + a2) * z];
end
