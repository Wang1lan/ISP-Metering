function info = generateReciprocalLUT()
%GENERATERECIPROCALLUT 离线生成 [1,2) 归一化分母的中点倒数表。
% 修改参数区后无参运行；与 block 大小及视场几何无关。

    % USER PARAMETERS BEGIN
    addrBits = 8;
    fracBits = 18;                % 整数编码小数位数，不影响 float 系数
    outputMode = 'both';          % 'float'、'fixed' 或 'both'
    outputDir = fullfile(fileparts(mfilename('fullpath')), '..');
    % USER PARAMETERS END

    validateattributes(addrBits, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'addrBits');
    count = 2 ^ double(addrBits);
    assert(isfinite(count) && count < flintmax, ...
        'generateReciprocalLUT:InvalidAddressBits', '表长须能由 double 精确表示。');
    address = (0:count-1).';
    lutFloat = 1 ./ (1 + (address + 0.5) / count);
    parameters = struct('lutType', 'Reciprocal', 'addrBits', double(addrBits), ...
        'normalizedMin', 1, 'normalizedMax', 2, 'sampleRule', 'midpoint', ...
        'addressFormula', 'floor((m-1)*2^addrBits)');
    info = exportMeteringLUT(lutFloat, outputDir, ...
        sprintf('LUT_Reciprocal_A%d', addrBits), outputMode, fracBits, parameters);
end
