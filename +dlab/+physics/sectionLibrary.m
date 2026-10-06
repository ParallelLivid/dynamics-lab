function lib = sectionLibrary()
%SECTIONLIBRARY Structural materials and cross-section shapes.
%   lib = dlab.physics.sectionLibrary() returns a struct:
%     MaterialNames, MaterialLabels   steel, aluminium, timber, custom
%     E (GPa), Yield (MPa)            for each material (NaN for custom)
%     ShapeNames, ShapeLabels         tube, rod, box, bar, custom
%     Columns                         the section row layout (see below)
%     Default                         a model's section when it has none
%     properties                      @(shape, D, t) [A (cm²), I (cm⁴), c (mm)]
%
%   properties takes the shape as an index into ShapeNames or as a name,
%   the outer size D (diameter or width) and the wall t in mm, and returns
%   the area A, the second moment of area I (about the weakest axis: the
%   one a member buckles about), and the distance c = D/2 from the
%   centroid to the outer fibre (bending about an axis parallel to a side
%   for the square shapes). All NaN when the dimensions do not make the
%   shape, and for custom.
%
%   A section row (the truss's) is [material shape E yield D t A I]:
%   material and shape as indices into the lists, then E (GPa), the yield
%   stress (MPa), D and t (mm, unused for custom shapes), A (cm²), I (cm⁴).
%
%   Materials (typical design values): A36 structural steel, E = 200 GPa,
%   yield 250 MPa; aluminium 6061-T6, 69 GPa, 276 MPa; C24 structural
%   softwood, 11 GPa, 21 MPa (its characteristic compressive strength
%   along the grain, used for tension too).
%
%   The default section is A36 steel with A = 100 cm² (the truss solver's
%   original 0.01 m²) and I = 8820 cm⁴, about a 273 × 12.7 mm steel tube.
lib.MaterialNames = ["steel" "aluminium" "timber" "custom"];
lib.MaterialLabels = ["Steel (A36)" "Aluminium (6061-T6)" "Timber (C24)" "Custom"];
lib.E = [200 69 11 NaN];
lib.Yield = [250 276 21 NaN];
lib.ShapeNames = ["tube" "rod" "box" "bar" "custom"];
lib.ShapeLabels = ["Round tube" "Solid rod" "Square box" "Solid square" "Custom"];
lib.Columns = ["material" "shape" "E" "yield" "D" "t" "A" "I"];
lib.Default = [1 5 200 250 0 0 100 8820];
lib.properties = @(shape, D, t) properties(shape, D, t, lib.ShapeNames);
end

function [A, I, c] = properties(shape, D, t, names)
[A, I, c] = deal(NaN);
if ~isnumeric(shape)
    shape = find(names == string(shape), 1);
    if isempty(shape)
        return
    end
end
c0 = D / 2;
D = D / 10;                       % mm → cm
t = t / 10;
switch shape
    case 1                        % round tube
        if D > 0 && t > 0 && 2 * t < D
            d = D - 2 * t;
            A = pi / 4 * (D^2 - d^2);
            I = pi / 64 * (D^4 - d^4);
            c = c0;
        end
    case 2                        % solid rod
        if D > 0
            A = pi / 4 * D^2;
            I = pi / 64 * D^4;
            c = c0;
        end
    case 3                        % square box
        if D > 0 && t > 0 && 2 * t < D
            b = D - 2 * t;
            A = D^2 - b^2;
            I = (D^4 - b^4) / 12;
            c = c0;
        end
    case 4                        % solid square
        if D > 0
            A = D^2;
            I = D^4 / 12;
            c = c0;
        end
end
end
