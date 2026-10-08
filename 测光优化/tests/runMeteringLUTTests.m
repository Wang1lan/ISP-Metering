function result = runMeteringLUTTests(outputDir)
%RUNMETERINGLUTTESTS MATLAB R2022a 离线 LUT 表级、初始化、行为及误差验收。
% addpath('tests'); result = runMeteringLUTTests();
% outputDir 可选，指定新目录可保留历史报告；本入口只在自有临时副本修改生成器参数。
    projectDir = fileparts(fileparts(mfilename('fullpath')));
    if nargin < 1, outputDir = fullfile(projectDir, 'tests', 'results'); end
    if ~isfolder(outputDir), mkdir(outputDir); end
    previousPath = path;
    restore = onCleanup(@() path(previousPath));
    addpath(fullfile(projectDir, 'float'), fullfile(projectDir, 'tests'), ...
        fullfile(projectDir, 'tests', 'reference'));
    checks = {};
    cfg = createMeteringConfig();
    weight = fullfile(projectDir, '权重配置文件', '圆形有效视场权重_16×16.txt');
    [luts, cfg, mask] = loadMeteringLUTs(cfg, [1080, 1920], weight);
    check(isequal(size(mask), [67, 120]) && nnz(mask) == 5314, 'default FOV geometry');
    for peakBlockCnt = [256, 512]
        changed = cfg; changed.peakBlockCnt = peakBlockCnt;
        [sameLuts, sameCfg, sameMask] = loadMeteringLUTs(changed, [1080, 1920], weight);
        check(isequal(sameLuts, luts) && isequal(sameMask, mask) && ...
            sameCfg.peakBlockCnt == peakBlockCnt, ...
            sprintf('K=%d preserves LUT values and metadata', peakBlockCnt));
    end
    checkTables(luts, cfg, true, @check);
    checkBehavior(luts, cfg, @check);
    checkRuntimeSource(projectDir, @check);

    [base, baseCleanup] = meteringLUTTestFixture(projectDir, struct(), 16); %#ok<ASGLU> retain cleanup owner
    [baseLuts, baseCfg, baseMask] = loadMeteringLUTs(base.cfg, base.imageSize, base.weightFile);
    baseCfg.peakBlockCnt = 64; % 此夹具只有 122 个有效 block，显式使用适配的小 K。
    check(isequal(baseMask, base.expectedMask), 'FOV row scan ordering');
    for thresholdMode = {'count', 'ratio'}
      for b = [8, 16, 32, 64]
        changes.R.thresholdMode = ['''', thresholdMode{1}, ''''];
        [fixture, owned] = meteringLUTTestFixture(projectDir, changes, b); %#ok<ASGLU> retain until clear
        [tables, config, actualMask] = loadMeteringLUTs( ...
            fixture.cfg, fixture.imageSize, fixture.weightFile);
        check(numel(tables.R) == b^2+1, sprintf('B=%d R length', b));
        expectedThresholds = [10, 50];
        if strcmp(thresholdMode{1}, 'ratio'), expectedThresholds = round([10, 50]/256*b^2); end
        check(isequal([config.N1, config.N2], expectedThresholds), ...
            sprintf('B=%d %s thresholds', b, thresholdMode{1}));
        check(isequal(actualMask, fixture.expectedMask) && ...
            tables.meta.lambda.Nvalid == nnz(actualMask) && ...
            numel(tables.lambda) == nnz(actualMask)+1, sprintf('B=%d lambda geometry', b));
        checkTables(tables, config, false, @check);
        rgb = repmat(uint8(37), [fixture.imageSize, 3]);
        prep = meteringPreprocess(rgb, actualMask, config, tables);
        check(isequal(size(prep.Bi), [8, 16]) && all(prep.NhMap(:) == 0) && ...
            max(abs(prep.Bi(actualMask)-37)) < 1e-12, sprintf('B=%d crop and preprocess', b));
        if b ~= 16
            wrong = base.cfg; wrong.lutManifests.R = fixture.cfg.lutManifests.R;
            expectFailure(@() loadMeteringLUTs(wrong, base.imageSize, base.weightFile), ...
                'loadMeteringLUTs:', sprintf('B=%d incompatible manifests', b));
        end
        clear owned
      end
    end
    check(baseCfg.N1 == 10 && baseCfg.N2 == 50, 'count mode uses absolute counts');

    modes = {'float', 'fixed', 'both'};
    for k = 1:numel(modes)
        mode = modes{k}; change = struct();
        for name = {'R', 'alpha', 'lambda'}, change.(name{1}).outputMode = ['''', mode, '''']; end
        change.R.fracBits = '7'; change.alpha.fracBits = '9'; change.lambda.fracBits = '11';
        [fixture, owned] = meteringLUTTestFixture(projectDir, change, 16); %#ok<ASGLU> retain until clear
        for name = {'R', 'alpha', 'lambda'}
            n = name{1}; info = fixture.info.(n);
            check(strcmp(info.meta.outputMode, mode), [mode, ' manifest mode ', n]);
            check(info.logicalBits == info.fracBits + 1, [mode, ' logical bits ', n]);
            if ~strcmp(mode, 'fixed')
                values = readMeteringColumn(info.floatFile, info.length);
                check(isequal(values, baseLuts.(n)), ['F change preserves float ', n, ' ', mode]);
            else
                check(isempty(info.floatFile) && isempty(info.meta.floatSHA256), ['fixed has no float ', n]);
            end
            if ~strcmp(mode, 'float')
                codes = readMeteringColumn(info.fixedFile, info.length);
                check(isequal(codes, round(baseLuts.(n)*2^info.fracBits)), ['round at own F ', n, ' ', mode]);
                check(max(abs(codes/2^info.fracBits-baseLuts.(n))) <= 2^(-info.fracBits-1)+1e-12, ...
                    ['QF error bound ', n, ' ', mode]);
            else
                check(isempty(info.fixedFile) && isempty(info.meta.fixedSHA256), ['float has no fixed ', n]);
            end
        end
        if strcmp(mode, 'fixed')
            % 故意放回同名旧 float；manifest 仍必须阻止其被当成本次输出。
            for name = {'R', 'alpha', 'lambda'}
                n = name{1}; copyfile(base.info.(n).floatFile, ...
                    fullfile(fixture.root, 'LUT', base.info.(n).meta.floatFile));
            end
            expectFailure(@() loadMeteringLUTs(fixture.cfg, fixture.imageSize, fixture.weightFile), ...
                'loadMeteringLUTs:', 'fixed-only rejects stale float');
        else
            tables = loadMeteringLUTs(fixture.cfg, fixture.imageSize, fixture.weightFile);
            check(isequal(tables.alpha, baseLuts.alpha), [mode, ' initialization']);
        end
        clear owned
    end

    bad.R.thresholdMode = '''ratio'''; bad.R.highRatio1 = '0.001'; bad.R.highRatio2 = '0.002';
    expectFailure(@() meteringLUTTestFixture(projectDir, bad, 8), ...
        'generateReliabilityLUT:InvalidThresholds', 'R rounded thresholds collapse');
    bad = struct(); bad.lambda.fusionP1 = '0.001'; bad.lambda.fusionP2 = '0.002';
    expectFailure(@() meteringLUTTestFixture(projectDir, bad, 16), ...
        'generateFusionLUT:CollapsedThresholds', 'lambda rounded thresholds collapse');
    bad = struct(); bad.lambda.lambdaMin = '0';
    expectFailure(@() meteringLUTTestFixture(projectDir, bad, 16), ...
        'generateFusionLUT:InvalidLambdaMin', 'lambda minimum must be positive');
    bad.lambda.lambdaMin = '1e-8';
    expectFailure(@() meteringLUTTestFixture(projectDir, bad, 16), ...
        'generateFusionLUT:QuantizedMinimumZero', 'positive lambda quantized to zero');
    bad = struct(); bad.R.Rmin = '1e-8';
    expectFailure(@() meteringLUTTestFixture(projectDir, bad, 16), ...
        'generateReliabilityLUT:QuantizedMinimumZero', 'positive R minimum quantized to zero');
    tiny = struct(); tiny.R.Rmin = '1e-8'; tiny.R.outputMode = '''float''';
    tiny.lambda.lambdaMin = '1e-8'; tiny.lambda.outputMode = '''float''';
    [floatOnly, tinyCleanup] = meteringLUTTestFixture(projectDir, tiny, 16); %#ok<ASGLU> retain until clear
    [tinyLuts, tinyCfg] = loadMeteringLUTs(floatOnly.cfg, floatOnly.imageSize, floatOnly.weightFile);
    check(tinyCfg.Rmin == 1e-8 && tinyCfg.lambdaMin == 1e-8 && ...
        tinyLuts.R(end) == 1e-8 && tinyLuts.lambda(1) == 1e-8, ...
        'float-only tiny positive minimum is not quantized');
    clear tinyCleanup
    zero = struct(); zero.R.Rmin = '0'; zero.alpha.LpMin = '1.7';
    [nondefault, extraCleanup] = meteringLUTTestFixture(projectDir, zero, 16); %#ok<ASGLU> retain until clear
    [otherLuts, otherCfg] = loadMeteringLUTs(nondefault.cfg, nondefault.imageSize, nondefault.weightFile);
    check(otherLuts.R(end) == 0 && otherCfg.Rmin == 0, 'Rmin=0 explicitly allowed');
    alphaError = 0;
    for lp = 0:3
        for lc = 0:8
            alphaError = max(alphaError, abs(otherLuts.alpha(256*lp+lc+1) - ...
                refA_getCenterWeight(lc, lp, otherCfg)));
        end
    end
    check(otherCfg.LpMin == 1.7 && alphaError <= 1e-12, 'nondefault LpMin table near denominator floor');
    clear extraCleanup
    emptyFile = fullfile(base.root, 'weights', 'empty-fov.txt');
    writeText(emptyFile, sprintf('%.0f\n', zeros(numel(baseMask), 1)));
    empty = struct(); empty.lambda.fovFile = ['''', strrep(emptyFile, '''', ''''''), ''''];
    expectFailure(@() meteringLUTTestFixture(projectDir, empty, 16), ...
        'generateFusionLUT:EmptyFOV', 'offline lambda rejects Nvalid=0');
    bad.R.Rmin = '1';
    [one, owned] = meteringLUTTestFixture(projectDir, bad, 16); %#ok<ASGLU> retain until clear
    [oneLuts, oneCfg, oneMask] = loadMeteringLUTs(one.cfg, one.imageSize, one.weightFile);
    rgb = zeros([one.imageSize, 3], 'uint8'); rgb(1:16, 1:16, :) = 255;
    prep = meteringPreprocess(rgb, oneMask, oneCfg, oneLuts);
    check(all(prep.Ri(oneMask) == 1) && prep.RminBlockCnt == 1, 'Rmin=1 counts Nh>=N2');
    clear owned

    checkCorruption(base, @expectFailure);
    rgb = repmat(uint8(45), [base.imageSize, 3]);
    changed = baseCfg; changed.N2 = baseCfg.N2+1;
    expectFailure(@() meteringPreprocess(rgb, baseMask, changed, baseLuts), ...
        'meteringPreprocess:', 'loaded N2 immutable');
    changed = baseCfg; changed.blockSize = 8;
    expectFailure(@() meteringPreprocess(rgb, baseMask, changed, baseLuts), ...
        'meteringPreprocess:', 'loaded block size immutable');
    moved = fullfile(base.root, 'LUT_moved_after_load');
    movefile(fullfile(base.root, 'LUT'), moved);
    movefile(base.weightFile, [base.weightFile, '.moved']);
    masks.center = false(size(baseMask)); masks.center(:, 1:8) = baseMask(:, 1:8);
    masks.edge = baseMask & ~masks.center;
    for intensity = [0, 45, 210]
        rgb(:) = intensity;
        prep = meteringPreprocess(rgb, baseMask, baseCfg, baseLuts);
        region = regionalMetering(prep, masks, baseCfg, baseLuts);
        peak = peakMetering(prep, baseCfg);
        fusion = fusionMetering(prep, region, peak, baseCfg, baseLuts);
        check(fusion.valid && abs(region.Mr-double(intensity)) < 1e-10, ...
            sprintf('frame %d after LUT and FOV moved', intensity));
    end
    result.errorReport = reportMeteringLUTError(projectDir, outputDir);
    check(result.errorReport.imageCount == 9, 'nine-image A/B and B/C report');
    check(numel(result.errorReport.peakChangeRows) == 9, 'nine-image old/new peak comparison');
    result.passedChecks = numel(checks);
    result.checks = checks;
    result.matFile = fullfile(outputDir, 'metering_lut_tests.mat');
    result.markdownFile = fullfile(outputDir, 'metering_lut_tests.md');
    writeSummary(result.markdownFile, checks);
    save(result.matFile, 'result');
    fprintf('METERING_LUT_TESTS_PASS checks=%d\n', numel(checks));

    function check(condition, label)
        assert(isscalar(condition) && condition, 'runMeteringLUTTests:Failed', '%s', label);
        checks{end+1, 1} = label;
    end

    function expectFailure(operation, prefix, label)
        caught = false;
        try
            operation();
        catch exception
            assert(startsWith(exception.identifier, prefix), ...
                'runMeteringLUTTests:UnexpectedFailure', '%s: %s / %s', ...
                label, exception.identifier, exception.message);
            caught = true;
        end
        check(caught, label);
    end

end

    function checkTables(t, config, exhaustiveAlpha, check)
        meta = t.meta.R; n = (0:config.blockSize^2).';
        expected = ones(size(n)); inside = n > meta.N1 & n < meta.N2;
        expected(inside) = 1-(1-meta.Rmin)*(n(inside)-meta.N1)/(meta.N2-meta.N1);
        expected(n >= meta.N2) = meta.Rmin;
        check(max(abs(t.R-expected)) <= 1e-12 && all(diff(t.R) <= 0), 'R full formula and monotonicity');
        check(t.R(meta.N1+1) == 1 && t.R(meta.N2+1) == meta.Rmin, 'R threshold endpoints');
        [expected, detail] = refA_buildFusionLUT(t.meta.lambda.Nvalid, config);
        check(max(abs(t.lambda-expected(:))) <= 1e-12 && all(diff(t.lambda) >= 0), ...
            'lambda full original formula and monotonicity');
        check(t.lambda(detail.C1+1) == config.lambdaMin && ...
            t.lambda(detail.C2+1) == config.lambdaMax && config.lambdaMin > 0, 'lambda endpoints');
        if exhaustiveAlpha
            expected = zeros(65536, 1);
            for lp = 0:255
                for lc = 0:255
                    expected(256*lp+lc+1) = refA_getCenterWeight(lc, lp, config);
                end
            end
            check(max(abs(t.alpha-expected)) <= 1e-12, 'alpha 65536 addresses versus original');
        end
        for name = {'R', 'alpha', 'lambda'}
            key = name{1}; m = t.meta.(key); values = t.(key);
            check(numel(values) == m.length && all(values >= 0 & values <= 1), [key, ' length and range']);
            check(isequal(values, readMeteringColumn(m.floatPath, m.length)), [key, ' TXT roundtrip']);
            check(strcmpi(meteringFileSHA256(m.floatPath), m.floatSHA256), [key, ' float SHA256']);
            codes = readMeteringColumn(m.fixedPath, m.length);
            check(isequal(codes, round(values*2^m.fracBits)) && ...
                max(abs(codes/2^m.fracBits-values)) <= 2^(-m.fracBits-1)+1e-12, [key, ' exact QF round and bound']);
            check(strcmpi(meteringFileSHA256(m.fixedPath), m.fixedSHA256), [key, ' fixed SHA256']);
        end
    end

    function checkBehavior(t, config, check)
        [alpha, dbg] = getCenterWeight(0, 0, t);
        check(alpha == config.Wc && dbg.blackFrame, 'exact black lookup');
        [alpha, dbg] = getCenterWeight(0.2, 0.3, t);
        check(alpha == t.alpha(1) && ~dbg.blackFrame && dbg.Lc_q == 0 && ...
            dbg.Lp_q == 0 && dbg.alphaAddr == 0, 'nonzero dark address zero');
        prep = struct('Bi', [0.2, 0.3], 'Ri', [1, 1], 'validMask', true(1, 2));
        masks = struct('center', logical([1, 0]), 'edge', logical([0, 1]));
        r = regionalMetering(prep, masks, config, t);
        check(r.Mr > 0 && abs(r.Mr-(alpha*0.2+(1-alpha)*0.3)) <= 1e-12 && ...
            strcmp(r.status, 'normal'), 'nonzero dark remains nonzero');
        prep.Bi = [0, 0]; r = regionalMetering(prep, masks, config, t);
        check(r.Mr == 0 && r.alpha == config.Wc && strcmp(r.status, 'blackFrame'), 'regional exact black');
        prep.Bi = [60, 90];
        for values = {[1, 0], [0, 1], [0, 0]}
            prep.Ri = values{1}; r = regionalMetering(prep, masks, config, t);
            if isequal(values{1}, [1, 0])
                ok = r.Mr == 60 && r.alpha == 1 && strcmp(r.status, 'onlyCenterValid');
            elseif isequal(values{1}, [0, 1])
                ok = r.Mr == 90 && r.alpha == 0 && strcmp(r.status, 'onlyEdgeValid');
            else
                ok = ~r.valid && isnan(r.Mr) && strcmp(r.status, 'noReliableBlocks');
            end
            check(ok, ['regional fallback ', mat2str(values{1})]);
        end
        p = struct('validBlockCnt', t.meta.lambda.Nvalid, 'RminBlockCnt', t.meta.lambda.C2);
        r = struct('Mr', 100, 'valid', true, 'status', 'normal');
        peak = struct('Mp', 80, 'valid', true, 'status', 'normal', 'validBlockCnt', p.validBlockCnt);
        for mp = [80, 100, 120]
            peak.Mp = mp; f = fusionMetering(p, r, peak, config, t);
            check(abs(f.Mf-(100+config.lambdaMax*max(0, mp-100))) <= 1e-12, ...
                sprintf('fusion Mp=%d Mr=100', mp));
        end
        peak.valid = false; peak.Mp = NaN;
        f = fusionMetering(p, r, peak, config, t);
        check(f.Mf == r.Mr && f.lambda == 0 && strcmp(f.status, 'onlyRegionValid'), 'only region fusion');
        r.valid = false; r.Mr = NaN; peak.valid = true; peak.Mp = 120;
        f = fusionMetering(p, r, peak, config, t);
        check(f.Mf == 120 && isnan(f.lambda) && strcmp(f.status, 'onlyPeakValid'), 'only peak fusion');
        peak.valid = false; peak.Mp = NaN; f = fusionMetering(p, r, peak, config, t);
        check(~f.valid && isnan(f.Mf) && strcmp(f.status, 'noValidMetering'), 'both invalid fusion');
        p.validBlockCnt = 0; p.RminBlockCnt = 0; peak.validBlockCnt = 0;
        f = fusionMetering(p, r, peak, config, struct());
        check(~f.valid && strcmp(f.status, 'noValidBlocks'), 'empty FOV before LUT access');
    end

    function checkRuntimeSource(root, check)
        for name = {'meteringPreprocess', 'getCenterWeight', 'regionalMetering', 'fusionMetering'}
            source = fileread(fullfile(root, 'float', [name{1}, '.m']));
            source = regexprep(source, '%[^\r\n]*', '');
            forbidden = '(generateReliabilityLUT|generateAlphaLUT|generateFusionLUT|buildReliabilityLUT|buildFusionLUT|fopen|readmatrix|readMeteringColumn|loadFovBlockMask)\s*\(';
            check(isempty(regexp(source, forbidden, 'once')), [name{1}, ' has no online table/file calls']);
            if strcmp(name{1}, 'getCenterWeight')
                check(isempty(strfind(source, '/')), 'alpha runtime performs no division'); %#ok<STREMP>
            end
        end
    end

    function checkCorruption(fixture, expectFailure)
        operation = @() loadMeteringLUTs(fixture.cfg, fixture.imageSize, fixture.weightFile);
        wrong = fixture.cfg; wrong.lutManifests.R = fullfile(fixture.root, 'missing_manifest.txt');
        expectFailure(@() loadMeteringLUTs(wrong, fixture.imageSize, fixture.weightFile), 'loadMeteringLUTs:', 'missing manifest');
        wrong = fixture.cfg; wrong.lutManifests.alpha = fixture.cfg.lutManifests.R;
        expectFailure(@() loadMeteringLUTs(wrong, fixture.imageSize, fixture.weightFile), 'loadMeteringLUTs:', 'wrong LUT type');
        expectFailure(@() loadMeteringLUTs(fixture.cfg, fixture.imageSize+[1, 0], fixture.weightFile), ...
            'loadMeteringLUTs:', 'image size mismatch');
        data = fixture.info.R.floatFile; manifest = fixture.info.R.manifestFile;
        originalData = fileread(data); originalManifest = fileread(manifest);
        done = onCleanup(@() restoreFiles({data, manifest}, {originalData, originalManifest}));
        writeText(manifest, replaceKey(originalManifest, 'floatFile', 'missing.txt'));
        expectFailure(operation, 'loadMeteringLUTs:', 'missing float TXT');
        writeText(manifest, originalManifest);
        firstEnd = regexp(originalData, '\r?\n', 'once');
        for kind = {'multiple columns', 'NaN', 'wrong length', 'bad digest'}
            switch kind{1}
                case 'multiple columns', modified = ['1 1', originalData(firstEnd:end)];
                case 'NaN', modified = ['NaN', originalData(firstEnd:end)];
                case 'wrong length', modified = [originalData, sprintf('1\n')];
                case 'bad digest', modified = ['0.9', originalData(firstEnd:end)];
            end
            writeText(data, modified);
            if strcmp(kind{1}, 'bad digest'), writeText(manifest, originalManifest);
            else, writeText(manifest, replaceKey(originalManifest, 'floatSHA256', meteringFileSHA256(data))); end
            expectFailure(operation, 'loadMeteringLUTs:', kind{1});
        end
        restoreFiles({data, manifest}, {originalData, originalManifest});
        text = fileread(fixture.weightFile);
        doneFov = onCleanup(@() writeText(fixture.weightFile, text));
        changed = fixture.expectedMask; changed(1, 1) = false; changed(1, 2) = true;
        writeText(fixture.weightFile, sprintf('%.0f\n', reshape(double(changed.'), [], 1)));
        expectFailure(operation, 'loadMeteringLUTs:', 'same-count wrong FOV digest');
        writeText(fixture.weightFile, sprintf('%.0f\n', zeros(numel(changed), 1)));
        expectFailure(operation, 'loadMeteringLUTs:', 'empty FOV');
    end

function source = replaceKey(source, name, value)
    expression = ['(?m)^', regexptranslate('escape', name), '=[^\r\n]*'];
    [first, last] = regexp(source, expression, 'start', 'end');
    assert(numel(first) == 1, 'runMeteringLUTTests:ManifestKey', 'manifest 字段必须唯一。');
    source = [source(1:first-1), name, '=', value, source(last+1:end)];
end

function writeText(file, text)
    fid = fopen(file, 'wb'); assert(fid >= 0);
    done = onCleanup(@() fclose(fid));
    fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
end

function restoreFiles(files, contents)
    for k = 1:numel(files), writeText(files{k}, contents{k}); end
end

function writeSummary(file, checks)
    fid = fopen(file, 'wt', 'n', 'UTF-8'); assert(fid >= 0);
    done = onCleanup(@() fclose(fid));
    fprintf(fid, '# 测光 LUT 验收结果\n\n');
    fprintf(fid, 'MATLAB %s，%s。\n\n', version('-release'), datestr(now, 31));
    fprintf(fid, 'METERING_LUT_TESTS_PASS：%d 项检查通过。\n\n', numel(checks));
    fprintf(fid, ['入口：runMeteringLUTTests。参考源码位于 tests/reference，测试不改写参考或正式生成器参数。\n\n', ...
        'A/B、B/C 误差数据见 metering_lut_error_report.md。业务精度容差尚未约定；C 不代表完整定点实现。\n\n', ...
        '本入口未包含 main 的双工作目录运行或手工 GUI 检查；这些验证应单独记录。\n\n']);
    for k = 1:numel(checks), fprintf(fid, '- [x] %s\n', checks{k}); end
end
