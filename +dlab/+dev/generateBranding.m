function generateBranding(options)
%GENERATEBRANDING Render the app icon and splash screen into resources/.
%   resources/icon.png     256×256 executable icon (an orbit around a body)
%   resources/splash.png   400×400 splash shown while MATLAB Runtime starts
%                          (square: MATLAB Compiler scales the splash to 400×400)
%   dlab.dev.generateBranding(Icon=false) redraws the splash only.
arguments
    options.Icon (1,1) logical = true
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
resources = fullfile(root, "resources");
t = dlab.ui.Theme.dark();

% Icon: a body with an elliptical orbit and a satellite.
if options.Icon
    [fig, ax] = canvas([256 256], t.Background);
    drawEmblem(ax, t, 1);
    axis(ax, [-1.2 1.2 -1.2 1.2]);
    saveCanvas(fig, fullfile(resources, "icon.png"));
end

% Splash: the emblem above the name and version.
[fig, ax] = canvas([400 400], t.Background);
drawEmblem(ax, t, 0.8);
axis(ax, [-1.5 1.5 -2.0 1.0]);
text(ax, 0, -0.95, "Dynamics Lab", FontSize=26, FontWeight="bold", Color=t.Accent, ...
    HorizontalAlignment="center");
text(ax, 0, -1.38, "Interactive physics simulators", FontSize=12, Color=t.TextMuted, ...
    HorizontalAlignment="center");
text(ax, 0, -1.72, "Version " + dlab.version() + "  ·  starting…", FontSize=10, Color=t.TextMuted, ...
    HorizontalAlignment="center");
saveCanvas(fig, fullfile(resources, "splash.png"));
fprintf("Wrote the branding to %s\n", resources);
end

function [fig, ax] = canvas(sizePixels, background)
fig = figure(Visible="off", Units="pixels", Position=[100 100 sizePixels], Color=background, ...
    InvertHardcopy="off", MenuBar="none", ToolBar="none");
ax = axes(fig, Units="normalized", Position=[0 0 1 1], Color=background, Visible="off");
hold(ax, "on");
axis(ax, "equal");
end

function drawEmblem(ax, t, scale)
% Fixed brand colours, so the emblem stays the same when the plot palette changes.
body = [89 184 242] / 255;
orbitColor = [242 230 102] / 255;
satelliteColor = [255 158 64] / 255;
angle = linspace(0, 2*pi, 200);
tilt = deg2rad(-25);
orbit = scale * [cos(angle) * 1.0; sin(angle) * 0.45];
rotation = [cos(tilt) -sin(tilt); sin(tilt) cos(tilt)];
orbit = rotation * orbit;
fill(ax, 0.42 * scale * cos(angle), 0.42 * scale * sin(angle), body, EdgeColor="none");
plot(ax, orbit(1, :), orbit(2, :), Color=orbitColor, LineWidth=6 * scale);
satellite = rotation * (scale * [cos(0.6); 0.45 * sin(0.6)]);
plot(ax, satellite(1), satellite(2), "o", MarkerSize=26 * scale, MarkerFaceColor=satelliteColor, ...
    MarkerEdgeColor=t.Background, LineWidth=3);
end

function saveCanvas(fig, file)
closer = onCleanup(@() close(fig));
print(fig, file, "-dpng", "-r0");    % -r0: exactly the figure's pixel size
end
