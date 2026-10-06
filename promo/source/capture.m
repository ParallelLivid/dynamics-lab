function capture(names)
%CAPTURE Record the scenes NAMES (from scenes.json) as PNG frame sequences
%   in frames/<name>/0001.png ... The window sits off-screen.
here = fileparts(mfilename("fullpath"));
addpath('C:\Users\natha\OneDrive\Desktop\Projects\wip\DynamicsLab');
setenv(dlab.core.Paths.EnvironmentVariable, string(tempname));
scenes = jsondecode(fileread(fullfile(here, "scenes.json")));
if ~iscell(scenes), scenes = num2cell(scenes); end
names = string(names);
for k = 1:numel(scenes)
    s = scenes{k};
    if ~ismember(string(s.name), names), continue, end
    out = fullfile(here, "frames", s.name);
    if isfolder(out) && string(field(s, "mode", "still")) ~= "anim", rmdir(out, "s"); end
    if ~isfolder(out), mkdir(out); end
    t0 = tic;
    try
        captureScene(s, out);
        fprintf("%-14s done in %.0f s\n", s.name, toc(t0));
    catch ME
        fprintf(2, "%-14s FAILED: %s\n%s\n", s.name, ME.message, getReport(ME));
    end
end
end

function captureScene(s, out)
theme = field(s, "theme", "dark");
sim = string(field(s, "sim", ""));
mode = string(field(s, "mode", "still"));
if mode == "home"
    setenv(dlab.core.Paths.EnvironmentVariable, string(tempname));
end
app = DynamicsLab(sim, Theme=theme, Visible=true);
closer = onCleanup(@() app.close());
app.Figure.Position = [-3000 40 1400 820];
drawnow; pause(1);
n = 0;
    function grab()
        drawnow;
        f = getframe(app.Figure);
        n = n + 1;
        imwrite(f.cdata, fullfile(out, sprintf("%04d.png", n)));
    end

if mode == "home"
    b = findall(app.Figure, Type="uibutton", Text="Got it");
    if ~isempty(b), b(1).ButtonPushedFcn(b(1), []); end
    drawnow; pause(1);
    g = findall(app.Figure, Type="uigridlayout", Scrollable="on");
    g = g(1);
    frames = s.frames;
    if getenv("PREVIEW") == "1", frames = 3; end
    for k = 1:frames
        u = (k - 1) / (frames - 1);
        e = u .^ 2 .* (3 - 2 * u);              % ease in and out
        scroll(g, 0, round(e * s.scroll));
        pause(0.05);
        grab();
    end
    return
end

v = app.View;
disp("  setup");
if isfield(s, "lesson")
    app.startLesson(s.lesson);
    v = app.View;
    step = field(s, "lessonStep", 1);
    v.lessonGo(step);
    v.lessonSetup(step);
elseif isfield(s, "setup")
    v.applySetup(s.setup);
elseif isfield(s, "preset")
    v.applyPreset("builtin:" + s.preset);
end
disp("  run");
if field(s, "run", true)
    v.run();
    if ~isempty(v.Playback), v.Playback.pause(); end
end
disp("  action/tab");
if isfield(s, "lesson") && field(s, "lessonCheck", false)
    v.lessonCheck(field(s, "lessonStep", 1));
end
action = string(field(s, "action", ""));
switch action
    case "sweep", v.runSweep();
    case "map", v.analysisPanel("Map"); v.runMap();
    case "optimize", v.analysisPanel("Optimize"); v.runOptimize();
    case "uncertainty", v.analysisPanel("Uncertainty"); v.runUncertainty();
end
if isfield(s, "tab")
    v.selectTab(s.tab);
end
if isfield(s, "dropdowns")          % {tag, label substring} pairs to pick
    d = s.dropdowns;
    for k = 1:2:numel(d)
        pick(app.Figure, d{k}, d{k+1});
    end
end
disp("  capture");
drawnow; pause(1.5);

if mode == "anim"
    p = v.Playback;
    p.pause();
    a = field(s, "t0", p.StartTime);
    b = field(s, "t1", p.EndTime);
    frames = s.frames;
    if getenv("PREVIEW") == "1", frames = 3; end
    for k = 1:frames
        if isfile(fullfile(out, sprintf("%04d.png", k)))   % resume
            n = k;
            continue
        end
        p.seek(a + (b - a) * (k - 1) / (frames - 1));
        grab();
    end
else
    if ~isempty(v.Playback)
        v.Playback.pause();
        if isfield(s, "t"), v.Playback.seek(s.t); end
    end
    pause(0.5);
    grab();
end
end

function pick(fig, tag, label)
dd = findall(fig, Type="uidropdown", Tag=tag);
assert(~isempty(dd), "No dropdown " + tag);
dd = dd(1);
items = string(dd.Items);
k = find(contains(items, label), 1);
assert(~isempty(k), "No item " + label + " in " + strjoin(items, " | "));
data = dd.ItemsData;
if isempty(data), data = dd.Items; end
if iscell(data), dd.Value = data{k}; else, dd.Value = data(k); end
dd.ValueChangedFcn(dd, struct("Value", dd.Value));
end

function v = field(s, name, default)
if isfield(s, name), v = s.(name); else, v = default; end
end
