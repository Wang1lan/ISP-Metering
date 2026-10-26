function cfg = createMeteringConfig()
%CREATEMETERINGCONFIG 白光测光运行参数及离线 LUT 选择。
% 映射参数由 loadMeteringLUTs 从 manifest 填充；加载后不可修改。
% 修改映射时应调整 LUT/tools 中对应生成器，再导出并重新初始化。

    projectDir = fileparts(fileparts(mfilename('fullpath')));
    lutDir = fullfile(projectDir, 'LUT');
    cfg.lutManifests.R = fullfile(lutDir, 'LUT_R_B16_manifest.txt');
    cfg.lutManifests.alpha = fullfile(lutDir, 'LUT_Alpha_L8_manifest.txt');
    cfg.lutManifests.lambda = fullfile(lutDir, 'LUT_Lambda_B16_N5314_manifest.txt');
    cfg.lutManifests.reciprocal = fullfile(lutDir, 'LUT_Reciprocal_A8_manifest.txt');
    cfg.regionMeanMethod = 'reciprocal_lut'; % 'division' 或 'reciprocal_lut'
    cfg.alphaMethod = 'lut2d';          % 'lut2d' 或 'reciprocal_lut'，独立选择
    cfg.compareRegionMean = false;     % 同帧两路诊断，不改变正式输出选择

    cfg.yCoeffs = [0.299, 0.587, 0.114]; % R/G/B 系数，保持 0~255 亮度域
    cfg.highlightTh = 180;             % Y >= 此阈值的像素计入 Nh
    cfg.centerRatio = 0.75;            % 初始化区域划分使用
    cfg.sumWMin = 0;                   % 区域权重和须严格大于此值
    cfg.peakBlockCnt = 512;            % 参与峰值测光的最亮有效块数，必须为 2 的幂
end
