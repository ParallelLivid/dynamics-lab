classdef RunReport
    %RUNREPORT One self-contained HTML page describing a run, for a lab
    %   write-up: title, date and version, the inputs grouped as the input
    %   panel groups them, the Summary table, every output tab as an
    %   embedded PNG, and optionally the kept runs.
    %
    %       info.Title    = "Projectile Motion";
    %       info.Subtitle = "Preset: Baseball";
    %       info.Version  = dlab.version();
    %       info.Date     = datetime("now");
    %       info.Groups   = dlab.core.RunReport.inputGroups(plugin.parameters(), params);
    %       info.Summary  = dlab.core.RunReport.summaryRows(plugin.summaryTable(result));
    %       info.Images   = struct("Title", "Trajectory", "Container", grid);
    %       info.Runs     = table(...);      % optional: kept runs, any columns
    %       info.Notes    = "";              % optional
    %       dlab.core.RunReport.write("run.html", info);
    %
    %   Images are written with exportgraphics in their current colours;
    %   one that cannot be exported becomes a note in the page instead of
    %   failing the report. The page itself is always light, for printing.

    methods (Static)
        function write(file, info, options)
            %WRITE Write INFO as one HTML file (UTF-8).
            arguments
                file (1,1) string
                info (1,1) struct
                options.Resolution (1,1) double {mustBePositive} = 150
            end
            html = dlab.core.RunReport.render(info, Resolution=options.Resolution);
            [fid, message] = fopen(file, "w", "n", "UTF-8");
            if fid < 0
                error("dlab:report:write", "Could not write %s: %s", file, message);
            end
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, char(html), "char");
            clear closer
        end

        function html = render(info, options)
            %RENDER The page as text (WRITE without the file).
            arguments
                info (1,1) struct
                options.Resolution (1,1) double {mustBePositive} = 150
            end
            esc = @dlab.core.RunReport.escape;
            title = field(info, "Title", "Dynamics Lab run");
            subtitle = field(info, "Subtitle", "");
            appVersion = field(info, "Version", dlab.version());
            date = field(info, "Date", datetime("now"));
            notes = field(info, "Notes", "");

            parts = strings(0, 1);
            parts(end+1) = "<!DOCTYPE html>";
            parts(end+1) = "<html lang=""en"">";
            parts(end+1) = "<head>";
            parts(end+1) = "<meta charset=""utf-8"">";
            parts(end+1) = "<meta name=""viewport"" content=""width=device-width, initial-scale=1"">";
            parts(end+1) = "<title>" + esc(strjoin([title subtitle(subtitle ~= "")], " – ")) + "</title>";
            parts(end+1) = "<style>" + stylesheet() + "</style>";
            parts(end+1) = "</head>";
            parts(end+1) = "<body>";
            parts(end+1) = "<header>";
            parts(end+1) = "<h1>" + esc(title) + "</h1>";
            if subtitle ~= ""
                parts(end+1) = "<p class=""subtitle"">" + esc(subtitle) + "</p>";
            end
            parts(end+1) = "<p class=""meta"">" + esc("Dynamics Lab " + appVersion + " · " + ...
                string(date, "yyyy-MM-dd HH:mm")) + "</p>";
            parts(end+1) = "</header>";
            if notes ~= ""
                parts(end+1) = "<section><h2>Notes</h2><p>" + multiline(notes) + "</p></section>";
            end

            groups = field(info, "Groups", struct("Name", {}, "Rows", {}));
            if ~isempty(groups)
                parts(end+1) = "<section><h2>Inputs</h2>";
                for g = groups(:)'
                    parts(end+1) = "<h3>" + esc(g.Name) + "</h3>"; %#ok<AGROW>
                    parts(end+1) = tableHtml(g.Rows(:, ["Label" "Value" "Units"]), ["Input" "Value" "Units"]); %#ok<AGROW>
                end
                parts(end+1) = "</section>";
            end

            summary = field(info, "Summary", table.empty);
            if ~isempty(summary) && height(summary) > 0
                parts(end+1) = "<section><h2>Summary</h2>";
                parts(end+1) = tableHtml(summary(:, ["Quantity" "Text" "Units"]), ["Quantity" "Value" "Units"]);
                parts(end+1) = "</section>";
            end

            runs = field(info, "Runs", table.empty);
            if ~isempty(runs) && height(runs) > 0
                parts(end+1) = "<section><h2>Kept runs</h2>";
                parts(end+1) = tableHtml(runs, string(runs.Properties.VariableNames));
                parts(end+1) = "</section>";
            end

            images = field(info, "Images", struct("Title", {}, "Container", {}));
            if ~isempty(images)
                parts(end+1) = "<section><h2>Plots</h2>";
                for image = images(:)'
                    parts(end+1) = imageHtml(image, options.Resolution); %#ok<AGROW>
                end
                parts(end+1) = "</section>";
            end
            parts(end+1) = "</body>";
            parts(end+1) = "</html>";
            html = strjoin(parts, newline) + newline;
        end

        function groups = inputGroups(specs, params)
            %INPUTGROUPS The inputs as the input panel shows them: one
            %   entry per group (Name, Rows = table Label, Value, Units),
            %   leaving out inputs hidden by VisibleWhen and groups with
            %   nothing visible. Missing values fall back to the defaults.
            arguments
                specs (:,1) dlab.core.ParamSpec
                params (1,1) struct
            end
            for spec = specs'
                if ~isfield(params, spec.Name)
                    params.(spec.Name) = spec.Default;
                end
            end
            groups = struct("Name", {}, "Rows", {});
            if isempty(specs)
                return
            end
            for name = dlab.core.ParamSpec.groupsOf(specs)
                members = specs([specs.Group] == name);
                labels = strings(0, 1);
                values = strings(0, 1);
                units = strings(0, 1);
                for spec = members'
                    if ~isShown(spec, params)
                        continue
                    end
                    [text, unit] = dlab.core.RunReport.valueText(spec, params.(spec.Name));
                    labels(end+1, 1) = spec.Label; %#ok<AGROW>
                    values(end+1, 1) = text; %#ok<AGROW>
                    units(end+1, 1) = unit; %#ok<AGROW>
                end
                if ~isempty(labels)
                    groups(end+1) = struct("Name", name, ...
                        "Rows", table(labels, values, units, VariableNames=["Label" "Value" "Units"])); %#ok<AGROW>
                end
            end
        end

        function [text, units] = valueText(spec, value)
            %VALUETEXT How one input reads in the report, and its units
            %   ("" where the text already says them or there are none).
            units = "";
            switch spec.Type
                case {"double" "integer"}
                    text = string(sprintf(spec.DisplayFormat, value));
                    units = spec.Units;
                case "logical"
                    text = "No";
                    if value
                        text = "Yes";
                    end
                case "choice"
                    label = spec.ChoiceLabels(spec.Choices == string(value));
                    text = string(value);
                    if ~isempty(label)
                        text = label(1);
                    end
                case "schedule"
                    s = dlab.core.Schedule.normalize(value);
                    if s.shape == "points"
                        unitText = "";
                        if spec.Units ~= ""
                            unitText = " " + spec.Units;
                        end
                        text = "points (t s, value" + unitText + "): " + dlab.core.Schedule.formatPoints(s.points);
                    else
                        text = dlab.core.Schedule.describe(s, spec.Units);
                    end
                case "table"
                    text = tableText(spec, value);
                otherwise
                    text = string(value);
            end
        end

        function S = summaryRows(T)
            %SUMMARYROWS A plugin's summaryTable as the Summary tab shows
            %   it: table Quantity, Text, Units (strings).
            if isempty(T) || height(T) == 0
                S = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
                    VariableNames=["Quantity" "Text" "Units"]);
                return
            end
            units = strings(height(T), 1);
            if ismember("Units", string(T.Properties.VariableNames))
                units = string(T.Units);
                units(ismissing(units)) = "";
            end
            S = table(string(T.Quantity), dlab.core.RunReport.summaryText(T), units, ...
                VariableNames=["Quantity" "Text" "Units"]);
        end

        function text = summaryText(T)
            %SUMMARYTEXT The Summary's text for each row: Display when
            %   given, else Value through Format (or "%.6g"), or the
            %   value's own text (older plugins return string values).
            n = height(T);
            text = strings(n, 1);
            names = string(T.Properties.VariableNames);
            for k = 1:n
                if ismember("Display", names) && ~ismissing(string(T.Display(k))) && string(T.Display(k)) ~= ""
                    text(k) = string(T.Display(k));
                    continue
                end
                value = T.Value(k);
                if iscell(value)
                    value = value{1};
                end
                if isnumeric(value) || islogical(value)
                    format = "%.6g";
                    if ismember("Format", names) && ~ismissing(string(T.Format(k))) && string(T.Format(k)) ~= ""
                        format = string(T.Format(k));
                    end
                    text(k) = string(sprintf(format, value));
                else
                    text(k) = string(value);
                end
            end
        end

        function text = escape(text)
            %ESCAPE Text safe inside HTML elements and quoted attributes.
            text = string(text);
            text = replace(text, "&", "&amp;");
            text = replace(text, "<", "&lt;");
            text = replace(text, ">", "&gt;");
            text = replace(text, """", "&quot;");
            text = replace(text, "'", "&#39;");
        end

        function uri = pngDataUri(container, resolution)
            %PNGDATAURI CONTAINER's graphics as a data:image/png URI. The
            %   PNG goes through a temporary file that is always deleted.
            arguments
                container (1,1)
                resolution (1,1) double {mustBePositive} = 150
            end
            file = string(tempname) + ".png";
            remover = onCleanup(@() deleteIfPresent(file));
            % Buttons beside a plot are left out on purpose: say nothing.
            quiet = warning("off", "MATLAB:print:ExportappForUIFigureWithUIControl");
            restore = onCleanup(@() warning(quiet));
            exportgraphics(container, file, Resolution=resolution, BackgroundColor="current");
            fid = fopen(file, "r");
            if fid < 0
                error("dlab:report:image", "The exported image could not be read back.");
            end
            bytes = fread(fid, Inf, "*uint8");
            fclose(fid);
            uri = "data:image/png;base64," + string(matlab.net.base64encode(bytes'));
            clear remover restore
        end
    end
end

function value = field(s, name, default)
% S.(NAME), or DEFAULT when it is missing or empty.
value = default;
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
    if isstring(default) || ischar(value)
        value = string(value);
    end
end
end

function tf = isShown(spec, params)
% As ParamPanel decides it; a rule that cannot be evaluated shows the input.
try
    tf = spec.isVisible(params);
catch
    tf = true;
end
end

function text = tableText(spec, value)
% One line per row: "1: Dry mass 4 t, Isp 300 s, Type solid".
if ~istable(value) || height(value) == 0
    text = "(no rows)";
    return
end
columns = spec.Columns;
lines = strings(height(value), 1);
for r = 1:height(value)
    cells = strings(1, numel(columns));
    for c = 1:min(numel(columns), width(value))
        x = value{r, c};
        if islogical(x)
            v = "no";
            if x
                v = "yes";
            end
        elseif isnumeric(x)
            v = string(sprintf("%.6g", x));
        else
            v = string(x);
        end
        if columns(c).Units ~= ""
            v = v + " " + columns(c).Units;
        end
        cells(c) = columns(c).Label + " " + v;
    end
    lines(r) = r + ": " + strjoin(cells, ", ");
end
text = strjoin(lines, newline);
end

function html = tableHtml(T, headers)
% Any table as an HTML table; every cell is text, escaped, with newlines
% kept as line breaks.
esc = @dlab.core.RunReport.escape;
parts = "<table><thead><tr>" + strjoin("<th>" + esc(headers(:)') + "</th>", "") + "</tr></thead><tbody>";
for r = 1:height(T)
    cells = strings(1, width(T));
    for c = 1:width(T)
        cells(c) = "<td>" + multiline(cellText(T{r, c})) + "</td>";
    end
    parts = parts + "<tr>" + strjoin(cells, "") + "</tr>";
end
html = parts + "</tbody></table>";
end

function text = cellText(x)
if iscell(x)
    if isempty(x)
        x = "";
    else
        x = x{1};
    end
end
if isnumeric(x) && isscalar(x)
    text = string(sprintf("%.6g", x));
elseif islogical(x) && isscalar(x)
    text = "No";
    if x
        text = "Yes";
    end
elseif isempty(x)
    text = "";
else
    text = strjoin(string(x(:)'), " ");
end
if ismissing(text)
    text = "";
end
end

function html = multiline(text)
html = replace(dlab.core.RunReport.escape(text), [sprintf("\r\n") newline], "<br>");
end

function html = imageHtml(image, resolution)
% A figure with the embedded PNG, or a note when the export failed.
esc = @dlab.core.RunReport.escape;
title = string(image.Title);
try
    container = image.Container;
    if iscell(container)
        container = container{1};
    end
    if isempty(container) || ~isgraphics(container)
        error("dlab:report:image", "it is not shown.");
    end
    uri = dlab.core.RunReport.pngDataUri(container, resolution);
    html = "<figure><img src=""" + uri + """ alt=""" + esc(title) + """>" + ...
        "<figcaption>" + esc(title) + "</figcaption></figure>";
catch ME
    html = "<p class=""note"">" + esc("Could not include """ + title + """: " + ME.message) + "</p>";
end
end

function deleteIfPresent(file)
if isfile(file)
    delete(file);
end
end

function css = stylesheet()
% Plain and printable; light whatever the app theme.
css = strjoin([
    ":root { color-scheme: light; }"
    "body { margin: 2rem auto; max-width: 960px; padding: 0 16px; background: #ffffff; color: #1d1d1f;"
    "  font: 15px/1.5 system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }"
    "h1 { margin: 0 0 0.2rem; font-size: 1.7rem; }"
    "h2 { margin: 2rem 0 0.6rem; font-size: 1.25rem; border-bottom: 1px solid #d0d0d7; padding-bottom: 0.2rem; }"
    "h3 { margin: 1.2rem 0 0.4rem; font-size: 1rem; color: #4a4a55; text-transform: uppercase; letter-spacing: 0.04em; }"
    ".subtitle { margin: 0; font-size: 1.1rem; color: #33333b; }"
    ".meta { margin: 0.2rem 0 0; color: #6b6b76; font-size: 0.9rem; }"
    ".note { color: #8a4b00; font-style: italic; }"
    "table { border-collapse: collapse; width: 100%; margin: 0.3rem 0 0.8rem; font-variant-numeric: tabular-nums; }"
    "th, td { border: 1px solid #d0d0d7; padding: 0.3rem 0.6rem; text-align: left; vertical-align: top; }"
    "th { background: #f2f2f5; font-weight: 600; }"
    "figure { margin: 1rem 0 1.6rem; break-inside: avoid; page-break-inside: avoid; }"
    "img { max-width: 100%; height: auto; display: block; border: 1px solid #d0d0d7; }"
    "figcaption { margin-top: 0.3rem; color: #4a4a55; font-size: 0.9rem; }"
    "@media print { body { margin: 0; max-width: none; } h2 { break-after: avoid; } table { break-inside: auto; } }"
    ], newline);
end
