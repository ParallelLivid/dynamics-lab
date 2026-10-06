function pixels = tableRowHeight(fontSize)
%TABLEROWHEIGHT Height in pixels of one row of a uitable at FONTSIZE, for
%   sizing a table to show its rows without empty space below them.
%   Measured in R2025b: 19 rows at 12 pt take 443 px, 11 rows at 16 pt
%   take 310 px. Not a whole number: round the height of several rows.
pixels = 1.225 * fontSize + 8.6;
end
