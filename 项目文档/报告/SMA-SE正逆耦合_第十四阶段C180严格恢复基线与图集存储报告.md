# 第十四阶段：C180 严格恢复基线、图集和存储治理

日期：2026-09-06。本文接续第十三阶段，记录实际运行、原始证据、代码、逐图解释、复核命令及未完成项。

## 1. 结论和声明边界

从已独立严格审核的 C60 完整 Operating Point 连续推进至 C180，新增 120 个循环。
六个 20-cycle 分段全部通过原机制门禁；C180 首次通过原先声明的周期漂移门禁，
编排器于本地时间 2026-09-06 00:37:46 正常写入 STOP。没有重置状态，没有使用 C246 失败链。
C180 又在独立 MATLAB 会话中通过 contents/interface checksum=`error` 的 1 ms 严格恢复。

**这不是整个目标完成，也不是 Qian Table 4 复现。**

原周期门禁覆盖 SMA/SE 轴向固体温度、相分数以及 SHEX/HHEX/CHEX 温度，未覆盖全部
buffer 库存和 PI 路线记忆。新增只读审计已量化出 buffer 仍有漂移；库存只有末周期完整
原生观测，PI 记忆没有完整时序。故 C180 仅授权同参数连续性及内部状态审核，
`steady_parameter_study_allowed=false`。不得作为已经完全稳态的 Table 4 求根或敏感性起点。

C200 仍是冻结的论文性能基准，不替换其原始结果；C246 仍是不可传播的历史诊断证据。
模型热控制体守恒通过不等于包含泵功耗散及所有附件的完整设备一阶定律通过。

## 2. 这一轮实际运行了什么

源代码运行版本：`6a5df5c456c550c4e580e382eb6d3dcdf60f658a`。
本阶段新的绘图、审计和研究入口门禁只作后处理/授权控制，未改写 C180 raw/OP。

| 分段终点 | 完成时间（UTC+8） | 机制 | 原周期门禁 | Eq.9/K | Eq.10 SCP/(W/g) |
|---|---|---:|---:|---:|---:|
| C80 | 09-05 19:19:30 | 1 | 0 | 28.62887067 | 0.315509553 |
| C100 | 09-05 20:22:53 | 1 | 0 | 28.67486920 | 0.316076075 |
| C120 | 09-05 21:26:33 | 1 | 0 | 28.69530918 | 0.316322022 |
| C140 | 09-05 22:24:54 | 1 | 0 | 28.70406142 | 0.316419088 |
| C160 | 09-05 23:31:05 | 1 | 0 | 28.70779333 | 0.316459407 |
| C180 | 09-06 00:37:46 | 1 | 1 | 28.70935532 | 0.316475000 |

从 09-05 18:16:47 启动至 STOP 约 6 小时 21 分钟，包括构建、数据落盘和审核。
启动器 PID 39196、worker PID 54824 已自然退出。当前主链不存在待中止的健康 MATLAB。
长任务期间使用唯一 30 分钟定时命令，保持同一回合附着，自然返回 JSON 后才检查。

权威进度及 STOP 证据在：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_runtime_shutdown_recovery_from60_20260905`

其中 `steady_continuation_progress.csv`、`steady_continuation_state.mat`、`matlab_stdout.log`
和 `matlab_stderr.log` 均保留。旧原链 C40 state 不改写；C60 关机中断补审见第十三阶段。

## 3. 结果位置与不可变哈希

以下目录简称 R，绝对路径为：

```text
C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_runtime_shutdown_recovery_from60_20260905\qian2019_table2_table4_simscape_180cycle_20260906_002332
```

| R 内文件 | 字节 | SHA-256 |
|---|---:|---|
| physical_simscape_result.mat | 4515089940 | 1E3A225BFEEE5D1798C66B926A7AAD9949E06463C6971930231D93F16BB96E6A |
| final_operating_point.mat | 3826339 | C1F5CEC81B48BC048D4D5C9E6CF57C99B593FBE6641ABD6485038DE2866318AF |

R 还包含逐周期物理摘要、参数合同、完整门禁报告、`strict_restore_audit.json`、
`system_energy_audit.json`，以及 `figures_sci` 中七张 600 dpi PNG 与 PDF。
恢复资格和允许用途由以下受版本控制文件声明：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\verification\runtime_c180_recovery_contract.json`

完整代码是工作区 Git 中的代码、模型、验证器及文档，不是只有几个脚本。运行时版本的
完整 tracked source ZIP 在 `outputs_storage_audit\shutdown_recovery_20260905\source_snapshot.zip`，
SHA-256 为 `426C19B145E851EA20B22C9E015A5BD326A130135FC32D0E08BACBF835CB9963`。
最新发布代码另以本阶段 source snapshot 和提交号记录，不把两者混为同一版本。
结果包是原位 manifest，不再把多个 GB 的 MAT 复制进 ZIP；下载/迁移应按 manifest 取文件。

最新发布完整代码快照为：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\runtime_c180_release_20260906\source_snapshot.zip`

其 `source_snapshot_sha256.json` 记录发布提交号、运行提交号和 ZIP 哈希；
总包的 `outputs_storage_audit\final_results_manifest_20260824.csv` 与
`final_results_sha256_20260824.csv` 是当前实际文件及哈希清单，文件名沿用历史，
当前生成时间见 `final_results_audit_summary_20260824.json`。

## 4. 门禁与性能的实际数值

Eq.9/Eq.10 窗口为最后十周期，即 1700-1800 s。固定 CHEX 温度 276.95 K；
外部负载设为 0 W 不意味着固定温度储库没有吸热，因此不能自动视作 zero-load root。

| 项目 | C180 数值 | 解释 |
|---|---:|---|
| Eq.9 出口温升 | 28.7093553213 K | 不是 T0-Tc 的简单储库温差 |
| Eq.10 冷量 | 13.2339833371 W | 正冷量，非零负载求根结果 |
| Eq.10 SCP | 0.316475000393 W/g | 采用当前文献质量基准 |
| CHEX 热流传感器冷量 | 12.966545404 W | 与 Eq.10 差 0.267437933 W，约 2.02084% |
| 端点温度最大漂移 | 0.013670478 K | 限值 0.05 K，通过 |
| 同相位温度 P99/RMS | 0.036240454 / 0.007888078 K | 限值 0.05 / 0.01 K，通过 |
| 相分数端点/极值漂移 | 1.26149276e-7 | 限值 1e-4，通过 |
| 同相位相分数 P99/RMS | 0.001741540 / 0.000380381 | 限值 0.002 / 0.0004，通过 |
| 同相位温度/相分数最大值 | 0.186245276 K / 0.008460178 | 保留报告，不拿 P99 冒充全样本最大值 |
| ALL_REQUIRED_PASS | 0 | Table 4 未复现，不是机制失败 |

C180 门禁报告中“valid performance-curve point”的措辞必须按本报告进一步收窄：
它是原已声明门禁下的固定温度观测点，不是全部内部状态稳态已经证实的可插值点。

## 5. 能量审计及缺口

原生库存只支持最终完整周期 1790-1800 s 的当前审核，10001 个样本。

| 能量/质量项 | 数值 |
|---|---:|
| SHEX 输入 / CHEX 吸热 / HHEX 排热 | 826.230698 / 12.966600 / 836.160867 W |
| 净外部热输入 | 3.036430754 W |
| buffer / 全模型储能变化率 | 3.178637579 / 3.183876647 W |
| 模型热残差 | -0.147445893 W |
| 审计归一化热残差 | 1.763367532e-4，限值 1e-3，通过 |
| SHEX / HHEX / CHEX 节点 KCL RMS | 1.6613e-13 / 3.2295e-11 / 0 W |
| 流体质量相对漂移 | 3.085874316e-6，限值 1e-5，通过 |
| 报告的 SMA+SE 寄生泵功 | 11.842956263 W |
| 原生压力源热力功 | 0 W（当前 power_spec=none） |

buffer 储能约 3.18 W 不能被忽略。把它纳入一阶能量账才能判断热控制体守恒，
但账目守恒仍不能证明 buffer 跨周期已经不漂移。
泵功目前仅单列，未作为耗散热进入模型，故完整设备闭合与 system COP 均未授权。

新增只读 HDF5 审计 `Audit_HeatDriveECC_InternalStateCoverage.py`（验证冻结 SHA 后切片读取）
在 1700-1800 s 内用相隔 10 s 的样本直接比较，结果为：

| buffer | 同相位 P99/K | RMS/K | 诊断 |
|---|---:|---:|---|
| SHEX | 0.052678738 | 0.036887167 | 若采用原温度阈值，两项均超限 |
| HHEX | 0.000086050 | 0.000067954 | 小漂移 |
| SMA-HHEX | 0.024239755 | 0.017135316 | 若采用原 RMS 阈值，超限 |
| CHEX | 0.000037771 | 0.000059820 | 小漂移 |

这只是扩展诊断，不追溯性改写生产门禁或宣称已预先通过新门禁。8 条 U/M 库存信号
100001 个窗口样本中仅 10002 个有限，覆盖 1789.999-1800 s；PI 记忆无完整时间序列。
机器可读证据：`outputs_storage_audit\runtime_c180_release_20260906\internal_state_coverage.json`。

## 6. 七张图逐张向负责人解释

所有图的数据均来自 R 的实际解，未用示意曲线替代数据。v3 修复了旧图的图例裁切、
低对比子图标签、错误的拒绝点外推及混合量纲坐标；保留原始瞬态尖峰，不为美观平滑结果。

1. **Fig01_last_cycle_mechanism**：上图是 SMA/SE 平均温度与冷热端温度；中图是相变分数，
   可见热驱动 SMA 和受力 SE 的反向相变；下图是 SMA 流量幅值和 SE 排热/制冷路线有符号流量。
   双轴仅用于明确分开的流量尺度，阶段竖线共用；阀切换尖峰完整显示，不裁到 4.2 g/s。
   此图解释正逆耦合的时序，不证明每个轴向位置都同步，也不能替代流量门禁。
2. **Fig02_last_cycle_axial_fields**：四个热图将 SMA/SE 温度和相分数分别按轴向位置、周期相位展开。
   SE 的轴向温差和相变前沿比平均曲线更清楚，揭示单一平均温度遮蔽的信息。
   温度色标分别注明范围；相分数共用物理 0-1 范围。21 节点可见，不插值伪装网格收敛。
3. **Fig03_periodic_convergence**：分别显示端点温度、端点漂移、逐周期 Eq.9、SCP。
   漂移图采用对数尺度且声明 1e-6 K 显示下限；Table 4 水平线仅是不同边界的参考值。
   图中“declared-state”限定范围，曲线变平不等于全 buffer/PI 稳态，更不等于复现。
4. **Fig04_control_and_energy**：压力命令、液压功率、本构热源及固体周期能量分别成图。
   压力符号跟随端口方向；本构热源包含相变与机械传递，不是设备外部热输入。
   固体柱形账中管路热和本构热大体抵消，小残差另有数值审核；泵功不能藏入热驱动 COP。
5. **Fig05_table4_boundary_audit**：只画 Qian zero-lift、zero-load 两个不同端点和当前固定 Tc 点。
   已删除历史拒绝点、连线和线性外推根。当前点有 0.316475 W/g 正冷量，不能与 26.2 K
   的 zero-load 点直接算复现误差；它也不是 0 K 温升下的 0.64 W/g 端点。
6. **Fig06_direct_SHEX_control_volume**：上图分开源到热端、热端到流体及热端储能；下图积分比较。
   源热并非机械功，瞬时输入和传给流体的热可以因储能而不同。末周期平均传递约 826.23 W，
   累积局部残差很小。右轴明确为无量纲局部积分残差，不能与整机热残差混用。
7. **Fig07_modeled_system_energy_ledger**：外部三条热边界、累积能量、各库存储能、无量纲积分残差、
   局部 KCL 分五个面板。KCL 单独使用 W 轴，50 ms 分箱保留最大绝对值而非平均值，
   1e-6 W 线标为 RMS 门禁参考，不冒充逐样本门禁。buffer 主导剩余储能。
   图中积分残差以整周期源热归一化，约 1.78e-4；JSON 门禁按其边界热流基准得到 1.763e-4，
   两个分母不同且均明确说明。设备泵耗散未耦合的限制直接写在图内。

图集审核是本地可读性/信息真实性审核，不是声称获得 SCI 期刊审稿接受。结果仍需负责人
按实际投稿版面审核字体、灰度和 caption；当前提供高分辨率 PNG、矢量曲线 PDF 和可重绘源码。

## 7. 文献是如何对比的

沿用已核对的本地 PDF 页码索引，不声称本阶段重新完整阅读 Zotero：
[Qian 本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。

| 文献与位置（PDF 从第一页计） | 本模型实际比较 | 不能据此推出 |
|---|---|---|
| Qian 2019, Energy 182, 881-899，第 3-4 页 Fig.1，第 5 页 Eqs.9-10，第 16-17 页 Table 4 | 拓扑/正逆相变时序、同质量定义下冷量、十周期窗口、不同端点单独列点 | 任意固定 Tc 点复现最大温升和最大 SCP |
| Tan 2020, Energy 197, 117261，第 6 页兼容方程，第 7-9 页输入热/质量比 | 内部机械传递正负抵消、源热分母和泵功单列 | 以材料级 COP 代替完整设备 COP |
| Qian 2015, IJR 56, 65-80，第 6-8 页流体控制体，第 10 页循环稳态 | 管路/buffer/端点热容储能和同相位漂移 | 平均固体温度变平即全部流体库存稳态 |
| Qian 2017, Energy 141, 744-756，第 6 页稳态/网格，第 9-10 页匹配 | 21 节点轴向温度/相变前沿和匹配时序 | 21 节点单次结果已经做过网格独立性验证 |

本图集与文献比较的是变量定义、物理边界、曲线信息组织及门禁，不以“看起来像论文”
证明定量正确。真正 Table 4 比较仍需共同参数下、全部有效域通过的两个端点。

## 8. 本阶段代码修改清单

以下均在 `C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote` 下。

| 文件 | 修改与验证目标 |
|---|---|
| Plot_HeatDriveECC_SCI_FigureSet.m | 七图 v3，修正拒绝点外推、量纲混杂、裁切、流量尖峰范围与标签 |
| verification/runtime_c180_recovery_contract.json | 固定 SHA、恢复成功、适用范围和未完成状态 |
| verification/Audit_HeatDriveECC_RuntimeBaselinePackage.ps1 | C180 raw/OP、能量、严格恢复、六段提升史和图集 manifest 审核 |
| verification/Audit_HeatDriveECC_InternalStateCoverage.py | 不加载整个 MAT 的冻结结果切片诊断，量化 buffer 漂移和库存覆盖 |
| verification/test_internal_state_coverage.py | 周期、线性漂移、缺失值、非法维度四项测试 |
| verification/Run_HeatDriveECC_Table4_OuterSolve.m | 在创建候选目录/运行模型之前拒绝研究资格为 false 的合同 |
| verification/Test_HeatDriveECC_RuntimeStudyGuard.m | 验证 C180 被拒绝且不创建目录 |
| verification/Manage_HeatDriveECC_OutputStorage.ps1 | C246 raw 只有替代 C180 包审核通过后才允许退役 |
| verification/Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1 | C246 原始数据退役后仍检查其小 OP、冻结合同及替代证据 |
| verification/Audit_FinalHeatDriveECC_Package.ps1 | v13 纳入 C180、内部覆盖及当前代码/报告，淘汰 raw 不再强制必需 |
| verification/Build_HeatDriveECC_RuntimeSourceSnapshot.ps1 | 只从干净 Git 提交封装全部 tracked 源码，不复制 raw；拒绝覆盖不同历史快照 |

第十三阶段已提交的恢复、绘图开关、异常结束识别和默认保护未淘汰文件等修复不重复算作
本阶段新改；其提交为 `5bf21ef` 和 `6a5df5c`。

## 9. 负责人可运行的完整复核入口

快速审核不启动仿真，不改写 raw/OP：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p test_internal_state_coverage.py -v
python verification/Audit_HeatDriveECC_InternalStateCoverage.py --output outputs_storage_audit/runtime_c180_release_20260906/internal_state_coverage.json
pwsh -File .\verification\Audit_HeatDriveECC_RuntimeBaselinePackage.ps1
pwsh -File .\verification\Audit_FinalHeatDriveECC_Package.ps1
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
git status --short --branch
```

Python 诊断依赖 h5py 和 numpy。已在本机实际运行四项单元测试通过。
MATLAB R2025b 已实际完成新代码 checkcode、研究资格拒绝测试、七图重绘及历史包验证。
在无本工程活动仿真时，负责人可独立执行：

```matlab
addpath(pwd); addpath('verification');
Test_HeatDriveECC_OutputOptions;
Test_HeatDriveECC_RuntimeStudyGuard;
c = jsondecode(fileread('verification/runtime_c180_recovery_contract.json'));
r = c.result_relative_path; op = c.checkpoint_relative_path;
e = Audit_HeatDriveECC_SystemEnergyResult(r, fullfile(fileparts(r),'independent_energy_audit.json'));
s = Audit_HeatDriveECC_OperatingPointRestore(r,op,fullfile(fileparts(r),'independent_strict_audit.json'));
assert(e.production_pass && s.strict_restore_pass);
assert(~e.complete_device_first_law_closure);
Plot_HeatDriveECC_SCI_FigureSet(r);
Verify_FinalHeatDriveECC_Package;
```

`Verify_FinalHeatDriveECC_Package` 主要复核历史 C200 等包；当前 C180 必须同时运行新的
PowerShell 基线包审核，不能把旧 `RESULT_PACKAGE_PASS=1` 当作 C180 全部科学门禁通过。
严格恢复审核只是 1 ms 连续性烟测，不能替代 20-cycle 稳态或完整内部状态审核。

## 10. 存储与 Git 审计

本轮开始前旧工作区已由先前治理降低到约 13.6 GiB；不能将最早“120 GB”至今的下降
全部归为本次删除。9 月 5 日先清理 52 个可重建文件，实际释放 47,276,384 字节。
新长链每次后继验证通过后及时压缩前段 raw/OP，C80/C100/C120/C140/C160 的删除审计
保留在各运行的 `SUPERSEDED_RAW_COMPACTED.txt`，最终 C180 MAT 保留合并的历史。
各段释放字节分别为 2011189958、2512883654、3013775373、3515570700、4017536538。

分段滚动压缩共释放 15,070,956,223 字节（14.035922 GiB），是运行期间避免重复历史累积，
不能与工作区净大小下降混为一谈。C60 位于旧根，编排器拒绝跨根删除，故 C40/C60 证据仍在。

09-06 01:36 实际受控删除 8 项：C246 已淘汰 raw 及 7 个 dense probe，共
6,351,608,193 字节（5.915396 GiB）。`outputs` 从 17.290985 GiB 降至 11.375589 GiB；
总工作区在新发布代码 ZIP 生成前测得 12.078355 GiB，生成约 52 MiB 的 ZIP 后约 12.13 GiB。
保留 C200、C180、C40/C60 raw/OP 和 C246 小 OP、原哈希、诊断图、日志、摘要。
大型 MAT 没有进入 Git，也没有打包复制第二份。

清理证据：`outputs_storage_audit\cleanup_summary_20260906_013620.txt` 和同时间的
`cleanup_candidates_20260906_013620.csv`，逐文件列明路径和字节数；删除前确认本工程
MATLAB 引用数为 0，全部路径解析在 outputs 内。随后
`cleanup_summary_20260906_013720.txt` 二次 dry-run：`candidate_count=0`。
Git 对象审计：packs 约 62.09 MiB，loose 约 0.48 MiB，garbage=0，无需重写历史或强制 GC。

七张最终 PNG 和七张 PDF（Poppler 渲染）全部逐图复核；检查记录、图片哈希及限制见
`outputs_storage_audit\runtime_c180_release_20260906\figure_qa.json`，更换图文件会使包审核失败。
MATLAB 重绘与守卫测试日志位于 `outputs_storage_audit\shutdown_recovery_20260905` 的
`matlab_stdout_c180_figures_v3.log`、`matlab_stdout_c180_figures_final.log`，退出码均为 0。
MATLAB 只提示大数据矢量导出可能较慢，没有将此性能提示计作物理门禁。

## 11. 未完成事项和接下来的主线

1. 从 C180 做同参数、严格恢复的扩展状态审核；先预声明 buffer 温度、质量/能量库存和
   PI 路线记忆的同相位观测及阈值，不能看到结果后放宽阈值。用流式标量/按周期摘要限制空间。
2. 对当前有漂移的 SHEX、SMA-HHEX buffer，判断是慢热容收敛还是边界/旁通/累积库存问题。
   严禁以重置 buffer 或 PI 的方式获得“稳态”。增加日志如果改变模型 checksum，必须先审核
   生产匹配恢复；不允许 warning 部分恢复。无兼容 OP 时另建冷态分支并如实记录。
3. 全内部状态有效域通过后才授权固定 Tc 外层求解。每个候选保持相同参数/记忆链与独立
   末十周期窗口，失败候选不进入插值或敏感性效应。
4. 以共同参数求得 zero-load（冷量为零）和 zero-lift（Eq.9 为零）两个合法端点，再与
   Qian Table 4 的 26.2 K、0.64 W/g 做成对定量审核，不能拿不同边界的单点直接调参。
5. 补齐泵功耗散/附件边界，定义 heat-driven 与 complete-device COP，完成网格/步长
   收敛和独立实验或文献数据验证；当前结果不能宣称 experimentally validated。

本阶段交付的是可严格恢复、带完整证据与诚实边界的 runtime 基线及图集，不是最终复现。
