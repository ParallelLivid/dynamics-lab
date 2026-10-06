classdef ToyTablePlugin < dlab.core.StaticPlugin
    %TOYTABLEPLUGIN Static plugin with a "table" input: a list of loads
    %   whose active weights are summed. Tests only; not registered.

    properties (Constant)
        Id = "toytable"
        Title = "Toy Table"
        Category = "Test"
        Summary = "Sums a table of loads; used to test table inputs."
        SchemaVersion = 1
    end

    properties (SetAccess = private)
        Axes
        Bars
    end

    methods
        function specs = parameters(~)
            P = @dlab.core.ParamSpec;
            C = @dlab.core.TableColumn;
            specs = [
                P("loads", Label="Loads", Type="table", Group="Loads", MinRows=1, MaxRows=5, ...
                    Description="Each row is one load.", Columns=[
                        C("x", Label="Position", Units="m", Min=0, Default=0)
                        C("w", Label="Weight", Units="N", Default=10)
                        C("kind", Label="Kind", Type="choice", Choices=["point" "spread"])
                        C("active", Label="On", Type="logical", Default=true)
                        C("count", Label="Count", Type="integer", Min=1, Default=1)
                    ], Default=table([0; 2], [10; 5], ["point"; "spread"], [true; true], [1; 2], ...
                        VariableNames=["x" "w" "kind" "active" "count"]))
                P("scale", Label="Scale", Default=1, Min=0, Group="Loads")
            ];
        end

        function list = presets(~)
            list = struct("Name", "Three loads", "Values", struct("loads", ...
                struct("x", {1, 2, 3}, "w", {1, 2, 3}, "kind", {'point', 'point', 'spread'}, ...
                    "active", {true, false, true}, "count", {1, 1, 1})));
        end

        function result = solve(~, p)
            on = p.loads.active;
            total = p.scale * sum(p.loads.w(on) .* p.loads.count(on));
            result = struct("total", total, "x", p.loads.x, "w", p.loads.w);
        end

        function titles = outputTabs(~, ~)
            titles = "Total";
        end

        function buildOutputs(obj, containers, theme)
            obj.Theme = theme;
            obj.Axes = dlab.ui.axesIn(containers{"Total"}, theme, Title="Loads", XLabel="x (m)", YLabel="w (N)");
            obj.Bars = line(obj.Axes, NaN, NaN, LineStyle="none", Marker="o", Color=theme.series(1));
        end

        function showResult(obj, result, ~)
            set(obj.Bars, XData=result.x, YData=result.w);
        end

        function clearResult(obj)
            set(obj.Bars, XData=NaN, YData=NaN);
        end

        function T = exportTable(~, result)
            T = table(result.x, result.w, VariableNames=["x" "w"]);
            T.Properties.VariableUnits = ["m" "N"];
        end

        function T = summaryTable(~, result)
            T = table("Total weight", result.total, "N", VariableNames=["Quantity" "Value" "Units"]);
        end
    end
end
