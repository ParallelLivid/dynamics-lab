function r = column_engine(m)
%COLUMN_ENGINE Buckling of a slender column under an axial load.
%   r = dlab.sims.column.column_engine(m) with a struct M (SI units):
%     endCondition   "pinned" (K = 1), "fixedfree" (K = 2), "fixedpinned"
%                    (K = 0.699), or "fixedfixed" (K = 0.5)
%     L              length (m)
%     E, yieldStress modulus and yield stress (Pa)
%     A, I, c        area (m²), second moment of area (m⁴), and the
%                    distance from the centroid to the outer fibre (m)
%     P              axial load (N), or
%     loadRatio      the load as a fraction of P_cr (used when present and
%                    finite; it overrides P)
%     e0             initial bow (m): the amplitude of an imperfection in
%                    the shape of the buckling mode
%     analysis       "linear" (the imperfect column, small deflections) or
%                    "elastica" (the perfect column, large deflections)
%     scatter        optional: relative scatter of the Southwell
%                    "measurements" (0 = exact; default 0)
%     progressFcn    optional @(fraction) stop
%
%   1. Euler: P_cr = π² E I / (K L)² for each end condition, with its mode
%      shape; the squash load A·σy; the slenderness K L / r (r = √(I/A))
%      against the limit π √(E/σy) where the two are equal.
%   2. Imperfection: a bow e0·φ(x) in the shape of the mode φ (max 1)
%      grows to δ = e0 / (1 − P/P_cr) (exact for any end condition when
%      the bow is affine to the mode). The largest moment is m·P·δ, with
%      m = 1 for pinned–pinned and fixed–free, 1/2 for fixed–fixed, and
%      EI·max|φ''|/P_cr for fixed–pinned; the largest stress is
%      P/A + m P δ c / I. The load at first yield solves σ = σy (the
%      Perry–Robertson formula): with η = m e0 c A / I and σcr = P_cr/A,
%          σ = [σcr(1+η) + σy − √((σcr(1+η) + σy)² − 4 σy σcr)] / 2.
%      A Southwell plot (Δ/P against Δ, Δ the deflection grown from e0)
%      of "measured" points is a straight line of slope 1/P_cr.
%   3. The elastica (dlab.sims.column.elastica), solved by shooting with
%      ode45: exact for pinned–pinned, and for fixed–free and fixed–fixed
%      as pieces of the same curve of length K L. Not available for
%      fixed–pinned (its end reaction tilts the line of thrust).
%
%   Throws column:InvalidParameter for bad input.
m = validate(m);
r.params = m;
if isfield(r.params, "progressFcn")
    r.params = rmfield(r.params, "progressFcn");
end
euler = dlab.sims.column.eulerModes(m.E * m.I, m.L);
r.endConditions = euler.names;
r.Ks = euler.K;
r.criticalLoads = euler.Pcr;
which = find(euler.names == m.endCondition);
r.K = euler.K(which);
r.effectiveLength = r.K * m.L;
r.Pcr = euler.Pcr(which);
r.radiusOfGyration = sqrt(m.I / m.A);
r.slenderness = r.effectiveLength / r.radiusOfGyration;
r.limitingSlenderness = pi * sqrt(m.E / m.yieldStress);
r.squashLoad = m.A * m.yieldStress;
r.bucklingGoverns = r.Pcr < r.squashLoad;

% Mode shapes (x/L from the base; max 1) and the moment factors m.
xi = euler.x;
r.modeX = xi;
r.modes = euler.modes;
r.momentFactors = euler.momentFactors;
r.momentFactor = r.momentFactors(which);

% The load.
if isfield(m, "loadRatio") && isfinite(m.loadRatio)
    r.P = m.loadRatio * r.Pcr;
else
    r.P = m.P;
end
r.loadRatio = r.P / r.Pcr;
if m.analysis == "elastica"
    if m.endCondition == "fixedpinned"
        error("column:InvalidParameter", ...
            "The elastica is solved for pinned–pinned, fixed–free, and fixed–fixed columns.");
    end
    if r.loadRatio > 10
        error("column:InvalidParameter", "The elastica is solved up to P = 10 P_cr (here %.3g P_cr).", r.loadRatio);
    end
end

% 2. The imperfect column.
eta = r.momentFactor * m.e0 * m.c * m.A / m.I;
r.imperfectionParameter = eta;
r.firstYieldLoad = m.A * perryRobertson(r.Pcr / m.A, m.yieldStress, eta);
r.failureLoad = r.firstYieldLoad;
r.utilization = r.P / r.failureLoad;
lin.available = r.loadRatio < 1;
lin.amplification = NaN;
lin.deflection = NaN;
lin.stress = NaN;
if lin.available
    lin.amplification = 1 / (1 - r.loadRatio);
    lin.deflection = m.e0 * lin.amplification;
    lin.stress = r.P / m.A + r.momentFactor * r.P * lin.deflection * m.c / m.I;
end
lin.height = xi * m.L;
lin.initial = m.e0 * r.modes(:, which);
lin.shape = lin.deflection * r.modes(:, which);
r.linear = lin;

% Load against deflection, and stress against load, below P_cr.
ratios = unique([linspace(0, 0.9, 46), 0.9 + 0.0999 * (1 - logspace(0, -3, 40)) / (1 - 1e-3)])';
r.curves.P = ratios * r.Pcr;
r.curves.linearDeflection = m.e0 ./ (1 - ratios);
r.curves.linearStress = r.curves.P / m.A .* (1 + eta ./ (1 - ratios));

% Southwell: "measured" deflections Δ = δ − e0 at loads up to the smaller
% of 0.9 P_cr and first yield, fitted by a straight line Δ/P = Δ/P_cr + e0/P_cr.
sw.available = m.e0 > 0;
top = min(0.9 * r.Pcr, r.firstYieldLoad);
sw.P = linspace(0.2, 1, 8)' * top;
growth = m.e0 * (sw.P / r.Pcr) ./ (1 - sw.P / r.Pcr);
u = dlab.physics.uniformSequence(7, numel(sw.P))';
sw.delta = growth .* (1 + m.scatter * (2 * u - 1));
[sw.slope, sw.intercept, sw.Pcr, sw.e0, sw.error] = deal(NaN);
if sw.available
    coefficients = polyfit(sw.delta, sw.delta ./ sw.P, 1);
    sw.slope = coefficients(1);
    sw.intercept = coefficients(2);
    sw.Pcr = 1 / sw.slope;
    sw.e0 = sw.intercept / sw.slope;
    sw.error = 100 * (sw.Pcr - r.Pcr) / r.Pcr;
end
r.southwell = sw;

% 3. The elastica: the shape at the load, and the curve past P_cr.
el.available = m.endCondition ~= "fixedpinned";
[el.alpha, el.deflection, el.shortening, el.stress] = deal(NaN);
[el.height, el.lateral] = deal(zeros(0, 1));
el.curveRatio = zeros(0, 1);
el.curveDeflection = zeros(0, 1);
el.curveStress = zeros(0, 1);
el.curveAlpha = zeros(0, 1);
if el.available
    % Each piece of the periodic elastica: arc lengths [s0, s0 + span] in
    % units of K L, and how many pinned bulges fit between the ends.
    switch m.endCondition
        case "pinned"
            [s0, span, bulges] = deal(0, 1, 1);
        case "fixedfree"
            [s0, span, bulges] = deal(0.5, 0.5, 1);
        otherwise
            [s0, span, bulges] = deal(0.5, 2, 2);
    end
    sol = dlab.sims.column.elastica(Ratio=r.loadRatio, Span=s0 + span, Points=401);
    keep = sol.s >= s0 - 1e-12;
    ell = r.effectiveLength;
    el.alpha = sol.alpha;
    el.height = (sol.x(keep) - sol.x(find(keep, 1))) * ell;
    el.lateral = (sol.w(keep) - sol.w(find(keep, 1))) * ell;
    if s0 > 0
        el.lateral = -el.lateral;
    end
    el.crest = sol.deflection * ell;               % the largest offset from the line of thrust
    el.deflection = bulges * el.crest;
    el.shortening = m.L - el.height(end);
    el.stress = r.P / m.A + r.P * el.crest * m.c / m.I;
    % The curve: one end rotation per point, up past the load shown.
    alphas = deg2rad([0:10, 12.5:2.5:170])';      % fine enough for a smooth curve
    if el.alpha > alphas(end)
        alphas = [alphas; linspace(alphas(end), min(el.alpha + deg2rad(2), pi * 0.995), 6)'];
    end
    alphas = unique(alphas);
    n = numel(alphas);
    [el.curveRatio, el.curveDeflection] = deal(zeros(n, 1));
    for k = 1:n
        point = dlab.sims.column.elastica(Alpha=alphas(k), Points=3);
        el.curveRatio(k) = point.ratio;
        el.curveDeflection(k) = bulges * point.deflection * ell;
        if isfield(m, "progressFcn") && ~isempty(m.progressFcn) && m.progressFcn(k / n)
            break
        end
    end
    el.curveAlpha = alphas;
    curveP = el.curveRatio * r.Pcr;
    el.curveStress = curveP / m.A + curveP .* el.curveDeflection / bulges * m.c / m.I;
end
r.elastica = el;

% The column curve: failure stress against slenderness, varying the length
% with e0/L held.
lambda = unique([linspace(1, max(300, 1.3 * r.slenderness), 300)'; r.slenderness]);
r.columnCurve.slenderness = lambda;
r.columnCurve.euler = pi^2 * m.E ./ lambda.^2;
etaCurve = r.momentFactor * (m.e0 / m.L) * lambda / r.K * m.c / r.radiusOfGyration;
r.columnCurve.perry = perryRobertson(r.columnCurve.euler, m.yieldStress, etaCurve);

% The result in the chosen analysis.
if m.analysis == "elastica"
    r.deflection = el.deflection;
    r.maxStress = el.stress;
else
    r.deflection = lin.deflection;
    r.maxStress = lin.stress;
end
r.stressRatio = r.maxStress / m.yieldStress;
end

% ---------------------------------------------------------------- helpers
function m = validate(m)
bad = @(message) error("column:InvalidParameter", message);
if ~isfield(m, "endCondition") || ~ismember(string(m.endCondition), ["pinned" "fixedfree" "fixedpinned" "fixedfixed"])
    bad("The end condition must be pinned, fixedfree, fixedpinned, or fixedfixed.");
end
m.endCondition = string(m.endCondition);
if ~isfield(m, "analysis")
    m.analysis = "linear";
end
m.analysis = string(m.analysis);
if ~ismember(m.analysis, ["linear" "elastica"])
    bad("The analysis must be linear or elastica.");
end
for name = ["L" "E" "yieldStress" "A" "I" "c"]
    if ~isfield(m, name) || ~(isscalar(m.(name)) && isfinite(m.(name)) && m.(name) > 0)
        bad(sprintf("%s must be a positive number.", name));
    end
end
if ~isfield(m, "e0")
    m.e0 = 0;
end
if ~(isscalar(m.e0) && isfinite(m.e0) && m.e0 >= 0)
    bad("The initial bow e0 must be a number >= 0.");
end
if m.e0 > m.L / 10
    bad("The initial bow e0 must be small: at most a tenth of the length.");
end
if ~isfield(m, "loadRatio")
    m.loadRatio = NaN;
end
if isfinite(m.loadRatio)
    if m.loadRatio < 0
        bad("The load ratio P/P_cr must be >= 0.");
    end
else
    if ~isfield(m, "P") || ~(isscalar(m.P) && isfinite(m.P) && m.P >= 0)
        bad("The load P must be a number >= 0.");
    end
end
if ~isfield(m, "scatter")
    m.scatter = 0;
end
if ~(isscalar(m.scatter) && m.scatter >= 0 && m.scatter <= 0.5)
    bad("The scatter must be between 0 and 0.5.");
end
if m.A * m.c^2 < m.I * (1 - 1e-9)
    bad("The section is impossible: I cannot exceed A·c² (no material lies beyond c).");
end
end

function sigma = perryRobertson(sigmaCr, sigmaY, eta)
% The mean stress at first yield of a bowed column (smaller root).
b = sigmaCr .* (1 + eta) + sigmaY;
sigma = (b - sqrt(max(b.^2 - 4 * sigmaY .* sigmaCr, 0))) / 2;
end
