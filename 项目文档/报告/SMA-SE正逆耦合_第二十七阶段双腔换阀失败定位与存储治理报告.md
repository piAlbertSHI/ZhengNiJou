# SMA-SE 正逆耦合：第二十七阶段双腔换阀失败定位与存储治理

日期：2026-09-07。本阶段是主目标的失败诊断与适用域验证，不是完成整机复现。

## 1. 审核结论

第二十六阶段单腔有限阻力通过，不能推广到生产公共双泵腔。本轮读取生产构建器、实际构建后的阀/压差源参数，建立双腔、压差源和四个复制路线阀的独立台架。

第一次 12 项完整运行缺少预期冷热激励，并且守恒组能量库存门禁失败。修正供回液边界后，12 项独立失败矩阵全部在 0.5 s 换阀事件触发 V3 出口温度下限断言。原生/守恒腔、是否加入泵功、局部 BE 1/0.5/0.25 ms 均未消除该失败。

失败末样本 V3 出口温度为 `49.81618181026903–53.851799808417184 K`，远低于水表 `273.16 K` 下限。它们是被拒绝的求解器样本，不是收敛物理解，不得据此报告制冷性能、COP、端点库存通过或恢复 OP。

所有生产模型代码、冻结 C200、现存生产/诊断 OP 均未被此台架替换或加载。主目标、完整系统一阶闭合、内部周期稳态、paired Table 4 均未完成。

## 2. 生产结构核查

实际源码和构建结果显示：入口腔外侧接 V1/V2，另一侧接 SMA 压差源；出口腔接压差源下游和 V3/V4。不存在上阶段单腔流量源测试中的相同状态约束。

- `Integrate_HeatDriveECC_Constitutive21_Interface.m` 的 `configure_sma_valve_manifolds`：上述端口连接与两个腔体库存。
- `Build_HeatDriveECC_EighthRound_Simulink_Model.m` 的 `audit_sma_pump_manifold_volumes`：阀、腔、传感器连接、容积和绝热 H 端核查。
- 同文件 `configure_pressure_source_fluid_energy`：已有 `none/isentropic` 显式合同。本轮读取的生产配置为 `none`，不是新发现的无条件程序错误；不能悄悄改成 isentropic 后沿用原 COP 边界。
- 复制阀采用 Cv 参数化、线性开启特性，Cv_max=1，Re_c=150，smoothing_factor=0.01；Cv_min 分别引用源选择阀和路线阀的原工作区变量。物理输入名为 L，压差源输入名为 P。

完整 mask 字符串保存在各 `dual_switch_result.json` 的 `source_valve_parameters` 和 `source_pressure_parameters`。诊断使用生产相同水表和腔容积，但没有复制整套 SHEX/HHEX/床体热路径，因此不能将本台架失败直接认定为现存生产循环同样失败。

## 3. 实际运行记录

| 输出目录后缀 | 执行提交 | 真实运行与结果 |
|---|---|---|
| `dual_chamber_switch_20260907` | `8df1cbf94eaabd405e87cbef75397262cf570cfd` | 12 例完成至 1 s，MATLAB 退出 0；但热激励不足、能量库存门禁失败 |
| `_v2` | `f6748966c86dd53cd960d507fdfa6ca439b536bb` | 分开供/回液，第一例在 0.5 s 断言退出 1，完整工况 0 |
| `_v3` | `627814d` | 不改物理参数，增加 CaptureErrors，捕获第一例全部原始叶节点后退出 1 |
| `_v4` | `390a734598c991467e09ef5a8a29a73353995190` | 独立失败矩阵，12 次尝试均在 0.5 s 失败，完整工况 0，最终退出 1 |

每个 MATLAB 只在前台启动一次并等待其真实 session 自然结束；没有定时等待器、heartbeat 或健康程序中止。矩阵各例在新建台架的配对初值开始，未使用任何前例的失败状态。

台架参数：两腔各 `1.6084954386379741e-6 m³`，初始 340 K、2.5 MPa；冷热供应 380/300 K，各边界 2.5 MPa。压差命令在 0.01 s 从 0 变为 260 Pa，0.5 s V1/V3 从 1 变 0、V2/V4 从 0 变 1。每档局部 BE 与全局 ode3 步长相同。260 Pa 是诊断干预，不是拟合 Qian 的生产压差。

## 4. 第一批为什么不能作为通过证据

第一批每一路只有一个 TL 单口储库，同时接供液和回液阀。即使阀内有约 `0.008572 kg/s` 流量，储库净流量近零，主要形成节点内部回流，不等价于独立热源供液。两腔温度只有约 `339.999842–340.001141 K` 的变化，不能说已测过冷热循环。

本批原生/守恒各六例，分别覆盖两个泵功模式和三档步长，总计十二例。守恒组六例全部时刻最大质量残差 `4.899e-18 kg`，但能量残差最高 `1.183304e-6 J`，超过原门禁 `1e-8 J`。空间端口与泵模式公式通过，不替代能量库存或热激励通过。

修正为独立热供液、热回液、冷供液、冷回液四个无限边界，消除同口回流的热激励错误；旧拓扑仍可通过函数第三参数 false 重建，原始失败摘要和代表性数据未抹去。

## 5. 失败矩阵定位

四边界的实际轨迹已出现有效升温：第一例断言前入口腔最高约 377.20 K，出口腔约 369.80 K。换阀最后样本 V3 A 温度约 364.82 K、B 温度约 49.83 K，B 压力仍为 2.5 MPa；V3 流量从约 8.6 g/s 变为负的微小值。

这将问题定位到冷热供液已生效时的近关阀、流向切换和代数端口温度处理，不是整腔温度降到 50 K。十二项矩阵证明在本台架下仅缩小时间步、更换守恒库存腔、增加泵功都不能单独解决。

本轮还读取安装的 `foundation/thermal_liquid/port_convection.ssc`，确认原生端口能流使用包含热传导平滑的迎风格式，近零流量不能简单使用 `Phi/mdot` 当比焓来反推温度。但阀主体包含受保护实现；本轮没有解密，也未直接观测编译状态消元。具体非线性求解根因尚未证明，不能把上述定位写成完整修复结论。

失败输出获取使用项目已有 `SimulationInput` 与 `CaptureErrors='on'` 模式。该设置允许取得错误信息及错误发生前的输出，不使失败仿真变为成功。参考：[MathWorks sim 文档](https://www.mathworks.com/help/simulink/slref/sim.html)。

## 6. 新图及代码

[Fig15 原图](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_chamber_switch_20260907_v4/Fig15_valve_switch_domain_failure.png)

- (a) 上图显示第一例换阀前的腔体和阀口温度，以及单独标记的失败末样本；下限线为 273.16 K。没有把无效点与有效轨迹相连来伪造物理冷却过程。出口腔与阀口正常段温度近重合。
- (b) 下图放大最后 5 ms 的 V3 流量，单独标出失败末样本的符号变化。它用于定位断言事件，不是有效换阀响应曲线。

图已目视检查，1760×1540 PNG，温度和流量分轴、单位清晰，失败点与正常记录区分；不宣称这是最终发表图或整机性能图。

新增源码：`Audit_HeatDriveECC_DualChamberSwitch.m`、`Audit_HeatDriveECC_DualChamberSwitchResult.py`、`Audit_HeatDriveECC_DualSwitchFailureMatrix.py`、`Plot_HeatDriveECC_DualSwitchFailure.py`、`Audit_HeatDriveECC_DualSwitchPackage.ps1`、`test_dual_chamber_switch.py`。共享单位转换器仅新增显式 `1 -> 1`，仍拒绝 `1 -> K`。首次离线审核因该单位未注册退出，修复后没有重跑仿真。

119 项 Python 测试通过，包括分支端口求和、泄漏检出、量纲拒绝、失败末样本保留且不得标成有效状态。一个新测试的整型 fixture 不能加入浮点扰动，已改为浮点 fixture；不是物理模型改动。

## 7. 存储与结果包

淘汰的单口储库批次保留原始 case_1、case_7、case_10，分别代表原生 none、守恒 none、守恒 isentropic。全部十二例的合同、全部 SI 信号首/末/范围、原始哈希、大小和完整原审核保留。

经绝对路径、文件大小和 SHA-256 逐项核对，删除其余九个 MAT，释放 **11872035 bytes**。删除审计在 `dual_chamber_switch_20260907/retirement_audit.json`。因此旧批次不能直接重新扫描所有 raw；需要完整旧原始轨迹时应按记录提交重建台架，不能声称已保留其全部数据。

当前关键 `_v4` 十二个失败原始轨迹全部保留，每例原生 138/守恒 142 条叶节点信号，分别 501/1001/2001 样本；失败末点保留且被明确拒绝。没有复制生产大 MAT，没有删除 C200、C180、C181 或新失败矩阵数据。

发布目录为 `gx101r1_R69_remote/outputs_storage_audit/dual_switch_release_20260907`。`result_manifest.csv` 给必要证据哈希和字节；`workspace_storage_snapshot.json` 给本轮完整工作区实测与新增/删除量；`release.json` 明确科学切换门禁 false。完整性通过不等于物理门禁通过。

完整代码使用 Stage17 `tl_inventory_release_20260906/source_snapshot.zip` 加本轮 `source_delta.patch`，后者直接相对 Stage17 基线，不能叠加前几轮 patch。源码最终提交在 release.json；基线 ZIP SHA-256 为 `CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。

## 8. 验证命令

```powershell
$r = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
python -m unittest discover -s "$r/verification" -p 'test_*.py'
& "$r/verification/Audit_HeatDriveECC_DualSwitchPackage.ps1"
python "$r/verification/Audit_HeatDriveECC_DualSwitchFailureMatrix.py" --repo $r --output "$env:TEMP/dual_switch_independent_audit.json"
```

输出文件须未存在；独立失败审核不需要 MATLAB，也不需要已删除的旧批次 raw。不要传 `--retirement-summary`，该可选参数仅用于删除前生成旧批次完整摘要。

重跑当前失败矩阵：MATLAB R2025b 加 Simulink/Simscape Fluids，干净代码树，未存在的输出目录，先进入 repo 并 `addpath('verification')`：

```matlab
Audit_HeatDriveECC_DualChamberSwitch( ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_switch_user_review/trial', ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/segment_physical.mat', ...
    true, true);
```

预期是收集十二个失败后返回非零退出，不应为了让命令退出 0 而关闭断言。默认第四参数 false 在第一个失败后停下；第三参数 false 重建已淘汰的同口储库台架。

## 9. 与 Qian 的边界及下一步

本阶段没有新增 Qian 性能点，不能叫复现。文献位置沿用第二十三/二十六阶段明确定位：Qian 2019 DOI `10.1016/j.energy.2019.06.094`，PDF 3–6 页、Fig.1、Table 2、Eq.9/10；Qian 2015 DOI `10.1016/j.ijrefrig.2015.04.001`，PDF 7–9 页、Fig.6、Eq.28–30。本轮台架无限供回液边界不是对文献有限水箱/换热器的替换主张。

下一步需对同一失败拓扑做有界的切换处理诊断：比较硬切换与有限阀动作时间，检查近零流量时的端口能流和平滑迎风约束，同时保留本轮硬切换基线。若仅平滑命令通过，仍需声明新增动作时间及其物理依据，不能偷偷修改 Qian 瞬时切换假设或直接推广到生产。

随后才检查双腔独立库存与外部账本、生产真实热路径/状态约束以及完整状态兼容。当前不得从失败样本续算，不得为拟合 Table 4 启动无保护降温/outer solve，不得把组件或包审核替代整机稳态、成对边界和共同参数合同。
