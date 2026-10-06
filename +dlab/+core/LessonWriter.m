classdef LessonWriter
    %LESSONWRITER Build lessons from the app: the current inputs become a
    %   step's setup, and a key result with a tolerance becomes its check
    %   ("Save as lesson step…"). Steps collect into a lesson file in the
    %   user's lessons folder, which the Home screen lists.
    %
    %       step = dlab.core.LessonWriter.makeStep(plugin, params, "Defaults", ...
    %           Title="Twice as long", Text="Double the length.", Metric="Period", ...
    %           Value=2.84, Units="s", Tolerance=5);
    %       L = dlab.core.LessonWriter.append(file, "pendulum", "My lesson", step);

    methods (Static)
        function step = makeStep(plugin, params, preset, options)
            %MAKESTEP A lesson step whose setup recreates PARAMS: PRESET
            %   (a built-in preset name, or anything else for the defaults)
            %   plus the inputs that differ from it. With a Metric, the step
            %   checks that result is within Tolerance percent of Value.
            arguments
                plugin (1,1) dlab.core.Plugin
                params (1,1) struct
                preset (1,1) string = "Defaults"
                options.Title (1,1) string = "Step"
                options.Text (1,1) string = ""
                options.Tab (1,1) string = ""
                options.Metric (1,1) string = ""
                options.Value (1,1) double = NaN
                options.Units (1,1) string = ""
                options.Tolerance (1,1) double {mustBePositive} = 5
            end
            if ismember(preset, string({plugin.presets().Name}))
                base = plugin.presetParams(preset);
            else
                preset = "Defaults";
                base = plugin.defaultParams();
            end
            json = plugin.paramsToJson(params);
            baseJson = plugin.paramsToJson(base);
            changed = struct();
            for name = string(fieldnames(json))'
                if ~isfield(baseJson, name) || ~isequal(json.(name), baseJson.(name))
                    changed.(name) = json.(name);
                end
            end
            setup = struct("preset", preset);
            if ~isempty(fieldnames(changed))
                setup.params = changed;
            end
            if options.Tab ~= ""
                setup.tab = options.Tab;
            end
            step = struct("title", options.Title, "text", options.Text, "setup", setup);
            if options.Metric ~= ""
                if ~isfinite(options.Value)
                    error("dlab:lesson:value", "%s has no value to check against; run first.", options.Metric);
                end
                margin = options.Tolerance / 100 * abs(options.Value);
                if margin == 0
                    margin = options.Tolerance / 100;      % a target of zero: an absolute band
                end
                unitText = "";
                if options.Units ~= ""
                    unitText = " " + options.Units;
                end
                step.check = struct("kind", "metric", "quantity", options.Metric, ...
                    "min", options.Value - margin, "max", options.Value + margin, ...
                    "success", sprintf("%s is %.4g%s.", options.Metric, options.Value, unitText));
                step.solution = struct("run", true);
            end
        end

        function L = append(file, simulator, title, step)
            %APPEND Add STEP to the lesson in FILE, creating the file (for
            %   SIMULATOR, titled TITLE) if it does not exist. Returns the
            %   lesson as dlab.core.Lesson.read gives it.
            arguments
                file (1,1) string
                simulator (1,1) string
                title (1,1) string
                step (1,1) struct
            end
            if isfile(file)
                raw = jsondecode(fileread(file, Encoding="UTF-8"));
                if string(raw.simulator) ~= simulator
                    error("dlab:lesson:simulator", "That lesson is for the ""%s"" simulator.", raw.simulator);
                end
                steps = raw.steps;
                if isstruct(steps)
                    steps = num2cell(steps);
                end
                raw.steps = [reshape(steps, 1, []), {step}];
            else
                [~, id] = fileparts(file);
                raw = struct("format", dlab.core.Lesson.Format, "formatVersion", dlab.core.Lesson.FormatVersion, ...
                    "id", string(id), "title", title, "simulator", simulator, ...
                    "summary", "", "order", 100, "steps", {{step}});
            end
            folder = fileparts(file);
            if folder ~= "" && ~isfolder(folder)
                mkdir(folder);
            end
            fid = fopen(file, "w", "n", "UTF-8");
            if fid < 0
                error("dlab:lesson:write", "Cannot write the lesson file ""%s"".", file);
            end
            closer = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(raw, PrettyPrint=true), "char");
            clear closer
            L = dlab.core.Lesson.read(file);
        end

        function file = fileFor(title)
            %FILEFOR The user-folder lesson file for a lesson titled TITLE.
            slug = lower(regexprep(strtrim(title), "[^A-Za-z0-9]+", "-"));
            slug = regexprep(slug, "^-+|-+$", "");
            if slug == ""
                slug = "my-lesson";
            end
            file = fullfile(dlab.core.Paths.lessons(), "my-" + slug + ".json");
        end

        function list = userLessons(simulator)
            %USERLESSONS The user's own lessons for SIMULATOR (Title, File),
            %   which new steps can be added to.
            list = struct("Title", {}, "File", {});
            folder = dlab.core.Paths.lessons();
            for f = reshape(dir(fullfile(folder, "*.json")), 1, [])
                file = string(fullfile(f.folder, f.name));
                try
                    L = dlab.core.Lesson.read(file);
                catch
                    continue
                end
                if L.simulator == simulator
                    list(end+1) = struct("Title", L.title, "File", file); %#ok<AGROW>
                end
            end
        end
    end
end
