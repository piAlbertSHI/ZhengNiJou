# 第三十二阶段：C200 归档严格恢复与状态观测

日期：2026-09-07。

## 1. 结论及更正

C200 原始 OP 可以在其归档物理模型及原日志设置下严格恢复。本轮没有使用 checksum=warning、部分恢复或冷启动，也未改写冻结 OP。此前仅据不匹配设置的烟测而认为“C200 不能恢复”过于宽泛；现在应区分：

- 原归档模型：严格恢复及无扰动状态观测已获得实证。
- 当前增加观测支路的模型、拟加入管壁/守恒管的新模型：尚未取得状态迁移许可。
- 扩展 C200 的周期指令时域后继续 C201：本轮尚未检验。

测试范围是三个独立的 2000→2000.001 s 恢复探针，不是新增三个周期，也不是完成 C201。归档指令仍使用 C200 原时域；不得将末点后的一个采样步视为已正确执行下一整周期。
本轮不宣称整机能量闭合、outer solve、正交敏感性或 Table4 成对复现完成。

## 2. 冻结源和构建条件

原始结果 SHA-256：`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`。
原始 OP SHA-256：`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD7D17DA7F798EBAAF4816`。
原始代码提交：`e3f1dcfa85c1cad7dd7a6d257b7eb9fb8820ef7d`。

从 Git 仅提取39个归档代码/模型文件，ZIP 333487字节，未复制约5GB生产 MAT。
归档 SLX SHA 为 `F1D07FDE12F442AFB2F735D5A9A833269CF433437896E2096F23AE984575EA5E`，与 C200 checkpoint_meta 中的模型哈希一致。

第一次构建被旧 `merge_structs` 的非标量结构数组错误阻断，错误发生在 sim 之前，不是 OP 恢复失败。
在隔离源码副本中，仅补上与现主线一致的 `isscalar` 条件：标量结构递归合并，结构数组整体赋值。原始 ZIP 未修改；独立审核逐文件验证只有这一个明确的非物理补丁，其余38个文件保持原字节。

模型路径指向隔离副本，关闭模型持久保存。构建后 `geometry/material/branch/system/constitutive/schedule/fluid` 七组参数均与冻结 options 完全一致，包括热容、储液体积、PI 参数、温度和相变参数。未修改归档物理方程或 SLX。

归档模型实际 Simscape 日志为 all、LimitData=on、History=5000。执行时匹配原生产的 accelerator、ode3、1ms、关闭重复输出、保存完整 OP；内容和接口校验均设 error。

## 3. 试验与审核结果

| 证据 | 实际执行结果 | 使用边界 |
|---|---|---|
| archived_source_probe | 旧参数合并报 MATLAB:maxrhs，未运行 sim | 保留构建失败及堆栈定位 |
| archived_source_probe_v2 | 严格恢复到2000.001s，退出码0 | 当时采集器仅识别timeseries，未提取Structure With Time信号，不能单独证明物理连续性 |
| archived_source_probe_v3 | 严格恢复、提取161个物理信号和1240条原生轨迹 | 与冻结末点比较 |
| archived_source_probe_v4 | SaveState=on仍严格恢复；获得73组具名数值状态 | 与v3逐轨迹检验观测无扰动 |

v3/v4各自与原始 C200 末点比较382个物理通道，包括42节点温度、相分数/应力/应变/驱动力/相变速率、换热器/buffer温度、压力命令、路线流量以及全部冻结温度探针。所有比较的实际差异为零。

119个储能组件的1240条原生轨迹都包含2000和2000.001s两个样本，数值有限。
开启状态记录前后，161组物理信号+1240组原生轨迹共1401组对比，所有实际差异为零。
比较程序声明 atol=1e-10、rtol=1e-11，但本批并不是“勉强落在容差内”，而是读取到的值完全相同。

## 4. 真正获得的状态信息

原 C200 OP 的公开 loggedStates 为空 double，不代表内部没有保存状态。
开启 SaveState 的严格恢复后，得到73组、1376个数值通道，新的诊断 OP 公开 loggedStates 为 Dataset。

关键记忆包括：

- 本构 StateDelay：210维；SMA/SE温度延迟：各21维。
- SE Stage2 PI：2000s为 −0.0817081335599946。
- SE Stage4 PI：2000s为 0.021125855502860502。
- SMA PI：2000s为 0.02291105120628706。
- 四个独立前馈温度延迟、误差滤波器、热源/阀命令转换器状态均保留。
- Solver Configuration：995个封装通道，尚未建立逐通道物理语义映射，不能凭数组顺序迁移。

详尽首末值见 `c200_state_capture_v1.json` 的 all_registered_states；原生储能变量见两个 endpoint audit JSON 的 native_inventory。未来迁移应保留实际延迟状态，不应直接用同一时刻的本构输出替换 StateDelay，这两者具有不同采样语义。

MATLAB仍给出解释型本构块的通用警告，提示不保存解释型函数的persistent变量。实际活动函数 `HeatDriveECC_ConstitutiveStateVectorStep21`、兼容求解及初始化依赖中未发现persistent声明；210维状态通过显式Unit Delay传递。含persistent的旧并行热模型在归档构建函数中被删除。本轮保留该警告，并用实际轨迹比较补充证据，不把一次无差异观测当成所有隐藏状态跨结构迁移的证明。

官方接口边界：[ModelOperatingPoint说明](https://www.mathworks.com/help/simulink/slref/simulink.op.modeloperatingpoint.html)明确区分公开loggedStates与隐藏/Simscape状态；[工作点续算说明](https://www.mathworks.com/help/simulink/ug/model-operating-point-for-faster-simulation.html)说明结构与算法改变可能影响工作点兼容。因此新结构仍须独立验证，不能删除995个封装值后声称“完整恢复”。

## 5. 代码、结果包与独立验证

工作代码根目录：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote`。

新增程序：

| 文件 | 功能 |
|---|---|
| verification/Audit_HeatDriveECC_C200SourceRestore.m | 使用归档构建器和未编辑C200 OP，严格恢复并采集状态 |
| verification/Audit_HeatDriveECC_C200RestoredSignals.py | 从原始MAT末行独立比较382通道，检查全部原生轨迹 |
| verification/Audit_HeatDriveECC_C200StateCapture.py | 审核39个归档文件、观测无扰动和具名记忆覆盖 |
| verification/Audit_HeatDriveECC_C200SourcePackage.py | 源码增量、三项独立复算、清单哈希及存储审计 |
| verification/test_c200_endpoint.py | 端点匹配、重置差异、非有限/形状错误回归测试 |

原始证据根：`outputs_storage_audit/c200_source_compatibility_20260907`。
结果包：`outputs_storage_audit/c200_source_restore_release_20260907`。
完整源码仍采用第17阶段 source_snapshot.zip 加本轮直接基线 source_delta.patch，不叠加历阶段补丁。C200专用归档ZIP和唯一修补后的Defaults文件也在本轮证据清单中，物理源代码与原SLX可独立核对。

```powershell
$r = 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -X utf8 "$r\verification\Audit_HeatDriveECC_C200SourcePackage.py"
python -m unittest discover -s "$r\verification" -p 'test_*.py'
$out = Join-Path $env:TEMP ('c200_state_reaudit_' + [guid]::NewGuid().ToString() + '.json')
python -X utf8 "$r\verification\Audit_HeatDriveECC_C200StateCapture.py" --repo $r --output $out
```

第一条核验交付清单，第二条应通过146项测试，第三条独立核验归档补丁、1401组轨迹和状态覆盖，不运行长仿真。
新的长试验应使用新目录；本轮诊断OP继续标记DO_NOT_RESUME_FOR_PRODUCTION，不自动进入任何生产恢复解析器。

## 6. 存储与 Git

39个归档源文件约1MB级；未复制C200/C180大型MAT。
淘汰v2中已被完整观测证据替代的3,626,047字节诊断OP，删除前核对绝对路径归属和SHA，保留retirement_receipt.json、v2日志/审核，以及v3/v4必要信号和诊断数据。没有删除原始C200。
本轮精确工作区字节数、保留证据尺寸、源码提交、Git对象占用及每文件SHA由包内workspace_storage_snapshot.json和result_manifest.csv记录。原先失败证据与构建诊断均未覆写。

## 7. 全部既有 Qian 对标位置

完整本地路径、DOI及逐页用途见[本地文献精确定位与模型映射](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。本轮重新核对该索引和文件位置，不宣称重新全文阅读所有论文。
该索引中的C246数值是历史证据，不是当前恢复许可。以下页码均为该索引对应本地PDF页码。

| 文献 | 精确对照位置 | 作用 |
|---|---|---|
| Qian2019, Energy182, 881–899 | PDF3–5 Fig.1、Eq.1–10；PDF6 Table2；PDF15–17 Fig.13/Table4 | 唯一主定量合同；材料/拓扑/兼容/末10周期及成对端点 |
| Tan/Qian2020, Energy197,117261 | PDF6 Eq.1–2；7–9 Eq.5–16；18–20 Fig.9–10 | 机械兼容、热输入、质量比及效率边界 |
| Qian2015, IJR56,65–80 | PDF6–8控制体；7–9 Fig.6/Eq.28–30；10周期稳态 | 流体、水箱、管壁库存与周期定义 |
| Qian2017, Energy141,744–756 | PDF5 AER/管路；6稳态/网格；9–10 Fig.11/Eq.21–26 | 有限相变、匹配、库存和收敛 |
| Qian2015, IJR55,102–119 | PDF3–4 Fig.1–2；6–8回热效率；13–17参数影响 | 回热与附件敏感性 |
| Qian2023, ATE219,119540 | PDF3 Fig.1/Table1；4–5 COP；9–12循环比较 | 材料/循环/系统性能边界 |
| Qian2021, Applied Energy298,117269 | PDF4 Fig.1；4–5拓扑；10–13性能 | 热功–制冷级联，不能混入2019单效参数 |
| 2016 IJR64弹热综述 | PDF2–6定义；9–10集成；16–18回热 | 术语与系统范围 |
| Qian2015博士论文 | PDF92–110回热；131页后原型 | 原型背景，不替代定量合同 |
| 整机优化论文，DOI10.1016/j.energy.2017.05.008 | PDF5–12动态模型；15–19优化 | 整机边界与约束优化辅助证据 |

## 8. 下一步必须通过的门禁

1. 先在归档物理模型中声明并检验C201指令时域扩展，保留严格OP恢复；核对周期边界前后的物理状态、具名PI/本构记忆和指令，不能把本轮保持原时域的1ms探针当成有效新周期。
2. 为守恒管和有限壁状态建立明确状态合同。先识别995封装通道中哪些属于求解器历史、哪些对应真实物理状态；需要时使用公开Simscape状态初始化机制并逐项验证，禁止下标猜测或遗漏后默认初始化。
3. 完成新结构同状态短段及全周期核对，保留热容、buffer、本构、温度、相分数和PI历史；失败链不传播。
4. 然后继续全控制体、固定Tc外层求解、正交敏感性和共同参数/窗口的两个Table4端点。最终SCI性能图及复现结论必须建立在这些实际结果上。

本轮是恢复主线依据的实质进展，不是将最终目标改成“能启动一次仿真”。
