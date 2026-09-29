function validMask = loadFovBlockMask(weightFile, imageSize, blockSize)
%LOADFOVBLOCKMASK 初始化读取 FOV；TXT 的 block 顺序为从左到右、从上到下。
    narginchk(3, 3);
    validateattributes(imageSize, {'numeric'}, ...
        {'real', 'finite', 'nonsparse', 'vector', 'numel', 2, 'integer', 'positive'});
    validateattributes(blockSize, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'});
    blockRows = floor(double(imageSize(1)) / double(blockSize));
    blockCols = floor(double(imageSize(2)) / double(blockSize));
    assert(blockRows >= 1 && blockCols >= 1, 'loadFovBlockMask:ImageTooSmall', ...
        '图像必须至少包含一个完整的 %d×%d block。', blockSize, blockSize);
    values = readMeteringColumn(weightFile, blockRows * blockCols);
    assert(all(values == 0 | values == 1), 'loadFovBlockMask:InvalidMaskValue', ...
        'FOV 权重文件只能包含 0 或 1。');
    validMask = logical(reshape(values, blockCols, blockRows).');
end
