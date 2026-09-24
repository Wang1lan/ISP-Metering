function [peak, debug] = peakMetering(prep, cfg)
%PEAKMETERING 第三阶段峰值测光，复用第一阶段的 block 亮度和有效掩模。
% prep.Bi 为 0~255 的二维数值矩阵，prep.validMask 为同尺寸的 0/1 掩模。
% 可选 prep.validBlockCnt 必须与掩模有效数量一致；cfg.peakRatio 在 (0,1]。
% 分支内先转 double，再以 floor(Bi+0.5) 量化；不修改 prep 或第二阶段口径。
% 256 档直方图逆向选取恰好 K 个 block，以 sum(b^2)/sum(b) 计算 Mp。
% 输出亮度保留 double；调用者须检查 peak.valid 后再用于后续融合。

    assert(isstruct(prep) && isscalar(prep), ...
        'peakMetering:InvalidPreprocess', 'prep 必须为标量结构体。');
    assert(isstruct(cfg) && isscalar(cfg), ...
        'peakMetering:InvalidConfig', 'cfg 必须为标量结构体。');
    assert(all(isfield(prep, {'Bi', 'validMask'})), ...
        'peakMetering:MissingPreprocessFields', 'prep 必须包含 Bi 和 validMask。');
    assert(isfield(cfg, 'peakRatio'), ...
        'peakMetering:MissingConfig', 'cfg 必须包含 peakRatio。');
    assert(isnumeric(prep.Bi) && isreal(prep.Bi) && ...
        ismatrix(prep.Bi) && ~isempty(prep.Bi) && ~issparse(prep.Bi), ...
        'peakMetering:InvalidBrightness', ...
        'prep.Bi 必须为非空、非稀疏的二维实数数值矩阵。');
    Bi = double(prep.Bi);
    assert(all(isfinite(Bi(:))) && all(Bi(:) >= 0 & Bi(:) <= 255), ...
        'peakMetering:InvalidBrightness', 'prep.Bi 全矩阵必须有限且在 0~255。');
    mask = prep.validMask;
    assert((isnumeric(mask) || islogical(mask)) && isreal(mask) && ...
        isequal(size(mask), size(Bi)), ...
        'peakMetering:InvalidMask', 'prep.validMask 必须为与 Bi 同尺寸的实数或逻辑矩阵。');
    assert(all(isfinite(mask(:))) && all(mask(:) == 0 | mask(:) == 1), ...
        'peakMetering:InvalidMask', 'prep.validMask 必须只含有限的 0 或 1。');
    validMask = logical(mask);
    Nvalid = nnz(validMask);
    if isfield(prep, 'validBlockCnt')
        count = prep.validBlockCnt;
        assert(isnumeric(count) && isreal(count) && isscalar(count) && ...
            isfinite(count) && count >= 0 && double(count) == floor(double(count)), ...
            'peakMetering:InvalidBlockCount', 'prep.validBlockCnt 必须为非负整数标量。');
        assert(double(count) == Nvalid, ...
            'peakMetering:BlockCountMismatch', ...
            'prep.validBlockCnt 必须等于 nnz(prep.validMask)。');
    end
    ratio = cfg.peakRatio;
    assert(isnumeric(ratio) && isreal(ratio) && isscalar(ratio) && ...
        isfinite(ratio) && ratio > 0 && ratio <= 1, ...
        'peakMetering:InvalidPeakRatio', 'cfg.peakRatio 必须为 (0,1] 内的有限实数标量。');
    ratio = double(ratio);

    H = zeros(256, 1);
    selectedH = zeros(256, 1);
    peak.Mp = NaN;
    peak.valid = false;
    peak.status = 'noValidBlocks';
    peak.validBlockCnt = Nvalid;
    peak.targetBlockCnt = 0;
    peak.selectedBlockCnt = 0;
    peak.thresholdBin = NaN;
    peak.sumB = 0;
    peak.sumB2 = 0;
    debug.histogram = H;
    debug.selectedHistogram = selectedH;
    debug.peakRatio = ratio;
    debug.actualRatio = NaN;
    debug.unweightedMean = NaN;
    debug.quantization = 'roundHalfUpToInteger';
    if Nvalid == 0
        return;
    end

    K = min(Nvalid, max(1, ceil(ratio * Nvalid)));
    bins = floor(Bi(validMask) + 0.5);
    for k = 1:numel(bins)
        idx = bins(k) + 1;
        H(idx) = H(idx) + 1;
    end

    selectedCount = 0;
    S1 = 0;
    S2 = 0;
    thresholdBin = NaN;
    for b = 255:-1:0
        take = min(H(b + 1), K - selectedCount);
        if take == 0
            continue;
        end
        selectedH(b + 1) = take;
        selectedCount = selectedCount + take;
        S1 = S1 + take * b;
        S2 = S2 + take * b * b;
        thresholdBin = b;
        if selectedCount == K
            break;
        end
    end

    peak.valid = true;
    peak.targetBlockCnt = K;
    peak.selectedBlockCnt = selectedCount;
    peak.thresholdBin = thresholdBin;
    peak.sumB = S1;
    peak.sumB2 = S2;
    if S1 == 0
        peak.Mp = 0;
        peak.status = 'zeroPeakBrightness';
    else
        peak.Mp = S2 / S1;
        peak.status = 'normal';
    end
    debug.histogram = H;
    debug.selectedHistogram = selectedH;
    debug.actualRatio = selectedCount / Nvalid;
    debug.unweightedMean = S1 / K;
end
