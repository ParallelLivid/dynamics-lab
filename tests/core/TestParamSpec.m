classdef TestParamSpec < matlab.unittest.TestCase
    %TESTPARAMSPEC Parameter schema: defaults, coercion, validation.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function labelsAndTooltips(testCase)
            spec = dlab.core.ParamSpec("L", Label="Length", Units="m", Default=1, ...
                Min=0, MinInclusive=false, Description="Rod length.");
            testCase.verifyEqual(spec.displayLabel(), "Length (m)");
            testCase.verifyEqual(spec.rangeText(), "(0, ∞) m");
            testCase.verifyEqual(spec.tooltip(), "Rod length." + newline + "Allowed: (0, ∞) m");
            bare = dlab.core.ParamSpec("k");
            testCase.verifyEqual(bare.displayLabel(), "k");
            testCase.verifyEqual(bare.tooltip(), "");
        end

        function fallbackDefaults(testCase)
            testCase.verifyEqual(dlab.core.ParamSpec("a").Default, 0);
            testCase.verifyEqual(dlab.core.ParamSpec("a", Min=2).Default, 2);
            testCase.verifyEqual(dlab.core.ParamSpec("a", Type="logical").Default, false);
            testCase.verifyEqual(dlab.core.ParamSpec("a", Type="choice", Choices=["x" "y"]).Default, "x");
        end

        function invalidSpecsAreRejected(testCase)
            testCase.verifyError(@() dlab.core.ParamSpec("a", Default=5, Max=1), "dlab:spec:badDefault");
            testCase.verifyError(@() dlab.core.ParamSpec("a", Min=0, MinInclusive=false), "dlab:spec:badDefault");
            testCase.verifyError(@() dlab.core.ParamSpec("a", Type="choice"), "dlab:spec:noChoices");
            testCase.verifyError(@() dlab.core.ParamSpec("a", Type="choice", Choices=["x" "y"], ...
                ChoiceLabels="X"), "dlab:spec:choiceLabels");
            testCase.verifyError(@() dlab.core.ParamSpec("a", Min=2, Max=1), "dlab:spec:range");
            testCase.verifyError(@() dlab.core.ParamSpec("not valid"), "MATLAB:validators:mustBeValidVariableName");
        end

        function numericBounds(testCase)
            spec = dlab.core.ParamSpec("a", Default=0.5, Min=0, Max=1, MaxInclusive=false);
            testCase.verifyTrue(accepts(spec, 0));
            testCase.verifyTrue(accepts(spec, 0.999));
            testCase.verifyFalse(accepts(spec, 1));
            testCase.verifyFalse(accepts(spec, -0.1));
            testCase.verifyFalse(accepts(spec, NaN));
            testCase.verifyFalse(accepts(spec, Inf));
            testCase.verifyFalse(accepts(spec, [0 1]));
            testCase.verifyFalse(accepts(spec, "0.5"));
            testCase.verifyFalse(accepts(spec, 1i));
            [~, ~, message] = spec.coerce(2);
            testCase.verifyEqual(message, "must be in [0, 1)");
        end

        function integerType(testCase)
            spec = dlab.core.ParamSpec("n", Type="integer", Default=3, Min=1);
            testCase.verifyTrue(accepts(spec, 4));
            testCase.verifyFalse(accepts(spec, 2.5));
            testCase.verifyClass(spec.coerce(int8(4)), "double");
        end

        function logicalType(testCase)
            spec = dlab.core.ParamSpec("on", Type="logical");
            testCase.verifyEqual(spec.coerce(1), true);
            testCase.verifyEqual(spec.coerce(false), false);
            testCase.verifyFalse(accepts(spec, 2));
            testCase.verifyFalse(accepts(spec, "true"));
        end

        function choiceType(testCase)
            spec = dlab.core.ParamSpec("m", Type="choice", Choices=["point" "drag"]);
            testCase.verifyEqual(spec.coerce('drag'), "drag");   % jsondecode gives char
            testCase.verifyFalse(accepts(spec, "other"));
            testCase.verifyFalse(accepts(spec, 1));
        end

        function validateAllReportsEveryProblem(testCase)
            specs = [dlab.core.ParamSpec("a", Label="Alpha", Min=0)
                     dlab.core.ParamSpec("b", Label="Beta", Type="logical")
                     dlab.core.ParamSpec("c", Label="Gamma")];
            params = struct("a", -1, "b", 7);
            try
                dlab.core.ParamSpec.validateAll(specs, params);
                testCase.verifyFail("Expected an error.");
            catch ME
                testCase.verifyEqual(ME.identifier, 'dlab:invalidParameter');
                testCase.verifySubstring(ME.message, "Alpha must be in");
                testCase.verifySubstring(ME.message, "Beta must be true or false");
                testCase.verifySubstring(ME.message, "Gamma is missing");
            end
            good = dlab.core.ParamSpec.validateAll(specs, struct("a", int32(2), "b", 1, "c", 0));
            testCase.verifyEqual(good, struct("a", 2, "b", true, "c", 0));
        end

        function visibilityAndLookup(testCase)
            specs = [dlab.core.ParamSpec("mode", Type="choice", Choices=["a" "b"], Group="G1")
                     dlab.core.ParamSpec("x", Group="G2", VisibleWhen=@(p) p.mode == "b")
                     dlab.core.ParamSpec("y", Group="G1")];
            params = dlab.core.ParamSpec.defaults(specs);
            x = dlab.core.ParamSpec.find(specs, "x");
            testCase.verifyFalse(x.isVisible(params));
            params.mode = "b";
            testCase.verifyTrue(x.isVisible(params));
            testCase.verifyEqual(dlab.core.ParamSpec.groupsOf(specs), ["G1" "G2"]);
            testCase.verifyError(@() dlab.core.ParamSpec.find(specs, "z"), "dlab:spec:unknown");
        end
    end
end

function tf = accepts(spec, value)
[~, tf] = spec.coerce(value);
end
