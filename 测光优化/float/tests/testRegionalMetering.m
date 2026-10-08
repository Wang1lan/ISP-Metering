function tests = testRegionalMetering
%TESTREGIONALMETERING 第二阶段区域测光的 MATLAB R2022a 行为测试。
% 从项目根目录运行：
%   results = runtests(fullfile('float', 'tests', 'testRegionalMetering.m'));
%   assertSuccess(results);
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    floatDir = fileparts(fileparts(mfilename('fullpath')));
    testCase.TestData.ProjectDir = fileparts(floatDir);
    previousPath = path;
    addpath(floatDir, fullfile(testCase.TestData.ProjectDir, 'tests', 'reference'));
    [testCase.TestData.Luts, testCase.TestData.Cfg] = loadMeteringLUTs( ...
        createMeteringConfig(), [1080, 1920], fullfile(testCase.TestData.ProjectDir, ...
        '权重配置文件', '圆形有效视场权重_16×16.txt'));
    testCase.addTeardown(@path, previousPath);

    % 只创建和清理本测试拥有的临时目录，不向项目目录写入 TXT。
    temporaryRoot = tempdir;
    temporaryDir = tempname(temporaryRoot);
    assert(startsWith(temporaryDir, temporaryRoot, 'IgnoreCase', true));
    assert(~isfolder(temporaryDir));
    [created, message] = mkdir(temporaryDir);
    assert(created, message);
    testCase.TestData.TemporaryDir = temporaryDir;
    testCase.addTeardown(@removeOwnedTemporaryDirectory, ...
        temporaryDir, temporaryRoot);
end

function testDefaultConfiguration(testCase)
    cfg = testCase.TestData.Cfg;
    names = {'rho1', 'rho2', 'rho3', 'rho4', 'alphaMin', ...
        'Wc', 'alphaMax', 'LpMin', 'sumWMin', 'centerRatio'};
    expected = [0.5, 0.9, 1.1, 1.5, 0.25, 0.5, 0.75, 1, 0, 0.75];
    for k = 1:numel(names)
        verifyEqual(testCase, cfg.(names{k}), expected(k));
    end
end

function testRealFovSeventyFivePercent(testCase)
    [center, edge, info, valid] = generateRealMasks(testCase, 0.75);
    verifySize(testCase, center, [67, 120]);
    verifyEqual(testCase, nnz(valid), 5314);
    verifyEqual(testCase, nnz(center), 3986);
    verifyEqual(testCase, nnz(edge), 1328);
    verifyPartition(testCase, center, edge, valid);
    expectedInfoFields = {'centerFile'; 'edgeFile'; 'imageSize'; ...
        'blockSize'; 'blockRows'; 'blockCols'; 'viewCenter'; ...
        'validBlockCount'; 'centerBlockCount'; 'edgeBlockCount'; ...
        'targetCenterRatio'; 'actualCenterRatio'; 'actualEdgeRatio'; ...
        'tieBreakRule'};
    verifyEqual(testCase, sort(fieldnames(info)), sort(expectedInfoFields));
    verifyEqual(testCase, info.imageSize, [1080, 1920]);
    verifyEqual(testCase, info.blockSize, 16);
    verifyEqual(testCase, info.blockRows, 67);
    verifyEqual(testCase, info.blockCols, 120);
    verifyEqual(testCase, info.viewCenter, [960.5, 540.5]);
    verifyEqual(testCase, info.validBlockCount, 5314);
    verifyEqual(testCase, info.centerBlockCount, 3986);
    verifyEqual(testCase, info.edgeBlockCount, 1328);
    verifyEqual(testCase, info.targetCenterRatio, 0.75);
    verifyEqual(testCase, info.actualCenterRatio, 3986 / 5314, 'AbsTol', 1e-14);
    verifyEqual(testCase, info.actualEdgeRatio, 1328 / 5314, 'AbsTol', 1e-14);
    verifyNotEmpty(testCase, info.tieBreakRule);
    loaded = loadRegionMasks(info.centerFile, info.edgeFile, [1080, 1920], 16, valid);
    verifyEqual(testCase, loaded.center, center);
    verifyEqual(testCase, loaded.edge, edge);
end

function testRealFovSeventyPercent(testCase)
    [center, edge, info, valid] = generateRealMasks(testCase, 0.70);
    verifyEqual(testCase, nnz(center), 3720);
    verifyEqual(testCase, nnz(edge), 1594);
    verifyEqual(testCase, info.targetCenterRatio, 0.70);
    verifyEqual(testCase, info.actualCenterRatio, 3720 / 5314, 'AbsTol', 1e-14);
    verifyPartition(testCase, center, edge, valid);
end

function testEqualDistancesUseRowScanOrder(testCase)
    folder = newTemporarySubdirectory(testCase);
    file = writeMask(folder, 'valid.txt', true(3));
    [center, edge] = generateRegionMasks(file, 1 / 3, 16, [48, 48], folder);
    % 最先为 (2,2)，距离相同的邻块依次为 (1,2)、(2,1)。
    expected = logical([0, 1, 0; 1, 1, 0; 0, 0, 0]);
    verifyEqual(testCase, center, expected);
    verifyPartition(testCase, center, edge, true(3));
end

function testUsesOriginalImageCenterBeforeCropping(testCase)
    folder = newTemporarySubdirectory(testCase);
    file = writeMask(folder, 'valid.txt', true(2));
    [center, edge, info] = generateRegionMasks(file, 0.5, 16, [35, 32], folder);
    % 原图中心 y=18，下面两块更近；若误用裁剪中心则会选上面两块。
    verifyEqual(testCase, info.viewCenter, [16.5, 18]);
    verifyEqual(testCase, center, logical([0, 0; 1, 1]));
    verifyPartition(testCase, center, edge, true(2));
end

function testTxtRowScanOrderAndRoundTrip(testCase)
    folder = newTemporarySubdirectory(testCase);
    valid = logical([1, 0, 1; 1, 1, 0]);
    file = writeMask(folder, 'valid.txt', valid);
    [center, edge, info] = generateRegionMasks(file, 0.5, 16, [32, 48], folder);
    expectedCenter = logical([1, 0, 0; 0, 1, 0]);
    expectedEdge = logical([0, 0, 1; 1, 0, 0]);
    verifyEqual(testCase, center, expectedCenter);
    verifyEqual(testCase, edge, expectedEdge);
    verifyEqual(testCase, readmatrix(info.centerFile), [1; 0; 0; 0; 1; 0]);
    verifyEqual(testCase, readmatrix(info.edgeFile), [0; 0; 1; 1; 0; 0]);
    for outputFile = {info.centerFile, info.edgeFile}
        lines = regexp(strtrim(fileread(outputFile{1})), '\r\n|\n|\r', 'split');
        verifyNumElements(testCase, lines, 6);
        verifyTrue(testCase, all(cellfun(@(line) ...
            ~isempty(regexp(line, '^[01]$', 'once')), lines)));
    end
    loaded = loadRegionMasks(info.centerFile, info.edgeFile, [32, 48], 16, valid);
    verifyEqual(testCase, loaded.center, expectedCenter);
    verifyEqual(testCase, loaded.edge, expectedEdge);
    verifyPartition(testCase, loaded.center, loaded.edge, valid);
end

function testGenerationRejectsEmptyRegions(testCase)
    folder = newTemporarySubdirectory(testCase);
    for mask = {false(2), logical([1, 0; 0, 0])}
        file = writeMask(folder, 'valid.txt', mask{1});
        verifyThrows(testCase, @() generateRegionMasks(file, 0.75, 16, [32, 32], folder));
    end
    file = writeMask(folder, 'valid.txt', true(2));
    for ratio = [0, 1, 0.01, 0.99]
        verifyThrows(testCase, @() generateRegionMasks(file, ratio, 16, [32, 32], folder));
    end
end

function testGenerationRejectsInvalidFiles(testCase)
    folder = newTemporarySubdirectory(testCase);
    malformed = {[1; 0; 1], [1, 1, 1, 1], [1, 1; 1, 1], ...
        [1; NaN; 0; 1], [1; Inf; 0; 1], [1; 2; 0; 1], [1; -1; 0; 1]};
    for k = 1:numel(malformed)
        file = writeNumericFile(folder, 'invalid.txt', malformed{k});
        verifyThrows(testCase, @() generateRegionMasks(file, 0.5, 16, [32, 32], folder));
    end
    verifyThrows(testCase, @() generateRegionMasks( ...
        fullfile(folder, 'missing.txt'), 0.5, 16, [32, 32], folder));
end

function testGenerationRejectsInvalidGeometryAndRatio(testCase)
    folder = newTemporarySubdirectory(testCase);
    file = writeMask(folder, 'valid.txt', true(2));
    for ratio = {-0.1, 1.1, NaN, Inf, [0.5, 0.6]}
        verifyThrows(testCase, @() generateRegionMasks(file, ratio{1}, 16, [32, 32], folder));
    end
    for blockSize = {0, -16, 1.5, NaN, [16, 16]}
        verifyThrows(testCase, @() generateRegionMasks(file, 0.5, blockSize{1}, [32, 32], folder));
    end
    for imageSize = {32, [32, 32, 3], [0, 32], [-32, 32], ...
            [32.5, 32], [NaN, 32], [15, 32]}
        verifyThrows(testCase, @() generateRegionMasks(file, 0.5, 16, imageSize{1}, folder));
    end
end

function testLoadingRejectsInvalidFiles(testCase)
    folder = newTemporarySubdirectory(testCase);
    centerFile = writeMask(folder, 'center.txt', logical([1, 0; 1, 0]));
    edgeFile = writeMask(folder, 'edge.txt', logical([0, 1; 0, 1]));
    malformed = {[1; 0; 1], [1, 0, 1, 0], [1, 0; 1, 0], ...
        [1; NaN; 1; 0], [1; Inf; 1; 0], [1; 2; 1; 0], [1; -1; 1; 0]};
    for k = 1:numel(malformed)
        badFile = writeNumericFile(folder, 'invalid.txt', malformed{k});
        verifyThrows(testCase, @() loadRegionMasks(badFile, edgeFile, [32, 32], 16, true(2)));
        verifyThrows(testCase, @() loadRegionMasks(centerFile, badFile, [32, 32], 16, true(2)));
    end
    verifyThrows(testCase, @() loadRegionMasks( ...
        fullfile(folder, 'missing.txt'), edgeFile, [32, 32], 16, true(2)));
end

function testLoadingRejectsInvalidCoverageAndDimensions(testCase)
    folder = newTemporarySubdirectory(testCase);
    center = logical([1, 0; 1, 0]);
    edge = ~center;
    centerFile = writeMask(folder, 'center.txt', center);
    edgeFile = writeMask(folder, 'edge.txt', edge);
    verifyThrows(testCase, @() loadRegionMasks(centerFile, centerFile, [32, 32], 16, true(2)));
    verifyThrows(testCase, @() loadRegionMasks(centerFile, edgeFile, [32, 32], 16, false(2)));
    verifyThrows(testCase, @() loadRegionMasks(centerFile, edgeFile, [32, 32], 16, ones(2) * 2));
    verifyThrows(testCase, @() loadRegionMasks(centerFile, edgeFile, [32, 32], 16, [1, 1, 1, 1]));
    % 元素数相同，但给定原图对应 1×4，不能接受 2×2 的有效掩模。
    verifyThrows(testCase, @() loadRegionMasks(centerFile, edgeFile, [16, 64], 16, true(2)));
    edge(1, 2) = false;
    edgeFile = writeMask(folder, 'edge.txt', edge);
    verifyThrows(testCase, @() loadRegionMasks(centerFile, edgeFile, [32, 32], 16, true(2)));
end

function testUniformBrightnessIsOneHundred(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    prep.Bi = uint8(100 * ones(size(prep.Bi)));
    [region, debug] = regionalMetering(prep, masks, cfg, luts);
    verifyRegionFields(testCase, region);
    verifyEqual(testCase, [region.Lc, region.Lp, region.Mr], [100, 100, 100], 'AbsTol', 1e-12);
    verifyEqual(testCase, region.alpha, cfg.Wc);
    verifyEqual(testCase, region.status, 'normal');
    verifyTrue(testCase, region.valid);
    verifyClass(testCase, region.Mr, 'double');
    verifyClass(testCase, region.Lc, 'double');
    verifyClass(testCase, region.Lp, 'double');
    verifyEqual(testCase, rmfield(debug, {'meanCenter', 'meanEdge'}), struct('Lc_q', 100, 'Lp_q', 100, ...
        'alphaAddr', 25700, 'blackFrame', false));
end

function testReliabilityUsesNormalizedWeightedMean(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    region = regionalMetering(prep, masks, cfg, luts);
    verifyEqual(testCase, region.sumWc, 1.1, 'AbsTol', 1e-14);
    verifyEqual(testCase, region.sumWp, 1, 'AbsTol', 1e-14);
    verifyEqual(testCase, region.Lc, 124 / 1.1, 'AbsTol', 1e-12);
    verifyEqual(testCase, region.Lp, 100, 'AbsTol', 1e-12);
    expectedAlpha = refA_getCenterWeight(113, 100, cfg);
    verifyEqual(testCase, region.alpha, expectedAlpha, 'AbsTol', 1e-12);
    verifyEqual(testCase, region.Mr, expectedAlpha * (124 / 1.1) + ...
        (1 - expectedAlpha) * 100, 'AbsTol', 1e-12);
end

function testFullScaleWithFractionalReliabilityDoesNotOverflow(testCase)
    [center, edge, ~, valid] = generateRealMasks(testCase, 0.75);
    masks = struct('center', center, 'edge', edge);
    prep = struct('validMask', valid, 'Bi', 255 * ones(size(valid)), ...
        'Ri', 0.1 * ones(size(valid)));
    region = regionalMetering(prep, masks, testCase.TestData.Cfg, testCase.TestData.Luts);
    verifyTrue(testCase, region.valid);
    verifyEqual(testCase, region.status, 'normal');
    verifyEqual(testCase, [region.Lc, region.Lp, region.Mr], [255, 255, 255], 'AbsTol', 1e-10);
    verifyEqual(testCase, region.alpha, 0.5);
end

function testScalingRegionReliabilityPreservesBrightness(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    original = regionalMetering(prep, masks, cfg, luts);
    prep.Ri(masks.center) = prep.Ri(masks.center) * 0.25;
    prep.Ri(masks.edge) = prep.Ri(masks.edge) * 0.5;
    scaled = regionalMetering(prep, masks, cfg, luts);
    verifyEqual(testCase, [scaled.Lc, scaled.Lp, scaled.alpha, scaled.Mr], ...
        [original.Lc, original.Lp, original.alpha, original.Mr], 'AbsTol', 1e-12);
end

function testBrightnessOutsideFovDoesNotAffectMetering(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    original = regionalMetering(prep, masks, cfg, luts);
    prep.Bi(~prep.validMask) = 255;
    changed = regionalMetering(prep, masks, cfg, luts);
    verifyEqual(testCase, changed, original);
end

function testIntegerAddressesMatchReferenceAFiveSegments(testCase)
    cfg = testCase.TestData.Cfg;
    luts = testCase.TestData.Luts;
    pairs = [25,100; 70,100; 100,100; 130,100; 170,100; ...
        50,100; 90,100; 110,100; 150,100; 0,0; 255,0; 0,1; 255,255];
    for k = 1:size(pairs, 1)
        [alpha, debug] = getCenterWeight(pairs(k, 1), pairs(k, 2), luts);
        expected = refA_getCenterWeight(pairs(k, 1), pairs(k, 2), cfg);
        verifyEqual(testCase, alpha, expected, 'AbsTol', 1e-12);
        verifyEqual(testCase, debug.alphaAddr, pairs(k, 2) * 256 + pairs(k, 1));
    end
end

function testHalfUpAddressQuantizationAndOriginalBrightness(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    pairs = [0.2,0.3; 0.5,0.25; 69.49,99.5; 69.5,100.49; 254.5,255];
    for k = 1:size(pairs, 1)
        [~, directDebug] = getCenterWeight(pairs(k, 1), pairs(k, 2), luts);
        verifyEqual(testCase, [directDebug.Lc_q, directDebug.Lp_q], floor(pairs(k, :) + 0.5));
        prep.Bi(masks.center) = pairs(k, 1);
        prep.Bi(masks.edge) = pairs(k, 2);
        [region, debug] = regionalMetering(prep, masks, cfg, luts);
        q = floor([region.Lc, region.Lp] + 0.5);
        verifyEqual(testCase, [debug.Lc_q, debug.Lp_q], q);
        verifyEqual(testCase, region.alpha, refA_getCenterWeight(q(1), q(2), cfg), 'AbsTol', 1e-12);
        verifyEqual(testCase, region.Mr, region.alpha * pairs(k, 1) + ...
            (1 - region.alpha) * pairs(k, 2), 'AbsTol', 1e-12);
        verifyFalse(testCase, debug.blackFrame);
        verifyEqual(testCase, region.status, 'normal');
    end
end

function testWeightIsMonotonicAndBoundedAtFixedLp(testCase)
    cfg = testCase.TestData.Cfg;
    weights = arrayfun(@(lc) getCenterWeight(lc, 100, testCase.TestData.Luts), 0:255);
    verifyGreaterThanOrEqual(testCase, min(diff(weights)), -1e-14);
    verifyGreaterThanOrEqual(testCase, min(weights), cfg.alphaMin);
    verifyLessThanOrEqual(testCase, max(weights), cfg.alphaMax);
end

function testFusionStaysInsideBrightnessConvexHull(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    pairs = [0,1; 1,0; 0.125,0.25; 0.5,1; 70,100; 100,100; 155,100; 255,1; 0,255; 255,255];
    for k = 1:size(pairs, 1)
        prep.Bi(masks.center) = pairs(k, 1);
        prep.Bi(masks.edge) = pairs(k, 2);
        region = regionalMetering(prep, masks, cfg, luts);
        verifyGreaterThanOrEqual(testCase, region.Mr, min(pairs(k, :)) - 1e-12);
        verifyLessThanOrEqual(testCase, region.Mr, max(pairs(k, :)) + 1e-12);
    end
end

function testBlackFrameHasValidZeroResult(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    prep.Bi(:) = 0;
    [region, debug] = regionalMetering(prep, masks, cfg, luts);
    verifyTrue(testCase, region.valid);
    verifyEqual(testCase, region.status, 'blackFrame');
    verifyEqual(testCase, [region.Lc, region.Lp, region.Mr], [0, 0, 0]);
    verifyEqual(testCase, region.alpha, cfg.Wc);
    verifyTrue(testCase, region.blackFrame);
    verifyEqual(testCase, rmfield(debug, {'meanCenter', 'meanEdge'}), struct('Lc_q', 0, 'Lp_q', 0, ...
        'alphaAddr', 0, 'blackFrame', true));
end

function testFallbacksDoNotAccessAlphaLUT(testCase)
    [prep, masks, cfg] = smallFixture(testCase);
    original = prep;
    cases = {'onlyCenterValid', 'onlyEdgeValid', 'noReliableBlocks'};
    for k = 1:3
        prep = original;
        if k ~= 2, prep.Ri(masks.edge) = 0; end
        if k ~= 1, prep.Ri(masks.center) = 0; end
        [region, debug] = regionalMetering(prep, masks, cfg, struct());
        verifyEqual(testCase, region.status, cases{k});
        verifyEqual(testCase, region.valid, k < 3);
        verifyTrue(testCase, all(isnan([debug.Lc_q, debug.Lp_q, debug.alphaAddr])));
        verifyFalse(testCase, debug.blackFrame);
        if k == 1
            verifyEqual(testCase, [region.Mr, region.alpha], [124 / 1.1, 1], 'AbsTol', 1e-12);
            verifyTrue(testCase, isnan(region.Lp));
        elseif k == 2
            verifyEqual(testCase, [region.Mr, region.alpha], [100, 0], 'AbsTol', 1e-12);
            verifyTrue(testCase, isnan(region.Lc));
        else
            verifyTrue(testCase, all(isnan([region.Lc, region.Lp, region.Mr, region.alpha])));
        end
    end
end

function testWeightSumThresholdIsStrict(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    cfg.sumWMin = 1;
    region = regionalMetering(prep, masks, cfg, luts);
    verifyEqual(testCase, region.status, 'onlyCenterValid');
    cfg.sumWMin = 1.1;
    region = regionalMetering(prep, masks, cfg, luts);
    verifyEqual(testCase, region.status, 'noReliableBlocks');
    verifyFalse(testCase, region.valid);
end

function testMappingConfigIsReadOnlyAfterLoading(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    for field = {'rho1', 'rho2', 'rho3', 'rho4', 'alphaMin', 'Wc', 'alphaMax', 'LpMin'}
        changed = cfg;
        changed.(field{1}) = changed.(field{1}) + 0.01;
        verifyError(testCase, @() regionalMetering(prep, masks, changed, luts), ...
            'regionalMetering:ConfigLUTMismatch');
        verifyError(testCase, @() regionalMetering(prep, masks, rmfield(cfg, field{1}), luts), ...
            'regionalMetering:ConfigLUTMismatch');
    end
    for value = {-1, NaN, Inf, [0, 1]}
        changed = cfg;
        changed.sumWMin = value{1};
        verifyThrows(testCase, @() regionalMetering(prep, masks, changed, luts));
    end
end

function testInvalidMappingBrightnessAndLUTAreRejected(testCase)
    luts = testCase.TestData.Luts;
    for value = {-1, 256, NaN, Inf, 1i, [], [1, 2]}
        verifyThrows(testCase, @() getCenterWeight(value{1}, 100, luts));
        verifyThrows(testCase, @() getCenterWeight(100, value{1}, luts));
    end
    verifyError(testCase, @() getCenterWeight(100, 100, struct()), 'getCenterWeight:InvalidLUT');
    changed = luts;
    changed.alpha(25701) = NaN;
    verifyError(testCase, @() getCenterWeight(100, 100, changed), 'getCenterWeight:InvalidCoefficient');
end
function testInvalidPreprocessingDataIsRejected(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    for field = {'Bi', 'Ri', 'validMask'}
        verifyThrows(testCase, @() regionalMetering(rmfield(prep, field{1}), masks, cfg, luts));
        changed = prep;
        changed.(field{1}) = zeros(3, 2);
        verifyThrows(testCase, @() regionalMetering(changed, masks, cfg, luts));
    end
    for value = {-1, 256, NaN, Inf, 1i}
        changed = prep;
        changed.Bi(1, 1) = value{1};
        verifyThrows(testCase, @() regionalMetering(changed, masks, cfg, luts));
    end
    for value = {-0.1, 1.1, NaN, Inf, 1i}
        changed = prep;
        changed.Ri(1, 1) = value{1};
        verifyThrows(testCase, @() regionalMetering(changed, masks, cfg, luts));
    end
    changed = prep;
    changed.Bi(~changed.validMask) = NaN;
    verifyThrows(testCase, @() regionalMetering(changed, masks, cfg, luts));
end

function testInvalidRuntimeMasksAreRejected(testCase)
    [prep, masks, cfg, luts] = smallFixture(testCase);
    for field = {'center', 'edge'}
        verifyThrows(testCase, @() regionalMetering(prep, rmfield(masks, field{1}), cfg, luts));
        changed = masks;
        changed.(field{1}) = false(3, 2);
        verifyThrows(testCase, @() regionalMetering(prep, changed, cfg, luts));
        for value = {-1, 2, NaN, Inf}
            changed = masks;
            changed.(field{1}) = double(changed.(field{1}));
            changed.(field{1})(1, 1) = value{1};
            verifyThrows(testCase, @() regionalMetering(prep, changed, cfg, luts));
        end
    end
    changed = masks;
    changed.edge(1, 1) = true;
    verifyThrows(testCase, @() regionalMetering(prep, changed, cfg, luts));
    changed = masks;
    changed.center(1, 1) = false;
    verifyThrows(testCase, @() regionalMetering(prep, changed, cfg, luts));
    changed = masks;
    changed.center(1, 3) = true;
    verifyThrows(testCase, @() regionalMetering(prep, changed, cfg, luts));
    changedPrep = prep;
    changedPrep.validMask = double(prep.validMask);
    changedPrep.validMask(1, 1) = 2;
    verifyThrows(testCase, @() regionalMetering(changedPrep, masks, cfg, luts));
end

function testFourImagesEndToEnd(testCase)
    cfg = testCase.TestData.Cfg;
    luts = testCase.TestData.Luts;
    projectDir = testCase.TestData.ProjectDir;
    [~, ~, info, valid] = generateRealMasks(testCase, cfg.centerRatio);
    masks = loadRegionMasks(info.centerFile, info.edgeFile, [1080, 1920], cfg.blockSize, valid);
    for k = 1:4
        rgb = imread(fullfile(projectDir, 'testImg', sprintf('testImg_%d.bmp', k)));
        prep = meteringPreprocess(rgb, valid, cfg, luts);
        region = regionalMetering(prep, masks, cfg, luts);
        verifyRegionFields(testCase, region);
        verifyTrue(testCase, region.valid);
        expectedLc = sum(prep.Bi(masks.center) .* prep.Ri(masks.center)) / sum(prep.Ri(masks.center));
        expectedLp = sum(prep.Bi(masks.edge) .* prep.Ri(masks.edge)) / sum(prep.Ri(masks.edge));
        verifyEqual(testCase, [region.Lc, region.Lp], [expectedLc, expectedLp], 'AbsTol', 1e-10);
        verifyEqual(testCase, region.alpha, refA_getCenterWeight( ...
            floor(expectedLc + 0.5), floor(expectedLp + 0.5), cfg), 'AbsTol', 1e-12);
    end
end
function [center, edge, info, valid] = generateRealMasks(testCase, ratio)
    folder = newTemporarySubdirectory(testCase);
    file = fullfile(testCase.TestData.ProjectDir, '权重配置文件', '圆形有效视场权重_16×16.txt');
    valid = logical(reshape(readmatrix(file), 120, 67).');
    [center, edge, info] = generateRegionMasks(file, ratio, 16, [1080, 1920], folder);
end

function [prep, masks, cfg, luts] = smallFixture(testCase)
    cfg = testCase.TestData.Cfg;
    luts = testCase.TestData.Luts;
    masks.center = logical([1, 1, 0; 0, 0, 0]);
    masks.edge = logical([0, 0, 0; 1, 1, 0]);
    prep.validMask = masks.center | masks.edge;
    prep.Bi = [100, 240, 0; 80, 120, 0];
    prep.Ri = [1, 0.1, 0; 0.5, 0.5, 0];
end

function verifyPartition(testCase, center, edge, valid)
    verifyClass(testCase, center, 'logical');
    verifyClass(testCase, edge, 'logical');
    verifyFalse(testCase, any(center(:) & edge(:)));
    verifyEqual(testCase, center | edge, valid);
end

function verifyRegionFields(testCase, region)
    expected = {'Lc'; 'Lp'; 'alpha'; 'Mr'; 'valid'; 'status'; ...
        'sumWc'; 'sumWp'; 'Lc_q'; 'Lp_q'; 'alphaAddr'; 'blackFrame'};
    verifyEqual(testCase, sort(fieldnames(region)), sort(expected));
end

function verifyThrows(testCase, action)
% 验证非法输入确实失败，不将测试绑定到尚未固定的错误标识符。
    didThrow = false;
    try
        action();
    catch
        didThrow = true;
    end
    verifyTrue(testCase, didThrow, '非法输入必须抛出异常。');
end

function folder = newTemporarySubdirectory(testCase)
    folder = tempname(testCase.TestData.TemporaryDir);
    [created, message] = mkdir(folder);
    assert(created, message);
end

function file = writeMask(folder, name, mask)
    file = fullfile(folder, name);
    [fid, message] = fopen(file, 'w');
    assert(fid >= 0, message);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%d\n', reshape(double(mask).', [], 1));
end

function file = writeNumericFile(folder, name, values)
    file = fullfile(folder, name);
    writematrix(values, file, 'Delimiter', 'tab');
end

function removeOwnedTemporaryDirectory(folder, temporaryRoot)
% folder 仅来自 setupOnce 的 tempname(temporaryRoot)，不是用户提供的路径。
    folderObject = java.io.File(folder);
    rootObject = java.io.File(temporaryRoot);
    absoluteFolder = char(folderObject.getCanonicalPath());
    absoluteRoot = char(rootObject.getCanonicalPath());
    rootPrefix = [absoluteRoot, filesep];
    assert(startsWith(absoluteFolder, rootPrefix, 'IgnoreCase', true), ...
        '拒绝清理系统临时目录之外的路径。');
    assert(~strcmpi(absoluteFolder, absoluteRoot), '拒绝清理系统临时目录本身。');
    if isfolder(absoluteFolder)
        rmdir(absoluteFolder, 's');
    end
end
