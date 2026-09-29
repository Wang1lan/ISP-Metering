function [luts, cfg, validMask] = loadMeteringLUTs(cfg, imageSize, weightFile)
%LOADMETERINGLUTS 初始化加载三张离线浮点表，验证格式、摘要和运行几何。
% 映射参数从 manifest 填入 cfg；重新调参须重导出并重新初始化。
% 正常路径不读取整数表，不生成映射表，不按文件名推测兼容性。
    narginchk(3, 3);
    validateattributes(cfg, {'struct'}, {'scalar'});
    validateattributes(imageSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'vector', 'numel', 2, 'integer', 'positive'});
    assert(isfield(cfg, 'lutManifests') && isstruct(cfg.lutManifests) && ...
        isscalar(cfg.lutManifests) && ...
        all(isfield(cfg.lutManifests, {'R', 'alpha', 'lambda'})), ...
        'loadMeteringLUTs:MissingConfig', 'cfg.lutManifests 须明确选择 R/alpha/lambda manifest。');
    [luts.R, luts.meta.R] = loadOne(cfg.lutManifests.R, 'R', 'generateReliabilityLUT');
    [luts.alpha, luts.meta.alpha] = loadOne(cfg.lutManifests.alpha, 'Alpha', 'generateAlphaLUT');
    [luts.lambda, luts.meta.lambda] = loadOne(cfg.lutManifests.lambda, 'Lambda', 'generateFusionLUT');
    r = luts.meta.R;
    a = luts.meta.alpha;
    f = luts.meta.lambda;
    assert(r.blockSize == f.blockSize, 'loadMeteringLUTs:BlockSizeMismatch', ...
        'R 与 Lambda 的 blockSize 不一致；请同步参数并重新运行对应生成器。');
    assert(isequal(reshape(double(imageSize), 1, 2), [f.imageHeight, f.imageWidth]), ...
        'loadMeteringLUTs:ImageSizeMismatch', ...
        '图像尺寸与 Lambda manifest 不一致；请重新运行 generateFusionLUT。');
    try
        validMask = loadFovBlockMask(weightFile, imageSize, r.blockSize);
        assert(isequal(size(validMask), [f.blockRows, f.blockCols]), ...
            'loadMeteringLUTs:GridMismatch', 'FOV 网格尺寸不匹配。');
        assert(nnz(validMask) > 0 && nnz(validMask) == f.Nvalid, ...
            'loadMeteringLUTs:FovCountMismatch', 'FOV 有效块数与 Lambda manifest 不匹配或为空。');
        assert(strcmpi(meteringFileSHA256(weightFile), f.fovSHA256), ...
            'loadMeteringLUTs:FovDigestMismatch', 'FOV 原始字节摘要不匹配。');
    catch cause
        error('loadMeteringLUTs:InvalidFov', ...
            '%s 请确认 FOV 并重新运行 generateFusionLUT。', cause.message);
    end
    for name = {'blockSize', 'N1', 'N2', 'Rmin'}
        cfg.(name{1}) = r.(name{1});
    end
    for name = {'rho1', 'rho2', 'rho3', 'rho4', 'alphaMin', 'Wc', 'alphaMax', 'LpMin'}
        cfg.(name{1}) = a.(name{1});
    end
    cfg.fusionP1 = f.P1;
    cfg.fusionP2 = f.P2;
    cfg.lambdaMin = f.lambdaMin;
    cfg.lambdaMax = f.lambdaMax;
end

function [lut, meta] = loadOne(manifestFile, lutType, generator)
    try
        meta = readManifest(manifestFile);
        require(meta, {'formatVersion', 'lutType', 'outputMode', 'floatFile', ...
            'fixedFile', 'floatSHA256', 'fixedSHA256', 'length', 'fracBits', ...
            'logicalBits', 'rounding', 'addressBase', 'addressFormula'});
        meta = numbers(meta, {'formatVersion', 'length', 'fracBits', 'logicalBits', 'addressBase'});
        assert(meta.formatVersion == 1 && strcmp(meta.lutType, lutType), ...
            'loadMeteringLUTs:FormatMismatch', 'manifest 版本或类型不匹配。');
        integerIn(meta.length, 1, Inf, 'length');
        integerIn(meta.fracBits, 1, 30, 'fracBits');
        assert(meta.logicalBits == meta.fracBits + 1 && meta.addressBase == 0 && ...
            strcmp(meta.rounding, 'nearestHalfUp'), ...
            'loadMeteringLUTs:EncodingMismatch', '逻辑位宽、地址基数或舍入规则不匹配。');
        assert(any(strcmp(meta.outputMode, {'float', 'fixed', 'both'})), ...
            'loadMeteringLUTs:InvalidMode', 'outputMode 无效。');
        hasFloat = any(strcmp(meta.outputMode, {'float', 'both'}));
        hasFixed = any(strcmp(meta.outputMode, {'fixed', 'both'}));
        checkOutput(meta.floatFile, meta.floatSHA256, hasFloat);
        checkOutput(meta.fixedFile, meta.fixedSHA256, hasFixed);
        assert(hasFloat, 'loadMeteringLUTs:NoFloatOutput', ...
            '本次 manifest 未导出 float 表，不能使用遗留文件或 QF 替代。');
        switch lutType
            case 'R'
                meta = validateR(meta);
            case 'Alpha'
                meta = validateAlpha(meta);
            case 'Lambda'
                meta = validateLambda(meta);
        end
        manifestFile = char(manifestFile);
        meta.manifestFile = manifestFile;
        meta.floatPath = fullfile(fileparts(manifestFile), meta.floatFile);
        meta.fixedPath = '';
        if hasFixed
            meta.fixedPath = fullfile(fileparts(manifestFile), meta.fixedFile);
        end
        assert(strcmpi(meteringFileSHA256(meta.floatPath), meta.floatSHA256), ...
            'loadMeteringLUTs:DigestMismatch', '浮点数据文件的 SHA-256 不匹配。');
        lut = readMeteringColumn(meta.floatPath, meta.length);
        assert(all(lut >= 0 & lut <= 1), 'loadMeteringLUTs:OutOfRange', 'LUT 系数必须在 [0,1]。');
        checkValues(lut, meta);
    catch cause
        error('loadMeteringLUTs:InvalidLUT', ...
            '%s LUT 加载失败：%s 请检查配置并重新运行 %s。', lutType, cause.message, generator);
    end
end

function meta = readManifest(filePath)
    [fid, message] = fopen(filePath, 'rt', 'n', 'UTF-8');
    assert(fid >= 0, 'loadMeteringLUTs:ReadFailed', '无法读取 %s：%s', filePath, message);
    cleanup = onCleanup(@() fclose(fid));
    meta = struct();
    line = fgetl(fid);
    while ischar(line)
        position = find(line == '=', 1);
        assert(~isempty(position), 'loadMeteringLUTs:InvalidManifest', 'manifest 每行必须为 key=value。');
        key = strtrim(line(1:position-1));
        assert(~isempty(regexp(key, '^[A-Za-z][A-Za-z0-9_]*$', 'once')) && ...
            isvarname(key) && ~isfield(meta, key), ...
            'loadMeteringLUTs:InvalidManifest', 'manifest 键非法或重复：%s', key);
        meta.(key) = strtrim(line(position+1:end));
        line = fgetl(fid);
    end
    [message, number] = ferror(fid);
    assert(number == 0 || (number == -4 && feof(fid)), ...
        'loadMeteringLUTs:ReadFailed', '%s', message);
end

function require(meta, fields)
    for k = 1:numel(fields)
        assert(isfield(meta, fields{k}), 'loadMeteringLUTs:MissingMetadata', ...
            'manifest 缺少字段 %s。', fields{k});
    end
end

function meta = numbers(meta, fields)
    require(meta, fields);
    pattern = '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$';
    for k = 1:numel(fields)
        name = fields{k};
        token = meta.(name);
        value = str2double(token);
        assert(~isempty(regexp(token, pattern, 'once')) && isfinite(value), ...
            'loadMeteringLUTs:InvalidMetadata', 'manifest %s 必须是有限实数。', name);
        meta.(name) = value;
    end
end

function integerIn(value, lo, hi, name)
    assert(value == floor(value) && value >= lo && value <= hi, ...
        'loadMeteringLUTs:InvalidMetadata', '%s 整数范围不正确。', name);
end

function checkRelative(file)
    assert(~isempty(file) && isempty(regexp(file, '^([A-Za-z]:|[\\/])', 'once')), ...
        'loadMeteringLUTs:AbsoluteDataPath', 'manifest 数据路径必须是相对路径。');
end

function checkOutput(file, hash, expected)
    if expected
        checkRelative(file);
        assert(~isempty(regexp(hash, '^[0-9a-fA-F]{64}$', 'once')), ...
            'loadMeteringLUTs:InvalidDigest', 'manifest SHA-256 格式不正确。');
    else
        assert(isempty(file) && isempty(hash), 'loadMeteringLUTs:OutputModeMismatch', ...
            '未导出的格式必须使用空路径和空摘要。');
    end
end

function m = validateR(m)
    require(m, {'thresholdMode'});
    m = numbers(m, {'blockSize', 'N1', 'N2', 'Rmin'});
    integerIn(m.blockSize, 1, Inf, 'blockSize');
    integerIn(m.N1, 0, m.blockSize^2, 'N1');
    integerIn(m.N2, 0, m.blockSize^2, 'N2');
    assert(m.N1 < m.N2 && m.Rmin >= 0 && m.Rmin <= 1 && ...
        m.length == m.blockSize^2 + 1 && strcmp(m.addressFormula, 'Nh'), ...
        'loadMeteringLUTs:InvalidR', 'R 参数、长度或地址公式不正确。');
    if strcmp(m.thresholdMode, 'count')
        m = numbers(m, {'sourceN1', 'sourceN2'});
        assert(m.N1 == m.sourceN1 && m.N2 == m.sourceN2, ...
            'loadMeteringLUTs:InvalidR', 'count 原始阈值与最终阈值不一致。');
    elseif strcmp(m.thresholdMode, 'ratio')
        m = numbers(m, {'highRatio1', 'highRatio2'});
        assert(0 <= m.highRatio1 && m.highRatio1 < m.highRatio2 && m.highRatio2 <= 1 && ...
            m.N1 == round(m.highRatio1 * m.blockSize^2) && ...
            m.N2 == round(m.highRatio2 * m.blockSize^2), ...
            'loadMeteringLUTs:InvalidR', 'ratio 原始阈值与最终阈值不一致。');
    else
        error('loadMeteringLUTs:InvalidR', 'thresholdMode 必须是 count 或 ratio。');
    end
    assert(strcmp(m.outputMode, 'float') || m.Rmin == 0 || round(m.Rmin * 2^m.fracBits) >= 1, ...
        'loadMeteringLUTs:QuantizedZero', '正 Rmin 被量化为零，须提高 fracBits。');
end

function m = validateAlpha(m)
    require(m, {'addressOrder', 'blackFrameRule'});
    m = numbers(m, {'inputBits', 'LcLevels', 'LpLevels', 'rho1', 'rho2', ...
        'rho3', 'rho4', 'alphaMin', 'Wc', 'alphaMax', 'LpMin'});
    assert(m.inputBits == 8 && m.LcLevels == 256 && m.LpLevels == 256 && ...
        m.length == 65536 && strcmp(m.addressFormula, '256*Lp_q+Lc_q') && ...
        strcmp(m.addressOrder, 'LcFastest') && strcmp(m.blackFrameRule, 'Lc==0&&Lp==0:Wc'), ...
        'loadMeteringLUTs:InvalidAlpha', 'Alpha 输入域或地址约定不正确。');
    assert(0 < m.rho1 && m.rho1 < m.rho2 && m.rho2 <= 1 && ...
        1 <= m.rho3 && m.rho3 < m.rho4 && m.rho2 < m.rho3 && ...
        0 <= m.alphaMin && m.alphaMin <= m.Wc && m.Wc <= m.alphaMax && ...
        m.alphaMax <= 1 && m.LpMin > 0, ...
        'loadMeteringLUTs:InvalidAlpha', 'Alpha 映射参数范围不正确。');
end

function m = validateLambda(m)
    require(m, {'fovFile', 'fovSHA256'});
    m = numbers(m, {'blockSize', 'imageHeight', 'imageWidth', 'blockRows', ...
        'blockCols', 'Nvalid', 'P1', 'P2', 'C1', 'C2', 'lambdaMin', 'lambdaMax'});
    for name = {'blockSize', 'imageHeight', 'imageWidth', 'blockRows', 'blockCols', 'Nvalid'}
        integerIn(m.(name{1}), 1, Inf, name{1});
    end
    assert(m.blockRows == floor(m.imageHeight / m.blockSize) && ...
        m.blockCols == floor(m.imageWidth / m.blockSize) && ...
        m.Nvalid <= m.blockRows * m.blockCols && m.length == m.Nvalid + 1 && ...
        strcmp(m.addressFormula, 'RminBlockCnt'), ...
        'loadMeteringLUTs:InvalidLambda', 'Lambda 几何、长度或地址公式不正确。');
    assert(0 <= m.P1 && m.P1 < m.P2 && m.P2 <= 1 && ...
        0 < m.lambdaMin && m.lambdaMin <= m.lambdaMax && m.lambdaMax <= 1 && ...
        m.C1 == round(m.P1 * m.Nvalid) && m.C2 == round(m.P2 * m.Nvalid) && ...
        0 <= m.C1 && m.C1 < m.C2 && m.C2 <= m.Nvalid, ...
        'loadMeteringLUTs:InvalidLambda', 'Lambda 阈值、下限或取整后计数不正确。');
    checkRelative(m.fovFile);
    assert(~isempty(regexp(m.fovSHA256, '^[0-9a-fA-F]{64}$', 'once')), ...
        'loadMeteringLUTs:InvalidDigest', 'FOV SHA-256 格式不正确。');
    assert(strcmp(m.outputMode, 'float') || round(m.lambdaMin * 2^m.fracBits) >= 1, ...
        'loadMeteringLUTs:QuantizedZero', '正 lambdaMin 被量化为零，须提高 fracBits。');
end

function checkValues(lut, m)
    tol = 1e-12;
    switch m.lutType
        case 'R'
            assert(all(lut >= m.Rmin - tol) && all(diff(lut) <= tol) && ...
                abs(lut(1) - 1) <= tol && abs(lut(m.N1 + 1) - 1) <= tol && ...
                abs(lut(m.N2 + 1) - m.Rmin) <= tol && abs(lut(end) - m.Rmin) <= tol, ...
                'loadMeteringLUTs:InvalidValues', 'R 的范围、端点或单调性不正确。');
        case 'Alpha'
            % 展平向量跨 Lp 行会跳变，不能检查全局单调性。
            assert(all(lut >= m.alphaMin - tol & lut <= m.alphaMax + tol) && ...
                abs(lut(1) - m.Wc) <= tol && ...
                all(abs(lut(257:256:end) - m.alphaMin) <= tol), ...
                'loadMeteringLUTs:InvalidValues', 'Alpha 范围或零亮度地址不正确。');
        case 'Lambda'
            assert(all(lut > 0 & lut >= m.lambdaMin - tol & lut <= m.lambdaMax + tol) && ...
                all(diff(lut) >= -tol) && abs(lut(1) - m.lambdaMin) <= tol && ...
                abs(lut(m.C1 + 1) - m.lambdaMin) <= tol && ...
                abs(lut(m.C2 + 1) - m.lambdaMax) <= tol && abs(lut(end) - m.lambdaMax) <= tol, ...
                'loadMeteringLUTs:InvalidValues', 'Lambda 范围、端点或单调性不正确。');
    end
end
