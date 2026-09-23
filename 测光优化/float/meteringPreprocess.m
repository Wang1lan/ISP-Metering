function prep = meteringPreprocess(rgb, weightFile, cfg)
%METERINGPREPROCESS 白光测光第一阶段的浮点参考模型。
% 输入:
%   rgb        H×W×3 非负、有限的 RGB 数值图像，不隐式归一化。
%   weightFile 每行一个 0/1 的 TXT，按 block 从左到右、从上到下排列。
%   cfg        配置结构体:
%     blockSize   默认 16，当前仅支持 16×16 block。
%     yCoeffs     默认 [0.299, 0.587, 0.114]，依次对应 R/G/B。
%     highlightTh 必填，高光阈值，与亮度 Y 使用相同数值域。
%     N1, N2      必填，整数高光像素数阈值，0 <= N1 < N2 <= 256。
%     Rmin        必填，可靠度下限，范围 [0, 1]。
% 输出:
%   prep.Bi / Ri / NhMap  block 亮度均值、可靠度、高光像素数；无效处为 0。
%   prep.validMask        与上述矩阵对齐的逻辑有效性表。
%   prep.RminBlockCnt     有效且 Nh >= N2 的 block 数，不以 Ri == Rmin 判断。
%   prep.validBlockCnt    有效 block 总数。
%   prep.Y                整幅浮点亮度图，包含未进入 block 统计的边缘。
% 除 validMask 外，数值输出均为 double。Y 和 Bi 均不取整。

    validateattributes(rgb, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', 'nonsparse', 'nonempty'}, ...
        mfilename, 'rgb');
    assert(ndims(rgb) == 3 && size(rgb, 3) == 3, ...
        'meteringPreprocess:InvalidRGB', 'rgb 必须是 H×W×3 图像。');
    validateattributes(cfg, {'struct'}, {'scalar'}, mfilename, 'cfg');
    requiredFields = {'highlightTh', 'N1', 'N2', 'Rmin'};
    assert(all(isfield(cfg, requiredFields)), ...
        'meteringPreprocess:MissingConfig', ...
        'cfg 必须包含 highlightTh、N1、N2 和 Rmin。');
    if ~isfield(cfg, 'blockSize')
        cfg.blockSize = 16;
    end
    if ~isfield(cfg, 'yCoeffs')
        cfg.yCoeffs = [0.299, 0.587, 0.114];
    end

    validateattributes(cfg.blockSize, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer'}, mfilename, 'cfg.blockSize');
    assert(cfg.blockSize == 16, 'meteringPreprocess:InvalidBlockSize', ...
        '当前仅支持 16×16 block。');
    validateattributes(cfg.yCoeffs, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', 'vector', 'numel', 3}, ...
        mfilename, 'cfg.yCoeffs');
    validateattributes(cfg.highlightTh, {'numeric'}, ...
        {'real', 'finite', 'nonnegative', 'scalar'}, mfilename, 'cfg.highlightTh');
    validateattributes(cfg.N1, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 0, '<=', 256}, ...
        mfilename, 'cfg.N1');
    validateattributes(cfg.N2, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 0, '<=', 256}, ...
        mfilename, 'cfg.N2');
    assert(cfg.N1 < cfg.N2, 'meteringPreprocess:InvalidThresholds', ...
        '必须满足 N1 < N2。');
    validateattributes(cfg.Rmin, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'cfg.Rmin');

    % 配置也统一为 double，避免整数类型配置参与运算时发生截断。
    cfg.blockSize = double(cfg.blockSize);
    cfg.yCoeffs = double(cfg.yCoeffs);
    cfg.highlightTh = double(cfg.highlightTh);
    cfg.N1 = double(cfg.N1);
    cfg.N2 = double(cfg.N2);
    cfg.Rmin = double(cfg.Rmin);
    blockRows = floor(size(rgb, 1) / cfg.blockSize);
    blockCols = floor(size(rgb, 2) / cfg.blockSize);
    assert(blockRows >= 1 && blockCols >= 1, ...
        'meteringPreprocess:ImageTooSmall', '图像必须至少包含一个完整的 16×16 block。');

    validMask = loadFovBlockMask(weightFile, blockRows, blockCols);
    LUT = buildReliabilityLUT(cfg.N1, cfg.N2, cfg.Rmin, cfg.blockSize);
    Y = rgbToMeteringY(rgb, cfg);
    prep = collectValidBlockStats(Y, validMask, LUT, cfg);
    prep.validMask = validMask;
    prep.Y = Y;
end

function validMask = loadFovBlockMask(weightFile, blockRows, blockCols)
% 每次读取权重，使调试期间对 TXT 的修改立即生效。
    v = readmatrix(weightFile);
    assert(isvector(v) && numel(v) == blockRows * blockCols, ...
        'meteringPreprocess:InvalidWeightSize', ...
        '权重必须为向量，且元素数量等于完整 block 的数量。');
    assert(all(v(:) == 0 | v(:) == 1), ...
        'meteringPreprocess:InvalidWeightValue', '当前权重文件只能包含 0 或 1。');
    validMask = logical(reshape(v, blockCols, blockRows).');
end

function Y = rgbToMeteringY(rgb, cfg)
% 全幅计算，保留原数值域及小数；有效视场不参与亮度转换。
    rgb = double(rgb);
    a = cfg.yCoeffs;
    Y = a(1) * rgb(:, :, 1) + a(2) * rgb(:, :, 2) + a(3) * rgb(:, :, 3);
end

function LUT = buildReliabilityLUT(N1, N2, Rmin, blockSize)
% 最近一次配置对应的 LUT；逐帧相同配置直接复用。
    persistent cachedParams cachedLUT
    params = [N1, N2, Rmin, blockSize];
    if isempty(cachedParams) || ~isequal(params, cachedParams)
        n = 0:blockSize^2;
        LUT = ones(1, blockSize^2 + 1);
        linearMask = n > N1 & n < N2;
        LUT(linearMask) = 1 - (1 - Rmin) * (n(linearMask) - N1) / (N2 - N1);
        LUT(n >= N2) = Rmin;
        cachedParams = params;
        cachedLUT = LUT;
    else
        LUT = cachedLUT;
    end
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

