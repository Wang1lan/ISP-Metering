function info = exportMeteringLUT(lutFloat, outputDir, baseName, outputMode, fracBits, parameters)
%EXPORTMETERINGLUT 公共导出：校验数据、量化、写 TXT 和 UTF-8 manifest。
% 不包含 R/alpha/lambda 映射公式。parameters 含 lutType 和专属元数据。
% 完整校验通过后写数据，摘要按实际文件字节计算，manifest 最后写入。

    validateattributes(lutFloat, {'numeric'}, ...
        {'real', 'finite', 'vector', 'nonempty', '>=', 0, '<=', 1}, mfilename, 'lutFloat');
    validateattributes(fracBits, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 1, '<=', 30}, mfilename, 'fracBits');
    validateattributes(parameters, {'struct'}, {'scalar'}, mfilename, 'parameters');
    outputDir = textScalar(outputDir, 'outputDir');
    baseName = textScalar(baseName, 'baseName');
    outputMode = textScalar(outputMode, 'outputMode');
    assert(~isempty(outputDir) && ~isempty(baseName) && ...
        isempty(regexp(baseName, '[\\/:*?"<>|]', 'once')), ...
        'exportMeteringLUT:InvalidPath', 'outputDir 不能为空，baseName 必须为不含目录的有效文件名。');
    assert(any(strcmp(outputMode, {'float', 'fixed', 'both'})), ...
        'exportMeteringLUT:InvalidOutputMode', 'outputMode 必须为 float、fixed 或 both。');
    assert(isfield(parameters, 'lutType'), ...
        'exportMeteringLUT:MissingLUTType', 'parameters 必须包含 lutType。');
    lutType = textScalar(parameters.lutType, 'lutType');
    assert(any(strcmp(lutType, {'R', 'Alpha', 'Lambda'})), ...
        'exportMeteringLUT:InvalidLUTType', 'lutType 必须为 R、Alpha 或 Lambda。');
    assert(usejava('jvm'), 'exportMeteringLUT:JVMRequired', ...
        '导出及 SHA-256 校验需要 MATLAB 标准 JVM。');
    directory = java.io.File(outputDir);
    if ~directory.isAbsolute()
        directory = java.io.File(fullfile(fileparts(mfilename('fullpath')), outputDir));
    end
    outputDir = char(directory.getCanonicalPath());
    fracBits = double(fracBits);
    lutFloat = double(lutFloat(:));
    scale = 2 ^ fracBits;
    quantized = floor(lutFloat * scale + 0.5);
    assert(all(quantized >= 0 & quantized <= scale & quantized == floor(quantized)), ...
        'exportMeteringLUT:InvalidQuantization', '量化结果必须为 [0, 2^fracBits] 内的整数。');
    lutInt = uint32(quantized);    % 容器与逻辑位宽区分，1.0 的编码不截断

    floatName = '';
    fixedName = '';
    if any(strcmp(outputMode, {'float', 'both'}))
        floatName = [baseName '_float.txt'];
    end
    if any(strcmp(outputMode, {'fixed', 'both'}))
        fixedName = sprintf('%s_Q%d.txt', baseName, fracBits);
    end
    meta = struct('formatVersion', 1, 'lutType', lutType, ...
        'outputMode', outputMode, 'floatFile', floatName, 'fixedFile', fixedName, ...
        'floatSHA256', '', 'fixedSHA256', '', 'length', numel(lutFloat), ...
        'fracBits', fracBits, 'logicalBits', fracBits + 1, ...
        'rounding', 'nearestHalfUp', 'addressBase', 0);
    names = fieldnames(parameters);
    for k = 1:numel(names)
        key = names{k};
        if strcmp(key, 'lutType')
            continue;
        end
        assert(~isfield(meta, key), 'exportMeteringLUT:ReservedMetadata', ...
            'parameters.%s 与公共元数据字段重名。', key);
        meta.(key) = parameters.(key);
    end
    manifestText(meta);           % 所有元数据先校验，避免写完数据才发现非法字段
    info = struct('floatFile', '', 'fixedFile', '', ...
        'manifestFile', fullfile(outputDir, [baseName '_manifest.txt']), ...
        'length', numel(lutFloat), 'parameters', parameters, ...
        'fracBits', fracBits, 'logicalBits', fracBits + 1);

    toolDir = fileparts(mfilename('fullpath'));
    projectDir = fileparts(fileparts(toolDir));
    oldPath = path;
    pathCleanup = onCleanup(@() path(oldPath));
    addpath(fullfile(projectDir, 'float'));
    if ~isfolder(outputDir)
        [success, message] = mkdir(outputDir);
        assert(success, 'exportMeteringLUT:CreateDirectoryFailed', ...
            '无法创建输出目录 %s：%s', outputDir, message);
    end
    if ~isempty(floatName)
        info.floatFile = fullfile(outputDir, floatName);
        writeFile(info.floatFile, '%.17g\n', lutFloat);
        meta.floatSHA256 = meteringFileSHA256(info.floatFile);
    end
    if ~isempty(fixedName)
        info.fixedFile = fullfile(outputDir, fixedName);
        writeFile(info.fixedFile, '%.0f\n', double(lutInt));
        meta.fixedSHA256 = meteringFileSHA256(info.fixedFile);
    end
    writeFile(info.manifestFile, '%s', manifestText(meta));
    info.meta = meta;
end

function value = textScalar(value, name)
    assert((ischar(value) && (isrow(value) || isempty(value))) || ...
        (isstring(value) && isscalar(value) && ~ismissing(value)), ...
        'exportMeteringLUT:InvalidText', '%s 必须为单行文本。', name);
    value = char(value);
    assert(~any(value == newline | value == char(13) | value == char(0)), ...
        'exportMeteringLUT:InvalidText', '%s 不能包含换行或空字符。', name);
end

function contents = manifestText(meta)
    names = fieldnames(meta);
    lines = cell(numel(names), 1);
    for k = 1:numel(names)
        value = meta.(names{k});
        if isnumeric(value)
            validateattributes(value, {'numeric'}, {'real', 'finite', 'scalar'}, ...
                mfilename, names{k});
            value = sprintf('%.17g', double(value));
        else
            value = textScalar(value, names{k});
        end
        lines{k} = sprintf('%s=%s\n', names{k}, value);
    end
    contents = [lines{:}];
end

function writeFile(filePath, format, values)
    [fid, message] = fopen(filePath, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'exportMeteringLUT:OpenFailed', ...
        '无法打开输出文件 %s：%s', filePath, message);
    try
        count = fprintf(fid, format, values);
        [message, errorNumber] = ferror(fid);
        if count < 0 || errorNumber ~= 0
            error('exportMeteringLUT:WriteFailed', '写入 %s 失败：%s', filePath, message);
        end
    catch exception
        fclose(fid);
        rethrow(exception);
    end
    status = fclose(fid);
    assert(status == 0, 'exportMeteringLUT:CloseFailed', ...
        '关闭输出文件 %s 失败，数据可能未完整写入。', filePath);
end
