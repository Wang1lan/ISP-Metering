function [fusion, fusionDebug] = fusionMetering(prep, region, peak, cfg)
%FUSIONMETERING 第四阶段区域/峰值测光融合，输出最终 0~255 浮点亮度。
% 仅使用同一帧、同一有效视场的标量结果，不重新扫描像素或 block。
% 严重高光数量直接复用 prep.RminBlockCnt（Nh >= N2），不重新判断 Ri。
% 正常时 Mf = Mr + lambda * max(0, Mp-Mr)，亮度保留 double 小数。
% 下游仅在 fusion.valid=true 时使用 Mf；无效结果为 NaN，不替换成零。

    checkStructure(prep, {'validBlockCnt', 'RminBlockCnt'}, 'prep');
    checkStructure(region, {'Mr', 'valid', 'status'}, 'region');
    checkStructure(peak, {'Mp', 'valid', 'status', 'validBlockCnt'}, 'peak');
    Nvalid = checkCount(prep.validBlockCnt, 'prep.validBlockCnt');
    count = checkCount(prep.RminBlockCnt, 'prep.RminBlockCnt');
    peakCount = checkCount(peak.validBlockCnt, 'peak.validBlockCnt');
    assert(count <= Nvalid, 'fusionMetering:InvalidHighlightCount', ...
        'prep.RminBlockCnt 不能超过 prep.validBlockCnt。');
    assert(peakCount == Nvalid, 'fusionMetering:BlockCountMismatch', ...
        'peak.validBlockCnt 必须等于 prep.validBlockCnt。');
    regionValid = checkValidFlag(region.valid, 'region.valid');
    peakValid = checkValidFlag(peak.valid, 'peak.valid');
    Mr = checkBrightness(region.Mr, regionValid, 'region.Mr');
    Mp = checkBrightness(peak.Mp, peakValid, 'peak.Mp');
    checkStatus(region.status, 'region.status');
    checkStatus(peak.status, 'peak.status');

    fusion = struct('Mf', NaN, 'lambda', NaN, ...
        'valid', false, 'status', 'noValidMetering');
    fusionDebug = struct('Mr', Mr, 'Mp', Mp, 'RminBlockCnt', count, ...
        'validBlockCnt', Nvalid, 'C1', NaN, 'C2', NaN, ...
        'lambdaFromLUT', NaN, 'delta', NaN, ...
        'regionStatus', region.status, 'peakStatus', peak.status);

    % 所有回退路径也校验映射配置；空视场只返回空表，不执行正常建表。
    [lambdaLUT, lutInfo] = buildFusionLUT(Nvalid, cfg);
    if Nvalid == 0
        assert(~regionValid && ~peakValid, 'fusionMetering:InconsistentEmptyFov', ...
            '无有效 block 时区域和峰值分支都必须标记为无效。');
        fusion.status = 'noValidBlocks';
        return;
    end

    lambda = lambdaLUT(count + 1);
    fusionDebug.lambdaLUT = lambdaLUT;
    fusionDebug.C1 = lutInfo.C1;
    fusionDebug.C2 = lutInfo.C2;
    fusionDebug.lambdaFromLUT = lambda;
    % 先按有效性回退，避免无效分支的 NaN 进入亮度差计算。
    if regionValid && peakValid
        delta = max(0, Mp - Mr);
        fusion.Mf = Mr + lambda * delta;
        fusion.lambda = lambda;
        fusion.valid = true;
        fusion.status = 'normal';
        fusionDebug.delta = delta;
    elseif regionValid
        fusion.Mf = Mr;
        fusion.lambda = 0;
        fusion.valid = true;
        fusion.status = 'onlyRegionValid';
    elseif peakValid
        fusion.Mf = Mp;
        fusion.valid = true;
        fusion.status = 'onlyPeakValid';
    end
end

function checkStructure(value, fields, name)
    assert(isstruct(value) && isscalar(value), ...
        'fusionMetering:InvalidStructure', '%s 必须为标量结构体。', name);
    assert(all(isfield(value, fields)), ...
        'fusionMetering:MissingFields', '%s 缺少必需字段。', name);
end

function value = checkCount(value, name)
    assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value >= 0 && double(value) == floor(double(value)), ...
        'fusionMetering:InvalidBlockCount', '%s 必须为非负、有限的整数数值标量。', name);
    value = double(value);
end

function value = checkValidFlag(value, name)
    assert((islogical(value) || isnumeric(value)) && isreal(value) && ...
        isscalar(value) && isfinite(value) && (value == 0 || value == 1), ...
        'fusionMetering:InvalidFlag', '%s 必须为逻辑标量或数值 0/1 标量。', name);
    value = logical(value);
end

function value = checkBrightness(value, valid, name)
    assert(isnumeric(value) && isreal(value) && isscalar(value), ...
        'fusionMetering:InvalidBrightness', '%s 必须为实数数值标量。', name);
    value = double(value);
    if valid
        assert(isfinite(value) && value >= 0 && value <= 255, ...
            'fusionMetering:InvalidBrightness', ...
            '分支有效时 %s 必须有限且在 0~255 范围内。', name);
    end
end

function checkStatus(value, name)
    assert((ischar(value) && isrow(value) && ~isempty(value)) || ...
        (isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value) > 0), ...
        'fusionMetering:InvalidStatus', '%s 必须为非空字符行向量或字符串标量。', name);
end
