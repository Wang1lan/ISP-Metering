# 区域归一化倒数 LUT

从项目根目录使用 MATLAB R2022a（标准 JVM）：

```matlab
addpath('LUT/tools');
generateReciprocalLUT; % 仅生成新增倒数表，不生成原三类表
addpath('float', 'float/tests');
initialization = runReciprocalLUTInitializationTests;
numeric = runRegionalReciprocalTests;
```

默认配置及主脚本保留除法、关闭对比。在加载 LUT 前选择：

```matlab
cfg = createMeteringConfig();
cfg.regionMeanMethod = 'reciprocal_lut';
cfg.compareRegionMean = true;
```

主脚本开启对比后保留 `meanComparison`，其中 `division` 和 `reciprocal_lut` 各含区域/融合输出及调试信息；`delta` 统一为 LUT 减除法。正式输出仍由方法字段决定。

`runRegionalReciprocalTests(outputDir)` 的可选目录默认是 `tests/results/regional_reciprocal`，包含数值测试 MAT、九图及合成输入的 A7/8/9/10 误差报告与完整 MAT。扫描只修改自有临时生成器副本，交付默认仍为 A8/F18。旧配置可省略倒数 manifest 和方法字段；启用 LUT 或对比时必须提供倒数 manifest。

平均值误差界仅适用于直接加权平均，不能用来宣称 α 地址变化后的 Mr/Mf 或设备曝光效果已满足业务要求。整数表当前仅作离线编码交付，逐帧仍使用 float 系数。
