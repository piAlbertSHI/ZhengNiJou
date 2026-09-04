# SMA-SE 正逆耦合第十二阶段：C246 运行时桥接、严格恢复复核与资格撤销报告

更新日期：2026-09-04

## 1. 严格结论

C246 的已完成数值段通过机制、周期稳态、模型热控制体和闭环流体质量门禁，因此其
性能和能量结果继续保留。后续严格复核发现，该段是在
`OperatingPointContentsChecksumMismatchMsg=warning` 下运行，MATLAB 明确报告
`Solver Configuration/EVAL_KEY/STATE_1` 无效。用 contents/interface 均为 `error`
的 1 ms 严格恢复烟测复核时，C246 Operating Point 无法完整加载。

因此，C246 **不是当前状态恢复权威**；原 `state_reset=false` 结论已撤销，机器合同现为
`state_reset=true`、`complete_operating_point_restore_verified=false`、
`state_recovery_allowed=false`。C200 在当前模型上也发生同类严格校验失败，只保留为
冻结论文性能基准。当前没有合法续算权威；新的 runtime 模型必须从冷态独立建立，
随后只有严格 checksum 恢复成功的 Operating Point 才可推进。完整设备一阶定律、
system COP、Qian Table 4 成对端点、网格/时间步收敛和独立 validation 仍未完成。

## 2. 为什么必须建立运行时桥接

从 C243 直接修改编译时 CHEX 温度后，MATLAB 报告 ModelOperatingPoint contents
checksum mismatch，说明模型状态结构与保存点不再完全匹配。两个候选均在
`t=2535.101 s` 触发 SMA Thermal Liquid 物性温度上限断言：

| 候选 | 结果 | 失败位置 | 处置 |
|---:|---|---|---|
| `Tc=276.80 K` | 无 result/checkpoint | `SMA/HoldPipe_021`、`SMA_V3_pump_to_heat_path` | rejected，不传播 |
| `Tc=276.94 K` | 无 result/checkpoint | 同上，同一时刻 | rejected，不传播 |

C243 末周期 SMA 固体最高温度仅 `392.602831467 K`，而水物性表上限为
`413.16 K`；两个不同步长却在同一时刻失败。原方案试图用同温度 runtime 桥接建立
新保存点，但桥接本身已出现 contents checksum mismatch，因此没有完成该目标。
MathWorks 文档说明：contents mismatch 表示模型结构或算法不同，软件不能完整初始化
到原 Operating Point；warning 只会尽量加载可用状态，不能证明完整连续性。

## 3. C246 连续性和状态继承

| 门禁 | C246 结果 |
|---|---:|
| 完成周期 | `246` |
| 状态 | `periodic_steady_state` |
| 原权威周期 | `243` |
| 分段开始/期望时刻 | `2430 / 2430 s` |
| `Tc` 保持不变 | `true` |
| 运行时可调 | `true` |
| checkpoint restart | `true` |
| 自定义 checkpoint chain | `true` |
| 时间轴连续 | `true` |
| contents checksum 严格恢复 | `false` |
| 无效内部状态 | `Solver Configuration/EVAL_KEY/STATE_1` |
| state reset | `true`，至少一个内部状态未恢复 |
| mechanism | `true` |
| periodic | `true` |

自定义合同和时间戳只能证明文件、参数与时间轴一致，不能替代 Simulink contents
checksum。现在不再声明 `thermal_capacity`、`buffer`、`constitutive`、`temperature`、
`phase_fraction`、`independent_route_PI_memory` 以及 Simscape solver 内部状态已被完整
继承。C246 仅作性能/诊断证据，禁止恢复或插值。

## 4. C246 数值审核

| 指标 | 数值 | 门禁/解释 |
|---|---:|---|
| endpoint drift | `0.0136023292 K` | periodic 通过 |
| same-phase temperature drift | `0.1935553131 K` | periodic 通过 |
| same-phase phase drift | `0.00935680452` | periodic 通过 |
| Eq. 9 lift | `28.7102592458 K` | 固定边界点，不是 zero-load root |
| Eq. 10 SCP | `0.316480808133 W/g` | 固定边界点，不是 zero-lift root |
| SHEX source input | `826.330180624 W` | 正向热驱动边界 |
| CHEX cooling input | `12.9667638702 W` | 当前固定边界冷量 |
| HHEX ambient rejection | `836.322087131 W` | 环境排热边界 |
| modeled residual | `-0.13987333999 W` | 模型热控制体残差 |
| relative residual | `1.67248171658e-4` | `<1e-3`，通过 |
| closed-loop mass drift | `1.333837539e-6 kg` | 相对 `3.085441665e-6`，通过 10 ppm |
| parasitic pump power | `11.8430413288 W` | 已报告但未热耦合 |

SHEX/HHEX/CHEX 节点 KCL RMS 分别为 `1.704e-13`、`3.156e-11` 和 `0 W`。
当前可以声明 modeled thermal control volume 通过；不能声明 complete device first-law
closure，因为 Pressure Source (TL) 仍使用 `power_spec=none`，泵耗散和外部附件散热
尚未分配到实测设备边界。

## 5. 权威文件和哈希

C246 结果目录：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_cold_boundary_runtime_bridge_from_c243_20260904\qian2019_table2_table4_simscape_246cycle_20260904_075932`

```text
physical_simscape_result.mat
B5FA3DE5C0AB7F386B686A6D3090599696DAFA11EAEAB50AEB7CF628238D291E

final_operating_point.mat
6EE1E34C0364C72833BD3918463AB3E6A2600C013BD2EC8DA3FA81FB1D854473
```

机器可读的已撤销恢复合同：
`gx101r1_R69_remote/verification/cold_boundary_runtime_c246_recovery_contract.json`。
C243 合同仍保存原始哈希和数值证据，但其 raw/OP 已按此前存储治理删除；C200 与
C246 的 raw/OP 均保留用于论文证据和故障追溯，当前都不得作为当前模型状态源。

严格恢复证据：

- `outputs_storage_audit/c246_strict_restore_20260904/strict_restore_audit.json`
- `outputs_storage_audit/c200_strict_restore_20260904/strict_restore_audit.json`

## 6. 本阶段代码成果

| 文件 | 作用 |
|---|---|
| `Integrate_HeatDriveECC_Constitutive21_Interface.m` | Temperature Source 支持可选择 compiletime/runtime，旧路线默认不变 |
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 生产续算强制 contents/interface checksum=`error`，禁止 flexible restore |
| `verification/Audit_HeatDriveECC_OperatingPointRestore.m` | 1 ms 严格恢复审计，不写新 OP、不传播失败状态 |
| `verification/Run_HeatDriveECC_ColdBoundaryRuntimeBridge.m` | 只有严格完整恢复通过才允许桥接被接受 |
| `verification/Start_HeatDriveECC_ColdBoundaryRuntimeBridge.ps1` | 独立启动器和日志/进程合同 |
| `verification/Run_HeatDriveECC_Table4_OuterSolve.m` | C246 合同禁用后会在候选启动前失败，不允许隐式回退 |
| `verification/Resolve_HeatDriveECC_SourceHeatFlowRecovery.m` | 要求合同显式证明完整 checksum 恢复 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | 审核 C200/C246 性能证据、严格恢复失败和恢复许可关闭 |
| `verification/Verify_FinalHeatDriveECC_Package.m` | MATLAB 侧复核桥接、周期、机制、能量和质量门禁 |
| `verification/Manage_HeatDriveECC_OutputStorage.ps1` | 只保护 C200 与当前 C246 raw/OP，列出其余可删除大文件 |

## 7. 与 Qian 文献的具体对比

主定量合同仍是 Qian et al., Energy 182 (2019), DOI
`10.1016/j.energy.2019.06.094`：PDF 3-4 页对照四阶段拓扑，PDF 5 页对照
Eqs. (1)-(10)，PDF 15-16 页对照成品几何，PDF 16-17 页对照 Table 4 的
`26.2 K` zero-load 与 `0.64 W/g` zero-lift 两个不同端点。

C246 的两个性能数值来自同一个 `Tc=276.95 K` 固定边界，不能与 Table 4 两个端点
分别拼接。Qian 2015、2017、2021、2023 以及 Tan 2020 只用于周期稳态、回热、机械
兼容、系统边界和参数有效域的交叉核对，不覆盖 2019 参数合同。完整本地 PDF 路径、
DOI 和页码见：

`C:\Users\86182\Desktop\正逆耦合\项目文档\研究笔记\2026-09-03_Qian本地文献精确定位与模型映射.md`

## 8. 复核命令

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
pwsh -File .\verification\Audit_FinalHeatDriveECC_Package.ps1
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.result_package_pass);"
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
```

确认 C246 解析器拒绝恢复：

```matlab
cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote');
addpath(genpath(pwd));
try
    Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
        'contract_path', fullfile(pwd,'verification', ...
        'cold_boundary_runtime_c246_recovery_contract.json')));
    error('C246 should not be accepted for recovery.');
catch e
    assert(strcmp(e.identifier,'HeatDriveECC:DisabledSourceRecoveryContract'));
end
```

## 9. 存储与 Git 策略

C246 现阶段保留 C200 paper benchmark 与 C246 performance/diagnostic evidence 的 raw/OP。
C243 的合同、SHA-256、系统能量 JSON、validation、周期摘要、参数合同、日志和七张
SCI 图继续保留；其 raw result 和 OP 已被 C246 状态与完整历史替代。删除前 C246
总包通过且没有 MATLAB 引用 outputs；dry-run 逐项确认 20 个候选后，受控删除 C243
raw/OP、C246 legacy 图和 dense probe 共 `5.722 GiB`，outputs 从 `16.254 GiB`
降至 `10.532 GiB`。删除审计为
`outputs_storage_audit/cleanup_summary_20260904_091925.txt`。

代码、合同、报告和审计清单进入 Git；多 GiB MAT 不进入 Git，以哈希和本地冻结路径
管理。清理后再次运行 PowerShell 与 MATLAB 总包审核，确保必要证据未丢失。

## 10. 下一步

1. 先验证当前 runtime 模型构建两次是否具有相同 contents checksum，并完成“冷态
   1 ms 保存 OP -> 重建模型 -> 严格恢复 1 ms”的确定性测试。
2. 确定性通过后，从冷态独立运行 runtime 模型到周期稳态，生成新的严格恢复基线；
   不使用 C200/C246 partial restore 缩短过程。
3. 每个候选必须通过 strict checkpoint restore、time continuity、mechanism、periodic、节点 KCL、
   模型热残差和质量守恒；失败点仅保留 rejected diagnostic package。
4. 在合法周期点上建立局部斜率，分别求 zero-load 和 zero-lift；禁止用拒绝点或单点
   外推形成 Table 4 结论。
5. 完成 UA、热容、buffer、库存、回热和相变参数的有效域敏感性，以及节点数和时间步
   独立性。
6. 单独解决泵功热耦合与附件散热边界后，才审核完整设备一阶定律和 system COP。

## 11. 首个运行时候选的窗口审核更正

提交 C246 冻结后，从 C246 独立启动 `Tc=276.94 K`、3-cycle 的首个运行时候选。
仿真到 C249 正常结束，末周期实际 CHEX 温度为 `276.94 K`，流量、相变、固体能量、
periodic、节点 KCL、模型热残差和质量守恒均通过；但总机制门禁为 0，未生成可恢复
checkpoint，编排器保持 C246 为唯一恢复源。

失败门禁仅为 `fixed_chex_temperature_authority`。原因是该门禁与 Eq.9/Eq.10 都审核
最后 10 个周期，而只追加 3 周期使窗口包含 7 个旧 `276.95 K` 周期；所以报告中的
最大温度误差恰为 `0.01 K`。这不是运行时参数未生效，也不能把 C249 改称通过点。
代码已要求所有改变 `Tc` 的首段至少运行 11 个新周期，使最后 10 周期窗口完全排除
变更时刻和旧权威历史。C249 保留约 `1.0 MiB` 的紧凑 rejected diagnostic package；
已删除 raw/OP/legacy 图 `6,297,277,307` 字节（`5.864797 GiB`），不传播恢复状态。

## 12. 负责人可用结论

> The completed C246 segment is mechanism-valid and periodic, and its modeled
> thermal control volume closes to a relative residual of 1.672e-4. However,
> strict contents-checksum testing proves that its ModelOperatingPoint cannot be
> completely restored in the current model; C246 is therefore retained only as
> performance and diagnostic evidence, not as a continuation authority. C200 is
> likewise a frozen paper benchmark rather than a current-model recovery state.
> No paired Table 4 endpoint or full-device first-law closure is claimed.

## 13. Clean11 失败与严格恢复审计

为排除 C249 的 10 周期窗口混入旧温度问题，第二次候选要求一次追加 11 周期。该仿真
未生成 C257 结果，而是在绝对时间 `2535.101 s`、cycle 254 Stage 3 开始后 `0.101 s`
再次触发 `SMA/HoldPipe_021` 与 `SMA_V3_pump_to_heat_path` 的 Thermal Liquid 最高温度
断言。编排器保持 `validated_cycles=246`，未产生 result/checkpoint，失败状态未传播。

随后对 C246 和 C200 分别执行 contents/interface checksum=`error` 的 1 ms 审计，二者
均在完整加载 Operating Point 前终止，`strict_restore_pass=false`。这证明此前 warning
不能作为状态连续性证据，也解释了为什么不能继续从 C246 调整 `Tc`。生产运行器现已
写死 strict 策略；任何 checksum mismatch 会在长仿真前失败。

独立的 runtime builder 确定性审计从冷态运行 1 ms、保存内存 OP、关闭并重建模型，
随后严格恢复到 2 ms。两次 `Simulink.BlockDiagram.getChecksum` 相同，第二步严格恢复
成功，`production_runtime_cold_start_allowed=true`。因此缺陷位于旧 OP 与当前结构之间，
不是当前 builder 每次随机改变结构；新的 runtime 冷启动链可以安全建立自身检查点。
