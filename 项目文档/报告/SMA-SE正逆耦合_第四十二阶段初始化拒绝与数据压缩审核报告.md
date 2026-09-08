# SMA-SE正逆耦合：第四十二阶段初始化拒绝与数据压缩审核报告

日期：2026-09-08。主线目标保持不变；本轮没有宣称整机第一定律闭合或Table 4复现。

## 1. 本轮真实结果

- 新增一次真实MATLAB初始化开关对照，严格checksum拒绝，未传播失败种子。
- C40和C60两份旧raw完成精确数据压缩，原文件共2,509,754,297字节，约2.3374 GiB。
- 共同前缀引用现存C180；约6.25 MB的附加档保存全部旧元数据和原始终点。
- 两份临时重建MAT由真实MATLAB加载，全部五个顶层变量与旧raw分别`isequaln`相等。
- 两份旧raw和两份临时重建文件已删除；四份删除回执逐文件保存，未删除任何OP。
- 删除后压缩档校验、旧恢复包的新审计入口及第四十一阶段包链全部通过。
- 222项Python回归通过。工作区在11:21实测约16.67674 GiB，outputs约14.541 GiB。

这里的压缩是保留全部逻辑数据、元数据、类型和旧终点，不是保持MAT容器文件字节不变。
重建MAT有新文件哈希，原raw哈希只作为原始来源证据保留，不能冒称两者哈希相同。

## 2. 初始化开关试验：拒绝，不是新机制失败

源码`fb5bec62c933de721e430e0bb34c1d796d46cd66`；目录：
`gx101r1_R69_remote/outputs_storage_audit/seed_full_op_without_target_reinit_20260908`。
前台MATLAB启动一次，沿同一session 33477等待自然退出1，没有重启或改为部分恢复。

保持C200归档物理模型、196项目标、控制器表示、公开快照来源和2000.001至2000.002 s
窗口不变；只在种子生成后，将`SimscapeUseOperatingPoints`由on改为off，再加载完整种子OP。
196项种子保持性检查通过，但第一个续算臂即被完整工作点内容checksum检查拒绝，
`cases=[]`，没有续算观测MAT，也没有保存可传播的最终检查点。

错误说明该配置变化不满足本次完整工作点恢复合同。没有把checksum降为warning，
没有从头重跑替代热态续算，也没有修改原C200。这个结果不能用来断言原初始化目标
确实覆盖或干扰了完整OP，因为关闭开关的续算根本没有成功执行。

公开文档将Simscape OP描述为初始化目标集合，并说明应用目标后执行模型初始化。
这与Simulink完整OP续算不是同一个概念；本试验没有证明两者同时启用时的优先关系。
[MathWorks初始化说明](https://www.mathworks.com/help/simscape/ug/using-operating-point-data-for-model-initialization.html)

第四十一阶段的结论不变：真实完整OP原样续算及公开Dataset原值写回均1474组逐位一致，
但三个目标重建/日志派生方案仍有初始7组、一步197组超限，结构迁移尚未通过。

## 3. 为什么不能直接删除旧raw

旧中断恢复合同和历史文件清单仍引用C40/C60。逐块比较发现每份145条物理时序中，
50条与C180对应前缀全部逐位一致，另95条仅在旧结果最后一个采样点存在差异。

|旧结果|原文件字节|原样本数|末时刻|仅终点不同的标量数|
|---|---:|---:|---:|---:|
|C40|1,003,890,832|400001|400 s|179|
|C60|1,505,863,465|600001|600 s|177|

400 s和600 s以前的相应前缀均逐位一致。直接从C180截取到旧终点会丢失这些差异，
所以保留每条旧时序自己的最后一点，包括NaN及负零等原始位模式。
22条记录含非有限值，压缩按原样保存；压缩完整性通过不能替代科学有限性或能量门禁。

原始逐字段比较见`outputs_storage_audit/c40_c60_raw_prefix_coverage_20260908.json`。
首次、第二次压缩原型分别遇到HDF5属性引用和变长字段名哈希问题，均在复制审核时拒绝。
修正为按引用对象内容和变长数组内容哈希，并增加回归；未用Python内存地址充当数据哈希。
成功版本单独保存在`c40_c60_prefix_archive_20260908_v3`，没有覆盖两个失败原型。

## 4. 压缩档内容与核验链

每个`c40`、`c60`目录包含：

- `archive.json`：旧raw身份、145条时序的原始逻辑哈希、维度、C180引用和压缩文件哈希。
- `metadata.h5`：available_simulink_variables、options、provenance、summary和非时序physical元数据。
- `endpoints.h5`：145条旧时序的真实终点及属性。
- `matlab_header.bin`：用于生成兼容MAT文件的原始512字节头。
- `materialized_validation.json`：已完成的重建文件哈希、长度和逻辑校验记录。

核验先检查C180完整文件哈希，再逐块读取其共同前缀、补回旧终点，与旧raw对应145条
时序的原始逻辑哈希比较；元数据的对象引用、变长字段、类型和内容也单独验证。
缺少任意时序、修改来源或丢失元数据类别都会拒绝，不仅检查少数温度或最大误差。

随后实际重建两份MAT，源码`cbd32a9`下真实MATLAB逐变量加载比较：
available_simulink_variables、options、physical、provenance、summary，共10项全部通过。
MATLAB的`isequaln`核验结构和值，Python逐块哈希额外保护时序位模式。

共用C180 raw SHA-256：
`1E3A225BFEEE5D1798C66B926A7AAD9949E06463C6971930231D93F16BB96E6A`。
该文件现已加入存储管理脚本的显式必保留依赖，不能因旧或被标记淘汰而自动删除。

## 5. 清理与旧包审计迁移

清理入口：`verification/Retire_HeatDriveECC_ArchivedRawPrefixes.ps1`，源码`f8c859f`。
删除前检查实际MATLAB比较、压缩重建和旧包替代入口；随后再次核对每个目标的绝对路径、
非重解析点属性、大小及SHA-256，只删除明确列出的四个普通文件，不递归删除目录。

回执：`c40_c60_prefix_archive_20260908_v3/retirement_receipt_20260908_111450.json`。
实际删除总量5,442,159,767字节，其中2,509,754,297字节是旧raw，
2,932,405,470字节是本轮生成后验证完毕的临时MAT。不能把后者也说成对旧工作区的净节省。

C40/C60的原OP、C180原始结果与OP、唯一主线C200结果与OP均保留。
旧raw的容器已退役，旧C40/C60 OP不因此自动获得新的恢复权限。
旧清单保留为历史快照，新版`Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1`在旧raw
缺失时核验压缩证据，不拿重建文件的新哈希冒充旧哈希。删除后41项旧包审计通过。
新运行的附带C180审计写入新输出目录，避免继续改写旧审核结果。

## 6. 源码、结果包及运行验证

本轮发布目录：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/raw_retirement_release_20260908`。
其中包含源码基线提交、当前源码提交、直接Git二进制差分、测试日志、结果哈希清单、
科学范围声明与存储盘点。完整源码仍用既有54 MB基线ZIP加本轮直接差分，不复制多份仓库。
大结果文件只在清单中引用；恢复所必需的原始文件依赖也纳入哈希核验。

日常只读核验，不重跑MATLAB或创建巨大临时文件：

```powershell
Set-Location -LiteralPath 'C:\Users\86182\Desktop\正逆耦合'
python -X utf8 gx101r1_R69_remote/verification/Audit_HeatDriveECC_RawRetirementRelease.py
python -X utf8 gx101r1_R69_remote/verification/Archive_HeatDriveECC_RawPrefixes.py --verify
python -m unittest discover -s gx101r1_R69_remote/verification -p test_*.py -v
```

确需重新取得旧MAT逻辑数据时，运行以下命令；它只生成归档目录下的`restored_validation.mat`，
不覆写原raw路径、不替换C200、不提升恢复资格，并拒绝覆盖已有输出：

```powershell
python -X utf8 gx101r1_R69_remote/verification/Archive_HeatDriveECC_RawPrefixes.py --materialize 40
python -X utf8 gx101r1_R69_remote/verification/Archive_HeatDriveECC_RawPrefixes.py --materialize 60
```

重新生成的临时MAT存在期间，本轮发布审核中的“已清理临时文件”检查会按设计提示状态改变。
不要重复运行带`-Apply`的退役命令，它不是周期性轮询脚本。

## 7. 文献位置与边界

以下沿用既有逐页索引，本轮未冒称重新阅读全文；旧索引中C246的历史性能判定不作为当前
生产资格。完整文件路径、DOI、PDF页码及各篇允许用途见：
[Qian本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。

|文献|索引章节|关键PDF位置|本项目用途|
|---|---:|---|---|
|Qian 2019，A heat driven elastocaloric cooling system|2|3-5页Fig.1/Eqs.1-10；6页Table2；15-17页Fig.13/Table4|唯一Table4定量合同|
|Tan 2020，Thermodynamic cycle analysis of heat driven elastocaloric|3|6页Eqs.1-2；7-9页；18-20页|机械兼容与热驱动权衡|
|Qian 2015，Thermodynamics cycle analysis and numerical modeling|4|6-9页控制体；10页周期稳态|整机库存、附件、周期窗口|
|Qian 2017，Numerical modeling…phase transformation kinetics…matching principle|5|5-6页；9-10页Section3.3|动力学与匹配有效域|
|Qian 2015，Study on high efficient heat recovery cycle|6|3-4、6-8、13-17页|回热方向性及附件敏感性|
|Qian 2023，Thermodynamics of elastocaloric cooling and heat pump cycles|7|3-5、9-12页|材料/循环/系统性能边界|
|Qian 2021，Cascade utilization of low-grade thermal energy|8|4-5、10-13页|级联拓扑背景，不替代单效合同|
|2016综述，A review of elastocaloric cooling|9.1|2-6、9-10、16-18页|术语、系统集成、回热|
|Qian博士论文|9.2|92-110页附近；131页后|回热与原型背景|
|2017，Modeling and analysis of an integrated solid state…system|9.3|5-12、15-19页|整机模型及约束优化|

26.2 K零负荷和0.64 W/g零温升仍是两个不同边界工况，必须共同参数合同、共同多周期
窗口、全部机制门禁和成对端点同时成立，不能用当前固定Tc预测点替代。

## 8. 下一步与尚未完成

完整OP重建、守恒连接腔结构迁移、完整系统端点能量闭合仍未解决。
因此还不能进入合格域outer solve、正式正交敏感性、paired Table4 strict audit或最终论文主图。
本轮不改变原有约-1.406 J的C201完整周期库存差额，也不把局部KCL或旧标量门禁当成整机闭合。

已向负责人询问是否允许单独建立修正模型的冷态诊断链；没有答复前不启动、不重置原C200，
也不把独立冷态结果冒充热态恢复。当前仍可继续公开接口范围内的热态对照和已核验的数据治理。
