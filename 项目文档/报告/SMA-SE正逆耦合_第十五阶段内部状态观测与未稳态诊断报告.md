# SMA-SE 正逆耦合：第十五阶段内部状态观测与未稳态诊断报告

日期：2026-09-06。承接第十四阶段 C180 严格恢复基线。本报告记录实际新增 20 周期、代码修改、可复核数据、图和存储处理；不宣称全部任务完成。

## 1. 结论与权限

- 从已授权 runtime C180 raw/Operating Point 严格连续计算到总 C200，新增 20 周期，未人工重置热容、buffer、本构、温度、相分数或 PI 记忆。
- 机制门禁、模型热控制体闭合、流体质量守恒分别通过；**原周期稳态门禁未通过**，相分数 RMS 为 `0.000400591810392`，原上限 `0.0004`，不放宽。
- 首次取得三条 PI 记忆、210 维本构记忆及其他数值状态的完整时序：73 组、1376 坐标，保存末 11 周期，支持末 10 周期逐样本滞后一周期比较。
- 995 维 Solver Configuration 向量已记录，但物理坐标映射尚未完成；原生库存 U/M 仍仅有末周期完整窗口。因此“全部内部状态稳态”和参数研究授权均保持 false。
- 本次 **runtime 观测 C200 不是论文冻结 C200**。C180 仍是已授权的 runtime 同参数恢复源。新结果保存为诊断合同，未授权新 OP 恢复，更未进入 Table 4 求根。

## 2. 实际运行与结束状态

仿真代码提交：`43def30`。分支：`codex/coupled-simscape-authority`。

输出根目录：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_runtime_state_observation_from180_20260906`

结果子目录：`qian2019_table2_table4_simscape_200cycle_20260906_030358`。

2026-09-06 02:21:07 开始 C180 -> C200；03:20:20 编排器记录末段结果与 maximum_cycles STOP。纯 `sim` 时间 `2054.3153532 s`，其余墙钟时间包含模型构建、历史合并、状态提取、压缩保存和审核，不能将两者混称为仿真时间。

启动器 PID 64944，实际 MATLAB worker PID 49876。两次独立 30 分钟静默等待顺序执行，没有竞争计时器、重复启动或停止健康 MATLAB。第一次等待末 CPU 增量约 2345.97 s，响应正常；第二次等待末 worker 已退出，结果完整。

**原包装脚本确有一个后处理分类错误。** `Audit_HeatDriveECC_SystemEnergyResult.production_pass` 同时要求 periodic，不是纯能量标志。原入口错误地把 false 断言成 energy/mass failure，导致 MATLAB 在完整结果和 STOP 之后退出码 1。原 stdout/stderr 保留，未伪装成无错误退出。修复后使用 `Classify_HeatDriveECC_ObservationGates` 分开判定，离线再审核得到 `transient_observation_complete`；没有重跑、修改 raw 或改动门禁。

## 3. 可复核量与原门限

性能统计窗口为 `1900..2000 s`；能量/质量窗口为末完整周期 `1990..2000 s`。

| 项目 | 实测 | 原判定/边界 |
| --- | ---: | --- |
| 机制门禁 | 1 | 原流量、路线、相变、本构能量等机制检查通过 |
| Eq.9 出口温差 | 28.7099866806 K | 暂态诊断，不是合法 Table 4 端点 |
| Eq.10 SCP | 0.316480027883 W/g | 同上 |
| 端点温度漂移 | 0.0135956484323 K | <= 0.05 K，通过 |
| 同相位温度 max/P99/RMS | 0.233108391 / 0.0382847141 / 0.00833433146 K | P99 <= 0.05 K，RMS <= 0.01 K，通过；max 如实保留 |
| 相分数端点/极值漂移 | 5.94534861013e-8 | <= 1e-4，通过 |
| 同相位相分数 max/P99/RMS | 0.0106503043 / 0.00181388256 / 0.000400591810392 | P99 <= 0.002，通过；RMS > 0.0004，未通过 |
| 源侧热输入 | 826.263445640 W | 方向通过 |
| CHEX 传感器冷量 | 12.9667792921 W | 正向；不是零负载解 |
| HHEX 向环境排热 | 836.208466658 W | 方向通过 |
| 模型热残差 | -0.144916490760 W；相对 1.73301869735e-4 | <= 1e-3，通过 |
| 流体质量相对漂移 | 3.08585122507e-6 | <= 1e-5，通过 |
| SHEX/HHEX/CHEX KCL RMS | 1.70592e-13 / 3.23355e-11 / 0 W | <= 1e-6 W，通过 |
| 泵寄生功 | 11.8429815462 W | 原模型 `power_spec=none`；未注入热账本 |

热闭合通过只是已有模型热控制体闭合。流体库存储能率 `3.16688909684 W`，其中 buffer `3.16159951524 W`，并非零储能稳态。完整设备的一阶定律、泵耗散及附件边界仍未关闭。

## 4. 新观测究竟补齐了什么

原生 Simscape 历史由 1 周期延长为 11 周期，会触发严格 contents checksum 不匹配。分离测试表明仅开启 `SaveState=on` 并保留原生历史长度可兼容 C180；由新增状态日志 OP 再严格恢复一步也通过。全部探针状态均丢弃，不作为恢复源。

新数据为独立 `internal_state_observation.mat`，约 692.54 MiB，末 `1890..2000 s`、每组 110001 个时间样本。未复制进累积 physical 历史，后续也不应无限累积每段的全量状态日志。

| PI 积分器 | 同相位 P99（MPa） | RMS（MPa） | 解释 |
| --- | ---: | ---: | --- |
| SE stage 2 | 6.90185106331e-7 | 4.20851068351e-7 | 独立路线记忆可直接观察，未发明验收阈值 |
| SE stage 4 | 9.50889554610e-7 | 4.96577319212e-7 | 同上 |
| SMA，保留终点 | 1.52423382076e-7 | 7.24506072780e-5 | 最大差值位于终止边界，不能直接解释成积分失稳 |

四个 buffer 的同相位 RMS：SHEX `0.0344620628971 K`，SE-HHEX `3.23398910083e-5 K`，SMA-HHEX `0.0175657139255 K`，CHEX `5.43990475082e-5 K`。SHEX 和 SMA-HHEX 仍明显漂移。图中的 0.01 K 是现有固体温度门限的参考线，不冒称已经预声明的 buffer 门禁。

库存 U/M 八条信号在末十周期的 100001 个样本里只有 10002 个有限值（1989.999..2000 s）。PI 新观测补齐不等于库存长窗口也补齐。

## 5. 终止边界不能与内部复位混为一谈

SMA 积分器在 1890、1900、...、1990 s 的内部周期边界均为 0；2000 s 终止点为 `0.02291100277799 MPa`。源码 `Integrate_HeatDriveECC_Constitutive21_Interface.m` 中 `disable_sma_feedback_during_commutation` 跳过最后总时长边界，末点没有与内部边界相同的复位命令。

完整比较的 SMA 最大差值为 `0.022911002778 MPa`；仅诊断性排除最后一个样本后，最大差值 `1.58090639644e-7 MPa`、RMS `5.00293031718e-8 MPa`。两种统计同时保存，未裁掉原始终点或将较小值用作新通过标准。

独立重算原生产相分数 RMS 与原 summary 一致，为 `0.0004005918103922933`。将周期网格改成半开区间、去掉重复终点的**诊断值**反而为 `0.0004010922375112464`，仍超限。因此不能用该边界差异解释掉相分数周期门禁失败。生产算法及原阈值没有修改。

## 6. Fig08 逐面板说明与绘图审核

文件：结果目录下 `figures_state_audit/Fig08_internal_state_observation.{png,pdf}`，PNG 600 dpi，PDF 矢量文字。标题明确注明 runtime C200、not periodic。

- (a) SMA 积分压力修正：重叠显示第 198/199/200 周期，单独标注最终 10 s 端点，说明其与内部复位点不同，不隐藏异常外观。
- (b) SE 第 2 阶段积分记忆：只显示本路线，不与 SMA 或另一 SE 路线混画；三周期基本重合，精确漂移仍以 JSON 为准。
- (c) SE 第 4 阶段积分记忆：显示其独立活动窗口与保持状态；不能用重合曲线代替数值/物理稳态审核。
- (d) 四个 buffer 的同相位温度 RMS：对数纵轴显示数量级差异，SHEX 与 SMA-HHEX 的慢漂移可直接区分；虚线仅是明确标注的原固体温度参考门限。

PNG 与 Poppler 渲染的 PDF 均逐项看图检查，图例已移离曲线，坐标、单位、对数尺度和终点标记未裁切。`figure_visual_qa.json` 绑定最终两文件哈希。通过的是技术可读性审核，不是期刊同行评审，也不是对新结果作复现通过背书。

## 7. 代码和验证入口

生产观测：`Resolve_HeatDriveECC_StateLoggingPolicy.m`、`Extract_HeatDriveECC_ObservedStates.m`，以及 cycle runner / long continuation 的可选输出接入；默认不开状态日志，模型 options 等价性已回归测试。

启动与恢复烟测：`Start_HeatDriveECC_InternalStateObservation.ps1`、`Run_HeatDriveECC_InternalStateObservation.m`、`Audit_HeatDriveECC_ExtendedLoggingRestore.m`。

审核与图：`Audit_HeatDriveECC_ObservedStateDrift.py`、`Audit_HeatDriveECC_InternalStateCoverage.py`、`Audit_HeatDriveECC_TerminalStateComparison.py`、`Plot_HeatDriveECC_StateObservation.py`。

分类和测试：`Classify_HeatDriveECC_ObservationGates.m`、`Test_HeatDriveECC_ObservationGates.m`、`Test_HeatDriveECC_ObservedStates.m`、`Test_HeatDriveECC_OutputOptions.m`、`test_observed_state_drift.py`。MATLAB checkcode、状态开关/形状/非有限值回归、恢复往返、物理失败与未稳态分类测试均通过；Python 状态类测试共 10 项通过。

在 PowerShell 中复核已有结果，不启动长仿真：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
$run = 'outputs\qian_runtime_state_observation_from180_20260906\qian2019_table2_table4_simscape_200cycle_20260906_030358'
python -m unittest discover -s verification -p 'test_*state*.py' -v
python verification\Audit_HeatDriveECC_ObservedStateDrift.py "$run\internal_state_observation.mat" --output "$run\internal_state_drift.json"
python verification\Audit_HeatDriveECC_InternalStateCoverage.py --contract verification\runtime_observation_c200_diagnostic_contract.json --output "$run\internal_state_coverage.json"
python verification\Audit_HeatDriveECC_TerminalStateComparison.py
pwsh -File verification\Audit_HeatDriveECC_StateObservationPackage.ps1
```

MATLAB 内只做分类回归：`addpath('verification'); Test_HeatDriveECC_ObservationGates;`。重绘入口 `python verification\Plot_HeatDriveECC_StateObservation.py` 会生成新 PDF，重新看图并更新视觉审核哈希前，旧 QA 不能直接沿用。

## 8. 完整结果包与哈希

结果按原位文件、独立代码 ZIP、逐文件 SHA-256 manifest 封装，不复制一份 5 GiB raw 到 ZIP 再占空间。

| 文件 | SHA-256 |
| --- | --- |
| physical_simscape_result.mat | `72A47B76ECECD190E3C92606950274D58B88C99E038C3F18F290DCA57F9E7044` |
| final_operating_point.mat | `2EC167BD44DE604438CB330C0AFB7389BA9F280D24EB011DB43D7668E44DE79D` |
| internal_state_observation.mat | `0F165903FAADDD6709628E599E2F36F69C22123A5294B94338B2FC4162353AD5` |

合同为 `verification/runtime_observation_c200_diagnostic_contract.json`。包索引目录为 `outputs_storage_audit/runtime_observation_c200_release_20260906`，包含 `source_snapshot.zip`、`source_snapshot_sha256.json`、`result_package_manifest.csv`、`package_audit.json`。源码 ZIP 的发布提交与实际仿真提交 `43def30` 分开记录，不能混淆事后修复与仿真时版本。旧 C180 发布 ZIP 不覆盖。

包审计通过只表示完整性、哈希和上述结论自洽；其中 `declared_periodic_gate_pass=false`、`steady_parameter_study_allowed=false` 必须保留。

## 9. 存储和 Git 管理

上一阶段清理后 outputs 约 11.376 GiB；新增本次 5,016,765,753 字节 raw、726,180,958 字节状态观测及小结果，使 outputs 暂升至约 16.776 GiB。这是本次新证据，不是重新堆积淘汰分支。

本阶段预审只列出 49,548,026 字节的可重建 `stage_temperature_probes_50samples.csv`，原位 MAT、cycle summary 与报告保留；2026-09-06 03:37 执行后 outputs 约 **16.730 GiB**。清理清单及前后字节数见 `outputs_storage_audit/cleanup_candidates_20260906_033748.csv`、`cleanup_summary_20260906_033748.txt`。

论文冻结 C200、runtime C180、C40/C60 历史恢复证据均未删除。新观测 raw/OP 仍待语义/恢复审核，不属于已经淘汰的数据。禁止因为本次 periodic=false 就自动清除唯一内部状态观测。无并行 HeatDriveECC MATLAB 时才执行清理，其他用户 MATLAB 工程未触碰。

大数据仍在 Git ignore 范围；提交只含代码、合同、报告与审核脚本。完整代码用新 ReleaseRoot 封装；旧 `783bf22` 的 C180 ZIP 与其原哈希保留。历史 `.git` 无需 destructive reset 或强制 GC。

## 10. 文献比较的准确边界

本次没有声称新增阅读一批论文。沿用已有精确定位与模型映射：`项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`。

Qian 2019 Energy 182:881-899，DOI `10.1016/j.energy.2019.06.094`：Eq.9 与 Eq.10 使用不同性能量；Table 4 的 26.2 K 与 0.64 W/g 必须在合法零负载/零温升边界下配对比较。本次固定 Tc=276.95 K、正冷量、periodic=false，不能把 `T0-Tc=26.2 K` 当作已经求得零负载端点，也不能把 `SCP=0.31648` 直接除以 `0.64` 后宣称复现误差。

Qian 2015 IJR（DOI `10.1016/j.ijrefrig.2015.04.001`）的流体控制体/周期讨论、Qian 2017 Energy（DOI `10.1016/j.energy.2017.09.116`）的稳态/匹配讨论及 Tan/Qian 2020 Energy（DOI `10.1016/j.energy.2020.117261`）的耦合/热输入边界仍是后续检查依据；具体页码与未覆盖项保留在上述定位文件，不能把引用列表等同于定量验证。

## 11. 接下来必须完成的工作

1. 对 995 维 Solver Configuration 状态建立物理坐标/单位映射；用原生 TL 日志交叉核对温度、质量与能量库存，不能以全有限代替物理覆盖。维持原生历史窗口的严格兼容性。
2. 先统一混合系统同相位比较的事件侧语义。对 SMA 终止复位差异做显式诊断，保留原门禁对照，不以删除不利终点或提高阈值换取通过。
3. 追踪 SHEX 与 SMA-HHEX buffer 的慢漂移及库存储能，形成有来源的容限与状态覆盖合同。必要的新续算先严格审核最终 OP、机制/能量/质量和父链；当前诊断合同不授权直接恢复。
4. 只有完整状态有效域通过后，才能转入固定 Tc 外层求根、正交敏感性及 Table 4 两个合法端点。未稳态观察值不进入拟合/插值。
5. 关闭泵耗散/附件边界，完成装置 COP、步长/网格收敛、Qian 多文献对照与独立验证；最终图集和完整修改总报告继续随证据更新。

本阶段交付是实算 20 周期、可重用的状态观测工具、定位到源码的边界诊断、分离的图与完整证据包，不是“全部目标严格审核通过”。
