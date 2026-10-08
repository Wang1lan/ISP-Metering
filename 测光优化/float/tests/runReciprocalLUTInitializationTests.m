function result = runReciprocalLUTInitializationTests()
%RUNRECIPROCALLUTINITIALIZATIONTESTS 标准 JVM 下的导出、加载和旧配置回归。
    projectDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    oldPath = path; restore = onCleanup(@() path(oldPath));
    addpath(fullfile(projectDir, 'float'), fullfile(projectDir, 'float', 'tests'));
    weight = fullfile(projectDir, '权重配置文件', '圆形有效视场权重_16×16.txt');
    cfg = createMeteringConfig();
    base = loadMeteringLUTs(cfg, [1080, 1920], weight);
    checks = {};
    check(numel(base.reciprocal) == 256 && base.meta.reciprocal.logicalBits == 19, 'default A8/u19');
    legacy = cfg;
    legacy.lutManifests = rmfield(legacy.lutManifests, 'reciprocal');
    legacy = rmfield(legacy, {'regionMeanMethod', 'compareRegionMean'});
    old = loadMeteringLUTs(legacy, [1080, 1920], weight);
    check(~isfield(old, 'reciprocal') && isequal(old.R, base.R) && ...
        isequal(old.alpha, base.alpha) && isequal(old.lambda, base.lambda), 'old three-table config');
    bad = legacy; bad.regionMeanMethod = 'reciprocal_lut';
    fail(@() loadMeteringLUTs(bad, [1080, 1920], weight), 'loadMeteringLUTs:MissingReciprocal');
    bad = legacy; bad.compareRegionMean = true;
    fail(@() loadMeteringLUTs(bad, [1080, 1920], weight), 'loadMeteringLUTs:MissingReciprocal');
    bad = cfg; bad.regionMeanMethod = 'unknown';
    fail(@() loadMeteringLUTs(bad, [1080, 1920], weight), 'loadMeteringLUTs:InvalidMethod');
    bad = cfg; bad.compareRegionMean = 2;
    fail(@() loadMeteringLUTs(bad, [1080, 1920], weight), '');
    for mode = {'float', 'fixed', 'both'}
        [info, owned] = reciprocalLUTTestFixture(8, mode{1}); %#ok<ASGLU> 保留 onCleanup 至本轮末尾
        expected = 1 ./ (1 + ((0:255).' + 0.5) / 256);
        if ~isempty(info.floatFile)
            check(isequal(readMeteringColumn(info.floatFile, 256), expected), ['generated float ', mode{1}]);
            check(strcmp(meteringFileSHA256(info.floatFile), info.meta.floatSHA256), 'float SHA-256');
        end
        if ~isempty(info.fixedFile)
            codes = readMeteringColumn(info.fixedFile, 256);
            check(isequal(codes, floor(expected * 2^18 + 0.5)), ['integer rounding ', mode{1}]);
            check(all(codes >= 0 & codes == floor(codes)), 'integer codes');
            check(strcmp(meteringFileSHA256(info.fixedFile), info.meta.fixedSHA256), 'fixed SHA-256');
        end
        selected = cfg; selected.lutManifests.reciprocal = info.manifestFile;
        if strcmp(mode{1}, 'fixed')
            % 同名旧 float 文件不能覆盖 fixed-only manifest 的明确约定。
            copyfile(base.meta.reciprocal.floatPath, fullfile(fileparts(info.manifestFile), 'LUT_Reciprocal_A8_float.txt'));
            fail(@() loadMeteringLUTs(selected, [1080, 1920], weight), 'loadMeteringLUTs:InvalidLUT');
        else
            loaded = loadMeteringLUTs(selected, [1080, 1920], weight);
            check(isequal(loaded.reciprocal, base.reciprocal), ['load ', mode{1}]);
        end
        clear owned
    end
    [info, owned] = reciprocalLUTTestFixture(8); %#ok<ASGLU> 保留 onCleanup 至破坏性夹具检查结束
    selected = cfg; selected.lutManifests.reciprocal = info.manifestFile;
    original = fileread(info.manifestFile);
    changes = {'length','255'; 'addrBits','7'; 'normalizedMin','0'; ...
        'normalizedMax','3'; 'sampleRule','left'; 'addressBase','1'; ...
        'addressFormula','m'; 'logicalBits','18'; 'fracBits','0'; ...
        'floatSHA256',repmat('0',1,64); 'floatFile','missing.txt'; 'lutType','R'};
    for k = 1:size(changes, 1)
        writeText(info.manifestFile, replaceKey(original, changes{k,1}, changes{k,2}));
        fail(@() loadMeteringLUTs(selected, [1080, 1920], weight), 'loadMeteringLUTs:InvalidLUT');
    end
    writeText(info.manifestFile, original);
    missing = selected; missing.lutManifests.reciprocal = fullfile(fileparts(info.manifestFile), 'missing_manifest.txt');
    fail(@() loadMeteringLUTs(missing, [1080, 1920], weight), 'loadMeteringLUTs:InvalidLUT');
    data = fileread(info.floatFile);
    for invalid = {'0.75', 'NaN', sprintf('%s\n0.75\n', strtrim(data)), ...
            regexprep(data, '^[^\r\n]*', '0.75'), regexprep(data, '^[^\r\n]*', '0.9 0.8')}
        writeText(info.floatFile, invalid{1});
        updated = replaceKey(original, 'floatSHA256', meteringFileSHA256(info.floatFile));
        writeText(info.manifestFile, updated);
        fail(@() loadMeteringLUTs(selected, [1080, 1920], weight), 'loadMeteringLUTs:InvalidLUT');
    end
    writeText(info.floatFile, data); writeText(info.manifestFile, original);
    loaded = loadMeteringLUTs(selected, [1080, 1920], weight);
    folder = fileparts(info.manifestFile);
    movefile(folder, [folder, '_moved']);
    runtimeCfg = selected; runtimeCfg.regionMeanMethod = 'reciprocal_lut';
    [value, debug] = computeRegionalMean(100, 1, runtimeCfg, loaded);
    check(abs(value-100*512/513) < 1e-12 && debug.address == 0, 'runtime after reciprocal files moved');
    clear owned
    % 校验交付文件，不仅校验临时生成器输出。
    m = base.meta.reciprocal;
    check(isequal(readMeteringColumn(m.fixedPath, m.length), ...
        floor(base.reciprocal * 2^m.fracBits + 0.5)), 'delivered Q18 values');
    check(strcmp(meteringFileSHA256(m.fixedPath), m.fixedSHA256), 'delivered Q18 SHA-256');
    result = struct('passed', numel(checks), 'checks', {checks});
    fprintf('RECIPROCAL_INITIALIZATION_PASS=%d\n', result.passed);

    function check(condition, label)
        assert(condition, 'runReciprocalLUTInitializationTests:Failed', '%s', label);
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
        check(thrown, ['reject ', identifier]);
    end
end

function text = replaceKey(text, key, value)
    text = regexprep(text, ['(?m)^', key, '=[^\r\n]*'], [key, '=', value]);
end

function writeText(file, text)
    fid = fopen(file, 'w', 'n', 'UTF-8'); assert(fid >= 0);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', text);
end
