# SMA-SE 正逆耦合第九阶段：SHEX 控制体、失败链隔离与 Qian 文献对标报告

> **2026-09-03 更正与替代说明**：本报告中的 C240 sink-to-fluid 热流是由节点平衡
> 重建的历史诊断，不是直接测量。后续 C242 已通过完整周期原生 Simscape 三支路
> 直接测量，发现早期 C241 审计受 `SimscapeLogDataHistory=5000` 截断和向前外推污染。
> 当前权威结论、哈希、图集和存储处置以
> `SMA-SE正逆耦合_第十阶段C242原生SHEX闭合与存储治理报告.md` 为准。C240/C241
> 原始 MAT 和 Operating Point 已在 C242 冻结后删除，只保留哈希、合同、报告和诊断。

更新日期：2026-09-03

## 1. 本阶段结论

本阶段没有修改 C200/C240 两个冻结结果，也没有用失败状态续算。工作完成了三件事：

1. 在冻结 C240 结果上，依据真实 SHEX 节点拓扑和能量守恒重建 sink-to-fluid 热流，
   完成 SHEX 局部控制体闭合。
2. 隔离三条 C240 到 C260 的失败链；三条链均在 `2535.101 s` 触发 Thermal Liquid
   最低有效温度错误，均未产生新的 result/checkpoint，全部标记为
   `REJECTED_DO_NOT_RESUME`。
3. 逐页核对“冷凝文献”中的 Qian 系列文献，明确当前结果与 2019 Table 4 的比较
   方法和仍未完成的系统级证据。

当前可以声明：C240 是机制有效且周期稳态的固定边界预测点；SHEX 局部控制体通过。
当前不能声明：完整系统一阶能量闭合、Qian Table 4 严格复现或实验验证。

## 2. 冻结权威与哈希

| 权威对象 | SHA-256 |
|---|---|
| C200 `physical_simscape_result.mat` | `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` |
| C200 `final_operating_point.mat` | `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816` |
| C240 `physical_simscape_result.mat` | `5C9E76BCEEC4445DF80658CC46D22FD8DB07F2A4B97B460DD30AE8D35786E134` |
| C240 `final_operating_point.mat` | `75673FD6EAA636408DF08861419108B8DA05E73B9F0C261A780EB49BFDA25ACA` |

C200 仍是唯一主线基准；C240 是源热流和 SHEX 控制体的附加生产证据。

## 3. 为什么不继续盲目跑 C260

三次独立启动均从通过门禁的 C240 Operating Point 开始，错误位置和时间完全一致：

| 输出根目录 | 观测方式 | 结果 |
|---|---|---|
| `outputs/qian_coupled_shex_transfer_steady_from_c240_20260901` | 下游物理热流传感器 | `2535.101 s`，SMA Thermal Liquid 低温越界 |
| `outputs/qian_coupled_shex_transfer_steady_from_c240_retry_20260901` | 下游物理热流传感器重试 | 同一时刻、同一错误 |
| `outputs/qian_coupled_shex_native_logging_from_c240_20260903` | 移除物理传感器，仅 native simlog | 同一时刻、同一错误 |

报错块为 `SMA/HoldPipe_021` 和 `SMA_V3_pump_to_heat_path`。第三次移除新增传感器后
错误不变，说明传感器不是根因；继续同配置重跑不会增加证据。三条输出根目录各约
`0.07 MiB`，只保留 stdout/stderr、仍指向 C240 的 state、启动合同和拒绝标记；
没有新增 progress 行、result 或 checkpoint，未形成可传播状态。

## 4. SHEX 控制体方法

真实拓扑是：

`AmbientTempSource -> HotSinkAmbientLink -> SHEX sink node -> HotSinkFluidLink -> HotPipe`

SHEX sink node 上只有源侧支路、`HotSinkMass` 储能项和下游流体支路，因此在统一正向
约定下严格满足：

```text
Q_sink_to_fluid = Q_source_to_sink - C_sink * dT_sink/dt
```

冻结 C240 已保存 `Q_SHEX_source_to_sink_W`、`SHEX_T_K` 和显式
`C_sink=418 J/K`。审核函数只读取 C240，不修改 MAT/Operating Point；最后 10 周期
窗口为 `2300-2400 s`，共使用原始 `2,400,001` 个样本。

## 5. 数值结果与门禁

| 指标 | 结果 |
|---|---:|
| 周期数 | 240 |
| periodic gate | 1 |
| source energy, last 10 cycles | `82631.6127342811 J` |
| sink storage change | `-1.54223071149e-5 J` |
| sink-to-fluid energy | `82631.6127497034 J` |
| source mean | `826.316127342811 W` |
| sink-to-fluid mean | `826.316127497034 W` |
| sink-to-fluid min/max | `0.256501245953 / 6773.96050748 W` |
| sink-to-fluid positive fraction | `1` |
| transfer ratio | `1.00000000018664` |
| derivative integration residual | `-1.1735e-13 J` |
| balance residual | `0 J` |
| production pass | 1 |
| complete-system closure | 0 |

transfer ratio 略高于 1 的 `1.866e-10` 相对差来自窗口末端极小的负储能变化，并非
能量增益。严格离散积分残差和控制体平衡残差均通过 `1e-9` 相对门禁。

## 6. Fig. 06 逐图解释

图文件：

`gx101r1_R69_remote/outputs_storage_audit/shex_control_volume_c240_20260903/Fig06_frozen_C240_SHEX_control_volume.png`

上图 (a) 展示 C240 最后一个 10 s 周期：蓝线是 source-to-sink，红线是由节点平衡
重建的 sink-to-fluid，绿线是 `C_sink*dT/dt`。蓝红两线的瞬时差正是 sink 热容的充放热，
因此不能只比较峰值判断闭合。

下图 (b) 展示最后 10 周期的时间平均。source input 与 to-fluid 两根柱几乎相同，
storage 柱接近零，说明周期稳态窗口内 sink 不再累积可观储能。图标题同时给出 transfer
ratio 和 balance residual，负责人可直接从图中判断方向、储能项和闭合质量。

## 7. 代码成果

| 文件 | 作用 | 当前验证状态 |
|---|---|---|
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 从 future production run 的 native simlog 提取 `HotSinkFluidLink/Q` | 静态检查通过；C260 因既有低温越界未产出直接信号 |
| `Summarize_HeatDriveECC_EighthRound_Output.m` | 汇总下游均值、范围、方向和积分 | 静态检查通过 |
| `Validate_HeatDriveECC_EighthRound_Physics.m` | 报告下游热流门禁 | 静态检查通过 |
| `verification/Audit_HeatDriveECC_FrozenSHEXControlVolume.m` | 对冻结 C240 执行节点平衡、导出 CSV/MAT/JSON 和 Fig.06 | 生产审核通过 |
| `verification/Build_HeatDriveECC_FrozenSHEXControlVolumePackage.ps1` | 校验 C240 哈希后生成可复核包 | 通过，确认 frozen files 未修改 |
| `verification/Audit_HeatDriveECC_SHEXTransferResult.m` | 审核未来直接 source/downstream 双信号结果 | 静态检查通过，尚无有效 C260 生产结果 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | 把 SHEX 包、代码和报告加入总清单 | PowerShell 总包审核通过 |
| `verification/Verify_FinalHeatDriveECC_Package.m` | MATLAB 总门禁增加 frozen SHEX 审核 | `RESULT_PACKAGE_PASS=1` |

## 8. 与 Qian 文献的具体比较

主定量比较只使用 Qian et al. 2019：PDF 3-4 页 Fig. 1 对拓扑，PDF 5 页
Eqs. (5)-(10) 对机械兼容和性能窗口，PDF 6 页 Table 2 对材料，PDF 15-17 页
Fig. 13/Table 4 对成品几何与 `26.2 K`、`0.64 W/g` 两个端点。

其他 Qian 文献用于交叉审核而不是拼参数：Tan 2020 PDF 6-9 页复核等力/等位移、
质量比和最小驱动温差；Qian 2015 thermoelastic PDF 6-10 页复核整机控制体和周期
稳态；Qian 2017 PDF 5-10 页复核有限速率动力学、网格和材料匹配；Qian 2015 heat
recovery PDF 3-8 页复核流体往复回热和附件库存；Qian 2021 PDF 4-13 页用于区分
当前单效 SMA-SE 耦合与热功-制冷级联系统。

完整本地路径和页码见：

`项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`

## 9. 复核命令

以下命令不会启动长循环：

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
$env:MW_DDUX_FORCE_DISABLE='1'
pwsh -File .\verification\Build_HeatDriveECC_FrozenSHEXControlVolumePackage.ps1
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.result_package_pass==1);"
pwsh -File .\verification\Audit_FinalHeatDriveECC_Package.ps1
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
```

直接核对冻结哈希：

```powershell
Get-FileHash -Algorithm SHA256 .\outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\physical_simscape_result.mat
Get-FileHash -Algorithm SHA256 .\outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\final_operating_point.mat
```

## 10. 尚未完成及后续主线

1. 诊断 `2535.101 s` 处 `HoldPipe_021`/`SMA_V3_pump_to_heat_path` 的物性有效域，
   先做只读节点温度、压力、焓和控制饱和诊断；修复前不重跑 C260。
2. 在不重置状态的前提下补齐 HHEX、CHEX、buffer、pipe 的热流边界，建立完整耦合
   系统一阶能量残差；SHEX 局部闭合不能替代整机闭合。
3. 对通过机制与周期门禁的候选重新求 zero-load 与 zero-lift 两个端点；失败点不得
   插值、恢复或传播。
4. 完成 endpoint-capacity strict pair、时间步/节点收敛、未报告参数敏感性和 operating map。
5. 增加独立实验或独立代码比较后，才允许把 numerical benchmark 升级为 validation。

## 11. 存储和恢复纪律

`outputs` 当前约 `10.37 GiB`；此前已删除约 `5.18 GiB` 的过时 raw/dense probe/
legacy figures。有效 C200/C240 raw 和 OP 必须保留；三条 C260 失败链仅约 `0.21 MiB`，
保留小型诊断证据比删除更有价值。所有清理先 dry-run，只有审计列出的 superseded
候选才应用删除。

长任务仍只允许一次启动一个 30 分钟静默等待命令。等待自然返回 JSON 前不轮询、
不发送重复状态、不启动竞争任务、不停止健康 MATLAB；失败链不进入恢复状态。
