function openMenuBelow(menu, button)
%OPENMENUBELOW Open a uicontextmenu just below BUTTON, as a drop-down
%   menu (the Export ▾ and Lessons ▾ buttons).
position = getpixelposition(button, true);
open(menu, position(1), position(2));
end
