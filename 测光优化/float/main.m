clc;
clear;
close all;

%% 初始导入
% 以脚本所在目录定位资源，从项目根目录或 float 目录运行均可。
scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(scriptDir);
imgDir = fullfile(projectDir, 'testImg');
imgList = ["testImg_1.bmp", "testImg_2.bmp", "testImg_3.bmp", "testImg_4.bmp", ...
        "testImg_5.bmp", "testImg_6.bmp", "testImg_7.bmp", "testImg_8.bmp", ...
        "testImg_9.bmp"];
weightFile = fullfile(projectDir, '圆形有效视场权重_16×16.txt');

img = imread(fullfile(imgDir, imgList(2)));
figure("Name","原图"),imshow(img, []),title("Orignal");

%% 第一阶段：预处理
cfg = createMeteringConfig();
prep = meteringPreprocess(img, weightFile, cfg);

%{
% 预处理参数调试
fprintf("RminBlockCnt: %d\n", prep.RminBlockCnt);
figure("Name", "阶段一"), 
subplot(1, 2, 1), imshow(prep.Y, []), title("Y");
subplot(1, 2, 2), imshow(prep.Ri), title("Ri");
%}

%% 第二阶段：区域测光
% 初始化区域配置：首次生成 TXT，以后读取并保留 regionMask 供逐帧复用。
% 视场、尺寸或 centerRatio 改动后，将开关设为 true 重新生成。
regenerateRegionMasks = false;
imageSize = [size(img, 1), size(img, 2)];
centerFile = fullfile(projectDir, sprintf('中心视场权重_%d×%d_%g.txt', ...
    cfg.blockSize, cfg.blockSize, 100 * cfg.centerRatio));
edgeFile = fullfile(projectDir, sprintf('边缘视场权重_%d×%d_%g.txt', ...
    cfg.blockSize, cfg.blockSize, 100 * (1 - cfg.centerRatio)));

% 不存在区域权重文件，则重新生成
if regenerateRegionMasks || ~isfile(centerFile) || ~isfile(edgeFile)
    [~, ~, regionMaskInfo] = generateRegionMasks( ...
        weightFile, cfg.centerRatio, cfg.blockSize, imageSize, projectDir);
    centerFile = regionMaskInfo.centerFile;
    edgeFile = regionMaskInfo.edgeFile;
end

% 载入中心和边缘区域权重文件
regionMask = loadRegionMasks( ...
    centerFile, edgeFile, imageSize, cfg.blockSize, prep.validMask);

% 每帧调用：区域测光只使用预处理结果、已加载掩模与配置。
[region, regionDebug] = regionalMetering(prep, regionMask, cfg);

% 打印第二阶段相关参数
fprintf('\n');
fprintf('Lc: %.6f, Lp: %.6f, alpha: %.6f, Mr: %.6f, valid: %d, status: %s\n', ...
    region.Lc, region.Lp, region.alpha, region.Mr, region.valid, region.status);
fprintf('rho: %.6f\n', regionDebug.rho);

%{
% 区域测光参数调试
% 查看中心和边缘视场
figure("Name", "中心和边缘视场"), 
subplot(1, 2, 1), imshow(regionMask.center), title("中心视场"),
subplot(1, 2, 2), imshow(regionMask.edge), title("边缘视场");
%}

%% 第三阶段：峰值测光
% 与区域分支共用同一帧 prep，保留独立输出供后续融合使用。
[peak, peakDebug] = peakMetering(prep, cfg);

% 打印第三阶段相关参数
fprintf('\n');
fprintf('Mp: %.6f, peak.valid: %d, status: %s\n', ...
    peak.Mp, peak.valid, peak.status);
fprintf('Nvalid: %d, K: %d, selected: %d, threshold: %g, TopK mean: %.6f\n', ...
    peak.validBlockCnt, peak.targetBlockCnt, peak.selectedBlockCnt, ...
    peak.thresholdBin, peakDebug.unweightedMean);
figure("Name","峰值Bin直方折线"),plot(peakDebug.histogram);
