# 第三阶段峰值测光（8 bit 浮点参考）

第三阶段复用第一阶段的 `prep.Bi`、`prep.validMask`，与区域测光分支并列计算 `Mp`。默认 `cfg.peakBlockCnt = 512`，输出最亮 K 个有效量化 block 的算术平均。现有第一、二阶段参数保持原值（包括 `rho4 = 1.5`）。

## 调用与数值口径

```matlab
cfg = createMeteringConfig();
[luts, cfg, validMask] = loadMeteringLUTs(cfg, imageSize, weightFile);
prep = meteringPreprocess(img, validMask, cfg, luts);
% regionMask 来自初始化时调用 loadRegionMasks。
[region, regionDebug] = regionalMetering(prep, regionMask, cfg, luts);
[peak, peakDebug] = peakMetering(prep, cfg);
```

- `prep`、`cfg` 必须是标量结构体。`Bi` 为非空、非稀疏、二维实数数值矩阵，全矩阵有限且在 0～255；掩模与其同尺寸，为 logical 或有限的 0/1 数值矩阵。
- `peakBlockCnt` 必填，须为有限实数标量、正整数且为 2 的幂。可选的 `prep.validBlockCnt` 必须为非负整数标量，且等于 `nnz(prep.validMask)`。非法输入明确报错，不限幅或替换默认值。
- 仅在本分支内先转 double，再以 `floor(Bi + 0.5)` 量化为 0～255 整数档；不回写 `prep`。选取和平均均使用量化后的亮度，有效零亮度块也参与候选。
- 直接使用配置 K，不随有效数量 N 动态变化。256 档直方图逆向累计，临界档只取尚缺数量，严格选满 K 个；`0<N<K` 报 `peakMetering:InsufficientValidBlocks`。无有效 block 时目标数与选取数为 0，诊断中仍保留配置 K。
- `S1 = sum(n_b*b)`，输出 `Mp = S1/K`，全零时正常得到 0；不计算平方和，不使用 `Ri` 或区域权重，不执行排序。输入为整数类型时也先转 double，避免累计饱和。
- `Mp` 保留 0～255 标度下的 double 小数。单个 block 量化误差不超过 0.5；相对于相同 K 的未量化 Top-K 均值，`Mp` 的量化误差也不超过 0.5。

## 输出契约

| 输出字段 | 含义 |
| --- | --- |
| `peak.Mp` | double 峰值亮度；无有效 block 时为 NaN |
| `peak.valid`、`peak.status` | logical 有效标志及字符状态，见下表 |
| `peak.validBlockCnt` | 有效 block 数 N，double |
| `peak.targetBlockCnt`、`peak.selectedBlockCnt` | 目标 K 和实际选取数量，double |
| `peak.thresholdBin` | 最后选中的整数档；无有效 block 时为 NaN |
| `peak.sumB` | double 亮度累加值 S1 |
| `peakDebug.histogram`、`peakDebug.selectedHistogram` | `256×1 double`，第 b+1 项对应亮度 b 的总数量、选取数量 |
| `peakDebug.peakBlockCnt`、`peakDebug.actualRatio` | 配置 K 和实际选取比例 K/N；无有效 block 时后者为 NaN |
| `peakDebug.unweightedMean` | 复用 `peak.Mp`，即 S1/K；无有效 block 时为 NaN |
| `peakDebug.quantization` | 字符值 `'roundHalfUpToInteger'` |

| 条件 | Mp | valid | status |
| --- | --- | --- | --- |
| N=0 | NaN | false | `noValidBlocks` |
| N≥K 且 S1=0 | 0 | true | `normal` |
| N≥K 且 S1>0 | S1/K | true | `normal` |

所有正常返回路径均提供完整的两个结构体。量化前不足 0.5 的极暗输入也可能得到零亮度，仍属于正常算术平均。临界档部分选取不对应唯一空间位置，本版本不返回空间 Top-K 掩模。

改变分辨率、blockSize 或有效视场后，须人工检查 K 是否合适。只修改 K 无须重新生成 R、α、λ LUT；不增加独立移位参数，浮点输出保留小数。

## 当前四阶段调用与验证

2026-09-29 的改造将第一、二、四阶段接入离线浮点 LUT，并将峰值算法改为固定 Top-K 算术平均。`createMeteringConfig` 只提供运行参数和三个 manifest 路径；B、rho4=1.5 等映射参数由初始化加载器填充。

```matlab
cfg = createMeteringConfig();
[luts, cfg, validMask] = loadMeteringLUTs(cfg, imageSize, weightFile);
% 初始化 regionMask 后，多帧复用 luts、cfg、validMask 和 regionMask。
prep = meteringPreprocess(img, validMask, cfg, luts);
[region, regionDebug] = regionalMetering(prep, regionMask, cfg, luts);
[peak, peakDebug] = peakMetering(prep, cfg);
[fusion, fusionDebug] = fusionMetering(prep, region, peak, cfg, luts);
```

- `main.m` 使用第 7 张图，权重路径统一为项目下的 `权重配置文件`，lambda 图仍默认关闭。
- 预处理支持可配置正整数 B，保持丢弃不完整 block 和 `Nh >= N2` 的严重高光计数语义。RGB 的值域为 0～255，允许 double 小数。
- 区域阶段只量化 alpha 地址；`Lc/Lp/Mr` 保留 double。诊断字段改为 `Lc_q/Lp_q/alphaAddr/blackFrame`，正常逐帧流程不再计算 rho。
- 原始 `(Lc,Lp)=(0,0)` 才是全黑；非零暗值即使查地址 0，仍用原始小数融合。单区域有效和无可靠区域时不查询 alpha。
- 融合使用 `Mr + lambda*max(0,Mp-Mr)`。仅区域有效时 lambda=0；仅峰值有效时 lambda=NaN；空视场先返回 `noValidBlocks`，不访问 LUT。
- 映射参数加载后只读。修改生成器参数后应重新导出并初始化；图像尺寸或 FOV 改变也须重新初始化。详细流程见 `LUT/README.md`。

从项目根目录执行：

```matlab
addpath(fullfile(pwd, 'float'), fullfile(pwd, 'float', 'tests'));
test_peakMetering;
results = runtests(fullfile('float', 'tests', 'testRegionalMetering.m'));
assertSuccess(results);
results = runtests(fullfile('float', 'tests', 'testFusionMetering.m'));
assertSuccess(results);
main;
```

区域测试覆盖实际加载表、整数地址与 A 参考公式、小数亮度、全黑和各回退。融合测试保留显式标为 `ReferenceA` 的旧公式用例，并以独立历史参数夹具验证原分段行为；生产默认值仍为 P1=0.002、P2=0.03、lambdaMin=0.3、lambdaMax=0.8。

本说明不将旧版测试结果作为新接口的验收结果。LUT 报告的 A/B/C 统一使用固定 Top-K 算术平均，分别评估 A/B 地址量化误差与 B/C 系数量化误差；C 不能称为完整定点模型。另以相同现行预处理、区域结果和 LUT 对比旧峰值分支与新峰值分支，记录九图的 K、Mp、Mr、λ、Mf。结果见 `tests/results/fixed_topk`，历史参考源码和报告保留原样。
