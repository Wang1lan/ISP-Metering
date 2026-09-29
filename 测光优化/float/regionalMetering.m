function [region, debug] = regionalMetering(prep, regionMask, cfg, luts)
%REGIONALMETERING 第二阶段区域测光，直接接收第一阶段 block 统计。
% prep.Bi/Ri/validMask 与 regionMask.center/edge 必须为同尺寸二维矩阵。
% Bi 在 0~255，Ri 在 0~1；区域掩模互斥且并集等于有效视场。
% cfg.sumWMin 为区域有效权重和门限；luts.alpha 为初始化加载的离线表。
% 本函数不读写 TXT，不执行区域几何划分；regionMask 应初始化后复用。
% 输出亮度保留 double，调用者须先检查 region.valid 再使用 region.Mr。

    validateattributes(prep, {'struct'}, {'scalar'}, mfilename, 'prep');
    validateattributes(regionMask, {'struct'}, {'scalar'}, mfilename, 'regionMask');
    validateattributes(cfg, {'struct'}, {'scalar'}, mfilename, 'cfg');
    assert(all(isfield(prep, {'Bi', 'Ri', 'validMask'})), ...
        'regionalMetering:MissingPreprocessFields', ...
        'prep 必须包含 Bi、Ri 和 validMask。');
    assert(all(isfield(regionMask, {'center', 'edge'})), ...
        'regionalMetering:MissingMasks', 'regionMask 必须包含 center 和 edge。');
    assert(isfield(cfg, 'sumWMin'), ...
        'regionalMetering:MissingConfig', 'cfg 必须包含 sumWMin。');
    validateattributes(cfg.sumWMin, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, 'cfg.sumWMin');
    validateattributes(prep.Bi, {'numeric'}, ...
        {'real', 'finite', '2d', 'nonsparse', 'nonempty', '>=', 0, '<=', 255}, ...
        mfilename, 'prep.Bi');
    gridSize = size(prep.Bi);
    validateattributes(prep.Ri, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'size', gridSize, '>=', 0, '<=', 1}, ...
        mfilename, 'prep.Ri');
    validMask = checkMask(prep.validMask, gridSize, 'prep.validMask');
    centerMask = checkMask(regionMask.center, gridSize, 'regionMask.center');
    edgeMask = checkMask(regionMask.edge, gridSize, 'regionMask.edge');
    assert(~any(centerMask(:) & edgeMask(:)) && ...
        isequal(centerMask | edgeMask, validMask), ...
        'regionalMetering:InvalidMaskCoverage', ...
        '中心和边缘掩模必须互不相交，且并集严格等于 prep.validMask。');
    assert(any(centerMask(:)) && any(edgeMask(:)), ...
        'regionalMetering:EmptyRegion', '中心和边缘掩模均须至少包含一个 block。');

    Bi = double(prep.Bi);
    Ri = double(prep.Ri);
    wc = double(centerMask) .* Ri;
    wp = double(edgeMask) .* Ri;
    sumWc = sum(wc(:));
    sumWp = sum(wp(:));
    sumBc = sum(Bi(:) .* wc(:));
    sumBp = sum(Bi(:) .* wp(:));
    centerValid = (sumWc > double(cfg.sumWMin));
    edgeValid = (sumWp > double(cfg.sumWMin));

    region.Lc = NaN;
    region.Lp = NaN;
    region.alpha = NaN;
    region.Mr = NaN;
    region.valid = centerValid || edgeValid;
    region.status = 'noReliableBlocks';
    region.sumWc = sumWc;
    region.sumWp = sumWp;
    region.Lc_q = NaN;
    region.Lp_q = NaN;
    region.alphaAddr = NaN;
    region.blackFrame = false;
    debug.Lc_q = NaN;
    debug.Lp_q = NaN;
    debug.alphaAddr = NaN;
    debug.blackFrame = false;
    % 输入已严格校验；限幅仅消除加权累计舍入导致的端点微小越界，保留小数。
    if centerValid
        region.Lc = min(255, max(0, sumBc / sumWc));
    end
    if edgeValid
        region.Lp = min(255, max(0, sumBp / sumWp));
    end

    if ~centerValid || ~edgeValid
        if centerValid
            region.Mr = region.Lc;
            region.alpha = 1;
            region.status = 'onlyCenterValid';
        elseif edgeValid
            region.Mr = region.Lp;
            region.alpha = 0;
            region.status = 'onlyEdgeValid';
        end
        return;
    end

    % 映射参数仅用于核对，不能通过修改 cfg 改变已加载的表。
    names = {'rho1', 'rho2', 'rho3', 'rho4', 'alphaMin', 'Wc', 'alphaMax', 'LpMin'};
    assert(isstruct(luts) && isscalar(luts) && isfield(luts, 'meta') && ...
        isstruct(luts.meta) && isscalar(luts.meta) && ...
        isfield(luts.meta, 'alpha') && isstruct(luts.meta.alpha) && ...
        isscalar(luts.meta.alpha), ...
        'regionalMetering:InvalidLUT', '请先加载 alpha 表及其元数据。');
    for k = 1:numel(names)
        name = names{k};
        assert(isfield(cfg, name) && isfield(luts.meta.alpha, name) && ...
            isnumeric(cfg.(name)) && isreal(cfg.(name)) && ...
            isscalar(cfg.(name)) && isfinite(cfg.(name)) && ...
            isequal(double(cfg.(name)), luts.meta.alpha.(name)), ...
            'regionalMetering:ConfigLUTMismatch', ...
            'cfg.%s 与已加载 alpha 表不一致，请重新初始化。', name);
    end
    [region.alpha, debug] = getCenterWeight(region.Lc, region.Lp, luts);
    region.Lc_q = debug.Lc_q;
    region.Lp_q = debug.Lp_q;
    region.alphaAddr = debug.alphaAddr;
    region.blackFrame = debug.blackFrame;
    if debug.blackFrame
        region.Mr = 0;
        region.status = 'blackFrame';
    else
        region.Mr = region.alpha * region.Lc + (1 - region.alpha) * region.Lp;
        region.Mr = min(max(region.Mr, min(region.Lc, region.Lp)), ...
            max(region.Lc, region.Lp));
        region.status = 'normal';
    end
end

function mask = checkMask(mask, gridSize, name)
    validateattributes(mask, {'numeric', 'logical'}, ...
        {'real', 'finite', 'nonsparse', 'size', gridSize}, mfilename, name);
    assert(all(mask(:) == 0 | mask(:) == 1), ...
        'regionalMetering:InvalidMaskValue', '%s 必须仅含 0/1。', name);
    mask = logical(mask);
end
