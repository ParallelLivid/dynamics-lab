function dv = tsiolkovsky(isp, m0, mf)
%TSIOLKOVSKY Ideal Δv (m/s) of a burn from mass M0 down to MF with
%   specific impulse ISP (s): g₀ Isp ln(m₀ / m_f). Vectors work element-wise.
dv = 9.80665 * isp .* log(m0 ./ mf);
end
