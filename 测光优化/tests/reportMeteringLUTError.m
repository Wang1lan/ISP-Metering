function report = reportMeteringLUTError(projectDir, outputDir)
%REPORTMETERINGLUTERROR 分离 A/B 地址量化与 B/C 系数量化误差。
% A=保存的连续预处理/区域/融合公式；B=离线浮点表；C=每张 QF 表按自身 F 反量化。
% A/B/C 统一使用当前固定 Top-K 峰值，另以相同现行链路对比旧峰值分支。
% 九张真实图像的 C 从 meteringPreprocess 重新执行，仍不是完整定点模型。
% 暗部/分段阈值样本从明确构造的 block 统计进入区域、峰值、融合流程。
    if nargin < 1, projectDir = fileparts(fileparts(mfilename('fullpath'))); end
    if nargin < 2, outputDir = fullfile(projectDir, 'tests', 'results'); end
    previousPath = path;
    restore = onCleanup(@() path(previousPath));
    addpath(fullfile(projectDir, 'float'), fullfile(projectDir, 'tests', 'reference'));
    if ~isfolder(outputDir), mkdir(outputDir); end
    cfg = createMeteringConfig();
    fov = fullfile(projectDir, '权重配置文件', '圆形有效视场权重_16×16.txt');
    [luts, cfg, mask] = loadMeteringLUTs(cfg, [1080, 1920], fov);
    masks = loadRegionMasks(fullfile(projectDir, '权重配置文件', ...
        '中心视场权重_16×16_75.txt'), fullfile(projectDir, '权重配置文件', ...
        '边缘视场权重_16×16_25.txt'), [1080, 1920], cfg.blockSize, mask);
    cfgA = refA_createMeteringConfig();
    cfgA.peakBlockCnt = cfg.peakBlockCnt;
    oldPeakCfg = cfg;
    oldPeakCfg.peakRatio = cfgA.peakRatio;
    qluts = luts;
    names = {'R', 'alpha', 'lambda'};
    report.fracBits = struct();
    coefficientTemplate = struct('name', '', 'fracBits', 0, 'maxAbs', 0, 'meanAbs', 0, ...
        'uniqueFloat', 0, 'uniqueFixed', 0, 'collapsedAdjacent', 0);
    report.coefficientSummary = repmat(coefficientTemplate, 1, numel(names));
    for k = 1:numel(names)
        name = names{k}; meta = luts.meta.(name);
        assert(~isempty(meta.fixedFile), 'reportMeteringLUTError:MissingFixed', ...
            '误差报告需要三张整数表，请运行 outputMode=both 的生成器。');
        values = readMeteringColumn(meta.fixedPath, meta.length);
        assert(all(values == round(luts.(name) * 2^meta.fracBits)), ...
            'reportMeteringLUTError:QuantizationMismatch', '%s 量化不一致。', name);
        assert(strcmpi(meteringFileSHA256(meta.fixedPath), meta.fixedSHA256), ...
            'reportMeteringLUTError:FixedDigestMismatch', '%s 整数表摘要不一致。', name);
        qluts.(name) = values / 2^meta.fracBits;
        report.fracBits.(name) = meta.fracBits;
        coefficientError = abs(qluts.(name) - luts.(name));
        report.coefficientSummary(k) = struct('name', name, 'fracBits', meta.fracBits, ...
            'maxAbs', max(coefficientError), 'meanAbs', mean(coefficientError), ...
            'uniqueFloat', numel(unique(luts.(name))), 'uniqueFixed', numel(unique(values)), ...
            'collapsedAdjacent', sum(diff(luts.(name)) ~= 0 & diff(values) == 0));
    end
    files = dir(fullfile(projectDir, 'testImg', '*.bmp'));
    assert(numel(files) == 9, 'reportMeteringLUTError:ImageCount', ...
        '本次验收要求现有九张 BMP 图像。');
    rows = struct('category', {}, 'name', {}, 'Lc', {}, 'Lp', {}, ...
        'alphaA', {}, 'alphaB', {}, 'alphaC', {}, 'MrA', {}, 'MrB', {}, 'MrC', {}, ...
        'MfA', {}, 'MfB', {}, 'MfC', {});
    peakChangeRows = struct('name', {}, 'validBlockCnt', {}, 'RminBlockCnt', {}, ...
        'KOld', {}, 'KNew', {}, 'MpOld', {}, 'MpNew', {}, 'MrOld', {}, 'MrNew', {}, ...
        'lambdaOld', {}, 'lambdaNew', {}, 'MfOld', {}, 'MfNew', {});
    sharedNames = {'Y', 'Bi', 'NhMap', 'Ri', 'RminBlockCnt', 'validBlockCnt'};
    sharedMax = zeros(1, numel(sharedNames));
    peakMax = 0; lambdaMax = 0;
    for k = 1:numel(files)
        rgb = imread(fullfile(files(k).folder, files(k).name));
        a = refA_meteringPreprocess(rgb, fov, cfgA);
        b = meteringPreprocess(rgb, mask, cfg, luts);
        c = meteringPreprocess(rgb, mask, cfg, qluts);
        for f = 1:numel(sharedNames)
            field = sharedNames{f};
            left = a.(field); right = b.(field);
            error = max(abs(double(left(:)) - double(right(:))));
            sharedMax(f) = max(sharedMax(f), error);
            assert(error <= 1e-12, 'reportMeteringLUTError:ABMismatch', ...
                '%s 的 A/B %s 不一致：%.17g。', files(k).name, field, error);
        end
        [ra, pa, fa] = afterPreprocess(a, masks, cfgA, [], true);
        [rb, pb, fb, db] = afterPreprocess(b, masks, cfg, luts, false);
        [rc, ~, fc] = afterPreprocess(c, masks, cfg, qluts, false);
        peakMax = max(peakMax, abs(pa.Mp - pb.Mp));
        lambdaMax = max(lambdaMax, abs(fa.lambda - fb.lambda));
        assert(abs(pa.Mp - pb.Mp) <= 1e-12 && abs(fa.lambda - fb.lambda) <= 1e-12, ...
            'reportMeteringLUTError:ABMismatch', '%s 的 Mp/lambda 不一致。', files(k).name);
        rows(end+1) = makeRow('image', files(k).name, ra, rb, rc, fa, fb, fc); %#ok<AGROW>
        oldPeak = refA_peakMetering(b, oldPeakCfg);
        [oldFusion, oldDebug] = fusionMetering(b, rb, oldPeak, cfg, luts);
        assert(rb.valid && oldPeak.valid && pb.valid && oldFusion.valid && fb.valid, ...
            'reportMeteringLUTError:InvalidPeakComparison', '%s 的新旧测光结果必须有效。', files(k).name);
        assert(oldPeak.validBlockCnt == b.validBlockCnt && pb.validBlockCnt == b.validBlockCnt && ...
            oldDebug.validBlockCnt == db.validBlockCnt && db.validBlockCnt == b.validBlockCnt && ...
            oldDebug.RminBlockCnt == db.RminBlockCnt && db.RminBlockCnt == b.RminBlockCnt && ...
            oldDebug.Mr == db.Mr && db.Mr == rb.Mr && ...
            abs(oldFusion.lambda - fb.lambda) <= 1e-12 && ...
            abs(fb.lambda - luts.lambda(b.RminBlockCnt + 1)) <= 1e-12, ...
            'reportMeteringLUTError:PeakComparisonMismatch', ...
            '%s 的新旧峰值对比必须保持有效计数、高光计数、Mr 和 lambda 不变。', files(k).name);
        assert(pb.targetBlockCnt == cfg.peakBlockCnt && pb.selectedBlockCnt == cfg.peakBlockCnt && ...
            abs(oldFusion.Mf - (rb.Mr + oldFusion.lambda * max(0, oldPeak.Mp-rb.Mr))) <= 1e-12 && ...
            abs(fb.Mf - (rb.Mr + fb.lambda * max(0, pb.Mp-rb.Mr))) <= 1e-12, ...
            'reportMeteringLUTError:PeakFusionMismatch', ...
            '%s 的固定 K 或新旧融合公式不一致。', files(k).name);
        peakChangeRows(end+1) = struct('name', files(k).name, ...
            'validBlockCnt', b.validBlockCnt, 'RminBlockCnt', b.RminBlockCnt, ...
            'KOld', oldPeak.targetBlockCnt, 'KNew', pb.targetBlockCnt, ...
            'MpOld', oldPeak.Mp, 'MpNew', pb.Mp, 'MrOld', oldDebug.Mr, 'MrNew', db.Mr, ...
            'lambdaOld', oldFusion.lambda, 'lambdaNew', fb.lambda, ...
            'MfOld', oldFusion.Mf, 'MfNew', fb.Mf); %#ok<AGROW>
        fprintf('ERROR_REPORT_IMAGE %d/%d %s\n', k, numel(files), files(k).name);
    end
    dark = [0, 0; 0.2, 0.3; 0.49, 0.49; 0.49, 0.51; 0.51, 0.49; ...
        0, 0.3; 0.3, 0; 0.99, 1.01; 1.01, 0.99; 1.49, 1.51];
    samples = dark;
    labels = repmat({'dark'}, size(dark, 1), 1);
    for lp = [0, 0.49, cfg.LpMin-1e-6, cfg.LpMin, cfg.LpMin+1e-6, 7.3, 60.4, 170.1]
        for rho = [cfg.rho1, cfg.rho2, cfg.rho3, cfg.rho4]
            for offset = [-0.49, -1e-6, 0, 1e-6, 0.49]
                lc = rho * max(lp, cfg.LpMin) + offset;
                if lc >= 0 && lc <= 255
                    samples(end+1, :) = [lc, lp]; %#ok<AGROW>
                    labels{end+1, 1} = 'threshold'; %#ok<AGROW>
                end
            end
        end
    end
    for k = 1:size(samples, 1)
        a = samplePrep(samples(k, :), mask, masks, cfg, luts);
        c = samplePrep(samples(k, :), mask, masks, cfg, qluts);
        [ra, ~, fa] = afterPreprocess(a, masks, cfgA, [], true);
        [rb, ~, fb] = afterPreprocess(a, masks, cfg, luts, false);
        [rc, ~, fc] = afterPreprocess(c, masks, cfg, qluts, false);
        label = sprintf('Lc=%.9g Lp=%.9g', samples(k, 1), samples(k, 2));
        rows(end+1) = makeRow(labels{k}, label, ra, rb, rc, fa, fb, fc); %#ok<AGROW>
    end
    report.rows = rows;
    report.peakChangeRows = peakChangeRows;
    report.peakBlockCnt = cfg.peakBlockCnt;
    report.oldPeakRatio = oldPeakCfg.peakRatio;
    report.imageCount = numel(files);
    report.sharedStageFields = sharedNames;
    report.sharedStageMaxAbs = sharedMax;
    report.peakMaxAbsAB = peakMax;
    report.lambdaMaxAbsAB = lambdaMax;
    report.summary = summarizeRows(rows);
    fprintf('ERROR_REPORT_SUMMARY images=%d samples=%d\n', numel(files), size(samples, 1));
    report.matFile = fullfile(outputDir, 'metering_lut_error_report.mat');
    report.markdownFile = fullfile(outputDir, 'metering_lut_error_report.md');
    save(report.matFile, 'report');
    writeReport(report.markdownFile, report);
    fprintf('LUT_ERROR_REPORT %s\n', report.markdownFile);
end

function [region, peak, fusion, debug] = afterPreprocess(prep, masks, cfg, luts, original)
    peak = peakMetering(prep, cfg);
    if original
        region = refA_regionalMetering(prep, masks, cfg);
        [fusion, debug] = refA_fusionMetering(prep, region, peak, cfg);
    else
        region = regionalMetering(prep, masks, cfg, luts);
        [fusion, debug] = fusionMetering(prep, region, peak, cfg, luts);
    end
end

function prep = samplePrep(pair, mask, masks, cfg, luts)
    prep.validMask = mask;
    prep.validBlockCnt = nnz(mask);
    prep.Bi = zeros(size(mask));
    prep.Bi(masks.center) = pair(1); prep.Bi(masks.edge) = pair(2);
    prep.NhMap = cfg.blockSize^2 * double(prep.Bi >= cfg.highlightTh & mask);
    prep.Ri = zeros(size(mask));
    prep.Ri(mask) = luts.R(prep.NhMap(mask) + 1);
    prep.RminBlockCnt = nnz(mask & prep.NhMap >= cfg.N2);
end

function row = makeRow(category, name, a, b, c, fa, fb, fc)
    row = struct('category', category, 'name', name, 'Lc', a.Lc, 'Lp', a.Lp, ...
        'alphaA', a.alpha, 'alphaB', b.alpha, 'alphaC', c.alpha, ...
        'MrA', a.Mr, 'MrB', b.Mr, 'MrC', c.Mr, ...
        'MfA', fa.Mf, 'MfB', fb.Mf, 'MfC', fc.Mf);
end

function summary = summarizeRows(rows)
    summary = struct('group', {}, 'comparison', {}, 'metric', {}, 'count', {}, ...
        'maxAbs', {}, 'meanAbs', {}, 'worst', {}, 'worstLc', {}, 'worstLp', {});
    for group = {'image', 'dark', 'threshold', 'all'}
        if strcmp(group{1}, 'all'), selected = rows;
        else, selected = rows(strcmp({rows.category}, group{1})); end
        for pair = {'AB', 'BC'}
            for field = {'alpha', 'Mr', 'Mf'}
                left = [field{1}, pair{1}(1)]; right = [field{1}, pair{1}(2)];
                errors = abs([selected.(left)] - [selected.(right)]);
                assert(all(isfinite(errors)), 'reportMeteringLUTError:NonfiniteError', ...
                    '误差样本必须全部有限，不可忽略无效样本。');
                [maximum, idx] = max(errors);
                summary(end+1) = struct('group', group{1}, 'comparison', pair{1}, ...
                    'metric', field{1}, 'count', numel(errors), 'maxAbs', maximum, ...
                    'meanAbs', mean(errors), 'worst', selected(idx).name, ...
                    'worstLc', selected(idx).Lc, 'worstLp', selected(idx).Lp); %#ok<AGROW>
            end
        end
    end
end

function writeReport(file, report)
    fid = fopen(file, 'wt', 'n', 'UTF-8');
    assert(fid >= 0, 'reportMeteringLUTError:WriteFailed', '无法写入误差报告。');
    done = onCleanup(@() fclose(fid));
    fprintf(fid, '# 测光 LUT 误差报告\n\n生成时间：%s\n\n', datestr(now, 31));
    fprintf(fid, ['A 使用保存的连续预处理、区域和融合公式；B 为离线浮点 LUT；C 为三张整数表按各自 F 反量化后运行的浮点流程。\n\n', ...
        'C 是系数量化验证，不是完整定点模型。九张图像均从预处理重跑 C；暗部和阈值样本从合成 block 统计进入区域、峰值和融合。\n\n']);
    fprintf(fid, 'A/B/C 均使用当前固定 Top-K 算术平均峰值（K=%d），用于隔离 LUT 误差；历史参考源码保持原样。\n\n', ...
        report.peakBlockCnt);
    fprintf(fid, 'R/alpha/lambda 的 F 分别为 %d/%d/%d。\n\n', ...
        report.fracBits.R, report.fracBits.alpha, report.fracBits.lambda);
    fprintf(fid, '## 表系数量化误差与合并\n\n');
    fprintf(fid, '相邻合并指按 TXT 地址顺序，原浮点系数不同、量化后整数编码相同的相邻地址对数量。\n\n');
    fprintf(fid, '|表|F|最大绝对误差|平均绝对误差|不同浮点值数|不同整数值数|相邻合并数|\n');
    fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|\n');
    for k = 1:numel(report.coefficientSummary)
        q = report.coefficientSummary(k);
        fprintf(fid, '|%s|%d|%.12g|%.12g|%d|%d|%d|\n', q.name, q.fracBits, ...
            q.maxAbs, q.meanAbs, q.uniqueFloat, q.uniqueFixed, q.collapsedAdjacent);
    end
    fprintf(fid, '\n## 测光链路误差\n\n');
    fprintf(fid, ['A/B 的 Y、Bi、NhMap、Ri、严重高光计数、有效块计数、Mp、同计数 lambda 均按 1e-12 核验。\n\n', ...
        '未约定 alpha 地址量化的业务容差，因此下列数据不作为图像效果无损或业务精度通过的结论。需用户确认地址量化结果及 F 的精度选择。\n\n']);
    fprintf(fid, '|样本|比较|指标|数量|最大绝对误差|平均绝对误差|最坏样本|\n');
    fprintf(fid, '|---|---|---|---:|---:|---:|---|\n');
    for k = 1:numel(report.summary)
        s = report.summary(k);
        fprintf(fid, '|%s|%s|%s|%d|%.12g|%.12g|%s|\n', s.group, ...
            s.comparison, s.metric, s.count, s.maxAbs, s.meanAbs, s.worst);
    end
    fprintf(fid, '\n## 每图与小数样本明细\n\n');
    fprintf(fid, '|类型|样本|Lc|Lp|alpha A/B/C|Mr A/B/C|Mf A/B/C|\n');
    fprintf(fid, '|---|---|---:|---:|---|---|---|\n');
    for k = 1:numel(report.rows)
        r = report.rows(k);
        fprintf(fid, '|%s|%s|%.9g|%.9g|%.9g / %.9g / %.9g|%.9g / %.9g / %.9g|%.9g / %.9g / %.9g|\n', ...
            r.category, r.name, r.Lc, r.Lp, r.alphaA, r.alphaB, r.alphaC, ...
            r.MrA, r.MrB, r.MrC, r.MfA, r.MfB, r.MfC);
    end
    fprintf(fid, '\n## 九图峰值分支变更对比\n\n');
    fprintf(fid, ['旧峰值使用历史参考的比例 %.9g 和亮度加权平均；新峰值使用固定 K=%d 的算术平均。\n\n', ...
        '两者复用相同的现行预处理、区域测光、LUT 和融合配置。已核验有效块数、高光风险计数、Mr、lambda 不变，Mf 均符合现行融合公式。\n\n', ...
        '本表记录单帧测光变化，不代表已经验证设备曝光闭环或高亮保护效果。\n\n'], ...
        report.oldPeakRatio, report.peakBlockCnt);
    fprintf(fid, '|图像|有效块数|高光风险计数|K 旧/新|Mp 旧/新|Mr 旧/新|lambda 旧/新|Mf 旧/新|\n');
    fprintf(fid, '|---|---:|---:|---|---|---|---|---|\n');
    for k = 1:numel(report.peakChangeRows)
        r = report.peakChangeRows(k);
        fprintf(fid, '|%s|%d|%d|%d / %d|%.9g / %.9g|%.9g / %.9g|%.9g / %.9g|%.9g / %.9g|\n', ...
            r.name, r.validBlockCnt, r.RminBlockCnt, r.KOld, r.KNew, r.MpOld, r.MpNew, ...
            r.MrOld, r.MrNew, r.lambdaOld, r.lambdaNew, r.MfOld, r.MfNew);
    end
end
