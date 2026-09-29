function info = generateFusionLUT()
%GENERATEFUSIONLUT 按实际 FOV 离线生成严重高光 block 数量到 lambda 的表。
% FOV 文件必须与图像尺寸、blockSize 匹配；不手写有效 block 数。

    % USER PARAMETERS BEGIN
    blockSize = 16;
    imageSize = [1080, 1920];
    fovFile = fullfile(fileparts(mfilename('fullpath')), '..', '..', '权重配置文件', '圆形有效视场权重_16×16.txt');
    fusionP1 = 0.002;
    fusionP2 = 0.03;
    lambdaMin = 0.3;
    lambdaMax = 0.8;
    outputMode = 'both';          % 'float'、'fixed' 或 'both'
    fracBits = 12;                % 1~30
    outputDir = fullfile(fileparts(mfilename('fullpath')), '..');
    % USER PARAMETERS END

    validateattributes(blockSize, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'blockSize');
    validateattributes(imageSize, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 2, 'integer', 'positive'}, mfilename, 'imageSize');
    validateattributes(fracBits, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 1, '<=', 30}, mfilename, 'fracBits');
    parameters = struct('P1', fusionP1, 'P2', fusionP2, ...
        'lambdaMin', lambdaMin, 'lambdaMax', lambdaMax);
    names = fieldnames(parameters);
    for k = 1:numel(names)
        validateattributes(parameters.(names{k}), {'numeric'}, ...
            {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, names{k});
        parameters.(names{k}) = double(parameters.(names{k}));
    end
    P1 = parameters.P1;
    P2 = parameters.P2;
    lambdaMin = parameters.lambdaMin;
    lambdaMax = parameters.lambdaMax;
    assert(P1 < P2, 'generateFusionLUT:InvalidThresholds', ...
        '必须满足 0 <= fusionP1 < fusionP2 <= 1。');
    assert(0 < lambdaMin && lambdaMin <= lambdaMax, ...
        'generateFusionLUT:InvalidLambdaMin', ...
        '必须满足 0 < lambdaMin <= lambdaMax <= 1。');
    if ~strcmp(outputMode, 'float')
        assert(round(lambdaMin * 2 ^ double(fracBits)) >= 1, ...
            'generateFusionLUT:QuantizedMinimumZero', ...
            '正的 lambdaMin 被量化为 0，请提高 fracBits。');
    end

    toolDir = fileparts(mfilename('fullpath'));
    projectDir = fileparts(fileparts(toolDir));
    fovFile = canonicalFilePath(fovFile, toolDir);
    outputDir = canonicalFilePath(outputDir, toolDir);
    oldPath = path;
    pathCleanup = onCleanup(@() path(oldPath));
    addpath(fullfile(projectDir, 'float'));
    blockSize = double(blockSize);
    imageSize = double(imageSize);
    validMask = loadFovBlockMask(fovFile, imageSize, blockSize);
    Nvalid = nnz(validMask);
    assert(Nvalid > 0, 'generateFusionLUT:EmptyFOV', ...
        'FOV 没有有效 block，不能生成正常测光用 lambda 表。');
    C1 = round(P1 * Nvalid);
    C2 = round(P2 * Nvalid);
    assert(0 <= C1 && C1 < C2 && C2 <= Nvalid, ...
        'generateFusionLUT:CollapsedThresholds', ...
        '取整后须满足 0 <= C1 < C2 <= Nvalid，请调整 fusionP1/fusionP2 或有效视场。');

    n = (0:Nvalid).';
    lutFloat = lambdaMin * ones(Nvalid + 1, 1);
    linearMask = n > C1 & n < C2;
    lutFloat(linearMask) = lambdaMin + (lambdaMax - lambdaMin) * ...
        (n(linearMask) - C1) / (C2 - C1);
    lutFloat(n >= C2) = lambdaMax;
    parameters.lutType = 'Lambda';
    parameters.blockSize = blockSize;
    parameters.imageHeight = imageSize(1);
    parameters.imageWidth = imageSize(2);
    parameters.blockRows = floor(imageSize(1) / blockSize);
    parameters.blockCols = floor(imageSize(2) / blockSize);
    parameters.fovFile = relativeFilePath(fovFile, outputDir);
    parameters.fovSHA256 = meteringFileSHA256(fovFile);
    parameters.Nvalid = Nvalid;
    parameters.C1 = C1;
    parameters.C2 = C2;
    parameters.addressFormula = 'RminBlockCnt';
    info = exportMeteringLUT(lutFloat, outputDir, ...
        sprintf('LUT_Lambda_B%d_N%d', blockSize, Nvalid), outputMode, fracBits, parameters);
end

function absolutePath = canonicalFilePath(filePath, toolDir)
    assert((ischar(filePath) && isrow(filePath)) || ...
        (isstring(filePath) && isscalar(filePath) && ~ismissing(filePath)), ...
        'generateFusionLUT:InvalidPath', '路径必须为非空单行文本。');
    filePath = char(filePath);
    assert(~isempty(filePath) && ~any(filePath == newline | ...
        filePath == char(13) | filePath == char(0)), ...
        'generateFusionLUT:InvalidPath', '路径不能为空或包含换行、空字符。');
    assert(usejava('jvm'), 'generateFusionLUT:JVMRequired', ...
        '生成文件摘要及相对路径需要 MATLAB 标准 JVM。');
    file = java.io.File(filePath);
    if ~file.isAbsolute()
        file = java.io.File(fullfile(toolDir, filePath));
    end
    absolutePath = char(file.getCanonicalPath());
end

function relativePath = relativeFilePath(filePath, directory)
% manifest 中的路径相对输出目录；不同盘符不能表示为相对路径。
    assert(usejava('jvm'), 'generateFusionLUT:JVMRequired', ...
        '生成文件摘要及相对路径需要 MATLAB 标准 JVM。');
    file = java.io.File(char(filePath));
    folder = java.io.File(char(directory));
    file = file.getCanonicalFile();
    folder = folder.getCanonicalFile();
    try
        folderPath = folder.toPath();
        relative = folderPath.relativize(file.toPath());
        relativePath = strrep(char(relative.toString()), '\', '/');
    catch exception
        error('generateFusionLUT:RelativePathFailed', ...
            '无法生成 FOV 相对路径，请将 outputDir 与 FOV 放在同一盘符：%s', exception.message);
    end
end
