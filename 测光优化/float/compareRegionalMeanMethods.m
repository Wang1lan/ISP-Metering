function meanComparison = compareRegionalMeanMethods(prep, regionMask, cfg, luts, peak)
%COMPAREREGIONALMEANMETHODS 同帧两路诊断；不修改调用者 cfg，不重算预处理/峰值。
% 两路分别用自己的 Lc/Lp 查 alpha 并融合；差值统一为 LUT - division。

    methods = {'division', 'reciprocal_lut'};
    for k = 1:numel(methods)
        localCfg = cfg;
        localCfg.regionMeanMethod = methods{k};
        localCfg.compareRegionMean = false;
        [branch.region, branch.debug] = regionalMetering(prep, regionMask, localCfg, luts);
        [branch.fusion, branch.fusionDebug] = fusionMetering( ...
            prep, branch.region, peak, localCfg, luts);
        meanComparison.(methods{k}) = branch;
    end
    exact = meanComparison.division;
    approximate = meanComparison.reciprocal_lut;
    for name = {'Lc', 'Lp', 'alpha', 'Mr'}
        meanComparison.delta.(name{1}) = ...
            approximate.region.(name{1}) - exact.region.(name{1});
    end
    meanComparison.delta.Mf = approximate.fusion.Mf - exact.fusion.Mf;
    meanComparison.alphaAddressChanged = ...
        isfinite(exact.region.alphaAddr) && isfinite(approximate.region.alphaAddr) && ...
        exact.region.alphaAddr ~= approximate.region.alphaAddr;
    meanComparison.statusChanged = ~strcmp(exact.region.status, approximate.region.status);
end
