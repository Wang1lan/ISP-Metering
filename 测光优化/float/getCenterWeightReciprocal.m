function [alpha, debug] = getCenterWeightReciprocal(Lc, Lp, luts)
%GETCENTERWEIGHTRECIPROCAL 量化区域亮度，以公共倒数表及五段映射计算 alpha。
% Lc/Lp 为 [0,255] double 标量；参数与斜率已初始化于 meta.alpha。
% alphaAddr 不适用于本模式；reciprocalAddr 为公共倒数表的零基地址。

    p = luts.meta.alpha;
    debug.Lc_q = min(255, max(0, floor(double(Lc) + 0.5)));
    debug.Lp_q = min(255, max(0, floor(double(Lp) + 0.5)));
    debug.alphaAddr = NaN;
    debug.blackFrame = (Lc == 0 && Lp == 0);
    debug.rhoApprox = NaN;
    debug.alphaMethod = 'reciprocal_lut';
    debug.reciprocalAddr = NaN;
    debug.alphaSegment = 0;
    if debug.Lc_q == 0 && debug.Lp_q == 0
        alpha = p.Wc;
        return;
    end

    [rho, divisionDebug] = divideByReciprocalLUT( ...
        debug.Lc_q, max(debug.Lp_q, p.LpMin), luts);
    debug.rhoApprox = rho;
    debug.reciprocalAddr = divisionDebug.address;
    if rho <= p.rho1
        alpha = p.alphaMin;
        debug.alphaSegment = 1;
    elseif rho < p.rho2
        alpha = p.alphaMin + p.k1 * (rho - p.rho1);
        debug.alphaSegment = 2;
    elseif rho <= p.rho3
        alpha = p.Wc;
        debug.alphaSegment = 3;
    elseif rho < p.rho4
        alpha = p.Wc + p.k2 * (rho - p.rho3);
        debug.alphaSegment = 4;
    else
        alpha = p.alphaMax;
        debug.alphaSegment = 5;
    end
    alpha = min(p.alphaMax, max(p.alphaMin, alpha));
end
