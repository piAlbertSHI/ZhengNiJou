# 第三十三阶段：C201边界事件与恢复连续性审核

日期：2026-09-07。性质：严格恢复和事件因果诊断，不是新的周期性能结果。

## 1. 结论与证据边界

本轮真正完成了两次MATLAB试验，均从未编辑的原C200 Operating Point开始，均只计算
`2000 -> 2000.001 s`，均保持两项工作点checksum检查为error并自然退出，退出码0。
没有启动完整C201，没有修改C200生产文件，没有将失败或诊断OP传播到生产链。

| 项目 | 名义C201时域扩展 | 仅边界反馈事件延迟1ms的因果对照 |
|---|---:|---:|
| 总指令时域 | 2010s | 2010s |
| 严格OP兼容性 | 通过 | 通过 |
| 物理信号首样本不一致 | 67/161组 | 0/161组 |
| 原生观测首样本不一致 | 698/1240组 | 0/1240组 |
| 具名状态首样本不一致 | 2/73组 | 0/73组 |
| 合计不一致 | 767/1474组 | 0/1474组，所有差异精确为0 |
| 独立连续性审核退出码 | 1，拒收 | 0，仅诊断通过 |
| 完整周期、整机闭合、Table4复现 | 均未通过/未执行 | 均未通过/未执行 |

“MATLAB成功退出”和“严格checksum通过”不能代替物理连续性审核。
767组是不同观测组的计数，不是767个独立物理状态；许多原生变量是代数量或重复派生量。
不把不同单位下的最大数值混合解释为一种物理误差。

## 2. 根因定位

归档接口程序`Integrate_HeatDriveECC_Constitutive21_Interface.m`的第845–860行生成SMA
反馈使能及reset指令，reset等于1-enable；第1331–1344行在换向期间禁用反馈，但跳过
整个仿真的最后一个边界。第1625行将SMA积分器的ExternalReset设为level，初值为0。

因此原200-cycle指令到2000s截止时，该处是终点，不执行内部边界的reset；扩展到
201-cycle后，相同绝对时刻成为普通内部换向边界，enable从1变为0、reset从0变为1。
这不是发现OP文件被编辑，也不能仅凭checksum通过便忽略它。

名义扩展后的首样本SMA PI从`0.02291105120628706 MPa`变为0。两个不一致的具名状态组
分别是SMAPressurePI_Integrator和995通道的Solver Configuration封装组；本构210维延迟、
两组21维温度延迟及SE两个路线PI等其余71组没有首样本差异。
示例物理变化：SMA温度最大差`0.000136955171 K`，SMA压力指令差`0.023924919603 MPa`。
这些值描述本次首样本比较，不是周期漂移或稳态性能。

本轮明确声明的因果对照仅改变两条反馈指令的一个边界样本：在2000s保持原enable=1、
reset=0，在2000.001s回到名义enable=0、reset=1。阀门、压力偏置及全部后续原指令
结点均保持原值。未改动OP数值、模型SLX、物理方程或热容/材料/几何/本构/流体参数。
独立审核逐点验证了这项修改范围，没有以稀疏采样代替全部结点核对。

对照首样本1474组全部精确一致，把本次差异定位到该反馈边界事件，而非无法解释的
任意状态丢失。但“把事件延迟1ms”不是已经批准的物理模型修复，也不是跨周期PI记忆
问题已经解决；不能用这一对照绕过用户关于恢复不得重置记忆的要求。

三条基础指令（SE阀、SMA阀、SMA压力偏置）分别核对C200/C201的全部249个周期结点，
结点时移10s、指令值完全相同。反馈reset在仿真终点的特殊处理单独诊断，不能混称所有
指令都已经严格周期重复。

## 3. 修改的代码

工作根目录：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote`。

| 文件 | 本轮工作 |
|---|---|
| verification/Audit_HeatDriveECC_C200SourceRestore.m | 显式200/201时域选项；冻结参数比较只允许schedule.total_time_s变化；保存指令；受限1ms事件对照；缓存目录隔离 |
| verification/Audit_HeatDriveECC_C201Horizon.py | 1474组首样本比较；完整结点核对；拒收结果写JSON后返回1；对照修改范围检查 |
| verification/test_c201_horizon.py | 6项测试：周期重复、尾值保持、缺结点、无效网格、越界修改及错误释放时刻 |
| verification/Audit_HeatDriveECC_C201Package.py | 原始数据清单、正反审核复算、缓存事故、源码增量和存储/Git审核 |

名义试验执行源码提交为`7268268`，对照试验为`4b43a1d`。交付源码提交以包内release.json
为准，包含后续独立审核和缓存隔离修正。归档物理源仍是`e3f1dcf`，只保留第三十二阶段
已声明的标量结构合并修补；本轮重新逐文件验证39个归档文件，未额外修改归档源码。

## 4. 原始结果与运行方法

证据根目录：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/c200_horizon_20260907`

- `probe201`：名义扩展，保留拒收轨迹、状态、指令、审核元数据及诊断OP。
- `boundary_hold_diagnostic`：明确的因果对照，保存同类原始资料。
- `horizon_audit_v1.json`：名义扩展连续性未通过，不能作为生产恢复许可。
- `boundary_ablation_audit_v1.json`：对照首样本审核通过，production_boundary_shift_authorized仍为false。

两次试验均有原始日志；通用的解释型本构块persistent状态警告保留，未屏蔽。
两份诊断OP均命名DO_NOT_RESUME_FOR_PRODUCTION.mat。原C200的结果SHA与OP SHA仍分别为：

```text
0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD
FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816
```

新的结果包位于：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/c201_boundary_release_20260907`
完整源码采用第17阶段source_snapshot.zip加本包从该基线直接生成的source_delta.patch，
不是依赖逐阶段叠加补丁。大型原始结果按清单引用，不复制进每个阶段目录。

```powershell
$r = 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -X utf8 "$r\verification\Audit_HeatDriveECC_C201Package.py"
python -m unittest discover -s "$r\verification" -p 'test_*.py'
$out = Join-Path $env:TEMP ('c201_nominal_' + [guid]::NewGuid() + '.json')
python -X utf8 "$r\verification\Audit_HeatDriveECC_C201Horizon.py" --repo $r --output $out
# 上一条应返回1：拒收证据的正确重现，不是命令需要盲目重试。
$out = Join-Path $env:TEMP ('c201_ablation_' + [guid]::NewGuid() + '.json')
python -X utf8 "$r\verification\Audit_HeatDriveECC_C201Horizon.py" --repo $r --probe boundary_hold_diagnostic --output $out
# 上一条应返回0；仍不授权生产边界延迟。
```

回归测试152项通过。包创建时还分别独立复算两份JSON，并要求返回码1/0以及字节哈希
与原审核完全匹配。包的完整性通过不等于名义连续性通过。

## 5. 存储、归档事故与修正

生产outputs清理dry-run为0候选，实测约16.878GiB；整个工作区最新精确字节数、文件数、
本轮新增证据量和Git对象占用见workspace_storage_snapshot.json。本轮未复制生产大型MAT，
未删除仍有因果诊断用途的两份小型探针。前几阶段已完成的大规模清理不重复记为本轮释放。

本轮复用归档模型目录时，Simulink更新了两个缓存：

1. slprj/_sfprj/heatdrive_ecc_coupled_se21/amsi_serial.mat，248字节。
2. slprj/accel/heatdrive_ecc_coupled_se21/heatdrive_ecc_coupled_se21_instrumentation_settings.mat，180字节。

第三十二阶段清单不应把可变编译缓存当作不可变科研证据。当前旧包全量审核返回1：
87项中85项未变、2项缓存哈希改变；所有71项非缓存条目均重新通过。旧清单没有修改，
不伪称旧包现在仍87/87通过。parent_cache_incident.json保留旧/新哈希及明确范围，新的
结果包不把16个生成缓存条目当作必要科研数据。

后续验证程序已用[Simulink.fileGenControl](https://www.mathworks.com/help/simulink/slref/simulink.filegencontrol.html)
将缓存和生成代码放到每次试验自己的目录，并在退出时还原会话设置。真实MATLAB配置
设置/还原烟测返回CACHE_CONFIG_ROUNDTRIP_PASS=1；尚未用新隔离设置重新完成一次整个
模型恢复仿真，不把配置烟测描述为已经完成那项验证。

## 6. 文献边界与下一步

本轮新增证据针对数值续算事件，不产生新的Eq.9、Eq.10、SCP、COP或Table4性能值，也不
需要把1ms诊断包装成SCI性能图。本轮没有宣称重新阅读全文；所有已对标文献位置仍见
[Qian本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)
以及第三十二阶段报告第7节的十篇逐页表。

主定量合同仍是Qian2019本地PDF第3–5页Fig.1/Eq.1–10、第6页Table2、第15–17页Fig.13/Table4；
Qian2015 IJR56的PDF第7–9页Fig.6/Eq.28–30辅助界定流体、水箱与管壁库存，不授权删除状态。

下一步必须明确恢复快照的事件前/事件后定义，建立不会把首次求值当成一次额外PI重置
的边界合同，并验证原模型固有reset与“恢复不得重置记忆”的约束如何一致。不能仅为
首样本匹配而永久延迟控制事件，或反过来把所有首样本差异豁免掉。隔离缓存后的严格
短段验证也须完成。只有事件、状态及完整观测窗口均通过后，才进入完整C201周期。

随后仍需新结构全状态合同、完整控制体质量/能量审核、受门禁保护的固定Tc外层求解、
正交敏感性、共同参数与共同周期窗口下的zero-load/zero-lift成对端点及最终SCI图集。
总目标保持未完成；本轮没有降低稳态、机制、能量或Table4门槛。
