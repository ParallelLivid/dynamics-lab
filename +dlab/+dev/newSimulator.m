function files = newSimulator(id, title, options)
%NEWSIMULATOR Scaffold a new Dynamics Lab simulator that passes the build at once.
%   dlab.dev.newSimulator("doublependulum", "Double Pendulum")
%   dlab.dev.newSimulator("beam", "Beam Deflection", Kind="static", Category="Structural")
%
%   Creates, from templates (FILES lists them in this order):
%     +dlab/+sims/+<id>/<Name>Plugin.m          plugin with every required method and the usual hooks
%     +dlab/+sims/+<id>/simulate<Name>.m        placeholder engine (replace with your physics)
%     tests/sims/<id>/Test<Name>Plugin.m        app test (tagged "ui")
%     tests/sims/<id>/test_simulate<Name>.m     engine test with golden values
%     docs/sims/<id>.md                         docs page
%     resources/lessons/<id>-intro.json         a one-step lesson
%     resources/thumbnails/<id>-dark.png, -light.png   placeholder Home thumbnails
%     docs/verification/<id>.md                 verification sheet, in review
%   and adds the plugin to +dlab/+sims/registry.m and a row to the README's
%   simulator table, under its category (Register=false prints both instead).
%   The placeholder model (exponential decay, or a parabola for static
%   plugins) passes the whole suite as generated. Replace the thumbnails
%   with "buildtool images" once the model draws something.
%   See docs/adding-a-simulator.md.
arguments
    id (1,1) string {mustBeValidId}
    title (1,1) string {mustBeNonzeroLengthText, mustBePlainText}
    options.Kind (1,1) string {mustBeMember(options.Kind, ["time" "static"])} = "time"
    options.Category (1,1) string {mustBePlainText} = "Mechanics"
    options.Summary (1,1) string {mustBeNonzeroLengthText, mustBePlainText} = ...
        "TODO: one line on what it covers, for the Home card."
    options.Register (1,1) logical = true
    options.Root (1,1) string = string(fileparts(fileparts(fileparts(mfilename("fullpath")))))
end
root = options.Root;
name = className(title);
package = fullfile(root, "+dlab", "+sims", "+" + id);
testFolder = fullfile(root, "tests", "sims", id);
if isfolder(package)
    error("dlab:dev:exists", "A simulator package already exists: %s", package);
end
files = [fullfile(package, name + "Plugin.m")
         fullfile(package, "simulate" + name + ".m")
         fullfile(testFolder, "Test" + name + "Plugin.m")
         fullfile(testFolder, "test_simulate" + name + ".m")
         fullfile(root, "docs", "sims", id + ".md")
         fullfile(root, "resources", "lessons", id + "-intro.json")
         fullfile(root, "resources", "thumbnails", id + "-dark.png")
         fullfile(root, "resources", "thumbnails", id + "-light.png")
         fullfile(root, "docs", "verification", id + ".md")];
existing = files(isfile(files));
if ~isempty(existing)
    error("dlab:dev:exists", "These files already exist: %s", strjoin(existing, ", "));
end
for folder = unique(string(cellfun(@fileparts, cellstr(files), UniformOutput=false)))'
    if ~isfolder(folder)
        mkdir(folder);
    end
end

fields = struct("Id", id, "Name", name, "Title", title, "Category", options.Category, ...
    "Summary", options.Summary, "Date", string(datetime("today", Format="yyyy-MM-dd")));
if options.Kind == "time"
    templates = {timeTemplate(), decayEngine(), appTest(), decayEngineTest(), decayDocs()};
    [fields.FirstTab, fields.Quantity, fields.Exact] = deal("Response", "Final value", "Exact final value");
    fields.ExactValue = exp(-5);              % x0 e^(−t/τ) at the defaults
else
    templates = {staticTemplate(), parabolaEngine(), appTest(), parabolaEngineTest(), parabolaDocs()};
    [fields.FirstTab, fields.Quantity, fields.Exact] = deal("Result", "Area under the curve", "Exact area");
    fields.ExactValue = 8 / 3;                % a span³ / 3 at the defaults
end
for k = 1:numel(templates)
    writeFile(files(k), render(templates{k}, fields));
end
writeFile(files(6), lessonStub(fields, fullfile(root, "resources", "lessons")));
writeThumbnail(files(7), "dark", options.Kind);
writeThumbnail(files(8), "light", options.Kind);
writeFile(files(9), verificationSheet(fields, options.Kind));

entry = "    @dlab.sims." + id + "." + name + "Plugin";
row = "| [" + escapeCell(title) + "](docs/sims/" + id + ".md) | " + escapeCell(options.Summary) + " |";
readme = fullfile(root, "README.md");
if options.Register
    registry = fullfile(root, "+dlab", "+sims", "registry.m");
    text = fileread(registry);
    closing = regexp(text, "\n\};", "once");
    assert(~isempty(closing), "dlab:dev:registry", "Could not find the end of the plugin list in %s.", registry);
    writeFile(registry, string(text(1:closing)) + entry + string(text(closing:end)));
    fprintf("Registered %s in %s\n", entry, registry);
    if isfile(readme)
        addReadmeRow(readme, options.Category, row);
        fprintf("Added a row to the simulator table in %s\n", readme);
    else
        fprintf("Add this row to the README's simulator table, under %s:\n%s\n", options.Category, row);
    end
else
    fprintf("Add this line to +dlab/+sims/registry.m:\n%s\n", entry);
    fprintf("and this row to the README's simulator table, under %s:\n%s\n", options.Category, row);
end
fprintf("Created:\n%s\n", strjoin("  " + files, newline));
fprintf("Next: replace simulate%s.m with your model, update its tests, docs page, and lesson,\n" + ...
    "then run ""buildtool images"" for real thumbnails and ""buildtool"" for the suite.\n" + ...
    "Before calling it done, work through docs/verification/README.md (""Adding a simulator"").\n", name);
end

% ------------------------------------------------------------- templates
function text = timeTemplate()
text = [
"classdef {{Name}}Plugin < dlab.core.TimeDomainPlugin"
"    %{{UPPER}}PLUGIN {{Title}} (scaffolded {{Date}} by dlab.dev.newSimulator)."
"    %   Replace the placeholder model in simulate{{Name}}.m and adapt each"
"    %   method. See docs/adding-a-simulator.md, and DcMotorPlugin for a full"
"    %   example."
""
"    properties (Constant)"
"        Id = ""{{Id}}"""
"        Title = ""{{Title}}"""
"        Category = ""{{Category}}"""
"        Summary = ""{{Summary}}"""
"        SchemaVersion = 1"
"    end"
""
"    properties (Access = private)"
"        Axes"
"        Line"
"        Marker"
"        Result"
"    end"
""
"    methods"
"        function specs = parameters(~)"
"            P = @dlab.core.ParamSpec;"
"            specs = ["
"                P(""x0"", Label=""Initial value"", Default=1, Min=-1e6, Max=1e6, Group=""Model"", ..."
"                    Description=""The value at the start."")"
"                P(""tau"", Label=""Time constant τ"", Units=""s"", Default=2, Min=0, MinInclusive=false, ..."
"                    Max=1e6, Group=""Model"", Description=""The value falls to 1/e of the start in τ."")"
"                P(""duration"", Label=""Duration"", Units=""s"", Default=10, Min=0, MinInclusive=false, ..."
"                    Max=1e6, Group=""Simulation"", MarksCustom=false, Description=""How long to simulate."")"
"                P(""dt"", Label=""Output step"", Units=""s"", Default=0.01, Min=0, MinInclusive=false, ..."
"                    Max=100, Group=""Simulation"", Description=""Spacing of the saved samples."")"
"            ];"
"        end"
""
"        function list = presets(~)"
"            list = struct(""Name"", {}, ""Values"", {});"
"            list(end+1) = struct(""Name"", ""Slow decay"", ""Values"", struct(""tau"", 5));"
"        end"
""
"        function result = solve(obj, params)"
"            q = params;"
"            q.progressFcn = obj.progressMonitor();       % progress bar and Cancel"
"            result = dlab.sims.{{Id}}.simulate{{Name}}(q);"
"            result.params = params;"
"        end"
""
"        function titles = outputTabs(~, ~)"
"            titles = ""Response"";"
"        end"
""
"        function buildOutputs(obj, containers, theme)"
"            obj.Theme = theme;"
"            obj.Axes = dlab.ui.axesIn(containers{""Response""}, theme, Title=""Response"", ..."
"                XLabel=""Time (s)"", YLabel=""x"");"
"            obj.Line = line(obj.Axes, NaN, NaN, Color=theme.series(1), LineWidth=1.5);"
"        end"
""
"        function buildAnimation(obj, parent, theme)"
"            ax = dlab.ui.axesIn(parent, theme, Title=""{{Title}}"", XLabel=""x"", YLabel="""");"
"            obj.Marker = line(ax, NaN, 0, Marker=""o"", MarkerSize=14, ..."
"                MarkerFaceColor=theme.Accent, Color=theme.Accent);"
"        end"
""
"        function showResult(obj, result, ~)"
"            obj.Result = result;"
"            set(obj.Line, XData=result.t, YData=result.x);"
"            if isgraphics(obj.Marker)"
"                xlim(obj.Marker.Parent, [-1.1 1.1] * max(max(abs(result.x)), eps));"
"            end"
"            obj.drawFrame(result.t(1));"
"        end"
""
"        function overlayRuns(obj, runs)"
"            % Keep previous runs: earlier results drawn faintly."
"            for run = runs(:)'"
"                dlab.ui.overlayLine(obj.Axes, run.Result.t, run.Result.x, run);"
"            end"
"        end"
""
"        function clearResult(obj)"
"            obj.Result = [];"
"            set(obj.Line, XData=NaN, YData=NaN);"
"            if isgraphics(obj.Marker)"
"                obj.Marker.XData = NaN;"
"            end"
"        end"
""
"        function t = timeVector(~, result)"
"            t = result.t;"
"        end"
""
"        function drawFrame(obj, simTime)"
"            if isempty(obj.Result) || ~isgraphics(obj.Marker)"
"                return"
"            end"
"            k = dlab.core.frameAt(obj.Result.t, simTime);"
"            obj.Marker.XData = obj.Result.x(k);"
"        end"
""
"        function T = exportTable(~, result)"
"            T = table(result.t, result.x, VariableNames=[""time"" ""x""]);"
"            T.Properties.VariableUnits = [""s"" """"];"
"        end"
""
"        function T = summaryTable(~, result)"
"            % Numbers stay numbers (sweeps and lessons read them); Format says"
"            % how to show each, and a text row has Value NaN and a Display."
"            p = result.params;"
"            rows = {"
"                ""Final value"", result.x(end), """", ""%.6g"""
"                ""Exact final value"", p.x0 * exp(-result.t(end) / p.tau), """", ""%.6g"""
"                ""Half-life"", p.tau * log(2), ""s"", ""%.4g"""
"            };"
"            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ..."
"                VariableNames=[""Quantity"" ""Value"" ""Units"" ""Format""]);"
"            T.Display = strings(height(T), 1);"
"            T(end+1, :) = {""Model"", NaN, """", """", ""placeholder (exponential decay)""};"
"        end"
""
"        function scene = showcase(~)"
"            % The Home thumbnail and README screenshot (buildtool images)."
"            scene = struct(""Preset"", """", ""Tab"", ""Response"", ""Time"", NaN);"
"        end"
""
"        function description = about(~)"
"            description = join(["
"                ""Placeholder model (replace it):"""
"                ""dx/dt = −x / τ,   x(0) = x0"""
"                ""Exact solution: x = x0 e^(−t/τ); the half-life is τ ln 2."""
"            ], newline);"
"        end"
"    end"
"end"
];
end

function text = staticTemplate()
text = [
"classdef {{Name}}Plugin < dlab.core.StaticPlugin"
"    %{{UPPER}}PLUGIN {{Title}} (scaffolded {{Date}} by dlab.dev.newSimulator)."
"    %   Replace the placeholder model in simulate{{Name}}.m and adapt each"
"    %   method. See docs/adding-a-simulator.md, and FramePlugin for a full"
"    %   example."
""
"    properties (Constant)"
"        Id = ""{{Id}}"""
"        Title = ""{{Title}}"""
"        Category = ""{{Category}}"""
"        Summary = ""{{Summary}}"""
"        SchemaVersion = 1"
"    end"
""
"    properties (Access = private)"
"        Axes"
"        Line"
"    end"
""
"    methods"
"        function obj = {{Name}}Plugin()"
"            obj.RunLabel = ""Solve"";"
"        end"
""
"        function specs = parameters(~)"
"            P = @dlab.core.ParamSpec;"
"            specs = ["
"                P(""a"", Label=""Curvature"", Units=""1/m"", Default=1, Min=-1e6, Max=1e6, Group=""Model"", ..."
"                    Description=""y = a x²."")"
"                P(""span"", Label=""Span"", Units=""m"", Default=2, Min=0, MinInclusive=false, Max=1e6, ..."
"                    Group=""Model"", Description=""How far along x the curve is drawn."")"
"            ];"
"        end"
""
"        function list = presets(~)"
"            list = struct(""Name"", {}, ""Values"", {});"
"            list(end+1) = struct(""Name"", ""Steep"", ""Values"", struct(""a"", 3));"
"        end"
""
"        function result = solve(~, params)"
"            result = dlab.sims.{{Id}}.simulate{{Name}}(params);"
"            result.params = params;"
"        end"
""
"        function titles = outputTabs(~, ~)"
"            titles = ""Result"";"
"        end"
""
"        function buildOutputs(obj, containers, theme)"
"            obj.Theme = theme;"
"            obj.Axes = dlab.ui.axesIn(containers{""Result""}, theme, Title=""Result"", ..."
"                XLabel=""x (m)"", YLabel=""y (m)"");"
"            obj.Line = line(obj.Axes, NaN, NaN, Color=theme.series(1), LineWidth=1.5);"
"        end"
""
"        function previewInputs(obj, params)"
"            title(obj.Axes, sprintf(""Span %g m (press Solve)"", params.span));"
"        end"
""
"        function showResult(obj, result, ~)"
"            set(obj.Line, XData=result.x, YData=result.y);"
"            title(obj.Axes, ""Result"");"
"        end"
""
"        function overlayRuns(obj, runs)"
"            % Keep previous runs: earlier results drawn faintly."
"            for run = runs(:)'"
"                dlab.ui.overlayLine(obj.Axes, run.Result.x, run.Result.y, run);"
"            end"
"        end"
""
"        function clearResult(obj)"
"            set(obj.Line, XData=NaN, YData=NaN);"
"        end"
""
"        function T = exportTable(~, result)"
"            T = table(result.x, result.y, VariableNames=[""x"" ""y""]);"
"            T.Properties.VariableUnits = [""m"" ""m""];"
"        end"
""
"        function T = summaryTable(~, result)"
"            % Numbers stay numbers (sweeps and lessons read them); Format says"
"            % how to show each, and a text row has Value NaN and a Display."
"            p = result.params;"
"            rows = {"
"                ""End value"", result.y(end), ""m"", ""%.6g"""
"                ""Area under the curve"", trapz(result.x, result.y), ""m²"", ""%.6g"""
"                ""Exact area"", p.a * p.span^3 / 3, ""m²"", ""%.6g"""
"            };"
"            T = table(string(rows(:, 1)), cell2mat(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ..."
"                VariableNames=[""Quantity"" ""Value"" ""Units"" ""Format""]);"
"            T.Display = strings(height(T), 1);"
"            T(end+1, :) = {""Model"", NaN, """", """", ""placeholder (parabola)""};"
"        end"
""
"        function scene = showcase(~)"
"            % The Home thumbnail and README screenshot (buildtool images)."
"            scene = struct(""Preset"", """", ""Tab"", ""Result"", ""Time"", NaN);"
"        end"
""
"        function description = about(~)"
"            description = join(["
"                ""Placeholder model (replace it):"""
"                ""y = a x²,   0 ≤ x ≤ span"""
"                ""The area under it is a span³ / 3."""
"            ], newline);"
"        end"
"    end"
"end"
];
end

function text = decayEngine()
text = [
"function result = simulate{{Name}}(params)"
"%SIMULATE{{UPPER}} Placeholder model for {{Title}}: exponential decay,"
"%   dx/dt = −x/τ, stepped exactly (x ← x e^(−dt/τ)) at each output step."
"%   Replace with the real engine. Keep it free of UI code, and throw for"
"%   invalid input (the message is shown in the status bar). The optional"
"%   params.progressFcn(fraction) reports progress and returns true when"
"%   the user cancels; the run then ends early with what it has."
"if params.dt >= params.duration"
"    error(""dlab:invalidParameter"", ""Output step must be smaller than the duration."");"
"end"
"progressFcn = [];"
"if isfield(params, ""progressFcn"")"
"    progressFcn = params.progressFcn;"
"end"
"t = (0:params.dt:params.duration)';"
"n = numel(t);"
"x = zeros(n, 1);"
"x(1) = params.x0;"
"decay = exp(-params.dt / params.tau);"
"reported = 0;"
"for k = 1:n - 1"
"    x(k + 1) = x(k) * decay;"
"    if ~isempty(progressFcn) && k >= reported + 0.02 * n"
"        reported = k;"
"        if progressFcn(k / (n - 1))"
"            t = t(1:k + 1);"
"            x = x(1:k + 1);"
"            break"
"        end"
"    end"
"end"
"result = struct(""t"", t, ""x"", x);"
"end"
];
end

function text = parabolaEngine()
text = [
"function result = simulate{{Name}}(params)"
"%SIMULATE{{UPPER}} Placeholder model for {{Title}}: y = a x² across the span."
"%   Replace with the real engine. Keep it free of UI code, and throw for"
"%   invalid input (the message is shown in the status bar)."
"x = linspace(0, params.span, 101)';"
"result = struct(""x"", x, ""y"", params.a * x.^2);"
"end"
];
end

function text = appTest()
text = [
"classdef (TestTags = {'ui'}) Test{{Name}}Plugin < matlab.unittest.TestCase"
"    %TEST{{UPPER}}PLUGIN {{Title}} in the app. PluginConformanceTest checks the"
"    %   plugin contract and test_simulate{{Name}} the engine's golden values;"
"    %   test what the user sees here."
""
"    properties"
"        App"
"    end"
""
"    methods (TestClassSetup)"
"        function addPaths(testCase)"
"            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));"
"            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));"
"            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);"
"            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ..."
"                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));"
"        end"
"    end"
""
"    methods (TestMethodSetup)"
"        function launch(testCase)"
"            testCase.App = DynamicsLab(""{{Id}}"", Plugins={@dlab.sims.{{Id}}.{{Name}}Plugin}, Visible=false);"
"            testCase.addTeardown(@() testCase.App.close());"
"        end"
"    end"
""
"    methods (Test)"
"        function runFillsTheSummary(testCase)"
"            run = findall(testCase.App.Figure, Tag=""dlab.run"");"
"            run.ButtonPushedFcn(run, []);"
"            testCase.assertEmpty(testCase.App.LastError);"
"            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);"
"            testCase.verifyEqual(M.Value(M.Quantity == ""{{Quantity}}""), M.Value(M.Quantity == ""{{Exact}}""), ..."
"                ""The placeholder model matches its exact solution."", RelTol=1e-3);"
"        end"
"    end"
"end"
];
end

function text = decayEngineTest()
text = [
"function tests = test_simulate{{Name}}"
"%TEST_SIMULATE{{UPPER}} Golden values (known-correct results) for the {{Title}}"
"%   engine. Replace them with ones for the real model."
"tests = functiontests(localfunctions);"
"end"
""
"function setupOnce(testCase)"
"repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));"
"testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));"
"end"
""
"function testDecaysAsTheExactSolution(testCase)"
"% Independent reference: the exact solution x0 e^(−t/τ). Replace it with one for the real"
"% model: a closed form, a published result, or a separate integration, never the engine itself."
"p = struct(""x0"", 1, ""tau"", 2, ""duration"", 10, ""dt"", 0.01);"
"r = dlab.sims.{{Id}}.simulate{{Name}}(p);"
"verifyEqual(testCase, r.x(end), 0.006737946999085467, ""x0 e^(−t/τ) = e^(−5) at t = 10 s."", RelTol=1e-9);"
"end"
""
"function testCancelEndsEarly(testCase)"
"p = struct(""x0"", 1, ""tau"", 2, ""duration"", 10, ""dt"", 0.01, ""progressFcn"", @(~) true);"
"r = dlab.sims.{{Id}}.simulate{{Name}}(p);"
"verifyLessThan(testCase, r.t(end), 10);"
"verifyEqual(testCase, numel(r.x), numel(r.t));"
"end"
""
"function testRejectsAStepLongerThanTheRun(testCase)"
"p = struct(""x0"", 1, ""tau"", 2, ""duration"", 1, ""dt"", 2);"
"verifyError(testCase, @() dlab.sims.{{Id}}.simulate{{Name}}(p), ""dlab:invalidParameter"");"
"end"
];
end

function text = parabolaEngineTest()
text = [
"function tests = test_simulate{{Name}}"
"%TEST_SIMULATE{{UPPER}} Golden values (known-correct results) for the {{Title}}"
"%   engine. Replace them with ones for the real model."
"tests = functiontests(localfunctions);"
"end"
""
"function setupOnce(testCase)"
"repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));"
"testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));"
"end"
""
"function testParabola(testCase)"
"% Independent reference: the closed forms a span² and a span³/3. Replace it with one for the"
"% real model: a closed form, a published result, or a separate calculation, never the engine."
"r = dlab.sims.{{Id}}.simulate{{Name}}(struct(""a"", 1, ""span"", 2));"
"verifyEqual(testCase, r.y(end), 4, ""a span² at the end of the span."", AbsTol=1e-12);"
"verifyEqual(testCase, trapz(r.x, r.y), 8 / 3, ""The area a span³ / 3."", RelTol=1e-3);"
"end"
];
end

function text = decayDocs()
text = [
"# {{Title}}"
""
"{{Summary}}"
""
"> Scaffolded {{Date}} by `dlab.dev.newSimulator`. Everything below describes the placeholder"
"> model: rewrite this page for the real one."
""
"## Model"
""
"Exponential decay, dx/dt = −x/τ, stepped exactly at each output step (x ← x e^(−Δt/τ)), so the"
"result matches x = x0 e^(−t/τ)."
""
"## Inputs"
""
"| Group | Inputs |"
"|---|---|"
"| Model | Initial value x0; time constant τ (s) |"
"| Simulation | Duration (s); output step (s) |"
""
"**Presets:** Slow decay (τ = 5 s)."
""
"## Outputs"
""
"- **Animation:** a marker at the current value."
"- **Response:** x against time."
"- **Summary:** the final value, the exact final value, and the half-life τ ln 2."
""
"## Reference results (asserted by the tests)"
""
"| Check | Value |"
"|---|---:|"
"| x0 = 1, τ = 2 s, after 10 s | x = e^(−5) = 0.006737947 |"
""
"## Lesson"
""
"**{{Title}}: first run** runs the model once."
];
end

function text = parabolaDocs()
text = [
"# {{Title}}"
""
"{{Summary}}"
""
"> Scaffolded {{Date}} by `dlab.dev.newSimulator`. Everything below describes the placeholder"
"> model: rewrite this page for the real one."
""
"## Model"
""
"A parabola, y = a x², across the span, sampled at 101 points."
""
"## Inputs"
""
"| Group | Inputs |"
"|---|---|"
"| Model | Curvature a (1/m); span (m) |"
""
"**Presets:** Steep (a = 3)."
""
"## Outputs"
""
"- **Result:** y against x."
"- **Summary:** the end value, the area under the curve (trapezoid rule), and the exact area"
"  a span³ / 3."
""
"## Reference results (asserted by the tests)"
""
"| Check | Value |"
"|---|---:|"
"| a = 1, span = 2 m | end value 4 m; area 8/3 m² |"
""
"## Lesson"
""
"**{{Title}}: first run** solves the model once."
];
end

function text = lessonStub(fields, folder)
% One step with a check and its solution (the tests work through it).
step = struct("title", "Run the model", ...
    "text", "TODO: what the learner should look for. Press Run, then Check.", ...
    "setup", struct("preset", "Defaults", "tab", fields.FirstTab), ...
    "check", struct("kind", "run", "success", "TODO: what the result shows."), ...
    "solution", struct("run", true), ...
    "claims", struct("kind", "metric", "quantity", fields.Quantity, "value", fields.ExactValue, ...
    "tolerance", 1e-3));
lesson = struct("format", "dynamicslab-lesson", "formatVersion", 1, "id", fields.Id + "-intro", ...
    "title", fields.Title + ": first run", "simulator", fields.Id, "order", nextOrder(folder), ...
    "summary", "TODO: one line on what the lesson teaches.", "steps", {{step}});
text = string(jsonencode(lesson, PrettyPrint=true)) + newline;
end

function text = verificationSheet(fields, kind)
% The verification sheet (docs/verification/README.md), in review, with the
% placeholder model's reference row: replace both with the real model's.
if kind == "time"
    reference = "| Defaults: x0 = 1, τ = 2 s, at t = 10 s | x0 e^(−t/τ) = e^(−5) = 0.006737947 (exact) | " + ...
        "TODO | TODO | TODO |";
else
    reference = "| Defaults: a = 1/m, span 2 m | area a span³/3 = 8/3 (exact) | TODO | TODO | TODO |";
end
text = join([
    "# " + fields.Title + " — verification"
    ""
    "Status: in review"
    "Screenshots: `verification/" + fields.Id + "/index.html` (run `dlab.dev.captureVerification(""" + ...
        fields.Id + """)` to make them)"
    ""
    "## Model as implemented"
    "TODO: equations, units, signs, frames, and assumptions, read from the engine; differences from"
    "the docs page and about()."
    ""
    "## Reference values"
    "Independent of the engine and its tests (closed forms, published results, hand calculations,"
    "a separate integration)."
    ""
    "| Case | Independent value (source) | App | Difference | Verdict |"
    "|---|---|---|---|---|"
    reference
    ""
    "## Automatic checks"
    "TODO: the table from captureVerification and checkBehaviour."
    ""
    "## Checklist"
    "- [ ] Physics: equations, units, signs, frames, assumptions match the docs page and about()"
    "- [ ] Numbers: defaults, every preset, and edge cases against the reference values"
    "- [ ] Inputs: labels, units, ranges, tooltips, visibility rules; presets load what they say"
    "- [ ] Outputs: every tab of every preset readable in both themes and at Larger text"
    "- [ ] Summary and exports: Summary, plots, and CSV agree; units everywhere"
    "- [ ] Analysis: Sweep, Map, Optimize, Uncertainty, Fit sensible; Modes and Bode against hand values"
    "- [ ] Teaching: every lesson number is a claim, from the reference values"
    "- [ ] Behaviour: readable errors; Cancel; run time; nothing left behind"
    ""
    "## Findings"
    "| # | Area | Finding | Resolution | Test |"
    "|---|---|---|---|---|"
], newline) + newline;
end

% --------------------------------------------------------------- helpers
function order = nextOrder(folder)
% After every lesson already in FOLDER.
order = 1;
for f = reshape(dir(fullfile(folder, "*.json")), 1, [])
    try
        raw = jsondecode(fileread(fullfile(f.folder, f.name), Encoding="UTF-8"));
        order = max(order, double(raw.order) + 1);
    catch
        % no order, or not a lesson: it does not count
    end
end
end

function writeThumbnail(file, themeName, kind)
% A flat placeholder in the theme's colours with the model's curve, until
% "buildtool images" renders the real view.
theme = dlab.ui.Theme.byName(themeName);
[h, w] = deal(408, 489);                       % the size buildtool images makes
pixels = zeros(h, w, 3);
for c = 1:3
    pixels(:, :, c) = theme.AxesBackground(c);
end
x = linspace(0.1, 0.9, 600);
if kind == "time"
    y = 0.15 + 0.7 * exp(-5 * (x - 0.1));
else
    y = 0.15 + 0.7 * ((x - 0.1) / 0.8).^2;
end
rows = round((1 - y) * h);
columns = round(x * w);
for k = 1:numel(x)
    for c = 1:3
        pixels(rows(k) + (-2:2), columns(k) + (-2:2), c) = theme.Accent(c);
    end
end
imwrite(pixels, file);
end

function addReadmeRow(readme, category, row)
% Insert ROW at the end of CATEGORY's section of the simulator table, or
% start a section for a new category at the end of the table.
text = string(fileread(readme, Encoding="UTF-8"));
lines = split(text, newline);
header = find(strtrim(lines) == "| **" + category + "** | |", 1);
if isempty(header)
    k = find(startsWith(lines, "| Simulator |"), 1);
    assert(~isempty(k), "dlab:dev:readme", "Could not find the simulator table in %s.", readme);
    while k < numel(lines) && startsWith(lines(k + 1), "|")
        k = k + 1;
    end
    added = ["| **" + category + "** | |"; row];
else
    k = header;
    while k < numel(lines) && startsWith(lines(k + 1), "|") && ~startsWith(lines(k + 1), "| **")
        k = k + 1;
    end
    added = row;
end
writeFile(readme, join([lines(1:k); added; lines(k + 1:end)], newline));
end

function text = render(template, fields)
text = join(template, newline) + newline;
fields.UPPER = upper(fields.Name);
for key = string(fieldnames(fields))'
    text = replace(text, "{{" + key + "}}", string(fields.(key)));
end
end

function name = className(title)
words = regexp(char(title), "[A-Za-z0-9]+", "match");
assert(~isempty(words), "dlab:dev:title", "The title needs letters or digits.");
name = strjoin(cellfun(@(w) [upper(w(1)) w(2:end)], words, UniformOutput=false), "");
name = string(name);
if ~isletter(char(extractBefore(name, 2)))
    name = "Sim" + name;
end
end

function text = escapeCell(text)
% Text for a Markdown table cell.
text = replace(text, "|", "\|");
end

function writeFile(file, text)
fid = fopen(file, "w", "n", "UTF-8");
assert(fid > 0, "dlab:dev:write", "Cannot write %s.", file);
closer = onCleanup(@() fclose(fid));
fwrite(fid, char(text), "char");
end

function mustBeValidId(id)
if ~matches(id, regexpPattern("[a-z][a-z0-9]*"))
    error("dlab:dev:id", "The id must be lowercase letters and digits, starting with a letter.");
end
end

function mustBePlainText(text)
% It goes into MATLAB string literals and one-line Markdown.
if contains(text, ["""" newline char(13)])
    error("dlab:dev:text", "Titles, categories, and summaries cannot contain double quotes or line breaks.");
end
end
