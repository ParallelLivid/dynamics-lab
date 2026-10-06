classdef (TestTags = {'ui'}) TestTrussPlugin < matlab.unittest.TestCase
    %TESTTRUSSPLUGIN Truss in the shell: README reference forces and the
    %   behaviours the original app's UI tests covered (test_truss_ui.m).

    properties
        App
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                dlab.core.Paths.EnvironmentVariable, string(temp.Folder)));
        end
    end

    methods (TestMethodSetup)
        function launch(testCase)
            testCase.App = DynamicsLab("truss", Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function c = find(testCase, tag)
            c = findall(testCase.App.Figure, Tag=tag);
            testCase.assertNumElements(c, 1, tag);
        end

        function press(testCase, tag)
            b = testCase.find(tag);
            b.ButtonPushedFcn(b, []);
        end

        function choosePreset(testCase, name)
            dd = testCase.find("dlab.preset");
            dd.Value = "builtin:" + name;
            dd.ValueChangedFcn(dd, []);
        end

        function forces = solveAndReadForces(testCase)
            testCase.press("dlab.run");
            testCase.assertEmpty(testCase.App.LastError);
            data = testCase.find("dlab.truss.result.state").Data;
            forces = dictionary(string(data(:, 1)), 1000 * cell2mat(data(:, 2)));     % kN in the table
        end

        function text = status(testCase)
            text = string(testCase.find("dlab.status").Text);
        end
    end

    methods (Test)
        function draggingANodeMovesItAsOneEdit(testCase)
            view = testCase.App.View;
            plugin = view.Plugin;
            before = view.params().nodes;
            solveAndReadForces(testCase);
            plugin.dragNode(3, before(3, :) + [1.26 0.74]);      % snaps to 0.5 m
            after = view.params().nodes;
            testCase.verifyEqual(after(3, :), round((before(3, :) + [1.26 0.74]) / 0.5) * 0.5);
            testCase.verifyEqual(after([1 2], :), before([1 2], :));
            testCase.verifySubstring(testCase.status(), "moved to");
            testCase.verifyTrue(view.IsStale, "Moving a node makes the results stale.");
            markers = testCase.find("dlab.truss.nodes");
            testCase.verifyEqual([markers.XData(3) markers.YData(3)], after(3, :));
            fig = testCase.App.Figure;
            testCase.verifyEmpty(fig.WindowButtonMotionFcn, "The figure's callbacks are given back.");
            testCase.verifyEmpty(fig.WindowButtonUpFcn);

            testCase.press("dlab.undo");                          % one undo step
            testCase.verifyEqual(view.params().nodes, before);

            % Solving after a drag equals typing the coordinates.
            plugin.dragNode(3, [before(3, 1) + 1, before(3, 2)]);
            dragged = solveAndReadForces(testCase);
            typed = plugin.solve(view.params());
            testCase.verifyEqual(values(dragged), typed.memberForces(:), AbsTol=0.05);   % the table: kN to 4 decimals
        end

        function tinyDragsAndBusyViewsChangeNothing(testCase)
            view = testCase.App.View;
            before = view.params().nodes;
            view.Plugin.dragNode(2, before(2, :) + [1e-4 0]);   % a click, not a drag
            testCase.verifyEqual(view.params().nodes, before);
            view.Inputs.setEnabled(false);
            view.Plugin.dragNode(2, before(2, :) + [2 0]);
            testCase.verifyEqual(view.params().nodes, before);
            view.Inputs.setEnabled(true);
        end

        function snappingCanBeTurnedOff(testCase)
            view = testCase.App.View;
            field = testCase.find("dlab.param.snap");
            field.Value = 0;
            field.ValueChangedFcn(field, []);
            before = view.params().nodes;
            view.Plugin.dragNode(2, before(2, :) + [1.234 0.567]);
            testCase.verifyEqual(view.params().nodes(2, :), before(2, :) + [1.234 0.567], AbsTol=1e-12);
        end

        function simpleTriangleMatchesReadme(testCase)
            testCase.verifyEqual(testCase.App.View.Preset, "Defaults");
            f = testCase.solveAndReadForces();
            testCase.verifyEqual(f("A-B"), 5773.7, RelTol=1e-4);
            testCase.verifyEqual(f("B-C"), -11547, RelTol=1e-4);
            testCase.verifyEqual(f("A-C"), -11547, RelTol=1e-4);
            reactions = testCase.find("dlab.truss.result.reaction").Data;
            testCase.verifyEqual(string(reactions(:, 1))' + "-" + string(reactions(:, 2))', ...
                ["A-X" "A-Y" "B-Y"]);
            testCase.verifyEqual(1000 * cell2mat(reactions(:, 3))', [0 10000 10000], AbsTol=1e-6);
            testCase.verifyEqual(string(testCase.find("dlab.run").Text), "▶  Solve");
        end

        function prattMatchesReadme(testCase)
            testCase.choosePreset("Pratt truss (6-panel)");
            f = testCase.solveAndReadForces();
            testCase.verifyEqual(f("A-B"), 0, AbsTol=1e-6);
            testCase.verifyEqual(f("D-E"), 32000, RelTol=1e-6);
            testCase.verifyEqual(f("J-K"), -36000, RelTol=1e-6);
            testCase.verifyEqual(f("B-H"), 36056, RelTol=1e-4);
        end

        function finkMatchesReadme(testCase)
            testCase.choosePreset("Roof truss (Fink)");
            f = testCase.solveAndReadForces();
            testCase.verifyEqual([f("A-F") f("F-B")], [26667 26667], RelTol=1e-4);
            testCase.verifyEqual([f("A-D") f("B-E")], [-33333 -33333], RelTol=1e-4);
            testCase.verifyEqual(f("C-F"), 10000, RelTol=1e-6);
        end

        function diagonalsFollowTheTrussType(testCase)
            plugin = dlab.sims.truss.TrussPlugin();
            pratt = plugin.solve(plugin.presetParams("Pratt truss (6-panel)"));
            howe = plugin.solve(plugin.presetParams("Howe truss (6-panel)"));
            testCase.verifyNumElements(pratt.memberForces, 25);
            testCase.verifyGreaterThan(pratt.memberForces(20:25), 0, "Pratt diagonals are in tension.");
            testCase.verifyLessThan(howe.memberForces(20:25), 0, "Howe diagonals are in compression.");
        end

        function firstSupportWorksAfterClear(testCase)
            % Legacy regression: adding a support to a fresh model failed.
            for attempt = 1:2
                testCase.press("dlab.truss.clear");
                testCase.press("dlab.truss.addnode");
                testCase.press("dlab.truss.addsupport");
                data = testCase.find("dlab.truss.table.supports").Data;
                testCase.verifyEqual(size(data, 1), 1);
                testCase.verifyEqual(data{1, 1}, 1);
            end
        end

        function invalidMemberEditsLeaveModelUnchanged(testCase)
            inputs = testCase.App.View.Inputs;
            before = inputs.Model;
            for value = {NaN, Inf, -Inf, 'bad', [], [1 2], 1i, 0, 4, 2}
                inputs.editCell("members", 1, 1, value{1});    % member A-B: 2 equals its other end
                testCase.verifyEqual(inputs.Model, before);
            end
            testCase.verifySubstring(testCase.status(), "rejected");
            inputs.editCell("members", 1, 2, 3);                % A-B becomes A-C: allowed
            testCase.verifyEqual(inputs.Model.members(1, :), [1 3 1], "Its section (S1) is kept.");
        end

        function deletingANodeRenumbersTheModel(testCase)
            model = dlab.sims.truss.TrussInputs.normalize(dlab.sims.truss.TrussPlugin().defaultParams());
            after = dlab.sims.truss.TrussInputs.removeRows(model, "nodes", 1);
            testCase.verifyEqual(after.nodes, [4 0; 2 3.464]);
            testCase.verifyEqual(after.members, [1 2 1]);         % only B-C survives, renumbered (section S1)
            testCase.verifyEqual(after.forces, [2 0 -20000]);
            testCase.verifyEqual(after.supports, [1 3]);
        end

        function editsMakeResultsStaleAndRedrawThePreview(testCase)
            testCase.press("dlab.run");
            testCase.App.View.Inputs.addNode(6, 0);
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "on");
            testCase.verifyEqual(testCase.App.View.Preset, "Custom");
            canvas = findall(testCase.App.Figure, Type="axes", Tag="");   % the model canvas (shell axes are tagged)
            testCase.verifySubstring(string(canvas.Title.String), "4 nodes");
            testCase.verifySubstring(testCase.status(), "Node D added");
        end

        function displayTogglesDoNotInvalidate(testCase)
            testCase.press("dlab.run");
            toggle = testCase.find("dlab.param.showForceValues");
            toggle.Value = true;
            toggle.ValueChangedFcn(toggle, []);
            canvas = findall(testCase.App.Figure, Type="axes", Tag="");   % the model canvas (shell axes are tagged)
            labels = string({findall(canvas, Type="text").String});
            testCase.verifyTrue(any(startsWith(labels, "A-B  5.774 kN")));
            testCase.verifyEqual(string(testCase.find("dlab.stale").Visible), "off");
            testCase.verifyEqual(testCase.App.View.Preset, "Defaults");
        end

        function solverErrorsAreReported(testCase)
            inputs = testCase.App.View.Inputs;
            inputs.deleteRows("supports", 1:2);
            testCase.press("dlab.run");
            testCase.verifyEqual(testCase.status(), "Add supports before solving.");
            testCase.press("dlab.truss.clear");
            canvas = findall(testCase.App.Figure, Type="axes", Tag="");   % the model canvas (shell axes are tagged)
            testCase.verifySubstring(string(canvas.Title.String), "No nodes yet");
        end

        function footbridgeWebBucklesAndCanBeFixed(testCase)
            testCase.choosePreset("Footbridge check (steel tubes)");
            testCase.press("dlab.run");
            testCase.assertEmpty(testCase.App.LastError);
            r = testCase.App.View.Result;
            testCase.verifyEqual(nnz(r.utilization > 1), 4);
            testCase.verifyEqual(unique(r.failureMode(r.utilization > 1)), "buckling");
            testCase.verifySubstring(testCase.status(), "fail the strength check");
            % Give every web member the 76.1 mm tube (S3): it holds.
            inputs = testCase.App.View.Inputs;
            inputs.setMemberSection(find(inputs.Model.members(:, 3) == 2), 3);
            testCase.press("dlab.run");
            r = testCase.App.View.Result;
            testCase.verifyLessThan(max(r.utilization), 1);
            M = testCase.App.View.Plugin.metrics(r);
            testCase.verifyEqual(M.Value(M.Quantity == "Members that fail"), 0);
            testCase.verifyEqual(M.Value(M.Quantity == "Safety factor"), 1 / max(r.utilization), RelTol=1e-12);
        end

        function sectionEditsFillInProperties(testCase)
            inputs = testCase.App.View.Inputs;
            lib = dlab.physics.sectionLibrary();
            inputs.editCell("sections", 1, 4, "Round tube");          % shape: A and I from D and t
            s = inputs.Model.sections(1, :);
            [A, I] = lib.properties(1, s(5), s(6));
            testCase.verifyEqual(s(7:8), [A I], RelTol=1e-12);
            inputs.editCell("sections", 1, 5, 273);                   % D = 273, t stays: recomputed
            inputs.editCell("sections", 1, 6, 12.7);
            testCase.verifyEqual(inputs.Model.sections(1, 7:8), [103.86 8817], RelTol=1e-3);
            inputs.editCell("sections", 1, 1, "Aluminium (6061-T6)"); % material: E and yield
            testCase.verifyEqual(inputs.Model.sections(1, 3:4), [69 276]);
            inputs.editCell("sections", 1, 2, 70);                    % typed E: custom material
            testCase.verifyEqual(lib.MaterialNames(inputs.Model.sections(1, 1)), "custom");
            inputs.editCell("sections", 1, 7, 50);                    % typed A: custom shape
            testCase.verifyEqual(lib.ShapeNames(inputs.Model.sections(1, 2)), "custom");
            inputs.editCell("sections", 1, 4, "Round tube");
            wall = inputs.Model.sections(1, 6);
            inputs.editCell("sections", 1, 6, 200);                   % wall thicker than the tube
            testCase.verifySubstring(testCase.status(), "unchanged");
            testCase.verifyEqual(inputs.Model.sections(1, 6), wall);
            inputs.deleteRows("sections", 1);                         % used by members: refused
            testCase.verifySubstring(testCase.status(), "used by members");
            testCase.verifyEqual(size(inputs.Model.sections, 1), 1);
        end

        function version1ScenariosMigrateTheirMaterial(testCase)
            plugin = dlab.sims.truss.TrussPlugin();
            old = plugin.defaultParams();
            old = rmfield(old, "sections");
            [old.E, old.A] = deal(70e9, 0.002);
            params = plugin.migrate(old, 1);
            testCase.verifyFalse(isfield(params, "E"));
            testCase.verifyEqual(params.sections(3), 70, "E in GPa");
            testCase.verifyEqual(params.sections(7), 20, "A in cm²");
            r = plugin.solve(params);
            testCase.verifyTrue(r.success);
        end

        function version2ScenariosLoadNominalStrengthSilently(testCase)
            plugin = dlab.sims.truss.TrussPlugin();
            params = plugin.defaultParams();
            params.loadScale = 1.5;
            s = jsondecode(jsonencode(dlab.core.ScenarioIO.toStruct(plugin, rmfield(params, "strengthScale"))));
            s.simulator = string(s.simulator);
            s.schemaVersion = 2;
            [loaded, warnings] = dlab.core.ScenarioIO.fromStruct(s, plugin);
            testCase.verifyEmpty(warnings);
            testCase.verifyEqual(loaded.strengthScale, 1);
            testCase.verifyEqual(loaded.loadScale, 1.5);
        end

        function scenarioRoundTripKeepsSingleRowArrays(testCase)
            plugin = dlab.sims.truss.TrussPlugin();
            params = plugin.defaultParams();                     % one force row
            params.supports = [1 1];                             % one support row
            decoded = jsondecode(jsonencode(dlab.core.ScenarioIO.toStruct(plugin, params)));
            decoded.simulator = string(decoded.simulator);
            loaded = dlab.core.ScenarioIO.fromStruct(decoded, plugin);
            testCase.verifyEqual(loaded.forces, [3 0 -20000]);
            testCase.verifyEqual(loaded.supports, [1 1]);
            params.forces = zeros(0, 3);                         % and empty arrays
            decoded = jsondecode(jsonencode(dlab.core.ScenarioIO.toStruct(plugin, params)));
            decoded.simulator = string(decoded.simulator);
            loaded = dlab.core.ScenarioIO.fromStruct(decoded, plugin);
            testCase.verifySize(loaded.forces, [0 3]);
        end

        function summaryNamesTiesAndHandlesNoLoad(testCase)
            % The footbridge's four end posts share the largest utilization
            % (1.3492, method of joints); with no load there is no safety
            % factor to show ("Inf").
            plugin = testCase.App.View.Plugin;
            p = plugin.presetParams("Footbridge check (steel tubes)");
            S = plugin.summaryTable(plugin.solve(p));
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyEqual(S.Quantity(1), "Largest tension", "Results first, counts last.");
            testCase.verifyEqual(S.Value(S.Quantity == "Largest utilization"), 1.349181, RelTol=1e-5);
            testCase.verifySubstring(shown(S.Quantity == "Governing member"), "and 3 more as high");
            p.loadScale = 0;
            S = plugin.summaryTable(plugin.solve(p));
            shown = dlab.core.RunReport.summaryText(S);
            testCase.verifyFalse(any(contains(shown, ["Inf" "NaN"])), strjoin(shown, ", "));
            testCase.verifyEqual(shown(S.Quantity == "Safety factor"), "— (no load)");
        end

        function exportIsFiniteAndNamed(testCase)
            % Every member's Euler load π²EI/L² (Inf in tension before), and
            % member names; a zero-force member is governed by nothing.
            plugin = testCase.App.View.Plugin;
            r = plugin.solve(plugin.presetParams("Footbridge check (steel tubes)"));
            T = plugin.exportTable(r);
            testCase.verifyTrue(all(isfinite(T.euler_load)));
            [D, d] = deal(0.0603, 0.0603 - 2 * 0.0032);     % the 60.3 × 3.2 mm web tube
            [A, I] = deal(pi / 4 * (D^2 - d^2), pi / 64 * (D^4 - d^4));
            testCase.verifyEqual(T.euler_load(T.member == "A-H"), pi^2 * 200e9 * I / 2.5^2, RelTol=1e-4);
            testCase.verifyEqual(T.stress(T.member == "A-H"), -100e3 / A, RelTol=1e-4);
            testCase.verifyEqual(T.governed_by(T.member == "A-B"), "", "A-B carries nothing.");
        end

        function inputsFitAndCanvasShowsScaledLoads(testCase)
            % The colour choices fit their field ("Strength che…" was cut
            % off); the canvas labels the loads as solved, load scale included.
            spec = testCase.App.View.Plugin.parameters();
            spec = spec([spec.Name] == "colorBy");
            testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11);
            testCase.App.View.applySetup(struct("params", struct("loadScale", 2)));
            labels = string(get(findall(testCase.App.Figure, Type="text"), "String"));
            testCase.verifyTrue(any(contains(labels, "-40 kN")), "20 kN × 2 at C.");
        end
    end
end
