# SMA-SE 正逆耦合：第二十六阶段有限阻力通流与泵功库存审核

日期：2026-09-07。范围：独立组件诊断，不是生产循环、Table 4 复现或实验验证。

## 1. 结论与边界

真实 MATLAB/Simscape 完成 18 项配对试验，执行提交 `9027cb3de2b66d78024093f586db38a4452dee60`，自然退出码 0。原生腔/守恒库存腔各 9 项，均包含正流、反流、换向及 1/0.5/0.25 ms 局部 BE 步长。

有限出口阻力条件下，守恒组件 9/9 通过不变的质量、内能库存门禁：全部时刻最大质量残差 `5.340966248911991e-18 kg`，最大能量残差 `1.879385536085465e-12 J`。18 项空间端口恒等式、非零泵压头与独立泵功公式核算均通过。

第二十五阶段的刚性定压通流失败仍然有效，本轮没有将其改判、删去或替换。本轮说明通过情况依赖连接边界；尚未直接观测编译后的独立状态选择，也没有证明全 SMA-SE 网络适用。生产恢复、完整系统一阶闭合、Table 4 复现三项声明仍为 false，主目标未完成。

## 2. 本轮实际修改

- `verification/Audit_HeatDriveECC_ChamberOpenFlow.m`：新增可选出口节流面积参数。默认零值保持旧四角色台架；正值创建独立有限阻力台架，记录第五角色及泵端密度。使用新 schema，避免新旧拓扑混淆。
- `verification/Audit_HeatDriveECC_ChamberOpenFlowResult.py`：读取器增加显式 `restricted=True` 分支。旧定压审核仍使用原默认合同，不接受新增端口角色。
- `verification/Audit_HeatDriveECC_ChamberRestrictedFlow.py`：新增独立外部端口、局部库存、泵功及原始物性哈希审核；无扣除误差、无事件区间裁剪。
- `verification/test_chamber_restricted_flow.py`：检查五角色读取合同、错误模式拒绝、正反向泵功符号、非有限密度、节流件内部泄漏。全套 116 项 Python 测试通过。
- `verification/Plot_HeatDriveECC_ChamberRestrictedFlow.py`：四分面图，压力、泵功、质量误差、能量误差分开表达。
- `verification/Audit_HeatDriveECC_RestrictedFlowPackage.ps1`：结果哈希、旧失败包、代码增量包和存储快照审核；明确组件门禁与整机结论不同。

生产构建器和守恒 SSC 方程未改，未加载任何 OP，未重置生产热容、buffer、PI、本构、温度或相分数。仿真只从 C181 `segment_physical.mat` 读取 options。

## 3. 可复核的台架合同

拓扑：HotReservoir A → FlowSource A/B → Chamber A/B → OutletRestriction A/B → ColdReservoir A。Chamber H 绝热；FluidSettings、Solver 接 Chamber A。

| 项目 | 本轮值 |
|---|---|
| 两无限储库压力 | 均为 2.5 MPa |
| 热/冷储库温度 | 380 / 300 K |
| 腔初始状态 | 340 K、2.5 MPa，覆盖开关开启且实际首样本核对 |
| 腔体积 | 1.6084954386379741e-6 m³ |
| 管端口面积 | 8.04247719318987e-6 m² |
| 固定出口节流面积 | 2e-8 m² |
| Cd / 临界 Re / 压力恢复 | 0.64 / 150 / true |
| 流量 | ±0.0002 kg/s；换向工况 0.5 s 由正变负 |
| 每例时间 | 0–1 s；保留初始样本及全部事件区间 |
| 求解器 | 局部 Backward Euler、全局 ode3；两者同档步长 |

节流面积是用于解除刚性定压约束的诊断干预，不是 Qian 参数、拟合值或生产改动。水表保持 C181 实际表合同，T 范围 273.16–413.16 K、p 范围 0.45–5 MPa。

## 4. 账本与门禁

端点库存由原始记录独立重算：`M = rho*V`，`U = rho*V*u`。

局部流入：`mdot_A+mdot_B`；局部热功输入：`Phi_A+Phi_B+Q_H`。

外部流入：`-mdot_hot-mdot_cold`；外部能量输入：`-Phi_hot-Phi_cold+source_power`。节流件不积累库存，两端质量和能量流分别相消。泵的两端能流加测量功率相消，不将泵功重复加入局部账本。

每一个原始区间使用右端点 BE 通量乘以实际 dt；对全部时刻累计和逐区间差额计算残差。累计最大绝对质量门禁 `1e-15 kg`，能量门禁 `1e-8 J`，没有放宽。初始/换向区间均纳入。

泵功另用实际端密度与压力核对：`mdot_A*(p_B-p_A)/((rho_A+rho_B)/2)`。最大公式误差约 `1.284e-16 W`。这是实际记录的非零功率核算，不是把零压头恒等式当成泵功验证。

## 5. 定量结果

下表为同一模式三档步长中的全时刻最大残差；完整逐例结果在 `restricted_flow_audit_v1.json`。

| 模式 | 原生质量 kg | 守恒质量 kg | 原生内能 J | 守恒内能 J |
|---|---:|---:|---:|---:|
| 正流 | 9.28944e-8 | 5.34097e-18 | 1.52290e-2 | 1.49569e-12 |
| 反流 | 3.49471e-8 | 4.66461e-18 | 1.06499e-2 | 1.14753e-12 |
| 换向 | 6.49676e-8 | 4.43824e-18 | 1.02648e-2 | 1.87939e-12 |

守恒组压力范围约 2.371678–2.630071 MPa，温度范围约 335.153822–344.794156 K。最大泵功约 0.0272580 W；1 ms 换向例积分泵功 0.0266040582 J。原生组库存门禁仍失败，减小时间步并未使其残差降到门禁内。

这些结果与前轮定压失败构成受控边界对照。它们支持继续检查代数约束/离散状态处理，但不能仅凭结果宣称已直接读出编译器的状态消元，更不能把有限阻力测试当成刚性定压测试的修复。

## 6. Fig14 逐分面解释与审核

[Fig14 原图](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/chamber_restricted_flow_20260907_v2/Fig14_restricted_flow_inventory_v2.png)

- (a) 守恒组件、1 ms 换向例的测量压力。储库保持 2.5 MPa，腔压随流向改变，证明本轮不再把腔压直接钉死在储库值。
- (b) 同例实际泵功率，约 27/26 mW，换向期间有瞬态；此功率已进入外部能量账本。图不是经验泵效率模型。
- (c) 每档时间步取三种模式的全时刻最大质量残差。原生有限阻力、旧守恒定压失败、新守恒有限阻力分别显示，点线是原门禁。
- (d) 以相同方式独立显示能量残差。新组通过并不遮盖旧组失败；对数坐标便于跨数量级比较，不代表相对误差。

2420×1672 PNG 已实际目视审核。初稿图例穿过能量门禁线，已改为独立共用图例区；轴名、单位、门禁和曲线无重叠。删去旧草稿 232406 bytes，保留哈希/原因。此图为组件诊断图，不冒称最终论文 SCI 图集或与文献完全同等验证等级。

## 7. 失败、修复与执行纪律

1. `3ddbcfe` 在仿真前被 checkcode 两项 AGROW 拦截，退出 1，真实仿真 0 项。独立只读诊断定位到源变量名拼接和第五 packet 追加。
2. `9027cb3` 改为完整字面量和预分配，checkcode 空结果；在新目录单次前台程序完成全部 18 项，退出 0。
3. 首次 Python 审核因将 SSC 布尔 `true` 错当为 Simulink `on` 字符串而拒绝合同。实际记录与安装源文件均为 true；修复为精确要求 true，未修改数据或放宽门禁，没有重跑 MATLAB。

两次失败的日志/诊断保留，未传播任何失败状态。整个等待使用真实程序 session，自然退出后读取退出码，不创建定时器、heartbeat 或轮询监视器。

## 8. 文献对照的实际范围

本轮没有新增 Qian 性能复现点，也没有把节流件实验当作文献试验。本轮直接核读 R2025b 安装源中的 `flow_rate_source.ssc` 与 `local_restriction.ssc`，用于确认泵功和无库存节流件的能量边界。

此前已核读的 Qian 附件模型定位保持如下，负责人可对照第二十三阶段完整说明：

- [Qian 2019 原文](C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A%20heat%20driven%20elastocaloric%20cooling%20system..pdf)：PDF 3–6 页、Fig.1、Table 2、Eq.9/10 和参考文献 [29]，DOI `10.1016/j.energy.2019.06.094`。
- [Qian 2015 原文](<C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/（3）Thermodynamics cycle analysis and numerical modeling of thermoelastic cooling systems.pdf>)：PDF 7–9 页，Fig.6、Eq.28 水箱、Eq.29/30 管道/壁面热容，DOI `10.1016/j.ijrefrig.2015.04.001`。

Qian 确有水箱，不能称文献没有储液附件。其附件简化能量模型与当前 TL 可压缩腔/单口 Tank 并不自动等价；文献的 1 ms ode3 也不等于本模型局部 BE。该差异仍需模型层级与状态边界审核，而不是借本轮通过跳过。

## 9. 完整代码、数据与验证入口

工作区：`C:/Users/86182/Desktop/正逆耦合`；以下命令在 PowerShell 执行。

```powershell
$w = 'C:/Users/86182/Desktop/正逆耦合'
$r = "$w/gx101r1_R69_remote"
python -m unittest discover -s "$r/verification" -p 'test_*.py'
& "$r/verification/Audit_HeatDriveECC_RestrictedFlowPackage.ps1"
```

独立重新计算现有原始数据，不需要启动 MATLAB；输出必须是未存在的新文件：

```powershell
python "$r/verification/Audit_HeatDriveECC_ChamberRestrictedFlow.py" --repo $r --trial "$r/outputs_storage_audit/chamber_restricted_flow_20260907_v2/trial" --execution-commit 9027cb3de2b66d78024093f586db38a4452dee60 --output "$env:TEMP/restricted_flow_independent_review.json"
```

真实台架重跑需 MATLAB R2025b、Simulink、Simscape Fluids，代码工作树必须干净，输出目录不得存在。先 `cd($r)`、`addpath('verification')`，再调用：

```matlab
Audit_HeatDriveECC_ChamberOpenFlow( ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/restricted_flow_user_review/trial', ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/segment_physical.mat', 2e-8);
```

新重跑需用新 `open_flow_result.json` 记录的 execution_commit 审核，不应冒用旧执行提交。18 个 `case_*.mat` 是完整小型原始轨迹，522 条标量信号；没有保存庞大的生产历史副本或创建 OP。

本轮发布目录：`gx101r1_R69_remote/outputs_storage_audit/restricted_flow_release_20260907`。`result_manifest.csv` 列全体所需文件、字节与 SHA-256；`release.json` 给最终源码提交；`source_delta.patch` 直接以 Stage17 基础提交为基线。

完整源码重建使用 Stage17 `tl_inventory_release_20260906/source_snapshot.zip` 加本轮 direct-from-base patch，不能叠加前几轮增量。基础 ZIP SHA-256：`CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。正式发布审核会校验父级失败证据包，不重复复制生产 MAT。

## 10. 工作区与 Git 管理

本轮前后实测工作区约 17.9 GiB，已不是早期描述的 120 GB。`Manage_HeatDriveECC_OutputStorage.ps1` dry-run：outputs 约 16.878 GiB，可安全清理旧大结果候选 0；本轮没有再次宣称释放历史约百 GB。完整新快照以发布目录 JSON 为准。

Git pack 约 62.09 MiB，garbage 为 0；无需破坏性历史清理。生产权威 C200、受限 C180、C181 诊断及旧失败核心数据不动。只删已替代的 Fig14 草稿，保存删除前 SHA-256、字节、替代图 SHA-256。新增独立试验原始数据在 MB 量级，保留完整以支持同行复核。

## 11. 下一阶段与仍未完成事项

1. 核查生产公共泵腔的实际连接/压力约束，明确是否存在与本轮不同的状态退化；优先读取公共编译/状态诊断信息，不把当前结果推断当成直接观测。
2. 建立双腔、实际阀换向和有限热交换的独立配对台架，保持相同物性、泵功、局部/外部库存与事件全覆盖门禁。此阶段不得把旧生产 OP 加载进修改后结构。
3. 刚性定压通流失败需要独立解决或形成有证据的组件适用域限制；不得为了通过而任意在生产网络新增阻力。
4. 组件适用域和完整状态兼容核查通过后，才设计可审计的生产迁移/新分支验证；C200 仍是冻结主线基准，失败状态不传播。
5. 全网络质量/第一定律与内部周期稳态未通过前，不启动无保护的固定 Tc outer solve，也不进行参数拟合、paired Table 4 最终复现或整机 COP 声明。

以上仍为正在实施的主目标，不是因一次失败而放弃，也不是以组件通过替代主目标完成。
