function regionMask = loadRegionMasks( ...
    centerFile, edgeFile, imageSize, blockSize, validMask)
%LOADREGIONMASKS 初始化读取中心/边缘 TXT，并校验二维布局与覆盖关系。
% imageSize 为原图 [H, W]；TXT 按 block 逐行扫描，每行一个 0/1。
% validMask 必须与完整 block 网格同尺寸且为二值矩阵。
% 返回 regionMask.center 和 regionMask.edge，均为 logical 矩阵。

    narginchk(5, 5);
    centerFile = validatePath(centerFile, 'centerFile');
    edgeFile = validatePath(edgeFile, 'edgeFile');
    validateattributes(imageSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'vector', 'numel', 2, ...
         'integer', 'positive'}, mfilename, 'imageSize');
    validateattributes(blockSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'scalar', 'integer', 'positive'}, ...
        mfilename, 'blockSize');
    validateattributes(validMask, {'numeric', 'logical'}, ...
        {'real', 'finite', 'nonsparse', '2d', 'nonempty'}, ...
        mfilename, 'validMask');

    imageSize = reshape(double(imageSize), 1, 2);
    blockSize = double(blockSize);
    blockRows = floor(imageSize(1) / blockSize);
    blockCols = floor(imageSize(2) / blockSize);
    assert(blockRows >= 1 && blockCols >= 1, ...
        'loadRegionMasks:ImageTooSmall', ...
        '原图必须至少包含一个完整 block。');
    assert(isequal(size(validMask), [blockRows, blockCols]), ...
        'loadRegionMasks:InvalidMaskSize', ...
        'validMask 尺寸必须与 imageSize 和 blockSize 定义的完整 block 网格一致。');
    assert(all(validMask(:) == 0 | validMask(:) == 1), ...
        'loadRegionMasks:InvalidMaskValue', 'validMask 只能包含 0 或 1。');
    validMask = logical(validMask);

    centerValues = readBinaryColumn(centerFile, blockRows * blockCols);
    edgeValues = readBinaryColumn(edgeFile, blockRows * blockCols);
    centerMask = logical(reshape(centerValues, blockCols, blockRows).');
    edgeMask = logical(reshape(edgeValues, blockCols, blockRows).');
    assert(~any(centerMask(:) & edgeMask(:)), ...
        'loadRegionMasks:OverlappingRegions', '中心与边缘掩模不能相交。');
    assert(isequal(centerMask | edgeMask, validMask), ...
        'loadRegionMasks:InvalidCoverage', ...
        '中心与边缘掩模的并集必须严格等于 validMask。');
    assert(any(centerMask(:)) && any(edgeMask(:)), ...
        'loadRegionMasks:EmptyRegion', '中心与边缘必须均包含有效 block。');

    regionMask.center = centerMask;
    regionMask.edge = edgeMask;
end

function path = validatePath(path, argumentName)
    if isstring(path)
        assert(isscalar(path) && ~ismissing(path) && strlength(path) > 0, ...
            'loadRegionMasks:InvalidPath', '%s 必须是非空文本路径。', argumentName);
        path = char(path);
    end
    assert(ischar(path) && isrow(path) && ~isempty(strtrim(path)), ...
        'loadRegionMasks:InvalidPath', '%s 必须是非空文本路径。', argumentName);
end

function v = readBinaryColumn(path, elementCount)
% 逐行校验，以免表头、空行、多列或非二值数据被自动导入忽略。
    [fid, message] = fopen(path, 'rt');
    assert(fid >= 0, 'loadRegionMasks:ReadFailed', ...
        '无法读取掩模文件 %s：%s', path, message);
    cleanup = onCleanup(@() fclose(fid));
    v = zeros(elementCount, 1);
    numberPattern = '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$';
    for k = 1:elementCount
        line = fgetl(fid);
        assert(ischar(line), 'loadRegionMasks:InvalidMaskSize', ...
            '掩模必须恰有 %d 行，每行一个数。', elementCount);
        token = strtrim(line);
        value = str2double(token);
        assert(~isempty(regexp(token, numberPattern, 'once')) && ...
            isfinite(value) && (value == 0 || value == 1), ...
            'loadRegionMasks:InvalidMaskValue', ...
            '掩模第 %d 行必须仅包含一个有限的 0 或 1。', k);
        v(k) = value;
    end
    assert(~ischar(fgetl(fid)), 'loadRegionMasks:InvalidMaskSize', ...
        '掩模必须恰有 %d 行，每行一个数。', elementCount);
end
