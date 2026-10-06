classdef Linearization
    %LINEARIZATION Small-motion analysis of a model near a reference state.
    %   A = ∂f/∂x by central differences, then its eigenvalues: one row per
    %   mode (a complex-conjugate pair counts once) with natural frequency,
    %   damping ratio, period, time constant, and stability.
    %
    %       lin = plugin.linearization(params);      % see dlab.core.Plugin
    %       L = dlab.core.Linearization.analyze(lin);
    %       L.Modes                                    % table

    methods (Static)
        function L = analyze(lin)
            arguments
                lin (1,1) struct
            end
            x0 = lin.X0(:);
            scale = ones(size(x0));
            if isfield(lin, "Scale") && ~isempty(lin.Scale)
                scale = lin.Scale(:);
            end
            A = dlab.physics.jacobian(lin.F, x0, Scale=scale);
            [V, D] = eig(A);
            lambda = diag(D);
            labels = repmat("", numel(lambda), 1);
            perUnit = "s";                            % 1/s, rad/s, and s
            durationUnit = "s";
            if isfield(lin, "TimeUnit") && strlength(string(lin.TimeUnit)) > 0
                perUnit = string(lin.TimeUnit);       % 1/time unit, rad/time unit, time units
                durationUnit = perUnit + "s";
            end
            if isfield(lin, "Classify") && ~isempty(lin.Classify)
                labels = reshape(string(lin.Classify(lambda, V)), [], 1);
            end

            tol = 1e-9 * max(1, max(abs(lambda)));
            keep = imag(lambda) >= -tol;              % one of each conjugate pair
            lambda = lambda(keep);
            labels = labels(keep);
            [~, order] = sort(abs(lambda));
            lambda = lambda(order);
            labels = labels(order);

            n = numel(lambda);
            re = real(lambda);
            im = imag(lambda);
            im(abs(im) <= tol) = 0;
            re(abs(re) <= tol) = 0;                    % round-off, as Stability says (Neutral)
            wn = abs(lambda);
            zeta = nan(n, 1);
            zeta(wn > tol) = -re(wn > tol) ./ wn(wn > tol);
            period = nan(n, 1);
            period(im > 0) = 2 * pi ./ im(im > 0);
            timeConstant = nan(n, 1);
            timeConstant(abs(re) > tol) = 1 ./ abs(re(abs(re) > tol));
            stability = repmat("Neutral", n, 1);
            stability(re < -tol) = "Stable";
            stability(re > tol) = "Unstable";
            text = compose("%.4g", re);
            oscillatory = im > 0;
            text(oscillatory) = compose("%.4g ± %.4gi", re(oscillatory), im(oscillatory));
            unnamed = labels == "";
            labels(unnamed & oscillatory) = "Oscillation";
            labels(unnamed & ~oscillatory) = "Real mode";

            residual = norm(lin.F(x0));
            L = struct( ...
                "A", A, ...
                "Eigenvalues", lambda, ...
                "Residual", residual, ...
                "IsEquilibrium", residual <= 1e-6 * max(1, norm(A * scale)), ...
                "Reference", string(lin.Reference), ...
                "StateNames", string(lin.StateNames), ...
                "TimeUnit", perUnit, ...
                "Modes", table(labels, text, re, im, wn, zeta, period, timeConstant, stability, ...
                    VariableNames=["Mode" "Eigenvalue" "Real" "Imaginary" "NaturalFrequency" ...
                    "DampingRatio" "Period" "TimeConstant" "Stability"]));
            L.Modes.Properties.VariableUnits = ["" "1/" + perUnit, "1/" + perUnit, "rad/" + perUnit, ...
                "rad/" + perUnit, "", durationUnit, durationUnit, ""];
        end
    end
end
