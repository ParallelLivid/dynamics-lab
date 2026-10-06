function density = thermosphereDensity(altitude)
%THERMOSPHEREDENSITY Earth's air density from the ground to orbit (kg/m³).
%   rho = dlab.physics.thermosphereDensity(h) for geometric altitudes h in
%   km (any array). An exponential model fitted in bands: within each band
%   rho = rho0 · exp(−(h − h0)/H), with the base altitude h0, base density
%   rho0, and scale height H of Vallado, Fundamentals of Astrodynamics and
%   Applications (4th ed., 2013), Table 8-4, from the CIRA-72 atmosphere.
%   Above 1000 km the last band continues; below 0 km the first.
%
%   Unlike dlab.physics.atmosphere (ISA 1976, to 86 km) it reaches orbital
%   altitudes, where its scale height grows from 5 km near 90 km to over
%   50 km above 300 km. It is a mean model: the real thermosphere varies
%   several-fold with solar activity, which this does not model.
persistent table
if isempty(table)
    table = [ ...   % h0 (km), rho0 (kg/m³), H (km)
          0  1.225      7.249
         25  3.899e-2   6.349
         30  1.774e-2   6.682
         40  3.972e-3   7.554
         50  1.057e-3   8.382
         60  3.206e-4   7.714
         70  8.770e-5   6.549
         80  1.905e-5   5.799
         90  3.396e-6   5.382
        100  5.297e-7   5.877
        110  9.661e-8   7.263
        120  2.438e-8   9.473
        130  8.484e-9  12.636
        140  3.845e-9  16.149
        150  2.070e-9  22.523
        180  5.464e-10 29.740
        200  2.789e-10 37.105
        250  7.248e-11 45.546
        300  2.418e-11 53.628
        350  9.518e-12 53.298
        400  3.725e-12 58.515
        450  1.585e-12 60.828
        500  6.967e-13 63.822
        600  1.454e-13 71.835
        700  3.614e-14 88.667
        800  1.170e-14 124.64
        900  5.245e-15 181.05
       1000  3.019e-15 268.00];
end
band = discretize(altitude, [-Inf; table(2:end, 1); Inf]);
band = reshape(band, size(altitude));
h0 = reshape(table(band, 1), size(altitude));
rho0 = reshape(table(band, 2), size(altitude));
H = reshape(table(band, 3), size(altitude));
density = rho0 .* exp(-(altitude - h0) ./ H);
end
