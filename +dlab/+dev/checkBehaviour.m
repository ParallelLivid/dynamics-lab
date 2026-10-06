function report = checkBehaviour(id)
%CHECKBEHAVIOUR Exercise one simulator in the app the way a user would, for
%   verification (docs/verification/README.md): every preset run, undo and
%   redo, a scenario round trip, every export, the Analyze tools, and
%   theme and text-size switches. Returns a table (Check, Passed, Detail);
%   a check fails on an error, on an error reported in the app, or when its
%   result is wrong.
%
%       T = dlab.dev.checkBehaviour("pendulum")
arguments
    id (1,1) string
end
userData = string(tempname);
previous = getenv(dlab.core.Paths.EnvironmentVariable);
setenv(dlab.core.Paths.EnvironmentVariable, userData);
restoreEnv = onCleanup(@() setenv(dlab.core.Paths.EnvironmentVariable, previous));
files = string(tempname);
mkdir(files);
app = DynamicsLab(id, Visible=false);
closer = onCleanup(@() closeApp(app));
plugin = app.View.Plugin;
specs = plugin.parameters();
numeric = dlab.core.SweepPanel.sweepable(specs);
numeric = numeric(isfinite([numeric.Default]) & [numeric.Default] ~= 0);
used = dlab.core.SweepPanel.usedNames(numeric, dlab.core.ParamSpec.defaults(specs));
numeric = numeric(ismember([numeric.Name], used));     % hidden inputs change nothing
rows = cell(0, 3);

    function step(name, work)
        % Run WORK(view); it returns a detail string, or errors.
        before = app.LastError;
        try
            detail = string(work(app.View));
            if ~isempty(app.LastError) && ~isequal(app.LastError, before)
                error("reported in the app: %s", app.LastError.message);
            end
            rows(end+1, :) = {name, true, detail};
        catch failure
            rows(end+1, :) = {name, false, string(failure.message)};
        end
    end

step("Every preset loads and runs in the app", @everyPreset);
step("Undo and redo an input", @undoRedo);
step("Scenario saved and loaded again", @scenario);
step("Data (CSV and MAT), plot, and report exports", @exports);
step("Animation export (GIF)", @animation);
step("Sweep", @sweep);
step("Map", @map);
step("Uncertainty", @uncertainty);
step("Optimize (a short search)", @optimize);
step("Modes and Bode", @modesAndBode);
step("Theme and text size switches keep the result", @switches);
report = cell2table(rows, VariableNames=["Check" "Passed" "Detail"]);

    function detail = everyPreset(view)
        names = ["Defaults", string({plugin.presets().Name})];
        times = zeros(size(names));
        lastError = app.LastError;
        for k = 1:numel(names)
            view.applySetup(struct("preset", names(k)));
            started = tic;
            view.run();
            times(k) = toc(started);
            if isempty(view.Result)
                error("%s: no result", names(k));
            end
            if ~isempty(app.LastError) && ~isequal(app.LastError, lastError)
                error("%s: %s", names(k), app.LastError.message);
            end
        end
        [slowest, k] = max(times);
        detail = sprintf("%d presets; slowest %.2f s in the app (%s), median %.2f s", numel(names), ...
            slowest, names(k), median(times));
        view.applySetup(struct("preset", "Defaults"));
        view.run();
    end

    function detail = undoRedo(view)
        if isempty(numeric)
            detail = "no numeric input";
            return
        end
        name = numeric(1).Name;
        before = view.params().(name);
        changed = before * 1.1;
        if numeric(1).Type == "integer"
            changed = before + 1;
        end
        view.applySetup(struct("params", struct(name, changed)));
        assertEqual(view.params().(name), changed, "the edit");
        view.undo();
        assertEqual(view.params().(name), before, "undo");
        view.redo();
        assertEqual(view.params().(name), changed, "redo");
        view.undo();
        detail = name + " " + string(before) + " → " + string(changed) + " → back";
    end

    function detail = scenario(view)
        file = fullfile(files, "scenario.json");
        before = view.params();
        view.saveScenario(file);
        view.reset();
        view.loadScenario(file, Confirm=false);
        after = view.params();
        for name = string(fieldnames(before))'
            if ~isequaln(before.(name), after.(name))
                error("%s changed after the round trip", name);
            end
        end
        detail = "every input the same";
    end

    function detail = exports(view)
        view.run();
        csv = fullfile(files, "data.csv");
        view.exportData("csv", csv);
        header = readlines(csv);
        header = header(1);
        T = plugin.exportTable(view.Result);
        units = string(T.Properties.VariableUnits);
        missing = units == "" & ~ismember(string(T.Properties.VariableNames), ["error" "event" "phase"]);
        view.exportData("mat", fullfile(files, "data.mat"));
        mat = load(fullfile(files, "data.mat"));
        titles = setdiff(view.tabTitles(), ["Summary" "Runs" "Analyze"], "stable");
        view.selectTab(titles(1));
        view.exportPlot(fullfile(files, "plot.png"));
        report = fullfile(files, "report.html");
        view.exportReport(report);
        html = string(fileread(report));
        S = plugin.summaryTable(view.Result);
        absent = S.Quantity(~arrayfun(@(q) contains(html, dlab.core.RunReport.escape(q)), string(S.Quantity)));
        if ~isempty(absent)
            error("the report is missing Summary rows: %s", strjoin(string(absent), ", "));
        end
        images = numel(strfind(html, "data:image/png;base64"));
        detail = sprintf("CSV %d columns (%d without units: %s); MAT fields %s; report %d images", ...
            width(T), nnz(missing), strjoin(string(T.Properties.VariableNames(missing)), " "), ...
            strjoin(string(fieldnames(mat)), " "), images);
        if ~contains(header, "[")
            detail = detail + "; NO units in the CSV header";
        end
    end

    function detail = animation(view)
        if isempty(view.Playback)
            detail = "static simulator: no animation";
            return
        end
        file = fullfile(files, "animation.gif");
        view.exportAnimation("gif", file, MaxFrames=10);
        info = imfinfo(file);
        detail = sprintf("%d frames, %d×%d", numel(info), info(1).Width, info(1).Height);
    end

    function detail = sweep(view)
        if isempty(numeric)
            detail = "no numeric input";
            return
        end
        s = numeric(1);
        [lo, hi] = around(s);
        view.applySetup(struct("sweep", struct("parameter", s.Name, "from", lo, "to", hi, "steps", 3)));
        view.runSweep();
        S = view.lessonContext().Sweep;
        failed = S.Errors(S.Errors ~= "");
        if ~isempty(failed)
            error("%d of 3 runs failed: %s", numel(failed), failed(1));
        end
        detail = sprintf("%s from %.4g to %.4g: %d results", s.Name, lo, hi, numel(S.Quantities));
    end

    function detail = map(view)
        if numel(numeric) < 2
            detail = "fewer than two numeric inputs";
            return
        end
        [x0, x1] = around(numeric(1));
        [y0, y1] = around(numeric(2));
        view.applySetup(struct("map", struct("x", struct("name", numeric(1).Name, "from", x0, "to", x1, "steps", 2), ...
            "y", struct("name", numeric(2).Name, "from", y0, "to", y1, "steps", 2))));
        view.runMap();
        M = view.lessonContext().Map;
        failed = M.Errors(M.Errors ~= "");
        if ~isempty(failed)
            error("%d of 4 runs failed: %s", numel(failed), failed(1));
        end
        detail = numeric(1).Name + " × " + numeric(2).Name + ": 4 runs";
    end

    function detail = uncertainty(view)
        if isempty(numeric)
            detail = "no numeric input";
            return
        end
        view.applySetup(struct("uncertainty", struct("inputs", struct("name", numeric(1).Name, ...
            "kind", "uniform", "spread", 2, "relative", true), "samples", 6, "seed", 1)));
        view.runUncertainty();
        R = view.lessonContext().Uncertainty;
        if isempty(R) || any(R.Errors ~= "")
            error("the study failed");
        end
        detail = sprintf("%s ±2 %%: %d samples", numeric(1).Name, size(R.Samples, 1));
    end

    function detail = optimize(~)
        if isempty(numeric)
            detail = "no numeric input";
            return
        end
        params = dlab.core.ParamSpec.validateAll(specs, app.View.params());
        M = plugin.metrics(plugin.solve(params));
        [lo, hi] = around(numeric(1));
        R = dlab.core.Optimizer.run(plugin, params, numeric(1).Name, string(M.Quantity(1)), ...
            Bounds=[lo hi], MaxEvaluations=8, StartGrid=false);
        detail = sprintf("%s over %s: best %.4g at %.4g (%d runs)", M.Quantity(1), numeric(1).Name, ...
            R.BestMetric, R.Best, height(R.Evaluations));
    end

    function detail = modesAndBode(view)
        view.run();
        context = view.lessonContext();
        tools = view.analysisTitles();
        parts = strings(0);
        if ismember("Modes", tools)
            if isempty(context.Modes)
                parts(end+1) = "Modes: none for these inputs";
            else
                parts(end+1) = sprintf("Modes: %d modes (%s)", height(context.Modes), strjoin(context.Modes.Mode, ", "));
            end
        else
            parts(end+1) = "no Modes tab";
        end
        if ismember("Bode", tools)
            R = context.Frequency;
            if isempty(R)
                parts(end+1) = "Bode: no response for these inputs";
            else
                parts(end+1) = "Bode: " + R.Input + " → " + R.Output;
            end
        end
        detail = strjoin(parts, "; ");
    end

    function detail = switches(view)
        view.run();
        result = view.Result;
        app.toggleTheme();
        assertTrue(isequaln(app.View.Result, result), "the result after a theme switch");
        app.setTextSize("larger");
        assertTrue(isequaln(app.View.Result, result), "the result after a text-size switch");
        app.setTextSize("normal");
        app.toggleTheme();
        detail = "result kept";
    end
end

function [lo, hi] = around(spec)
% A small range about the default, inside the input's limits.
value = spec.Default;
lo = max(value * 0.9, spec.Min + 1e-6 * abs(value));
hi = min(value * 1.1, spec.Max - 1e-6 * abs(value));
if value < 0
    [lo, hi] = deal(max(value * 1.1, spec.Min), min(value * 0.9, spec.Max));
end
if spec.Type == "integer"
    lo = max(round(value) - 1, ceil(spec.Min));
    hi = min(round(value) + 1, floor(spec.Max));
end
end

function assertEqual(actual, expected, what)
if ~isequaln(actual, expected)
    error("%s: expected %s, got %s", what, mat2str(expected), mat2str(actual));
end
end

function assertTrue(condition, what)
if ~condition
    error("lost %s", what);
end
end

function closeApp(app)
if isvalid(app)
    app.close();
end
end
