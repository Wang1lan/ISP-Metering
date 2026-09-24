function cfg = createMeteringConfig()
%CREATEMETERINGCONFIG 生成白光测光第一至第四阶段的浮点模型配置。
% 在此集中修改参数，便于快速实验；也可在调用后修改 cfg 的字段。
% 以下高光和可靠度参数为 8 bit 测试图的初始验证值。

    cfg.blockSize = 16;                    % 当前固定为 16×16 block
    cfg.yCoeffs = [0.299, 0.587, 0.114];    % R/G/B 亮度系数，不归一化或取整
    cfg.highlightTh = 180;                % 高光阈值，与 Y 同域；Y >= 阈值即计数
    cfg.N1 = 10;                          % Nh <= N1 时可靠度为 1
    cfg.N2 = 50;                          % Nh >= N2 时可靠度为 Rmin
    cfg.Rmin = 0.3;                       % 可靠度下限，范围 [0, 1]

    % 第二阶段：以下为已选定的调试初值。
    cfg.centerRatio = 0.75;              % 中心占有效 block 数量的比例，离线划分
    cfg.rho1 = 0.5;                      % 低值恒定区上界
    cfg.rho2 = 0.9;                      % 死区下界
    cfg.rho3 = 1.1;                      % 死区上界
    cfg.rho4 = 1.5;                        % 高值恒定区下界
    cfg.alphaMin = 0.25;                 % 低比值端中心融合权重
    cfg.Wc = 0.5;                        % 死区权重，与 centerRatio 独立
    cfg.alphaMax = 0.75;                 % 高比值端中心融合权重
    cfg.LpMin = 1;                       % 比值分母下限，采用 0~255 亮度标度
    cfg.sumWMin = 0;                     % 区域 Ri 权重和须大于此值才有效

    % 第三阶段：有效 block 中参与峰值测光的比例。
    cfg.peakRatio = 0.10;

    % 第四阶段：融合参数。
    cfg.fusionP1 = 0.002;                % 严重高光 block 占比
    cfg.fusionP2 = 0.03;                 % 达到最大融合权重的占比阈值
    cfg.lambdaMin = 0.3;                 % 峰值分支最小融合强度
    cfg.lambdaMax = 0.8;                % 峰值分支最大融合强度
end
