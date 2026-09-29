function prep = meteringPreprocess(rgb, validMask, cfg, luts)
%METERINGPREPROCESS 逐帧计算亮度、完整 block 统计并查询离线可靠度表。
% rgb 为 H×W×3、0~255 有限数值图像；double 小数保持原值。
% validMask 为初始化加载的 logical 完整 block 网格，本函数不读取文件。
% 无效 block 的 Bi/Ri/NhMap 保持 0；Y 包含被完整 block 网格丢弃的边缘。
% RminBlockCnt 仍统计 Nh >= N2，不能按 Ri 是否等于 Rmin 判断。

    validateattributes(rgb, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', '<=', 255, 'nonsparse', 'nonempty'}, ...
        mfilename, 'rgb');
    assert(ndims(rgb) == 3 && size(rgb, 3) == 3, ...
        'meteringPreprocess:InvalidRGB', 'rgb 必须是 H×W×3 图像。');
    validateattributes(cfg, {'struct'}, {'scalar'}, mfilename, 'cfg');
    requiredFields = {'blockSize', 'yCoeffs', 'highlightTh', 'N1', 'N2', 'Rmin'};
    assert(all(isfield(cfg, requiredFields)), ...
        'meteringPreprocess:MissingConfig', '请先调用 loadMeteringLUTs 初始化配置。');
    validateattributes(cfg.blockSize, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'cfg.blockSize');
    validateattributes(cfg.yCoeffs, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', 'vector', 'numel', 3}, ...
        mfilename, 'cfg.yCoeffs');
    validateattributes(cfg.highlightTh, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', 'scalar'}, mfilename, 'cfg.highlightTh');
    B = double(cfg.blockSize);
    assert(isstruct(luts) && isscalar(luts) && ...
        all(isfield(luts, {'R', 'meta'})) && isstruct(luts.meta) && ...
        isscalar(luts.meta) && isfield(luts.meta, 'R') && ...
        isstruct(luts.meta.R) && isscalar(luts.meta.R), ...
        'meteringPreprocess:InvalidLUT', '请先加载 R 表及其元数据。');
    names = {'blockSize', 'N1', 'N2', 'Rmin'};
    for k = 1:numel(names)
        name = names{k};
        assert(isfield(luts.meta.R, name) && ...
            isnumeric(cfg.(name)) && isreal(cfg.(name)) && isscalar(cfg.(name)) && ...
            isfinite(cfg.(name)) && isequal(double(cfg.(name)), luts.meta.R.(name)), ...
            'meteringPreprocess:ConfigLUTMismatch', ...
            'cfg.%s 与已加载 R 表不一致，请重新初始化。', name);
    end
    assert(isa(luts.R, 'double') && isreal(luts.R) && ...
        isequal(size(luts.R), [B * B + 1, 1]), ...
        'meteringPreprocess:InvalidLUT', 'R 表长度须为 blockSize^2+1。');

    cfg.blockSize = B;
    cfg.yCoeffs = double(cfg.yCoeffs);
    cfg.highlightTh = double(cfg.highlightTh);
    cfg.N2 = double(cfg.N2);
    blockRows = floor(size(rgb, 1) / B);
    blockCols = floor(size(rgb, 2) / B);
    assert(blockRows >= 1 && blockCols >= 1, ...
        'meteringPreprocess:ImageTooSmall', ...
        '图像必须至少包含一个完整的 %d×%d block。', B, B);
    assert(islogical(validMask) && ~issparse(validMask) && ...
        isequal(size(validMask), [blockRows, blockCols]), ...
        'meteringPreprocess:InvalidMaskSize', ...
        'validMask 必须为与当前完整 block 网格同尺寸的 logical 矩阵。');
    % 精确图像尺寸也需保持一致，即使变化后完整 block 网格仍相同。
    assert(isfield(luts.meta, 'lambda') && ...
        all(isfield(luts.meta.lambda, {'imageHeight', 'imageWidth', 'Nvalid'})) && ...
        size(rgb, 1) == luts.meta.lambda.imageHeight && ...
        size(rgb, 2) == luts.meta.lambda.imageWidth && ...
        nnz(validMask) == luts.meta.lambda.Nvalid, ...
        'meteringPreprocess:GeometryMismatch', ...
        '图像尺寸或有效 block 数已改变，请重新初始化。');

    Y = rgbToMeteringY(rgb, cfg);
    assert(all(isfinite(Y(:))) && all(Y(:) >= 0 & Y(:) <= 255), ...
        'meteringPreprocess:InvalidBrightnessDomain', ...
        '当前 yCoeffs 产生了 0~255 域外亮度，请调整运行配置。');
    prep = collectValidBlockStats(Y, validMask, luts.R, cfg);
    prep.validMask = validMask;
    prep.Y = Y;
end

function Y = rgbToMeteringY(rgb, cfg)
% 保留原计算顺序和小数，不按有效视场裁剪亮度图。
    rgb = double(rgb);
    a = cfg.yCoeffs;
    Y = a(1) * rgb(:, :, 1) + a(2) * rgb(:, :, 2) + a(3) * rgb(:, :, 3);
end

function prep = collectValidBlockStats(Y, validMask, LUT, cfg)
% 显式 block/像素循环，保留 sumY、Nh，便于后续对照整数流式实现。
    [blockRows, blockCols] = size(validMask);
    B = cfg.blockSize;
    Bi = zeros(blockRows, blockCols);
    Ri = zeros(blockRows, blockCols);
    NhMap = zeros(blockRows, blockCols);
    validBlockCnt = 0;
    RminBlockCnt = 0;

    for br = 1:blockRows
        for bc = 1:blockCols
            if ~validMask(br, bc)
                continue;
            end
            sumY = 0;
            Nh = 0;
            r0 = (br - 1) * B + 1;
            c0 = (bc - 1) * B + 1;
            for dy = 0:B-1
                for dx = 0:B-1
                    y = Y(r0 + dy, c0 + dx);
                    sumY = sumY + y;
                    if y >= cfg.highlightTh
                        Nh = Nh + 1;
                    end
                end
            end
            Bi(br, bc) = sumY / (B * B);
            Ri(br, bc) = LUT(Nh + 1);
            NhMap(br, bc) = Nh;
            validBlockCnt = validBlockCnt + 1;
            if Nh >= cfg.N2
                RminBlockCnt = RminBlockCnt + 1;
            end
        end
    end

    prep.Bi = Bi;
    prep.Ri = Ri;
    prep.NhMap = NhMap;
    prep.RminBlockCnt = RminBlockCnt;
    prep.validBlockCnt = validBlockCnt;
end
