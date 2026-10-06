function report = captureVerification(id, options)
%CAPTUREVERIFICATION Screenshots and automatic checks for verifying one
%   simulator by hand (docs/verification/README.md).
%
%       dlab.dev.captureVerification("pendulum")
%
%   For every preset (and the defaults) it runs the simulator and saves the
%   whole window with each output tab and the Summary selected, plus the
%   animation at its start, middle, and end; for the defaults also the
%   Analyze tools that follow a run (Custom plot, Modes, Bode). It does this
%   in the dark and light themes, and once more for the defaults at the
%   largest text size. Pictures go to verification/<id>/ (not in git) with
%   an index.html to browse them.
%
%   The automatic checks, for every preset: the solve time; that every
%   Summary number appears in the metrics; that the exported table has a
%   unit for every column and no NaN or Inf; and that the result is the same
%   when solved twice (deterministic). REPORT is a table, one row per preset,
%   also written to verification/<id>/checks.csv. Then dlab.dev.checkBehaviour
%   exercises the simulator in the app (behaviour.csv).
arguments
    id (1,1) string
    options.Themes (1,:) string = ["dark" "light"]
    options.Screenshots (1,1) logical = true
    options.Frames (1,:) double = [0 0.5 1]     % animation times, as fractions of the run
end
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
folder = fullfile(root, "verification", id);
if ~isfolder(folder)
    mkdir(folder);
end
userData = string(tempname);
previous = getenv(dlab.core.Paths.EnvironmentVariable);
setenv(dlab.core.Paths.EnvironmentVariable, userData);
restore = onCleanup(@() setenv(dlab.core.Paths.EnvironmentVariable, previous));

plugin = dlab.core.Headless.plugin(id, dlab.sims.registry());
presets = ["Defaults", string({plugin.presets().Name})];

% ---- automatic checks (headless)
rows = cell(numel(presets), 7);
for k = 1:numel(presets)
    params = presetParams(plugin, presets(k));
    started = tic;
    result = plugin.solve(params);
    seconds = toc(started);
    again = plugin.solve(params);
    T = plugin.exportTable(result);
    M = plugin.metrics(result);
    S = plugin.summaryTable(result);
    numeric = S(isfinite(double(numericValues(S.Value))), :);
    missing = setdiff(string(numeric.Quantity), string(M.Quantity));
    units = string(T.Properties.VariableUnits);
    values = T{:, vartype("numeric")};
    rows(k, :) = {presets(k), seconds, height(T), numel(units) == width(T), ...
        nnz(~isfinite(values)), strjoin(missing, "; "), isequaln(plugin.exportTable(again), T)};
end
report = cell2table(rows, VariableNames=["Preset" "SolveSeconds" "ExportRows" "UnitsForEveryColumn" ...
    "NonFiniteExportValues" "SummaryNumbersNotInMetrics" "Deterministic"]);
writetable(report, fullfile(folder, "checks.csv"));
disp(report);
behaviour = dlab.dev.checkBehaviour(id);
writetable(behaviour, fullfile(folder, "behaviour.csv"));
disp(behaviour);

if ~options.Screenshots
    return
end

% ---- screenshots
shots = strings(0, 2);                 % file, caption
cases = [repmat("normal", 1, numel(options.Themes)), "larger"];
themes = [options.Themes, "dark"];
for c = 1:numel(cases)
    app = DynamicsLab(id, Theme=themes(c), Visible=true);
    closer = onCleanup(@() app.close());
    app.setTextSize(cases(c));
    list = presets;
    if cases(c) == "larger"
        list = "Defaults";
    end
    for k = 1:numel(list)
        view = app.View;
        view.applySetup(struct("preset", list(k)));
        view.run();
        if ~isempty(view.Playback)
            view.Playback.pause();
        end
        stem = cases(c) + "-" + themes(c) + "-" + slug(list(k));
        tabs = [view.tabTitles(), "Summary"];
        tabs = unique(tabs(tabs ~= "Analyze" & tabs ~= "Runs"), "stable");
        for tab = tabs
            if tab == "Animation"
                for f = options.Frames
                    t = view.Playback.StartTime + f * (view.Playback.EndTime - view.Playback.StartTime);
                    view.Playback.seek(t);
                    shots(end+1, :) = capture(app, view, tab, folder, stem + "-animation-" + round(100 * f), ...
                        sprintf("%s · %s · %s · Animation at %.3g s", list(k), themes(c), cases(c), t)); %#ok<AGROW>
                end
            else
                shots(end+1, :) = capture(app, view, tab, folder, stem + "-" + slug(tab), ...
                    list(k) + " · " + themes(c) + " · " + cases(c) + " · " + tab); %#ok<AGROW>
            end
        end
        if list(k) == "Defaults"
            for tab = intersect(["Custom plot" "Modes" "Bode"], view.analysisTitles(), "stable")
                shots(end+1, :) = capture(app, view, tab, folder, stem + "-" + slug(tab), ...
                    list(k) + " · " + themes(c) + " · " + cases(c) + " · Analyze ▸ " + tab); %#ok<AGROW>
            end
        end
    end
    clear closer
end
writeIndex(folder, id, shots, report, behaviour);
fprintf("%d screenshots in %s\n", size(shots, 1), folder);
end

function params = presetParams(plugin, name)
if name == "Defaults"
    params = plugin.defaultParams();
else
    params = plugin.presetParams(name);
end
end

function values = numericValues(v)
% Summary Values as numbers (NaN for text rows, old string values parsed).
if iscell(v)
    values = cellfun(@(x) toNumber(x), v);
elseif isnumeric(v)
    values = v;
else
    values = str2double(string(v));
end
end

function x = toNumber(v)
if isnumeric(v) && isscalar(v)
    x = double(v);
else
    x = str2double(string(v));
end
end

function shot = capture(app, view, tab, folder, name, caption)
view.selectTab(tab);
drawnow;
pause(0.4);                                % let uifigure finish rendering
file = fullfile(folder, name + ".png");
exportapp(app.Figure, file);
shot = [name + ".png", caption];
end

function s = slug(text)
s = lower(regexprep(string(text), "[^A-Za-z0-9]+", "-"));
s = regexprep(s, "^-+|-+$", "");
end

function writeIndex(folder, id, shots, report, behaviour)
% A page to browse the screenshots, with the automatic checks on top.
html = ["<!doctype html><meta charset=""utf-8""><title>Verification: " + id + "</title>"
    "<style>body{font-family:Segoe UI,sans-serif;margin:16px;background:#f6f7f9;color:#222}" + ...
    "figure{display:inline-block;margin:8px;width:460px;vertical-align:top}" + ...
    "img{width:100%;border:1px solid #ccc}figcaption{font-size:13px}" + ...
    "table{border-collapse:collapse;font-size:13px}td,th{border:1px solid #ccc;padding:3px 6px}</style>"
    "<h1>Verification screenshots: " + id + "</h1><h2>Automatic checks</h2><table><tr>"];
names = string(report.Properties.VariableNames);
html(end+1) = "<th>" + strjoin(names, "</th><th>") + "</th></tr>";
for k = 1:height(report)
    cells = strings(1, numel(names));
    for j = 1:numel(names)
        cells(j) = string(report{k, j});
    end
    html(end+1) = "<tr><td>" + strjoin(cells, "</td><td>") + "</td></tr>"; %#ok<AGROW>
end
html(end+1) = "</table><h2>In the app</h2><table><tr><th>Check</th><th>Passed</th><th>Detail</th></tr>";
for k = 1:height(behaviour)
    html(end+1) = "<tr><td>" + behaviour.Check(k) + "</td><td>" + string(behaviour.Passed(k)) + ...
        "</td><td>" + dlab.core.RunReport.escape(behaviour.Detail(k)) + "</td></tr>"; %#ok<AGROW>
end
html(end+1) = "</table><h2>Screenshots</h2>";
for k = 1:size(shots, 1)
    html(end+1) = "<figure><a href=""" + shots(k, 1) + """><img src=""" + shots(k, 1) + """ loading=""lazy""></a>" + ...
        "<figcaption>" + shots(k, 2) + "</figcaption></figure>"; %#ok<AGROW>
end
writelines(html, fullfile(folder, "index.html"));
end
