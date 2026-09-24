function [alpha, debug] = getCenterWeight(Lc, Lp, cfg)
%GETCENTERWEIGHT 根据区域亮度进行带死区的五段中心权重映射。
% Lc、Lp 为 0~255 的有限标量；cfg 中须提供 rho1~rho4、alphaMin、
% Wc、alphaMax、LpMin。使用 Lc/max(Lp,LpMin)，不量化区域亮度。
% debug 返回 rho、alphaSegment (1~5，特殊状态为 0)、denFloorApplied
% 和 blackFrame。全黑时 alpha=Wc、rho=NaN，不执行无意义的比值判断。

    validateattributes(Lc, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 255}, mfilename, 'Lc');
    validateattributes(Lp, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 255}, mfilename, 'Lp');
    validateattributes(cfg, {'struct'}, {'scalar'}, mfilename, 'cfg');
    requiredFields = {'rho1', 'rho2', 'rho3', 'rho4', ...
        'alphaMin', 'Wc', 'alphaMax', 'LpMin'};
    assert(all(isfield(cfg, requiredFields)), ...
        'getCenterWeight:MissingConfig', ...
        'cfg 必须包含 rho1~rho4、alphaMin、Wc、alphaMax 和 LpMin。');

    positiveFields = {'rho1', 'rho2', 'rho3', 'rho4', 'LpMin'};
    for k = 1:numel(positiveFields)
        name = positiveFields{k};
        validateattributes(cfg.(name), {'numeric'}, ...
            {'real', 'finite', 'scalar', 'positive'}, mfilename, ['cfg.' name]);
        cfg.(name) = double(cfg.(name));
    end
    weightFields = {'alphaMin', 'Wc', 'alphaMax'};
    for k = 1:numel(weightFields)
        name = weightFields{k};
        validateattributes(cfg.(name), {'numeric'}, ...
            {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, ...
            mfilename, ['cfg.' name]);
        cfg.(name) = double(cfg.(name));
    end
    assert(cfg.rho1 < cfg.rho2 && cfg.rho2 <= 1 && ...
        1 <= cfg.rho3 && cfg.rho3 < cfg.rho4 && cfg.rho2 < cfg.rho3, ...
        'getCenterWeight:InvalidThresholds', ...
        '必须满足 0 < rho1 < rho2 <= 1 <= rho3 < rho4，且 rho2 < rho3。');
    assert(cfg.alphaMin <= cfg.Wc && cfg.Wc <= cfg.alphaMax, ...
        'getCenterWeight:InvalidWeights', ...
        '必须满足 0 <= alphaMin <= Wc <= alphaMax <= 1。');

    Lc = double(Lc);
    Lp = double(Lp);
    debug.rho = NaN;
    debug.alphaSegment = 0;
    debug.denFloorApplied = false;
    debug.blackFrame = (Lc == 0 && Lp == 0);
    if debug.blackFrame
        alpha = cfg.Wc;
        return;
    end

    debug.denFloorApplied = (Lp < cfg.LpMin);
    rho = Lc / max(Lp, cfg.LpMin);
    debug.rho = rho;
    if rho <= cfg.rho1
        alpha = cfg.alphaMin;
        debug.alphaSegment = 1;
    elseif rho < cfg.rho2
        alpha = cfg.alphaMin + (cfg.Wc - cfg.alphaMin) * ...
            (rho - cfg.rho1) / (cfg.rho2 - cfg.rho1);
        debug.alphaSegment = 2;
    elseif rho <= cfg.rho3
        alpha = cfg.Wc;
        debug.alphaSegment = 3;
    elseif rho < cfg.rho4
        alpha = cfg.Wc + (cfg.alphaMax - cfg.Wc) * ...
            (rho - cfg.rho3) / (cfg.rho4 - cfg.rho3);
        debug.alphaSegment = 4;
    else
        alpha = cfg.alphaMax;
        debug.alphaSegment = 5;
    end
end
