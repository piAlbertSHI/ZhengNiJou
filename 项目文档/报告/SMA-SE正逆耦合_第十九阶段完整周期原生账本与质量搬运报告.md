# SMA-SE 正逆耦合：第十九阶段完整周期原生账本与质量搬运报告

日期：2026-09-06。承接第十八阶段。保留原始结果、失败记录及历次报告，不把后处理修改倒填成新的物理运行。

## 1. 负责人先看结论

从受限 runtime C180 检查点严格推进了**一个完整周期 C181，1800 至 1810 s**。真实前台 MATLAB 自然退出码 0；该周期全部既有机制门禁通过。新增采集覆盖 119 个原生储能元件、1240 个原生坐标，以及 73 组/1376 个观测状态坐标，各保留 10001 个样本，未降精度、抽点或删除端点。

新证据不是“已经完成全部目标”：SHEX 罐该周期增重 0.163772 g、内部温度下降 0.0523901 K；SMA 热侧罐减重 0.162591 g、内部温度上升 0.0249030 K。全回路总质量变化很小，不能掩盖两罐之间仍在发生的质量再分配。

**当前只完成一个完整周期的受控诊断，不是十周期内部稳态，不是方程匹配的物理闭合通过，不是 Table 4 复现。** 没有开放生产接续或外层求根，没有修改物理参数、初态、流量门限或周期门限。本次 C181 OP 仍限原试验内部使用，不是通用恢复点。

## 2. 实际改了什么

核心目录为 `C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote`。物理试验执行提交：`17d7b85e95e69c5b01e3f328473d49c7557730b2`。后续离线修正/报告提交由发布包 `release.json.source_commit` 精确记录。

| 文件 | 具体作用及行为边界 |
| --- | --- |
| `Extract_HeatDriveECC_PhysicalLogs.m` | 从原生产驱动机械提取共享日志读取函数；默认行为保留。新诊断显式不提取旧 U/M 库存字段 |
| `HeatDriveECC_CycleStageFromTime.m` | 共享原有阶段映射，不改变生产时序 |
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 仅改为调用共享函数；文本回归对照旧提交证明默认路径是机械搬移 |
| `verification/Make_HeatDriveECC_MechanismWindow.m` | 将完整物理周期生成只读审核视图，复用原机制门禁；不更改仿真时间、状态或原 options |
| `verification/Export_HeatDriveECC_PhysicalTail.py` | 从冻结 raw 按 HDF5 有界读取末周期，不复制整条 GiB 历史；验证来源哈希 |
| `verification/Collect_HeatDriveECC_NativeCycleDiagnostic.m` | 严格 OP、完整周期采集、机制审核、独立原生账本和受限 OP 保存；机制失败即禁止传播。支持 1 至 10 周期，但本次只运行 1 周期 |
| `verification/Audit_HeatDriveECC_NativeCyclePacket.py` | 从完整原生周期独立计算 119 元件账本，只声明账本可计算 |
| `verification/Audit_HeatDriveECC_CommandCoverage.m` | 读取实际 18 条 From Workspace 时间轴，而不是把模型 StopTime 当作输入覆盖终点 |
| `verification/Audit_HeatDriveECC_NativeSystemLedger.py` | 组合无外加冷负载的实测外边界与原生积累；分别保存能量残差、质量漂移和四罐逐阶段净交换 |
| `verification/Audit_HeatDriveECC_NativePilotPackage.ps1` | 创建或只读审核代码增量、原位数据清单、冻结 C200/C180、作用域标志和逐文件 SHA-256 |

新增/扩展测试为 `test_physical_extraction_move.py`、`test_physical_tail.py`、`test_native_system_ledger.py` 和 MATLAB 的 `Test_HeatDriveECC_MechanismWindow.m`。当前 Python 全套 **62 项通过**，覆盖阶段边界错位、非有限值、跨日志时钟差异、热流正负号、潜热重复计入防护和不支持外边界拒绝等。

最后对 collector、命令覆盖、机制窗口、共享 physical 提取器和阶段映射五个 MATLAB 文件重新运行 checkcode，无条目，前台程序退出 0，`simulation_run=false`。日志为 `native_cycle_preflight_20260906/postprocessing_checkcode.log`。

## 3. 真实运行与状态继承

真实程序只启动一次，约 62 分钟后自然退出；没有定时器、轮询循环、heartbeat、后台监控或重复启动。原生记录保存完整 10 s 周期，固定 `ode3`、1 ms、accelerator；两个 OP checksum mismatch 均保持 `error`。MATLAB 关于 Interpreted MATLAB Function 的 persistent 状态通用警告保留在 `matlab_stdout.log`，未抑制；已有显式本构 UnitDelay 接续证据不扩张成所有调用的形式化证明。

恢复源仅来自 `verification/runtime_c180_recovery_contract.json` 的显式 `inventory_diagnostic` 权限。未从机制/周期失败的观测 C200 恢复，也没有重置热容、buffer、本构、温度、相分数或独立路线 PI 记忆。论文 C200 继续冻结为性能基准，不是当前模型的通用恢复源。

| 本次结果 | 值 |
| --- | --- |
| 严格恢复 / 既有机制门禁 | 通过 / 通过 |
| 完整原生采集周期数 | 1，不是 10 |
| 多周期内部周期性 | 未证明 |
| 方程匹配控制体闭合 | 未批准通过 |
| 新生产循环 / 生产恢复权限 | 0 / 禁止 |
| 单周期 Eq.9 诊断值 | 28.7095933935 K |
| 单周期 Eq.10 SCP 诊断值 | 0.316531391953 W/g |
| Eq.10 冷量 / CHEX 传感器冷量 | 13.2363414537 W / 12.9666131506 W |

两种冷量相差约 0.269728 W，尚需按控制体及采样定义解释。此处只有一个周期，不满足文献比较合同的末十周期窗口。固定 CHEX 温度仍为 276.95 K，没有求得 zero-load/zero-lift 成对根。

## 4. 两项元数据/离线问题及处理

### 4.1 命令覆盖字段

原始 `native_cycle_result.json` 的 v1 字段 `command_horizon_s=1800` 错用了继承的 `options.simulation.stop_time_s`。实际命令生成器使用 `cycle_count*tau=1820 s`，本次 `SimulationInput.StopTime=1810 s`。

从本次保存的 options 实际重新构建模型后，逐条读取了 18 个 From Workspace 输入：全部覆盖到 1820 s，审核退出 0，**没有重跑物理周期**。证据为 `native_cycle_preflight_20260906/pilot_command_coverage.json`。collector v2 增加真实命令覆盖前置检查，并分开记录 `nominal_model_stop_time_s` 与最短命令终点。原始 v1 结果不改写，不把 v2 冒充执行版本。

### 4.2 跨日志时钟差异

首次离线系统账本检查要求 To Workspace 与 Simscape 原生日志的 float64 时间戳逐位相同，因而退出 1。诊断发现两者均为 10001 点，起止点与 1 ms 整数步号相同；1680 个时间戳相差一个 ULP，最大 2.2737367544323206e-13 s。

修正仅限离线汇总：沿用已测试的 16 ULP 固定网格验证，要求整数步号完全相同；两条流分别在各自保留的原时间轴积分。汇总器不插值、不修改 raw、不删除事件样本。**共享 physical 提取器仍保留其原有网格插值，不能宣称整条处理链从未插值。** 首次失败与诊断保存在 `system_ledger_initial_rejection.json`，后续 v1/v2/v3/v4 账本也保留。

## 5. 完整周期外边界与积累账本

使用第十八阶段核对的 67 管、4 罐、2 腔体、46 固体热容方程。固体潜热/机械本构源只作为实测输入保留一次，未再塞入显热库存。当前仅覆盖 `cold_load_mode=no_load`、外加冷负载为零和压力源热功为零的已核对配置；工具拒绝未审核的非零负载/压力源热功模式。

正号定义为流入已列控制体。外部热输入为 SHEX 源输入减去 HHEX 环境排热、减去 CHEX 固定源传感器的原生有向输出。

| 1800 至 1810 s | J |
| --- | ---: |
| SHEX 热源输入 | 8262.32169906 |
| HHEX 向环境排热 | 8361.63187265 |
| CHEX 固定源向系统输入 | 129.666131506 |
| 外部净热输入 | 30.3559579195 |
| 实测本构源净输入 | 0.0000132261021 |
| 119 元件原生通量净输入 | 30.3559711408 |
| 方程系数路径积分积累 | 31.7716030544 |
| 输入减积累残差 | **-1.41563190881** |

外边界与全部元件空间求和的瞬时能量差 RMS 为 `6.86518e-10 W`，质量差最大 `6.93889e-18 kg/s`，支持**边界计数和正负号一致**，不代表时间积分已闭合。能量残差按最大源/排热积分归一化为 `1.69300913e-4`，即 **0.0169301%**。这一数值不自动触发旧账本门限的通过结论；不能用元件正负抵消替代局部审核。

主要元件能量残差：泵出口腔体 `-0.818866 J`，泵入口腔体 `-0.489098 J`，SHEX 罐 `-0.211170 J`，SMA 热侧罐 `+0.103383 J`。其余管路/固体最大残差约 `2.24e-7 J`，SE 两罐分别约 `+0.000233 J`、`-0.000115 J`。事件区间积分和腔体系数离散还需要审核。

原生流体质量起点 `0.433286143883 kg`，端点变化 `1.18144908e-6 kg`，约 **1.18145 mg / 2.727 ppm**；系数质量积累 `1.18168891e-6 kg`，边界净质量通量积分约 `-4.56e-19 kg`。这些不同定义分别保留，没有混用来消除残差。

压力源的**原生热功**积分为 0 J；工程附加泵功代理为 `118.430405 J`，约 11.8430 W。后者不是本次实测完整设备电功，不能直接宣称设备一阶能量闭合或最终 system COP。

## 6. 四罐质量搬运：比总量更重要的新结果

以下温度为原生 **T_I**，不是旧 `*_buffer_T_K` 的 A 端口温度。

| 罐 | 周期末减初始质量 g | 相对初始质量 | 内部温度变化 K |
| --- | ---: | ---: | ---: |
| SHEX 水罐 | +0.163772009 | +0.136928% | -0.052390087 |
| SMA 热侧水罐 | -0.162590548 | -0.246166% | +0.024903043 |
| SE 冷侧罐 | -0.014114077 | -0.014217% | -0.000024426 |
| SE 热侧罐 | +0.014114077 | +0.013838% | +0.000059105 |

实际时序为 **3.5 / 1.5 / 3.5 / 1.5 s**，不是四个等长阶段。下表为原生端口净流量积分，正号为进入罐：

| 罐 | 阶段 1，g | 阶段 2，g | 阶段 3，g | 阶段 4，g |
| --- | ---: | ---: | ---: | ---: |
| SHEX | +0.158192612 | +0.006558234 | -0.000721165 | -0.000257672 |
| SMA 热侧 | -0.000758466 | -0.000239949 | -0.155921362 | -0.005670770 |
| SE 冷侧 | +0.141759208 | -4.424259100 | -0.128525771 | +4.396911586 |
| SE 热侧 | -0.141759208 | +4.424259100 | +0.128525771 | -4.396911586 |

四罐本次均只记录一个流体端口 `mdot_A`；这表示罐与连接回路之间的净交换，不是把罐当成两个端口的贯通流道。SHEX 增重集中于阶段 1，SMA 热侧减重集中于阶段 3。分阶段通量积分与质量端点差同时保存，共享阶段端点按梯形积分保留；例如 SE 阶段边界处两种数值存在微小差异，不能择一隐藏。

这已经足以否定“外部指标稳定就等于全部内部稳态”的推断，**但尚未确定控制器、阀切换、热膨胀、腔体可压缩性及数值积分各自贡献**，也不能将一个周期的漂移线性外推为必然耗尽或失稳。因此暂不盲目启动十周期链，先分解相关腔体和阀泵切换时段的质量/能量预算。

## 7. 代码、结果包与哈希

完整当前代码在 Git 工作树。可重建代码包沿用第十七阶段完整 `source_snapshot.zip` 加本阶段 `source_delta.patch`，**不是再复制完整 ZIP**。基包提交 `3f1925866cc68f357d71dc413590d049c0f6cc96`，ZIP SHA-256：`CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。本阶段 patch 直接从该基包提交生成，已经包含第十八阶段改动，不需要顺次套用两个 patch。

- 本周期结果目录：`outputs/qian_native_inventory_pilot_from_c180_20260906`。
- 元件明细：`cycle_181/native_ledger.json`；机制明细：`cycle_181/cycle_audit.json`。
- 最新离线系统账本：`outputs_storage_audit/native_cycle_preflight_20260906/native_system_ledger_C181_v4.json`。
- 发布记录：`outputs_storage_audit/native_pilot_release_20260906`，包括 `release.json`、`result_manifest.csv`、源码增量、测试日志及存储快照。

| 原位文件 | bytes | SHA-256 |
| --- | ---: | --- |
| `cycle_181/native_window.mat` | 127792114 | `0A87C41FB2E0D59E72F3AA53D831EB4778C048ACCBAD09AC0AAAA5CDB9B837FB` |
| `cycle_181/segment_physical.mat` | 26672880 | `6E5D15B2C2F67799748187F1BD15E0CBA1B08C7BCF1A5C1D1639B35AFE6CCC13` |
| `cycle_181/DO_NOT_RESUME_FOR_PRODUCTION.mat` | 3626327 | `2B43D70E6DA794D82E0CD4758DE2D7BBD08DD3A7AF5CBA54323609FFAAD7EFCE` |
| `cycle_181/native_ledger.json` | 153959 | `D723A928B728358D42FE96E5E5510AD6C2C82B44568AA6E7D7580B80D2825DEA` |

冻结 C200、runtime C180 的 raw/OP 也列入本阶段原位哈希审核，不复制。发布是**完整代码的基包加增量和本机原位结果清单**，不是便携全数据 ZIP；搬到其他机器时须连同清单要求的数据路径一并迁移。包审核通过仅说明文件完整、已声明诊断检查通过，不是物理闭合/稳态通过。

## 8. 负责人运行什么验证

以下只读审核已有结果，不启动仿真：

测试依赖 Python 的 NumPy/SciPy/h5py；其中机械搬移比较使用本机 Git 历史提交 `43329ec`。源码 ZIP 加 patch 不自带 Git 历史；在无历史的新机器执行该项测试还需保留仓库历史或取得该基线源码，不能把缺少 Git 历史解释成物理模型失败。

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p 'test_*.py' -v
pwsh -File verification/Audit_HeatDriveECC_NativePilotPackage.ps1
```

独立重算逐元件与系统账本，使用新目录，工具拒绝覆盖旧证据：

```powershell
$a = 'outputs_storage_audit'
$c = 'outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181'
$new = "$a/owner_C181_recheck_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
python verification/Audit_HeatDriveECC_NativeCyclePacket.py --packet "$c/native_window.mat" --topology "$a/tl_domain_energy_tables_20260906/tl_domain_metadata.json" --probe "$a/native_inventory_port_comparison_20260906/native_inventory_probe.json" --metadata "$a/native_inventory_model_metadata_20260906/storage_model_metadata.json" --output "$new/native_ledger.json"
python verification/Audit_HeatDriveECC_NativeSystemLedger.py --cycle-root $c --output "$new/system_ledger.json"
```

第一条重新计算元件账本；第二条重新读取原生和 physical MAT，校核原来元件账本的来源后汇总系统。可以比较新元件账本与原 `cycle_181/native_ledger.json` 的数值一致性，不能把两个脚本解释为两次独立仿真。历史包另可运行 `Audit_HeatDriveECC_NativeWindowPackage.ps1` 和 `Audit_HeatDriveECC_TLInventoryPackage.ps1`，均不重跑物理程序。

真实重新执行试验的入口为 `Collect_HeatDriveECC_NativeCycleDiagnostic(new_output_root, 1)`，需 MATLAB R2025b、现有已验证模型依赖、冻结源文件、Python 依赖及干净的已提交工作树。它是约一小时量级的新物理试验，不是日常查看结果命令；当前不建议把周期数直接改成 10 来掩盖漂移诊断。

## 9. 工作区与 Git 管理

2026-09-06 16:54:59 工作区实测 **19214325355 bytes，17.894735 GiB，4187 文件**；该快照在本报告和发布增量写入之前，发布时的更新实测保存在 `workspace_storage_snapshot.json`。已远低于用户最初提出的约 120 GB，但不能把跨多个历史阶段的差额冒充本阶段释放量。

本阶段实际删除 **249882 bytes，约 244.03 KiB**：唯一文件为本次可重建的 `cycle_181/stage_temperature_probes_50samples.csv`。先 dry-run，核对绝对路径和用途，再用既有管理器 Apply；删除清单及结果分别为 `cleanup_candidates_20260906_165247.csv`、`cleanup_summary_20260906_165247.txt`。清理后 outputs 为 **18122651757 bytes，16.878035 GiB**。完整原生、物理记录、OP、日志、参数合同及报告均保留。

没有新增大 raw 的复制或提交。Git pack 约 **62.09 MiB**，无 garbage，当前不是空间大头。C40/C60 raw 仍被中断恢复包审核引用，不因文件旧就删除；继续瘦身前必须先生成、验证替代证据并修订依赖合同。本阶段也没有运行可能破坏恢复依据的统一删除或 Git 强制重置。

## 10. 未完成项及下一步

1. 对 C181 泵进/出口腔体逐阶段及阀切换邻域重算残差，分离事件采样、微分系数积分与实际净搬运，建立可被实验否定的原因假设。新增实测表明本步骤先于盲目长链。
2. 明确四个罐原生 M/T_I 和两腔体 p/T 的同相位门禁；995 个求解器打包坐标仍未逐项完成物理映射。三条 PI 观测存在，不等于所有隐含状态已映射。
3. 在不重置状态、失败不传播的受控协议下取得连续完整十周期原生证据。现有短窗口同会话接续试验与本次一周期 strict restore 不等于全部长窗口/跨会话等价证明。
4. 原生控制体、完整内部周期门禁和有效参数域通过后，才能恢复固定 Tc 的受保护 outer solve、正交敏感性以及共同参数/窗口下成对 Table 4 边界。
5. 完整设备电功、系统 COP、步长/网格收敛和独立 validation 尚未完成。历史 SCI 图保留；本阶段未新增最终生产图集，也没有对未稳态数据发布新的复现结论。

文献逐页定位仍见 [Qian 本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。主量化合同为 2019 Energy 文献 Table 4；该索引中的 C246 性能叙述属于历史点，不能理解为当前获准恢复源。2015 系统控制体/周期稳态、2017 匹配与收敛、2020 热驱动兼容等文献只提供各自范围证据，不能混用参数，不能以本次单周期值直接对标 26.2 K / 0.64 W/g 两个不同边界端点。
