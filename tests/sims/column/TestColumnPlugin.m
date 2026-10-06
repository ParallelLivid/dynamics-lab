classdef (TestTags = {'ui'}) TestColumnPlugin < matlab.unittest.TestCase
    %TESTCOLUMNPLUGIN Column buckling in the app: Euler loads from the
    %   section library, the presets, the elastica, and bad inputs.

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
            testCase.App = DynamicsLab("column", Plugins={@dlab.sims.column.ColumnPlugin}, Visible=false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods
        function pressSolve(testCase)
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            testCase.assertEmpty(testCase.App.LastError);
        end

        function choosePreset(testCase, name)
            dd = findall(testCase.App.Figure, Tag="dlab.preset");
            dd.Value = "builtin:" + name;
            dd.ValueChangedFcn(dd, []);
        end

        function value = metric(testCase, quantity)
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            value = M.Value(M.Quantity == quantity);
            testCase.assertNumElements(value, 1, quantity);
        end
    end

    methods (Test)
        function defaultTubeBucklesAtTheEulerLoad(testCase)
            testCase.pressSolve();
            I = pi / 64 * (0.060^4 - 0.052^4);
            testCase.verifyEqual(testCase.metric("Critical load P_cr"), pi^2 * 200e9 * I / 3^2 / 1e3, RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Buckling governs"), 1);
            testCase.verifyEqual(testCase.metric("Amplification"), 1 / (1 - 40 / testCase.metric("Critical load P_cr")), ...
                RelTol=1e-9);
            testCase.verifyLessThan(abs(testCase.metric("Southwell error")), 1e-6);
            testCase.verifyEqual(testCase.App.View.Plugin.RunLabel, "Solve");
            testCase.verifyNotEmpty(findall(testCase.App.Figure, Type="uitab", Title="Summary"));
        end

        function endConditionsScaleTheLoad(testCase)
            testCase.pressSolve();
            pinned = testCase.metric("Critical load P_cr");
            factors = struct("fixedfree", 1 / 4, "fixedfixed", 4, "fixedpinned", (4.493409457909064 / pi)^2);
            for name = string(fieldnames(factors))'
                testCase.App.View.Plugin.requestInputs(struct("endCondition", name), "End conditions");
                testCase.pressSolve();
                testCase.verifyEqual(testCase.metric("Critical load P_cr"), pinned * factors.(name), "RelTol", 1e-9, name);
            end
        end

        function presetsTellTheirStory(testCase)
            testCase.choosePreset("Fixed–fixed timber post");
            testCase.pressSolve();
            testCase.verifyEqual(testCase.metric("Buckling governs"), 0, "A short timber post yields first.");
            testCase.choosePreset("Slender aluminium rod");
            testCase.pressSolve();
            testCase.verifyGreaterThan(testCase.metric("Slenderness K L / r"), 300);
            testCase.choosePreset("Imperfect column near P_cr");
            testCase.pressSolve();
            testCase.verifyEqual(testCase.metric("Amplification"), 20, RelTol=1e-9);
            testCase.verifyGreaterThan(testCase.metric("Stress / yield"), 1);
            testCase.choosePreset("Elastica far past buckling");
            testCase.pressSolve();
            alpha = deg2rad(testCase.metric("Elastica end rotation"));
            [K, ~] = ellipke(sin(alpha / 2)^2);
            testCase.verifyEqual((2 * K / pi)^2, 2, RelTol=1e-4);
        end

        function customSectionAndMaterial(testCase)
            testCase.App.View.Plugin.requestInputs(struct("material", "custom", "E", 100, "yieldStress", 300, ...
                "shape", "custom", "A", 10, "I", 50, "c", 40, "L", 2), "Custom section");
            testCase.pressSolve();
            testCase.verifyEqual(testCase.metric("Critical load P_cr"), pi^2 * 100e9 * 50e-8 / 4 / 1e3, RelTol=1e-9);
            testCase.verifyEqual(testCase.metric("Squash load A σy"), 10e-4 * 300e6 / 1e3, RelTol=1e-12);
        end

        function badInputsAreReported(testCase)
            plugin = testCase.App.View.Plugin;
            plugin.requestInputs(struct("endCondition", "fixedpinned", "analysis", "elastica"), "Elastica");
            b = findall(testCase.App.Figure, Tag="dlab.run");
            b.ButtonPushedFcn(b, []);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "elastica"), string(status.Text));
            plugin.requestInputs(struct("analysis", "linear", "t", 40), "Thick wall");
            b.ButtonPushedFcn(b, []);
            testCase.verifyTrue(contains(string(status.Text), "wall"), string(status.Text));
        end

        function pastBucklingWarnsInSmallDeflection(testCase)
            testCase.App.View.Plugin.requestInputs(struct("loadMode", "ratio", "loadRatio", 1.2), "Past P_cr");
            testCase.pressSolve();
            M = testCase.App.View.Plugin.metrics(testCase.App.View.Result);
            testCase.verifyFalse(any(M.Quantity == "Largest deflection"), "No small-deflection equilibrium.");
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyTrue(contains(string(status.Text), "P ≥ P_cr"), string(status.Text));
        end

        function inputsFitAndExplainThemselves(testCase)
            % A tooltip on every input; choice labels short enough for their
            % fields ("Pinned–pinne…", "Small deflecti…", "Aluminium (6…").
            for spec = testCase.App.View.Plugin.parameters()'
                testCase.verifyNotEqual(spec.Description, "", spec.Name + " has no tooltip.");
                if spec.Type == "choice"
                    testCase.verifyLessThanOrEqual(max(strlength(spec.ChoiceLabels)), 11, spec.Name);
                end
            end
        end

        function summaryRowsAreClean(testCase)
            % Units only in the units column (prose such as "P / failure
            % load" was there); no elastica rows in the imperfect analysis;
            % exact Southwell points give an error of 0, not -1.2e-14 %.
            plugin = testCase.App.View.Plugin;
            testCase.pressSolve();
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyTrue(all(ismember(S.Units, ["" "kN" "m" "mm" "MPa" "deg" "%"])), strjoin(S.Units, ", "));
            testCase.verifyFalse(any(startsWith(S.Quantity, "Elastica")));
            testCase.verifyEqual(S.Value(S.Quantity == "Southwell error"), 0);
            testCase.verifyEqual(S.Display(S.Quantity == "Buckling governs"), "yes (P_cr < A σy)");
            testCase.choosePreset("Elastica far past buckling");
            testCase.pressSolve();
            S = plugin.summaryTable(testCase.App.View.Result);
            testCase.verifyTrue(any(S.Quantity == "Elastica end rotation"));
            testCase.verifyFalse(any(S.Quantity == "Amplification"));
            % With no bow the column curve's legend read "e0 = L/4503599627370496".
            names = string(get(findall(testCase.App.Figure, Type="line"), "DisplayName"));
            testCase.verifyFalse(any(contains(names, "L/4")), strjoin(names(contains(names, "L/")), " | "));
        end

        function elasticaWarnsWhenItsEndsPass(testCase)
            % Past 2.18 P_cr (end rotation 130.7°) the ends pass each other:
            % the shortening exceeds the length.
            testCase.App.View.Plugin.requestInputs(struct("loadMode", "ratio", "loadRatio", 2.1, ...
                "analysis", "elastica", "e0", 0), "Elastica");
            testCase.pressSolve();
            testCase.verifyLessThan(testCase.metric("Elastica end shortening"), 3e3);
            status = findall(testCase.App.Figure, Tag="dlab.status");
            testCase.verifyFalse(contains(string(status.Text), "pass each other"), string(status.Text));
            testCase.App.View.Plugin.requestInputs(struct("loadRatio", 2.3), "Further");
            testCase.pressSolve();
            testCase.verifyGreaterThan(testCase.metric("Elastica end shortening"), 3e3);
            testCase.verifyTrue(contains(string(status.Text), "pass each other"), string(status.Text));
        end

        function analyzeVariesOnlyInputsInUse(testCase)
            % E and the yield stress are hidden (and ignored) with a library
            % material: the Map ran over L × E and was flat in E.
            view = testCase.App.View;
            specs = view.Plugin.parameters();
            used = dlab.core.SweepPanel.usedNames(dlab.core.SweepPanel.sweepable(specs), view.params());
            testCase.verifyFalse(any(ismember(["E" "yieldStress" "A" "I" "c" "loadRatio"], used)));
            testCase.verifyEqual(used(1:2), ["L" "D"]);
            sweep = findall(testCase.App.Figure, Tag="dlab.sweep.parameter");
            testCase.verifyEqual(string(sweep.Value), "L");
            view.applySetup(struct("map", struct("x", struct("name", "L", "from", 2, "to", 4, "steps", 2), ...
                "y", struct("name", "E", "from", 100, "to", 200, "steps", 2))));
            testCase.verifyError(@() view.runMap(), "dlab:analysis:unused");
        end
    end
end
