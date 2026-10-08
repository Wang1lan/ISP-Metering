function summary = test_peakMetering()
%TEST_PEAKMETERING 第三阶段峰值测光验收，不依赖图片或外部测试框架。
% 直接调用 test_peakMetering。排序只用于本测试的独立数值基准。
% 确定性用例捕获固定数量、零值漏计、临界档超取、整数溢出和错误加权；
% 随机基准捕获其他网格/K 下的统计错误；非法输入捕获契约校验缺失。

    % K=1 时，单个有效 block 必须选择自身。
    prep = struct('Bi', 80, 'validMask', true);
    cfg = struct('peakBlockCnt', 1);
    [peak, debug] = peakMetering(prep, cfg);
    verifyOutputs(prep, cfg, peak, debug);
    assert(peak.Mp == 80 && peak.targetBlockCnt == 1, ...
        '单个有效 block 必须选择自身。');
    deterministicCount = 1;

    % 每行：说明、Bi、有效掩模、配置 K、实际 K、S、临界档、状态。
    fixtures = {
        '101 个有效 block 仍选择固定数量', 80 * ones(1,101), true(1,101), 8, 8, 640, 80, 'normal';
        '有效全黑', zeros(2,3), true(2,3), 4, 4, 0, 0, 'normal';
        '无有效 block', [0 80; 255 20], false(2,2), 512, 0, 0, NaN, 'noValidBlocks';
        '均匀中间亮度', 127 * ones(2,3), true(2,3), 4, 4, 508, 127, 'normal';
        '均匀最高亮度且最高档超过 K', 255 * ones(2,3), true(2,3), 4, 4, 1020, 255, 'normal';
        '屏蔽无效亮块', [255 20 20], [0 1 1], 2, 2, 40, 20, 'normal';
        '所有有效块参与算术平均', [100 200], true(1,2), 2, 2, 300, 100, 'normal';
        '临界档只纳入剩余数量', [200 * ones(1,3), 100 * ones(1,10)], true(1,13), 8, 8, 1100, 100, 'normal';
        '零亮度也是有效 block', [0 0 0 10], true(1,4), 4, 4, 10, 0, 'normal';
        '四舍五入含半整数边界', [.49 .5 10.49 10.5 254.5 0 0 0], true(1,8), 8, 8, 277, 0, 'normal';
        '极暗量化后为零', .4 * ones(2,3), true(2,3), 4, 4, 0, 0, 'normal';
        '先转 double 再做整数算术', uint8([100 200 255 0]), true(1,4), 4, 4, 555, 0, 'normal';
        'numeric 二值掩模', [5 20; 80 255], uint8([1 0; 1 0]), 2, 2, 85, 5, 'normal';
        '不加 epsilon 改变低亮度', [.5 .51 0 0], true(1,4), 4, 4, 2, 0, 'normal';
        'K=1 选择最大有效亮度', [10 20], true(1,2), 1, 1, 20, 20, 'normal'
    };
    for row = 1:size(fixtures,1)
        item = fixtures(row,:);
        prep = struct('Bi', item{2}, 'validMask', item{3});
        cfg = struct('peakBlockCnt', item{4});
        [peak, ~] = checkedCall(prep, cfg);
        assert(peak.targetBlockCnt == item{5}, item{1});
        assert(peak.sumB == item{6}, item{1});
        assert(isequaln(peak.thresholdBin, item{7}), item{1});
        assert(strcmp(peak.status, item{8}), item{1});
        if peak.valid
            assert(peak.Mp == item{6} / item{5}, item{1});
        end
        deterministicCount = deterministicCount + 1;
    end

    % 从配置工厂实际调用，验证默认 K 及其最大亮度和。
    cfg = createMeteringConfig();
    prep = struct('Bi', 255 * ones(1,1024), 'validMask', true(1,1024));
    [peak, debug] = checkedCall(prep, cfg);
    assert(debug.peakBlockCnt == 512 && peak.targetBlockCnt == 512, ...
        '默认配置必须选择固定的 512 个有效 block。');
    assert(peak.sumB == 130560 && peak.Mp == 255, 'K=512 时最大亮度和应为 130560。');
    deterministicCount = deterministicCount + 1;

    % 有效块数量发生变化时，仅实际比例变化，配置 K 不动态缩放。
    baseRatio = debug.actualRatio;
    prep = struct('Bi', 255 * ones(1,2048), 'validMask', true(1,2048));
    [peak, debug] = checkedCall(prep, cfg);
    assert(peak.targetBlockCnt == 512 && peak.selectedBlockCnt == 512 && ...
        debug.peakBlockCnt == 512 && debug.actualRatio == baseRatio / 2);
    invariantCount = 1;

    % validBlockCnt 可选，但存在时必须匹配；零计数同样必须合法。
    prep = struct('Bi', [80 200], 'validMask', [1 0], 'validBlockCnt', uint8(1));
    checkedCall(prep, struct('peakBlockCnt', single(1)));
    prep.validMask = [0 0];
    prep.validBlockCnt = 0;
    checkedCall(prep, struct('peakBlockCnt', uint16(512)));
    deterministicCount = deterministicCount + 2;
    prep = struct('Bi', [80 200], 'validMask', true(1,2));
    integerCounts = {uint8(2), uint16(2)};
    for index = 1:numel(integerCounts)
        checkedCall(prep, struct('peakBlockCnt', integerCounts{index}));
        deterministicCount = deterministicCount + 1;
    end

    % Ri 不是峰值输入：删除或改变 Ri 均不能影响两个输出。
    prep = struct('Bi', [0 30.4 90.5; 255 150 50], ...
        'validMask', logical([1 1 1; 0 1 1]), 'Ri', ones(2,3), ...
        'validBlockCnt', 5, 'RminBlockCnt', 2);
    cfg = struct('peakBlockCnt', 4);
    [basePeak, baseDebug] = checkedCall(prep, cfg);
    prep.Ri = zeros(2,3);
    [peak, debug] = checkedCall(prep, cfg);
    assert(isequaln(peak, basePeak) && isequaln(debug, baseDebug), '改变 Ri 不应改变峰值结果。');
    prep = rmfield(prep, 'Ri');
    [peak, debug] = checkedCall(prep, cfg);
    assert(isequaln(peak, basePeak) && isequaln(debug, baseDebug), '删除 Ri 不应改变峰值结果。');
    invariantCount = invariantCount + 2;

    % 只改变二维布局；先转置打乱线性顺序，再重排为另一网格。
    prep = struct('Bi', reshape([0 .5 20.2 40.7 80 100 127.5 150 200 230 254.5 255],3,4), ...
        'validMask', logical(reshape([1 1 0 1 1 1 1 0 1 1 1 1],3,4)));
    [basePeak, baseDebug] = checkedCall(prep, cfg);
    reordered = struct('Bi', reshape(prep.Bi.',2,6), ...
        'validMask', reshape(prep.validMask.',2,6));
    [peak, debug] = checkedCall(reordered, cfg);
    assert(isequaln(peak, basePeak) && isequaln(debug, baseDebug), '二维排列不应改变结果。');
    invariantCount = invariantCount + 1;

    extended = struct('Bi', [prep.Bi, [255; 0; .49], [10.5; 254.5; 255]], ...
        'validMask', [prep.validMask, false(3,2)]);
    [peak, debug] = checkedCall(extended, cfg);
    assert(isequaln(peak, basePeak) && isequaln(debug, baseDebug), '追加无效位置不应改变结果。');
    invariantCount = invariantCount + 1;

    % 独立排序基准；恢复调用者随机状态，避免影响其他实验。
    previousRng = rng;
    restoreRng = onCleanup(@() rng(previousRng));
    rng(42);
    grids = [1 1; 2 3; 23 37; 67 120];
    oracleCount = 0;
    for gridIndex = 1:size(grids,1)
        grid = grids(gridIndex,:);
        prep = struct('Bi', 255 * rand(grid), 'validMask', rand(grid) > .2);
        % 最小网格仍验证正常分支，无有效路径由确定性用例独立覆盖。
        prep.validMask(1) = true;
        prep.validBlockCnt = nnz(prep.validMask);
        % 覆盖当前网格下所有可行的 2 的幂。
        blockCounts = 2 .^ (0:floor(log2(prep.validBlockCnt)));
        for blockCount = blockCounts
            checkedCall(prep, struct('peakBlockCnt', blockCount));
            oracleCount = oracleCount + 1;
        end
    end

    invalidCount = testInvalidInputs();
    summary = struct('deterministicCases', deterministicCount, ...
        'invariantCases', invariantCount, 'oracleCases', oracleCount, ...
        'invalidCases', invalidCount, ...
        'totalCases', deterministicCount + invariantCount + oracleCount + invalidCount);
    fprintf('test_peakMetering PASS: %d cases (%d deterministic, %d invariant, %d oracle, %d invalid).\n', ...
        summary.totalCases, deterministicCount, invariantCount, oracleCount, invalidCount);
end

function [peak, debug] = checkedCall(prep, cfg)
% 检查输入内容保持不变，并对每次合法调用检查完整输出契约。
    before = prep;
    [peak, debug] = peakMetering(prep, cfg);
    assert(isequaln(prep, before), 'peakMetering 不得修改 prep。');
    verifyOutputs(prep, cfg, peak, debug);
end

function verifyOutputs(prep, cfg, peak, debug)
    assert(isstruct(peak) && isscalar(peak), 'peak 必须是标量结构体。');
    assert(isstruct(debug) && isscalar(debug), 'debug 必须是标量结构体。');
    peakNumbers = {'Mp', 'validBlockCnt', 'targetBlockCnt', ...
        'selectedBlockCnt', 'thresholdBin', 'sumB'};
    for index = 1:numel(peakNumbers)
        field = peakNumbers{index};
        assert(isfield(peak, field), ['缺少 peak.' field]);
        assert(isa(peak.(field), 'double') && isscalar(peak.(field)) && isreal(peak.(field)), ...
            ['peak.' field ' 必须为 double 实数标量。']);
    end
    assert(isfield(peak, 'valid') && islogical(peak.valid) && isscalar(peak.valid));
    assert(isfield(peak, 'status') && ischar(peak.status) && isrow(peak.status));
    assert(~isfield(peak, 'sumB2'), '峰值诊断不应保留已删除的平方和。');
    assert(~isfield(debug, 'peakRatio'), '峰值诊断应使用固定 K 字段。');
    debugNumbers = {'peakBlockCnt', 'actualRatio', 'unweightedMean'};
    for index = 1:numel(debugNumbers)
        field = debugNumbers{index};
        assert(isfield(debug, field), ['缺少 debug.' field]);
        assert(isa(debug.(field), 'double') && isscalar(debug.(field)) && isreal(debug.(field)), ...
            ['debug.' field ' 必须为 double 实数标量。']);
    end
    histFields = {'histogram', 'selectedHistogram'};
    for index = 1:numel(histFields)
        field = histFields{index};
        assert(isfield(debug, field), ['缺少 debug.' field]);
        actual = debug.(field);
        assert(isa(actual, 'double') && isequal(size(actual), [256 1]) && isreal(actual));
        assert(all(isfinite(actual)) && all(actual >= 0) && all(actual == floor(actual)));
    end
    assert(isfield(debug, 'quantization') && ischar(debug.quantization) && ...
        strcmp(debug.quantization, 'roundHalfUpToInteger'));
    assert(debug.peakBlockCnt == double(cfg.peakBlockCnt));

    values = floor(double(prep.Bi(logical(prep.validMask))) + .5);
    values = sort(values(:), 'descend'); % 独立排序 oracle，仅测试中允许。
    validCount = numel(values);
    expectedHistogram = accumarray(values + 1, ones(size(values)), [256 1]);
    assert(isequal(debug.histogram, expectedHistogram));
    assert(peak.validBlockCnt == validCount && sum(debug.histogram) == validCount);
    if validCount == 0
        assert(~peak.valid && strcmp(peak.status, 'noValidBlocks') && isnan(peak.Mp));
        assert(peak.targetBlockCnt == 0 && peak.selectedBlockCnt == 0);
        assert(isnan(peak.thresholdBin) && peak.sumB == 0);
        assert(all(debug.selectedHistogram == 0));
        assert(isnan(debug.actualRatio) && isnan(debug.unweightedMean));
        return;
    end

    targetCount = double(cfg.peakBlockCnt);
    selected = values(1:targetCount);
    expectedSelected = accumarray(selected + 1, ones(size(selected)), [256 1]);
    sumB = sum(selected);
    assert(peak.valid && peak.targetBlockCnt == targetCount && peak.selectedBlockCnt == targetCount);
    assert(isequal(debug.selectedHistogram, expectedSelected));
    assert(sum(debug.selectedHistogram) == targetCount);
    assert(all(debug.selectedHistogram <= debug.histogram));
    assert(peak.thresholdBin == selected(end) && peak.sumB == sumB);
    assert(abs(debug.actualRatio - targetCount / validCount) <= 1e-12);
    assert(debug.unweightedMean == peak.Mp);
    assert(abs(peak.Mp - mean(selected)) <= 1e-10);
    assert(strcmp(peak.status, 'normal'));
    assert(peak.Mp >= selected(end) - 1e-10 && peak.Mp <= selected(1) + 1e-10);
    assert(isfinite(peak.Mp) && peak.Mp >= 0 && peak.Mp <= 255);
end

function count = testInvalidInputs()
% 原输入校验限定公开命名空间；固定 K 的新增契约检查明确错误类型。
    goodPrep = struct('Bi', [10 20], 'validMask', true(1,2));
    goodCfg = struct('peakBlockCnt', 2);
    count = 0;
    badStructs = {[], 1, 'bad', {1}, struct([]), repmat(struct('x', 1), 1, 2)};
    for index = 1:numel(badStructs)
        expectError(@() peakMetering(badStructs{index}, goodCfg));
        expectError(@() peakMetering(goodPrep, badStructs{index}));
        count = count + 2;
    end
    expectError(@() peakMetering(rmfield(goodPrep, 'Bi'), goodCfg));
    expectError(@() peakMetering(rmfield(goodPrep, 'validMask'), goodCfg));
    expectError(@() peakMetering(goodPrep, struct()), 'peakMetering:MissingConfig');
    count = count + 3;

    badBlockCounts = {0, -1, -.1, .5, 1.01, 3, 6, NaN, Inf, -Inf, ...
        1i, [], [1 2], '2', {2}, true, single(3), 2^40 - 1, 2^40 + 1, ...
        uint64(2^53) - uint64(1), uint64(2^53) + uint64(1)};
    for index = 1:numel(badBlockCounts)
        cfg = goodCfg;
        cfg.peakBlockCnt = badBlockCounts{index};
        expectError(@() peakMetering(goodPrep, cfg), 'peakMetering:InvalidPeakBlockCnt');
        count = count + 1;
    end
    expectError(@() peakMetering(goodPrep, struct('peakBlockCnt', 4)), ...
        'peakMetering:InsufficientValidBlocks');
    expectError(@() peakMetering(goodPrep, struct('peakRatio', .1)), ...
        'peakMetering:MissingConfig');
    count = count + 2;
    badBrightness = {[], sparse([10 20]), ones(1,2,2), [10 20i], ...
        [-.01 20], [10 255.01], [NaN 20], [10 Inf], [-Inf 20], 'ab', {10 20}};
    for index = 1:numel(badBrightness)
        prep = goodPrep;
        prep.Bi = badBrightness{index};
        expectError(@() peakMetering(prep, goodCfg));
        count = count + 1;
    end
    % 无效位置也必须校验亮度，不能先按掩模过滤再掩盖非法值。
    for value = [-1 256 NaN Inf -Inf]
        prep = struct('Bi', [10 value], 'validMask', [1 0]);
        expectError(@() peakMetering(prep, goodCfg));
        count = count + 1;
    end
    badMasks = {[], true(2,1), true(1,2,2), [1 .5], [1 -1], [1 2], ...
        [1 NaN], [1 Inf], [1 1i], '01', {true false}};
    for index = 1:numel(badMasks)
        prep = goodPrep;
        prep.validMask = badMasks{index};
        expectError(@() peakMetering(prep, goodCfg));
        count = count + 1;
    end
    badCounts = {-1, .5, NaN, Inf, 2i, [], [2 2], '2', {2}, 0, 1, 3};
    for index = 1:numel(badCounts)
        prep = goodPrep;
        prep.validBlockCnt = badCounts{index};
        expectError(@() peakMetering(prep, goodCfg));
        count = count + 1;
    end
    % 无有效 block 提前返回，也不能绕过配置或计数校验。
    prep = goodPrep;
    prep.validMask(:) = false;
    expectError(@() peakMetering(prep, struct('peakBlockCnt', 0)), ...
        'peakMetering:InvalidPeakBlockCnt');
    expectError(@() peakMetering(prep, struct('peakBlockCnt', uint64(2^53) + uint64(1))), ...
        'peakMetering:InvalidPeakBlockCnt');
    prep.validBlockCnt = 1;
    expectError(@() peakMetering(prep, goodCfg));
    count = count + 3;
end

function expectError(call, expectedIdentifier)
    didThrow = false;
    try
        call();
    catch err
        didThrow = true;
        assert(startsWith(err.identifier, 'peakMetering:'), ...
            ['错误标识应以 peakMetering: 开头，实际为 ' err.identifier]);
        if nargin > 1
            assert(strcmp(err.identifier, expectedIdentifier), ...
                ['错误标识应为 ' expectedIdentifier '，实际为 ' err.identifier]);
        end
    end
    assert(didThrow, '非法输入必须报错。');
end
