# SMA-SE 正逆耦合：第十八阶段严格分段接续与原生账本报告

日期：2026-09-06。承接第十七阶段，不替换历史报告或冻结数据。

## 1. 本阶段结论与边界

已完成真实 Simscape 的两种短断点接续试验，MATLAB 自然退出，退出码 0。两组试验中，前缀及磁盘保存/读取后的后缀与连续轨迹相符；Python 从实际 MAT 数据独立检查了 41856 个数值，float64 位模式完全一致。

新增独立版本的原生窗口账本，覆盖 119 个储能元件；两组共 2212 项分段积分可加性检查通过。又将六组真实窗口转成共享时间轴的紧凑格式，78480 个数值及时间轴逐位核对通过，文件合计 535804 bytes。没有使用降精度或抽点压缩。

**以上是接续方法、账本实现和数据格式的有限范围证据，不是完整周期能量闭合或文献复现。** 本阶段没有新增生产循环，没有解除 C180 的生产限制，没有重置任何物理或控制器状态。新的诊断 OP 仍禁止作为生产恢复源。

## 2. 真实运行与断点设计

实际执行代码为 `1246409dd47596b9eaa87ab8954312890129abac`，启动时工作树干净。程序为 `verification/Audit_HeatDriveECC_SegmentedInventoryRestore.m`，从 runtime C180 的冻结 raw/OP 合同进入显式 `inventory_diagnostic` 路径。原始哈希见 `verification/runtime_c180_recovery_contract.json`，试验 JSON 也保存这两项 SHA-256。

- 前台 MATLAB 启动约 11:11:54，自然完成约 14:42:54，约 3 小时 31 分钟，shell 最终退出码 0。
- 整个试验固定命令生成终点 1820 s、`ode3`、1 ms、accelerator、原 SaveState/SaveFormat 与 10002 点 Simscape 日志上限。
- Contents/Interface 两个 OP checksum mismatch 均保持 `error`，没有改为 warning。
- 共七次严格 `sim` 调用，属于同一个前台 MATLAB 程序，不是七次盲目重试。

| 试验 | 起点 s | 保存断点 s | 终点 s |
| --- | ---: | ---: | ---: |
| 周期内部 | 1800 | 1800.003 | 1800.006 |
| 周期边界 | 1809.997 | 1810 | 1810.0030000000002 |

每项先计算不分段参考，再从相同起点计算 3 ms 前缀。前缀全部轨迹匹配后才保存受限 OP，读回后继续 3 ms 后缀。周期边界试验的起点来自 C180 严格推进到 1809.997 s，没有人工设定温度、相分数、热容、buffer、PI 或本构变量。

磁盘 OP 往返是在**同一个 MATLAB 会话内**完成，不能扩张为新 MATLAB 进程跨会话接续证明；只比较两个 6 ms 窗口，也不能扩张为完整 10 周期等价证明。比较包含起点、断点与终止样本，没有插值或删除事件点。

## 3. 独立复核与警告处置

每次比较包含 73 组数值状态、1376 坐标，以及 119 个真实储能元件的 1240 条原生叶变量。两项试验的前缀/后缀、observed/native 共八组比较最大绝对差全部为 0。

执行提交的 MATLAB 比较器将 `isequal` 标注成 `bitwise_values_equal`，命名过强：数值相等不区分正零与负零。本阶段已改成 uint64 位模式比较，并增加正负零回归测试。没有改写历史 JSON；独立 Python 复算直接读取历史 MAT，确认本次数据确实逐位相等，因此不需要为修正字段语义重跑物理试验。

MATLAB 的 Interpreted MATLAB Function 关于 persistent 状态可能不进入 OP 的通用警告保留在 stdout，未被抑制。接口中本构 210 维状态由显式 UnitDelay 回送，`HeatDriveECC_ConstitutiveStateVectorStep21` 从输入状态重建下一步，并读取固定 options；本次静态检查未在所核对的更新函数中发现隐含 persistent 状态。不过，这不是全部传递调用的形式化证明，也不是 995 个 SolverConfiguration 坐标的物理映射完成。

## 4. 新原生账本具体计算什么

新 schema 为 `heatdrive_ecc_native_window_ledger_v1`。它校核冻结来源、119 元件清单、实际物性域、单位、原生查表值和完整固定步长窗口。旧生产的 `U_*_inventory_J`、`M_*_inventory_kg` 没有导入，也没有被悄悄改义。

| 元件 | 积累依据 | 另行保留 |
| --- | --- | --- |
| 67 Pipe (TL) | 固定 `M=rho_nominal*V`，`M*delta(u_I)` | 端口质量、能量通量，瞬时原生温度/压力 |
| 4 Tank (TL) | `integral(M*cp dT + h dM)`，限已核对的常压模式 | 原生 T_I/M/V、delta(Mu)、delta(Mh)、integral(p dV) |
| 2 定容腔体 | 原生表系数 `integral(dUdp dp + dUdT dT)`，质量亦用微分系数 | 端点 rho*V 与 rho*V*u 的变化，避免混同 |
| 46 Thermal Mass | 固定质量、cp 的显热积累 | 原生 Q；相变潜热作为外部输入，不重复计入 |

管路与腔体公式重新对照本机 R2025b 的 `pipe.ssc` 和 `constant_volume_chamber.ssc`；确切路径、行号及哈希见 `verification/native_inventory_equation_sources.json`。罐式方程由官方 [Tank (TL) 的 Energy Balance 与 Mass Balance](https://www.mathworks.com/help/hydro/ref/tanktl.html) 代数整理得到；本机受保护源码未解码。

离线积分采用保留样本的梯形/系数路径积分。每个元件分别保存能量/质量残差，不以不同元件的正负抵消宣称系统闭合。流量绝对积分分端口累计，用于后续尺度审计，但目前尚无获准的物理残差通过结论。

| 窗口 | 积分可加性比较数 | 元件最大绝对能量残差 J | 元件最大绝对质量残差 kg |
| --- | ---: | ---: | ---: |
| 1800 至 1800.006 s | 1106 | 0.01297106832194 | 7.2752229723e-8 |
| 1809.997 至 1810.003 s | 1106 | 0.01070636378151 | 6.0029036227e-8 |

“可加性通过”只指同一段采样拆开积分再相加与整体积分一致。预设数值比较限为能量 `1e-9 J + 1e-11*scale`、质量 `1e-12 kg + 1e-11*scale`，**不是物理闭合阈值**。上表非零残差未删除、未放宽门禁，事件采样和积分误差仍待完整周期审核。

## 5. 紧凑采集与测试

`Write_HeatDriveECC_NativeWindow.m` 输出的 MAT 只含四项：`header_json`、共享 `time_s`、`native_values`、`observed_values`。保留完整通道描述和来源哈希，不含模型对象、OP、冗余时间轴或旧库存字段。写入器本身不能证明严格恢复，因此 header 显式保留 `strict_restore_verified_by_writer=false`。

`Audit_HeatDriveECC_NativeWindowPacking.m` 只读取已完成的试验数据，没有启动新仿真；生成六个包，并验证拒绝非有限值、错误终点、重复变量和不完整清单四类输入。Python 独立读回时逐位对照原 MAT，连时间位模式也比较。此压缩比例是两个短窗口的实测，不能推算长周期一定有相同比例。

- Python 全套 **51 项测试通过**，包含固定名义质量、罐压力体积功、腔体系数、断点终止值、正负零、不同版本/来源拒绝和紧凑列映射。
- MATLAB 比较器 **7 项测试通过**，四个相关 MATLAB 文件 checkcode 无条目。
- MATLAB 打包审核前台程序自然退出码 **0**，`PACKETS=6 REJECTIONS=4 SIMULATION_RUN=0`。
- 原生账本独立复算退出 0；紧凑包独立复算退出 0。

主要新增文件位于仓库 `verification`：`Audit_HeatDriveECC_SegmentedEvidence.py`、`Audit_HeatDriveECC_NativeWindowLedger.py`、`Write_HeatDriveECC_NativeWindow.m`、`Audit_HeatDriveECC_NativeWindowPacking.m`、`Audit_HeatDriveECC_NativeWindowPackets.py` 及三个测试模块。包审核入口为 `Audit_HeatDriveECC_NativeWindowPackage.ps1`。

## 6. 结果、代码与负责人复核命令

以下路径均以 `C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote` 为基目录：

- 原始断点试验、受限 OP、完整 trace MAT、stdout：`outputs_storage_audit/segmented_inventory_restore_20260906`。
- 独立位模式审核：上述目录的 `independent_evidence_v2.json`，含原始结果 SHA-256。
- 新逐元件账本：上述目录的 `native_window_ledger_v1.json`。
- 六个紧凑包及独立哈希：`outputs_storage_audit/native_window_packing_test_20260906`。
- 本阶段发布记录：`outputs_storage_audit/native_window_release_20260906`，包含 `result_manifest.csv`、`release.json`、测试日志和 `source_delta.patch`。

不再复制一份约 54 MB 的完整代码 ZIP。完整源代码基包沿用第十七阶段 `tl_inventory_release_20260906/source_snapshot.zip`，SHA-256 为 `CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`；本阶段 patch 由该基包提交至本阶段提交生成。`release.json` 记录基包及当前提交，创建时做反向 apply-check。现有 Git 工作树就是最新完整代码；基包加 patch 也是完整代码交付方式，不是仅交一段示例。大 MAT 仍按原位文件清单交付，不是便携全数据 ZIP。

检查已有结果，不启动仿真：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p 'test_*.py' -v
pwsh -File verification/Audit_HeatDriveECC_NativeWindowPackage.ps1
pwsh -File verification/Audit_HeatDriveECC_TLInventoryPackage.ps1
```

独立重算时使用新文件名，工具拒绝覆盖旧证据：

```powershell
$a = 'outputs_storage_audit'
$s = "$a/segmented_inventory_restore_20260906"
$new = "$a/owner_native_recheck_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
python verification/Audit_HeatDriveECC_SegmentedEvidence.py $s --execution-commit 1246409 --output "$new/split.json"
python verification/Audit_HeatDriveECC_NativeWindowLedger.py --topology "$a/tl_domain_energy_tables_20260906/tl_domain_metadata.json" --probe "$a/native_inventory_port_comparison_20260906/native_inventory_probe.json" --metadata "$a/native_inventory_model_metadata_20260906/storage_model_metadata.json" --split-root $s --execution-commit 1246409 --output "$new/ledger.json"
python verification/Audit_HeatDriveECC_NativeWindowPackets.py --packet-root "$a/native_window_packing_test_20260906/packets" --split-root $s --execution-commit 1246409 --output "$new/packing.json"
```

`--execution-commit` 是明确传入的历史运行记录，离线工具不能从数值猜测执行提交。本阶段最新工具提交号见发布记录，不倒填为物理试验的执行版本。

## 7. 工作区及 Git 管理

2026-09-06 15:07:23 实测全工作区 **19025535314 bytes，17.718911 GiB，4100 文件**；同次 outputs dry-run 为 **16.731 GiB**、已审核淘汰候选 **0**。本阶段实际删除 **0 byte**，不把历史释放量或最初约 120 GB 估计虚算成本阶段清理成果。

Git pack 约 62.09 MiB，松散对象约 827 KiB，无 garbage；不是当前占用大头。仅代码、测试、合同与报告进入 Git，原生 MAT/OP、紧凑包和诊断日志不提交。发布采用源代码增量，不重复复制生产 raw。

仍保留论文 C200、runtime C180、观测失败 C200 的必要证据。旧 C40/C60 raw 目前仍被中断恢复包审核显式依赖，不能仅按日期删除；下一轮若做进一步瘦身，应先验证其所需前缀在后续保留数据中的完整性，生成替代清单并同步旧包审核入口。原始断点 trace/OP 也仍作为本阶段唯一试验依据保留。

## 8. 下一步主线与未完成项

1. 将已验证的紧凑窗口写入器接入受限原生多周期采集编排；每段保留严格 OP 检查和机制门禁，不沿用旧库存通过标志。
2. 在共同命令/日志设置下取得连续完整周期原生记录；新 MATLAB 会话磁盘恢复及全周期轨迹比较尚未完成。本阶段的短窗口验证不替代这两项。
3. 用新账本审核全部内部状态与控制器记忆的周期漂移、元件守恒及事件积分，再组合泵、冷热源、ColdLoadMass 和全部外边界，不能把 119 元件通量总和当成已闭合的外部系统。
4. 正确账本和完整内部周期门禁通过前，生产权限、固定 Tc outer solve、正交敏感性和成对 Table 4 复现仍未开放；最终 SCI 图集、完整 system COP 和独立 validation 仍未完成。

本阶段没有新增 Qian 边界数据或宣称论文复现。文章及逐页对照定位仍在 [Qian 本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。历史 SCI 图保留，待新完整周期证据通过后再发布新生产图集。
