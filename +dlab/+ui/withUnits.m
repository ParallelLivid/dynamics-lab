function text = withUnits(label, unit)
%WITHUNITS An axis or list label with its units: "Speed (m/s)".
%   text = dlab.ui.withUnits(label, unit) appends " (unit)" to each
%   label whose unit is not empty and leaves the others as they are.
%   LABEL and UNIT are string arrays of the same size.
text = string(label);
unit = string(unit);
hasUnits = unit ~= "";
text(hasUnits) = text(hasUnits) + " (" + unit(hasUnits) + ")";
end
