function report = runAlphaReciprocalTests(outputDir)
%RUNALPHARECIPROCALTESTS 65536 地址及同帧四组合对比；不设业务误差门限。
% outputDir 可选；报告写入新目录，不修改原表、图像、权重或历史报告。
    projectDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if nargin < 1, outputDir = fullfile(projectDir, 'tests', 'results', 'alpha_reciprocal'); end
    previousFolder = pwd; previousPath = path;
    restore = onCleanup(@() restoreEnvironment(previousFolder, previousPath));
    floatDir = fullfile(projectDir, 'float');
    cd(floatDir);
    addpath(floatDir, fullfile(projectDir, 'tests', 'reference'), '-begin');
    names = {'createMeteringConfig', 'loadMeteringLUTs', 'regionalMetering', ...
        'computeRegionalMean', 'divideByReciprocalLUT', 'getCenterWeight', ...
        'getCenterWeightReciprocal', 'compareRegionalMeanMethods'};
    for k = 1:numel(names)
        assert(strcmpi(which(names{k}), fullfile(floatDir, [names{k}, '.m'])), ...
            'runAlphaReciprocalTests:FunctionPath', '%s 未解析到正式 float。', names{k});
    end
    cfg = createMeteringConfig();
    assert(strcmp(cfg.regionMeanMethod, 'reciprocal_lut') && strcmp(cfg.alphaMethod, 'lut2d'));
    weightDir = fullfile(projectDir, '权重配置文件');
    weight = fullfile(weightDir, '圆形有效视场权重_16×16.txt');
    [luts, cfg, valid] = loadMeteringLUTs(cfg, [1080,1920], weight);
    masks = loadRegionMasks(fullfile(weightDir, '中心视场权重_16×16_75.txt'), ...
        fullfile(weightDir, '边缘视场权重_16×16_25.txt'), [1080,1920], cfg.blockSize, valid);
    checks = {'formal function paths and actual defaults'};

    % 保留历史二维接口/结构；公共商不接受均值的亮度限幅。
    noAlphaTable = rmfield(luts, 'alpha');
    [raw, shared] = divideByReciprocalLUT(600, 1, luts);
    [meanValue, meanDebug] = computeRegionalMean(600, 1, cfg, luts);
    check(raw > 255 && meanValue == 255 && meanDebug.rawMean == raw, 'unclipped shared quotient');
    for field = {'normalizedDenominator', 'exponent', 'address', 'reciprocal'}
        check(isequal(meanDebug.(field{1}), shared.(field{1})), ['preserved mean debug ', field{1}]);
    end
    check(isequal([luts.meta.alpha.k1,luts.meta.alpha.k2], ...
        [(cfg.Wc-cfg.alphaMin)/(cfg.rho2-cfg.rho1), ...
         (cfg.alphaMax-cfg.Wc)/(cfg.rho4-cfg.rho3)]), 'initialized alpha slopes');

    oldAlpha = zeros(65536,1); exactAlpha = oldAlpha; newAlpha = oldAlpha;
    exactSegments = oldAlpha; newSegments = oldAlpha;
    for lp = 0:255
        for lc = 0:255
            index = 256*lp+lc+1;
            [oldAlpha(index), oldDebug] = getCenterWeight(lc, lp, luts);
            exactAlpha(index) = refA_getCenterWeight(lc, lp, cfg);
            [newAlpha(index), newDebug] = getCenterWeightReciprocal(lc, lp, noAlphaTable);
            exactSegments(index) = exactSegment(lc, lp, cfg);
            newSegments(index) = newDebug.alphaSegment;
            assert(oldDebug.alphaAddr == index-1 && isnan(newDebug.alphaAddr) && ...
                newDebug.Lc_q == lc && newDebug.Lp_q == lp && ...
                newDebug.blackFrame == (lc == 0 && lp == 0) && ...
                strcmp(newDebug.alphaMethod, 'reciprocal_lut'), ...
                'runAlphaReciprocalTests:Address', '量化/调试字段不一致。');
        end
    end
    check(max(abs(oldAlpha-exactAlpha)) <= 1e-12, '65536 old LUT versus exact five segments');
    check(all(newAlpha >= cfg.alphaMin & newAlpha <= cfg.alphaMax), '65536 reciprocal alpha bounds');
    check(newAlpha(1) == cfg.Wc && newSegments(1) == 0, 'quantized zero special case');
    alphaError = abs(newAlpha-oldAlpha);
    report.exhaustive = struct('pairCount', 65536, ...
        'exactFormulaMaxAbs', max(abs(oldAlpha-exactAlpha)), ...
        'maxAbsAlpha', max(alphaError), 'meanAbsAlpha', mean(alphaError), ...
        'segmentSwitchCount', nnz(exactSegments ~= newSegments));
    [~, worst] = max(alphaError);
    report.exhaustive.worstPair = [mod(worst-1,256), floor((worst-1)/256)];
    report.exhaustive.worstAlpha = [oldAlpha(worst), newAlpha(worst)];

    % 新模式仅在自有临时目录放 alpha manifest，故其二维 TXT 确实不存在。
    temporaryRoot = tempdir; temporaryDir = tempname(temporaryRoot); mkdir(temporaryDir);
    owned = onCleanup(@() removeOwned(temporaryDir, temporaryRoot));
    alphaManifest = fullfile(temporaryDir, 'alpha_manifest.txt');
    copyfile(cfg.lutManifests.alpha, alphaManifest);
    manifestText = fileread(alphaManifest);
    methods = {'division','reciprocal_lut'};
    newLuts = cell(1,2); newCfg = cell(1,2);
    for m = 1:2
        selected = cfg; selected.regionMeanMethod = methods{m};
        selected.alphaMethod = 'reciprocal_lut'; selected.lutManifests.alpha = alphaManifest;
        [newLuts{m}, newCfg{m}, newValid] = loadMeteringLUTs(selected, [1080,1920], weight);
        check((~isfield(newLuts{m}, 'alpha') || isempty(newLuts{m}.alpha)) && ...
            ~isfile(newLuts{m}.meta.alpha.floatPath) && isequal(valid,newValid) && ...
            isequal(luts.reciprocal,newLuts{m}.reciprocal), ['metadata-only initialization ', methods{m}]);
    end
    selected.alphaMethod = 'lut2d';
    mustFail(@() loadMeteringLUTs(selected, [1080,1920], weight), 'loadMeteringLUTs:InvalidLUT');
    selected = newCfg{1}; selected.lutManifests = rmfield(selected.lutManifests,'reciprocal');
    mustFail(@() loadMeteringLUTs(selected, [1080,1920], weight), 'loadMeteringLUTs:MissingReciprocal');
    selected = newCfg{1};
    for replacement = {'rho2=0.4', 'rho2=NaN', 'addressOrder=LpFastest'}
        key = strtok(replacement{1}, '=');
        changed = regexprep(manifestText, ['(?m)^',key,'=[^\r\n]*'], replacement{1});
        writeText(alphaManifest, changed);
        mustFail(@() loadMeteringLUTs(selected, [1080,1920], weight), 'loadMeteringLUTs:InvalidLUT');
    end
    writeText(alphaManifest, regexprep(manifestText, '(?m)^rho2=[^\r\n]*[\r\n]+', ''));
    mustFail(@() loadMeteringLUTs(selected, [1080,1920], weight), 'loadMeteringLUTs:InvalidLUT');
    writeText(alphaManifest, manifestText);
    reciprocalManifest = fullfile(temporaryDir, 'reciprocal_manifest.txt');
    copyfile(cfg.lutManifests.reciprocal, reciprocalManifest);
    copyfile(luts.meta.reciprocal.floatPath, ...
        fullfile(temporaryDir,luts.meta.reciprocal.floatFile));
    writeText(reciprocalManifest, regexprep(fileread(reciprocalManifest), ...
        '(?m)^normalizedMin=[^\r\n]*', 'normalizedMin=0'));
    selected.lutManifests.reciprocal = reciprocalManifest;
    mustFail(@() loadMeteringLUTs(selected, [1080,1920], weight), 'loadMeteringLUTs:InvalidLUT');
    legacy = rmfield(cfg,'alphaMethod'); legacy.regionMeanMethod = 'division';
    [legacyLuts,legacyCfg] = loadMeteringLUTs(legacy,[1080,1920],weight);
    check(strcmp(legacyCfg.alphaMethod,'lut2d') && isequal(legacyLuts.alpha,luts.alpha), ...
        'legacy alphaMethod defaults to lut2d');
    selected = cfg; selected.alphaMethod = 'unknown';
    mustFail(@() loadMeteringLUTs(selected,[1080,1920],weight), 'loadMeteringLUTs:InvalidAlphaMethod');

    inputs = {}; peaks = {}; labels = {}; groups = {};
    for k = 1:9
        labels{end+1} = sprintf('testImg_%d.bmp',k); groups{end+1} = 'image'; %#ok<AGROW>
        prep = meteringPreprocess(imread(fullfile(projectDir,'testImg',labels{end})),valid,cfg,luts);
        inputs{end+1} = rmfield(prep,'Y'); peaks{end+1} = peakMetering(prep,cfg); %#ok<AGROW>
    end
    pairs = [0,0; .2,.3; .49,.49; .49,.51; .5,.49; 0,1; 1,0; ...
        255,0; 255,255; 3,2; 0,255; 255,1];
    for lp = [1,2,10,100,170]
        for rho = [cfg.rho1,cfg.rho2,cfg.rho3,cfg.rho4]
            for offset = [-.5,-.49,-1e-6,0,1e-6,.49,.5]
                lc = rho*lp+offset;
                if lc >= 0 && lc <= 255, pairs(end+1,:) = [lc,lp]; end %#ok<AGROW>
            end
        end
    end
    pairs = unique(pairs,'rows','stable');
    for k = 1:size(pairs,1)+3
        prep = struct('Bi',zeros(size(valid)),'Ri',double(valid),'validMask',valid, ...
            'validBlockCnt',nnz(valid),'RminBlockCnt',0);
        if k <= size(pairs,1)
            pair = pairs(k,:); label = sprintf('Lc=%.9g Lp=%.9g',pair);
            group = 'synthetic';
        else
            pair = [60,90]; fallback = k-size(pairs,1); group = 'fallback';
            label = sprintf('fallback_%d',fallback);
            if fallback ~= 2, prep.Ri(masks.edge) = 0; end
            if fallback ~= 1, prep.Ri(masks.center) = 0; end
        end
        prep.Bi(masks.center) = pair(1); prep.Bi(masks.edge) = pair(2);
        inputs{end+1} = prep; peaks{end+1} = peakMetering(prep,cfg); %#ok<AGROW>
        labels{end+1} = label; groups{end+1} = group; %#ok<AGROW>
    end
    rows = struct('regionMeanMethod',{},'sample',{},'group',{}, ...
        'oldValues',{},'newValues',{},'delta',{},'segmentChanged',{});
    regionFields = {'Lc';'Lp';'alpha';'Mr';'valid';'status';'sumWc';'sumWp'; ...
        'Lc_q';'Lp_q';'alphaAddr';'blackFrame'};
    oldDebugFields = {'Lc_q';'Lp_q';'alphaAddr';'blackFrame';'meanCenter';'meanEdge'};
    for m = 1:2
        oldCfg = cfg; oldCfg.regionMeanMethod = methods{m};
        for k = 1:numel(inputs)
            [oldRegion,oldDebug] = regionalMetering(inputs{k},masks,oldCfg,luts);
            [newRegion,newDebug] = regionalMetering(inputs{k},masks,newCfg{m},newLuts{m});
            oldFusion = fusionMetering(inputs{k},oldRegion,peaks{k},oldCfg,luts);
            newFusion = fusionMetering(inputs{k},newRegion,peaks{k},newCfg{m},newLuts{m});
            assert(isequal(sort(fieldnames(oldRegion)),sort(regionFields)) && ...
                isequal(sort(fieldnames(newRegion)),sort(regionFields)) && ...
                isequal(sort(fieldnames(oldDebug)),sort(oldDebugFields)), ...
                'runAlphaReciprocalTests:LegacyFields', '旧字段结构发生变化。');
            assert(isequaln([oldRegion.Lc,oldRegion.Lp],[newRegion.Lc,newRegion.Lp]) && ...
                isequaln(oldDebug.meanCenter,newDebug.meanCenter) && ...
                isequaln(oldDebug.meanEdge,newDebug.meanEdge) && ...
                oldRegion.valid == newRegion.valid && strcmp(oldRegion.status,newRegion.status) && ...
                oldFusion.valid == newFusion.valid && strcmp(oldFusion.status,newFusion.status) && ...
                isequaln(oldFusion.lambda,newFusion.lambda) && isnan(newRegion.alphaAddr), ...
                'runAlphaReciprocalTests:SameFrame', '切换 alpha 改变了同帧输入或状态。');
            changed = false;
            if isfinite(oldRegion.alphaAddr)
                segment = exactSegment(oldDebug.Lc_q,oldDebug.Lp_q,cfg);
                changed = segment ~= newDebug.alphaSegment;
                assert(newDebug.blackFrame == (newRegion.Lc == 0 && newRegion.Lp == 0) && ...
                    isequal([oldDebug.Lc_q,oldDebug.Lp_q],[newDebug.Lc_q,newDebug.Lp_q]));
            end
            oldValues = [oldRegion.alpha,oldRegion.Mr,oldFusion.Mf];
            newValues = [newRegion.alpha,newRegion.Mr,newFusion.Mf];
            rows(end+1) = struct('regionMeanMethod',methods{m},'sample',labels{k}, ...
                'group',groups{k},'oldValues',oldValues,'newValues',newValues, ...
                'delta',newValues-oldValues,'segmentChanged',changed); %#ok<AGROW>
        end
        % 原区域均值诊断也可在 alpha 新模式下执行。
        comparison = compareRegionalMeanMethods(inputs{1},masks,newCfg{m},newLuts{m},peaks{1});
        check(isfinite(comparison.delta.Mf) && ~comparison.alphaAddressChanged, ...
            ['mean comparison with reciprocal alpha ',methods{m}]);
    end
    check(true,'four combinations preserve old region and lut2d debug fields');
    check(all(isfinite(vertcat(rows.newValues)) | isnan(vertcat(rows.oldValues)),'all'), ...
        'new-mode Mf and common-valid outputs finite without alpha TXT');
    % 只用除法均值时，单侧无效不访问任何 alpha 或倒数表。
    fallbackCfg = newCfg{1};
    fallbackStates = {'onlyCenterValid','onlyEdgeValid','noReliableBlocks'};
    for k = numel(inputs)-2:numel(inputs)
        region = regionalMetering(inputs{k},masks,fallbackCfg,struct());
        check(strcmp(region.status,fallbackStates{k-numel(inputs)+3}), ...
            'fallback skips alpha and reciprocal tables');
    end
    clear owned

    report.metricNames = {'alpha','Mr','Mf'};
    report.imageCount = 9; report.syntheticCount = size(pairs,1); report.rows = rows;
    report.summaries = struct('regionMeanMethod',{},'group',{},'sampleCount',{}, ...
        'maxAbs',{},'meanAbs',{},'commonFiniteCount',{},'segmentSwitchCount',{});
    for m = 1:2
        for group = {'image','synthetic','fallback'}
            selectedRows = rows(strcmp({rows.regionMeanMethod},methods{m}) & strcmp({rows.group},group{1}));
            errors = abs(vertcat(selectedRows.delta));
            maximum = NaN(1,3); average = maximum; count = zeros(1,3);
            for metric = 1:3
                values = errors(isfinite(errors(:,metric)),metric); count(metric) = numel(values);
                if ~isempty(values), maximum(metric) = max(values); average(metric) = mean(values); end
            end
            report.summaries(end+1) = struct('regionMeanMethod',methods{m},'group',group{1}, ...
                'sampleCount',numel(selectedRows),'maxAbs',maximum,'meanAbs',average, ...
                'commonFiniteCount',count,'segmentSwitchCount',nnz([selectedRows.segmentChanged]));
        end
    end
    report.passedChecks = numel(checks); report.checks = checks; report.matlabVersion = version;
    if ~isfolder(outputDir), mkdir(outputDir); end
    save(fullfile(outputDir,'alpha_reciprocal_tests.mat'),'report');
    fid = fopen(fullfile(outputDir,'alpha_reciprocal_tests.md'),'w','n','UTF-8'); assert(fid >= 0);
    closeReport = onCleanup(@() fclose(fid));
    fprintf(fid,'# Alpha 公共倒数 LUT 对比\n\nMATLAB %s；差值为 reciprocal_lut - lut2d。\n\n',version);
    fprintf(fid,'65536 对：旧表/exact 最大误差 %.17g；新 alpha 最大/平均绝对误差 %.17g / %.17g；分段切换 %d 对。\n\n', ...
        report.exhaustive.exactFormulaMaxAbs,report.exhaustive.maxAbsAlpha, ...
        report.exhaustive.meanAbsAlpha,report.exhaustive.segmentSwitchCount);
    fprintf(fid,'同帧比较共用 prep、regionMask 和峰值结果，只切换 alpha；新模式初始化时没有二维 alpha TXT。\n');
    fprintf(fid,'未设置业务精度门限；当前 double/8 位亮度域结果不构成 u12 定点或设备曝光验收。\n\n');
    fprintf(fid,'| 均值方式 | 样本 | 帧数 | alpha 最大/平均绝对误差 | Mr 最大/平均 | Mf 最大/平均 | 分段切换 |\n');
    fprintf(fid,'|---|---|---:|---:|---:|---:|---:|\n');
    for s = report.summaries
        fprintf(fid,'| %s | %s | %d | %.12g / %.12g | %.12g / %.12g | %.12g / %.12g | %d |\n', ...
            s.regionMeanMethod,s.group,s.sampleCount,s.maxAbs(1),s.meanAbs(1), ...
            s.maxAbs(2),s.meanAbs(2),s.maxAbs(3),s.meanAbs(3),s.segmentSwitchCount);
    end
    fprintf('ALPHA_RECIPROCAL_PASS checks=%d pairs=65536 images=9 synthetic=%d\n',numel(checks),size(pairs,1));
    fprintf('ALPHA_ERROR max=%.17g mean=%.17g segmentChanges=%d\n', ...
        report.exhaustive.maxAbsAlpha,report.exhaustive.meanAbsAlpha,report.exhaustive.segmentSwitchCount);

    function check(condition,label)
        assert(condition,'runAlphaReciprocalTests:Failed','%s',label);
        checks{end+1} = label;
    end
    function mustFail(operation,identifier)
        thrown = false;
        try
            operation();
        catch cause
            if ~strcmp(cause.identifier,identifier), rethrow(cause); end
            thrown = true;
        end
        check(thrown,['reject ',identifier]);
    end
end

function segment = exactSegment(lc,lp,cfg)
    if lc == 0 && lp == 0, segment = 0; return; end
    rho = lc/max(lp,cfg.LpMin);
    if rho <= cfg.rho1, segment = 1;
    elseif rho < cfg.rho2, segment = 2;
    elseif rho <= cfg.rho3, segment = 3;
    elseif rho < cfg.rho4, segment = 4;
    else, segment = 5;
    end
end

function writeText(file,text)
    fid = fopen(file,'w','n','UTF-8'); assert(fid >= 0);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'%s',text);
end

function removeOwned(folder,parent)
    file = java.io.File(folder); root = java.io.File(parent);
    absolute = char(file.getCanonicalPath()); base = char(root.getCanonicalPath());
    assert(startsWith(absolute,[base,filesep],'IgnoreCase',true) && ~strcmpi(absolute,base));
    if isfolder(absolute), rmdir(absolute,'s'); end
end

function restoreEnvironment(folder,previousPath)
    cd(folder); path(previousPath);
end
