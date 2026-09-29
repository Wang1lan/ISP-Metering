function [alpha, debug] = getCenterWeight(Lc, Lp, luts)
%GETCENTERWEIGHT 量化区域亮度地址并查询离线二维中心权重表。
% Lc/Lp 为 0~255 的有限标量；仅地址取整，区域亮度保留原 double。
% alphaAddr=256*Lp_q+Lc_q；blackFrame 按原始亮度精确为零判断。

    validateattributes(Lc, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 255}, mfilename, 'Lc');
    validateattributes(Lp, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 255}, mfilename, 'Lp');
    assert(isstruct(luts) && isscalar(luts) && isfield(luts, 'alpha') && ...
        isa(luts.alpha, 'double') && isreal(luts.alpha) && ...
        isequal(size(luts.alpha), [65536, 1]), ...
        'getCenterWeight:InvalidLUT', '请初始化加载完整的 65536 项浮点 alpha 表。');

    Lc = double(Lc);
    Lp = double(Lp);
    debug.Lc_q = min(255, max(0, floor(Lc + 0.5)));
    debug.Lp_q = min(255, max(0, floor(Lp + 0.5)));
    debug.alphaAddr = debug.Lp_q * 256 + debug.Lc_q;
    debug.blackFrame = (Lc == 0 && Lp == 0);
    alpha = luts.alpha(debug.alphaAddr + 1);
    assert(isfinite(alpha) && alpha >= 0 && alpha <= 1, ...
        'getCenterWeight:InvalidCoefficient', '查得的 alpha 必须有限且在 [0,1]。');
end
