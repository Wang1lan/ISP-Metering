function tests = testFusionMetering
%TESTFUSIONMETERING 第四阶段测光融合的 MATLAB R2022a 行为测试。
% 从项目根目录运行：
%   results = runtests(fullfile('float', 'tests', 'testFusionMetering.m'));
%   assertSuccess(results);
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    floatDir = fileparts(fileparts(mfilename('fullpath')));
    testCase.TestData.ProjectDir = fileparts(floatDir);
    previousPath = path;
    addpath(floatDir, fullfile(testCase.TestData.ProjectDir, 'tests', 'reference'));
    testCase.addTeardown(@path, previousPath);
end

function testReferenceALUTReferenceBoundariesAndShape(testCase)
    cfg = referenceFixtureConfig();
    [lut, info] = refA_buildFusionLUT(1000, cfg);
    verifyClass(testCase, lut, 'double');
    verifySize(testCase, lut, [1, 1001]);
    verifyEqual(testCase, [info.validBlockCnt, info.C1, info.C2, ...
        info.P1, info.P2, info.lambdaMin, info.lambdaMax], ...
        [1000, 20, 100, 0.02, 0.10, 0.20, 0.50]);
    for name = {'validBlockCnt', 'C1', 'C2', 'P1', 'P2', 'lambdaMin', 'lambdaMax'}
        verifyClass(testCase, info.(name{1}), 'double');
    end
    counts = [0, 20, 21, 60, 99, 100, 1000];
    expected = [0.2, 0.2, 0.2 + 0.3 / 80, 0.35, ...
        0.2 + 0.3 * 79 / 80, 0.5, 0.5];
    verifyEqual(testCase, lut(counts + 1), expected, 'AbsTol', 1e-12);
    verifyGreaterThanOrEqual(testCase, min(diff(lut)), -1e-14);
    verifyGreaterThanOrEqual(testCase, min(lut), cfg.lambdaMin);
    verifyLessThanOrEqual(testCase, max(lut), cfg.lambdaMax);

    % MATLAB round 在半个 block 处向上取整，按取整后的数量阈值验收。
    [rounded, roundedInfo] = refA_buildFusionLUT(25, cfg);
    verifyEqual(testCase, [roundedInfo.C1, roundedInfo.C2], [1, 3]);
    verifyEqual(testCase, rounded(3), 0.35, 'AbsTol', 1e-12);
end

function testReferenceALUTCacheKeysAndRepeatedCalls(testCase)
    cfg = referenceFixtureConfig();
    [base, baseInfo] = refA_buildFusionLUT(1000, cfg);
    [again, againInfo] = refA_buildFusionLUT(1000, cfg);
    verifyEqual(testCase, again, base);
    verifyEqual(testCase, againInfo, baseInfo);

    [larger, largerInfo] = refA_buildFusionLUT(2000, cfg);
    verifySize(testCase, larger, [1, 2001]);
    verifyEqual(testCase, [largerInfo.C1, largerInfo.C2], [40, 200]);
    verifyEqual(testCase, larger(121), 0.35, 'AbsTol', 1e-12);

    verifyEqual(testCase, refA_buildFusionLUT(1000, cfg), base);
    changed = cfg;
    changed.fusionP1 = 0.04;
    [newP1, infoP1] = refA_buildFusionLUT(1000, changed);
    verifyEqual(testCase, infoP1.C1, 40);
    verifyEqual(testCase, newP1(61), 0.2 + 0.3 * 20 / 60, 'AbsTol', 1e-12);

    verifyEqual(testCase, refA_buildFusionLUT(1000, cfg), base);
    changed = cfg;
    changed.fusionP2 = 0.12;
    [newP2, infoP2] = refA_buildFusionLUT(1000, changed);
    verifyEqual(testCase, infoP2.C2, 120);
    verifyEqual(testCase, newP2(61), 0.32, 'AbsTol', 1e-12);

    verifyEqual(testCase, refA_buildFusionLUT(1000, cfg), base);
    changed = cfg;
    changed.lambdaMax = 0.75;
    [newMax, infoMax] = refA_buildFusionLUT(1000, changed);
    verifyEqual(testCase, infoMax.lambdaMax, 0.75);
    verifyEqual(testCase, newMax(61), 0.475, 'AbsTol', 1e-12);

    % 不清除持久缓存，只改变下限也必须重建表。
    verifyEqual(testCase, refA_buildFusionLUT(1000, cfg), base);
    changed = cfg;
    changed.lambdaMin = 0.3;
    [newMin, infoMin] = refA_buildFusionLUT(1000, changed);
    verifyEqual(testCase, [newMin(1), newMin(61), infoMin.lambdaMin], ...
        [0.3, 0.4, 0.3], 'AbsTol', 1e-12);
    verifyEqual(testCase, refA_buildFusionLUT(1000, cfg), base);

    changed.lambdaMin = changed.lambdaMax;
    [flat, flatInfo] = refA_buildFusionLUT(1000, changed);
    verifyEqual(testCase, flatInfo.lambdaMin, cfg.lambdaMax);
    verifyEqual(testCase, flat, cfg.lambdaMax * ones(1, 1001));

    [restored, restoredInfo] = refA_buildFusionLUT(1000, cfg);
    verifyEqual(testCase, restored, base);
    verifyEqual(testCase, restoredInfo, baseInfo);
end

function testReferenceAZeroValidBlocksHasNoNormalLUT(testCase)
    [lut, info] = refA_buildFusionLUT(0, referenceFixtureConfig());
    verifyClass(testCase, lut, 'double');
    verifySize(testCase, lut, [1, 0]);
    verifyEqual(testCase, info.validBlockCnt, 0);
    verifyTrue(testCase, isnan(info.C1) && isnan(info.C2));
    verifyEqual(testCase, info.lambdaMin, 0.2);
    cfg = referenceFixtureConfig();
    cfg.lambdaMin = 0;
    verifyError(testCase, @() refA_buildFusionLUT(0, cfg), ...
        'refA_buildFusionLUT:InvalidLambdaMin');
end

function testReferenceALUTRejectsInvalidCountsAndConfiguration(testCase)
    cfg = referenceFixtureConfig();
    for count = {-1, 1.5, NaN, Inf, 1i, [], [1, 2]}
        verifyFusionError(testCase, @() refA_buildFusionLUT(count{1}, cfg));
    end
    invalid = {'fusionP1', -0.01; 'fusionP1', 0.10; ...
        'fusionP2', 0; 'fusionP2', 1.01; 'lambdaMax', -0.01; ...
        'lambdaMax', 1.01; 'fusionP1', NaN; 'fusionP2', Inf; ...
        'lambdaMax', 1i; 'fusionP1', [0.01, 0.02]};
    for k = 1:size(invalid, 1)
        changed = cfg;
        changed.(invalid{k, 1}) = invalid{k, 2};
        verifyFusionError(testCase, @() refA_buildFusionLUT(1000, changed));
    end
    for name = {'fusionP1', 'fusionP2', 'lambdaMax'}
        verifyFusionError(testCase, @() refA_buildFusionLUT(1000, rmfield(cfg, name{1})));
    end
    verifyError(testCase, @() refA_buildFusionLUT(1000, rmfield(cfg, 'lambdaMin')), ...
        'refA_buildFusionLUT:MissingConfig');
    for value = {0, -0.1, 0.6}
        changed = cfg;
        changed.lambdaMin = value{1};
        verifyError(testCase, @() refA_buildFusionLUT(1000, changed), ...
            'refA_buildFusionLUT:InvalidLambdaMin');
    end
    for value = {NaN, Inf, 1i, [], [0.1, 0.2]}
        changed = cfg;
        changed.lambdaMin = value{1};
        verifyError(testCase, @() refA_buildFusionLUT(1000, changed), ...
            'refA_buildFusionLUT:InvalidParameter');
    end
    verifyFusionError(testCase, @() refA_buildFusionLUT(1, cfg));
end

function testNormalFusionAndNondecreasingCount(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyFusionShape(testCase, fusion, debug);
    verifyTrue(testCase, fusion.valid);
    verifyEqual(testCase, fusion.status, 'normal');
    verifyEqual(testCase, [fusion.Mf, fusion.lambda, debug.delta], ...
        [122, 0.35, 120], 'AbsTol', 1e-12);
    verifyEqual(testCase, [debug.Mr, debug.Mp, debug.RminBlockCnt, ...
        debug.validBlockCnt, debug.C1, debug.C2, debug.lambdaFromLUT], ...
        [80, 200, 60, 1000, 20, 100, 0.35], 'AbsTol', 1e-12);
    verifyEqual(testCase, debug.regionStatus, region.status);
    verifyEqual(testCase, debug.peakStatus, peak.status);

    region.Mr = 80.25;
    peak.Mp = 200.75;
    fractional = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, fractional.Mf, 122.425, 'AbsTol', 1e-12);
    verifyClass(testCase, fractional.Mf, 'double');
    region.Mr = 80;
    peak.Mp = 200;

    counts = [0, 20, 21, 60, 99, 100, 1000];
    values = zeros(size(counts));
    for k = 1:numel(counts)
        prep.RminBlockCnt = counts(k);
        result = fusionMetering(prep, region, peak, cfg, luts);
        values(k) = result.Mf;
        verifyGreaterThanOrEqual(testCase, result.Mf, region.Mr);
        verifyLessThanOrEqual(testCase, result.Mf, peak.Mp);
    end
    verifyGreaterThanOrEqual(testCase, min(diff(values)), -1e-12);
    verifyEqual(testCase, values(4), 122, 'AbsTol', 1e-12);

    % 零严重高光计数仍采用正下限；峰值不高于区域值时不下拉。
    prep.RminBlockCnt = 0;
    peak.Mp = 180;
    lowCount = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, [lowCount.Mf, lowCount.lambda], [100, 0.2], 'AbsTol', 1e-12);
    for mp = [70, 80]
        peak.Mp = mp;
        noIncrease = fusionMetering(prep, region, peak, cfg, luts);
        verifyEqual(testCase, [noIncrease.Mf, noIncrease.lambda], ...
            [80, 0.2], 'AbsTol', 1e-12);
    end
end

function testPeakNeverLowersRegionAndLambdaLimits(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    region.Mr = 120;
    peak.Mp = 80;
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, [fusion.Mf, debug.delta], [120, 0]);
    verifyEqual(testCase, fusion.lambda, 0.35, 'AbsTol', 1e-12);

    region.Mr = 80;
    peak.Mp = 200;
    cfg.lambdaMax = 0;
    verifyError(testCase, @() fusionMetering(prep, region, peak, cfg, luts), ...
        'fusionMetering:ConfigLUTMismatch');

    cfg.lambdaMax = 1;
    luts = syntheticLoadedLuts(cfg, prep.validBlockCnt);
    fusion = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, [fusion.Mf, fusion.lambda], [152, 0.6], 'AbsTol', 1e-12);
    prep.RminBlockCnt = 100;
    fusion = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, [fusion.Mf, fusion.lambda], [200, 1]);
end

function testFallbacksAndCompleteDebug(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    invalidCfg = cfg;
    invalidCfg.fusionP1 = invalidCfg.fusionP2;
    peak.valid = false;
    peak.Mp = NaN;
    peak.status = 'noPeak';
    verifyFusionError(testCase, @() fusionMetering(prep, region, peak, invalidCfg, luts));
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyFusionShape(testCase, fusion, debug);
    verifyEqual(testCase, [fusion.Mf, fusion.lambda], [region.Mr, 0]);
    verifyTrue(testCase, fusion.valid);
    verifyEqual(testCase, fusion.status, 'onlyRegionValid');
    verifyTrue(testCase, isnan(debug.Mp) && isnan(debug.delta));
    verifyEqual(testCase, debug.lambdaFromLUT, 0.35, 'AbsTol', 1e-12);
    verifyEqual(testCase, debug.peakStatus, peak.status);

    region.valid = false;
    region.Mr = NaN;
    region.status = 'noRegion';
    peak.valid = true;
    peak.Mp = 200;
    verifyFusionError(testCase, @() fusionMetering(prep, region, peak, invalidCfg, luts));
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyFusionShape(testCase, fusion, debug);
    verifyEqual(testCase, fusion.Mf, 200);
    verifyTrue(testCase, isnan(fusion.lambda) && isnan(debug.delta));
    verifyTrue(testCase, fusion.valid);
    verifyEqual(testCase, fusion.status, 'onlyPeakValid');
    verifyEqual(testCase, debug.lambdaFromLUT, 0.35, 'AbsTol', 1e-12);
    verifyEqual(testCase, debug.regionStatus, region.status);

    peak.valid = false;
    peak.Mp = NaN;
    verifyFusionError(testCase, @() fusionMetering(prep, region, peak, invalidCfg, luts));
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyFusionShape(testCase, fusion, debug);
    verifyFalse(testCase, fusion.valid);
    verifyEqual(testCase, fusion.status, 'noValidMetering');
    verifyTrue(testCase, isnan(fusion.Mf) && isnan(fusion.lambda) && isnan(debug.delta));
    verifyEqual(testCase, debug.lambdaFromLUT, 0.35, 'AbsTol', 1e-12);

    prep.validBlockCnt = 0;
    prep.RminBlockCnt = 0;
    peak.validBlockCnt = 0;

    [fusion, debug] = fusionMetering(prep, region, peak, struct(), struct());
    verifyFusionShape(testCase, fusion, debug);
    verifyFalse(testCase, fusion.valid);
    verifyEqual(testCase, fusion.status, 'noValidBlocks');
    verifyTrue(testCase, isnan(fusion.Mf) && isnan(fusion.lambda));
    verifyTrue(testCase, all(isnan([debug.C1, debug.C2, ...
        debug.lambdaFromLUT, debug.delta])));
end

function testZeroBrightnessIsValidAndOutputsAreDouble(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    region.Mr = uint8(0);
    peak.Mp = uint8(0);
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyTrue(testCase, fusion.valid);
    verifyEqual(testCase, fusion.Mf, 0);
    verifyEqual(testCase, fusion.status, 'normal');
    verifyEqual(testCase, debug.delta, 0);
    verifyFusionShape(testCase, fusion, debug);
end

function testInvalidBranchBrightnessNeedsOnlyRealNumericScalar(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    region.valid = false;
    for brightness = {NaN, Inf, -5, 256}
        region.Mr = brightness{1};
        fusion = fusionMetering(prep, region, peak, cfg, luts);
        verifyTrue(testCase, fusion.valid);
        verifyEqual(testCase, fusion.Mf, peak.Mp);
        verifyEqual(testCase, fusion.status, 'onlyPeakValid');
    end
    for brightness = {'invalid', [], [1, 2], 1i}
        region.Mr = brightness{1};
        verifyFusionError(testCase, @() fusionMetering(prep, region, peak, cfg, luts));
    end
    region.Mr = 80;
    region.valid = true;
    peak.valid = false;
    for brightness = {NaN, Inf, -5, 256}
        peak.Mp = brightness{1};
        fusion = fusionMetering(prep, region, peak, cfg, luts);
        verifyEqual(testCase, fusion.Mf, region.Mr);
        verifyEqual(testCase, fusion.status, 'onlyRegionValid');
    end
    peak.Mp = 'invalid';
    verifyFusionError(testCase, @() fusionMetering(prep, region, peak, cfg, luts));
end

function testValidUpstreamFallbackAndStatusText(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    region.status = 'onlyCenterValid';
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, fusion.status, 'normal');
    verifyEqual(testCase, fusion.Mf, 122, 'AbsTol', 1e-12);
    verifyEqual(testCase, debug.regionStatus, region.status);

    region.status = "onlyEdgeValid";
    peak.status = "zeroPeakBrightness";
    [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, fusion.status, 'normal');
    verifyEqual(testCase, fusion.Mf, 122, 'AbsTol', 1e-12);
    verifyEqual(testCase, debug.regionStatus, region.status);
    verifyEqual(testCase, debug.peakStatus, peak.status);
    verifyFusionShape(testCase, fusion, debug);
end

function testInvalidFusionInputsAreRejected(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    for count = {-1, 1.5, NaN, Inf, 1001, [], [1, 2]}
        changed = prep;
        changed.RminBlockCnt = count{1};
        verifyFusionError(testCase, @() fusionMetering(changed, region, peak, cfg, luts));
    end
    changed = prep;
    changed.validBlockCnt = 999;
    verifyFusionError(testCase, @() fusionMetering(changed, region, peak, cfg, luts));
    changed = peak;
    changed.validBlockCnt = 999;
    verifyFusionError(testCase, @() fusionMetering(prep, region, changed, cfg, luts));
    for value = {NaN, Inf, -1, 256, 1i, [], [80, 90]}
        changed = region;
        changed.Mr = value{1};
        verifyFusionError(testCase, @() fusionMetering(prep, changed, peak, cfg, luts));
        changed = peak;
        changed.Mp = value{1};
        verifyFusionError(testCase, @() fusionMetering(prep, region, changed, cfg, luts));
    end
    for flag = {2, NaN, [], [0, 1]}
        changed = region;
        changed.valid = flag{1};
        verifyFusionError(testCase, @() fusionMetering(prep, changed, peak, cfg, luts));
    end
    changed = prep;
    changed.validBlockCnt = 0;
    changed.RminBlockCnt = 0;
    changedPeak = peak;
    changedPeak.validBlockCnt = 0;
    verifyFusionError(testCase, @() fusionMetering(changed, region, changedPeak, cfg, luts));
    changed.validBlockCnt = 1;
    changedPeak.validBlockCnt = 1;
    changed.RminBlockCnt = 0;
    changedRegion = region;
    changedRegion.valid = false;
    changedRegion.Mr = NaN;
    changedPeak.valid = false;
    changedPeak.Mp = NaN;
    verifyFusionError(testCase, @() fusionMetering( ...
        changed, changedRegion, changedPeak, cfg, luts));

    for name = {'validBlockCnt', 'RminBlockCnt'}
        verifyFusionError(testCase, @() fusionMetering(rmfield(prep, name{1}), region, peak, cfg, luts));
    end
    for name = {'Mr', 'valid', 'status'}
        verifyFusionError(testCase, @() fusionMetering(prep, rmfield(region, name{1}), peak, cfg, luts));
    end
    for name = {'Mp', 'valid', 'status', 'validBlockCnt'}
        verifyFusionError(testCase, @() fusionMetering(prep, region, rmfield(peak, name{1}), cfg, luts));
    end
    verifyFusionError(testCase, @() fusionMetering(prep, region, peak, rmfield(cfg, 'fusionP1'), luts));
    verifyError(testCase, @() fusionMetering(prep, region, peak, rmfield(cfg, 'lambdaMin'), luts), ...
        'fusionMetering:MissingFields');
end

function testFusionReadsOnlyDocumentedScalars(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    plain = fusionMetering(prep, region, peak, cfg, luts);
    prep.Bi = NaN;
    prep.Ri = 'not a reliability map';
    prep.validMask = [];
    withUnusedFields = fusionMetering(prep, region, peak, cfg, luts);
    verifyEqual(testCase, withUnusedFields, plain);
end

function testLoadedDefaultsAndNineImagesThroughAllFourStages(testCase)
    projectDir = testCase.TestData.ProjectDir;
    weightDir = fullfile(projectDir, '权重配置文件');
    [luts, cfg, validMask] = loadMeteringLUTs(createMeteringConfig(), [1080,1920], ...
        fullfile(weightDir, '圆形有效视场权重_16×16.txt'));
    verifyEqual(testCase, [cfg.fusionP1, cfg.fusionP2, cfg.lambdaMin, cfg.lambdaMax], ...
        [0.002, 0.03, 0.3, 0.8]);
    masks = loadRegionMasks(fullfile(weightDir, '中心视场权重_16×16_75.txt'), ...
        fullfile(weightDir, '边缘视场权重_16×16_25.txt'), [1080,1920], cfg.blockSize, validMask);
    for k = 1:9
        name = sprintf('testImg_%d.bmp', k);
        rgb = imread(fullfile(projectDir, 'testImg', name));
        prep = meteringPreprocess(rgb, validMask, cfg, luts);
        region = regionalMetering(prep, masks, cfg, luts);
        peak = peakMetering(prep, cfg);
        [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
        verifyFusionShape(testCase, fusion, debug);
        verifyEqual(testCase, peak.validBlockCnt, prep.validBlockCnt);
        verifyTrue(testCase, region.valid && peak.valid && fusion.valid);
        reference = refA_buildFusionLUT(prep.validBlockCnt, cfg);
        expectedLambda = reference(prep.RminBlockCnt + 1);
        expectedMf = region.Mr + expectedLambda * max(0, peak.Mp - region.Mr);
        verifyEqual(testCase, [debug.C1, debug.C2], [11, 159]);
        verifyEqual(testCase, [fusion.lambda, debug.lambdaFromLUT], ...
            [expectedLambda, expectedLambda], 'AbsTol', 1e-12);
        verifyEqual(testCase, fusion.Mf, expectedMf, 'AbsTol', 1e-12);
        fprintf('%s: n=%d, Mr=%.6f, Mp=%.6f, lambda=%.6f, Mf=%.6f\n', ...
            name, prep.RminBlockCnt, region.Mr, peak.Mp, fusion.lambda, fusion.Mf);
    end
end

function testLoadedTableCountAndParameterMismatchRejected(testCase)
    [prep, region, peak, cfg, luts] = syntheticCase();
    changed = luts;
    changed.meta.lambda.Nvalid = 999;
    verifyError(testCase, @() fusionMetering(prep, region, peak, cfg, changed), ...
        'fusionMetering:LUTBlockCountMismatch');
    changed = cfg;
    changed.lambdaMin = 0.3;
    verifyError(testCase, @() fusionMetering(prep, region, peak, changed, luts), ...
        'fusionMetering:ConfigLUTMismatch');
    changed = luts;
    changed.lambda(prep.RminBlockCnt + 1) = NaN;
    verifyError(testCase, @() fusionMetering(prep, region, peak, cfg, changed), ...
        'fusionMetering:InvalidCoefficient');
end

function cfg = referenceFixtureConfig()
% 明确的历史参数测试夹具，不代表当前生产默认值。
    cfg = refA_createMeteringConfig();
    cfg.fusionP1 = 0.02;
    cfg.fusionP2 = 0.10;
    cfg.lambdaMin = 0.20;
    cfg.lambdaMax = 0.50;
end

function luts = syntheticLoadedLuts(cfg, Nvalid)
% 单元测试在初始化夹具中创建输入；逐帧生产函数仅消费该表。
    [reference, info] = refA_buildFusionLUT(Nvalid, cfg);
    luts.lambda = reference(:);
    luts.meta.lambda = struct('Nvalid', Nvalid, 'P1', info.P1, 'P2', info.P2, ...
        'C1', info.C1, 'C2', info.C2, 'lambdaMin', info.lambdaMin, 'lambdaMax', info.lambdaMax);
end
function [prep, region, peak, cfg, luts] = syntheticCase()
    cfg = referenceFixtureConfig();
    luts = syntheticLoadedLuts(cfg, 1000);
    prep = struct('validBlockCnt', 1000, 'RminBlockCnt', 60);
    region = struct('Mr', 80, 'valid', true, 'status', 'normal');
    peak = struct('Mp', 200, 'valid', true, 'status', 'normal', ...
        'validBlockCnt', 1000);
end

function verifyFusionShape(testCase, fusion, debug)
    fusionFields = {'Mf', 'lambda', 'valid', 'status'};
    debugFields = {'Mr', 'Mp', 'RminBlockCnt', 'validBlockCnt', ...
        'C1', 'C2', 'lambdaFromLUT', 'delta', 'regionStatus', 'peakStatus'};
    verifyTrue(testCase, all(isfield(fusion, fusionFields)));
    verifyTrue(testCase, all(isfield(debug, debugFields)));
    for name = {'Mf', 'lambda'}
        verifyClass(testCase, fusion.(name{1}), 'double');
    end
    for name = {'Mr', 'Mp', 'RminBlockCnt', 'validBlockCnt', ...
            'C1', 'C2', 'lambdaFromLUT', 'delta'}
        verifyClass(testCase, debug.(name{1}), 'double');
    end
    verifyClass(testCase, fusion.valid, 'logical');
    verifyClass(testCase, fusion.status, 'char');
    verifyTrue(testCase, ischar(debug.regionStatus) || isstring(debug.regionStatus));
    verifyTrue(testCase, ischar(debug.peakStatus) || isstring(debug.peakStatus));
end

function verifyFusionError(testCase, action)
% 不依赖参数校验顺序，只要求错误归属第四阶段公开函数。
    didThrow = false;
    try
        action();
    catch exception
        didThrow = true;
        verifyTrue(testCase, startsWith(exception.identifier, 'refA_buildFusionLUT:') || ...
            startsWith(exception.identifier, 'fusionMetering:'), exception.message);
    end
    verifyTrue(testCase, didThrow, '非法输入必须抛出异常。');
end
