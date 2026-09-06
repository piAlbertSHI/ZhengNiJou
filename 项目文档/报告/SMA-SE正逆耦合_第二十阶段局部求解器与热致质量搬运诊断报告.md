# SMA-SE 正逆耦合：第二十阶段局部求解器与热致质量搬运诊断报告

日期：2026-09-06。承接第十九阶段。本阶段包括一次真实但未全部成功的短窗口试验、原生账本分解及两张新的诊断图；没有新增生产循环或替换冻结恢复点。

## 1. 结论及必要更正

1. 两泵腔先前约 `-0.4891 / -0.8189 J` 的梯形路径残差，不能直接称为求解器未满足其离散方程。实际物理网络使用 **1 ms 局部 Backward Euler（BE）**。按该离散式复核，两腔整周期能量残差约 `1.65e-11 / 2.95e-11 J`，逐步绝对残差和约 `6.99e-8 / 7.59e-8 J`。原梯形结果完整保留。
2. 这不等于连续能量闭合或时间收敛。四罐能量残差仍有未解释部分，且端点质量再分配仍在。没有借换积分规则把生产、周期或物理闭合标志改为通过。
3. 水路预算已把主要质量搬运定位到共同泵腔的温度积累项：阶段 1 升温排出约 0.1574 g，阶段 3 降温吸入约 0.1566 g，与 SHEX/SMA 热侧罐的交换对应，压力项显著更小。这支持当前模型中冷热交替连接容积的热膨胀/收缩机制，尚非参数干预后的完整物理因果验证。
4. 原本只改变全局 ode3 步长的对照设计不充分，且 0.5 ms 严格 OP 恢复实际失败。错误设计和失败均明确记录，不能声称完成步长收敛。本阶段不从失败点接续，不重置物理或控制器状态。

## 2. 实际执行与失败证据

真实执行提交 `72823d0b46777178cf2cbd030d76d332072eee14`。程序 `verification/Audit_HeatDriveECC_NativeSolverRefinement.m` 只启动一次前台 MATLAB，等待同一真实 session 自然退出；最终 shell 退出码 **1**。

设计为共同 C180 OP、1800 至 1800.3 s、全局步长 1/0.5/0.25 ms，本构采样始终 1 ms。共同命令终点 1820 s；记录及参数保持严格 checksum error，无部分恢复。

| 项目 | 结果 |
| --- | --- |
| 1 ms 名义试验 | 完成，实际 sim 约 127.4 s |
| 原生前缀比较 | 1240 坐标 × 301 点 = 373240 数值逐位相同 |
| 观测状态前缀比较 | 1376 坐标 × 301 点 = 414176 数值逐位相同 |
| 合计数值比较 | **787416**，最大绝对差 0，端点保留 |
| 0.5 ms 试验 | 完整 OP 恢复被 contents checksum 拒绝，未取得细步长轨迹 |
| 0.25 ms 试验 | 未执行 |
| 新候选 OP | 未保存，不能提升为恢复点 |

错误为 `HeatDriveECC:RefinementStrictRestoreFailed`，原 MATLAB 信息说明当前模型不同于生成初始工作点的模型。官方说明内容校验和不匹配意味着不能完整初始化；warning/none 只会尽量加载可用状态，因此没有采用其建议绕过。见 [Operating Point Contents Checksum Mismatch](https://www.mathworks.com/help/simulink/gui/operatingpointcontentschecksummismatch.html)。

证据目录：`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\native_solver_refinement_20260906`。保留 stdout、失败 result、第一项实际 trace MAT、独立审核 JSON 和进度记录。该目录是**失败的细化试验及成功名义前缀证据**，不是三步长通过包。

## 3. 求解器合同：不能只看全局 Solver

从 C181 保存的 options 构建模型后，实际读取唯一 Solver Configuration 块：`UseLocalSolver=on`、`LocalSolverChoice=NE_BACKWARD_EULER_ADVANCER`、`LocalSolverSampleTime=0.001`。只构建/读取，没有新仿真。数据见 `native_residual_localization_20260906/solver_contract_v2/local_solver_contract.json`。

官方说明，使用局部求解器后，物理网络状态对 Simulink 表示为按局部采样周期更新的离散状态。全局步长变小并不自动减小局部物理积分步长。见 [Solver Configuration：Use Local Solver、Solver Type、Sample Time](https://www.mathworks.com/help/simscape/ref/solverconfiguration.html)。

**字段解释：** 构建后尚未应用 SimulationInput 时，模板全局设置为 ode23t/0.1 s；实际原试验的 SimulationInput 覆盖为 ode3/0.001 s。最新合同分别记录两者，不把模板默认值冒充执行设置。原协议忽略局部求解器，现已追加更正，并在旧全局步长试验入口增加前置拒绝，避免重复消耗。

## 4. 两种账本并列，不改写旧结论

`Audit_HeatDriveECC_NativeResidualLocalization.py` 保留每个 1 ms 区间，分成实际 3.5/1.5/3.5/1.5 s 四阶段，并事先固定检查阶段边界前后 10、50、100 ms 的邻域；没有删除切换点。逐区间和与第十九阶段完整账本一致。

离散检查按 BE 右端点取系数与流量，例如腔体质量积累为 `sum[(M/beta)_n delta(p) - (alpha M)_n delta(T)]`。它检验实际差分方程；原梯形积分仍用于连续路径的采样近似，二者分开命名、分开保存。

| 元件 | 原梯形能量残差 J | BE 能量残差 J | BE 逐步绝对残差和 J |
| --- | ---: | ---: | ---: |
| 泵入口腔体 | -0.489097612 | 1.64873e-11 | 6.98842e-8 |
| 泵出口腔体 | -0.818866261 | 2.95306e-11 | 7.59251e-8 |
| SHEX 水罐 | -0.211169919 | -0.210890067 | 0.242706638 |
| SMA 热侧水罐 | +0.103383325 | +0.103371989 | 0.103501816 |
| SE 冷侧罐 | -0.000114509 | -0.000104629 | 0.045385353 |
| SE 热侧罐 | +0.000233189 | +0.000238562 | 0.057621332 |

两腔 BE 质量残差整周期约 `-2.66e-18 / -1.61e-17 kg`，逐步绝对残差和约 `1.07e-14 / 1.16e-14 kg`。四罐 BE 质量方程也匹配到很小误差，**但四罐的能量项未因该检查而闭合**。不能仅看整周期正负抵消，故表中另给逐步绝对和。

这些结果与本机 `constant_volume_chamber.ssc` 的质量/能量方程相符；方程出处为 [Constant Volume Chamber (TL)](https://www.mathworks.com/help/simscape/ref/constantvolumechambertl.html)。罐式连续方程此前来自 [Tank (TL)：Energy Balance](https://www.mathworks.com/help/hydro/ref/tanktl.html)；受保护实现没有被解码，现阶段仍需核对其能量状态、通量及离散含义，不能把公开连续公式当成已证明的内部实现。

## 5. 水路质量预算改变了下一步优先级

| 阶段 | 两泵腔温度变化 K | 两腔 BE 温度质量项 g | 两腔 BE 压力质量项 g | 两腔端点质量变化 g |
| --- | --- | ---: | ---: | ---: |
| 1 | +82.8578 / +83.0286 | -0.157400345 | -0.0000307414 | -0.156959813 |
| 2 | +2.4910 / +2.4145 | -0.006315579 | +0.0000009188 | -0.006206938 |
| 3 | -80.1014 / -80.2660 | +0.156623688 | +0.0000222326 | +0.157406184 |
| 4 | -5.2475 / -5.1771 | +0.005912681 | +0.0000056827 | +0.005760554 |

两个泵腔与两个水罐的 BE 净质量通量在每阶段相消至约 `1e-19 kg`。阶段 1 SHEX 罐增重约 0.158197 g，阶段 3 SMA 热侧罐减重约 0.155924 g，与上述温度库存项对应。体积固定、温度相关密度的共同泵腔，在连接不同温度的路线时确实参与质量交换；这一现象不是三条 PI 终点漂移即可解释或消除的。

必须另外保留**端点物理质量与离散系数积累的差异**：四水侧元件的每阶段端点总质量变化分别约 +0.471273、+0.107723、+0.760263、-0.157810 mg，整周期仍约 +1.18145 mg。离散质量方程满足不等于原生 rho*V 库存完全守恒，也不等于罐的单周期末状态回到起点。

据此，下一步优先核对 Qian 连接管库存的具体假设，以及本模型“67 根准稳态定名义质量管路 + 两个可压缩混合泵腔”的共同使用是否合理。此时直接改 PI、增加周期数或令膨胀系数为零，都不足以构成已审核的修复。本阶段未改这些参数或拓扑。

## 6. 新图及逐图解释

图目录：`outputs_storage_audit/native_residual_localization_20260906/figures_diagnostic`。两图均输出 300 dpi PNG 和矢量 PDF，实际 PDF 已用 Poppler 渲染查看；没有遮挡、截断、缺字或轴单位混用。图形是可读的期刊式**诊断图**，尚不是文献复现通过后的最终生产图。

- **Fig09_native_balance_definitions**：横轴为 C181 内时间，纵轴为累计能量残差。上排分别是泵入口/出口腔体，蓝虚线 BE 近零、橙实线梯形路径出现瞬态尖峰和周期净差，说明两种检查不可混称。下排 SHEX/SMA 热侧罐两种曲线均有非零偏差，直观显示问题仍未全部解决。竖虚线仅标阶段边界，不隐去其后的快速前沿。
- **Fig10_native_tank_inventory**：上排分别显示水路/SE 回路的质量相对周期初始变化；分开坐标范围，避免 SE 数克往返运动掩盖水侧约 0.16 g 净交换。下排对应显示原生内部 T_I 的变化，不用旧端口 A 温度代替。周期内形状与末端漂移均保留；一条曲线画满 10 s 不等于通过十周期同相位稳态审核。

本阶段没有重新比较 Qian 全文图的全部定量边界，因此不声称“已达到参考文献复现水准”。所用本地文献路径、页码及每篇适用范围仍见 [Qian 文献定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)；2019 的 Table 4 是主量化合同，其余文章不能替换其几何、材料或端点定义。

## 7. 交付、复核与存储管理

核心目录：`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote`。

- 最新预算：`outputs_storage_audit/native_residual_localization_20260906/localization_v3_water_budget.json`，保留 v1、v2，不覆盖历史。
- 真实试验及失败：`outputs_storage_audit/native_solver_refinement_20260906`，唯一新 trace MAT 为 **13500372 bytes**。
- 两图的 SHA-256 在 `figures_diagnostic/figure_manifest.json`；源 packet 和元数据哈希在定位 JSON。
- 本阶段发布：`outputs_storage_audit/native_residual_release_20260906`，包含源代码增量、逐文件哈希、测试日志、失败状态声明及存储快照。依赖第十九阶段已冻结结果包，审核入口同时复核它。
- 完整代码仍为第十七阶段完整 ZIP 加**本阶段直接从该基包生成的 patch**，不需要再叠加第十八/十九阶段 patch。Git 工作树就是完整最新代码，大 MAT 原位交付，不另复制便携全数据 ZIP。

只读审核，不运行仿真：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p 'test_*.py' -v
pwsh -File verification/Audit_HeatDriveECC_NativeResidualPackage.ps1
```

独立重算（使用新输出名，不覆盖旧证据）：

```powershell
$a = 'outputs_storage_audit'
$c = 'outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181'
$new = "$a/owner_residual_recheck_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
python verification/Audit_HeatDriveECC_NativeResidualLocalization.py --cycle-root $c --topology "$a/tl_domain_energy_tables_20260906/tl_domain_metadata.json" --probe "$a/native_inventory_port_comparison_20260906/native_inventory_probe.json" --metadata "$a/native_inventory_model_metadata_20260906/storage_model_metadata.json" --output "$new/localization.json"
python verification/Audit_HeatDriveECC_NativeRefinementCase.py --repo . --case-file "$a/native_solver_refinement_20260906/case_1_traces.mat" --output "$new/nominal_prefix.json"
```

当前 **70 项 Python 测试通过**；新 MATLAB 检查器及局部求解器合同导出完成静态/真实构建检查。包审核通过只表示证据完整和如实保留拒绝结果，输出中 `physical_experiment_exit_code=1`、`solver_refinement_pass=false` 不会被隐藏。

17:52:29 工作区快照为 **19231166586 bytes**、4258 文件，约 **17.910 GiB**；发布时的新快照另存。outputs 仍约 **16.878 GiB**。17:52:09 清理 dry-run 候选 **0**，本阶段实际删除 **0 byte**；不把失败日志或唯一名义前缀证据当垃圾。未复制生产 raw，未改 C200/C180 哈希，未重置 Git；只提交代码、测试、协议和报告。

## 8. 下一阶段仍需完成

1. 对四罐继续核对原生能量通量、储能变量和离散实现；不能用泵腔 BE 通过代替罐的审核。
2. 对照文献连接管/储液器假设，审核共同泵腔热膨胀质量搬运及与准稳态管路并用的适用性，提出保持物理意义的候选模型或边界方案。
3. 重新设计真正覆盖**局部物理求解器**的收敛研究；必须使用兼容检查点或独立的同版本验证协议，不能给现有 OP 改校验和、部分恢复、清空状态或把冷启动替换成旧主线接续。
4. 原生库存、完整内部周期门禁及设备功边界通过前，固定 Tc outer solve、正交敏感性、成对 zero-load/zero-lift、最终 system COP 和独立 validation 均仍未完成。主目标保持不变，没有将本阶段诊断通过替代全部目标完成。
