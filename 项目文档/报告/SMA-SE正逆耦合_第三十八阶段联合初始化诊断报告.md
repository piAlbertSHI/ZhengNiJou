# 第三十八阶段：联合初始化实际试验与拒绝诊断

日期：2026-09-08。结论：取得热态及核心记忆保持的实际证据，但完整初始化一致性门禁未通过。
禁止生产恢复；不宣称连接腔守恒修复、周期稳态或Table4复现完成。

## 1. 本轮真正完成的工作

从上一轮125个公开热态目标出发，执行真实MATLAB初始化与一步试验，而非继续只做目录核对。
识别了R2025b中部分Dataset导入与Simscape目标初始化的冲突；用独立热质量/积分器模型
区分了五种接口组合。随后通过完整的目标种子ModelOperatingPoint及具名状态编辑，
在耦合模型上完成2000至2000.001s计算。

最后程序自然退出0；独立科学审核退出1。两者不是同一门禁。
186项Python回归通过，不等于完整物理状态恢复通过。

## 2. 全部试验与失败记录

以下目录均位于`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/`。

| 目录 | 结果及处理 |
|---|---|
| joint_target_initialization_20260908 | 仿真前因错误调用timeseries.copy退出1；不覆盖 |
| joint_target_initialization_20260908_v2 | 仿真前发现OP末状态与日志末样本不一致，退出1 |
| joint_target_initialization_20260908_v3 | 真正尝试部分Dataset联合初始化；2000s物性/液位断言失败，退出1 |
| joint_init_interface_isolation_20260908 | 建模端口名称错误，未仿真；后改为实际端口发现 |
| joint_init_interface_isolation_20260908_v2 | 两个控制成功；部分Dataset案例因重复InitialState配置未执行 |
| joint_init_interface_isolation_20260908_v3 | 排除配置错误后，部分Dataset案例触发绝对零度断言 |
| joint_init_interface_isolation_20260908_v4 | 加入完整Dataset，仍失败；不猜测封装下标 |
| joint_init_interface_isolation_20260908_v5 | 完整种子OP加公开积分器状态编辑成功；两个Dataset反例仍保留失败 |
| joint_target_seeded_op_20260908 | 种子热态123/125通过，两个连接腔压力失败；未传播种子 |
| lag_state_space_equivalence_20260908 | 101点真实Transfer Fcn/State-Space状态及输出精确一致，退出0 |
| joint_target_controller_seeded_op_20260908 | 125个种子目标通过；一步程序退出0，但独立比较拒绝 |

各次改变均先定位前次退出原因；未重复启动仍存活的进程，未取消健康MATLAB。
本轮没有新增自动监测、计时程序或生产检查点；所有等待均复用实际会话直到自然退出。

## 3. 接口根因及对照结果

R2025b新进程在未加载Simulink时第一次读取诊断OP，可能得到空的loggedStates；独立
进程验证先`load_system('simulink')`后可在首次加载得到73组Dataset。代码显式初始化
Simulink并检查类型、数量。73组值类副本测试证明Data/Time赋值未改变来源模板。

实际OP末状态并不总等于同刻观测日志：42个ConstitutiveHeatPS转换器存在差异，求解器
封装状态也有差异。因此OP仅作为具名类型/形状模板，候选值依然取2000s观测，不混用端点。
这些差异完整保存在`template_vs_logged_final_differences`中。

独立热质量模型的五组对照如下。失败不会被记成通过：

| 初始化路径 | 热质量目标340K | 积分器目标 | 结果 |
|---|---:|---:|---|
| 仅Simscape目标 | 340K | 默认0 | 通过 |
| 目标+部分Dataset | 绝对零度断言 | 请求7.25 | 失败 |
| 目标+块初值 | 340K | 7.25 | 通过 |
| 目标+种子完整Dataset | 绝对零度断言 | 请求7.25 | 失败 |
| 完整种子ModelOperatingPoint+公开记忆编辑 | 340K | 7.25 | 通过 |

官方说明完整ModelOperatingPoint包含隐藏块状态、执行引擎状态；Dataset不能替代这些数据。
参考[MathWorks工作点限制](https://www.mathworks.com/help/simulink/ug/model-operating-point-for-faster-simulation.html)。
这里是本机隔离试验结果，不把它推广为所有MATLAB版本/模型的通用结论。

## 4. 控制器初态与两个压力偏移

仅热态目标生成的种子保住123个目标，但两个连接腔压力分别由C200的
1.0054184560213255MPa和0.8266805616241467MPa变为1.017380915822736MPa及
0.8147181018227361MPa，偏移幅值0.01196245980141MPa。门禁未放宽，种子未用于续算。

下一次构造明确使用12组测得的核心控制/本构状态：7个Unit Delay、3个积分器及2个误差
滤波器。Transfer Fcn不能直接设置非零块初值，故仅在诊断模型中将两个误差滤波器
替换为同一可控标准型State-Space；没有改写归档SLX。该实现变化已明确记录，并非严格
从原C200 OP恢复。参考[Transfer Fcn初始条件说明](https://www.mathworks.com/help/simulink/slref/transferfcn.html)。

实际tau=0.002s，tf2ss给出A=-500、B=1、C=500、D=0。独立非零初态
x0=-3.379561321780173e-6、正弦输入、ode3及0.001s步长，101点状态和输出最大差均为0。
因此保留原状态坐标，不把滤波器状态误当成滤波器输出。

## 5. 最后一次试验：通过与未通过必须分开

执行源提交：`af77e234e9b11a40fc5063f48f8e0499556e3e60`。
种子125/125热态目标通过；72组具名状态替换在新种子OP上执行，未编辑原C200 OP。
最后比较保持先前1e-10绝对项加1e-11相对项的数值界限，没有提高容差。

- 125个热态目标：初始全部通过。
- 12组核心控制/本构记忆：初始和一步后均全部通过。
- 全部1474组观测：初始49组不通过、一步后197组不通过。
- 初始精确相同622组，一步后精确相同268组；其余必须根据原门禁判断，不能算作精确相同。
- 42个热流转换器的典型日志由参考[1,0]变为[0,0]（第一通道两个时刻），第二通道均为0。
- 非转换器初始差异包括SMA流量6.0233e-9kg/s、连接腔端口能流8.6080e-7kW。
- 一步后最大温度差约1.1470e-7K；这些小数值不自动推翻严格不一致结论。

读取原C200转换器完整块工作点的公开get接口返回CannotFindSimStateForBlock；不得
改动受保护内核、可见性或封装向量下标来绕过。下一步需解释转换器日志与运行状态
的语义，并检验其对开关瞬间/热量积分的影响；不能直接删除这42组比较。

没有保存最后失败门禁分支的final_operating_point.mat。仅保留观测、输入、参数和审核结果。
原C201周期-1.40601049J库存差额不受本次目标保持结果改变；完整系统闭合仍未通过。

## 6. 代码、结果包与复核

新代码在`gx101r1_R69_remote/verification/`：

- Run_HeatDriveECC_TargetInitializationProbe.m：有界探针，显式区分部分Dataset、完整种子OP及控制器初值模式。
- Audit_HeatDriveECC_TargetInitialization.py、test_target_initialization.py：完整1474组比较及5项新增回归。
- Test_HeatDriveECC_TypedStateCopy.m：73组类型、形状、值类隔离测试。
- Audit_HeatDriveECC_JointInitializationIsolation.m：五种路径的对照及保留失败证据。
- Test_HeatDriveECC_LagStateSpaceEquivalence.m：非零初态标准型等价性真实仿真。
- Apply_HeatDriveECC_ObservedControllerInitialState.m：10处显式初值和2处已核验标准型替换。
- Audit_HeatDriveECC_JointInitializationPackage.py：包完整性、先前包递归复核、独立科学结果重算。

不启动仿真的包审核与回归命令：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合'
python gx101r1_R69_remote/verification/Audit_HeatDriveECC_JointInitializationPackage.py
python -m unittest discover -s gx101r1_R69_remote/verification -p 'test_*.py'
```

包目录`outputs_storage_audit/joint_initialization_release_20260908/`保存release.json、
result_manifest.csv、python_tests.log、storage_snapshot.json和直接源代码差分source_delta.patch。
完整代码仍用已冻结的`tl_inventory_release_20260906/source_snapshot.zip`加直接差分重建，
不重复复制生产MAT。包审核通过仅表示证据完整，`scientific_initialization_gate_pass=false`
必须保留。重新运行科学审核并输出新文件，应返回退出1；不得覆盖已有独立审核JSON。

## 7. 存储与后续主线

本轮全部试验原始观测和失败日志合计约26.4MiB，未复制生产大MAT、未删除原恢复依据。
工作区仍约18.82GiB；准确字节数及Git对象占用以包中的storage_snapshot.json为准。
试验目录隔离构建缓存，不把缓存列入科学必需文件；不为了腾空间删除尚无替代合同的证据。

优先工作依然是连接腔守恒模型的可信状态迁移及整机第一定律，不是先推进失败点的Tc插值。
通过接口语义和物理迁移审查后，再执行新连接腔的一步/完整周期/十周期稳态门禁、固定Tc、
正交敏感性及共同参数的成对Table4边界。本轮没有新增文献性能对比；Qian位置沿用主报告
及2026-09-03文献精确定位笔记，不宣称此次重新阅读了全部文献。
