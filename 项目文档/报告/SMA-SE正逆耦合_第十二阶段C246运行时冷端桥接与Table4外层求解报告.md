# SMA-SE 正逆耦合第十二阶段：C246 运行时冷端桥接与 Table 4 外层求解报告

更新日期：2026-09-04

## 1. 严格结论

C246 是从 C243 已验证 Operating Point 连续运行三个完整周期得到的当前唯一状态恢复
权威。桥接过程保持冷端温度 `Tc=276.95 K` 不变，只把 CHEX Temperature Source
的温度参数从编译时参数改为 Simscape 运行时参数；没有重置热容、buffer、本构、
温度、相分数或独立路线 PI 记忆。

C246 通过机制、周期稳态、检查点连续性、模型热控制体和闭环流体质量门禁，可作为
后续小范围 `Tc` 外层求解的恢复基线。C200 仍是论文性能基准。完整设备一阶定律、
system COP、Qian Table 4 两个成对端点、网格/时间步收敛和独立 validation 尚未完成。

## 2. 为什么必须建立运行时桥接

从 C243 直接修改编译时 CHEX 温度后，MATLAB 报告 ModelOperatingPoint contents
checksum mismatch，说明模型状态结构与保存点不再完全匹配。两个候选均在
`t=2535.101 s` 触发 SMA Thermal Liquid 物性温度上限断言：

| 候选 | 结果 | 失败位置 | 处置 |
|---:|---|---|---|
| `Tc=276.80 K` | 无 result/checkpoint | `SMA/HoldPipe_021`、`SMA_V3_pump_to_heat_path` | rejected，不传播 |
| `Tc=276.94 K` | 无 result/checkpoint | 同上，同一时刻 | rejected，不传播 |

C243 末周期 SMA 固体最高温度仅 `392.602831467 K`，而水物性表上限为
`413.16 K`；两个不同步长却在同一时刻失败，证据指向不完整 Operating Point 恢复，
而不是 `Tc` 步长本身。运行时参数桥接用于在不改变温度数值的情况下建立一个与后续
参数扫描结构一致的新保存点。

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
| checkpoint chain | `true` |
| time continuity | `true` |
| state reset | `false` |
| mechanism | `true` |
| periodic | `true` |

继承的状态类别为 `thermal_capacity`、`buffer`、`constitutive`、`temperature`、
`phase_fraction` 和 `independent_route_PI_memory`。失败结果不得恢复；只有通过全部
门禁并写入恢复合同的结果可以推进。

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

机器可读恢复合同：
`gx101r1_R69_remote/verification/cold_boundary_runtime_c246_recovery_contract.json`。
C243 合同仍保存原始哈希和数值证据，但 `state_recovery_allowed=false`，不得继续作为
状态源。

## 6. 本阶段代码成果

| 文件 | 作用 |
|---|---|
| `Integrate_HeatDriveECC_Constitutive21_Interface.m` | Temperature Source 支持可选择 compiletime/runtime，旧路线默认不变 |
| `verification/Run_HeatDriveECC_ColdBoundaryRuntimeBridge.m` | 同温度、完整 OP、三周期桥接和连续性审核 |
| `verification/Start_HeatDriveECC_ColdBoundaryRuntimeBridge.ps1` | 独立启动器和日志/进程合同 |
| `verification/Run_HeatDriveECC_Table4_OuterSolve.m` | 后续候选只使用 C246 并继承 runtime 配置和控制器状态 |
| `verification/Start_HeatDriveECC_Table4OuterSolve.ps1` | 记录 C246-only 恢复策略 |
| `verification/Resolve_HeatDriveECC_SourceHeatFlowRecovery.m` | 禁止恢复已关闭的 C243 合同 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | 审核 C200/C246 双权威、C243 紧凑历史证据和报告 |
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

解析 C246 恢复合同并确认 C243 已禁用：

```matlab
cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote');
addpath(genpath(pwd));
r = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
    'contract_path', fullfile(pwd,'verification', ...
    'cold_boundary_runtime_c246_recovery_contract.json')));
assert(r.completed_cycles == 246);
```

## 9. 存储与 Git 策略

C246 冻结后只长期保留 C200 paper benchmark 与 C246 current recovery 的 raw/OP。
C243 的合同、SHA-256、系统能量 JSON、validation、周期摘要、参数合同、日志和七张
SCI 图继续保留；其 raw result 和 OP 已被 C246 状态与完整历史替代。删除前 C246
总包通过且没有 MATLAB 引用 outputs；dry-run 逐项确认 20 个候选后，受控删除 C243
raw/OP、C246 legacy 图和 dense probe 共 `5.722 GiB`，outputs 从 `16.254 GiB`
降至 `10.532 GiB`。删除审计为
`outputs_storage_audit/cleanup_summary_20260904_091925.txt`。

代码、合同、报告和审计清单进入 Git；多 GiB MAT 不进入 Git，以哈希和本地冻结路径
管理。清理后再次运行 PowerShell 与 MATLAB 总包审核，确保必要证据未丢失。

## 10. 下一步

1. 从 C246 运行时恢复点以 `Tc=276.94 K` 做最小参数变更候选；先证明无 checksum
   mismatch、无物性域异常，再接受性能数值。
2. 每个候选必须通过 checkpoint/time continuity、mechanism、periodic、节点 KCL、
   模型热残差和质量守恒；失败点仅保留 rejected diagnostic package。
3. 在合法周期点上建立局部斜率，分别求 zero-load 和 zero-lift；禁止用拒绝点或单点
   外推形成 Table 4 结论。
4. 完成 UA、热容、buffer、库存、回热和相变参数的有效域敏感性，以及节点数和时间步
   独立性。
5. 单独解决泵功热耦合与附件散热边界后，才审核完整设备一阶定律和 system COP。

## 11. 负责人可用结论

> The C246 operating point is a mechanism-valid and periodic continuation of
> C243 with an unchanged 276.95 K cold boundary and a verified run-time
> temperature parameter. The complete operating-point state and time continuity
> are preserved, and the modeled thermal control volume closes to a relative
> residual of 1.672e-4. It is the current continuation authority, but it is not
> a reproduction of Qian et al.'s paired Table 4 endpoints and does not yet close
> the full device first-law boundary.
