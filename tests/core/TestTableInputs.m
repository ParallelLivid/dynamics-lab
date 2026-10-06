classdef (TestTags = {'ui'}) TestTableInputs < matlab.unittest.TestCase
    %TESTTABLEINPUTS ParamSpec Type="table": coercion, scenario files,
    %   the table editor in ParamPanel, and editing in the app.

    properties
        Plugin
        Spec
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "fixtures")));
        end
    end

    methods (TestMethodSetup)
        function setUp(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
            testCase.Plugin = dlabtest.ToyTablePlugin();
            testCase.Spec = dlab.core.ParamSpec.find(testCase.Plugin.parameters(), "loads");
        end
    end

    methods (Test)
        function defaultsAreTypedTables(testCase)
            T = testCase.Spec.Default;
            testCase.verifyClass(T, "table");
            testCase.verifyEqual(string(T.Properties.VariableNames), ["x" "w" "kind" "active" "count"]);
            testCase.verifyClass(T.kind, "string");
            testCase.verifyClass(T.active, "logical");
            testCase.verifyEqual(height(testCase.Spec.defaultRow()), 1);
            testCase.verifySubstring(testCase.Spec.tooltip(), "1 to 5 rows");
            % Without a Default, MinRows rows of column defaults.
            spec = dlab.core.ParamSpec("t", Type="table", MinRows=2, ...
                Columns=dlab.core.TableColumn("a", Default=3));
            testCase.verifyEqual(spec.Default, table([3; 3], VariableNames="a"));
            testCase.verifyError(@() dlab.core.ParamSpec("t", Type="table"), "dlab:spec:noColumns");
        end

        function everyInputShapeIsAccepted(testCase)
            spec = testCase.Spec;
            expected = spec.Default;
            fromStruct = struct("x", {0, 2}, "w", {10, 5}, "kind", {'point', 'spread'}, ...
                "active", {true, true}, "count", {1, 2});
            testCase.verifyEqual(coerced(spec, fromStruct), expected);
            testCase.verifyEqual(coerced(spec, dlab.core.TableColumn.toCell(expected)), expected);
            testCase.verifyEqual(coerced(spec, expected(:, [5 4 3 2 1])), expected, "Columns are reordered.");
            one = coerced(spec, struct("x", 1, "w", 2, "kind", 'point', "active", false, "count", 3));
            testCase.verifyEqual(height(one), 1, "One row, as jsondecode returns it.");
        end

        function badTablesAreRejectedWithReasons(testCase)
            spec = testCase.Spec;
            [~, ok, message] = spec.coerce([]);
            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, "1 to 5 rows");
            bad = spec.Default;
            bad.x(2) = -1;
            [~, ok, message] = spec.coerce(bad);
            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, "Position must be in [0, ∞) m (row 2)");
            bad = spec.Default;
            bad.kind(1) = "heavy";
            [~, ok] = spec.coerce(bad);
            testCase.verifyFalse(ok);
            bad = spec.Default;
            bad.count(1) = 1.5;
            [~, ok, message] = spec.coerce(bad);
            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, "whole number");
            [~, ok, message] = spec.coerce(removevars(spec.Default, "w"));
            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, "missing the column w");
            [~, ok] = spec.coerce(repmat(spec.Default, 3, 1));
            testCase.verifyFalse(ok, "Six rows exceed MaxRows.");
            % Numeric matrices work when no column is a choice.
            numeric = dlab.core.ParamSpec("n", Type="table", Columns=[
                dlab.core.TableColumn("a"); dlab.core.TableColumn("b", Type="logical")]);
            testCase.verifyEqual(coerced(numeric, [1 0; 2 1]), table([1; 2], [false; true], VariableNames=["a" "b"]));
        end

        function scenarioFilesRoundTrip(testCase)
            plugin = testCase.Plugin;
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(temp.Folder, "table.json");
            for params = [plugin.defaultParams(), plugin.presetParams("Three loads")]
                one = params;
                one.loads = one.loads(1, :);
                for p = [params one]
                    dlab.core.ScenarioIO.save(file, plugin, p);
                    [loaded, ~, warnings] = dlab.core.ScenarioIO.load(file, plugin);
                    testCase.verifyEqual(loaded, p);
                    testCase.verifyEmpty(warnings);
                end
            end
        end

        function panelEditsAddsAndDeletesRows(testCase)
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            specs = testCase.Plugin.parameters();
            panel = dlab.core.ParamPanel(fig, specs, dlab.core.ParamSpec.defaults(specs), dlab.ui.Theme.light());
            changes = strings(0);
            messages = strings(0);
            l1 = listener(panel, "ValueChanged", @(~, evt) record(evt.Name)); %#ok<NASGU>
            l2 = listener(panel, "StatusMessage", @(~, evt) note(evt.Message)); %#ok<NASGU>
            grid = findall(fig, Tag="dlab.param.loads");
            testCase.assertClass(grid, "matlab.ui.control.Table");
            testCase.verifyEqual(size(grid.Data), [2 5]);

            grid.Data{1, 2} = 42;                                   % an edit
            grid.CellEditCallback(grid, []);
            testCase.verifyEqual(panel.values().loads.w(1), 42);
            testCase.verifyEqual(changes, "loads");

            grid.Data{1, 1} = -5;                                   % rejected, restored
            grid.CellEditCallback(grid, []);
            testCase.verifyEqual(panel.values().loads.x(1), 0);
            testCase.verifyEqual(grid.Data{1, 1}, 0);
            testCase.verifySubstring(messages(end), "Position must be in");

            add = findall(fig, Tag="dlab.param.loads.add");
            add.ButtonPushedFcn(add, []);
            testCase.verifyEqual(height(panel.values().loads), 3);
            testCase.verifyEqual(panel.values().loads(3, :), testCase.Spec.defaultRow());

            remove = findall(fig, Tag="dlab.param.loads.delete");
            grid.Selection = [1 3];
            remove.ButtonPushedFcn(remove, []);
            testCase.verifyEqual(panel.values().loads.w, 5);
            grid.Selection = 1;
            remove.ButtonPushedFcn(remove, []);                    % would leave no rows
            testCase.verifyEqual(height(panel.values().loads), 1);
            testCase.verifySubstring(messages(end), "at least 1 rows");

            panel.setValues(testCase.Plugin.presetParams("Three loads"));
            testCase.verifyEqual(size(grid.Data), [3 5]);
            testCase.verifyEqual(numel(changes), 3, "setValues fires nothing.");
            panel.setEnabled(false);
            testCase.verifyEqual(string(add.Enable), "off");

            function record(name)
                changes(end+1) = name;
            end
            function note(message)
                messages(end+1) = message;
            end
        end

        function tableRowsGrowWithTheText(testCase)
            % At Larger text the rows are taller: the table grows with
            % them (fixed pixels left the frame's elements table showing
            % only its header).
            specs = testCase.Plugin.parameters();
            heights = zeros(1, 2);
            sizes = ["normal" "larger"];
            rows = height(dlab.core.ParamSpec.defaults(specs).loads);
            for k = 1:2
                fig = uifigure(Visible="off");
                testCase.addTeardown(@delete, fig);
                theme = dlab.ui.Theme.light().withTextSize(sizes(k));
                panel = dlab.core.ParamPanel(fig, specs, dlab.core.ParamSpec.defaults(specs), theme);
                field = findall(fig, Tag="dlab.param.loads");
                heights(k) = panel.Grid.RowHeight{field.Layout.Row};
                testCase.verifyGreaterThanOrEqual(heights(k), 27 + rows * dlab.ui.tableRowHeight(field.FontSize), ...
                    sizes(k) + ": the headings and every row");
            end
            testCase.verifyGreaterThan(heights(2), heights(1), "Taller rows at Larger text.");
        end

        function tableColumnsShareThePanelWidth(testCase)
            % Wide enough: the columns share the width by what they need
            % ("Nx"), so numbers are not cut off ("3." for 3.25). Too narrow:
            % each gets what it needs, and the table scrolls sideways, with
            % room for the scroll bar.
            specs = testCase.Plugin.parameters();
            fig = uifigure(Visible="off");
            testCase.addTeardown(@delete, fig);
            panel = dlab.core.ParamPanel(fig, specs, dlab.core.ParamSpec.defaults(specs), dlab.ui.Theme.light());
            field = findall(fig, Tag="dlab.param.loads");
            testCase.verifyEqual(field.ColumnFormat{1}, 'shortG', "3.25, not 3.2500");
            panel.setWidth(600);
            testCase.verifyTrue(iscellstr(field.ColumnWidth) && all(endsWith(field.ColumnWidth, "x")), ...
                "Shared by weight when they fit.");
            wide = panel.Grid.RowHeight{field.Layout.Row};
            panel.setWidth(250);
            testCase.verifyTrue(all(cellfun(@isnumeric, field.ColumnWidth)), "Pixel widths when they do not.");
            testCase.verifyEqual(panel.Grid.RowHeight{field.Layout.Row} - wide, 17, "Room for the scroll bar.");
        end

        function tablesEditInTheAppWithUndo(testCase)
            app = DynamicsLab(Plugins={@dlabtest.ToyTablePlugin}, Visible=false);
            testCase.addTeardown(@() app.close());
            app.open("toytable");
            run = findall(app.Figure, Tag="dlab.run");
            run.ButtonPushedFcn(run, []);
            testCase.assertEmpty(app.LastError);
            testCase.verifyEqual(app.View.Plugin.summaryTable(app.View.Result).Value, 20);

            grid = findall(app.Figure, Tag="dlab.param.loads");
            grid.Data{2, 4} = false;
            grid.CellEditCallback(grid, []);
            testCase.verifyTrue(app.View.IsStale);
            testCase.verifyFalse(app.View.params().loads.active(2));
            undo = findall(app.Figure, Tag="dlab.undo");
            undo.ButtonPushedFcn(undo, []);
            testCase.verifyTrue(app.View.params().loads.active(2));
            testCase.verifyFalse(app.View.IsStale);
            testCase.verifyEqual(grid.Data{2, 4}, true);

            % Scripts may pass tables (or struct arrays); bad shapes are refused.
            params = dlab.core.Headless.params(app.View.Plugin, {"loads", table(1, 2, "point", true, 1, ...
                VariableNames=["x" "w" "kind" "active" "count"])});
            testCase.verifyEqual(height(params.loads), 1);
            testCase.verifyError(@() dlab.core.Headless.params(app.View.Plugin, {"loads", [1 2; 3 4]}), ...
                "dlab:invalidParameter");
        end
    end
end

function value = coerced(spec, value)
[value, ok, message] = spec.coerce(value);
assert(ok, message);
end
