function result = runRegionalReciprocalTests(outputDir)
%RUNREGIONALRECIPROCALTESTS 平均值边界、区域回退、同帧对比及四种表长报告。
    projectDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if nargin < 1, outputDir = fullfile(projectDir, 'tests', 'results', 'regional_reciprocal'); end
    oldPath = path; restore = onCleanup(@() path(oldPath));
    addpath(fullfile(projectDir, 'float'), fullfile(projectDir, 'float', 'tests'));
    weight = fullfile(projectDir, '权重配置文件', '圆形有效视场权重_16×16.txt');
    cfg = createMeteringConfig();
    cfg.regionMeanMethod = 'division';
    cfg.alphaMethod = 'lut2d';
    [luts, cfg, valid] = loadMeteringLUTs(cfg, [1080, 1920], weight);
    lutCfg = cfg; lutCfg.regionMeanMethod = 'reciprocal_lut';
    checks = {};
    for d = [0.25, 1, 64]
        [v, debug] = computeRegionalMean(100*d, d, lutCfg, luts);
        check(abs(v - 100*512/513) < 1e-12 && debug.address == 0, 'scale-invariant power-of-two example');
    end
    for exponent = [-12, -2, 0, 6, 20]
        for j = 0:256
            boundary = 1 + j/256;
            for m = [boundary-eps(boundary), boundary, boundary+eps(boundary)]
                d = pow2(m, exponent);
                [v, debug] = computeRegionalMean(123.25*d, d, lutCfg, luts);
                check(debug.address >= 0 && debug.address <= 255, 'boundary address bounds');
                check(abs(v-123.25) <= 123.25/513 + 1e-10, 'midpoint error bound');
                check(abs(pow2(debug.normalizedDenominator, debug.exponent)-d) <= eps(d), 'binary normalization');
            end
        end
    end
    [v, debug] = computeRegionalMean(0, 0.25, lutCfg, luts);
    check(v == 0 && debug.exponent == -2, 'zero numerator and negative exponent');
    [v, debug] = computeRegionalMean(255*(1+0.999/256), 1+0.999/256, lutCfg, luts);
    check(v == 255 && debug.rawMean > 255 && debug.address == 0, 'rawMean before saturation');
    oldCfg = rmfield(cfg, 'regionMeanMethod');
    [v, debug] = computeRegionalMean(25, 0.25, oldCfg, struct());
    check(v == 100 && strcmp(debug.method, 'division') && isnan(debug.address), 'legacy division default');
    fail(@() computeRegionalMean(1, 0, lutCfg, luts), '');
    fail(@() computeRegionalMean(-1, 1, lutCfg, luts), '');
    fail(@() computeRegionalMean(Inf, 1, lutCfg, luts), '');
    fail(@() computeRegionalMean(1, NaN, lutCfg, luts), '');
    bad = cfg; bad.regionMeanMethod = 'unknown';
    fail(@() computeRegionalMean(1, 1, bad, luts), 'computeRegionalMean:InvalidMethod');
    fail(@() computeRegionalMean(1, 1, lutCfg, struct()), 'computeRegionalMean:InvalidLUT');
    badLuts = luts; badLuts.reciprocal = luts.reciprocal.';
    fail(@() computeRegionalMean(1, 1, lutCfg, badLuts), 'computeRegionalMean:InvalidLUT');
    badLuts = luts; badLuts.reciprocal(1) = NaN;
    fail(@() computeRegionalMean(1, 1, lutCfg, badLuts), 'computeRegionalMean:InvalidCoefficient');
    masks = struct('center', logical([1,0]), 'edge', logical([0,1]));
    prep = struct('Bi', [69.5,100.49], 'Ri', [1,1], 'validMask', true(1,2));
    [region, debug] = regionalMetering(prep, masks, lutCfg, luts);
    check(region.alphaAddr == floor(region.Lp+0.5)*256+floor(region.Lc+0.5) && ...
        ~isempty(fieldnames(debug.meanCenter)), 'alpha/debug use LUT means');
    check(region.alpha == luts.alpha(region.alphaAddr+1), 'own alpha lookup');
    exact = regionalMetering(prep, masks, cfg, luts);
    check(exact.alphaAddr ~= region.alphaAddr, 'half-integer address change');
    for k = 1:3
        fallback = prep;
        if k ~= 2, fallback.Ri(2) = 0; end
        if k ~= 1, fallback.Ri(1) = 0; end
        tables = luts;
        if k == 3, tables = struct(); end
        [r, dbg] = regionalMetering(fallback, masks, lutCfg, tables);
        states = {'onlyCenterValid', 'onlyEdgeValid', 'noReliableBlocks'};
        check(strcmp(r.status, states{k}), 'fallback status');
        check(isempty(fieldnames(dbg.meanCenter)) == (k ~= 1) && ...
            isempty(fieldnames(dbg.meanEdge)) == (k ~= 2), 'invalid means skip LUT');
        if k == 3, check(~r.valid && isnan(r.Mr), 'invalid remains NaN'); end
        if k == 1, check(r.Mr == r.Lc && r.alpha == 1, 'center fallback'); end
        if k == 2, check(r.Mr == r.Lp && r.alpha == 0, 'edge fallback'); end
    end
    thresholdCfg = lutCfg; thresholdCfg.sumWMin = 1;
    r = regionalMetering(prep, masks, thresholdCfg, struct());
    check(~r.valid, 'strict sumWMin equality');
    prep.Bi(:) = 0;
    [r, dbg] = regionalMetering(prep, masks, lutCfg, luts);
    check(r.valid && r.Mr == 0 && strcmp(r.status,'blackFrame') && dbg.blackFrame, 'black frame');
    center = false(size(valid)); center(find(valid, 1)) = true;
    realMasks = struct('center', center, 'edge', valid & ~center);
    fullPrep = struct('Bi', 100.49*ones(size(valid)), 'Ri', ones(size(valid)), ...
        'validMask', valid, 'validBlockCnt', nnz(valid), 'RminBlockCnt', 0);
    fullPrep.Bi(center) = 69.5;
    peak = peakMetering(fullPrep, cfg);
    originalCfg = cfg;
    comparison = compareRegionalMeanMethods(fullPrep, realMasks, cfg, luts, peak);
    check(isequal(cfg, originalCfg) && comparison.alphaAddressChanged, 'comparison preserves cfg and detects address');
    check(comparison.delta.Mf == comparison.reciprocal_lut.fusion.Mf - ...
        comparison.division.fusion.Mf, 'comparison delta direction');
    for name = {'division','reciprocal_lut'}
        b = comparison.(name{1});
        check(b.fusion.Mf == b.region.Mr + b.fusion.lambda*max(0,peak.Mp-b.region.Mr), 'existing fusion formula');
    end
    fallbackPrep = fullPrep; fallbackPrep.Ri(realMasks.edge) = 0;
    comparison = compareRegionalMeanMethods(fallbackPrep, realMasks, cfg, luts, peak);
    check(isnan(comparison.delta.Lp) && ~comparison.alphaAddressChanged && ...
        ~comparison.statusChanged && strcmp(comparison.reciprocal_lut.region.status, ...
        'onlyCenterValid'), 'comparison single-region fallback');
    fallbackPrep.Ri(:) = 0;
    comparison = compareRegionalMeanMethods(fallbackPrep, realMasks, cfg, luts, peak);
    check(isnan(comparison.delta.Lc) && isnan(comparison.delta.Mr) && ...
        comparison.delta.Mf == 0 && ~comparison.alphaAddressChanged && ...
        ~comparison.statusChanged, 'comparison invalid region and valid peak');
    check(comparison.reciprocal_lut.fusion.Mf == peak.Mp && ...
        strcmp(comparison.reciprocal_lut.fusion.status, 'onlyPeakValid'), 'comparison fusion fallback');
    report = reportRegionalReciprocalError(outputDir);
    result = struct('passed', numel(checks), 'checks', {checks}, 'report', report);
    if ~isfolder(outputDir), mkdir(outputDir); end
    save(fullfile(outputDir, 'regional_reciprocal_tests.mat'), 'result');
    fprintf('REGIONAL_RECIPROCAL_PASS=%d\n', result.passed);

    function check(condition, label)
        assert(condition, 'runRegionalReciprocalTests:Failed', '%s', label);
        checks{end+1} = label;
    end
    function fail(operation, identifier)
        thrown = false;
        try
            operation();
        catch exception
            thrown = isempty(identifier) || strcmp(exception.identifier, identifier);
            if ~thrown, rethrow(exception); end
        end
        check(thrown, ['reject ',identifier]);
    end
end
