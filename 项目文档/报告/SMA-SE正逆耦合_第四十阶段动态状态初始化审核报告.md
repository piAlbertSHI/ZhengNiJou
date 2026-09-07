# SMA-SE正逆耦合：第四十阶段动态状态初始化审核报告

日期：2026-09-08。结论：数字恢复记录与动态坐标有实质修正；整机完整恢复门禁仍未通过。

## 1. 本轮实际推进

本轮完成一次42路数字观测重放、三次整机初始化试验，并独立重算全部1474组观测。
不是等待记录，不是生产20-cycle结果，也没有把局部通过替代完整目标。

两项得到真实整机试验证据的修正：

1. 42个转换器必须使用公开OP数字记录，不能使用同一时刻普通输出样本。
   修正后42组初始观测全部逐位吻合；总初始失败组由49降为7。
2. 块的“初始目标”不等于求解器的实际动态坐标。实际动态变量包括67条管路的比内能
   `u_I`和4个buffer的`mass`；此前对应的是代数量温度和液位。
   使用实际动态坐标后，125个动态变量在探针初始时刻全部逐位吻合。

**仍未通过：完整1474组比较有7个初始失败、197个一步后失败。**
唯一一步后超过门禁的动态坐标是SMA泵出口连接腔压力，差1.41953904e-9 MPa。
不能据此宣称完整热态恢复、守恒连接腔迁移、整机第一定律闭合或Table4复现。

## 2. 不变的主线与科学边界

- C200结果SHA-256：`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`。
- C200 OP SHA-256：`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816`。
- 每次整机探针均重新核对上述原始哈希。没有编辑、替换原OP。
- 归档物理模型未改，三个探针均采用C200的2000至2000.001 s窗口。
- 没有扩展周期命令到C201，没有将边界事件延后1 ms，没有重置生产热容、buffer、本构或PI。
- 沿用第三十八阶段已独立验证的两条控制误差滤波器等价状态空间表示；该表示变更仍明确记录。
- 原始1474组比较的绝对1e-10加相对1e-11门禁未放宽，也没有删除转换器或求解器组。
- 本轮没有生成`final_operating_point.mat`，所有生产恢复许可仍为false。

## 3. 数字重放的配置修正和资格范围

目录：`gx101r1_R69_remote/outputs_storage_audit/c200_converter_digital_history_20260908`。
真实MATLAB执行源码`98cd966`，自然退出0。

修正隔离热容的`T_specify=on`，实际初温逐位等于340 K；新增离散驱动出口的To Workspace
观测和转换器逐样本数值记录。输入来自冻结C200末4点，未使用失败物理模型的检查点。

独立审核：42路数字输入与冻结命令逐位相同，转换器第二通道观测逐位相同；公开快照
中的上一输入也逐位相同。隔离热容最大BE能量残差1.59875e-11 J。

此前物理热源端口的位一致失败仍保留：26/42逐位相同，16路有1 ULP差异。
`strict_bitwise_native_heat_gate_pass=false`并未改成true。本轮资格只限于数字记忆观测，
物理热流另外按已有数值比较界限报告；这不是降低整机恢复门禁，也不是接纳旧失败OP。
新的诊断探针仅复制42个公开数字记录，未复制隔离模型的热容、求解器或物理状态。

新增7项测试包括数字输入1 ULP变化必须失败、物理端口位不一致不能隐去、错误热流、
缺样本、错误时刻样本及非有限值。全套201项Python回归实际通过。

## 4. 第一次整机试验：转换器历史记录

目录：`outputs_storage_audit/joint_converter_history_seeded_op_20260908`。
执行源码`d3dbe24`。前台MATLAB自然退出0，科学审核退出1。

|项目|第三十八阶段|本轮转换器修正|
|---|---:|---:|
|初始失败观测组|49|7|
|一步后失败观测组|197|197|
|初始逐位一致组|622|664|
|一步后逐位一致组|268|268|
|原125个物理目标|通过|通过|
|72组具名记忆|42组初始失败|全部通过|

直接比较前后原始MAT：变化恰好只有42个转换器的初始观测；所有1474组一步后数值
完全相同。因此，本构转换器首通道的修正没有消除其余动力学差异，不能继续归咎于它。

## 5. 第二次整机试验：额外流量目标，拒绝

目录：`outputs_storage_audit/joint_converter_flux_seeded_op_20260908`。
执行源码`0342088`，自然退出1，在种子状态保持性检查失败后退出；种子观测仍保留。

增加的三个低优先级初始化目标全部来自C200原生观测：

|变量|数值|单位|
|---|---:|---|
|SMA泵入口连接腔mdot_B|0.05248800330546055|kg/s|
|SMA泵出口连接腔mdot_A|-0.05248800330546055|kg/s|
|SHEX热容Q|0.0017482710107777158|W|

结果使两个连接腔压力偏离C200约1.509695e-10 MPa，分别超过1.100542e-10和
1.082668e-10 MPa门禁。该种子未进入后续一步仿真，失败记录没有传播。
该试验否定了“只补几个代数流量目标即可解决问题”的当前方案。

## 6. 发现真实动态坐标

只读加载第三十七阶段已经冻结的公开目标树，提取`Differential`和`Eliminated`属性。
没有重新初始化模型，也没有解码私有内核。全部2668条属性保存于
`outputs_storage_audit/c200_differential_target_metadata_20260908.json`。

共有125个动态变量，均未被消去，且全部能与C200原生观测按完整路径和单位精确匹配：

|动态坐标类别|数量|单位|
|---|---:|---|
|管路比内能u_I|67|kJ/kg|
|固体和集中热容温度T|46|K|
|buffer与连接腔温度T_I|6|K|
|buffer质量mass|4|kg|
|连接腔压力p_I|2|MPa|

原先125个活跃块目标与这些动态坐标只重合54项。不能因为两者数量同为125，就声称
已经覆盖所有动态状态。新候选对实际动态坐标采用High，保留原71个代数温度/液位目标
为Low，共196项目标；每项优先级变更和数据来源均写入审计，不隐瞒坐标表示的改变。
原始125个物理观测的验收门禁仍照常检查，不因目标优先级调整而放宽。

该选择基于本机R2025b的实际公开元数据；动态与代数量的区别参见
[MathWorks仿真过程说明](https://www.mathworks.com/help/simscape/ug/how-simscape-simulation-works.html)。
公开目标的应用仍会重新求解初始化条件，并不等同于恢复完整求解器执行信息，参见
[Operating Point初始化流程](https://www.mathworks.com/help/simscape/ug/using-operating-point-data-for-model-initialization.html)。

## 7. 第三次整机试验：真实动态坐标

目录：`outputs_storage_audit/joint_differential_seeded_op_20260908`。
执行源码`6250ef6`，自然退出0，独立科学审核退出1。

125个动态种子值逐位等于C200；在随后一步探针的初始样本，125个动态坐标仍全部逐位一致。
原125个物理目标和72组记忆也通过。初始逐位一致组由664增为833，一步后由268增为341。
但失败组仍为初始7、一步后197，整体不通过。

初始失败组的实际物理差异如下；信号别名和995通道求解器组另有重复记录，合计7组：

|原生观测|绝对差|原生单位|
|---|---:|---|
|入口连接腔mdot_B、出口连接腔mdot_A|约6.02327e-9|kg/s|
|上述两端Phi|约8.60796e-7|kW|
|SHEX/HotSinkMass/Q|约6.13e-10|W|

注意Phi以kW记录，不能错写成W。一步后最显著的热流差为HHEX热容Q约6.85254e-7 W，
SMA入口流体温度差约1.14701e-7 K。125个动态坐标中只有出口连接腔p_I一步后超门禁，
差1.41953904e-9 MPa。完整数值、单位和原始/候选样本见包内2948行比较CSV。

这些结果说明：仅补齐动态坐标并不能证明完整OP等价。剩余原因可能涉及求解器恢复信息、
代数解或导数的时序，目前尚未证实，不能写成已经查明的内核缺陷。

## 8. 修改清单

代码位于`gx101r1_R69_remote/verification`：

- `Replay_HeatDriveECC_ConverterHistory.m`：真实初温目标、数字出口日志、公开快照数值。
- `Audit_HeatDriveECC_DigitalConverterHistory.py`及测试：独立数字资格与物理位一致分列。
- `Apply_HeatDriveECC_ConverterHistoryState.m`：42个具名数字记录的哈希、配置、类型和时刻检查。
- `Apply_HeatDriveECC_ObservedFluxTargets.m`：三个代数流量目标的已拒绝诊断方案。
- `Export_HeatDriveECC_DifferentialTargetMetadata.m`：2668条公开变量属性只读导出。
- `Build_HeatDriveECC_DifferentialStateTargets.m`：196项测得目标及优先级变更记录。
- `Run_HeatDriveECC_TargetInitializationProbe.m`：新增三条明确分开的诊断路径，失败种子禁止传播。
- `Audit_HeatDriveECC_TargetInitialization.py`：增加数字证据链、125动态坐标及196项目标来源审核。
- `Audit_HeatDriveECC_DynamicInitializationPackage.py`：原始MAT对照、完整比较CSV、源码包和存储审核。

源代码完整版本使用已冻结基准ZIP加本包直接Git二进制增量；不再重复复制生产大MAT。
本轮没有新增性能图，以免将初始化诊断包装成新的制冷循环成果。

## 9. 结果包和复核命令

包目录：`gx101r1_R69_remote/outputs_storage_audit/dynamic_initialization_release_20260908`。

- `release.json`：源码基准/当前提交、实际退出码、资格范围。
- `comparison_summary.json`：转换器修正前后因果比较与动态坐标覆盖。
- `full_1474_group_comparison.csv`：1474组×2时刻，包含单位、全部通道原值、候选值及门禁。
- `result_manifest.csv`：每项必需文件大小与SHA-256，包含失败试验和历史包链接。
- `source_delta.patch`：相对于冻结源码基准的完整直接增量。
- `python_tests.log`、`storage_snapshot.json`：回归日志、工作区及Git占用。

只读复核，不启动MATLAB、不生成生产数据：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合'
python -X utf8 .\gx101r1_R69_remote\verification\Audit_HeatDriveECC_DynamicInitializationPackage.py
python -m unittest discover -s .\gx101r1_R69_remote\verification -p 'test_*.py'
```

包审核通过只表示证据完整和可重复重算；其`full_scientific_gate_pass`仍必须为false。

## 10. 管理、后续和未完成事项

三个真实整机进程均只启动一次，等待原会话自然退出；没有定时器、心跳、重复启动或
终止健康MATLAB。运行期间未发送反复等待消息。失败后先读取具体误差再开展不同假设试验。

2026-09-08 07:45存储治理dry-run：outputs为16.878 GiB，删除候选0，本轮删除0。
四个本轮试验目录合计约47.43 MiB，主要为小规模观测和隔离编译缓存；未复制约5 GB生产MAT。
整个工作区的精确字节数见本包存储快照，不能把outputs占用当作整个工作区占用。

下一步是比较严格C200恢复中公开可取得的完整求解器记录与目标初始化的记录，先检验
“普通观测能否作为求解器恢复数据”这一尚未证明的假设。不得猜测995向量下标、修改私有
状态、删除剩余7/197组门禁，或凭125动态变量通过就直接进入生产迁移。

控制体完整周期仍有约-1.40601 J库存端点差额；守恒连接腔迁移、十个新稳态周期、机制
保护的Tc求解、敏感性分析、共同合同下的成对Table4及完整系统COP均未完成。完整目标保持不变。

Qian文献位置继续使用
[本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。
2019 Energy论文Table4零负载26.2 K与零温跨0.64 W/g是不同边界条件；本轮没有新增论文
对标结果，也不宣称`validated`或`reproduced`。当前表述仍是诊断性的`simulated`、`not yet reproduced`。
