function summary = runTestsInParallel(tasks, options)
%RUNTESTSINPARALLEL Run buildtool test tasks at once, each in its own
%   MATLAB session, and report the totals ("buildtool ptest" runs the five
%   parts of the suite this way).
%
%       dlab.dev.runTestsInParallel(["testcore" "testsimsam"])
%
%   Each session writes test-results/<task>.log and <task>.xml. Returns a
%   table (Task, Tests, Failures, Errors, Skipped, Minutes) and errors if
%   any test failed or any session did not finish.
arguments
    tasks (1,:) string
    options.TimeoutMinutes (1,1) double {mustBePositive} = 60
end
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
results = fullfile(root, "test-results");
if ~isfolder(results)
    mkdir(results);
end
exe = fullfile(matlabroot, "bin", "matlab");
logs = fullfile(results, tasks + ".log");
xmls = fullfile(results, tasks + ".xml");
for k = 1:numel(tasks)
    deleteIfPresent(logs(k));
    deleteIfPresent(xmls(k));
    command = sprintf('"%s" -sd "%s" -logfile "%s" -batch "buildtool %s"', exe, root, logs(k), tasks(k));
    if ispc
        system("start """" /b " + command);
    else
        system(command + " > /dev/null 2>&1 &");
    end
end

started = tic;
done = false(size(tasks));
minutes = nan(size(tasks));
while ~all(done) && toc(started) < 60 * options.TimeoutMinutes
    pause(5);
    for k = find(~done)
        text = readText(logs(k));
        if contains(text, "** Finished " + tasks(k)) || contains(text, "** Failed " + tasks(k)) || ...
                contains(text, "Build failed") || contains(text, "Error using buildtool")
            done(k) = true;
            minutes(k) = toc(started) / 60;
            fprintf("%-16s finished after %.1f min\n", tasks(k), minutes(k));
        end
    end
end

summary = table(tasks(:), zeros(numel(tasks), 1), zeros(numel(tasks), 1), zeros(numel(tasks), 1), ...
    zeros(numel(tasks), 1), minutes(:), VariableNames=["Task" "Tests" "Failures" "Errors" "Skipped" "Minutes"]);
for k = 1:numel(tasks)
    if isfile(xmls(k))
        counts = junitCounts(xmls(k));
        summary{k, ["Tests" "Failures" "Errors" "Skipped"]} = counts;
    else
        summary.Errors(k) = NaN;
    end
end
disp(summary);
fprintf("%d tests in %.1f min: %d failed, %d errors.\n", sum(summary.Tests), max(summary.Minutes), ...
    sum(summary.Failures), sum(summary.Errors, "omitnan"));
if ~all(done) || any(isnan(summary.Errors)) || any(summary.Failures + summary.Errors > 0)
    error("dlab:dev:testsFailed", "Some test parts failed or did not finish; see test-results/*.log.");
end
end

function counts = junitCounts(file)
% Totals over every <testsuite> in a JUnit XML file.
text = readText(file);
counts = zeros(1, 4);
names = ["tests" "failures" "errors" "skipped"];
for j = 1:numel(names)
    values = regexp(text, "<testsuite [^>]*\s" + names(j) + "=""(\d+)""", "tokens");
    counts(j) = sum(cellfun(@(v) str2double(v{1}), values));
end
end

function text = readText(file)
text = "";
if isfile(file)
    try
        text = string(fileread(file));
    catch
        % still being written
    end
end
end

function deleteIfPresent(file)
if isfile(file)
    delete(file);
end
end
