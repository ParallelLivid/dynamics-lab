classdef Lesson
    %LESSON Guided lessons: JSON files that walk through a simulator one
    %   step at a time. Shipped lessons live in resources/lessons; lessons
    %   in <user data>/lessons appear too. See docs/lessons.md.
    %
    %   {
    %     "format": "dynamicslab-lesson", "formatVersion": 1,
    %     "id": "projectile-best-angle", "title": "...", "simulator": "projectile",
    %     "summary": "...", "order": 3,
    %     "steps": [
    %       { "title": "...", "text": "...",
    %         "setup": { "preset": "...", "params": { "theta": 30 }, "tab": "Sweep",
    %                    "keepRuns": true, "sweep": { "parameter": "theta", "from": 5, "to": 85, "steps": 17 } },
    %         "check": { "kind": "metric", "quantity": "Range", "min": 250, "max": 260,
    %                    "hint": "...", "success": "..." },
    %         "solution": { "params": { ... }, "run": true },
    %         "claims": [ { "kind": "metric", "quantity": "Range", "value": 254.8, "tolerance": 0.005 } ] }
    %     ]
    %   }
    %
    %   Check kinds: run, metric, input, sweep, map, optimize, uncertainty,
    %   fit, modes, bode, runs, choice (a multiple-choice question), and all
    %   (every check in "checks" must pass). A step without a check is for
    %   reading. A step may name another "simulator": the lesson moves to
    %   it, so one lesson can compare models. "solution" is never shown;
    %   tests use it to prove each step can be completed.
    %
    %   "claims" are checks the learner never sees: the numbers the step's
    %   text and success message state, checked by the tests after the
    %   solution has run (so a step with claims needs a solution). A claim
    %   is written like a check, or with "value" and a relative "tolerance"
    %   (default 1 %) in place of "min" and "max".

    properties (Constant)
        Format = "dynamicslab-lesson"
        FormatVersion = 1
        CheckKinds = ["run" "metric" "input" "sweep" "map" "optimize" "uncertainty" "fit" "modes" "bode" ...
            "runs" "choice" "all"]
    end

    methods (Static)
        function list = list(knownIds)
            %LIST Every readable lesson for the simulators in KNOWNIDS
            %   (struct array: Id, Title, Simulator, Summary, Steps, File),
            %   in their "order".
            arguments
                knownIds (1,:) string = string.empty(1, 0)
            end
            list = struct("Id", {}, "Title", {}, "Simulator", {}, "Summary", {}, "Steps", {}, ...
                "File", {}, "Order", {});
            folders = [fullfile(dlab.core.Paths.resources(), "lessons"), dlab.core.Paths.lessons()];
            for folder = folders
                for f = reshape(dir(fullfile(folder, "*.json")), 1, [])
                    file = string(fullfile(f.folder, f.name));
                    try
                        L = dlab.core.Lesson.read(file);
                    catch
                        continue            % a broken lesson file is skipped, not fatal
                    end
                    if (~isempty(knownIds) && ~ismember(L.simulator, knownIds)) || ismember(L.id, string({list.Id}))
                        continue
                    end
                    list(end+1) = struct("Id", L.id, "Title", L.title, "Simulator", L.simulator, ...
                        "Summary", L.summary, "Steps", numel(L.steps), "File", file, "Order", L.order); %#ok<AGROW>
                end
            end
            [~, order] = sortrows([[list.Order]' (1:numel(list))']);
            list = list(order);
        end

        function L = load(id)
            %LOAD The lesson with this id.
            arguments
                id (1,1) string
            end
            match = dlab.core.Lesson.list();
            match = match([match.Id] == id);
            if isempty(match)
                error("dlab:lesson:unknown", "There is no lesson called ""%s"".", id);
            end
            L = dlab.core.Lesson.read(match(1).File);
        end

        function L = read(file)
            %READ Decode and check a lesson file.
            arguments
                file (1,1) string
            end
            try
                raw = jsondecode(fileread(file, Encoding="UTF-8"));
            catch
                error("dlab:lesson:notJson", """%s"" is not a valid JSON file.", file);
            end
            required = ["format" "formatVersion" "id" "title" "simulator" "steps"];
            if ~isstruct(raw) || ~all(isfield(raw, required)) || string(raw.format) ~= dlab.core.Lesson.Format
                error("dlab:lesson:format", """%s"" is not a Dynamics Lab lesson.", file);
            end
            if raw.formatVersion > dlab.core.Lesson.FormatVersion
                error("dlab:lesson:newerFormat", "This lesson needs a newer version of Dynamics Lab.");
            end
            L = struct("id", string(raw.id), "title", string(raw.title), "simulator", string(raw.simulator), ...
                "summary", "", "order", 100, "steps", {cell(1, 0)}, "file", file);
            if isfield(raw, "summary")
                L.summary = string(raw.summary);
            end
            if isfield(raw, "order")
                L.order = double(raw.order);
            end
            steps = raw.steps;
            if isstruct(steps)
                steps = num2cell(steps);
            end
            for k = 1:numel(steps)
                step = steps{k};
                if ~isstruct(step) || ~all(isfield(step, ["title" "text"]))
                    error("dlab:lesson:format", "Step %d of ""%s"" needs a title and text.", k, L.title);
                end
                step.title = string(step.title);
                step.text = string(step.text);
                if isfield(step, "simulator")
                    step.simulator = string(step.simulator);
                end
                if isfield(step, "check")
                    dlab.core.Lesson.validateCheck(step.check, k);
                end
                if isfield(step, "claims")
                    step.claims = dlab.core.Lesson.readClaims(step, k);
                end
                L.steps{end+1} = step;
            end
            if isempty(L.steps)
                error("dlab:lesson:format", """%s"" has no steps.", L.title);
            end
        end

        function ids = simulators(L)
            %SIMULATORS Every simulator lesson L uses, its own first.
            ids = L.simulator;
            for k = 1:numel(L.steps)
                ids(end+1) = dlab.core.Lesson.stepSimulator(L, k); %#ok<AGROW>
            end
            ids = unique(ids, "stable");
        end

        function id = stepSimulator(L, k)
            %STEPSIMULATOR The simulator step K runs in (the lesson's own
            %   unless the step names another).
            id = L.simulator;
            if isfield(L.steps{k}, "simulator")
                id = L.steps{k}.simulator;
            end
        end

        function [passed, message] = evaluate(check, context)
            %EVALUATE Whether the learner has done what CHECK asks.
            %   CONTEXT (from the simulator view): Params, Specs, Fresh,
            %   RunParams, Metrics, Sweep, Map, Optimize, Uncertainty, Fit,
            %   Modes, Frequency, KeptRuns, and Answer (the option chosen
            %   for a multiple-choice step, NaN if none).
            kind = string(check.kind);
            switch kind
                case "all"
                    checks = check.checks;
                    if isstruct(checks)
                        checks = num2cell(checks);
                    end
                    passed = true;
                    message = "";
                    for k = 1:numel(checks)
                        [passed, message] = dlab.core.Lesson.evaluate(checks{k}, context);
                        if ~passed
                            break
                        end
                    end
                case "run"
                    [passed, message] = needFresh(context);
                case "metric"
                    [passed, message] = needFresh(context);
                    if passed
                        quantity = string(check.quantity);
                        M = context.Metrics;
                        row = M(M.Quantity == quantity, :);
                        if isempty(row)
                            [passed, message] = deal(false, "This run has no """ + quantity + """ result.");
                        else
                            [passed, message] = inRange(quantity, row.Value(1), row.Units(1), check);
                        end
                    end
                case "input"
                    [passed, message] = checkInput(check, context);
                case "sweep"
                    S = context.Sweep;
                    name = string(check.parameter);
                    needed = field(check, "minRuns", 2);
                    passed = ~isempty(S) && S.Parameter == name && nnz(S.Errors == "" & ...
                        any(isfinite(S.Data), 2)) >= needed;
                    message = sprintf("Run a sweep of %s with at least %d values (Analyze ▸ Sweep).", ...
                        labelOf(context, name), needed);
                case "map"
                    [passed, message] = checkMap(check, context);
                case "optimize"
                    [passed, message] = checkOptimize(check, context);
                case "uncertainty"
                    [passed, message] = checkUncertainty(check, context);
                case "fit"
                    [passed, message] = checkFit(check, context);
                case "modes"
                    [passed, message] = needFresh(context);
                    if passed
                        [passed, message] = checkModes(check, context);
                    end
                case "bode"
                    [passed, message] = needFresh(context);
                    if passed
                        [passed, message] = checkBode(check, context);
                    end
                case "choice"
                    answer = field(context, "Answer", NaN);
                    passed = isequal(answer, double(check.answer));
                    if isnan(answer)
                        message = "Choose an answer, then press Check.";
                    else
                        message = "Not quite.";
                    end
                case "runs"
                    needed = field(check, "min", 1);
                    passed = context.KeptRuns >= needed;
                    message = sprintf("Tick ""Keep previous runs"" and run until %d earlier run(s) are kept.", needed);
                otherwise
                    error("dlab:lesson:check", "Unknown check kind ""%s"".", kind);
            end
            if passed
                message = "✓ " + string(field(check, "success", "Well done."));
            elseif isfield(check, "hint")
                message = "✗ " + message + " " + string(check.hint);
            else
                message = "✗ " + message;
            end
        end

        function progress = progress(id)
            %PROGRESS How far the learner got: struct(Step, Done).
            progress = struct("Step", 1, "Done", false);
            saved = dlab.core.Settings.get("lessonProgress", struct());
            key = matlab.lang.makeValidName(id);
            if isstruct(saved) && isfield(saved, key) && isstruct(saved.(key))
                entry = saved.(key);
                if isfield(entry, "Step") && isnumeric(entry.Step) && isscalar(entry.Step)
                    progress.Step = max(1, round(entry.Step));
                end
                if isfield(entry, "Done") && isscalar(entry.Done)
                    progress.Done = logical(entry.Done);
                end
            end
        end

        function saveProgress(id, step, done)
            %SAVEPROGRESS Remember the step reached (and whether finished).
            saved = dlab.core.Settings.get("lessonProgress", struct());
            if ~isstruct(saved)
                saved = struct();
            end
            key = matlab.lang.makeValidName(id);
            saved.(key) = struct("Step", step, "Done", done);
            dlab.core.Settings.set("lessonProgress", saved);
        end

        function claims = readClaims(step, k)
            %READCLAIMS A step's claims as a cell of checks, "value" and
            %   "tolerance" turned into "min" and "max".
            claims = step.claims;
            if isstruct(claims)
                claims = num2cell(claims);
            end
            if ~isfield(step, "solution")
                error("dlab:lesson:format", "Step %d has claims but no solution to check them with.", k);
            end
            for j = 1:numel(claims)
                claim = claims{j};
                if isstruct(claim) && isfield(claim, "value")
                    tolerance = field(claim, "tolerance", 0.01);
                    margin = tolerance * max(abs(claim.value), eps);
                    claim.min = claim.value - margin;
                    claim.max = claim.value + margin;
                end
                dlab.core.Lesson.validateCheck(claim, k);
                claims{j} = claim;
            end
        end

        function validateCheck(check, step)
            if ~isstruct(check) || ~isfield(check, "kind") || ~ismember(string(check.kind), dlab.core.Lesson.CheckKinds)
                error("dlab:lesson:format", "Step %d has a check without a known kind (%s).", step, ...
                    strjoin(dlab.core.Lesson.CheckKinds, ", "));
            end
            if string(check.kind) == "choice" && (~all(isfield(check, ["options" "answer"])) || ...
                    ~ismember(check.answer, 1:numel(string(check.options))))
                error("dlab:lesson:format", "Step %d: a choice needs ""options"" and the number of " + ...
                    "the right one as ""answer"".", step);
            end
        end
    end
end

% ------------------------------------------------------------------ checks
function [passed, message] = needFresh(context)
passed = context.Fresh;
message = "Press Run first; results must be up to date with the inputs.";
end

function [passed, message] = inRange(name, value, units, check)
low = field(check, "min", -Inf);
high = field(check, "max", Inf);
passed = value >= low && value <= high;
unitText = "";
if string(units) ~= ""
    unitText = " " + string(units);
end
if isinf(low)
    target = sprintf("at most %.4g", high);
elseif isinf(high)
    target = sprintf("at least %.4g", low);
else
    target = sprintf("between %.4g and %.4g", low, high);
end
message = sprintf("%s is %.4g%s; aim for %s%s.", name, value, unitText, target, unitText);
end

function [passed, message] = checkInput(check, context)
name = string(check.name);
label = labelOf(context, name);
if ~isfield(context.Params, name)
    error("dlab:lesson:check", "This simulator has no input ""%s"".", name);
end
value = context.Params.(name);
if isfield(check, "value")
    wanted = check.value;
    if ischar(wanted)
        wanted = string(wanted);
    end
    passed = isequal(value, wanted);
    message = sprintf("Set %s to %s.", label, string(wanted));
elseif isfield(check, "shape")
    passed = isstruct(value) && string(value.shape) == string(check.shape);
    message = sprintf("Make %s a %s.", label, string(check.shape));
elseif istable(value)
    [passed, message] = inRange(label + " rows", height(value), "", check);
else
    [passed, message] = inRange(label, value, unitsOf(context, name), check);
end
end

function [passed, message] = checkModes(check, context)
M = context.Modes;
mode = string(check.mode);
if isempty(M) || ~any(M.Mode == mode)
    [passed, message] = deal(false, "There is no " + mode + " mode on Analyze ▸ Modes for this run.");
    return
end
passed = true;
message = "";
if isfield(check, "quantity")
    quantity = string(check.quantity);
    names = struct("Period", "Period", "NaturalFrequency", "Natural frequency", ...
        "DampingRatio", "Damping ratio", "TimeConstant", "Time constant");
    value = M.(quantity)(find(M.Mode == mode, 1));
    units = M.Properties.VariableUnits(string(M.Properties.VariableNames) == quantity);
    [passed, message] = inRange(mode + " " + lower(names.(quantity)), value, units{1}, check);
end
end

function [passed, message] = checkMap(check, context)
% A map of these two inputs with enough runs, and optionally a result whose
% largest value on the map is in range.
M = context.Map;
x = string(check.x);
y = string(check.y);
needed = field(check, "minRuns", 4);
message = sprintf("Run a map of %s and %s with at least %d points (Analyze ▸ Map).", labelOf(context, x), ...
    labelOf(context, y), needed);
passed = ~isempty(M) && isequal(sort(M.Parameters), sort([x y])) && ...
    nnz(M.Errors == "" & any(isfinite(M.Data), 3)) >= needed;
if passed && isfield(check, "quantity")
    quantity = string(check.quantity);
    if ~any(M.Quantities == quantity)
        [passed, message] = deal(false, "The map has no """ + quantity + """ result.");
        return
    end
    z = dlab.core.Map.layer(M, quantity);
    [passed, message] = inRange("The largest " + quantity, max(z(:)), ...
        M.QuantityUnits(M.Quantities == quantity), check);
end
end

function [passed, message] = checkOptimize(check, context)
% A finished search over these inputs (for this result), with the best
% input or the best result in range.
R = context.Optimize;
inputs = reshape(string(check.inputs), 1, []);      % a JSON list decodes as a column
labels = arrayfun(@(n) labelOf(context, n), inputs);
message = "Optimize " + strjoin(labels, " and ");
if isfield(check, "metric")
    message = message + " for " + string(check.metric);
end
message = message + " (Analyze ▸ Optimize), and let it finish.";
passed = ~isempty(R) && isequal(sort(R.Inputs), sort(inputs)) && ~R.Cancelled && all(isfinite(R.Best)) && ...
    (~isfield(check, "metric") || R.Metric == string(check.metric));
if ~passed
    return
end
if ~R.Satisfied
    [passed, message] = deal(false, "The best inputs found don't meet the limit.");
elseif isfield(check, "input")
    name = string(check.input);
    [passed, message] = inRange("The best " + labelOf(context, name), R.Best(R.Inputs == name), ...
        unitsOf(context, name), check);
elseif isfield(check, "min") || isfield(check, "max")
    [passed, message] = inRange("The best " + R.Metric, R.BestMetric, R.MetricUnits, check);
end
end

function [passed, message] = checkUncertainty(check, context)
% A Monte Carlo study (varying these inputs) with enough runs, and
% optionally a statistic of one result in range.
R = context.Uncertainty;
needed = field(check, "minRuns", 20);
message = sprintf("Run a Monte Carlo study with at least %d samples (Analyze ▸ Uncertainty).", needed);
passed = ~isempty(R) && ~R.Cancelled && nnz(R.Errors == "") >= needed;
if passed && isfield(check, "inputs")
    inputs = reshape(string(check.inputs), 1, []);
    passed = all(ismember(inputs, R.Inputs));
    message = "Give " + strjoin(arrayfun(@(n) labelOf(context, n), inputs), " and ") + ...
        " a tolerance and run the study (Analyze ▸ Uncertainty).";
end
if passed && isfield(check, "quantity")
    quantity = string(check.quantity);
    statistic = string(field(check, "statistic", "Std"));
    column = find(R.Quantities == quantity, 1);
    if isempty(column)
        [passed, message] = deal(false, "The study has no """ + quantity + """ result.");
        return
    end
    names = struct("Mean", "mean", "Std", "spread (σ)", "P05", "5th percentile", "P95", "95th percentile", ...
        "Min", "smallest", "Max", "largest");
    [passed, message] = inRange(quantity + " " + names.(statistic), R.(statistic)(column), ...
        R.QuantityUnits(column), check);
end
end

function [passed, message] = checkFit(check, context)
% A finished fit of these inputs, with a fitted input or the residual in range.
R = context.Fit;
inputs = reshape(string(check.inputs), 1, []);
message = "Fit " + strjoin(arrayfun(@(n) labelOf(context, n), inputs), " and ") + ...
    " to the measured data (Analyze ▸ Fit), and let it finish.";
passed = ~isempty(R) && isequal(sort(R.Inputs(:)).', sort(inputs)) && ~R.Cancelled && isfinite(R.BestRMS);
if ~passed
    return
end
if isfield(check, "input")
    name = string(check.input);
    [passed, message] = inRange("The fitted " + labelOf(context, name), R.Best(R.Inputs == name), ...
        unitsOf(context, name), check);
elseif isfield(check, "min") || isfield(check, "max")
    [passed, message] = inRange("The RMS misfit", R.BestRMS, R.ValueUnits, check);
end
end

function [passed, message] = checkBode(check, context)
% The Bode tab shows this input to this output, with a quantity in range.
R = context.Frequency;
if isempty(R)
    [passed, message] = deal(false, "The Bode tab has no response for this run.");
    return
end
if isfield(check, "input") && R.Input ~= string(check.input) || ...
        isfield(check, "output") && R.Output ~= string(check.output)
    [passed, message] = deal(false, sprintf("Choose %s → %s on Analyze ▸ Bode.", ...
        string(field(check, "input", R.Input)), string(field(check, "output", R.Output))));
    return
end
passed = true;
message = "";
if isfield(check, "quantity")
    quantity = string(check.quantity);
    names = struct("DCGain", "DC gain", "PeakGain", "Peak gain", "PeakFrequency", "Resonant frequency", ...
        "Bandwidth", "Bandwidth", "PhaseMargin", "Phase margin", "GainMargin", "Gain margin");
    units = struct("DCGain", "", "PeakGain", "", "PeakFrequency", "rad/s", "Bandwidth", "rad/s", ...
        "PhaseMargin", "deg", "GainMargin", "dB");
    [passed, message] = inRange(names.(quantity), R.(quantity), units.(quantity), check);
end
end

function value = field(s, name, default)
if isfield(s, name)
    value = s.(name);
else
    value = default;
end
end

function label = labelOf(context, name)
label = name;
if isempty(context.Specs)
    return
end
match = context.Specs([context.Specs.Name] == name);
if ~isempty(match)
    label = match(1).Label;
end
end

function units = unitsOf(context, name)
units = "";
if isempty(context.Specs)
    return
end
match = context.Specs([context.Specs.Name] == name);
if ~isempty(match)
    units = match(1).Units;
end
end
