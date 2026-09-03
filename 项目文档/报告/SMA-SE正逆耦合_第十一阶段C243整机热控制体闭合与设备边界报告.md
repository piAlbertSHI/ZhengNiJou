# SMA-SE 正逆耦合第十一阶段：C243 整机热控制体闭合与设备边界报告

更新日期：2026-09-04  
代码分支：`codex/coupled-simscape-authority`

## 1. 严格结论

C243 是从 C242 已验证 Operating Point 连续运行一个完整周期得到的新权威恢复点，
没有重置热容、buffer、本构、温度、相分数或独立路线 PI 记忆。C243 同时通过：

1. SMA-SE 四阶段耦合机制门禁；
2. 周期稳态门禁；
3. SHEX、HHEX、CHEX 三个换热节点的直接 KCL 门禁；
4. 全部 Pipe/Tank/Constant Volume Chamber 原生流体能量与质量库存门禁；
5. 包含流体、三端换热器热容及 SMA/SE 显热和潜热的 modeled thermal control
   volume 一阶能量门禁。

因此可以声明“当前模型定义内的整机热控制体闭合通过”。仍不能声明完整设备一阶
能量闭合，因为两个 `Pressure Source (TL)` 采用 `power_spec=none`，计算得到的泵功
没有作为热耗散注入流体，也没有对应的附件散热测量边界。该边界差异是显式保留，
不是用热残差抵消泵功。

C200 仍是唯一论文性能基准；C243 是当前耦合状态恢复与整机热账本权威。Qian
Table 4 两个端点、网格/步长收敛和独立验证尚未完成。

## 2. 权威文件和哈希

### 2.1 C200 论文基准

| 文件 | SHA-256 |
|---|---|
| `physical_simscape_result.mat` | `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` |
| `final_operating_point.mat` | `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816` |

### 2.2 C243 当前恢复与系统能量权威

结果目录：

`gx101r1_R69_remote/outputs/qian_coupled_system_energy_c243_20260904/qian2019_table2_table4_simscape_243cycle_20260904_025423`

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `physical_simscape_result.mat` | `6067366262` | `BEFD79CD744DA356BECF376A968B2FA408E974E25BCCFE7A2AD0776A8AFF7C5D` |
| `final_operating_point.mat` | `3825981` | `7F9EBFA47E578290E7FD7E0D8DED5BB7CB182BDE66A86E3B7E25166F4CAF1B70` |

恢复合同：`verification/system_energy_c243_recovery_contract.json`  
结果审核：`outputs/qian_coupled_system_energy_c243_20260904/system_energy_audit_c243.json`

## 3. C243 周期与性能状态

| 指标 | C243 | 结论 |
|---|---:|---|
| 总周期 | `243` | C242 OP 连续续算 |
| 新增仿真时间 | `2420-2430 s` | 完整 10 s 周期 |
| `mechanism_pass` | `1` | 通过 |
| `periodic_steady_state` | `1` | 通过 |
| endpoint drift | `0.0136228578 K` | 通过 |
| same-phase temperature max drift | `0.220500395 K` | 鲁棒 P99/RMS 门禁通过 |
| same-phase phase drift | `0.0100248223` | 通过 |
| Eq. 9 lift | `28.7102598660 K` | 固定边界预测点 |
| Eq. 10 SCP | `0.316481103505 W/g` | 固定边界预测点 |
| SE phase swing | `0.997839576887` | 机制完整 |
| `ALL_REQUIRED_PASS` | `0` | Table 4 严格端点未完成，不是机制失败 |

## 4. 整机热账本

最终完整周期的边界采用：

`Q_external = Q_SHEX,in + Q_CHEX,fixed + Q_CHEX,load - Q_HHEX,out`

模型内储能采用：

`U_total = U_fluid + U_endpoint + U_SMA + U_SE`

其中本构模块向显热节点注入 `+m*Delta_h*dxM + mechanical`。将潜热源项移到
控制体储能侧后，必须使用 `U_latent = -m*Delta_h*xM`。这次更正只改变审计和
Fig.07 的账本定义，不改变仿真本构、相态或 Operating Point。修正前图中的约
`1.8 kJ` 半周期伪残差已经消除。

### 4.1 换热器节点 KCL

| 项目 | RMS 残差 |
|---|---:|
| SHEX node KCL | `1.72343e-13 W` |
| HHEX node KCL | `3.17649e-11 W` |
| CHEX node KCL | `1.46825e-12 W` |
| CHEX workspace/native 一致性 | `2.00602e-11 W` |

统一门禁为 `1e-6 W`，全部通过。

### 4.2 边界热流

| 项目 | 周期均值 |
|---|---:|
| SHEX 热源输入 | `826.326619400 W` |
| CHEX 固定冷源输入 | `12.9667532214 W` |
| CHEX 声明负载输入 | `5.17e-26 W` |
| HHEX 环境排热 | `836.314668863 W` |
| 外部净热输入 | `2.97870375767 W` |

### 4.3 储能率和残差

| 储能项 | 周期端点变化率 |
|---|---:|
| Pipes | `0.00477904448 W` |
| Buffers | `3.11380963703 W` |
| Manifolds | `0.000497194431 W` |
| 全流体库存 | `3.11908587595 W` |
| 三个换热端热容 | `-0.00105519770 W` |
| SMA+SE 显热与潜热 | `0.000845469327 W` |
| 总模型储能率 | `3.11887614757 W` |
| 一阶热残差 | `-0.140172389903 W` |
| 相对残差 | `1.67607235795e-4` |

相对门禁为 `1e-3`，通过。残差以 SHEX/HHEX 最大边界热流归一化，并不是以较小的
净热输入归一化；报告同时保留绝对值，避免只报相对数掩盖误差。

### 4.4 质量和泵边界

流体起始质量 `0.432296814753 kg`，末值 `0.432298148512 kg`，漂移
`1.33375939e-6 kg`，相对 `3.08528618e-6`。10 ppm 门禁为 `1e-5`，通过；
该阈值比生产 ODE3 相对容差低三个数量级，用于区分毫克级可压缩数值残差与外部
质量边界。

SMA 与 SE 泵功分别为 `11.5842785028 W` 和 `0.258758332645 W`，总计
`11.8430368354 W`；原生 pressure-source power 为 `0 W`。所以：

- `modeled_thermal_closure_pass = true`；
- `complete_device_first_law_closure = false`；
- 当前不能发布完整设备 COP。

## 5. 七张 SCI 图逐图说明

图集目录为 C243 结果目录下的 `figures_sci`，每张均有 600 dpi PNG 和 PDF。

### Fig.01 `Fig01_last_cycle_mechanism`

同一周期轴上展示 SMA/SE 平均温度、换热器边界、两种材料马氏体分数及阶段流量。
负责人应据此核对四阶段切换、相变方向和路线开启是否一致。它证明末周期机制可读，
不单独证明 Table 4。

### Fig.02 `Fig02_last_cycle_axial_fields`

展示 SMA/SE 的 21 节点温度场和相分数场。该图用于观察轴向换热/相变前沿以及局部
滞后，防止平均值掩盖节点异常。

### Fig.03 `Fig03_periodic_convergence`

展示循环端点、漂移、Eq.9 和 Eq.10 SCP 的历史。负责人应结合 validation report
的鲁棒同相位 P99/RMS 门禁判断稳态，不把 `ALL_REQUIRED_PASS=0` 误判为机制失败。

### Fig.04 `Fig04_control_and_energy`

展示压力命令、液压功、本构热率和 SMA/SE 固体局部能量分解。该图中的泵功是附件
功耗诊断，不是已热耦合到流体的边界。

### Fig.05 `Fig05_table4_boundary_audit`

对照 Qian Table 4 的 `26.2 K` zero-load 与 `0.64 W/g` zero-lift 两个端点，并明确
区分 C243 固定 `Tc=276.95 K` 点、拒绝点和线性诊断外推。固定点不能冒充两个端点。

### Fig.06 `Fig06_direct_SHEX_control_volume`

直接显示 SHEX source、sink-to-fluid、sink storage 三支路瞬时和累计关系，证明
SHEX 局部节点闭合，不再依赖 C240 重建。

### Fig.07 `Fig07_modeled_system_energy_ledger`

面板 (a) 比较 SHEX 输入、CHEX 冷源输入和 HHEX 排热；(b) 比较累计外部净输入、
总储能和残差；(c) 分项显示 pipe/buffer/manifold/HX mass/SMA+SE 储能率；(d) 同时
显示三个换热节点 KCL 与系统累计残差。图内明确注明设备闭合不含泵耗散。潜热储能
符号修正后，累计输入与总储能在全周期基本重合，图例、横轴和注释均无重叠。

## 6. 与 Qian 文献的比较方式

主定量合同仍是 Qian et al., Energy 182 (2019), DOI
`10.1016/j.energy.2019.06.094`：

| 文献位置 | 比较对象 | C243 状态 |
|---|---|---|
| Fig.1，PDF 3-4 页 | SMA-SE-SHEX/HHEX/CHEX 四阶段拓扑 | 已实现并通过机制门禁 |
| Eqs.(1)-(4)，PDF 5 页 | 固液能量与相变动力学 | 21+21 节点和跨周期状态已实现；收敛性未完成 |
| Eqs.(5)-(8)，PDF 5 页 | 等力/等位移兼容 | 每个离散步联立求解 |
| Eqs.(9)-(10)，PDF 5 页 | 温跨和 SCP 周期平均 | 已按最后 10 周期与 active SE mass 计算 |
| Table 4，PDF 16-17 页 | 两个不同边界的 `26.2 K`、`0.64 W/g` | 尚无合法 paired roots |

C243 的 `28.7103 K` 和 `0.316481 W/g` 属于同一个固定边界点。温跨相对文献
`26.2 K` 高约 `9.58%`，超过 5% 定量边界；SCP 又不是 zero-lift 条件，所以不能
直接计算“复现误差”。

Qian 2015 IJ Refrigeration 用于完整流体回路和 cyclic steady 定义；Qian 2017
Energy 用于有限库存、网格和 matching principle；Tan 2020 Energy 用于等力/等位移
和热驱动输入；Qian 2021/2023 用于区分级联、材料/循环/系统 COP。不同论文的几何、
材料或性能值没有混入 2019 Table 4 合同。精确本地路径和 PDF 页码见
`项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`。

## 7. 本阶段代码成果

| 文件 | 成果 |
|---|---|
| `Integrate_HeatDriveECC_Constitutive21_Interface.m` | 接入 SHEX fluid heat-flow sensor，不改变 TL 主流体端口 |
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 提取 SHEX/HHEX/CHEX 热流、全部原生流体能量/质量库存和 pressure-source power |
| `Summarize_HeatDriveECC_EighthRound_Output.m` | 末周期/末十周期有限性和性能汇总 |
| `Validate_HeatDriveECC_EighthRound_Physics.m` | 输出新增换热与系统能量指标 |
| `verification/Diagnose_HeatDriveECC_SystemEnergyLogging.m` | 短时原生日志块/变量盘点，不启动长循环 |
| `verification/Audit_HeatDriveECC_SystemEnergyResult.m` | 最终完整周期整机热账本、质量和设备边界门禁 |
| `verification/Build_HeatDriveECC_ControlVolumeContract.m` | 10 个控制体、10 个方程及显式潜热符号合同 |
| `Plot_HeatDriveECC_SCI_FigureSet.m` | 图集扩展到 Fig.07，并修复系统账本可读性 |
| `verification/system_energy_c243_recovery_contract.json` | 冻结 C243 哈希、门禁、状态继承和恢复许可 |
| `verification/Manage_HeatDriveECC_OutputStorage.ps1` | 仅保护 C200 与 C243 权威 raw/OP |
| `verification/Verify_FinalHeatDriveECC_Package.m` | MATLAB 总包审核加入 C243 系统能量门禁 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | 文件、SHA-256、C200/C243 双权威审核 |

关键提交包括 `0f374d1`（整机热账本观测）、`976630c`（质量门禁）、`c05950a`
（潜热储能符号和 Fig.07）。

## 8. 存储治理

C243 权威冻结后关闭 C242 恢复许可，仅保留其合同、哈希、validation、周期摘要、
日志和 SCI 小文件。本次删除 C242 raw/OP、C243 legacy figures 和 dense probe 共
`5.705 GiB`：

| 项目 | 清理前 | 清理后 |
|---|---:|---:|
| `gx101r1_R69_remote/outputs` | `16.164 GiB` | `10.460 GiB` |
| 整个 `正逆耦合` 工作区 | - | `11.116 GiB` |
| 二次 dry-run 候选 | - | `0` |

删除审计：`outputs_storage_audit/cleanup_summary_20260904_044428.txt`。C200 与 C243
raw/OP 不得删除；失败结果始终禁止进入恢复链。

## 9. 复核命令

只读 C243 系统能量审核：

```powershell
cd C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); a=Audit_HeatDriveECC_SystemEnergyResult('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_system_energy_c243_20260904/qian2019_table2_table4_simscape_243cycle_20260904_025423/physical_simscape_result.mat'); assert(a.production_pass && ~a.complete_device_first_law_closure);"
```

重新生成七图集，不重新仿真：

```powershell
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); Plot_HeatDriveECC_SCI_FigureSet('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_coupled_system_energy_c243_20260904/qian2019_table2_table4_simscape_243cycle_20260904_025423/physical_simscape_result.mat');"
```

总包和存储复核：

```powershell
pwsh -File .\verification\Audit_FinalHeatDriveECC_Package.ps1
matlab -batch "cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'); addpath(genpath(pwd)); a=Verify_FinalHeatDriveECC_Package(pwd); assert(a.result_package_pass);"
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
```

## 10. 尚未完成和下一步

1. 给泵耗散定义物理去向：耦合到流体、单独附件散热边界，或明确排除在设备控制体
   外；完成后再审核完整 device first law 和 system COP。
2. 在 C243 恢复权威上建立机制保护的外层求根，分别得到 zero-load 和 zero-lift 两个
   合法周期端点，不能再用单点线性外推代替。
3. 完成 Table 4 参数图谱和局部/全局敏感性；候选点必须先通过相变、流量、温度物性
   域和周期稳态门禁。
4. 完成节点数和时间步独立性。当前 21 节点、1 ms 是生产合同，但尚不能称网格/
   时间收敛。
5. 取得独立实验或独立代码基准后，才能使用 `validated`；目前只允许
   `simulated`、`predicted`、`benchmark-consistent`、`not yet reproduced`。

## 11. 负责人可用结论

> The C243 fully coupled SMA-SE Simscape continuation is mechanism-valid and
> periodic. Direct SHEX/HHEX/CHEX heat-flow balances, native fluid inventories,
> endpoint capacities, and SMA/SE sensible-latent storage close the modeled
> thermal control volume to a relative residual of 1.676e-4. Full device
> first-law closure remains withheld because the reported 11.843 W pump work is
> not thermally coupled by the current pressure-source contract. The operating
> point is not a reproduction of Qian et al.'s paired Table 4 endpoints.
