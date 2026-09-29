function info = generateReliabilityLUT()
%GENERATERELIABILITYLUT 离线生成高亮像素数 Nh 到可靠度 R 的查找表。
% 修改下方参数后直接无参运行；所有路径以本文件位置为基准。

    % USER PARAMETERS BEGIN
    blockSize = 16;
    thresholdMode = 'count';       % 'count' 为像素数，'ratio' 为面积占比
    N1 = 10;                      % count 模式使用，不随 B 自动缩放
    N2 = 50;
    highRatio1 = 10 / 256;         % ratio 模式使用
    highRatio2 = 50 / 256;
    Rmin = 0.3;
    outputMode = 'both';          % 'float'、'fixed' 或 'both'
    fracBits = 12;                % 1~30，1.0 编码为 2^fracBits
    outputDir = fullfile(fileparts(mfilename('fullpath')), '..');
    % USER PARAMETERS END

    validateattributes(blockSize, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'blockSize');
    validateattributes(Rmin, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'Rmin');
    validateattributes(fracBits, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 1, '<=', 30}, mfilename, 'fracBits');
    assert((ischar(thresholdMode) && isrow(thresholdMode)) || ...
        (isstring(thresholdMode) && isscalar(thresholdMode)), ...
        'generateReliabilityLUT:InvalidThresholdMode', 'thresholdMode 必须为 count 或 ratio。');
    thresholdMode = char(thresholdMode);
    blockSize = double(blockSize);
    Rmin = double(Rmin);
    blockPixels = blockSize ^ 2;
    assert(isfinite(blockPixels) && blockPixels < flintmax, ...
        'generateReliabilityLUT:InvalidBlockSize', 'blockSize^2 必须能由 double 精确表示。');
    parameters = struct('lutType', 'R', 'blockSize', blockSize, ...
        'thresholdMode', thresholdMode);
    switch thresholdMode
        case 'count'
            validateattributes(N1, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'integer', '>=', 0, '<=', blockPixels}, mfilename, 'N1');
            validateattributes(N2, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'integer', '>=', 0, '<=', blockPixels}, mfilename, 'N2');
            N1 = double(N1);
            N2 = double(N2);
            parameters.sourceN1 = N1;
            parameters.sourceN2 = N2;
        case 'ratio'
            validateattributes(highRatio1, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'highRatio1');
            validateattributes(highRatio2, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'highRatio2');
            assert(highRatio1 < highRatio2, ...
                'generateReliabilityLUT:InvalidRatios', ...
                '必须满足 0 <= highRatio1 < highRatio2 <= 1。');
            parameters.highRatio1 = double(highRatio1);
            parameters.highRatio2 = double(highRatio2);
            N1 = round(double(highRatio1) * blockPixels);
            N2 = round(double(highRatio2) * blockPixels);
        otherwise
            error('generateReliabilityLUT:InvalidThresholdMode', ...
                'thresholdMode 必须为 count 或 ratio。');
    end
    assert(0 <= N1 && N1 < N2 && N2 <= blockPixels, ...
        'generateReliabilityLUT:InvalidThresholds', ...
        '最终阈值须满足 0 <= N1 < N2 <= blockSize^2；取整合并时请调整参数。');
    if ~strcmp(outputMode, 'float') && Rmin > 0
        assert(round(Rmin * 2 ^ double(fracBits)) >= 1, ...
            'generateReliabilityLUT:QuantizedMinimumZero', ...
            '正的 Rmin 被量化为 0，请提高 fracBits。');
    end

    n = (0:blockPixels).';
    lutFloat = ones(blockPixels + 1, 1);
    linearMask = n > N1 & n < N2;
    lutFloat(linearMask) = 1 - (1 - Rmin) * (n(linearMask) - N1) / (N2 - N1);
    lutFloat(n >= N2) = Rmin;
    parameters.N1 = N1;
    parameters.N2 = N2;
    parameters.Rmin = Rmin;
    parameters.addressFormula = 'Nh';
    info = exportMeteringLUT(lutFloat, outputDir, ...
        sprintf('LUT_R_B%d', blockSize), outputMode, fracBits, parameters);
end
