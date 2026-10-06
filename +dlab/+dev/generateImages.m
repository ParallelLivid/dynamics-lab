function generateImages(options)
%GENERATEIMAGES Render Home thumbnails and README screenshots from the app.
%   dlab.dev.generateImages                       all simulators, both themes
%   dlab.dev.generateImages(Ids="pendulum")       one simulator
%
%   For each simulator, its showcase() scene (preset, tab, playback time)
%   is run and captured:
%     resources/thumbnails/<id>-<theme>.png   Home card images
%     docs/images/<id>.png                    full-window screenshot (dark)
%     docs/images/home.png                    the Home screen (dark)
%   Also available as "buildtool images".
arguments
    options.Ids (1,:) string = string.empty(1, 0)
    options.Themes (1,:) string = ["dark" "light"]
    options.Screenshots (1,1) logical = true
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
thumbnails = fullfile(root, "resources", "thumbnails");
images = fullfile(root, "docs", "images");
cellfun(@ensureFolder, {thumbnails, images});

% Keep the user's settings and scenarios out of it.
userData = string(tempname);
previous = getenv(dlab.core.Paths.EnvironmentVariable);
setenv(dlab.core.Paths.EnvironmentVariable, userData);
restore = onCleanup(@() setenv(dlab.core.Paths.EnvironmentVariable, previous));

plugins = dlab.sims.registry();
for k = 1:numel(plugins)
    plugin = plugins{k}();
    id = string(plugin.Id);
    if ~isempty(options.Ids) && ~ismember(id, options.Ids)
        continue
    end
    scene = plugin.showcase();
    for themeName = options.Themes
        app = DynamicsLab(id, Theme=themeName, Visible=true);
        closer = onCleanup(@() app.close());
        view = app.View;
        if scene.Preset ~= ""
            view.applyPreset("builtin:" + scene.Preset);
        end
        view.run();
        if ~isempty(view.Playback)
            view.Playback.pause();
            time = scene.Time;
            if isnan(time)
                time = (view.Playback.StartTime + view.Playback.EndTime) / 2;
            end
            view.Playback.seek(time);
        end
        view.selectTab(scene.Tab);
        drawnow;
        pause(0.5);                       % let uifigure finish rendering
        if options.Screenshots && themeName == "dark"
            exportapp(app.Figure, fullfile(images, id + ".png"));
        end
        % The card shows the plot about a quarter of its size, where tick
        % labels, titles, and legends are only noise: leave them out, and
        % draw lines and markers heavier.
        simplifyForThumbnail(view.Tabs.SelectedTab);
        drawnow;
        pause(0.3);
        view.exportPlot(fullfile(thumbnails, id + "-" + themeName + ".png"), Resolution=60);
        clear closer
        fprintf("%-11s %-5s done\n", id, themeName);
    end
end

if options.Screenshots && isempty(options.Ids)
    setenv(dlab.core.Paths.EnvironmentVariable, string(tempname));   % a first launch: no recent work
    app = DynamicsLab(Theme="dark", Visible=true);
    closer = onCleanup(@() app.close());
    drawnow;
    pause(0.5);
    exportapp(app.Figure, fullfile(images, "home.png"));
    clear closer
    fprintf("home        dark  done\n");
end
end

function simplifyForThumbnail(tab)
% Strip TAB's plots to their data for a small picture (the app is closed
% afterwards, so nothing is restored).
for ax = reshape(findall(tab, Type="axes"), 1, [])
    set(ax, XTickLabel={}, YTickLabel={}, ZTickLabel={}, TickLength=[0 0]);
    ax.Title.String = "";
    ax.Subtitle.String = "";
    [ax.XLabel.String, ax.YLabel.String, ax.ZLabel.String] = deal("");
    if ~isempty(ax.Legend)
        ax.Legend.Visible = "off";
    end
end
set(findall(tab, Type="colorbar"), Visible="off");
set(findall(tab, Type="text"), Visible="off");       % readouts and labels
for h = reshape(findall(tab, Type="line"), 1, [])
    h.LineWidth = min(3, 1.6 * h.LineWidth);
    h.MarkerSize = 1.5 * h.MarkerSize;
end
for h = reshape(findall(tab, Type="scatter"), 1, [])
    h.SizeData = 2.5 * h.SizeData;
end
end

function ensureFolder(folder)
if ~isfolder(folder)
    mkdir(folder);
end
end
