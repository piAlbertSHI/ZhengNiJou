# SMA-SE 正逆耦合：第八阶段完整实施与严格审核报告

生成日期：2026-08-24；OAT 与最终结果包更新：2026-08-26
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
| local OAT | 12/12 完成，6 点 admissible | 2/6 对可计算严格局部响应 |
| local OAT 非零严格响应 | SE regeneration flow | `+1%` 相对变化对应 lift `+0.0100909 K`、SCP `+0.00160918 W/g` |

当前最强可写结论是：完整 SMA-SE 物理 Simscape 模型在固定 `Tc=276.95 K` 下达到机制有效的周期性能点；参数过渡和端点搜索的首要限制来自 SE 末循环流量/控制可行域，而不是相变、能量或可观测性门禁。严格 local OAT 仅允许对 SE buffer 与 regeneration flow 两对求导，其中 regeneration flow 是唯一非零响应；这不足以建立完整六因素排序。当前结果没有同时复现 Qian 等人报告的 `26.2 K @ zero load` 和 `0.64 W/g @ zero lift`。

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

- `verification/Build_HeatDriveECC_ControlVolumeContract.m`：生成 9 个控制体的 CSV/JSON/Markdown 合同。
- 明确 CHEX sensor、SHEX/HHEX/CHEX 流体、SMA、SE、buffer、连接管和泵功边界。
- Eq. 9/Eq. 10 使用最后 10 个完整循环窗口。
- SCP 分母为 active SE solid mass：`41.8168364663 g`。
- `Qcool/Ppump` 只称 hydraulic/active-unit diagnostic；因缺少 SHEX source heat-flow，system COP withheld。

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

### 8.4 可写与不可写结论

可写：较宽 L8 扰动首先暴露 SE 流量/控制可行域限制；局部 OAT 表明 regeneration flow 在当前合法局部域内同时提高 lift 与 SCP，但幅度远不足以解释 `9.58%` lift 偏差和约 `50.55%` SCP 缺口。SE buffer 局部响应为零，其余四因素仍不可严格求导。

不可写：UA、buffer、inventory 或 latent heat 是“主导因素”，也不能宣称 regeneration flow 已是全局主导因素。L8 正交对比不完整，local OAT 只有 2/6 对合法。用 rejected/transient 数值补算效应会混入不同周期可行域，结论无效。

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

2026-08-26 更新后 Fig. 6 同时读取 L8 v3、L8 v4 和 local OAT，共 28 个敏感性点，其中 11 个 admissible、17 个 rejected。增加 OAT 后仍保持实心圆/红叉合同，不通过点没有被连线或拟合。

### Fig. 7 Local sensitivity audit

目录：`gx101r1_R69_remote/outputs_storage_audit/local_sensitivity_figure/Fig07_local_sensitivity_audit.*`。

- (a) UA、(b) 端点热容、(c) SE buffer、(d) SMA fluid inventory、(e) SE regeneration flow、(f) latent heat，各面板只放该因素的对称低/高点。
- 蓝色左轴是 Eq. 9，橙色右轴是 SCP；实心标记为 periodic admissible，叉号为 rejected。
- 只有 (c) 和 (e) 两对有连线，因为只有它们满足严格成对门禁；其余面板明确写 `strict pair: unavailable`。
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
- heat-driven system COP：分母应是 SHEX heat-source input，并声明泵、阀、控制、储热和附件是否包含；当前 SHEX source heat-flow 未测量，所以不报告数值。
- 文献 COP：Qian 2015/2019 和 Yuan 2023 的分母边界不同，不能与 `Qcool/Ppump` 画成同一 COP。

论文允许使用 `simulated`、`predicted`、`benchmark-consistent`、`not yet reproduced`；禁止在当前证据下使用 `validated` 或 `reproduced`。

## 13. 存储审计和数据治理

2026-08-24 首轮清理前：`gx101r1_R69_remote/outputs = 5.973 GiB`；删除 2,177 个旧 raw/probe/legacy-figure 文件，`1.224 GiB`。
2026-08-26 OAT 收尾前：`5.000 GiB`；再次删除 374 个已提取标量后的 raw/probe/legacy-figure 文件，`0.232 GiB`。
最终：`4.768 GiB`，其中约 `4.70 GiB` 是唯一保留的 C200 authority raw；local OAT 标量包为 `19.58 MiB`。候选 compactor 在 12 点运行过程中累计释放 `103,825,298,192 bytes`（`96.695 GiB`）临时 raw。

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

```text
正逆耦合/
├─ gx101r1_R69_remote/
│  ├─ heatdrive_ecc_coupled_se21.slx
│  ├─ Plot_HeatDriveECC_SCI_FigureSet.m
│  ├─ Plot_HeatDriveECC_CoupledTradeoff.m
│  ├─ Plot_HeatDriveECC_LocalSensitivityAudit.m
│  ├─ verification/
│  │  ├─ c200_mainline_freeze_contract.json
│  │  ├─ Build_HeatDriveECC_ControlVolumeContract.m
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
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); o=Plot_HeatDriveECC_LocalSensitivityAudit(); disp(o); addpath(fullfile(pwd,'verification')); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.local_sensitivity_completed_count==12 && a.local_sensitivity_strict_pair_count==2);"
```

预期关键输出：

```text
completed_points: 12
admissible_points: 6
strict_local_pairs: 2
LOCAL_OAT completed=12 admissible=6 strict_pairs=2 factors=SE_buffer,regenerator_utilization
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

### 15.7 存储 dry-run 和应用

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1 -Apply
```

第一条只产生候选清单；第二条才删除，并在有 MATLAB 引用 outputs 时拒绝运行。

### 15.8 长任务纪律

```powershell
pwsh -File .\verification\WaitAndCheck_HeatDriveECC.ps1 -WaitMinutes 30
```

该命令静默等待 30 分钟并自然返回一次 JSON；等待中不重复输出，不启动竞争 MATLAB，不停止健康 worker。

## 16. 尚未完成与后续主线

1. 增加 SHEX source heat-flow sensor 和周期积分，建立真正 heat-driven system COP；在此之前继续 withholding system COP。
2. local OAT 已完成，但仅 2/6 对合法；先对 UA、端点热容、inventory 和 latent heat 扩展周期数或缩小扰动，仍须保持独立 C200 恢复和成对门禁，不能沿 rejected OP 续算。
3. 针对 SE Stage 2/4 末循环 no-reversal、instantaneous-flow 和 RMS-flow 门禁重新设计控制器，先扩展稳定可行域，再继续端点求根。
4. 在控制器通过独立流量测试后重新求 zero-load 和 zero-lift；任何失败点仍不得插值或传播。
5. 两个 accepted roots 共同通过 authority、参数合同、窗口和机制门禁后，再运行 paired strict audit。
6. 建立 `Tc`、外载荷、流量、频率、压力、泵功、SCP、lift 和 system COP 的机制有效 operating map。
7. 增加时间步/节点收敛、能量残差不确定性和独立实验或独立代码比较。只有独立物理测量覆盖所声明量和工况后才使用 validation。

## 17. 最终负责人审核结论

已完成：完整 SMA-SE 主线冻结、控制体合同、outer-solve 实现与两侧候选、两轮 L8、12 点 local OAT、paired audit、Fig. 1-7 SCI 图集、结果哈希和存储治理。

未完成：两个合法 Table 4 端点、其余 4/6 因素的严格局部效应、SHEX 热源输入和 system COP、独立物理 validation。

可签字结论：

> The fully coupled physical Simscape SMA-SE model reached a mechanism-valid periodic operating point after 200 cycles at fixed `Tc=276.95 K`, predicting an Eq. 9 lift of `28.70997 K` and an active-SE-mass Eq. 10 SCP of `0.3164805 W/g`. A 12-point mechanism-gated local OAT admitted six points and only two complete pairs; regeneration flow was the sole non-zero strict local response, while the remaining unavailable pairs were not imputed. The paired Qian Table 4 endpoints are not yet reproduced, and system COP is withheld because source-side SHEX heat input is not yet measured.

禁止签字结论：`Qian Table 4 reproduced`、`experimentally validated`、`system COP = Qcool/Ppump`、或任何基于 rejected L8 点的六因素主导排序。
