function [K, X, poles] = lqr(A, B, Q, R)
%LQR Linear-quadratic regulator gain for continuous-time state feedback.
%   [K, X, poles] = dlab.physics.lqr(A, B, Q, R) returns the gain K that
%   minimises ∫ (xᵀQx + uᵀRu) dt with u = −K x, the Riccati solution X
%   (dlab.physics.care), and the closed-loop poles eig(A − B K).
[X, ok] = dlab.physics.care(A, B, Q, R);
if ~ok
    error("dlab:physics:lqr", "The Riccati solution is not accurate enough for a reliable gain.");
end
K = R \ (B.' * X);
poles = eig(A - B * K);
end
