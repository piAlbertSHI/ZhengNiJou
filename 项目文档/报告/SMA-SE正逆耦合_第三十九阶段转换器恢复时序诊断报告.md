# SMA-SE正逆耦合：第三十九阶段转换器恢复时序诊断报告

日期：2026-09-08。性质：真实隔离试验、失败归因与证据封装，不是生产恢复资格报告。

## 1. 本轮回答了什么

第三十八阶段同模型联合初始化仍有初始49组、一步后197组不一致，其中42组是本构热流
Simulink-PS转换器。本轮不删除这些观测，不改变1474组严格比较，也不重跑失败生产链。

本轮找到了一个可实验复现的时序问题：**转换器在同一时刻的普通状态输出日志，不能直接
当作Operating Point内的恢复记录。** 在边界前5 W、边界处0 W的控制试验中，输出日志
为`[1,0]`，完整OP的公开记录却为`[1,5]`。将输出样本移入种子OP会复现首通道差异；
移入完整OP的原记录则恢复一致。没有解码私有内核或猜测995通道求解器向量。

这解释了此前恢复方法的一项不足，但尚未证明整机42组问题全部修复，更不等于整机迁移通过。

## 2. 原始主线保持不变

- C200原始结果SHA-256：`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`。
- C200原始OP SHA-256：`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816`。
- 本轮从C200大MAT只提取末4个输入样本；提取前重新核对完整结果哈希。
- 没有编辑原OP，没有新生产周期，没有复位生产模型热容、buffer、本构或PI记忆。
- 所有本轮试验均`production_recovery_allowed=false`。

当前完整C201控制体诊断仍是：净输入30.20821765 J，库存变化加pdV为31.61422814 J，
差额约-1.40601049 J。转换器隔离试验并未消除该差额。

## 3. 实际执行及退出状态

以下目录均位于工作区`gx101r1_R69_remote/outputs_storage_audit`。

|目录|实际执行|退出与结果|
|---|---|---|
|converter_boundary_isolation_20260908|首版标量试验|退出1；关闭插值与默认外推配置冲突，保留日志|
|converter_boundary_isolation_20260908_v2|直接输入，4种比较|退出0；热流、温度及转换器观测一致|
|converter_discrete_boundary_isolation_20260908|0.001 s解释型离散驱动，4种比较|退出0；结果一致，尚未复现整机差异|
|converter_falling_boundary_isolation_20260908|增加边界归零，6种比较|退出0；首次复现转换器首通道差异|
|converter_snapshot_phase_isolation_20260908|增加“用输出样本恢复”负对照，9种比较|退出0；普通日志与OP记录不能互换|
|c200_converter_history_replay_20260908|C200末步42路输入重放|退出1；严格输入/热源观测检查失败，首版现场信息不足|
|c200_converter_history_replay_20260908_v2|保留全部42路现场后检查|退出1；时间全部一致，16路热源端口有1 ULP差异|

前三个标量版本及后两次扩展均保存逐样本MAT和JSON。对已完成标量试验使用独立Python
读取原始MAT重新核算，不只信任MATLAB布尔字段。42路试验失败结果不进入恢复链。

## 4. 隔离物理合同与独立审核

标量热容为1000 J/K，初始340 K；正输入经受控热流源从热容节点流向热参考，故热容
净热流为输入的负值。全局ode3步长0.001 s，本地Backward Euler步长0.001 s，accelerator。

归零试验窗口为2000.004至2000.010 s。分别检查：

1. 每个求解器采样点的命令是否真正传递到热源，避免“两次仿真都没有输入”也被判等价。
2. 热源与热容端口符号是否相反。
3. 每区间`1000*(T[n]-T[n-1]) - 0.001*Q_mass[n]`的残差。
4. 严格OP与种子路径的热流、温度、转换器两通道及时间戳，分别报告而不混成一个PASS。

9种比较中实际热流、温度全部一致；最大区间能量残差约1.76733e-11 J。
舍入界限按`8*C*spacing(T)`计算，仅用于已知解析热容的隔离试验，未修改整机门禁。

种子路径时间戳最大差2.2737367544e-13 s，属于浮点时间表示差异。
独立审核明确给出`all_time_grids_exact=false`；只对隔离试验按两个ULP内的同一求解器tick
核算，不把它说成C200逐位时间网格恢复成功。MATLAB时间重置警告保留。

## 5. 关键负对照

|波形|种子OP|移入原OP转换器记录|移入同一时刻输出样本|
|---|---|---|---|
|全零|转换器观测一致|一致|一致|
|边界0变5 W|一致|一致|不一致|
|边界5变0 W|不一致|一致|不一致|

表中“一致”仅表示该标量试验的转换器观测；不能推广成整机恢复资格。
标量试验显示，首通道与输入变化有关，但没有据此声明其全部内部语义。

## 6. C200末步与42路重放

C200末4点为1999.997、1999.998、1999.999、2000 s。全部42路在1999.999 s非零，
到2000 s归零，确实包含与负对照相同的输入历史类型。只导出4×42个数值，没有复制大MAT。

重放使用42个真实转换器和受控热流源，驱动共用隔离热容；这不是SMA-SE物理模型。
独立读取归档SLX，逐个检查全部42个转换器的6个参数；均为W、provide、Udot=0、
一阶配置值、0.001 s配置值、AffineConversion=off。`provide`表示没有启用输入滤波。

42路现场结果：

- 精确时间网格：42/42。
- 热源端口热流逐位等于指令：26/42；另16路最大相差1 ULP，最大绝对差1.73472348e-18 W。
- 公开快照JSON中第二个数值与1999.999 s输入完全一致：42/42。
- MATLAB timeseries对象本体按MAT文件哈希保全；Python未冒充解码其不透明序列化内容。
- 隔离热容实际初温为300 K，而非意图中的340 K：该重放脚本未启用`T_specify`。
  这是另一个需要修正并重新验证的试验配置问题，不能隐去。其最大BE能量残差约1.59875e-11 J。

**严格重放门禁保持失败。** 物理热源端口是经过网络求解的量，不是数字输入本身；下一轮应
先补充实际转换器输入日志，明确区分输入位一致性、端口求解舍入和能量守恒。不能只因误差
很小，就把本轮错误状态改成成功，或把其快照送入生产恢复链。

## 7. Fig23逐图解释与视觉审核

正式图位于：
[Fig23 PNG](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/converter_snapshot_phase_isolation_20260908/figures_v2/Fig23_converter_restart_phase.png)
及同目录PDF、逐点CSV。

- a：四种恢复路径的实际热源输入完全重合，正负热流方向可辨。采用阶梯线，不暗示连续斜坡输入。
- b：首通道在边界处区分两组路径；原OP和原快照恢复一致，种子与错误输出样本恢复一致。
- c：第二通道输出在四种路径完全重合。日志字段不同不必然意味着此试验输送了不同热量。
- d：库存变化减BE热量积分，单位nJ；四条曲线重合，显示的是浮点残差，不是整机能量闭合。

已实际查看PNG：标题、坐标、单位、图例无裁切，四面板各回答一个问题。a/c/d曲线重叠是
数值一致的结果，不靠人为错位把相同数据画成不同结论。该图为调试补充图，不冒充Qian性能图。

## 8. 修改代码与验证

新增/扩展的代码均在`gx101r1_R69_remote/verification`：

- `Audit_HeatDriveECC_ConverterBoundary.m`：三波形、三恢复方式及公开快照记录。
- `HeatDriveECC_ConverterIdentity.m`：无持久状态的解释型驱动。
- `Audit_HeatDriveECC_ConverterEvidence.py`：独立输入、符号、时间、BE库存审核。
- `test_converter_evidence.py`：8项回归，含相同但错误输入、错误符号、漏能量、NaN及时间错位负例。
- `Export_HeatDriveECC_ConverterHistory.py`：哈希保护的C200末4点提取。
- `Replay_HeatDriveECC_ConverterHistory.m`：42路独立重放及失败现场保存。
- `Audit_HeatDriveECC_ConverterReplay.py`：不改写失败的独立重算与42块参数覆盖审核。
- `Plot_HeatDriveECC_ConverterPhase.py`：Fig23 PNG/PDF/CSV。
- `Audit_HeatDriveECC_ConverterPackage.py`：本轮包、完整源码基准加增量、历史证据链和存储审核。

194项Python回归实际通过。主要执行源码提交为`47b38df`、`23a2566`、`767ffef`、`00ff3d6`、
`8d02f86`、`fb5292f`；最终包的精确源码提交见`release.json`。包完整不等于科学门禁通过。

## 9. 可直接运行的复核

只读复核，不启动MATLAB、不复制生产数据：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合'
python -X utf8 .\gx101r1_R69_remote\verification\Audit_HeatDriveECC_ConverterPackage.py
python -m unittest discover -s .\gx101r1_R69_remote\verification -p 'test_*.py'
```

包目录：`gx101r1_R69_remote/outputs_storage_audit/converter_phase_release_20260908`。
完整源码采用已冻结`tl_inventory_release_20260906/source_snapshot.zip`加本包
`source_delta.patch`，不是重复打包约5 GB的C200原始结果。文件位置、大小、哈希见
`result_manifest.csv`，源码基准及目标提交见`release.json`。

## 10. 存储与Git纪律

当前已不是历史120 GB量级；本轮实测总工作区字节数及GiB见包内`storage_snapshot.json`。
2026-09-08 06:27的outputs dry-run为16.878 GiB、候选0、本轮删除0。该值仅是outputs，
不冒充整个工作区大小。本轮未复制C200大MAT、未删除原OP或科学失败证据。

缓存不进入必需科学证据清单，源码由Git管理；本轮小规模失败日志/输入/结果保留用于复核。
所有真实MATLAB进程均等待同一会话自然退出，没有定时器、心跳、重复启动或杀死健康进程。

## 11. 后续主线和文献边界

下一步顺序不变：修正42路重放的初温目标并补全数字输入观测；通过其预先声明的检查后，
再对同模型热态初始化做全部1474组、125个物理目标及72组记忆的严格比较。
不得先删除42组转换器门禁。即使42组修复，其余压力/端口/求解器差异也必须继续诊断。

之后才是守恒连接腔迁移、库存端点闭合、十个新稳态周期、受保护Tc求解与共同合同下的
zero-load/zero-lift成对Table4比较。当前这些工作仍未完成。

本轮新增依据是实际R2025b隔离试验及
[MathWorks Simulink-PS Converter说明](https://www.mathworks.com/help/simscape/ref/simulinkpsconverter.html)，
不是重新验证Qian论文。Qian文献位置继续参见
[本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。
2019 Energy论文Table4的26.2 K与0.64 W/g分别对应不同边界条件；本轮不得宣称复现、
实验验证、完整系统COP或整机第一定律已经通过。
