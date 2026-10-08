# 测光 LUT 验证

环境：MATLAB R2022a，启用 JVM。以下命令在“测光优化”目录执行。

## 离线表、加载器与误差

默认三套 LUT 已随项目交付。仅修改峰值 K 无须重新生成 LUT。本次固定 Top-K 回归使用新输出目录，保留原有历史报告：

```matlab
addpath(fullfile(pwd, 'tests'));
outputDir = fullfile(pwd, 'tests', 'results', 'fixed_topk');
result = runMeteringLUTTests(outputDir);
```

入口穷举 R/λ 全地址及 α 的 65536 个地址，并验证几何、TXT/QF、异常配置、回退、无文件多帧复用，以及 K=256/512 不改变 LUT 表值或元数据。B 和输出模式的变化在自有临时目录中运行生成器副本，不改正式参数区或交付文件。122 个有效块的合成夹具显式使用 K=64。

末尾自动比较全部九张图及暗部/阈值小数样本，生成：

- `outputDir/metering_lut_tests.md`：通过的检查清单。
- `outputDir/metering_lut_error_report.md`：A/B 地址量化、B/C 系数量化误差及九图新旧峰值对比。
- 同名 MAT：完整结构化结果，可在 MATLAB 中继续分析。

只重算误差时运行 `reportMeteringLUTError(pwd, outputDir)`。省略输出目录时两个入口仍写入 `tests/results`，会更新其中同名结果。映射参数改变时，继续按 `LUT/README.md` 运行对应的离线生成器。

A 使用 `reference/refA_*` 的连续预处理、区域和融合公式，A/B/C 的峰值统一使用当前固定 K 算术平均，以隔离 LUT 误差。历史参考文件保持原样，来源见该目录 README。九图的 C 从预处理开始重跑；合成小数样本从明确构造的 block 统计进入区域、峰值和融合。

报告另在相同的现行预处理、区域测光、LUT 和融合配置下，比较旧比例加权峰值与新固定 K 峰值的 K、Mp、Mr、lambda、Mf。验证有效计数、高光风险计数、Mr 和 lambda 不变，Mf 符合现行公式。该对比记录单帧测光变化，不代表设备曝光闭环或高亮保护效果已经通过验证。

## 原有行为回归

```matlab
addpath(fullfile(pwd, 'float'), fullfile(pwd, 'float', 'tests'));
results = runtests({fullfile('float','tests','testRegionalMetering.m'), ...
                   fullfile('float','tests','testFusionMetering.m')});
assertSuccess(results);
summary = test_peakMetering();
```

峰值测试是自行断言并返回 summary 的入口，须单独调用。区域/融合测试已适配新接口；连续公式及历史缓存检查明确使用参考 A，不作为在线实现。

## 主脚本启动

从项目根目录 `addpath('float'); main`，及从 `float` 目录直接 `main`，分别检查默认第 7 张图的输出。`main` 会清空工作区并创建图窗，测试时不要依赖其运行前的临时变量。

自动验证可使用 `set(groot,'DefaultFigureVisible','off')` 隐藏图窗。此检查确认程序和图窗创建路径可运行，不替代人工观察 GUI 或真实设备曝光验证。

业务容差尚未约定。测试中的 `1e-12` 用于应保持一致的中间量/公式，不是 α 地址量化后整帧误差的业务门限。
