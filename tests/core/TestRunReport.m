classdef TestRunReport < matlab.unittest.TestCase
    %TESTRUNREPORT The HTML run report without a window: inputs as the
    %   panel shows them, Summary text, escaping, structure, and images
    %   that cannot be exported. TestRunReportUi embeds real plots.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (Test)
        function escapesTheFiveCharacters(testCase)
            testCase.verifyEqual(dlab.core.RunReport.escape("a & b < c > d ""e"" 'f'"), ...
                "a &amp; b &lt; c &gt; d &quot;e&quot; &#39;f&#39;");
            testCase.verifyEqual(dlab.core.RunReport.escape("&lt;"), "&amp;lt;", "Ampersands go first.");
            testCase.verifyEqual(dlab.core.RunReport.escape(["<" "x"]), ["&lt;" "x"]);
        end

        function visibleProjectileInputsAppearOnce(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            specs = plugin.parameters();
            p = plugin.defaultParams();
            groups = dlab.core.RunReport.inputGroups(specs, p);
            testCase.verifyEqual([groups.Name], ["Model" "Launch" "Environment" "Simulation" "Analysis" "Display"], ...
                "Groups with nothing visible (Drag, Air, Spin for a point mass) are left out.");
            labels = vertcat(groups.Rows);
            labels = labels.Label;
            visible = specs(arrayfun(@(s) s.isVisible(p), specs));
            testCase.verifyEqual(sort(labels), sort([visible.Label])', "Every visible input once, no hidden one.");

            launch = groups([groups.Name] == "Launch").Rows;
            testCase.verifyEqual(launch.Value(launch.Label == "Launch speed"), "50");
            testCase.verifyEqual(launch.Units(launch.Label == "Launch speed"), "m/s");
            model = groups(1).Rows;
            testCase.verifyEqual(model.Value, "Point mass", "Choices show their labels.");
            testCase.verifyEqual(model.Units, "");
            shown = groups(end).Rows;
            testCase.verifyEqual(shown.Value, "Yes");
        end

        function visibilityFollowsTheValues(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            specs = plugin.parameters();
            p = plugin.defaultParams();
            p.model = "sphere";
            p.density = "isa";
            groups = dlab.core.RunReport.inputGroups(specs, p);
            rows = vertcat(groups.Rows);
            for label = ["Size given by" "Radius" "Drag coefficient" "Launch site altitude" "Wind" "Backspin"]
                testCase.verifyEqual(nnz(rows.Label == label), 1, label + " is shown once.");
            end
            for label = ["Frontal area" "Air density" "Wind profile"]
                testCase.verifyFalse(any(rows.Label == label), label + " is hidden.");
            end
            testCase.verifyEqual(groups([groups.Name] == "Drag").Rows.Units(1), "", ...
                "A choice has no units.");
        end

        function missingValuesUseTheDefaults(testCase)
            plugin = dlab.sims.projectile.ProjectilePlugin();
            groups = dlab.core.RunReport.inputGroups(plugin.parameters(), struct("v0", 12));
            launch = groups([groups.Name] == "Launch").Rows;
            testCase.verifyEqual(launch.Value(1:2), ["12"; "45"]);
        end

        function everyInputTypeHasReadableText(testCase)
            P = @dlab.core.ParamSpec;
            C = @dlab.core.TableColumn;
            specs = [
                P("k", Label="Stiffness", Units="N/m", Default=1234.5678, DisplayFormat="%.2f")
                P("n", Label="Count", Type="integer", Default=3)
                P("on", Label="Damping", Type="logical", Default=false)
                P("elev", Label="Elevator", Units="deg", Type="schedule", ...
                    Default=dlab.core.Schedule.make("step", Value=0, Amplitude=2, Start=1))
                P("thr", Label="Throttle", Type="schedule", ...
                    Default=dlab.core.Schedule.make("points", Points=[0 0; 2 1]))
                P("stages", Label="Stages", Type="table", MinRows=1, Columns=[
                    C("dry", Label="Dry mass", Units="t", Default=4)
                    C("kind", Label="Type", Type="choice", Choices=["solid" "liquid"])
                    C("on", Label="Used", Type="logical", Default=true)])
            ];
            p = dlab.core.ParamSpec.defaults(specs);
            p.stages = [p.stages; p.stages];
            p.stages.kind(2) = "liquid";
            rows = dlab.core.RunReport.inputGroups(specs, p).Rows;
            testCase.verifyEqual(rows.Value(1:3), ["1234.57"; "3"; "No"]);
            testCase.verifyEqual(rows.Units(1:3), ["N/m"; ""; ""]);
            testCase.verifyEqual(rows.Value(4), dlab.core.Schedule.describe(p.elev, "deg"));
            testCase.verifyEqual(rows.Units(4), "", "The schedule text says its units.");
            testCase.verifyEqual(rows.Value(5), "points (t s, value): 0 0; 2 1");
            testCase.verifyEqual(rows.Value(6), "1: Dry mass 4 t, Type solid, Used yes" + newline + ...
                "2: Dry mass 4 t, Type liquid, Used yes");
            html = dlab.core.RunReport.render(struct("Groups", dlab.core.RunReport.inputGroups(specs, p)));
            testCase.verifySubstring(html, "Used yes<br>2: Dry mass", "Table rows become lines.");
        end

        function summaryRowsApplyFormatAndDisplay(testCase)
            T = table(["Range"; "Apex"; "Termination"; "Flag"], [1234.5678; 0.000123456; NaN; 1], ...
                ["m"; "m"; ""; ""], ["%.1f"; ""; ""; "%d"], [""; ""; "Hit the ground"; missing], ...
                VariableNames=["Quantity" "Value" "Units" "Format" "Display"]);
            S = dlab.core.RunReport.summaryRows(T);
            testCase.verifyEqual(S.Properties.VariableNames, {'Quantity' 'Text' 'Units'});
            testCase.verifyEqual(S.Text, ["1234.6"; "0.000123456"; "Hit the ground"; "1"]);
            testCase.verifyEqual(S.Units, ["m"; "m"; ""; ""]);
            testCase.verifyEqual(dlab.core.RunReport.summaryText(T), S.Text);
        end

        function summaryRowsAcceptOldStringValues(testCase)
            T = table(["Period"; "Regime"], ["2.006"; "chaotic"], ["s"; ""], ...
                VariableNames=["Quantity" "Value" "Units"]);
            testCase.verifyEqual(dlab.core.RunReport.summaryRows(T).Text, ["2.006"; "chaotic"]);
            C = table(["Period"; "Regime"], {2.00612345; "chaotic"}, ["s"; ""], ...
                VariableNames=["Quantity" "Value" "Units"]);
            testCase.verifyEqual(dlab.core.RunReport.summaryRows(C).Text, ["2.00612"; "chaotic"]);
            testCase.verifyEqual(height(dlab.core.RunReport.summaryRows(table.empty)), 0);
        end

        function summaryOfARealPlugin(testCase)
            plugin = dlabtest.ToyOscillatorPlugin();
            result = plugin.solve(plugin.defaultParams());
            T = plugin.summaryTable(result);
            S = dlab.core.RunReport.summaryRows(T);
            testCase.verifyEqual(S.Quantity, string(T.Quantity));
            testCase.verifyEqual(S.Text, compose("%.6g", T.Value));
        end

        function pageIsWellFormedAndEscaped(testCase)
            info = sampleInfo();
            html = dlab.core.RunReport.render(info);
            testCase.verifyTrue(startsWith(html, "<!DOCTYPE html>"));
            verifyBalanced(testCase, html);
            testCase.verifySubstring(html, "<title>Test &lt;rig&gt; – Preset: A &amp; B</title>");
            testCase.verifySubstring(html, "Dynamics Lab 9.9.9 · 2026-03-04 05:06");
            testCase.verifySubstring(html, "<td>Gain &quot;K&quot;</td><td>2</td><td>N/m</td>");
            testCase.verifySubstring(html, "<td>Range</td><td>12.3</td><td>m</td>");
            testCase.verifySubstring(html, "<h2>Kept runs</h2>");
            testCase.verifySubstring(html, "<td>Run 1</td><td>Mass = 2 kg</td><td>3.5</td>");
            testCase.verifySubstring(html, "Line one<br>&lt;b&gt;two&lt;/b&gt;");
            testCase.verifyFalse(contains(html, "<b>"), "No unescaped text.");
            testCase.verifySubstring(html, "background: #ffffff", "Always a light page.");
            testCase.verifySubstring(html, "max-width: 100%");
        end

        function optionalPartsCanBeLeftOut(testCase)
            html = dlab.core.RunReport.render(struct("Title", "Bare", "Date", datetime(2026, 1, 1)));
            verifyBalanced(testCase, html);
            testCase.verifySubstring(html, "<h1>Bare</h1>");
            testCase.verifySubstring(html, "Dynamics Lab " + dlab.version());
            for heading = ["Inputs" "Summary" "Kept runs" "Plots" "Notes"]
                testCase.verifyFalse(contains(html, "<h2>" + heading + "</h2>"), heading + " is left out.");
            end
        end

        function anImageThatFailsBecomesANote(testCase)
            info = sampleInfo();
            info.Images = struct("Title", {"Gone <tab>", "Not graphics"}, "Container", {gobjects(1), 42});
            html = dlab.core.RunReport.render(info);
            verifyBalanced(testCase, html);
            testCase.verifySubstring(html, "<p class=""note"">Could not include &quot;Gone &lt;tab&gt;&quot;");
            testCase.verifySubstring(html, "Could not include &quot;Not graphics&quot;");
            testCase.verifyFalse(contains(html, "<img"));
        end

        function writesAUtf8File(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(temp.Folder, "run.html");
            info = sampleInfo();
            dlab.core.RunReport.write(file, info);
            testCase.verifyTrue(isfile(file));
            testCase.verifyEqual(string(fileread(file, Encoding="UTF-8")), dlab.core.RunReport.render(info));
            testCase.verifyEqual(numel(dir(fullfile(temp.Folder, "*"))) - 2, 1, "Only the report is written.");
        end
    end
end

function info = sampleInfo()
info.Title = "Test <rig>";
info.Subtitle = "Preset: A & B";
info.Version = "9.9.9";
info.Date = datetime(2026, 3, 4, 5, 6, 7);
info.Groups = struct("Name", "Physical", "Rows", table(["Gain ""K"""; "Mode"], ["2"; "Fast"], ["N/m"; ""], ...
    VariableNames=["Label" "Value" "Units"]));
info.Summary = table("Range", "12.3", "m", VariableNames=["Quantity" "Text" "Units"]);
info.Runs = table(["Run 1"; "Current"], ["Mass = 2 kg"; "(same inputs)"], [3.5; 4], ...
    VariableNames=["Run" "Inputs that differ" "Range (m)"]);
info.Images = struct("Title", {}, "Container", {});
info.Notes = "Line one" + newline + "<b>two</b>";
end

function verifyBalanced(testCase, html)
% Every element the report emits is closed, in order (void ones excepted).
tags = regexp(html, "<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>", "tokens");
stack = strings(0);
void = ["meta" "img" "br"];
for k = 1:numel(tags)
    closing = tags{k}(1) == "/";
    name = lower(tags{k}(2));
    if ismember(name, void)
        continue
    end
    if closing
        testCase.assertNotEmpty(stack, "</" + name + "> closes nothing.");
        testCase.assertEqual(stack(end), name, "</" + name + "> closes <" + stack(end) + ">.");
        stack(end) = [];
    else
        stack(end+1) = name; %#ok<AGROW>
    end
end
testCase.verifyEmpty(stack, "Unclosed: " + strjoin(stack, ", "));
end
