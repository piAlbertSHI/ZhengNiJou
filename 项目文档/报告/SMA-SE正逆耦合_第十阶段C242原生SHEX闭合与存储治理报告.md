# SMA-SE 正逆耦合第十阶段：C242 原生 SHEX 闭合、SCI 图集与存储治理报告

更新日期：2026-09-03
代码分支：`codex/coupled-simscape-authority`

## 1. 当前严格结论

本阶段完成了 C241 到 C242 的真实 Operating Point 连续续算，并修复原生 Simscape
日志截断造成的错误外推。C242 通过物理机制门禁、周期稳态门禁和 SHEX 局部直接
控制体门禁；C200 仍是唯一主线基准，C242 是当前 SHEX 能量观测与后续恢复权威。

可以声明：

1. SMA-SE 四阶段正逆耦合在 C242 仍为机制有效且周期稳态。
2. SHEX source、sink storage、sink-to-fluid 三条原生支路在最终完整 10 s 周期上
   满足节点能量守恒。
3. C242 的直接 SHEX 局部控制体通过，不再依赖 C240 的节点平衡重建。
4. C242 的 SCI 图集已扩展为 6 张 PNG/PDF，并完成逐图视觉审核。
5. 工作区已从约 120 GB 的历史高位治理到 `11.025 GiB`；当前 `outputs` 为
   `10.436 GiB`，清理并生成终版六图后仍无剩余候选。

不能声明：

1. 不能声明 Qian 2019 Table 4 已严格复现。
2. 不能声明完整 SMA-SE 整机一阶能量闭合；HHEX、CHEX、buffer 和 pipe 边界尚未
   全部直接测量。
3. 不能把 `13.234 W / 826.319 W` 写成最终系统 COP；在完整控制体闭合前该指标
   只能作为局部能量比，正式 heat-driven system COP 继续 withheld。
4. 不能声明 experimentally validated；当前是物理 Simscape 预测和文献 benchmark。

## 2. 权威结果和哈希

### 2.1 C200 主线基准

| 文件 | SHA-256 |
|---|---|
| `physical_simscape_result.mat` | `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` |
| `final_operating_point.mat` | `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816` |

目录：

`gx101r1_R69_remote/outputs/qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821/qian2019_table2_table4_simscape_200cycle_20260821_121246`

### 2.2 C242 当前 SHEX 权威

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `physical_simscape_result.mat` | `6049509486` | `64812578CE36356339A2E7C4192E7943478688EDDE869AFC306B9A1963364F3F` |
| `final_operating_point.mat` | `3825991` | `D2607DDB7F0440A1448F538522A0E34C067F382858068AD370102FB829F16949` |

结果目录：

`gx101r1_R69_remote/outputs/qian_coupled_shex_fullcycle_c242_v2_20260903/qian2019_table2_table4_simscape_242cycle_20260903_173052`

恢复合同：

`gx101r1_R69_remote/verification/shex_fullcycle_c242_recovery_contract.json`

直接控制体审核：

`gx101r1_R69_remote/outputs/qian_coupled_shex_fullcycle_c242_v2_20260903/shex_transfer_audit_c242.json`

## 3. C240、C241 到 C242 的问题定位

### 3.1 Operating Point 时间语义

两条诊断分支分别尝试了显式 `StartTime=2400` 和局部 `StopTime=10`。前者被
Simulink 按 Operating Point 的只读时间语义重置，后者因 checkpoint
`snapshotTime=2400` 大于 StopTime 而被拒绝。正确规则是：

1. `StartTime` 保持 `0`。
2. 将 Operating Point 作为 initial state。
3. `StopTime` 使用大于 snapshotTime 的绝对时间。
4. 不修改或重置任何热容、buffer、本构、温度、相分数和 PI 记忆。

因此历史 C240 到后续周期不是“重复从零多算”；先前局部时间判断已由提交
`b8e97c6` 更正。两个失败分支均未进入恢复链。

### 3.2 C241 能量审计为什么被拒绝

C241 本身 `mechanism=1`、`periodic=1`，所以其 Operating Point 是物理有效状态。
但当时模型的 `SimscapeLogDataHistory=5000`，1 ms 步长下只保留最终约 5 s。
提取函数又使用 `interp1(...,'extrap')`，把后半周期原生热流错误外推到前半周期，
导致：

| 错误审计量 | 错误值 |
|---|---:|
| sink-to-fluid 均值 | `1108.300 W` |
| source/sink 比 | `1.3411` |
| 局部控制体相对残差 | `0.3411` |

这些值不是物理失配，而是日志窗口和外推错误。C241 能量结论被拒绝；C241 状态
只用于一次 C242 连续续算，随后其 5.60 GiB MAT 和 OP 被删除。

### 3.3 修复方法

1. `SimscapeLogDataHistory` 按 `ceil(tau_cycle/fixed_step)+2` 设置，至少保留一个
   完整周期。
2. 原生日志只在自身真实时间覆盖区间内插值，区间外写 `NaN`，禁止外推。
3. SHEX 生产审核固定为 `final_complete_cycle_only`，禁止与早期不兼容诊断周期拼接。
4. 直接使用 `source-to-sink`、`sink mass Q` 和 `sink-to-fluid Q` 三支路检查 KCL。
5. 完整周期诊断中，工作区 source 与原生 sensor RMS 差为 `8.95e-10 W`，三支路
   KCL RMS 为 `1.65e-13 W`。

## 4. C242 数值结果与门禁

| 项目 | C242 结果 | 门禁结论 |
|---|---:|---|
| 总周期 | `242` | 连续历史 |
| 新增段 | `2410-2420 s` | 1 个完整周期 |
| `mechanism_pass` | `1` | 通过 |
| `periodic_steady_state` | `1` | 通过 |
| endpoint drift | `0.0136733499 K` | 通过周期门禁 |
| same-phase temperature max drift | `0.220500395 K` | 鲁棒 P99/RMS 门禁通过 |
| same-phase phase drift | `0.0100248223` | 通过 |
| Eq. 9 lift | `28.7102591496 K` | 固定边界预测点 |
| Eq. 10 cooling power | `13.2342446565 W` | 最后 10 周期定义 |
| Eq. 10 SCP | `0.316481249537 W/g` | 固定边界预测点 |
| CHEX sensor power | `12.9668120094 W` | 与 Eq.10 相差 `2.0208%` |
| SE phase swing | `0.997839523` | 机制完整 |
| source heat input, final-cycle CV window | `826.325496580 W` | 正向通过 |
| source heat input, last-10-cycle performance window | `826.318961674 W` | 仅用于性能平均 |
| sink-to-fluid heat input | `826.325496710 W` | 正向通过 |
| transfer ratio, same final cycle | `1.00000000016` | 通过 `1e-4` 门禁 |
| direct CV residual | `-3.18672e-8 W` | 通过 |
| direct CV relative residual | `3.85650e-11` | 通过 `1e-3` 门禁 |
| `ALL_REQUIRED_PASS` | `0` | Table 4 严格条件未完成，不是机制失败 |

## 5. 与 Qian 文献的具体比较

主定量合同仍是 Qian et al., Energy 182 (2019), DOI
`10.1016/j.energy.2019.06.094`。本地 PDF 为：

`C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A heat driven elastocaloric cooling system..pdf`

| 文献位置 | 文献要求 | 当前比较方式 | 当前结论 |
|---|---|---|---|
| Fig. 1，PDF 3-4 页 | SMA-SE-SHEX/HHEX/CHEX 四阶段单效拓扑 | 对照实际 Simscape 流路和 10 s 时序 | 已实现 |
| Eqs. (1)-(4)，PDF 5 页 | 固液能量方程和相变动力学 | 21+21 节点、1 ms ODE3、跨周期状态 | 已实现，尚缺网格/步长收敛 |
| Eqs. (5)-(8)，PDF 5 页 | 等力、等位移机械兼容 | 每个子步联立求 SMA-SE 应力/位移 | 已实现 |
| Eqs. (9)-(10)，PDF 5 页 | 温跨和 SCP 的周期平均定义 | 最后 10 周期、明确质量基准 | 已实现 |
| Table 4，PDF 16-17 页 | zero-load `26.2 K` 与 zero-lift `0.64 W/g` 两个端点 | 必须分别外层求根并成对审核 | 尚未完成 |

C242 的 `28.7103 K` 与 `0.31648 W/g` 来自同一个固定 `Tc=276.95 K` 周期点。
它相对 `26.2 K` 最大温跨目标高 `9.581%`，超过当前 `5%` 接受边界；同时
`0.31648 W/g` 不能与文献的 zero-lift `0.64 W/g` 直接比较，因为边界条件不同。
因此本结果是 `periodic simulated operating point`，不是 `Table 4 reproduced`。

其他 Qian 文献用于交叉约束，不覆盖 2019 定量合同：

1. Qian et al., IJ Refrigeration 56 (2015), DOI `10.1016/j.ijrefrig.2015.04.001`：
   用于完整流体回路、系统控制体和 cyclic steady 定义。
2. Qian et al., Energy 141 (2017), DOI `10.1016/j.energy.2017.09.116`：
   用于相变动力学、材料匹配和 10-cycle 周期稳态证据。
3. Tan et al., Energy 197 (2020), DOI `10.1016/j.energy.2020.117261`：
   用于等力/等位移、质量比、输入热和性能权衡。
4. Qian et al., Applied Energy 298 (2021), DOI `10.1016/j.apenergy.2021.117269`：
   只用于区分当前单效耦合与功循环/制冷循环级联，不移植其性能值。
5. Qian et al., Applied Thermal Engineering 219 (2023), DOI
   `10.1016/j.applthermaleng.2022.119540`：用于区分材料级、循环级和系统级 COP。

完整页码和本地文件索引见：

`项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`

## 6. SCI 图集逐图说明

图集目录：

`gx101r1_R69_remote/outputs/qian_coupled_shex_fullcycle_c242_v2_20260903/qian2019_table2_table4_simscape_242cycle_20260903_173052/figures_sci`

### Fig. 01 `Fig01_last_cycle_mechanism`

上图展示 SMA/SE 平均温度及 HHEX/CHEX 边界；中图展示两种材料马氏体分数；下图
展示 SMA 主流量和 SE 两条阶段流量。负责人应从该图确认四阶段时序、SMA 驱动和
SE 制冷相变方向一致、流量在规定阶段开启且无错误反向。

### Fig. 02 `Fig02_last_cycle_axial_fields`

四张热图分别给出 SMA/SE 的 21 节点温度和马氏体分数随轴向位置、周期相位的演化。
该图用于识别轴向前沿、换热非均匀性和局部未完成相变，不能只用平均温度代替。

### Fig. 03 `Fig03_periodic_convergence`

展示冷启动到 C242 的循环末温度、endpoint drift、Eq.9 和 Eq.10 SCP。灰色门禁线
用于判断周期稳定性；末点虽有小幅漂移但仍在鲁棒周期门禁内。该图同时说明性能已
收敛到固定边界平台，而不是说明 Table 4 端点已复现。

### Fig. 04 `Fig04_control_and_energy`

展示压力命令、液压功、SMA/SE 本构热率以及固体周期能量分解。右下角仅是 SMA/SE
固体局部能量闭合，不是完整系统能量闭合；SHEX/HHEX/CHEX/buffer/pipe 必须另行
计入。

### Fig. 05 `Fig05_table4_boundary_audit`

黑线和空心点是 Qian Table 4 两个文献端点；绿色实心点是 C242 固定边界预测；
红叉是因 SE 相变不完整而拒绝的 270 K 点；绿色虚线和空心三角只表示线性诊断
外推，不能作为有效根。该图直接说明“接近文献”与“严格成对端点复现”的区别。

### Fig. 06 `Fig06_direct_SHEX_control_volume`

上图直接画 source-to-sink、sink-to-fluid 和 sink storage 三支路瞬时热流；前半周期
热源与流体支路接近，差额由 sink storage 吸收或释放。下图给出累计输入、累计流体
转移、累计 storage 和归一化累计残差。周期末 source 和 fluid 均约 `826.32 W`，
相对残差 `3.8565e-11`，这是本阶段 SHEX 局部控制体通过的直接图证。

视觉审核结果：6 张图均为白底、Arial、600 dpi PNG 和矢量 PDF；分面、图例、色标、
轴单位和阶段线可读，无裁切、重叠或混入同一坐标轴的无关量。Fig. 06 首版长标题
曾被裁切，已缩短并把数值移入图内后重新导出。

## 7. 代码修改成果

| 文件 | 修改内容 |
|---|---|
| `Build_HeatDriveECC_EighthRound_Defaults.m` | 结构体数组不再进入标量递归合并，修复保存 options 恢复失败 |
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 保留完整周期原生日志；禁止 Simscape 区间外外推；提取 SHEX 三支路 |
| `Summarize_HeatDriveECC_EighthRound_Output.m` | SHEX 审核限定最终完整周期并计算 source/storage/fluid 残差 |
| `Validate_HeatDriveECC_EighthRound_Physics.m` | 将完整周期合同和直接控制体指标写入物理报告 |
| `Plot_HeatDriveECC_SCI_FigureSet.m` | SCI 图集扩展为 6 图，新增直接 SHEX 控制体图 |
| `verification/Diagnose_HeatDriveECC_SHEXNativeLogging.m` | 短时/整周期原生日志时间覆盖、传感器一致性和 KCL 诊断 |
| `verification/Audit_HeatDriveECC_SHEXTransferResult.m` | source、sink-to-fluid、周期窗口和直接残差生产门禁 |
| `verification/shex_fullcycle_c242_recovery_contract.json` | C242 哈希、状态和能量门禁冻结 |
| `verification/Manage_HeatDriveECC_OutputStorage.ps1` | 只保护 C200 与当前 C242 原始恢复点，安全轮换旧 raw |
| `verification/Verify_FinalHeatDriveECC_Package.m` | MATLAB 最终包审核改用 C242 直接测量 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | 301 项文件/哈希清单更新为 C242 权威 |

关键 Git 提交：

| Commit | 内容 |
|---|---|
| `b8e97c6` | 恢复原生 Operating Point 绝对时间续算语义 |
| `2ff7a75` | 增加 SHEX 观测窗口审核 |
| `557485f` | 增加短时原生日志诊断 |
| `97a97d3` | 修复完整周期 Simscape 日志保留与禁止外推 |
| `afd7d93` | 冻结机制有效 C241 状态 |
| `3558a80` | 修复 C241 合同 schema 后再启动 |
| `e62f777` | 审核限定最终完整周期 |
| `aed4f2a` | 冻结 C242 并切换存储权威 |

## 8. 结果包结构

1. C200 主线 raw、OP、SCI 图和报告：保留。
2. C242 SHEX raw、OP、SCI 图 1-6、validation、progress、state、run contract、
   transfer audit 和 recovery contract：保留。
3. C240/C241：只保留哈希合同、周期摘要、validation、SCI/诊断图、日志和拒绝原因；
   重复 raw、OP、dense probe 和 legacy figures 已删除。
4. 最终文件清单：
   `gx101r1_R69_remote/outputs_storage_audit/final_results_manifest_20260824.csv`
5. 最终 SHA-256 清单：
   `gx101r1_R69_remote/outputs_storage_audit/final_results_sha256_20260824.csv`
6. 最终包摘要：
   `gx101r1_R69_remote/outputs_storage_audit/final_results_audit_summary_20260824.json`

PowerShell 包审核结果：`301/301` required files present，`missing=0`。MATLAB 包审核：
`RESULT_PACKAGE_PASS=1`，同时明确 `STRICT_TABLE4_REPRODUCTION=0`。

## 9. 验证命令

以下命令在
`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote` 执行。

### 9.1 直接 SHEX 门禁

```powershell
matlab -batch "cd(pwd); addpath('verification'); p=fullfile(pwd,'outputs','qian_coupled_shex_fullcycle_c242_v2_20260903','qian2019_table2_table4_simscape_242cycle_20260903_173052','physical_simscape_result.mat'); a=Audit_HeatDriveECC_SHEXTransferResult(p); assert(a.production_pass);"
```

预期关键输出：

```text
SHEX_TRANSFER_RESULT_PASS=1
source_W=826.32549658
sink_to_fluid_W=826.32549671
ratio=1.00000000016
periodic=1
```

### 9.2 MATLAB 最终包门禁

```powershell
matlab -batch "cd(pwd); addpath('verification'); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.result_package_pass);"
```

预期：`RESULT_PACKAGE_PASS=1 STRICT_TABLE4_REPRODUCTION=0`。

### 9.3 PowerShell 文件与哈希门禁

```powershell
pwsh -File verification\Audit_FinalHeatDriveECC_Package.ps1
```

预期：`required_file_count=301`、`present_file_count=301`、`missing_file_count=0`。

### 9.4 权威哈希

```powershell
Get-FileHash outputs\qian_coupled_shex_fullcycle_c242_v2_20260903\qian2019_table2_table4_simscape_242cycle_20260903_173052\physical_simscape_result.mat -Algorithm SHA256
Get-FileHash outputs\qian_coupled_shex_fullcycle_c242_v2_20260903\qian2019_table2_table4_simscape_242cycle_20260903_173052\final_operating_point.mat -Algorithm SHA256
```

### 9.5 SCI 图集重建

```powershell
matlab -batch "cd(pwd); p=fullfile(pwd,'outputs','qian_coupled_shex_fullcycle_c242_v2_20260903','qian2019_table2_table4_simscape_242cycle_20260903_173052','physical_simscape_result.mat'); s=Plot_HeatDriveECC_SCI_FigureSet(p,fullfile(fileparts(p),'figures_sci')); assert(size(s.files,1)==6);"
```

### 9.6 存储 dry-run

```powershell
pwsh -File verification\Manage_HeatDriveECC_OutputStorage.ps1
```

预期：`candidate_count=0`。不要在健康 MATLAB 引用 outputs 时使用 `-Apply`。

### 9.7 从 C242 连续推进一周期

```powershell
pwsh -File verification\Start_HeatDriveECC_SourceHeatFlowValidation.ps1 `
  -OutputRoot outputs\qian_coupled_shex_c243_recheck `
  -SegmentCycles 1 -MaximumCycles 243 `
  -RecoveryContractPath verification\shex_fullcycle_c242_recovery_contract.json
```

该命令只能从 C242 当前合同继续，不能从已删除的 C240/C241 raw 或任何失败链恢复。

## 10. 存储治理结果

| 项目 | 数值 |
|---|---:|
| 清理前 outputs | `21.753 GiB` |
| 删除候选 | `40` 个 |
| 删除容量 | `11.317 GiB` |
| 清理并生成终版图后 outputs | `10.436 GiB` |
| 清理并生成终版图后整个工作区 | `11.025 GiB` |
| 二次 dry-run | `candidate_count=0` |

应用记录：

`gx101r1_R69_remote/outputs_storage_audit/cleanup_summary_20260903_192630.txt`

候选清单：

`gx101r1_R69_remote/outputs_storage_audit/cleanup_candidates_20260903_192630.csv`

删除仅限被 C242 替代的 C240/C241 raw 和 OP、C241/C242 legacy figures、dense probe。
没有删除 C200、C242、SCI 图、报告、周期摘要、参数合同、日志、哈希和失败原因。

## 11. 当前 SE21 和完整 SMA-SE 尚未完成的工作

1. **Table 4 zero-load root**：在机制有效前提下求 `SCP=0` 的温跨根，并达到
   `26.2 K` 定量边界。
2. **Table 4 zero-lift root**：单独求 `DeltaT=0` 的 SCP 根，并达到 `0.64 W/g`。
3. **paired endpoint 审核**：两个端点必须都合法、都完整相变、都在物性范围内，
   不允许用一条线性外推替代。
4. **完整系统能量闭合**：补 HHEX-to-ambient、CHEX-to-load/environment、各 buffer、
   连接管、泵功和全部储能项的统一符号控制体。
5. **完整系统 COP/SCP**：在第 4 项通过后才发布系统 COP，并区分材料、循环和系统
   三种边界。
6. **网格和步长收敛**：21 节点、1 ms 目前是生产离散，不是已证明收敛；至少做
   轴向节点和时间步的独立加密比较。
7. **参数可辨识性和不确定度**：目前部分 UA/附件库存是工程闭合假设，需要报告
   来源、范围和敏感性，不得反标 Table 4。
8. **独立 validation**：需要实验数据或独立求解器/数据集交叉验证；内部机制门禁
   不能替代 validation。

## 12. 后续主线计划

1. 以 C242 OP 为唯一 SHEX 连续恢复起点，新增 HHEX、CHEX、buffer 和 pipe 原生
   热流观测，先做 1-cycle 日志合同验证。
2. 对每个新增控制体先执行“时间覆盖、无外推、最终完整周期、KCL”四项门禁，禁止
   直接进入长链。
3. 形成统一整机能量表，逐项列出输入热、冷量、环境排热、储能变化和泵功；周期末
   总储能变化应趋近零。
4. 完整系统闭合后，再启动两个独立 Table 4 外层求根，不传播机制失败结果。
5. 每个长段使用固定 30 分钟等待命令，中间不轮询、不刷状态；自然返回 JSON 后再
   审核或续转。
6. 新权威结果通过后立即轮换存储，只保留 C200、最新恢复点、SCI 图、摘要、合同、
   哈希和必要失败证据。

## 13. 负责人审核结论

C242 可作为当前“机制有效、周期稳态、SHEX 局部直接闭合”的生产结果和后续恢复点。
图集、代码、结果 MAT、OP、审计 JSON、报告、SHA-256 清单和存储记录均可复核。
项目尚未达到 Qian Table 4 严格复现，也未达到完整系统能量闭合或独立实验验证；后续
工作必须按第 11-12 节继续，不得提前提高结论等级。
