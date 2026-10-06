function label = nodeLabel(index)
%NODELABEL Spreadsheet-style node names: 1 → "A", 26 → "Z", 27 → "AA".
arguments
    index (1,1) double {mustBeInteger, mustBePositive}
end
letters = 'A':'Z';
label = '';
n = index;
while n > 0
    n = n - 1;
    label = [letters(mod(n, 26) + 1) label]; %#ok<AGROW>
    n = floor(n / 26);
end
label = string(label);
end
