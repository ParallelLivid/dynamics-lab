function info = simulators(simulatorId)
%SIMULATORS The simulators available to dlab.run and the app.
%   T = dlab.simulators()            one row per simulator: Id, Title,
%                                    Category, Kind, Summary
%   T = dlab.simulators("pendulum")  that simulator's inputs: Name, Label,
%                                    Units, Type, Default, Range, Group
arguments
    simulatorId (1,1) string = ""
end
factories = dlab.sims.registry();
if simulatorId == ""
    rows = cell(numel(factories), 5);
    for k = 1:numel(factories)
        plugin = factories{k}();
        rows(k, :) = {plugin.Id, plugin.Title, plugin.Category, plugin.kind(), plugin.Summary};
        delete(plugin);
    end
    info = cell2table(rows, VariableNames=["Id" "Title" "Category" "Kind" "Summary"]);
    info = convertvars(info, 1:5, "string");
    return
end
plugin = dlab.core.Headless.plugin(simulatorId, factories);
cleanup = onCleanup(@() delete(plugin));
specs = plugin.parameters();
defaults = strings(numel(specs), 1);
ranges = strings(numel(specs), 1);
for k = 1:numel(specs)
    value = specs(k).Default;
    if specs(k).Type == "choice"
        defaults(k) = """" + value + """";
        ranges(k) = strjoin("""" + specs(k).Choices + """", " | ");
    elseif specs(k).Type == "table"
        defaults(k) = sprintf("table, %d rows", height(value));
        columns = specs(k).Columns;
        ranges(k) = specs(k).rowsText() + " of: " + strjoin(arrayfun(@(c) c.header(), columns'), ", ");
    elseif specs(k).Type == "schedule"
        defaults(k) = dlab.core.Schedule.describe(value, specs(k).Units);
        ranges(k) = specs(k).rangeText();
    else
        defaults(k) = string(mat2str(value));
        ranges(k) = specs(k).rangeText();
    end
end
info = table([specs.Name]', [specs.Label]', [specs.Units]', [specs.Type]', defaults, ranges, ...
    [specs.Group]', VariableNames=["Name" "Label" "Units" "Type" "Default" "Range" "Group"]);
end
