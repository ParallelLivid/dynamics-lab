% Run the Script column's code for real and save what it prints and plots.
addpath('C:\Users\natha\OneDrive\Desktop\Projects\wip\DynamicsLab');
setenv(dlab.core.Paths.EnvironmentVariable, string(tempname));
format compact
out = dlab.run("pendulum", theta0=60, L=2);
txt = evalc('out.Summary(3, 1:3)');
txt = regexprep(txt, '<[^>]*>', '');           % no hyperlinks or bold markup
fid = fopen('summary.txt', 'w', 'n', 'UTF-8'); fprintf(fid, '%s', txt); fclose(fid);
T = dlab.sweep("nonlinear", "A", linspace(0.9, 1.5, 120), Preset="Driven pendulum: period-1");
S = T.Properties.UserData.Sets;
writetable(S(:, ["A" "Value"]), 'sweep.csv');
