# SMA-SE 正逆耦合：第十七阶段物性域与库存方程核对报告

日期：2026-09-06。本阶段新增生产循环数为 **0**；复用第十六阶段严格恢复的 `1800..1800.003 s` 原生采样，只新增模型只读导出和离线审核。没有重置状态、修改控制参数或提升诊断恢复点。

## 1. 已完成与未完成

已完成：实际物理端口映射、两套流体域连通审核、67 根准稳态管路名义密度和固定质量重建、73 个流体储能元件的原生密度/内能查表核对，以及四罐和两腔体的微分积累方程短窗口诊断。

**尚未完成：正确账本的多周期闭合、全内部状态周期性、生产采集器替换、固定 Tc 外层求根、敏感性、Table 4 成对端点、完整设备 COP 和独立 validation。** 原 `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` 的旧库存后处理仍作为历史实现保留，不把本阶段离线工具冒称为已经部署的生产账本。生产续算仍被用途守卫禁止。

论文冻结 C200 继续作为基准，不是当前模型合法恢复源；runtime C180 只允许显式库存诊断。runtime 观测 C200 仍不允许恢复，其相分数 RMS=`0.000400591810392 > 0.0004` 的失败没有改变。

## 2. 物性域连接审核

初版导出有两处问题，证据保留：

1. `SourceFile` 不是通用参数枚举中的稳定字段。改为针对 SimscapeBlock 直接查询，找到两套设置块。
2. 按 `LineParent` 合并物理线段漏掉了分支，初版只有 76 条外部连接。改用公开 `PortConnectivity` 的物理目标端口句柄，不把它当成零基信号端口序号。依据：[MathWorks Block Parameters / PortConnectivity](https://www.mathworks.com/help/simulink/slref/block-parameters-and-properties.html)。

最终导出：167 个块、277 个热流体端口、234 条去重外部连接、17 条层级连接。只对登记过的单流体通道元件加入内部连通关系；不把整个 Subsystem 的端口合并，不通过热端口连接两种流体。

| 实际设置块 | Pipe | Tank | Chamber | 管路名义密度 kg/m³ | 管路固定总质量 kg |
| --- | ---: | ---: | ---: | ---: | ---: |
| SMA_ThermalLiquidSettings | 44 | 2 | 2 | 998.620029312 | 0.0364130454811 |
| 热流体设置 | 23 | 2 | 0 | 1050.439243866 | 0.00674820022226 |

设置归属由连通图得到，而不是根据 SMA/SE 路径文字猜测。端口复制探针只操作临时模型；源模型没有改线或保存 OP。

## 3. 查表与管路库存结果

重建严格跟随本机 R2025b：一维密度向量先扩展到 **30 点对数压力网格**，再双线性查表。不能直接在目标压力上求指数后代替原网格插值。

- 73 元件共 292 个原生密度采样：最大绝对差 `4.547473508864641e-13 kg/m³`，预声明实现比较阈值 `1e-7 kg/m³`。
- 同样 292 个原生内能采样：最大绝对差 `2.3283064365386963e-10 J/kg`，预声明阈值 `1e-6 J/kg`。
- 实际两套表均使用内能向量模式。界面中未激活的默认 cp 向量没有参与重建；cp 由扩展内能与密度表的焓差分得到。
- 当前准稳态管路使用 `M=rho_nominal*V`、`U=M*u_I`，固定总管质量约 `0.0431612457034 kg`。瞬时 rho_I 是物性值，不是该准稳态储能方程的质量系数。

旧质量算法在本次四样本中的最大相对偏差为 `5.51131870288%`，发生于 SHEX/HotPipe。该管 3 ms 窗口的新库存残差为 `-2.37985196495e-8 J`，旧算法为 `1.11117857445e-4 J`。这说明该元件账本更贴合实际方程，**不能从一个短窗口推导全系统闭合**。

## 4. 罐与腔体的积累方程

常压 Tank 的官方能量方程可代数整理为 `M*cp*dT + h*dM`；本阶段分别列出该系数路径积分、端点 `delta(M*u)`、`integral(p dV)` 与 `delta(M*h)`，不混为同一数值。罐本机实现是受保护源码，未尝试解码；方程依据为官方 [Tank (TL), Energy Balance](https://www.mathworks.com/help/hydro/ref/tanktl.html)。

定容腔体使用本机可读源码中的 `dUdp`、`dUdT` 及质量系数；由于表值及其差分分别插值，不能先假定其路径积分与端点 `rho*V*u` 严格相同。

| 元件 | 系数方程短窗口能量残差 J |
| --- | ---: |
| ColdFluidBuffer | +0.00431486958180 |
| HotFluidBuffer | -0.0106333010656 |
| SHEXFluidBuffer | -0.00000375909425 |
| SMAHotFluidBuffer | +0.00141494874038 |
| SMA Pump inlet chamber | -0.000501951596680 |
| SMA Pump outlet chamber | -0.00138600675875 |

残差没有被删去或调阈值变成“通过”。此处只有三个 1 ms 步长，并处于换向附近；离散积分、事件采样与表格导数一致性仍需分离审核。程序只宣布查表实现一致，所有周期闭合、生产授权和 Table 4 标志均为 false。

本机源码位置和 SHA-256 见 `verification/native_inventory_equation_sources.json`。它记录 pipe.ssc、thermal_liquid_settings.ssc、constant_volume_chamber.ssc 的精确行号及摘要，不复制受版权保护的完整 MATLAB 源码。

## 5. 修改与测试

- `Export_HeatDriveECC_TLConnectivity.m`：分支感知 v2 图及原始端口连接记录。
- `Test_HeatDriveECC_TLConnectivity.m`：双通道层级、共同热连接、三传感器分支回归；四方向端口映射测试继续通过。
- `Audit_HeatDriveECC_TLDomainMetadata.m`：直接查询 SourceFile，保留部分失败导出，增加实际内能模式/参数。
- `Audit_HeatDriveECC_TLDomainInventory.py`：登记元件内部通道、拒绝无物性孤岛/跨域合并、逐管固定库存重建。
- `Audit_HeatDriveECC_NativeAccumulation.py`：原生内能对照及罐/腔体微分积累诊断。
- 两个新增 Python 测试模块，总测试数由 16 增至 **32**，全部通过。
- 新增源码依据合同、结果包审核入口、本报告。总报告追加第 22 节，旧第十四至十六阶段报告不改写。

一次测试虽然动态端口断言通过，但 MATLAB checkcode 提示测试索引写法，命令退出 1；诊断日志保留，修正后重新测试及完整模型导出退出 0。没有把非零退出当作整体通过。

Git：`4df4ffb` 冻结分支映射与密度重建；`4cd5c06` 冻结能量物性导出。后者真实模型导出由该提交执行。早先分支导出是在未提交定义下完成，不能倒填成事前冻结提交。最终代码快照提交号与哈希见结果包 `release.json`。

## 6. 完整结果与可运行复核

仓库基目录：`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote`。

- 实际拓扑与能量物性：`outputs_storage_audit/tl_domain_energy_tables_20260906/tl_domain_metadata.json`。
- 逐管库存/密度：`outputs_storage_audit/tl_domain_inventory_reconstruction_20260906/domain_inventory.{json,csv}`。
- 罐/腔体方程对照：`outputs_storage_audit/native_accumulation_equations_20260906/native_accumulation.json`。
- 完整已跟踪代码和报告 ZIP、原位结果清单、冻结合同副本、测试日志、存储快照：`outputs_storage_audit/tl_inventory_release_20260906`。

ZIP 不复制数 GiB 的原始结果；`result_manifest.csv` 按路径、大小和 SHA-256 绑定原位文件，包含论文 C200、runtime C180、runtime 观测 C200 的 raw/OP 及观测 sidecar。这是一套“代码 ZIP + 原位数据清单”，不是可独立搬走的全数据 ZIP。

以下检查现有结果，不启动仿真，也不覆写旧证据：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p 'test_*.py' -v
pwsh -File verification\Audit_HeatDriveECC_TLInventoryPackage.ps1
```

重新计算离线结果，用新目录防止覆写：

```powershell
$r = 'outputs_storage_audit'
$new = Join-Path $r ('owner_recheck_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$t = "$r/tl_domain_energy_tables_20260906/tl_domain_metadata.json"
$p = "$r/native_inventory_port_comparison_20260906/native_inventory_probe.json"
$m = "$r/native_inventory_model_metadata_20260906/storage_model_metadata.json"
python verification/Audit_HeatDriveECC_TLDomainInventory.py --topology $t --probe $p --metadata $m --output "$new/domain_inventory.json"
python verification/Audit_HeatDriveECC_NativeAccumulation.py --topology $t --probe $p --metadata $m --output "$new/native_accumulation.json"
```

若需重建实际模型，在 MATLAB 执行 `addpath('verification'); Audit_HeatDriveECC_TLDomainMetadata(<新目录>);`。这是建模和导出，不是新循环计算。长程序必须前台只启动一次并等待其真实会话自然退出；当前有效纪律不再使用计时器或 heartbeat。

## 7. 存储管理及接续

2026-09-06 10:55 dry-run：outputs **16.731 GiB**，删除候选 **0**，本阶段删除 **0 byte**。上次全工作区实测约 17.60 GiB；本阶段精确更新值见包内 `workspace_storage_snapshot.json`。最初“约 120 GB”是用户估计，不据此编造本阶段释放量。

仍保留有证据用途的 raw、严格 OP、状态 sidecar；不删除未审核数据来凑清理量。新增文件主要是数百 KB 的表和完整源代码 ZIP，不复制生产 MAT，不把大结果加入 Git。

下一步顺序：

1. 做同一诊断起点下短分段严格 OP 接续与不分段轨迹比较，固定命令终止时刻和日志配置。中间 OP 仅用于该受控试验，不进入生产恢复链。
2. 接入独立命名、显式版本的原生库存采集器；保留旧字段，不把两种账本拼接。完整记录罐内 T_I/M/V、管路固定质量、腔体系数及各端口能量/质量流。
3. 用经接续一致性审核的方式取得多周期原生记录，分离表插值和积分误差，审核 ColdLoadMass、泵和所有外边界。
4. 正确元件账本及全内部周期门禁通过后再恢复生产权限，进入固定 Tc 求根、正交敏感性和成对 Table 4 端点。

Qian 文章与具体对照位置仍见 `项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`。本阶段查的是建模元件依据，没有新增 Qian 端点数据、绘制新生产 SCI 图或完成文献复现。
