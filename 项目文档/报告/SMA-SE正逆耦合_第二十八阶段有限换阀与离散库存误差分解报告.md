# SMA-SE 第二十八阶段：有限换阀与离散库存误差分解

日期：2026-09-07。状态：诊断推进，完整主目标未完成。C200 仍为唯一冻结主线参考；本阶段没有加载、修改或传播生产 Operating Point。

## 1. 给负责人的结论

本阶段不是又一次“等待”。已经运行三组真实 MATLAB/Simscape 双腔换阀台架，每组十二例，共三十六例均计算至 1 s 并自然退出 0。有限 10 ms 阀动作避免了本诊断台架的温度下限断言，但不能据此改判原瞬时换阀失败。

收紧非线性求解容差后，全部空间端口恒等式通过，库存门禁仍失败。进一步用原始温度、压力和实际物性表复算，六个守恒工况的十二个腔体均符合温度/压力坐标下的 BE 链式离散；该离散不等同于直接对端点质量、内能库存作 BE 更新。这是对误差的可重复解释，不是将残差扣除后宣布守恒。

本轮没有增加有效生产周期、稳态性能点或 Table 4 对比端点。完整一阶能量闭合、合法主线恢复、受门禁保护的 outer solve 和成对文献边界仍未完成。

## 2. 本轮具体修改

源码均在 `C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/verification`。

| 文件 | 修改及用途 |
|---|---|
| `Audit_HeatDriveECC_DualChamberSwitch.m` | 显式 10 ms Ramp/Saturation 阀命令；可选 Projection 和严格求解容差；记录实际 solver 参数、四独立供回液边界及所有阀口 T/p；旧默认硬切换仍可重建 |
| `Audit_HeatDriveECC_DualChamberSwitchResult.py` | 同时审核原生库存和独立物性表重建库存；保留旧物性恒等式门禁；增加实际命令、域和热激励审核 |
| `Audit_HeatDriveECC_DualChamberRampResult.py` | 三组执行提交和输入哈希固定；严格区分完成计算、空间恒等式和库存闭合 |
| `Audit_HeatDriveECC_DualChamberCoordinates.py` | 对每个区间计算精确双线性表梯度、TP 链式增量及端点差额；不删除表节点跨越区间 |
| `Plot_HeatDriveECC_DualChamberRamp.py` | 新 Fig16 的实际阀动作、温度、步长残差和库存差额分解；PNG/PDF |
| `Audit_HeatDriveECC_DualRampPackage.ps1` | 父包校验、输入/结果哈希、源码增量、回归测试、存储审计及声明边界检查 |
| `test_dual_chamber_ramp.py`、`test_dual_coordinates.py` | 命令与物性门禁、独立回液泄漏检出、坐标梯度/跨区间差额、域拒绝和未计热量检出 |

生产构建器和守恒 SSC 原型本轮没有物理修改。台架只从 C181 的 `segment_physical.mat` 读取 options，不加载其失败恢复状态。每例从新建台架的配对初值开始，绝非复位生产长链。

## 3. 实际运行合同

两腔各 `1.6084954386379741e-6 m³`；初始 340 K、2.5 MPa；四个独立无限供回液储库，热 380 K、冷 300 K，均为 2.5 MPa。压差源在 0.01 s 从 0 跳为 260 Pa。V1/V3 在 0.5–0.51 s 线性关闭，V2/V4 同时线性打开。泵命令仍是瞬时阶跃。

每组原生/守恒两种腔、none/isentropic 两种泵功模式、1/0.5/0.25 ms 三档局部 BE 步长，合计十二例；全局 ode3 步长与局部相同。每组记录 948 条标量时间序列。三组均完成至 1 s、退出 0；没有关闭物性断言或中止健康 MATLAB。

输出目录公共前缀为 `C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/`：

| 子目录 | 执行 Git 提交 | 唯一比较干预 |
|---|---|---|
| `dual_chamber_ramp_20260907` | `702165653bdd80795599675290dc2b770dc25af6` | 四边界硬切换改为显式 10 ms 阀动作 |
| `dual_chamber_projection_20260907` | `1371d3a3b5b7587b310337b9e97a86b668541b8d` | 上述有限动作，IndexReductionMethod 改为 Projection |
| `dual_chamber_tight_20260907` | `276a9add8f02a6188f8a0657d1d53a7a5577aea5` | 有限动作，保持 DerivativeReplacement，收紧求解容差 |

实际复制的生产 Solver Configuration 使用 `ResidualTolerance=0.001`、`ConsistencyTolSource=GLOBAL`，不是库块默认值的推测。严格组设 `ResidualTolerance=1e-12`、`ConsistencyTolSource=LOCAL`、`ConsistencyAbsTol=ConsistencyRelTol=1e-12`。所有值写入实际工况合同；这些求解容差与物理库存门禁是不同量。

## 4. 严格审核结果

库存原门禁保持质量 `1e-15 kg`、能量 `1e-8 J`。下表取每组六个守恒工况、各局部/重建/总账本的全部时刻最大绝对残差，不只看最终值。

| 比较组 | 完成数 | 质量残差上界 kg | 能量残差上界 J | 全部空间端口恒等式 | 守恒库存闭合 |
|---|---:|---:|---:|---|---|
| 原容差，有限动作 | 12/12 | 1.1565724e-7 | 0.135908688 | 未全部通过 | 六例均失败 |
| Projection | 12/12 | 1.1955200e-7 | 0.091167201 | 未全部通过 | 六例均失败 |
| 严格容差 | 12/12 | 1.0235709e-7 | 0.134279168 | 全部通过 | 六例均失败 |

三组泵模式公式、实际阀命令和热激励检查全部通过。阀口最低温分别约 299.999842、299.999842、300.000000 K，均高于 273.16 K 下限。这里只说明有限动作台架未触发旧断言，原硬切换失败仍保留。

原容差、守恒 none 的能量总账残差随 1/0.5/0.25 ms 减小至约 0.135905/0.070304/0.035470 J。误差随步长减小不等于达到 `1e-8 J`；不能把趋向改善写成门禁通过。Projection 或严格容差单独也没有解决库存守恒。

首次离线审核在 0.501 s 发现原生 rho/u 与独立物性表重建不一致而退出；原容差第一例入口密度差约 `-1.8239e-8 kg/m³`、比内能差 `-1.6722e-4 J/kg`。修改为保留原 `1e-8 kg/m³` 与 `1e-6 J/kg` 阈值的逐项失败结果，并继续计算独立账本，没有放宽门禁。后续一次 JSON 输出因 NumPy 布尔类型失败，改为显式 Python bool；两次离线问题均未触发 MATLAB 重跑。诊断记录见 `property_gate_diagnosis.json` 与相关源码提交。

## 5. 库存差额为什么产生

令 `x=(T,p)`，实际表插值为 `rho(x)` 和 `u(x)`，腔体体积 V 固定。分别比较：

```text
端点物理质量增量 = V*rho(x[n]) - V*rho(x[n-1])
TP 坐标质量增量  = V*grad(rho)[n] dot (x[n]-x[n-1])
端点物理内能增量 = V*rho(x[n])*u(x[n]) - V*rho(x[n-1])*u(x[n-1])
TP 坐标内能增量  = V*(u*grad(rho)+rho*grad(u))[n] dot (x[n]-x[n-1])
```

每个右端点的坐标增量与实际 `dt*(mdot_A+mdot_B)`、`dt*(Phi_A+Phi_B+Q_H)` 对照。梯度来自冻结的实际双线性物性表单元，既保留单元内非线性乘积，也保留跨表单元的所有区间。

严格容差组六个守恒工况、十二个腔体的最大单区间不一致仅 `7.1971331e-20 kg`、`3.6270986e-13 J`；累计能量解释误差最高 `1.3302415e-11 J`。因此观察到的轨迹与 TP 链式 BE 高度一致，而非端点库存 BE。

例如严格容差、none、1 ms 的入口腔，端点与坐标累计差 `0.097697035028 J`，其中单元内 `0.082119305750 J`、跨单元 `0.015577729278 J`。实际未修正物理残差为 `0.097697035029 J`。出口腔相应约 `0.03657889378 J`。将诊断差额从残差中扣除会掩盖库存问题，本项目没有这样做。

尚未直接读取编译器最终选定的状态列表；报告只声明观测到的方程一致性。连续方程写成 `der(M)`、`der(U)` 并不自动证明该受代数压力约束网络的有限步端点守恒。对状态选择和高指标系统的文档参考：[MathWorks Solver Configuration](https://www.mathworks.com/help/simscape/ref/solverconfiguration.html)，不能用文档替代本模型状态的直接证据。

## 6. Fig16 逐图解释与图审

[Fig16 PNG](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_chamber_tight_20260907/Fig16_finite_actuation_inventory_v2.png)；[矢量 PDF](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_chamber_tight_20260907/Fig16_finite_actuation_inventory_v2.pdf)。

- (a) 放大实际 10 ms 热路线关闭、冷路线打开。它展示新增动作时间，不暗示文献规定该时间。
- (b) 严格组守恒 none、1 ms 的两腔与 V3 出口温度；升温再降温证明真实热激励，端口不等于腔内温度，近关闭支路可能继续保持不同温度。阀口起始代数调整也完整保留。
- (c) 守恒 none 三档步长的三种求解设置，纵轴为全时刻、全部账本最大能量残差。对数坐标同时显示真实误差与未变门禁，原容差/严格容差曲线接近而重叠，不是遗漏了一组数据。
- (d) 同一严格 1 ms 工况的入口/出口端点差额，分别显示单元内和跨单元贡献，黑色短线为原物理残差。两者吻合是误差解释，不是通过证据。

已目视审核 2640×1920 PNG，物理量分面板、单位明确、无双纵轴。首次下限线与图例重叠，调整后重新查看；旧 PNG/PDF 删除并记录哈希，释放 351842 bytes。图属于数值诊断图，不声称达到最终 SCI 发表审核，更不替代整机性能图。

## 7. 存储、结果包与 Git

本轮生产 outputs 的清理 dry-run 为 `candidate_count=0`，实测约 `16.878 GiB`；该值不是整个工作区大小。整个工作区、Git 对象及本轮新增证据的字节数在结果包 `workspace_storage_snapshot.json` 重新实测。此前约 120 GB 的旧占用不能作为当前值，也不能将此前累计释放量说成本轮删除量。

本轮只删除 351842-byte 绘图草稿，不删除生产 raw。保留三组各十二个原始 MAT、实际工况合同、构建组件、日志和失败审核，因为它们是区分求解容差、降指标方法与物理库存误差的独立对照，不是重复备份。旧硬切换失败矩阵与原物性恒等式失败记录保留。C200、C180、C181 及受已有合同引用的大证据不动，结果包不复制 GiB 生产 MAT。

新结果包目录：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_ramp_release_20260907`。`result_manifest.csv` 给逐文件 SHA-256/大小；`release.json` 明确完整性与科学门禁分离。完整代码使用 Stage17 `tl_inventory_release_20260906/source_snapshot.zip` 加新包的 **直接相对 Stage17 基线** `source_delta.patch`，不能叠加前阶段补丁。最终源码提交由 `release.json` 给出。

基线 ZIP SHA-256：`CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。三组独立离线复算及坐标解释已重复执行，输出与冻结 JSON 的 SHA-256 完全相同；126 项 Python 回归测试通过。

| 审核文件 | SHA-256 |
|---|---|
| `ramp_audit_v1.json` | `8A64AB6BE52DA9CD580B46F591C0C8D7527317744FE4E00C6E825F4A1A5E4E11` |
| `projection_audit_v1.json` | `76F71873EC88B66609251810FA9CB3EE3B9C6D837F6A0D890578AAF607260D2F` |
| `tight_audit_v1.json` | `EBA2D586145159A89121C3B15D6FF39535F684906A417349375D2FBBEDFFAF40` |
| `coordinate_diagnosis_v1.json` | `0DD03A573EBF77DA215598739C50A32DBBCD23D7B5E4D65A31061D23DE046D29` |

## 8. 负责人如何验证

以下命令不启动生产仿真。需要 PowerShell 7、Python 及 numpy/scipy/h5py；绘图另需 matplotlib。离线审核输出必须尚不存在，独立文件名采用随机后缀；原结果不会被覆盖。

```powershell
$r = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
python -m unittest discover -s "$r/verification" -p 'test_*.py'
& "$r/verification/Audit_HeatDriveECC_DualRampPackage.ps1"
$tag = [guid]::NewGuid().ToString('N')
python "$r/verification/Audit_HeatDriveECC_DualChamberRampResult.py" --repo $r --output "$env:TEMP/ramp_$tag.json"
python "$r/verification/Audit_HeatDriveECC_DualChamberRampResult.py" --repo $r --projection --output "$env:TEMP/projection_$tag.json"
python "$r/verification/Audit_HeatDriveECC_DualChamberRampResult.py" --repo $r --tight --output "$env:TEMP/tight_$tag.json"
python "$r/verification/Audit_HeatDriveECC_DualChamberCoordinates.py" --repo $r --output "$env:TEMP/coordinates_$tag.json"
```

预期包完整性 true，但 `scientific_inventory_gate_pass=false`；预期坐标解释 true，但 `physical_inventory_gate_pass=false`。不能只检查命令退出码。原始数据保留在三个目录的 `trial/case_1.mat` 至 `case_12.mat`。

需重新做真实严格组实验时，在 MATLAB R2025b（Simulink/Simscape Fluids）进入 repo、`addpath('verification')`、干净代码树，使用全新目录：

```matlab
Audit_HeatDriveECC_DualChamberSwitch( ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_tight_user_review/trial', ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/segment_physical.mat', ...
    true, true, .01, 'DerivativeReplacement', 1e-12);
```

函数记录实际执行提交；上述新运行不应覆盖冻结目录。固定历史提交的审核器会拒绝不一致合同，这是预期保护。若要逐字重现历史执行，应从表中相应提交取得代码；新提交的实验需另立合同，不能手改旧哈希蒙混通过。

## 9. Qian 对照位置与适用边界

| 文献和本地位置 | 对照内容 | 本阶段结论 |
|---|---|---|
| Qian 2019，DOI `10.1016/j.energy.2019.06.094`；`C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A heat driven elastocaloric cooling system..pdf`；PDF 3–6 页、Fig.1、Table 2、Eq.9/10 | 系统热路径、参数、温跨与 SCP 定义；文中 1 ms ODE3 | 不能将 1 ms ODE3 等同于当前 Simscape 局部 BE；本次无新增性能复现点 |
| Qian 2015，DOI `10.1016/j.ijrefrig.2015.04.001`；同文件夹 `（3）Thermodynamics cycle analysis and numerical modeling of thermoelastic cooling systems.pdf`；PDF 7–9 页、Fig.6、Eq.28–30 | 水箱、管路能量方程、热容因子及瞬时阀/泵假设 | 文献确有水箱；本台架四无限储库不是其有限水箱。10 ms 动作是诊断新增参数，非文献输入；机械 COP 不能替代热输入 COP |

两 PDF 哈希分别为 `2D0EB5F84AA515BA651638974414D426A3806FD417A1EAD96EFA36EDA08034CC`、`DA6F22848081C74460A6732F7BAE7749D6C05DB5D2F695538C248EA5C9D28CD7`。本轮是延续已有文献定位，不宣称新读完更多 Qian 论文或完成实验验证。

## 10. 下一步主线与停止条件

1. 针对双腔理想压差代数约束建立可观测状态/独立离散库存试验，验证是否能够同时满足压力关系和端点 M/U 更新。先保持原物性表、明确端口通量，不能只继续缩步或收紧容差。
2. 如需引入实际惯性、顺应性或有限阀动作时间，先给物理或文献依据并区分诊断/生产合同，不得为数值通过任意添加状态或更改 Qian 假设。继续保留原硬切换失败。
3. 新组件必须跨密闭、定压通流、有限阻力、双腔热切换和非零泵功测试，通过原库存门禁后才考虑生产集成；完整状态恢复兼容另行验证，不能把旧 OP 直接装进结构改变的模型。
4. 整机必须完成全控制体库存、外部热流、泵功与全部内部状态周期门禁，再进行固定 Tc outer solve、正交敏感性和成对 zero-load/zero-lift 边界。失败点不得进入插值或恢复链。
5. 最后再制作正式 SMA-SE 温度/相变/回热/流量/泵功/SCP/COP 图组与 Table 4 严格报告。当前仅可称 simulated diagnostic；不能称 reproduced、experimentally validated 或完整整机能量闭合已完成。

长任务纪律按最新 AGENTS：真实程序前台只启动一次，等待同一 session/PID 自然退出后读取退出码和结果；不用历史 30 分钟定时器或 heartbeat，也不要求用户先清除 Goal。
