function cfg = createMeteringConfig()
%CREATEMETERINGCONFIG 生成白光测光第一阶段的浮点模型配置。
% 在此集中修改参数，便于快速实验；也可在调用后修改 cfg 的字段。
% 以下高光和可靠度参数为 8 bit 测试图的初始验证值，尚未完成调参。

    cfg.blockSize = 16;                    % 当前固定为 16×16 block
    cfg.yCoeffs = [0.299, 0.587, 0.114];    % R/G/B 亮度系数，不归一化或取整
    cfg.highlightTh = 200;                % 高光阈值，与 Y 同域；Y >= 阈值即计数
    cfg.N1 = 16;                          % Nh <= N1 时可靠度为 1
    cfg.N2 = 64;                          % Nh >= N2 时可靠度为 Rmin
    cfg.Rmin = 0.1;                       % 可靠度下限，范围 [0, 1]
end
