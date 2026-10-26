function report = reportRegionalReciprocalError(outputDir)
%REPORTREGIONALRECIPROCALERROR 九图同帧对比及 A7/8/9/10 扫描，保留完整 MAT。
% 合成输入从 block 统计进入；类别名称不是对真实图像的自动分类。
    projectDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if nargin < 1, outputDir = fullfile(projectDir, 'tests', 'results', 'regional_reciprocal'); end
    oldPath = path; restore = onCleanup(@() path(oldPath));
    addpath(fullfile(projectDir, 'float'), fullfile(projectDir, 'float', 'tests'));
    weightDir = fullfile(projectDir, '权重配置文件');
    weight = fullfile(weightDir, '圆形有效视场权重_16×16.txt');
    cfg = createMeteringConfig();
    cfg.regionMeanMethod = 'division';
    cfg.alphaMethod = 'lut2d';
    [luts, cfg, valid] = loadMeteringLUTs(cfg, [1080,1920], weight);
    masks = loadRegionMasks(fullfile(weightDir, '中心视场权重_16×16_75.txt'), ...
        fullfile(weightDir, '边缘视场权重_16×16_25.txt'), [1080,1920], cfg.blockSize, valid);
    inputs = {}; peaks = {}; labels = {}; groups = {};
    for k = 1:9
        label = sprintf('testImg_%d.bmp', k);
        rgb = imread(fullfile(projectDir, 'testImg', label));
        prep = meteringPreprocess(rgb, valid, cfg, luts);
        inputs{end+1} = rmfield(prep, 'Y'); %#ok<AGROW> 小规模诊断样本
        peaks{end+1} = peakMetering(prep, cfg); %#ok<AGROW>
        labels{end+1} = label; groups{end+1} = 'real'; %#ok<AGROW>
    end
    synthetic = {'high',220,255; 'low',1,8; 'uniform',100,100; ...
        'black',0,0; 'threshold',69.5,100.49; 'saturation',255,255};
    for k = 1:size(synthetic,1)
        prep = struct('Bi', zeros(size(valid)), 'Ri', double(valid), ...
            'validMask', valid, 'validBlockCnt', nnz(valid), 'RminBlockCnt', 0);
        prep.Bi(masks.center) = synthetic{k,2};
        prep.Bi(masks.edge) = synthetic{k,3};
        if strcmp(synthetic{k,1}, 'saturation')
            % A8 第一分箱上沿附近会产生 rawMean > 255，同时覆盖 D<1。
            prep.Ri(masks.center) = (1+0.999/256)/nnz(masks.center);
            prep.Ri(masks.edge) = 0.25/nnz(masks.edge);
        end
        inputs{end+1} = prep; peaks{end+1} = peakMetering(prep, cfg); %#ok<AGROW>
        labels{end+1} = ['synthetic_',synthetic{k,1}]; groups{end+1} = synthetic{k,1}; %#ok<AGROW>
    end
    rows = struct('addrBits', {}, 'sample', {}, 'group', {}, 'comparison', {}, ...
        'clipCount', {}, 'alphaComparable', {});
    summaries = struct('addrBits', {}, 'group', {}, 'sampleCount', {}, ...
        'maxAbs', {}, 'meanAbs', {}, 'commonValidCount', {}, ...
        'alphaComparableCount', {}, 'alphaAddressChangedCount', {}, ...
        'alphaAddressChangedRate', {}, 'statusChangedCount', {}, 'clipCount', {});
    for bits = 7:10
        [info, owned] = reciprocalLUTTestFixture(bits); %#ok<ASGLU> 保留 onCleanup 至本轮末尾
        selected = cfg; selected.lutManifests.reciprocal = info.manifestFile;
        tables = loadMeteringLUTs(selected, [1080,1920], weight);
        for k = 1:numel(inputs)
            comparison = compareRegionalMeanMethods(inputs{k}, masks, selected, tables, peaks{k});
            exact = comparison.division; approximate = comparison.reciprocal_lut;
            row = struct('addrBits', bits, 'sample', labels{k}, 'group', groups{k}, ...
                'comparison', comparison, 'clipCount', 0, 'alphaComparable', ...
                isfinite(exact.region.alphaAddr) && isfinite(approximate.region.alphaAddr));
            for pair = {'meanCenter', 'meanEdge'}
                a = approximate.debug.(pair{1}); d = exact.debug.(pair{1});
                if ~isempty(fieldnames(a)) && ~isempty(fieldnames(d))
                    assert(abs(a.rawMean-d.rawMean) <= abs(d.rawMean)/(2*2^bits+1)+1e-9, ...
                        'reportRegionalReciprocalError:MeanBound', '直接平均超出理论误差界。');
                    row.clipCount = row.clipCount + (a.rawMean < 0 || a.rawMean > 255);
                end
            end
            rows(end+1) = row; %#ok<AGROW>
        end
        names = unique(groups, 'stable');
        for k = 1:numel(names)
            selectedRows = rows([rows.addrBits] == bits & strcmp({rows.group}, names{k}));
            summary = struct('addrBits', bits, 'group', names{k}, 'sampleCount', numel(selectedRows), ...
                'maxAbs', struct(), 'meanAbs', struct(), 'commonValidCount', struct(), ...
                'alphaComparableCount', sum([selectedRows.alphaComparable]), ...
                'alphaAddressChangedCount', 0, 'alphaAddressChangedRate', NaN, ...
                'statusChangedCount', 0, 'clipCount', sum([selectedRows.clipCount]));
            for field = {'Lc','Lp','Mr','Mf'}
                values = arrayfun(@(x) x.comparison.delta.(field{1}), selectedRows);
                values = abs(values(isfinite(values)));
                summary.commonValidCount.(field{1}) = numel(values);
                if isempty(values)
                    summary.maxAbs.(field{1}) = NaN; summary.meanAbs.(field{1}) = NaN;
                else
                    summary.maxAbs.(field{1}) = max(values); summary.meanAbs.(field{1}) = mean(values);
                end
            end
            summary.alphaAddressChangedCount = sum(arrayfun(@(x) x.comparison.alphaAddressChanged, selectedRows));
            if summary.alphaComparableCount > 0
                summary.alphaAddressChangedRate = summary.alphaAddressChangedCount/summary.alphaComparableCount;
            end
            summary.statusChangedCount = sum(arrayfun(@(x) x.comparison.statusChanged, selectedRows));
            summaries(end+1) = summary; %#ok<AGROW>
        end
        clear owned
    end
    report = struct('imageCount', 9, 'syntheticCount', size(synthetic,1), ...
        'rows', rows, 'summaries', summaries, 'defaultAddrBits', 8);
    if ~isfolder(outputDir), mkdir(outputDir); end
    save(fullfile(outputDir, 'regional_reciprocal_error_report.mat'), 'report');
    file = fullfile(outputDir, 'regional_reciprocal_error_report.md');
    fid = fopen(file, 'w', 'n', 'UTF-8'); assert(fid >= 0);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '# 区域倒数 LUT 同帧误差报告\n\n');
    fprintf(fid, '环境：MATLAB %s，标准 JVM。九张真实图像各预处理和峰值测光一次，四种表长共用结果。\n\n', version);
    fprintf(fid, '差值为 LUT - division；Lc/Lp/Mr/Mf 误差统计只纳入共同有效且有限的样本。');
    fprintf(fid, '直接平均按 L/(2M+1) 检查；Mr/Mf 不设未经约定的业务门限。\n\n');
    fprintf(fid, 'high/low/uniform 为明确构造的 block 输入：中心/边缘分别 220/255、1/8、100/100，');
    fprintf(fid, 'Ri=1；black=0/0、threshold=69.5/100.49；saturation=255/255 且权重和刻意置于边界。');
    fprintf(fid, '这些类别不表示九张真实图像的分类，合成输入不代替真实图像或设备验证。\n\n');
    fprintf(fid, '默认保持 A8/F18；该扫描不构成未来 u12 项数选择或设备曝光结论。\n\n');
    fprintf(fid, '| A | 类别 | 帧数 | Lc 最大/平均绝对误差 | Lp 最大/平均 | Mr 最大/平均 | Mf 最大/平均 | α 地址改变率 | 状态改变数 | LUT rawMean 限幅数 |\n');
    fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
    for s = summaries
        fprintf(fid, '| %d | %s | %d | %.9g / %.9g | %.9g / %.9g | %.9g / %.9g | %.9g / %.9g | %.6g | %d | %d |\n', ...
            s.addrBits, s.group, s.sampleCount, s.maxAbs.Lc, s.meanAbs.Lc, ...
            s.maxAbs.Lp, s.meanAbs.Lp, s.maxAbs.Mr, s.meanAbs.Mr, s.maxAbs.Mf, s.meanAbs.Mf, ...
            s.alphaAddressChangedRate, s.statusChangedCount, s.clipCount);
    end
    fprintf(fid, '\n逐帧结果（完整两路结构见同名 MAT）：\n\n');
    fprintf(fid, '| A | 样本 | ΔLc | ΔLp | Δalpha | ΔMr | ΔMf | α 地址改变 | 状态改变 | 限幅数 |\n');
    fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
    for r = rows
        d = r.comparison.delta;
        fprintf(fid, '| %d | %s | %+.9g | %+.9g | %+.9g | %+.9g | %+.9g | %d | %d | %d |\n', ...
            r.addrBits, r.sample, d.Lc, d.Lp, d.alpha, d.Mr, d.Mf, ...
            r.comparison.alphaAddressChanged, r.comparison.statusChanged, r.clipCount);
    end
    fprintf('RECIPROCAL_REPORT_PASS images=9 A=7/8/9/10 synthetic=%d\n', size(synthetic,1));
end
