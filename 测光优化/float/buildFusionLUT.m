function [lambdaLUT, lutInfo] = buildFusionLUT(validBlockCnt, cfg)
%BUILDFUSIONLUT 第四阶段严重高光 block 数量到融合权重的查找表。
% 将占比阈值乘有效 block 数并 round 后建表；下标 n+1 对应数量 n。
% 缓存最近一次配置，稳定配置直接复用，不逐帧计算占比或线性映射。
% 无有效 block 时返回 1×0 double 空表、NaN 阈值，仍严格校验配置。

    assert(isnumeric(validBlockCnt) && isreal(validBlockCnt) && ...
        isscalar(validBlockCnt) && isfinite(validBlockCnt) && ...
        validBlockCnt >= 0 && double(validBlockCnt) == floor(double(validBlockCnt)), ...
        'buildFusionLUT:InvalidBlockCount', ...
        'validBlockCnt 必须为非负、有限的整数数值标量。');
    assert(isstruct(cfg) && isscalar(cfg), ...
        'buildFusionLUT:InvalidConfig', 'cfg 必须为标量结构体。');
    names = {'fusionP1', 'fusionP2', 'lambdaMax'};
    assert(all(isfield(cfg, names)), ...
        'buildFusionLUT:MissingConfig', ...
        'cfg 必须包含 fusionP1、fusionP2 和 lambdaMax。');
    for k = 1:numel(names)
        value = cfg.(names{k});
        assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value), ...
            'buildFusionLUT:InvalidParameter', ...
            'cfg.%s 必须为有限的实数数值标量。', names{k});
    end
    Nvalid = double(validBlockCnt);
    P1 = double(cfg.fusionP1);
    P2 = double(cfg.fusionP2);
    lambdaMax = double(cfg.lambdaMax);
    assert(0 <= P1 && P1 < P2 && P2 <= 1, ...
        'buildFusionLUT:InvalidThresholds', ...
        '必须满足 0 <= fusionP1 < fusionP2 <= 1。');
    assert(0 <= lambdaMax && lambdaMax <= 1, ...
        'buildFusionLUT:InvalidLambdaMax', 'lambdaMax 必须在 0~1 范围内。');

    persistent cachedParams cachedLUT cachedInfo
    params = [Nvalid, P1, P2, lambdaMax];
    if isequal(params, cachedParams)
        lambdaLUT = cachedLUT;
        lutInfo = cachedInfo;
        return;
    end

    lutInfo = struct('validBlockCnt', Nvalid, 'C1', NaN, 'C2', NaN, ...
        'P1', P1, 'P2', P2, 'lambdaMax', lambdaMax);
    lambdaLUT = zeros(1, 0);
    if Nvalid > 0
        C1 = round(P1 * Nvalid);
        C2 = round(P2 * Nvalid);
        assert(0 <= C1 && C1 < C2 && C2 <= Nvalid, ...
            'buildFusionLUT:CollapsedThresholds', ...
            '取整后须满足 0 <= C1 < C2 <= Nvalid，请调整 fusionP1/fusionP2 或有效视场。');
        n = 0:Nvalid;
        lambdaLUT = zeros(1, Nvalid + 1);
        linearMask = n > C1 & n < C2;
        lambdaLUT(linearMask) = lambdaMax * (n(linearMask) - C1) / (C2 - C1);
        lambdaLUT(n >= C2) = lambdaMax;
        lutInfo.C1 = C1;
        lutInfo.C2 = C2;
    end
    cachedParams = params;
    cachedLUT = lambdaLUT;
    cachedInfo = lutInfo;
end
