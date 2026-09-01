# SE21 SMA-SE 耦合：完整修改、结果、绘图与审核报告

> 历史状态说明：本文件冻结于 C200 完成后的 2026-08-21。第 8 节的实际实施、
> zero-load/zero-lift、两轮 L8、paired audit、Fig. 6 和 2026-08-24 存储审核，
> 以同目录 `SMA-SE正逆耦合_第八阶段完整实施与严格审核报告.md` 为准。

生成状态：2026-08-21 主链 C200 结果完成后整理。本文是当前工作区的权威交接报告；它不把未通过的文献定量门禁包装成复现结论。

## 1. 最终结论

当前唯一可作为主线结果的文件是：

`gx101r1_R69_remote/outputs/qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821/qian2019_table2_table4_simscape_200cycle_20260821_121246/physical_simscape_result.mat`

该结果是物理 Simscape、四阶段 SMA-SE 耦合、21+21 轴向节点、ODE3、1 ms 步长、accelerator 模式、固定 CHEX 温度 `Tc=276.95 K` 的 200-cycle 结果。它满足当前机制和周期稳态审核，但没有通过 Qian Table 4 的严格定量复现门禁：

| 项目 | C200 当前结果 | 审核结论 |
|---|---:|---|
| 机制门禁 | 1 | 通过 |
| 周期稳态 | 1 | 通过，最后 10 个完整循环窗口 |
| Eq. 9 温跨 | 28.7099701 K | 不是 Table 4 的 26.2 K 严格结果 |
| Eq. 10 SCP | 0.316480491 W/g | 非零，仍不是 zero-load root；低于 0.64 W/g |
| 端点/极值漂移 | 0.0135818 K / 1.31945e-7 | 通过当前周期门禁 |
| 同相温度 max/P99/RMS | 0.167090 / 0.0356652 / 0.00760518 K | P99/RMS 通过；max 保留为前沿时移诊断 |
| 同相相分数 max/P99/RMS | 0.00755658 / 0.00169579 / 0.000366455 | P99/RMS 通过；max 保留为诊断 |
| `ALL_REQUIRED_PASS` | 0 | 仍有定量/边界门禁未通过 |
| `strict_table4_reproduction` | 0 | 不得宣称严格复现 |

C200 的 `HHEX-CHEX` 端点 lift 为 `26.2322671 K`，接近 Qian Table 4 的 `26.2 K`；但 Qian Eq. 9 的周期平均 outlet-temperature lift 是 `28.7099701 K`，相对目标误差约 `9.58%`，超过本项目设置的 `5%` 定量门限。Eq. 10 的当前 SCP 只有 `0.316480491 W/g`，约为 `0.64 W/g` 的 `49.45%`，因此只能称为固定边界下的有效性能点，不能称为 zero-load maximum 或 Table 4 reproduction。

## 2. 十二天长任务的可审计完成内容

这里的“十二天”按长任务工作链汇总，不虚构每一次 heartbeat 的独立科学产出；每项均对应代码、日志、报告或结果文件。

1. 完成 SMA 与 SE 的四阶段热驱动正逆循环接口：SMA/SE 力学兼容、双流体域、SHEX/HHEX/CHEX 换热、21+21 轴向节点、热容与 buffer 状态在连续时间线上传递。
2. 将本构相分数推进固定为 1 ms Bogacki-Shampine/ODE3 子步；三个子阶段都重新求解兼容应力，不在阶段端点强制相分数或温度。
3. 修正 Qian Table 4 几何质量合同：显式使用 32 根 1 mm SMA 线束体积；不再把旧圆板面积映射当成 Table 4 激活体积；SE buffer 使用声明质量和 glycol 密度换算。
4. 将 SE Stage 2/4 控制器改为同一物理压力源上的路线独立 PI，并保留路线记忆；增加稳定段瞬时流量、反向流量、相变、压力、液体物性、换热器和能量残差门禁。
5. 对 accelerator 与 normal 执行回归；保留 Operating Point 合同检查，拒绝旧模型、代理结果或不完整检查点跨合同续算。
6. 以多条冷态和续算链定位失效机制：共享 PI、dynamic feedforward、Stage 4 增益、路线平均/端点前馈等分支均只作诊断，机制失败结果没有传播到主链。
7. 建立固定 CHEX 温度边界链：以已验证 C107 Operating Point 恢复，完成 C127、C147、C167、C187、C200；C200 通过新的周期稳态统计门禁。
8. 增加周期稳态的统计门禁：保留 endpoint 与相变极值 `L_inf`，并增加全场同相温度/相分数 P99 与 RMS；将原始同相 `L_inf` 作为前沿时移诊断，避免把前沿位移误判为全场状态失稳。
9. 完成 SCI 图集函数和五张图的白底、黑轴、600 dpi PNG、矢量 PDF 审核；图例、色标、注释和 Fig. 4 图外图例已修复。
10. 对 Qian 2019、热弹性循环、active regenerator 和热回收相关资料建立对比边界；明确 verification、benchmark、consistency 与 validation 的不同含义。
11. 对工作区执行过时原始数组清理：删除可复现、失败或被后续 checkpoint 完整替代的 MAT/大 CSV，保留小型报告、参数合同、progress/state、拒绝或替代说明和主线权威结果。
12. 维护 Git 提交链、最终结果清单、SHA-256 清单和本报告，使长任务从“窗口状态”变成可复核的文件包。

## 3. 代码成果与 Git

本次关键代码文件：

- `gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`：唯一生产 Simscape 模型；主链报告中记录了生产模型哈希。
- `gx101r1_R69_remote/Plot_HeatDriveECC_SCI_FigureSet.m`：从权威 `physical_simscape_result.mat` 生成五张 SCI 图及 manifest。
- `gx101r1_R69_remote/verification/Verify_HeatDriveECC_LongTask.m`：生产三循环/成对 Table 4 审核入口；不应用旧 Stage-only 直模拟路径。
- `gx101r1_R69_remote/verification/WaitAndCheck_HeatDriveECC.ps1`：一次性静默等待 30 分钟后返回一次 JSON 快照；不停止 MATLAB、不修改状态、不在等待中轮询。
- `gx101r1_R69_remote/verification/Verify_FinalHeatDriveECC_Package.m`：只读读取 C200 progress CSV，复核周期门禁和结果包声明，不启动仿真。
- `gx101r1_R69_remote/verification/Audit_FinalHeatDriveECC_Package.ps1`：只读生成最终包 CSV manifest、SHA-256 清单和 JSON 总结。

最近 Git 提交：

| 提交 | 内容 |
|---|---|
| 本次交付提交 | final coupled-cycle audit, SCI figure set and complete report |
| `20d5ee8` | robust periodic convergence diagnostics |
| `5050947` | expose Stage 2 gain schedules for fixed CHEX runs |
| `42057fa` | separate startup flow diagnostics from steady gates |
| `0dff879` | add fixed CHEX reservoir Table 4 workflow |

图集函数、本报告和审计函数已由本次交付提交纳入 Git，实际提交号以 `git rev-parse HEAD` 为准。大 MAT、运行 CSV、PNG/PDF 和本地 hash 清单没有作为 Git 对象加入仓库；它们保留在输出/审计目录并由 SHA-256 清单管理。

## 4. C20 到 C200 的结果演进

固定 `Tc=276.95 K` 主链的可审计阶段如下。C20-C100 来自早期 accelerator/冷态诊断；最终主链从合法 C107 恢复并完成后续段。不同控制合同的数值不能直接拼成一条状态时间线。

| 阶段 | 机制 | Eq. 9 (K) | SCP (W/g) | 端点漂移 (K) | 同相温度 (K) | 同相相分数 | 用途 |
|---:|---:|---:|---:|---:|---:|---:|---|
| C20 | 通过 | 5.93236 | 0.294317 | 0.359995 | 0.368360 | 0.0138976 | 冷启动诊断 |
| C40 | 通过 | 11.5189 | 0.232784 | 0.269556 | 0.360771 | 0.0208524 | 继续性诊断 |
| C60 | 通过 | 16.5369 | 0.215091 | 0.240941 | 0.325238 | 0.0159615 | 继续性诊断 |
| C80 | 通过 | 21.1219 | 0.203128 | 0.223132 | 0.281268 | 0.0141657 | 继续性诊断 |
| C100 | 失败 | 25.3975 | 0.186912 | 0.205824 | 0.310603 | 0.0152535 | 旧链机制失败，拒绝传播 |
| C107 | 通过 | 28.6836 | 0.316197 | 0.0134248 | 0.224137 | 0.0107887 | 合法恢复点/新控制合同 |
| C127 | 通过 | 28.6990 | 0.316369 | 0.0138181 | 0.177160 | 0.00815033 | 稳态收敛 |
| C147 | 通过 | 28.7056 | 0.316440 | 0.0136961 | 0.224502 | 0.0101716 | 稳态收敛 |
| C167 | 通过 | 28.7085 | 0.316468 | 0.0136556 | 0.215731 | 0.00978478 | 稳态收敛 |
| C187 | 通过 | 28.7096 | 0.316478 | 0.0135603 | 0.222436 | 0.0102218 | 稳态收敛 |
| C200 | 通过/周期 | 28.7100 | 0.316480 | 0.0135818 | 0.167090 | 0.00755658 | 最终权威性能点 |

C102 到 C122 的一条尝试因 Simscape Thermal Liquid 温度瞬态越过有效物性范围而异常退出；它没有产生合法 C122 结果，后续只允许从本链最后通过的 Operating Point/prior result 恢复。C100 及早期 dynamic-ff/Stage4 失败链均不属于 C200 的恢复源。

## 5. 每张 SCI 图的含义与负责人说明

图集目录：

`gx101r1_R69_remote/outputs/qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821/qian2019_table2_table4_simscape_200cycle_20260821_121246/figures_sci`

### Fig. 1：`Fig01_last_cycle_mechanism`

上图给出 C200 末循环 SMA/SE 平均温度与 HHEX/CHEX 边界温度；中图给出 SMA/SE 马氏体分数；下图给出 SMA 流量和 SE 两条路线流量。流量面板使用明确标注的左右双纵轴，左轴显示约 50 g/s 的 SMA，右轴显示约 3.2 g/s 的 SE，避免量级差掩盖 SE 路线。负责人应据此说明四阶段内热边界、相变状态和路线换向是否在同一时间轴发生。它证明的是末循环机制可读性和状态耦合，不单独证明周期稳态，也不证明 Table 4 定量结果。

### Fig. 2：`Fig02_last_cycle_axial_fields`

四个热图分别显示 SMA/SE 的 21 节点温度场和相分数场，横轴为归一化轴向位置，纵轴为循环相位。它把“平均温度”拆成轴向信息，便于识别换热前沿、相变前沿和末端滞后。全场图对应周期统计中的同相 P99/RMS 审核，不能把局部前沿时移的 `L_inf` 直接当成整个场发散。

### Fig. 3：`Fig03_periodic_convergence`

四个面板依次为循环端点温度、端点漂移、Eq. 9 lift 和 Eq. 10 SCP 随循环数的演进。它说明 C200 是从冷态/恢复点逐步进入周期性能点的过程；图中 Qian 26.2 K 线是比较线，不是当前结果已经达到该目标的证明。负责人应以 progress CSV 和 validation report 的门禁字段为准。

### Fig. 4：`Fig04_control_and_energy`

四个面板分别显示 SMA/SE 压力命令、液压功率、本构热流和末循环 SMA/SE 能量项。热流曲线用 20 ms 移动平均改善可读性，但积分结果没有改变。它用于解释控制代价、热驱动相变和能量闭合；当前质量基准、泵功边界和 Eq. 10 定义仍需在论文方法部分明确，不能把 active-unit SCP 当成系统 COP。

### Fig. 5：`Fig05_table4_boundary_audit`

该图把 Qian Table 4 的理想端点连接、C200 固定边界周期点、270 K 机制失败点和两点线性诊断外推放在同一 lift-SCP 平面。270 K 点明确标为 rejected，外推根只用于显示模型趋势，不能作为零点结果。该图的核心结论是：当前模型有有效正 SCP 的周期点，但尚未找到同时满足机制门禁和 Qian zero-load quantitative boundary 的根。

## 6. 与 Qian 文献的具体对比方法

本项目采用以下证据等级：生产 Simscape 连续耦合是 verification；Qian Table 4 是外部 benchmark；与 Qian 系列文章的拓扑/趋势一致属于 consistency；没有实验数据，因此不称 validation。

1. 以 Qian 2019 source 中的 `Tc` 定义为 cooling reservoir/CHEX 温度；固定 CHEX 链显式使用 `Tc=276.95 K`，而不是把某个内部节点温度冒充 reservoir。
2. 按 Qian 的流程先给定边界/载荷，再连续运行到 cyclic steady state；只在最后 10 个完整循环窗口计算 Eq. 9 outlet-temperature lift 和 Eq. 10 cooling power/SCP。
3. 使用同一 Table 4 几何和质量合同：32 根 1 mm SMA 线束、两块 0.5 x 17 mm SE 板、active mass `m_r` 和声明的流体/换热器设置；Table 2 的另一组几何不与 Table 4 性能目标混用。
4. 逐项比较 Qian Table 4 的 no-load maximum lift `26.2 K` 和 zero-lift maximum SCP `0.64 W/g`。当前 C200 的 `28.7099701 K` 与 `0.316480491 W/g` 只支持 benchmark discrepancy 的定量报告。
5. 另外核对 CHEX sensor heat flow 与 Eq. 10：C200 为 `12.9667766 W` 对 `13.2342129 W`，差 `0.267436 W`，相对差约 `2.02%`。这说明当前性能定义和 sensor/control-volume 还需要明确，不是严格 root pass。
6. Qian 2015 thermoelastic model 用于核对循环热力学和 SMA-SE 兼容关系；Qian 2017 active-regenerator/heat-recovery 资料用于核对回热、buffer 和有限速率换热的建模方向。它们是方法一致性参考，不把不同几何和不同质量基准直接合并到 Table 4 数值。
7. Qian review/博士论文和本地热驱动系统文章用于检查热驱动正逆耦合拓扑与性能定义；它们不能替代当前模型的独立实验 validation。

## 7. 当前 SE21 尚未完成的工作

1. 未完成同时满足机制门禁、zero-load root、Eq. 9 = 26.2 K 和 Eq. 10 = 0.64 W/g 的完整外层求根。
2. 未完成 CHEX sensor、Eq. 10、管路热流和 active-unit 质量基准的统一控制体审计；当前 mismatch 已量化但未解释为物理误差或采样定义差异。
3. 未完成 UA、热容、buffer、流体库存、回热损失和换热器初始状态的敏感性分析。
4. 未完成材料相变参数、有限速率动力学和温度/应力依赖黏度对 zero-load boundary 的不确定性分析。
5. 未完成独立实验数据或独立代码结果的 validation；当前只能写 numerical verification/benchmark/consistency。
6. 未完成面向论文的性能地图：`Tc`/外部冷负荷、流量、频率、压力、SCP、温跨、泵功和 COP 的共同边界扫描。
7. 未完成把完整 SMA-SE 正逆耦合从固定边界性能点扩展为可审计的外层热源/冷源闭合模型。

## 8. 下一阶段完整 SMA-SE 正逆耦合计划

1. 冻结 C200 结果和 SHA-256；以 C200 `final_operating_point.mat` 作为当前唯一主线恢复参考，不重置热容、buffer、本构、温度、相分数或 PI 路线记忆。
2. 先建立控制体表：分别列 CHEX 传感器、SHEX/HHEX/CHEX 流体、SMA、SE、buffer、管路和泵功的能量/质量边界；让 Eq. 9 与 Eq. 10 的采样窗口和质量基准完全显式。
3. 对固定 `Tc` 做小范围、机制门禁保护的 outer solve；每个候选点必须先完成当前周期稳态和全部流量/相变/能量门禁，失败点只生成 rejected diagnostic package，不进入插值或恢复链。
4. 对 UA、热容、buffer、流体库存、回热和相变参数做正交敏感性分析，识别 9.58% 温跨偏差和约 50.55% SCP 缺口的主导来源。
5. 在有效参数域内重新求解 zero-load 和 zero-lift 两个边界；只有成对端点、共同参数合同、共同周期窗口和全部机制门禁同时满足时，才允许运行 paired Table 4 strict audit。
6. 完成正向/逆向热驱动闭环的工作图：温度边界、流量利用率、相变摆幅、热回收、泵功、SCP 和 COP 的 trade-off，而不是继续盲目降温直到物性域异常。
7. 最后才做论文主文图表、补充材料、数据声明和独立 validation 计划。论文中使用 `simulated`、`predicted`、`benchmark-consistent`、`not yet reproduced`，不使用 `validated` 或 `reproduced`，除非新证据通过对应门禁。

## 9. 运行与验证命令

以下命令只读审计已完成结果，不会启动长循环：

```powershell
cd C:\Users\86182\Desktop\正逆耦合
pwsh -File .\gx101r1_R69_remote\verification\Audit_FinalHeatDriveECC_Package.ps1
```

MATLAB 结果门禁复核：

```powershell
cd C:\Users\86182\Desktop\正逆耦合
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); audit=Verify_FinalHeatDriveECC_Package(pwd); assert(audit.mechanism_pass==1 && audit.periodic_steady_state==1);"
```

重新生成 SCI 图集（需要 MATLAB，但不重新仿真）：

```powershell
cd C:\Users\86182\Desktop\正逆耦合
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); Plot_HeatDriveECC_SCI_FigureSet('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821/qian2019_table2_table4_simscape_200cycle_20260821_121246/physical_simscape_result.mat');"
```

长任务监测只在真正启动新任务后使用，并且一次只挂一个等待命令：

```powershell
pwsh -File .\gx101r1_R69_remote\verification\WaitAndCheck_HeatDriveECC.ps1 -WaitMinutes 30
```

等待期间不发送重复状态，不启动第二个续算，不终止健康 worker。新的仿真恢复只能使用同一合同下最后通过的 Operating Point/prior result。

## 10. 存储与 Git 交付

当前 C200 权威结果包包含：C200 physical MAT、final Operating Point、progress/state、validation report、cycle summary、parameter contract、50-sample probe CSV、五张 PNG/PDF、figure manifest、固定边界 manifest，以及 270 K rejected 的小型报告/CSV/marker。270 K raw MAT 不属于最终结果包。

审计产物目录：

`C:\Users\86182\Desktop\正逆耦合\outputs_storage_audit`

其中生成：

- `final_results_manifest_20260821.csv`
- `final_results_sha256_20260821.csv`
- `final_results_audit_summary_20260821.json`

当前主文件的 SHA-256 摘录如下；完整清单以 CSV 为准：

| 文件 | SHA-256 |
|---|---|
| `physical_simscape_result.mat` | `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` |
| `final_operating_point.mat` | `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816` |
| `steady_continuation_progress.csv` | `F84D3315182221CCD8285601B40ACA6ACA7321F1739E7141AD487CE787CA944B` |
| `Plot_HeatDriveECC_SCI_FigureSet.m` | `D8F8EEA9780ACCF0FFB69D6836312D4880F518CDF0B66859362C853C01185713` |

本回合受控清理释放 `6.925 GB`（约 `6.78 GB` 主旧链原始 MAT/探针数组，另有 `0.145 GB` 中间探针数组）。`gx101r1_R69_remote\outputs` 当前约 `5.62 GB`；其中约 `4.75 GB` 是 C200 权威 physical MAT，不能按旧诊断数据清除。更早阶段已经把用户所述约 120 GB 工作区压缩到当前可审计规模。

清理规则：主 C200 MAT 和其恢复点不删；旧链只保留报告、progress/state、参数合同、拒绝/替代说明和必要小型 Operating Point；删除前先确认 MATLAB 不运行且路径位于 `gx101r1_R69_remote/outputs` 内。任何机制失败结果都不能作为恢复源，也不能写入主线性能图或 Table 4 结论。

本报告、审计脚本、结果复核函数和图集函数应作为代码/文档提交；大体积输出只保存在本地结果包，不进入 Git。

## 11. 负责人签字式审核结论

负责人可以据此向下游写入的结论是：

> The fully coupled physical Simscape SMA-SE model reached a mechanism-valid periodic operating point at fixed `Tc=276.95 K` after 200 cycles. The point predicts `28.710 K` Eq. 9 lift and `0.31648 W/g` Eq. 10 SCP under the declared active-unit boundary. It is a reproducible numerical benchmark point, not yet a strict reproduction of Qian et al.'s Table 4 zero-load endpoints (`26.2 K`, `0.64 W/g`).

不得写入的结论是“已经复现 Qian Table 4”“已经完成 zero-load root”“C200 的 `ALL_REQUIRED_PASS=0` 等于模型机制失败”。

## 12. 源热流观测链与 C240 续算补充

2026-09-01 已完成新增 SHEX 源侧热流传感器的生产验证。主线恢复基准仍为 C200 冻结合同；C240 是从已验证 C220 Operating Point 连续恢复得到的附加生产证据，恢复过程没有重置热容、buffer、本构、温度、相分数或独立路线 PI 记忆。

最终 C240 结果目录：

`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301`

最终门禁为 `mechanism=1`、`periodic=1`、`Eq.9=28.7102572487 K`、`Eq.10 SCP=0.316481488072 W/g`。末 10 周期源侧 SHEX 输入为 `826.316127343 W`，源热流正向比例 `1`，固体 SMA/SE 最大相对能量残差 `2.3930632603e-4`，由此计算的 heat-driven COP 为 `0.0160159703936`。该 COP 的分母是正向 SHEX source heat input，不是泵功；由于尚未测量 SHEX 下游到流体端的完整转移热流，完整系统一阶能量闭合状态仍为 `incomplete`。

C240 仍不是 Qian Table 4 strict reproduction：`26.2 K` no-load lift 与 `0.64 W/g` zero-lift SCP 尚未形成两个合法成对端点；`ALL_REQUIRED_PASS=0` 表示严格定量 Table 4 条件未满足，不能单独解释为机制失败。C220 之前的三次启动失败证据保留为日志/报告诊断，失败 raw 和不再需要的 dense probe/legacy figures 已按 storage audit 删除。

新增恢复合同：

`gx101r1_R69_remote/verification/source_heatflow_c240_recovery_contract.json`

C240 两个生产 raw 的 SHA-256：

```text
physical_simscape_result.mat  5C9E76BCEEC4445DF80658CC46D22FD8DB07F2A4B97B460DD30AE8D35786E134
final_operating_point.mat     75673FD6EAA636408DF08861419108B8DA05E73B9F0C261A780EB49BFDA25ACA
```

生产复核命令：

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(pwd); addpath(fullfile(pwd,'verification')); a=Audit_HeatDriveECC_SourceHeatFlowResult('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_source_heatflow_steady_from_c220_20260831/qian2019_table2_table4_simscape_240cycle_20260901_001301/physical_simscape_result.mat'); assert(a.production_pass==1); disp(a);"
```

当前仍未完成：完整 SHEX 下游热流测量与一阶系统闭合、两个合法 Table 4 paired roots、endpoint-capacity strict pair、独立 validation 和论文数据声明。论文表述继续限定为 `simulated`、`predicted`、`benchmark-consistent`、`not yet reproduced`。
