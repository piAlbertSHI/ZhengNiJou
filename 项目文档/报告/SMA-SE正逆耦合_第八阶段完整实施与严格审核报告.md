# SMA-SE 正逆耦合：第八阶段完整实施与严格审核报告

生成日期：2026-08-24；refined OAT、图集、结果包与 endpoint-capacity 超细复核更新：2026-08-31
代码分支：`codex/coupled-simscape-authority`  
报告性质：生产 Simscape 结果交接、文献 benchmark、失败边界和后续计划的权威审计。  
结论边界：当前工作是 numerical verification + literature benchmark，不是独立实验 validation，也不是 Qian Table 4 strict reproduction。

## 1. 执行摘要

第八阶段完成了 C200 主线冻结、控制体合同、固定 `Tc` 机制保护 outer solve、两轮六因素 L8 筛选、zero-load/zero-lift 候选审核、paired strict audit、六面板 trade-off 图和工作区压缩。结果明确，但不是“全部复现通过”：

| 项目 | 当前结果 | 严格结论 |
|---|---:|---|
| C200 mechanism gate | 1 | 通过 |
| C200 periodic steady state | 1 | 通过 |
| Eq. 9 lift | 28.709970099 K | 有效固定边界性能点 |
| Eq. 10 SCP | 0.316480491 W/g | 有效 active-SE-mass 性能点 |
| Qian Table 4 zero-load root | 未找到 | not yet reproduced |
| Qian Table 4 zero-lift root | 未找到 | not yet reproduced |
| paired strict audit | 0 | 两个 accepted roots 均缺失 |
| heat-driven system COP | 不可用 | SHEX source heat-flow 未测量 |
| L8 严格六因素主效应 | 全部 `NaN` | 可接受点不足，禁止用 rejected 点补算 |
| 首轮 local OAT | 12/12 完成，6 点 admissible | buffer、regeneration 2/6 对合法 |
| refined local OAT | 10 点实际运行，9 点 admissible | UA、inventory、regeneration、latent heat 4 对合法；buffer 不重复运行 |
| 合并后的独立 pair 证据 | 12 个低/高点，11 点 admissible | 5/6 对可计算；仅 endpoint capacity 不可用 |
| endpoint-capacity ultrafine | 2/12 实际运行，1 admissible，1 rejected | `±0.125%` 仍无 strict pair；导数保持 `NaN` |
| 最大合法局部归一化响应 | transformation latent heat | 每单位 fractional change：lift `+1.91413 K`、SCP `+0.304583 W/g` |

当前最强可写结论是：完整 SMA-SE 物理 Simscape 模型在固定 `Tc=276.95 K` 下达到机制有效的周期性能点；参数过渡和端点搜索的首要限制来自 SE 末循环流量/控制可行域，而不是相变、能量或可观测性门禁。两轮独立、对称、均从冻结 C200 启动的 local OAT 合并后，UA、buffer、fluid inventory、regeneration flow 和 latent heat 共 5/6 对可严格求导；latent heat 在这五个合法局部 pair 中对 lift 和 SCP 的归一化响应最大，但所有局部变化都远不足以闭合当前 Table 4 偏差，且 endpoint capacity 仍缺少合法 pair，因此不能宣称完整六因素全局排序。当前结果没有同时复现 Qian 等人报告的 `26.2 K @ zero load` 和 `0.64 W/g @ zero lift`。

## 2. 唯一主线恢复源与哈希

权威结果目录：

`gx101r1_R69_remote/outputs/qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821/qian2019_table2_table4_simscape_200cycle_20260821_121246`

只有以下两个文件可以传播到新的主线续算：

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `physical_simscape_result.mat` | 4,987,450,900 | `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` |
| `final_operating_point.mat` | 3,822,969 | `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816` |

冻结合同：`gx101r1_R69_remote/verification/c200_mainline_freeze_contract.json`。

2026-08-24 存储清理前后均重新计算两个哈希，均与合同一致。旧 C100、80/100-cycle、dynamic-ff、Stage 4 retune、L8 rejected、275.5 K 和 303 K 结果都不是恢复源。不得重置热容、buffer、本构、温度、相分数或 PI 路线记忆。

## 3. C200 结果审核

| 指标 | 数值 | 判定 |
|---|---:|---|
| completed cycles | 200 | 权威终点 |
| coupled mechanism | 1 | 通过 |
| robust periodic state | 1 | 通过 |
| endpoint drift | 0.0135817579 K | 通过 |
| same-phase temperature max drift | 0.167089691 K | 保留为前沿时移诊断 |
| same-phase phase-fraction max drift | 0.00755657984 | 保留为诊断 |
| Eq. 9 lift | 28.709970099 K | 相对 26.2 K 偏高约 9.58% |
| Eq. 10 SCP | 0.316480491 W/g | 为 0.64 W/g 的约 49.45% |
| `ALL_REQUIRED_PASS` | 0 | 含 Table 4 定量边界，不能等同机制失败 |
| strict Table 4 | 0 | 不得写 reproduced |

C200 是验证通过的固定边界性能点，不是 zero-load maximum，也不是 zero-lift maximum。周期门禁采用最后 `min(N,10)` 个完整循环；同相 P99/RMS 用于稳态判定，极值仍保留作前沿位移诊断。

## 4. 本阶段代码修改

### 4.1 主线冻结和 Operating Point 合同

- `verification/Freeze_HeatDriveECC_C200_Mainline.ps1`：冻结 C200 路径、大小和 SHA-256。
- `verification/Resolve_HeatDriveECC_MainlineAuthority.m`：所有候选统一解析 C200 authority。
- `verification/c200_mainline_freeze_contract.json`：结果、OP、报告和 progress 的不可变合同。
- `verification/Run_HeatDriveECC_LongSteadyContinuation.m`：恢复时保留完整状态和控制记忆。
- `verification/Run_HeatDriveECC_EighthRound_Simulink_Cycles.m`：只允许状态兼容的参数变化。

### 4.2 控制体与性能合同

- `verification/Build_HeatDriveECC_ControlVolumeContract.m`：生成 10 个控制体的 CSV/JSON/Markdown 合同。
- 明确 SHEX 源热流传感器、CHEX sensor、SHEX/HHEX/CHEX 流体、SMA、SE、buffer、连接管和泵功边界。
- Eq. 9/Eq. 10 使用最后 10 个完整循环窗口。
- SCP 分母为 active SE solid mass：`41.8168364663 g`。
- 新的 `SHEXSourceToSinkHeatFlowSensor` 通过 `shex_source_heat_flow_W` 记录源侧输入；C200 冻结结果没有该信号，因此当前 system COP 仍 withheld，待新周期结果验证后才可启用。

### 4.3 机制门禁保护的端点求解

- `verification/Run_HeatDriveECC_Table4_OuterSolve.m`：统一支持 `eq10_SCP_W_per_g` zero-load 和 `eq9_lift_K` zero-lift 目标。
- `verification/Start_HeatDriveECC_Table4OuterSolve.ps1`：静默启动器，stdout/stderr 独立记录。
- 候选必须先通过 flow、phase、energy、observability、periodic 和固定 CHEX authority 门禁，才允许进入插值。
- 失败候选写入 `REJECTED_DO_NOT_RESUME.txt`，不会传播 OP 或进入 root interpolation。

### 4.4 六因素 L8 筛选

- `verification/Run_HeatDriveECC_Table4_Sensitivity.m`：UA、端点热容、SE buffer、SMA manifold inventory、SE regenerator utilization、latent heat/entropy 六因素 L8。
- `verification/Start_HeatDriveECC_Table4Sensitivity.ps1`：分候选记录错误并继续后续 run。
- 参数过渡期与 benchmark 门禁分离；单个 run 已记录 `simulation_error` 后不终止整个 L8。
- rejected/transient 点不进入正交效应计算；不能通过删门禁获得看似完整的主效应表。

### 4.5 六因素成对 local OAT

- `verification/Run_HeatDriveECC_Table4_Sensitivity.m` 新增 `design_kind='local_oat'`，从同一 C200 authority 为每个因素建立独立对称 `-/+` 候选。
- UA、端点热容、回热利用率和潜热采用 `±0.5%`；SE buffer 与 SMA 流体库存采用 `±1%`。
- 只有同一因素两点都通过 mechanism、periodic、flow、phase、energy 和 observability 门禁，才写入导数；其余字段保持 `NaN`。
- 12 个候选按 20-cycle 分段、最多再算 40 cycles；每个候选均从 C200 恢复，候选之间不传播 OP。

### 4.6 成对端点审核和绘图

- `verification/Audit_HeatDriveECC_PairedTable4Endpoints.m`：要求两个 accepted roots、共同 authority、共同参数合同、共同 10-cycle window、全部机制门禁和 Table 4 定量容差同时通过。
- `Plot_HeatDriveECC_CoupledTradeoff.m`：将 admissible 点画为实心圆、rejected 点画为红叉，拒绝点不拟合、不求效应。
- `Plot_HeatDriveECC_LocalSensitivityAudit.m`：六因素各占一个面板，只有严格成对通过时连接响应点，直接显示不可求导的因素。
- 输出 600 dpi PNG、矢量 PDF、两个绘图数据 CSV 和 manifest。

### 4.7 存储和长任务纪律

- `verification/Compact_HeatDriveECC_RejectedCandidate.ps1`：只压缩具有 rejected 和 scalar-extraction 双标记的单一候选。
- `verification/Manage_HeatDriveECC_OutputStorage.ps1`：从 C200 冻结合同解析唯一 raw 白名单，先输出 deletion CSV，再删除旧 raw、旧 probe 和 legacy figures。
- `项目文档/研究笔记/长任务运行纪律.md`：长任务使用单个 30 分钟静默等待命令，等待自然结束后一次返回 JSON。

## 5. Git 修改链

| Commit | 内容 |
|---|---|
| `2b1c865` | 冻结 C200 authority，增加控制体和 outer solve |
| `ddbf57c` | 增加 outer solve 静默启动器和等待发现逻辑 |
| `3b5ec5e` | 允许状态兼容的 checkpoint 参数变化 |
| `628deb8` | 候选间保留 C200 控制参数 |
| `a66c5ca` | Qian 耦合循环文献逐页定位 |
| `c00b05e` | 增加门禁保护 L8 敏感性工作流 |
| `4e32cc2` | 参数过渡与 benchmark gate 分离 |
| `7b145b2` | 参数过渡后再启用敏感性门禁 |
| `d46b156` | 单候选 simulation error 记录后继续 L8 |
| `ae14fb3` | 增加 paired Table 4 endpoint audit |
| `4290f5f` | 增加六因素独立、对称、机制门禁 local OAT |
| `866a960` | 完成 12 点 OAT 审核、Fig. 6/7、结果包 v3 和存储收尾 |
| `5350403` | 完成 refined OAT 合并审核、Fig. 6/7 v3/v2、结果包 v4 和 2026-08-30 存储收尾 |

本报告、Fig. 6、拒绝候选压缩脚本和收紧后的全量存储治理脚本在本阶段最终提交中纳入 Git。大 MAT、运行输出和生成图不进入 Git；由结果 manifest 与 SHA-256 管理。

## 6. Zero-load 求解结果

输出：`gx101r1_R69_remote/outputs/qian_table4_zero_load_outer_solve_v3_20260822`

| `Tc` | status | mechanism | periodic | Eq. 9 | SCP | 主要原因 |
|---:|---|---:|---:|---:|---:|---|
| 276.95 K | accepted frozen baseline | 1 | 1 | 28.7099701 K | 0.316480491 W/g | C200 合法基线，但非 SCP=0 |
| 275.5 K | mechanism failure | 0 | 0 | 29.7134645 K | 0.281336036 W/g | SE 末循环流量门禁失败 |

275.5 K 没有产生负 SCP，也没有通过机制/周期门禁，因此没有有效符号包络，不能插值 zero-load root。该候选原始 result 和 checkpoint 已压缩，只保留报告、CSV、合同、状态和拒绝说明。

## 7. Zero-lift 求解结果

输出：`gx101r1_R69_remote/outputs/qian_table4_zero_lift_outer_solve_20260824`

| `Tc` | status | mechanism | periodic | Eq. 9 | SCP | 主要原因 |
|---:|---|---:|---:|---:|---:|---|
| 276.95 K | accepted frozen baseline | 1 | 1 | 28.7099701 K | 0.316480491 W/g | C200 合法基线，但非 lift=0 |
| 303 K | mechanism failure | 0 | 0 | 11.1761482 K | 0.854949745 W/g | SE no-reversal、instantaneous target、RMS target 均失败 |

303 K 点通过 phase、energy、observability 和 fixed-CHEX authority，但 flow gate 失败，且 Eq. 9 仍为正。它说明高 `Tc` 端当前控制路线先失稳，不能继续盲目升温，也不能把该点当作 zero-lift root。压缩释放 5,560,589,377 bytes；失败 OP 未保留。

## 8. 六因素正交敏感性审核

### 8.1 L8 v3：较宽扰动

幅值：UA/热容/潜热 `±5%`，buffer/inventory `±10%`，utilization `±3%`。

| Run | status | admissible | Eq. 9 (K) | SCP (W/g) |
|---|---|---:|---:|---:|
| R01 | maximum cycles | 0 | 28.62059 | 0.289444 |
| R02 | mechanism failure | 0 | 28.88360 | 0.328454 |
| R03 | maximum cycles | 0 | 28.85355 | 0.319446 |
| R04 | periodic steady | 1 | 28.67754 | 0.297379 |
| R05 | mechanism failure | 0 | 28.58514 | 0.311989 |
| R06 | mechanism failure | 0 | 28.72300 | 0.332339 |
| R07 | mechanism failure | 0 | 28.77735 | 0.343726 |
| R08 | periodic steady | 1 | 28.54689 | 0.302720 |

结果：8/8 完成，2/8 admissible。两点不足以保持 L8 正交平衡，六因素效应全部 `NaN`。

### 8.2 L8 v4：收窄扰动

幅值：UA/热容/utilization/latent heat `±1%`，buffer/inventory `±2%`。

| Run | status | admissible | Eq. 9 (K) | SCP (W/g) |
|---|---|---:|---:|---:|
| R01 | simulation error after C240 record | 0 | 28.68765 | 0.310406 |
| R02 | mechanism failure | 0 | 28.74719 | 0.319634 |
| R03 | simulation error after C240 record | 0 | 28.73423 | 0.316566 |
| R04 | periodic steady | 1 | 28.70812 | 0.313493 |
| R05 | mechanism failure | 0 | 28.68850 | 0.316380 |
| R06 | periodic steady | 1 | 28.70732 | 0.319185 |
| R07 | mechanism failure | 0 | 28.72703 | 0.322544 |
| R08 | periodic steady | 1 | 28.67369 | 0.313198 |

结果：8/8 有记录，3/8 admissible。R01/R03 后续 Simscape Thermal Liquid 温度有效域异常不抹去已记录诊断，但也不使其成为 admissible。所有机制失败点都只失败于 flow gates；全部候选的 phase、energy 和 observability gates 均通过。

### 8.3 local OAT：独立对称小扰动

输出：`gx101r1_R69_remote/outputs/qian_table4_local_oat_sensitivity_20260824`。

| Run | 因素/扰动 | status | admissible | Eq. 9 (K) | SCP (W/g) | 同相温漂 (K) | 同相相分数漂移 |
|---|---|---|---:|---:|---:|---:|---:|
| R01 | UA -0.5% | maximum cycles | 0 | 28.716898 | 0.315802422 | 0.205 | 0.0093 |
| R02 | UA +0.5% | periodic steady | 1 | 28.703626 | 0.317155544 | 0.244 | 0.0111 |
| R03 | capacity -0.5% | maximum cycles | 0 | 28.710258 | 0.316481223 | 0.234 | 0.0106 |
| R04 | capacity +0.5% | maximum cycles | 0 | 28.710255 | 0.316480976 | 0.216 | 0.0098 |
| R05 | buffer -1% | periodic steady | 1 | 28.710257 | 0.316481488 | 0.221 | 0.0100 |
| R06 | buffer +1% | periodic steady | 1 | 28.710257 | 0.316481488 | 0.221 | 0.0100 |
| R07 | inventory -1% | maximum cycles | 0 | 28.710253 | 0.316493327 | 0.240 | 0.0117 |
| R08 | inventory +1% | maximum cycles | 0 | 28.710255 | 0.316467360 | 0.279 | 0.0136 |
| R09 | regeneration -0.5% | periodic steady | 1 | 28.706304 | 0.315686779 | 0.234 | 0.0106 |
| R10 | regeneration +0.5% | periodic steady | 1 | 28.716395 | 0.317295962 | 0.251 | 0.0117 |
| R11 | latent heat -0.5% | maximum cycles | 0 | 28.698507 | 0.314916805 | 0.210 | 0.0097 |
| R12 | latent heat +0.5% | periodic steady | 1 | 28.719743 | 0.317999489 | 0.223 | 0.0101 |

审核结果：12/12 完成、6/12 admissible、2/6 strict local pairs。SE buffer 对通过，但在当前数值合同和 `±1%` 范围内 Eq. 9、SCP、泵功和回热利用率响应均为机器精度零；这只能写为“该局部范围未分辨出响应”，不能推广为 buffer 永远无影响。SE regeneration flow 对通过，`high-low` 为：

| 响应 | `high-low` | 每单位 fractional change 导数 |
|---|---:|---:|
| Eq. 9 lift | +0.010090901 K | +1.009090099 K |
| Eq. 10 SCP | +0.001609184 W/g | +0.160918360 W/g |
| temperature error fraction | +0.000385149 | +0.038514889 |
| SCP gap fraction | -0.002514349 | -0.251434938 |
| pump power | +0.004786111 W | +0.478611102 W |
| SE utilization | +0.007557117 | +0.755711725 |

UA、端点热容、inventory 和 latent heat 至少一侧未通过 periodic gate，四对全部保持 `NaN`。它们的瞬态数值只用于显示可行域边界，不能参与主导因素排序。全部 12 点的 flow、phase、energy 和 observability 均通过；本轮拒绝原因是 240 cycles 内未满足 periodic gate，而不是机制失败。

### 8.4 refined local OAT：缩小扰动复核

输出：`gx101r1_R69_remote/outputs/qian_table4_local_oat_refined_sensitivity_20260826`。所有实际候选仍独立从冻结 C200 启动；异常中断的 R04/R11 只从本候选最后已验证状态恢复，没有传播 rejected 状态。buffer 已在首轮形成合法 `±1%` pair，因此本轮 R05/R06 明确保持 pending，不重复消耗 raw 和算力。

| 因素 | 扰动 | 低侧 | 高侧 | strict pair | lift high-low (K) | SCP high-low (W/g) |
|---|---:|---|---|---:|---:|---:|
| UA | ±0.25% | periodic C240 | periodic C220 | 1 | -0.005866621 | +0.000690868 |
| endpoint capacity | ±0.25% | maximum C240 | periodic C240 | 0 | `NaN` | `NaN` |
| fluid inventory | ±0.5% | periodic C240 | periodic C240 | 1 | -0.000004085 | -0.000011159 |
| regeneration flow | ±0.5% | periodic C220 | periodic C240 | 1 | +0.010090901 | +0.001609184 |
| latent heat | ±0.25% | periodic C220 | periodic C220 | 1 | +0.009570627 | +0.001522916 |

refined 运行共 10/10 完成，9/10 admissible，4 个严格 pair。endpoint capacity 低侧虽通过 flow、phase、energy、observability 和 mechanism gates，但在 240 cycles 内未通过 periodic gate，因此整对导数保持 `NaN`。将首轮已通过的 buffer pair 与本轮其余因素按“每个因素只能来自同一对称 campaign”合并后，最终可审计证据是 12 个低/高点、11 个 admissible、5/6 strict pairs。

### 8.4.1 endpoint-capacity ultrafine follow-up

输出：`gx101r1_R69_remote/outputs/qian_table4_endpoint_capacity_ultrafine_20260830`。该 campaign 以冻结 C200 为恢复基准，对 endpoint capacity 进行同一 `±0.125%` 对称扰动，目标至 C260，并严格禁止从 rejected 状态继续传播。

| 候选 | 倍率 | 最后已验证周期 | mechanism | periodic | 结果 |
|---|---:|---:|---:|---:|---|
| R03 低侧 | 0.99875 | C240 | 1 | 0 | C260 物性域错误，rejected diagnostic package |
| R04 高侧 | 1.00125 | C240 | 1 | 1 | admissible periodic point |

R03 在 C240 的末周期门禁为 endpoint drift `0.0137309021 K`、same-phase temperature drift `0.22803312 K`、same-phase phase drift `0.0103546134`、Eq. 9 `28.7102545 K`、SCP `0.316481587 W/g`；之后 C240 到 C260 的 Thermal Liquid 温度有效域错误发生在 `HoldPipe_021` 和 `SMA_V3_pump_to_heat_path`。R04 在 C240 通过全部 flow/phase/energy/observability/mechanism/periodic gates，endpoint drift `0.0135877171 K`、same-phase temperature drift `0.23846705 K`、same-phase phase drift `0.0107834064`、Eq. 9 `28.7102555 K`、SCP `0.316481247 W/g`。

由于 strict local derivative 要求同一对称 campaign 的两侧均 mechanism-valid 且 periodic，endpoint-capacity 的 strict pair 仍为 `0`，所有 endpoint-capacity derivative 保持 `NaN`。R03 的 C240 标量只保留为 rejected diagnostic evidence，不进入插值、求根、恢复链、主导因素排序或论文趋势线。

按 fractional parameter change 归一化后，五个合法 pair 的局部响应为：

| 因素 | d(lift)/d(fraction) (K) | d(SCP)/d(fraction) (W/g) | 审核解释 |
|---|---:|---:|---|
| latent heat | +1.914125 | +0.304583 | 五个合法 pair 中两项均最大 |
| UA | -1.173324 | +0.138174 | 提高 UA 略降 lift、略增 SCP |
| regeneration flow | +1.009090 | +0.160918 | 同时提高 lift 与 SCP，泵功也上升 |
| fluid inventory | -0.000408 | -0.001116 | 当前局部响应接近零 |
| SE buffer | 0 | 0 | 首轮 ±1% 范围未分辨出响应 |

这是一组局部 fractional derivatives，不是全局 Sobol 排序。以实际扰动幅值看，最大 high-low 变化仅约 `0.0101 K` 和 `0.00161 W/g`，相对于 C200 与 Qian benchmark 的约 `2.51 K` lift 差和 `0.3235 W/g` SCP 差都很小，所以不能通过这些小扰动解释或消除偏差。

### 8.5 可写与不可写结论

可写：较宽 L8 扰动首先暴露 SE 流量/控制可行域限制；合并后的严格 local OAT 表明 latent heat 是五个合法 pair 中 lift 与 SCP 的最大归一化局部响应，regeneration flow 同时提高两项性能但增加泵功，UA 呈 lift/SCP 权衡，buffer 和 inventory 在当前局部范围近零。所有实际 high-low 变化都远不足以解释 `9.58%` lift 偏差和约 `50.55%` SCP 缺口。

不可写：latent heat 是全局主导因素、五个局部 pair 等价于完整六因素排序，或 endpoint capacity 的导数可由 transient 数值补算。L8 正交对比仍不完整，endpoint capacity pair 仍不可用；用 rejected/transient 数值补算效应会混入不同周期可行域，结论无效。

## 9. Paired strict audit

输出：`gx101r1_R69_remote/outputs_storage_audit/paired_table4_endpoint_audit`

```text
roots_available=0
common_authority=0
common_window=0
common_parameter_contract=0
all_endpoint_gates=0
paired_contract_pass=0
quantitative_pass=0
paired_strict_pass=0
```

这里的 `common_* = 0` 是因为两个 accepted endpoint 根不存在，并非 C200 冻结合同自身损坏。只有 zero-load 和 zero-lift 都成为 accepted root 后，审计才比较共同 authority、共同参数合同和共同窗口。当前正式 claim 是 `not yet reproduced`。

## 10. SCI 图集逐图说明

### Fig. 1 Last-cycle mechanism

目录：C200 `figures_sci/Fig01_last_cycle_mechanism.*`。同一循环相位上对齐 SMA/SE 温度、马氏体分数和各流路质量流量。用于确认四阶段换热、加载/卸载、相变和换向是否同步。它证明末循环机制可读，不单独证明周期稳态或 Table 4 定量复现。

### Fig. 2 Last-cycle axial fields

目录：`Fig02_last_cycle_axial_fields.*`。以 21 个轴向节点展示 SMA/SE 温度和相分数前沿。负责人应通过它识别换热前沿、相变完成度和端点滞后；局部前沿平移不能直接解释为整个场发散。

### Fig. 3 Periodic convergence

目录：`Fig03_periodic_convergence.*`。展示循环端点、漂移、Eq. 9 和 SCP 的跨循环演化。用于说明 C200 是收敛性能点，并将 Qian 目标线作为 benchmark，而不是“已通过”标签。

### Fig. 4 Control and energy

目录：`Fig04_control_and_energy.*`。展示压力命令、液压功、本构热流和能量项。20 ms 平滑仅改善显示，不改变积分。泵功属于 modeled hydraulic boundary，不能替代 SHEX source heat input。

### Fig. 5 Table 4 boundary audit

目录：`Fig05_table4_boundary_audit.*`。在 Eq.9-SCP 平面区分 C200、Qian 两端点和 rejected 诊断。任何 rejected 点或线性外推都不构成 root。

### Fig. 6 Coupled-cycle trade-offs

目录：`gx101r1_R69_remote/outputs_storage_audit/coupled_tradeoff_figure/Fig06_coupled_cycle_tradeoff.*`。

- (a) fixed `Tc` 对 Eq. 9，颜色是 SCP；显示端点搜索尚未形成合法根包络。
- (b) active SE utilization 对 SCP；展示流量利用率变化与 cooling output 的共同变化。
- (c) SE phase swing 对 Eq. 9；绝大多数点接近完整相变，说明当前拒绝主因不是相变摆幅。
- (d) pump power 对 Eq.10 cooling power；颜色仅为 `Qcool/Ppump` hydraulic diagnostic。
- (e) same-phase temperature drift 对 phase drift；区分 periodic admissible 点与 rejected/transient 点。
- (f) Eq.9-SCP 与 Qian 两端点；图内明确标出 system COP withheld。

2026-08-31 更新后 Fig. 6 同时读取 L8 v3、L8 v4、首轮 local OAT、refined local OAT 和 endpoint-capacity ultrafine 标量；过滤 pending 行后，共 40 个真实候选，其中 21 个 admissible、19 个 rejected。所有不通过点仍只以红叉显示，没有被连线、拟合或用于求根。

### Fig. 7 Local sensitivity audit

目录：`gx101r1_R69_remote/outputs_storage_audit/local_sensitivity_figure/Fig07_local_sensitivity_audit.*`。

- (a) UA、(b) 端点热容、(c) SE buffer、(d) SMA fluid inventory、(e) SE regeneration flow、(f) latent heat，各面板只放该因素的对称低/高点。
- 蓝色左轴是 Eq. 9，橙色右轴是 SCP；实心标记为 periodic admissible，叉号为 rejected。
- (c) buffer 使用首轮 `±1%` 合法 pair；其余面板使用 refined campaign 的更小对称扰动。每个因素的低/高点始终来自同一 campaign。
- (a)、(c)、(d)、(e)、(f) 有连线，因为五对均满足严格成对门禁；(b) endpoint capacity 改用 ultrafine `±0.125%` 结果，低侧 rejected，故明确写 `strict pair: unavailable`。
- 该图用于审计“哪些导数可以计算”，不用于把 rejected 点包装成趋势，也不替代 Qian Table 4 端点图。

绘图符号合同：实心圆为 admissible，红叉为 rejected，黄色菱形/方形为 Qian benchmark。红叉只用于显示可行域边界，不参与拟合、求根或效应计算。第二轮视觉审核修正了黑色面板标号、标题/坐标/色标文字、固定 SCP 色标和 (f) 注释留白。

## 11. 与 Qian 文献的具体比较

精确索引：`项目文档/研究笔记/2026-08-22_Qian文献精确定位索引.md`。

| 文献位置 | 对比内容 | 本项目处理 |
|---|---|---|
| Qian 2019 PDF 2 / journal 882 | `Tc` 是 cooling reservoir/CHEX | 固定在 CHEX reservoir，不用内部固体温度替代 |
| PDF 3-4 / 883-884 | SMA-SE 拓扑和四阶段 | 物理 Simscape 四阶段流路 |
| PDF 5 / 885 | Eqs. 1-8、本构与等力等位移 | 21 节点固液方程，每子步重解兼容应力 |
| PDF 5 / 885 | Eqs. 9-10、last 10 cycles | 统一最后 10 完整循环窗口 |
| PDF 5 / 885 | ODE3, 1 ms | 固定 ODE3/1 ms |
| PDF 6 / 886 | Table 2 | 材料/附件来源，不与 Table 4 成品几何混用 |
| PDF 16-17 / 896-897 | 26.2 K、0.64 W/g、Table 4 | paired strict benchmark 目标 |
| Qian 2017 journal 748-749 | AER、管路、buffer、10-cycle steady | inventory/buffer 和稳态窗口参考 |
| Qian 2015 journal 70-74 | 系统控制体、COP、HTF、PID、steady | 性能边界和控制体参考 |
| Tan 2020 PDF 6-9,18-20 | 机械匹配、完整相变、trade-off | 可行域和设计权衡参考 |
| Yuan 2023 PDF 3,8-9,13 | COP 边界、完整相变、ODE3 | 双效扩展和数值 consistency 参考 |

比较规则：同几何、同质量基准、同边界、同窗口才能做定量比较；不同文章只支持拓扑、方程或趋势 consistency。Qian 未提供当前物理压力源路线 PI 的数值增益，因此 PI 是本模型控制闭合，不宣称其参数复现。没有独立测量数据，不能用 `validated`。

## 12. COP、SCP 和证据边界

- SCP：`Eq.10 cooling power / 41.8168364663 g active SE mass`。
- hydraulic diagnostic：`Eq.10 cooling power / modeled mean pump power`，仅说明 active-unit 水力代价。
- heat-driven system COP：代码现在把 SHEX 源到 SHEX 质量块的正向热流在同一最后 10 周期窗口积分，作为显式分母，并声明泵、阀、控制、储热和附件是否包含；C200 冻结结果尚未记录该新增信号，所以当前不报告数值。
- 文献 COP：Qian 2015/2019 和 Yuan 2023 的分母边界不同，不能与 `Qcool/Ppump` 画成同一 COP。

论文允许使用 `simulated`、`predicted`、`benchmark-consistent`、`not yet reproduced`；禁止在当前证据下使用 `validated` 或 `reproduced`。

## 13. 存储审计和数据治理

2026-08-24 首轮清理前：`gx101r1_R69_remote/outputs = 5.973 GiB`；删除 2,177 个旧 raw/probe/legacy-figure 文件，`1.224 GiB`。
2026-08-26 首轮 OAT 收尾前：`5.000 GiB`；删除 374 个已提取标量后的 raw/probe/legacy-figure 文件，`0.232 GiB`，降至 `4.768 GiB`。
2026-08-30 refined OAT 的每个已完成候选在标量和门禁提取后立即压缩，R04/R07/R08/R09/R10/R11/R12 的候选 compactor 合计释放约 `63.0 GB` 十进制 raw；最终存储管理器随后删除 272 个非 C200 MAT、dense probe 或 legacy figure 文件，共 `0.156414 GiB`。2026-08-31 endpoint-capacity ultrafine 完成后又删除 68 个可重建逐循环图片，共 `0.042315 GiB`；`outputs` 当前约 `4.786 GiB`，整个 `正逆耦合` 工作区约 `5.44 GiB`。本轮 dry-run `cleanup_summary_20260831_155758.txt` 显示候选 `0`、未删除；4.64 GiB 的 C200 `physical_simscape_result.mat` 仍按冻结合同保留，不能作为普通旧数据清理。最新应用审计为 `outputs_storage_audit/cleanup_summary_20260831_131709.txt`。

保留内容：

- C200 两个权威 MAT、C200 probe、progress/state、validation report、cycle summary、参数合同和 `figures_sci`。
- 所有运行的报告、summary CSV/JSON、参数合同、stdout/stderr、markers 和小型状态清单。
- L8 与端点的标量结果、拒绝原因、paired audit、control-volume contract 和 Fig. 6 数据。

删除内容：

- C200 之外的 `physical_simscape_result.mat` 和 `final_operating_point.mat`。
- C200 之外的 `stage_temperature_probes_50samples.csv`。
- 所有 `figures` legacy per-run 图片；权威 `figures_sci` 和绘图源代码保留。

审计：`gx101r1_R69_remote/outputs_storage_audit/cleanup_candidates_20260824_103946.csv` 与 `cleanup_summary_20260824_103946.txt`。脚本执行前检查是否有 MATLAB 命令行引用该 outputs 根，删除路径必须保持在仓库 outputs 内。

## 14. 完整结果包

2026-08-31 `Audit_FinalHeatDriveECC_Package.ps1` 审核将 C200、两轮 local OAT 与 endpoint-capacity ultrafine 的必要标量和门禁证据纳入清单；清单和逐文件 SHA-256 分别位于 `outputs_storage_audit/final_results_manifest_20260824.csv` 与 `outputs_storage_audit/final_results_sha256_20260824.csv`。文件名保留首建日期以维持外部引用，内容 schema 已升级并明确记录 ultrafine `2 completed / 1 admissible / 1 rejected / 0 strict pair`。C200 两个冻结 MAT 的 SHA-256 必须仍与第 2 节合同一致。

```text
正逆耦合/
├─ gx101r1_R69_remote/
│  ├─ heatdrive_ecc_coupled_se21.slx
│  ├─ Integrate_HeatDriveECC_Constitutive21_Interface.m
│  ├─ Run_HeatDriveECC_EighthRound_Simulink_Cycles.m
│  ├─ Summarize_HeatDriveECC_EighthRound_Output.m
│  ├─ Plot_HeatDriveECC_SCI_FigureSet.m
│  ├─ Plot_HeatDriveECC_CoupledTradeoff.m
│  ├─ Plot_HeatDriveECC_LocalSensitivityAudit.m
│  ├─ verification/
│  │  ├─ c200_mainline_freeze_contract.json
│  │  ├─ Build_HeatDriveECC_ControlVolumeContract.m
│  │  ├─ Audit_HeatDriveECC_SourceHeatFlow.m
│  │  ├─ Run_HeatDriveECC_Table4_OuterSolve.m
│  │  ├─ Run_HeatDriveECC_Table4_Sensitivity.m
│  │  ├─ Audit_HeatDriveECC_PairedTable4Endpoints.m
│  │  ├─ Verify_FinalHeatDriveECC_Package.m
│  │  ├─ Audit_FinalHeatDriveECC_Package.ps1
│  │  ├─ Manage_HeatDriveECC_OutputStorage.ps1
│  │  └─ WaitAndCheck_HeatDriveECC.ps1
│  ├─ outputs/<C200 authority and scalar diagnostic packages, including local OAT>
│  └─ outputs_storage_audit/
│     ├─ control_volume_contract/
│     ├─ paired_table4_endpoint_audit/
│     ├─ coupled_tradeoff_figure/
│     └─ local_sensitivity_figure/
└─ 项目文档/
   ├─ 报告/SMA-SE正逆耦合_第八阶段完整实施与严格审核报告.md
   └─ 研究笔记/2026-08-22_Qian文献精确定位索引.md
```

## 15. 复核运行命令

### 15.1 C200 门禁，只读，不重新仿真

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
matlab -batch "addpath(fullfile(pwd,'verification')); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.result_package_pass==1 && a.strict_table4_reproduction==0);"
```

预期关键输出：

```text
C200 cycles=200 mechanism=1 periodic=1
RESULT_PACKAGE_PASS=1 STRICT_TABLE4_REPRODUCTION=0
```

### 15.2 重新生成 Fig. 1-5

```powershell
matlab -batch "r='C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'; cd(r); f=fullfile(r,'outputs','qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821','qian2019_table2_table4_simscape_200cycle_20260821_121246','physical_simscape_result.mat'); Plot_HeatDriveECC_SCI_FigureSet(f);"
```

### 15.3 重新生成 Fig. 6

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); o=Plot_HeatDriveECC_CoupledTradeoff(); disp(o);"
```

### 15.4 审核 local OAT 并重新生成 Fig. 7

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); o=Plot_HeatDriveECC_LocalSensitivityAudit(); disp(o); addpath(fullfile(pwd,'verification')); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.local_sensitivity_completed_count==12 && a.local_sensitivity_strict_pair_count==5 && a.result_package_pass==1);"
```

预期关键输出：

```text
completed_points: 12
admissible_points: 11
strict_local_pairs: 5
LOCAL_OAT consolidated_points=12 admissible=11 strict_pairs=5 factors=SE_buffer,UA,fluid_inventory,latent_heat,regenerator_utilization
```

### 15.5 Paired endpoint audit

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(fullfile(pwd,'verification')); a=Audit_HeatDriveECC_PairedTable4Endpoints(); assert(a.paired_strict_pass==0);"
```

### 15.6 结果包 manifest 和 SHA-256

```powershell
cd C:\Users\86182\Desktop\正逆耦合
pwsh -File .\gx101r1_R69_remote\verification\Audit_FinalHeatDriveECC_Package.ps1
```

### 15.7 SHEX 源热流拓扑审计与控制体合同

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(pwd); addpath(fullfile(pwd,'verification')); a=Audit_HeatDriveECC_SourceHeatFlow(); assert(a.source_heat_flow_contract==1); Build_HeatDriveECC_ControlVolumeContract(fullfile(pwd,'outputs_storage_audit','control_volume_contract'));"
```

该命令只在内存中构建模型并审计 `AmbientTempSource -> SHEXSourceToSinkHeatFlowSensor -> HotSinkMass`，不启动仿真、不保存模型；预期输出为 `SHEX_SOURCE_HEAT_FLOW_AUDIT_PASS=1`。生产周期仍必须使用新信号验证方向、正向积分、能量闭合和 COP 分母后，才可解除 system COP withholding。

### 15.8 存储 dry-run 和应用

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1 -Apply
```

第一条只产生候选清单；第二条才删除，并在有 MATLAB 引用 outputs 时拒绝运行。

### 15.9 长任务纪律

```powershell
pwsh -File .\verification\WaitAndCheck_HeatDriveECC.ps1 -WaitMinutes 30
```

该命令静默等待 30 分钟并自然返回一次 JSON；等待中不重复输出，不启动竞争 MATLAB，不停止健康 worker。

## 16. 尚未完成与后续主线

1. 用新增 SHEX source heat-flow sensor 做一次从 C200 合同恢复的周期运行，验证源热流方向、正向积分和能量闭合；通过后才建立真正 heat-driven system COP，在此之前继续 withholding system COP。
2. 两轮 local OAT 加 endpoint-capacity ultrafine 已形成 5/6 个合法 pair；endpoint capacity 已完成一次 `±0.125%` follow-up，但仍为 0 strict pair，低侧物性域错误。不得再把该低侧 transient/失败状态作为导数；是否继续该方向须先解决管路温度有效域和控制可行域问题，并仍须从 C200 或候选最后已验证 OP 恢复。
3. 针对 SE Stage 2/4 末循环 no-reversal、instantaneous-flow 和 RMS-flow 门禁重新设计控制器，先扩展稳定可行域，再继续端点求根。
4. 在控制器通过独立流量测试后重新求 zero-load 和 zero-lift；任何失败点仍不得插值或传播。
5. 两个 accepted roots 共同通过 authority、参数合同、窗口和机制门禁后，再运行 paired strict audit。
6. 建立 `Tc`、外载荷、流量、频率、压力、泵功、SCP、lift 和 system COP 的机制有效 operating map。
7. 增加时间步/节点收敛、能量残差不确定性和独立实验或独立代码比较。只有独立物理测量覆盖所声明量和工况后才使用 validation。

## 17. 最终负责人审核结论

已完成：完整 SMA-SE 主线冻结、控制体合同、outer-solve 实现与两侧候选、两轮 L8、首轮与 refined local OAT、endpoint-capacity ultrafine follow-up、5/6 严格局部 pair、paired audit、Fig. 1-7 SCI 图集、结果哈希和存储治理。

未完成：两个合法 Table 4 端点、endpoint capacity 的严格局部 pair、SHEX 新增源热流信号的生产运行审核和 system COP、独立物理 validation。

可签字结论：

> The fully coupled physical Simscape SMA-SE model reached a mechanism-valid periodic operating point after 200 cycles at fixed `Tc=276.95 K`, predicting an Eq. 9 lift of `28.70997 K` and an active-SE-mass Eq. 10 SCP of `0.3164805 W/g`. Consolidating two independent, symmetric, C200-initialized local OAT campaigns yielded five admissible parameter pairs; latent heat produced the largest normalized local lift and SCP responses among those pairs, while the unavailable endpoint-capacity derivative was not imputed. The paired Qian Table 4 endpoints are not yet reproduced, and system COP is withheld because source-side SHEX heat input is not measured.

禁止签字结论：`Qian Table 4 reproduced`、`experimentally validated`、`system COP = Qcool/Ppump`、或任何基于 rejected L8 点的六因素主导排序。

## 18. 2026-09-01 源热流生产链补充审核

本补充节记录新增 SHEX 源侧热流观测链和从冻结状态连续恢复的最终证据。C200 主线冻结合同保持不变，仍是 SMA-SE 主线的唯一基准；新增 C240 只作为已通过周期门禁的 source-heat-flow 生产恢复点，不替代 C200 的历史权威合同。

### 18.1 运行链与失败边界

1. 首次 `C200 -> C220` 运行因新增信号与旧 checkpoint 的物理信号集合不一致而停止；该结果没有进入恢复链。
2. 第二次重试修复了底层合并器，但固定储库点封装器没有传递 append contract，仍停止；该结果没有进入恢复链。
3. 第三次重试完成真实 C220 Simscape 结果，随后报告字段缺失导致 `MATLAB:nonExistentField`；离线重新审核得到 `mechanism=1`、`periodic=0`，因此 C220 只能作为诊断中间点。
4. 修复汇总字段后，从 C220 已验证 Operating Point 连续运行到 C240；未重置热容、buffer、本构、温度、相分数或独立路线 PI 记忆。

### 18.2 C240 最终生产证据

结果目录：

`gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301`

| 门禁/指标 | 结果 |
|---|---:|
| completed cycles | 240 |
| mechanism gate | 1 |
| periodic steady state | 1 |
| endpoint drift | 0.013660504757 K |
| same-phase temperature drift (max) | 0.220500395386 K |
| same-phase phase-fraction drift (max) | 0.0100248222919 |
| Eq. 9 lift, last 10 cycles | 28.7102572487 K |
| Eq. 10 cooling power | 13.2342546313 W |
| Eq. 10 SCP, active SE mass | 0.316481488072 W/g |
| SHEX source heat input, last 10 cycles | 826.316127343 W |
| source heat flow mean/min/max | 826.307866939 / 0.260349378872 / 4892.90854408 W |
| positive/negative sample fraction | 1 / 0 |
| heat-driven system COP | 0.0160159703936 |
| solid SMA/SE energy residual relative | 2.3930632603e-4 |
| `ALL_REQUIRED_PASS` | 0 |
| strict Table 4 reproduction | 0 |

这里的 COP 是 `Eq.10 cooling power / positive SHEX source heat input`，不是泵功 COP。当前传感器覆盖源侧到 SHEX sink 的源输入和 SMA/SE 固体能量门禁，但没有测量 SHEX 下游至各流体端的完整传递热流，因此 `system_energy_closure_complete=0`，完整系统一阶能量闭合仍未完成。C240 的周期门禁通过不改变 `26.2 K` 与 `0.64 W/g` 两个 Qian Table 4 端点尚未成对复现的结论。

### 18.3 新增代码、合同与验证命令

本轮新增/提交：

- `9b29a47`：允许声明的源热流信号加入 checkpoint 合并。
- `6c78e94`：把 append contract 传递到固定储库点封装器。
- `7634eb4`：补齐源热流 summary 字段并限定末 10 周期有限性检查。
- `d03f509`：冻结 C220 中间恢复合同、恢复解析器和源热流存储治理。

源热流 C240 合同为 `verification/source_heatflow_c240_recovery_contract.json`；生产审核函数为 `verification/Audit_HeatDriveECC_SourceHeatFlowResult.m`。复核 C240 的命令：

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(pwd); addpath(fullfile(pwd,'verification')); a=Audit_HeatDriveECC_SourceHeatFlowResult('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301/physical_simscape_result.mat'); assert(a.production_pass==1); disp(a);"
```

重新运行正式图集（不重跑仿真）：

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(pwd); addpath(fullfile(pwd,'verification')); L=load('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301/physical_simscape_result.mat','physical','summary','options','provenance'); r=struct('physical',L.physical,'summary',L.summary,'options',L.options,'provenance',L.provenance,'used_simulink_sim',true,'authority',L.physical.authority,'legacy_surrogate_used_for_results',false,'output_dir','C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301','output_mat','C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301/physical_simscape_result.mat'); Plot_HeatDriveECC_SCI_FigureSet(r);"
```

### 18.4 存储与恢复状态

2026-09-01 的 storage audit 先 dry-run 后 apply，删除约 `5.18 GiB`：C220 失败/非稳态 raw、C240 legacy per-run figures 和 dense probe CSV。C240 的两份生产 raw、SCI 图集、报告、cycle summary、参数合同、source-heat-flow audit、manifest 和 state/progress 保留。C200 两份冻结文件哈希仍为：

`physical_simscape_result.mat = 0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`

`final_operating_point.mat = FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816`

C240 源热流生产文件哈希为：

`physical_simscape_result.mat = 5C9E76BCEEC4445DF80658CC46D22FD8DB07F2A4B97B460DD30AE8D35786E134`

`final_operating_point.mat = 75673FD6EAA636408DF08861419108B8DA05E73B9F0C261A780EB49BFDA25ACA`

清理后再次 dry-run 的 `candidate_count=0`。后续长任务仍只启动一个 `WaitAndCheck_HeatDriveECC.ps1 -WaitMinutes 30`，等待命令自然返回 JSON 前不轮询、不重复续转、不发送中间状态。

### 18.5 后续主线

当前可推进的下一步是：在 C240 周期状态基础上补齐 SHEX 下游各流体端热流传感器，并建立完整控制体的一阶能量闭合；之后才有资格把 heat-driven COP 扩展为完整系统指标。Table 4 zero-load/zero-lift 的 paired endpoint 求解、endpoint-capacity strict pair、独立代码/实验 validation 和论文数据声明仍未完成，任何失败候选仍不得进入恢复链、插值或论文定量结论。
