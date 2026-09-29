# 离线 LUT 与浮点测光

三张表在离线生成，主程序初始化时读取 float TXT。逐帧仅查询 R、α、λ；区域加权平均、峰值测光和亮度运算继续使用 double。

## 直接运行

已交付默认 float/Q12 数据及三份 manifest。在“测光优化”目录的 MATLAB 命令窗口运行：

```matlab
addpath(fullfile(pwd, 'float'));
main;
```

也可以进入 `float` 目录直接运行 `main`。资源路径由函数所在目录确定。示例保留第 7 张图及原有显示设置；融合 LUT 图默认关闭。

示例需要在项目根目录自行准备 `testImg/testImg_7.bmp`；测试图像不随本次代码上传。

权重文件使用项目下的“权重配置文件”目录。该目录包含原三份 TXT 的副本，根目录原件保留。

## 修改参数及重新导出

三个生成器均在 `tools` 下，直接无参调用。修改各文件顶部 `USER PARAMETERS BEGIN/END` 之间的参数区：

| 生成器 | 参数 | 默认表长 |
| --- | --- | ---: |
| `generateReliabilityLUT` | B、count/ratio、N1/N2 或 highRatio1/2、Rmin | 257 |
| `generateAlphaLUT` | rho1～rho4、alphaMin/Wc/alphaMax、LpMin | 65536 |
| `generateFusionLUT` | B、imageSize、fovFile、fusionP1/P2、lambdaMin/Max | 5315 |

在项目根目录运行：

```matlab
addpath(fullfile(pwd, 'LUT', 'tools'));
rInfo = generateReliabilityLUT();
aInfo = generateAlphaLUT();
fInfo = generateFusionLUT();
```

每个函数可独立运行，只需重导出受影响的表。默认输出到 `LUT`；`outputDir` 也可选择实验子目录。相对路径以生成器文件所在目录为基准。

- `outputMode='both'` 同时生成 float 和整数；`'float'` 或 `'fixed'` 只记录本次选定格式。遗留文件不会被当成本次输出，fixed-only manifest 不能供浮点主程序加载。
- 各表默认 `fracBits=12`，允许 1～30。编码为 `round(x*2^F)`，反量化为 `Q/2^F`；逻辑位宽为无符号 F+1 位。Q12 中 1.0 编码为 4096，不能截成 4095。
- R 的 count 模式保持绝对阈值；ratio 模式使用 `round(highRatio*B^2)`，取整合并时报错。
- α 的地址为 `256*Lp_q+Lc_q`，Lc 变化最快。首项 `(0,0)` 为 Wc。运行时仅地址四舍五入，Lc/Lp 本身保留小数；精确全黑由原值判断。
- λ 的有效块数来自实际 FOV；默认 Nvalid=5314、C1=11、C2=159。正常融合为 `Mr+lambda*max(0,Mp-Mr)`。

## 初始化与参数归属

```matlab
cfg = createMeteringConfig();
% cfg.lutManifests.R / alpha / lambda 可明确选择另一组 manifest。
[luts, cfg, validMask] = loadMeteringLUTs(cfg, imageSize, weightFile);
regionMask = loadRegionMasks(centerFile, edgeFile, imageSize, cfg.blockSize, validMask);

prep = meteringPreprocess(img, validMask, cfg, luts);
[region, regionDebug] = regionalMetering(prep, regionMask, cfg, luts);
[peak, peakDebug] = peakMetering(prep, cfg);
[fusion, fusionDebug] = fusionMetering(prep, region, peak, cfg, luts);
```

映射参数由 manifest 填入 cfg，加载后视为只读。`createMeteringConfig` 只维护运行参数和文件选择，调表不需要修改第二份映射默认值。

| 修改内容 | 必需操作 |
| --- | --- |
| R / α / λ 映射参数 | 修改对应生成器、重新导出、重新初始化 |
| B | 同步 R/λ 生成器，准备匹配 FOV 和区域掩模，重新导出 R/λ；检查 manifest 选择 |
| 分辨率或 FOV | 更新 λ 参数和掩模，重导出 λ，重新初始化 |
| centerRatio | 重新生成中心/边缘区域掩模 |
| highlightTh、sumWMin、peakRatio | 修改运行 cfg |
| yCoeffs | 修改运行 cfg，保证实际亮度仍处于 0～255 |
| 某张表的 F | 重导出对应表和 manifest；浮点表数值不变 |

初始化检查版本、参数、文件长度、纯单列数值、摘要和几何，失败时明确报错。数据文件和 FOV 的 SHA-256 按原始字节计算，换行等内容变化也需重新导出。校验需要 MATLAB 标准 JVM。运行端不自动生成 LUT。

## 验证

在项目根目录运行：

```matlab
addpath(fullfile(pwd, 'float'), fullfile(pwd, 'tests'));
summary = runMeteringLUTTests();
% 上述入口已生成误差报告；需要单独重算时运行 reportMeteringLUTError()。
```

验证覆盖完整地址、TXT 往返、QF 编码、配置变体、错误文件、回退和多帧复用。变体生成只修改临时目录中的生成器副本。原峰值测试保持原样。

参考 A 保存在 `tests/reference`，其来源摘要记录在该目录说明中。B 为新 float LUT 链路；C 使用各自 F 反量化三张整数表后，从预处理重新运行 double 流程。C 只用于系数量化评估，不能称为完整定点模型。

测试结果与 A/B、B/C 误差报告保存在 `tests/results`。地址量化的业务容差尚未约定，需根据报告中的实测误差确认精度，不能据此宣称无损或实机效果达标。
