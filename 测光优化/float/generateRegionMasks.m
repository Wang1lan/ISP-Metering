function [centerMask, edgeMask, info] = generateRegionMasks( ...
    validWeightFile, centerRatio, blockSize, imageSize, outputDir)
%GENERATEREGIONMASKS 按有效 block 到原图中心的距离生成区域配置。
% imageSize 为原图 [H, W]，只保留完整的 block。centerRatio 为中心
% 有效 block 的目标比例（通常为 0.75），实际数量采用 round。
% 输入、输出 TXT 均按从左到右、从上到下的顺序，每行一个 0/1。
% 输出掩模为 logical；info 记录实际比例、布局和导出文件路径。

    narginchk(5, 5);
    validWeightFile = validatePath(validWeightFile, 'validWeightFile');
    outputDir = validatePath(outputDir, 'outputDir');
    validateattributes(centerRatio, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'scalar', '>', 0, '<', 1}, ...
        mfilename, 'centerRatio');
    validateattributes(blockSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'scalar', 'integer', 'positive'}, ...
        mfilename, 'blockSize');
    validateattributes(imageSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'vector', 'numel', 2, ...
         'integer', 'positive'}, mfilename, 'imageSize');

    centerRatio = double(centerRatio);
    blockSize = double(blockSize);
    imageSize = reshape(double(imageSize), 1, 2);
    blockRows = floor(imageSize(1) / blockSize);
    blockCols = floor(imageSize(2) / blockSize);
    assert(blockRows >= 1 && blockCols >= 1, ...
        'generateRegionMasks:ImageTooSmall', ...
        '原图必须至少包含一个完整 block。');

    v = readBinaryColumn(validWeightFile, blockRows * blockCols);
    validMask = logical(reshape(v, blockCols, blockRows).');
    validBlockCount = nnz(validMask);
    centerBlockCount = round(centerRatio * validBlockCount);
    edgeBlockCount = validBlockCount - centerBlockCount;
    assert(centerBlockCount > 0 && edgeBlockCount > 0, ...
        'generateRegionMasks:EmptyRegion', ...
        '中心与边缘必须均包含有效 block，请修改 centerRatio 或有效区域。');

    % 原图中心不随底部、右侧不完整 block 的丢弃而移动。
    viewCenter = [(imageSize(2) + 1) / 2, (imageSize(1) + 1) / 2];
    validIndices = find(validMask);
    [r, c] = ind2sub([blockRows, blockCols], validIndices);
    x = (c - 1) * blockSize + (blockSize + 1) / 2;
    y = (r - 1) * blockSize + (blockSize + 1) / 2;
    distanceSquared = (x - viewCenter(1)).^2 + (y - viewCenter(2)).^2;
    rowScanIndex = (r - 1) * blockCols + c;
    [~, order] = sortrows([distanceSquared, rowScanIndex], [1, 2]);

    centerMask = false(blockRows, blockCols);
    centerMask(validIndices(order(1:centerBlockCount))) = true;
    edgeMask = validMask & ~centerMask;
    assert(~any(centerMask(:) & edgeMask(:)) && ...
        isequal(centerMask | edgeMask, validMask) && ...
        nnz(centerMask) == centerBlockCount && ...
        nnz(edgeMask) == edgeBlockCount, ...
        'generateRegionMasks:InvalidPartition', '区域划分未满足覆盖和数量约束。');

    if ~isfolder(outputDir)
        [ok, message] = mkdir(outputDir);
        assert(ok, 'generateRegionMasks:OutputDirectory', ...
            '无法创建输出目录：%s', message);
    end
    centerFile = fullfile(outputDir, sprintf( ...
        '中心视场权重_%d×%d_%g.txt', blockSize, blockSize, 100 * centerRatio));
    edgeFile = fullfile(outputDir, sprintf( ...
        '边缘视场权重_%d×%d_%g.txt', blockSize, blockSize, 100 * (1 - centerRatio)));
    writeBinaryColumn(centerFile, centerMask);
    writeBinaryColumn(edgeFile, edgeMask);

    info.centerFile = centerFile;
    info.edgeFile = edgeFile;
    info.imageSize = imageSize;
    info.blockSize = blockSize;
    info.blockRows = blockRows;
    info.blockCols = blockCols;
    info.viewCenter = viewCenter;
    info.validBlockCount = validBlockCount;
    info.centerBlockCount = centerBlockCount;
    info.edgeBlockCount = edgeBlockCount;
    info.targetCenterRatio = centerRatio;
    info.actualCenterRatio = centerBlockCount / validBlockCount;
    info.actualEdgeRatio = edgeBlockCount / validBlockCount;
    info.tieBreakRule = ...
        'distanceSquared ascending, then (r-1)*blockCols+c ascending';
end

function path = validatePath(path, argumentName)
    if isstring(path)
        assert(isscalar(path) && ~ismissing(path) && strlength(path) > 0, ...
            'generateRegionMasks:InvalidPath', '%s 必须是非空文本路径。', argumentName);
        path = char(path);
    end
    assert(ischar(path) && isrow(path) && ~isempty(strtrim(path)), ...
        'generateRegionMasks:InvalidPath', '%s 必须是非空文本路径。', argumentName);
end

function v = readBinaryColumn(path, elementCount)
% 按行读取，避免自动导入静默跳过表头、空行或接受多列布局。
    [fid, message] = fopen(path, 'rt');
    assert(fid >= 0, 'generateRegionMasks:ReadFailed', ...
        '无法读取掩模文件 %s：%s', path, message);
    cleanup = onCleanup(@() fclose(fid));
    v = zeros(elementCount, 1);
    numberPattern = '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$';
    for k = 1:elementCount
        line = fgetl(fid);
        assert(ischar(line), 'generateRegionMasks:InvalidMaskSize', ...
            '掩模必须恰有 %d 行，每行一个数。', elementCount);
        token = strtrim(line);
        value = str2double(token);
        assert(~isempty(regexp(token, numberPattern, 'once')) && ...
            isfinite(value) && (value == 0 || value == 1), ...
            'generateRegionMasks:InvalidMaskValue', ...
            '掩模第 %d 行必须仅包含一个有限的 0 或 1。', k);
        v(k) = value;
    end
    assert(~ischar(fgetl(fid)), 'generateRegionMasks:InvalidMaskSize', ...
        '掩模必须恰有 %d 行，每行一个数。', elementCount);
end

function writeBinaryColumn(path, mask)
    [fid, message] = fopen(path, 'wt');
    assert(fid >= 0, 'generateRegionMasks:WriteFailed', ...
        '无法写入掩模文件 %s：%s', path, message);
    cleanup = onCleanup(@() fclose(fid));
    v = reshape(double(mask).', [], 1);
    fprintf(fid, '%d\n', v);
    [message, errorNumber] = ferror(fid);
    assert(errorNumber == 0, 'generateRegionMasks:WriteFailed', ...
        '写入掩模文件 %s 失败：%s', path, message);
end
