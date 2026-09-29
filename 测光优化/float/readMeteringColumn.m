function values = readMeteringColumn(filePath, expectedLength)
%READMETERINGCOLUMN 严格读取每行一个有限实数的 TXT，不忽略空行或多列。
    validateattributes(expectedLength, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'});
    [fid, message] = fopen(filePath, 'rt');
    assert(fid >= 0, 'readMeteringColumn:ReadFailed', ...
        '无法读取 %s：%s', filePath, message);
    cleanup = onCleanup(@() fclose(fid));
    values = zeros(expectedLength, 1);
    pattern = '^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$';
    for k = 1:expectedLength
        line = fgetl(fid);
        assert(ischar(line), 'readMeteringColumn:LengthMismatch', ...
            '%s 必须恰有 %d 行，第 %d 行缺失。', filePath, expectedLength, k);
        token = strtrim(line);
        value = str2double(token);
        assert(~isempty(regexp(token, pattern, 'once')) && isfinite(value), ...
            'readMeteringColumn:InvalidValue', ...
            '%s 第 %d 行必须仅包含一个有限实数。', filePath, k);
        values(k) = value;
    end
    assert(~ischar(fgetl(fid)), 'readMeteringColumn:LengthMismatch', ...
        '%s 必须恰有 %d 行，存在多余数据或空行。', filePath, expectedLength);
    [message, number] = ferror(fid);
    assert(number == 0 || (number == -4 && feof(fid)), ...
        'readMeteringColumn:ReadFailed', '%s', message);
end
