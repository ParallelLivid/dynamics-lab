classdef PluginConformanceTest < matlab.unittest.TestCase
    %PLUGINCONFORMANCETEST The contract every simulator plugin must meet.
    %   Parameterized over every *Plugin.m under +dlab/+sims plus the toy
    %   fixture, so a new simulator is covered without writing anything.

    properties (TestParameter)
        PluginClass = PluginConformanceTest.discover()
        ThemeName = {"dark", "light"}
    end

    properties
        UserData
    end

    methods (Static)
        function classes = discover()
            %DISCOVER Plugin class names, found from files (the path is not
            %   set up yet when test parameters are evaluated).
            root = fileparts(fileparts(mfilename("fullpath")));
            files = dir(fullfile(root, "+dlab", "+sims", "+*", "*Plugin.m"));
            names = strings(1, 0);
            for f = files'
                [~, package] = fileparts(f.folder);
                names(end+1) = "dlab.sims." + extractAfter(string(package), "+") + "." + erase(f.name, ".m"); %#ok<AGROW>
            end
            names(end+1) = "dlabtest.ToyOscillatorPlugin";
            classes = cell2struct(cellstr(names), matlab.lang.makeValidName(names), 2);
        end
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (Test)
        function metadataIsComplete(testCase, PluginClass)
            plugin = feval(PluginClass);
            testCase.verifyTrue(isa(plugin, "dlab.core.TimeDomainPlugin") || isa(plugin, "dlab.core.StaticPlugin"), ...
                "Subclass TimeDomainPlugin or StaticPlugin.");
            testCase.verifyMatches(string(plugin.Id), "^[a-z][a-z0-9]*$", "Id: lowercase letters and digits.");
            for name = ["Title" "Category" "Summary"]
                testCase.verifyNotEqual(strtrim(string(plugin.(name))), "", name + " must be set.");
            end
            testCase.verifyTrue(isscalar(plugin.SchemaVersion) && plugin.SchemaVersion >= 1 ...
                && plugin.SchemaVersion == round(plugin.SchemaVersion));
        end

        function parametersAreWellFormed(testCase, PluginClass)
            plugin = feval(PluginClass);
            specs = plugin.parameters();
            testCase.verifyClass(specs, "dlab.core.ParamSpec");
            testCase.verifyEqual(size(specs, 2), 1, "parameters() returns a column.");
            names = [specs.Name];
            testCase.verifyEqual(numel(unique(names)), numel(names), "Parameter names must be unique.");
            params = plugin.defaultParams();
            testCase.verifyEqual(dlab.core.ParamSpec.validateAll(specs, params), params);
            for spec = specs'
                testCase.verifyClass(spec.isVisible(params), "logical", spec.Name + " VisibleWhen");
            end
        end

        function inputsHaveTooltips(testCase, PluginClass)
            % Every input explains itself (the first verification pass found over 100 without a tooltip).
            plugin = feval(PluginClass);
            for spec = plugin.parameters()'
                testCase.verifyNotEqual(strtrim(spec.Description), "", spec.Name + ": give it a Description (tooltip).");
            end
        end

        function defaultsAndEveryPresetSolve(testCase, PluginClass)
            plugin = feval(PluginClass);
            cases = [{"Defaults"}, {plugin.presets().Name}];
            for k = 1:numel(cases)
                if k == 1
                    params = plugin.defaultParams();
                else
                    params = plugin.presetParams(cases{k});
                end
                result = plugin.solve(params);
                T = plugin.exportTable(result);
                testCase.verifyClass(T, "table", cases{k});
                testCase.verifyGreaterThan(height(T), 0, cases{k});
                testCase.verifyEqual(numel(T.Properties.VariableUnits), width(T), ...
                    cases{k} + ": set VariableUnits for every column.");
                S = plugin.summaryTable(result);
                if ~isempty(S)
                    testCase.verifyTrue(all(ismember(["Quantity" "Value" "Units"], ...
                        S.Properties.VariableNames)), "summaryTable needs Quantity, Value, Units.");
                    summaryConventions(testCase, S, cases{k});
                end
                if plugin.kind() == "time"
                    t = plugin.timeVector(result);
                    testCase.verifyTrue(iscolumn(t) && all(diff(t) >= 0), "timeVector: ascending column.");
                end
            end
        end

        function outputTabsAreValid(testCase, PluginClass)
            plugin = feval(PluginClass);
            titles = plugin.outputTabs(plugin.defaultParams());
            testCase.verifyClass(titles, "string");
            testCase.verifyEqual(numel(unique(titles)), numel(titles));
            testCase.verifyFalse(any(ismember(titles, dlab.core.SimulatorView.ShellTabs)), ...
                "The shell adds Animation, Summary, Runs, and the analysis tabs itself.");
        end

        function metricsAreNumeric(testCase, PluginClass)
            plugin = feval(PluginClass);
            M = plugin.metrics(plugin.solve(plugin.defaultParams()));
            testCase.verifyEqual(string(M.Properties.VariableNames), ["Quantity" "Value" "Units"]);
            testCase.verifyClass(M.Value, "double");
            testCase.verifyTrue(all(isfinite(M.Value)), "Metrics are finite numbers.");
            testCase.verifyEqual(numel(unique(M.Quantity)), height(M), "Metric names are unique.");
        end

        function distributionsAreFiniteColumns(testCase, PluginClass)
            plugin = feval(PluginClass);
            if ~plugin.implements("distributions")
                return
            end
            D = plugin.distributions(plugin.solve(plugin.defaultParams()));
            testCase.verifyEqual(string(D.Properties.VariableNames), ["Quantity" "Values" "Units"]);
            testCase.verifyClass(D.Values, "cell");
            for k = 1:height(D)
                v = D.Values{k};
                testCase.verifyTrue(isempty(v) || (iscolumn(v) && isnumeric(v) && all(isfinite(v))), ...
                    D.Quantity(k) + ": a column of finite numbers.");
            end
        end

        function linearizationIsWellFormed(testCase, PluginClass)
            plugin = feval(PluginClass);
            if ~plugin.implements("linearization")
                return
            end
            cases = [{"Defaults"}, {plugin.presets().Name}];
            for k = 1:numel(cases)
                if k == 1
                    params = plugin.defaultParams();
                else
                    params = plugin.presetParams(cases{k});
                end
                lin = plugin.linearization(params);
                if isempty(lin)
                    continue
                end
                testCase.verifyEqual(numel(lin.StateNames), numel(lin.X0), cases{k} + ": one name per state.");
                L = dlab.core.Linearization.analyze(lin);
                testCase.verifyTrue(all(isfinite(L.Eigenvalues)), cases{k});
                testCase.verifyTrue(all(L.Modes.Mode ~= ""), cases{k} + ": every mode is named.");
                if dlab.core.FrequencyResponse.available(lin)
                    % Inputs for the Bode tab: F is G at the nominal inputs.
                    x = lin.X0(:) + 1e-3 * (1:numel(lin.X0))';
                    testCase.verifyEqual(lin.G(x, lin.U0(:)), lin.F(x), cases{k} + ": F(x) = G(x, U0).", ...
                        AbsTol=1e-9);
                    S = dlab.core.FrequencyResponse.model(lin);     % checks the names fit
                    R = dlab.core.FrequencyResponse.response(S, 1, 1);
                    testCase.verifyTrue(all(isfinite(R.Response)), cases{k} + ": a finite response.");
                end
            end
        end

        function showcaseNamesARealView(testCase, PluginClass)
            plugin = feval(PluginClass);
            scene = plugin.showcase();
            params = plugin.defaultParams();
            if scene.Preset ~= ""
                params = plugin.presetParams(scene.Preset);   % errors if the preset is unknown
            end
            tabs = plugin.outputTabs(params);
            if plugin.kind() == "time"
                tabs(end+1) = "Animation";
            end
            testCase.verifyTrue(ismember(scene.Tab, tabs), "Showcase tab """ + scene.Tab + """ does not exist.");
        end

        function scenarioRoundTripIsLossless(testCase, PluginClass)
            plugin = feval(PluginClass);
            params = plugin.defaultParams();
            s = dlab.core.ScenarioIO.toStruct(plugin, params);
            decoded = jsondecode(jsonencode(s));
            decoded.simulator = string(decoded.simulator);
            [loaded, warnings] = dlab.core.ScenarioIO.fromStruct(decoded, plugin);
            testCase.verifyEqual(loaded, params);
            testCase.verifyEmpty(warnings);
        end

    end

    methods (Test, TestTags = {'ui'})
        % These open figures (or the whole app): left out of "buildtool fasttest".
        function buildsDrawsAndClearsHeadless(testCase, PluginClass, ThemeName)
            plugin = feval(PluginClass);
            tokens = dlab.ui.Theme.byName(ThemeName);
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            params = plugin.defaultParams();
            containers = dictionary(string.empty, cell.empty);
            tabs = uitabgroup(fig);
            for title = plugin.outputTabs(params)
                containers(title) = {uigridlayout(uitab(tabs, Title=title), [1 1])};
            end
            plugin.buildOutputs(containers, tokens);
            if plugin.kind() == "time"
                plugin.buildAnimation(uigridlayout(uitab(tabs, Title="Animation"), [1 1]), tokens);
            else
                plugin.previewInputs(params);
            end
            result = plugin.solve(params);
            plugin.showResult(result, params);
            if plugin.kind() == "time"
                t = plugin.timeVector(result);
                for time = [t(1), (t(1) + t(end)) / 2, t(end)]
                    plugin.drawFrame(time);
                end
            end
            plugin.clearResult();
            drawnow
        end

        function choicesFitTheirFields(testCase, PluginClass)
            % A choice's label must fit the input panel's 118-pixel field: at
            % the normal text size about 85 px of text show before the "..."
            % (measured: "Crank-Nicolson", 85 px, fits; "Single pendulum",
            % 89.5 px, was cut to "Single pendul..."). Fonts standing in for
            % Helvetica measure up to a pixel apart between platforms
            % ("Newton's cradle": 85.0 px on Windows, 86.0 on Linux), so the
            % check allows one pixel over 85.
            plugin = feval(PluginClass);
            fig = figure(Visible="off");
            testCase.addTeardown(@delete, fig);
            ax = axes(fig, Units="pixels", Position=[1 1 800 100]);
            size = dlab.ui.Theme.dark().FontSize.md;
            for spec = plugin.parameters()'
                if spec.Type ~= "choice"
                    continue
                end
                for label = reshape(spec.ChoiceLabels, 1, [])
                    h = text(ax, 0, 0, label, Units="pixels", FontUnits="pixels", FontSize=size, ...
                        FontName="Helvetica", Interpreter="none");
                    testCase.verifyLessThanOrEqual(round(h.Extent(3)), 86, sprintf("%s: ""%s"" is %.0f px wide; " + ...
                        "shorten it and explain in the Description.", spec.Name, label, h.Extent(3)));
                    delete(h);
                end
            end
        end

        function plotsReadAtEveryPreset(testCase, PluginClass)
            % Each preset's plots, drawn as the app draws them (padded
            % limits): no steady value stretched into round-off noise
            % (Orbital Mechanics' a = 7000 km +- 1e-6 km), and no labels
            % printed over each other (Rocket's "Stage 2 burnout" on "Stage 3
            % ignition").
            plugin = feval(PluginClass);
            tokens = dlab.ui.Theme.dark();
            cases = [{"Defaults"}, {plugin.presets().Name}];
            for c = 1:numel(cases)
                params = plugin.defaultParams();
                if c > 1
                    params = plugin.presetParams(cases{c});
                end
                fig = uifigure(Visible="off", Position=[50 50 1040 720]);
                tabs = uitabgroup(fig, Position=[1 1 1040 720]);
                containers = dictionary(string.empty, cell.empty);
                for title = plugin.outputTabs(params)
                    containers(title) = {uigridlayout(uitab(tabs, Title=title), [1 1])};
                end
                plugin.buildOutputs(containers, tokens);
                if plugin.kind() == "time"
                    plugin.buildAnimation(uigridlayout(uitab(tabs, Title="Animation"), [1 1]), tokens);
                else
                    plugin.previewInputs(params);
                end
                result = plugin.solve(params);
                plugin.showResult(result, params);
                if plugin.kind() == "time"
                    t = plugin.timeVector(result);
                    plugin.drawFrame(t(max(1, round(end / 2))));
                end
                dlab.ui.padLimits(fig);
                for tab = reshape(tabs.Children, 1, [])
                    tabs.SelectedTab = tab;
                    drawnow
                    for ax = reshape(findall(tab, Type="axes"), 1, [])
                        plotReads(testCase, ax, cases{c} + " / " + string(tab.Title));
                    end
                end
                plugin.clearResult();
                delete(fig);
            end
        end

        function overlaysDrawHeadless(testCase, PluginClass, ThemeName)
            plugin = feval(PluginClass);
            if ~plugin.implements("overlayRuns")
                return
            end
            tokens = dlab.ui.Theme.byName(ThemeName);
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            params = plugin.defaultParams();
            containers = dictionary(string.empty, cell.empty);
            tabs = uitabgroup(fig);
            for title = plugin.outputTabs(params)
                containers(title) = {uigridlayout(uitab(tabs, Title=title), [1 1])};
            end
            plugin.buildOutputs(containers, tokens);
            if plugin.kind() == "time"
                plugin.buildAnimation(uigridlayout(uitab(tabs, Title="Animation"), [1 1]), tokens);
            end
            result = plugin.solve(params);
            plugin.showResult(result, params);
            run = struct("Result", {result}, "Params", params, "Label", "Run 1", ...
                "Color", tokens.series(2), "Index", 1);
            plugin.overlayRuns(run);
            testCase.verifyNotEmpty(findall(fig, Tag="dlab.overlay"), "overlayRuns draws tagged lines.");
        end

        function runsInsideTheShell(testCase, PluginClass)
            plugin = feval(PluginClass);
            app = DynamicsLab(plugin.Id, Plugins={str2func(PluginClass)}, Visible=false);
            testCase.addTeardown(@() app.close());
            run = findall(app.Figure, Tag="dlab.run");
            run.ButtonPushedFcn(run, []);
            testCase.verifyEmpty(app.LastError, "Run raised an error.");
            testCase.verifyNotEmpty(app.View.Result);
            keep = findall(app.Figure, Tag="dlab.keepRuns");
            testCase.verifyEqual(logical(keep.Visible), plugin.implements("overlayRuns"), ...
                "Keep previous runs appears exactly when the plugin draws overlays.");
            app.goHome();
            testCase.verifyEmpty(timerfindall(Tag=dlab.core.PlaybackController.TimerTag));
        end
    end
end

% ---------------------------------------------------------------- helpers
function summaryConventions(testCase, S, where)
% Units only in the units column; text rows as text; no unit said twice.
hasDisplay = ismember("Display", S.Properties.VariableNames);
for i = 1:height(S)
    value = S.Value(i);
    if iscell(value)
        value = value{1};
    end
    quantity = string(S.Quantity(i));
    units = string(S.Units(i));
    shown = "";
    if hasDisplay
        shown = string(S.Display(i));
    end
    words = lower(split(units));
    testCase.verifyFalse(any(ismember(words, ["relative" "yes" "no" "true" "false"])) || contains(units, "="), ...
        where + ": """ + quantity + """ has """ + units + """ as units; put words in the name " + ...
        "(""Energy drift (relative)"") and yes/no in Display.");
    if isnumeric(value) && isscalar(value) && ~isfinite(value)
        testCase.verifyNotEqual(shown, "", where + ": """ + quantity + """ is " + value + ...
            "; show text in Display instead.");
    end
    testCase.verifyFalse(ismember(shown, ["NaN" "Inf" "-Inf"]), where + ": """ + quantity + """ shows " + shown);
    if units ~= ""
        testCase.verifyFalse(endsWith(quantity, "(" + units + ")"), ...
            where + ": """ + quantity + """ repeats its units in its name.");
    end
end
end

function plotReads(testCase, ax, where)
% A 2-D axes: no steady value stretched into round-off, no overlapping text.
if ax.Visible == "off" || ~isequal(ax.View, [0 90])
    return
end
name = where + " / " + strjoin(string(ax.Title.String));
y = [];
for line = reshape(findall(ax, Type="line"), 1, [])
    y = [y; line.YData(:)]; %#ok<AGROW>
end
y = y(isfinite(y));
if ax.YScale == "linear" && ~isempty(y) && max(abs(y)) > 0
    testCase.verifyGreaterThanOrEqual(diff(ax.YLim), 1e-9 * max(abs(y)), name + ": the y axis " + ...
        "spans only round-off; give it a minimum span (dlab.ui.minimumSpan).");
end
texts = findall(ax, Type="text");
keep = arrayfun(@(h) h.Visible == "on" && strlength(strjoin(string(h.String), "")) > 0 && ...
    ~isequal(h, ax.Title) && ~isequal(h, ax.XLabel) && ~isequal(h, ax.YLabel), texts);
texts = texts(keep);
if numel(texts) < 2
    return
end
set(texts, Units="pixels");
drawnow
E = cell2mat(arrayfun(@(h) h.Extent, texts, UniformOutput=false));
for i = 1:numel(texts)
    for j = i+1:numel(texts)
        w = min(E(i, 1) + E(i, 3), E(j, 1) + E(j, 3)) - max(E(i, 1), E(j, 1));
        h = min(E(i, 2) + E(i, 4), E(j, 2) + E(j, 4)) - max(E(i, 2), E(j, 2));
        overlap = max(w, 0) * max(h, 0) / max(min(E(i, 3) * E(i, 4), E(j, 3) * E(j, 4)), eps);
        testCase.verifyLessThanOrEqual(overlap, 0.3, sprintf("%s: ""%s"" and ""%s"" print over each other.", ...
            name, strjoin(string(texts(i).String)), strjoin(string(texts(j).String))));
    end
end
end
