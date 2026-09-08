# SMA-SE正逆耦合：第四十一阶段公开快照与存储审核报告

日期：2026-09-08。范围：接续第四十阶段的公开状态恢复诊断，以及工作区和Git管理。

## 1. 本轮结论

严格C200续算参考可重复；三种公开快照恢复方案均未通过完整1474组比较。
没有生产恢复许可，没有新20-cycle生产结果，没有完整系统第一定律闭合或Table 4复现。
程序正常退出与科学门禁通过是两个不同结果。本轮独立科学审核正常产出JSON后退出1，
明确表示拒绝恢复方案；结果包完整性审核单独判断文件、哈希及复算是否一致。

|方案|复制的公开状态组|初始超限组|一步后超限组|初始逐位一致组|一步后逐位一致组|
|---|---:|---:|---:|---:|---:|
|动态目标种子，复制非网络快照|72|7|197|876|338|
|动态目标种子，复制完整公开快照|73|7|197|876|338|
|未编辑的日志派生Simscape OP种子，复制非网络快照|72|7|197|647|355|

比较窗口为2000.001至2000.002 s。采用原绝对1e-10加相对1e-11界限，保持单位、
样本时刻、通道覆盖一致；没有删去995通道求解器组，也没有把逐位不一致冒充逐位通过。

## 2. 真实程序和独立审核

本轮接续前已执行的MATLAB记录保留在`gx101r1_R69_remote/outputs_storage_audit`：

|目录|执行源码|结果及用途|
|---|---|---|
|c200_zero_time_snapshot_20260908|150c997|退出1：原OP时间2000 s，StopTime不允许小于等于该时间；保留错误JSON|
|c200_two_step_snapshot_20260908|f3b2da1|退出0：严格续算至2000.002 s，三个样本及真实公开OP快照|
|public_snapshot_control_20260908|071751a|局部变量path遮蔽MATLAB函数，启动失败；空diary不是完整错误证据，错误仅有先前终端记录|
|public_snapshot_control_20260908_v2|0110b82|修正变量名后退出0；72/73组复制两臂均完成，科学比较均失败|
|c200_logged_simscape_op_20260908|83a178a|退出0：重复严格参考，生成未经编辑的日志派生Simscape OP|
|logged_simscape_snapshot_control_20260908|c6524c2|退出0：日志派生OP初始化对照完成，科学比较仍失败|

本次接续没有再次启动这些MATLAB程序。新增独立审核并实际重算所有比较，210项Python
回归实际通过。原v4元数据早于命令范围字段；兼容仅限其固定SHA-256
`EF96B1A124EAEE0D999181223119C66B3C5717C5C6A2A3F0D6CB98C9E7B734BC`。
其他文件缺字段会报错，不能默认通过。首次审核的KeyError已据此诊断修正。
`public_snapshot_evidence_20260908.json`为首版独立结果，`_v2.json`进一步核对日志OP
哈希、来源、时间、196项种子目标及未编辑声明；二者均保留，不覆写旧证据。

## 3. 新证据说明了什么

严格参考的161组信号、1240组原生变量、73组注册状态，共1474组，新增参考的前两个
样本与冻结v4逐位相同；独立重复的全部三个样本也逐位相同。

2000.002 s实际公开OP中的995个求解器数值，全部逐位等于2000.001 s普通日志样本，
而不等于2000.002 s日志。说明在本次模型和配置下不能直接把同一时间的普通输出日志
当作恢复快照。995个数值单位并未逐项公开辨认，不能把其混合数值差解释为热量或温度。

动态目标种子的72组与73组复制两臂，1474组输出全部相同。这只能说明本次公开赋值路径
没有改变输出，不能推广成“Simscape忽略所有状态写入”。旧两臂没有保存候选输入Dataset
的读回副本；日志OP对照已增加`nonnetwork_snapshot_input_public_states.mat`以便后续追踪。

日志派生对象通过公开`simscape.op.create(simlog,2000.001)`取得，2668项目标，包含框架
生成的私有数据，整个对象直接使用，没有解码或编辑私有内容。文件57,497,112字节，SHA-256：
`54F69B6FC5B22D02614EF4DF4DA2F7F07FF957199ED4EA31FDC3F243D5340FCC`。
它改变了一些数值结果，但没有消除7/197组超限，不能提升为生产恢复点。

公开属性检查中`loggedStates`可读写，`startTime`和`snapshotTime`仅可公开读取；原C200
OP的Solver Configuration具名get不可用。未绕过这些访问限制，也未猜测匿名索引。
物理网络沿用C200归档模型；两条控制误差滤波器仍使用此前明确记录并隔离验证的等价
状态空间表示，因此不声称整个Simulink图逐字节未改。

## 4. 本轮代码交付

- `Audit_HeatDriveECC_C200SourceRestore.m`：严格参考的两步捕获、真实快照导出和日志OP导出。
- `Build_HeatDriveECC_DifferentialStateTargets.m`：允许显式选择第二个已观测样本，默认旧行为不变。
- `Run_HeatDriveECC_PublicSnapshotControl.m`：两种种子来源及公开整组复制对照，不保存生产检查点。
- `Audit_HeatDriveECC_PublicSnapshotEvidence.py`：独立1474组比较、时间/单位/覆盖检查、来源与哈希检查。
- `test_public_snapshot_evidence.py`：新增9项测试；包括缺失覆盖、错时、错单位、NaN、未知旧元数据拒绝。
- `Audit_HeatDriveECC_PublicSnapshotPackage.py`：递归核验第四十阶段包，重算三臂比较和本轮哈希清单。

这些文件均位于`gx101r1_R69_remote/verification`。完整源码使用既有54 MB基线ZIP加从
基线提交到本轮源码提交的直接Git二进制差分，不逐阶段复制整个仓库或大结果MAT。
本轮源码提交、基线提交记录在结果包`release.json`；源码差分生成时经过反向应用检查。

## 5. 完整结果包与验证命令

本轮包目录：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/public_snapshot_release_20260908`。

包内包含`release.json`、`result_manifest.csv`、`source_delta.patch`、`python_tests.log`、
`storage_snapshot.json`、`full_1474_group_comparison.csv`。清单引用现存原始MAT、JSON、
报告和前置结果包，不另复制大型结果。CSV共8844行，即3方案×1474组×2时刻，含原单位、
参考/实际逐通道数值、误差、既有界限判定和逐位比较。没有用单一最大误差隐藏失败项。

在PowerShell运行只读核验，不重跑MATLAB、不覆写既有结果：

```powershell
Set-Location -LiteralPath 'C:\Users\86182\Desktop\正逆耦合'
python -X utf8 gx101r1_R69_remote/verification/Audit_HeatDriveECC_PublicSnapshotPackage.py
python -m unittest discover -s gx101r1_R69_remote/verification -p test_*.py -v
git status --short --branch
```

包审核预期退出0、`package_integrity_pass=true`，同时科学与生产许可仍为false。
若文件被修改、缺失或重算比较改变，审核必须失败。独立科学脚本的预期退出1不能作为
恢复链自动重试理由；需要新的证据改变结论，而不是放宽界限。

## 6. 工作区和Git管理

本次盘点工作区约18.98 GiB，不再是历史120 GB。精确测量时间、字节数及前15大文件写入
包内`storage_snapshot.json`。这是当前实测，不把历史120 GB与当前GiB直接相减冒称本轮释放量。

09:58的现有outputs清理规则检查：16.878 GiB、候选0、删除0。大文件主要是冻结C200、
另一路运行观测C200及其C180/60/40来源数据；不能仅因旧或失败就删除仍被审计引用的文件。
本轮没有复制生产大MAT，没有删除原始失败证据或有效恢复点。

Git对象约58 MiB，无垃圾对象；大输出和编译缓存由既有`.gitignore`排除。代码、报告与测试
按明确文件列表提交，不执行git add全仓库，不改写历史，不回滚用户修改。本轮结果清单引用
的原始文件保留在磁盘，不将几GB MAT塞进Git。

仍可进一步节省空间的工作：逐个验证C40/60是否完全被C180或C200原始序列涵盖，同时
核对所有引用合同；只有生成替代摘要、校验哈希、更新只读审计依赖后才能删除。当前
candidate=0仅代表现有规则未命中，不等于所有18.98 GiB都已证明不可再压缩。

检查发现另一个项目的MATLAB进程，命令指向`Documents/New project/gx101r1/SciML`；
不是本工作区程序，未停止、未重启、未修改该任务。

## 7. 主线边界与下一步

C200仍是唯一冻结主线，结果SHA-256：
`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`；OP：
`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816`。
本轮不是新增20-cycle生产链，也没有重新阅读文献或宣称新增SCI图集完成。

下一项状态诊断应以真实完整OP作为未修改对照，保存候选公开Dataset写入前后的读回，
区分公开赋值生效、初始化再求解和两条控制器表示转换的影响；不要再重复已经失败的相同
目标初始化配方。每次使用新诊断目录，保持原命令时刻、物理参数及既有1474组门禁。

完整恢复通过后才进入守恒连接腔结构迁移，重新审计所有储能部件和边界源热流，处理
已观察到的C201单周期端点库存差额约-1.406 J，再推进Tc求解、敏感性、周期稳态和成对
Table 4工况。26.2 K零负荷与0.64 W/g零温升不是同一工况，仍需共同参数合同下分别验证。
本阶段只改进诊断证据，不能据此宣布完整系统COP、第一定律闭合或文献定量复现完成。
