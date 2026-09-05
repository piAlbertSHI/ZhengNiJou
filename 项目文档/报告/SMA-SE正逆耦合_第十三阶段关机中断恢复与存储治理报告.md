# SMA-SE 正逆耦合：第十三阶段关机中断恢复与存储治理报告

日期：2026-09-05。工作分支：`codex/coupled-simscape-authority`。

## 1. 本阶段结论

本阶段不是 Table 4 最终复现。已识别关机中断、补齐 C60 审核、修复严格恢复审计与生产
配置不一致的问题、修复中间绘图开关，并保护有效检查点后清理旧数据。

- 新 runtime 冷启动链 C20/C40 已被原编排器接受，均机制通过但尚未稳态。
- C60 原始时序与完整 Operating Point 已在 2026-09-04 落盘；关机发生在后处理阶段，
  原进度表仍停在 C40。不能仅凭存在文件直接提升恢复状态。
- 2026-09-05 离线重审 C60：机制、三换热器 KCL、模型热残差和闭环流体质量均通过。
- 匹配生产配置后，C60 在新 MATLAB 会话中用 contents/interface=`error` 严格恢复成功；
  没有执行 warning 部分恢复探针。烟测只运行一个 1 ms 步，不是新的长周期结果。
- 恢复准备器再次通过父链、时间、原机制、能量/质量、严格恢复和前后 SHA 审核，生成
  `audited_recovery_contract.json` 与 `audited_recovery_settings.mat`。原 C40 状态文件未改。
- C60 `periodic_steady_state=false`，仅允许同参数暂态续算，不允许稳态外层插值或敏感性分析。

## 2. 中断时间线

| 本地时间 | 已证实事件 | 解释 |
|---|---|---|
| 2026-09-04 17:01 左右 | C20 接受 | 启动前声明 C1-C2 为采集期，C3 起使用原阈值 |
| 2026-09-04 18:47 左右 | C40 接受 | 20-cycle 分段、完整 OP 连续续算 |
| 2026-09-04 20:47:17 | C60 输出目录建立，raw/OP 落盘 | 后处理、标量审核和状态提升尚未完成 |
| 2026-09-04 21:00:28 | Windows System 1074 用户发起关机事件 | 与无 STOP、worker 消失及不完整后处理一致 |
| 2026-09-05 | C60 离线审核和跨会话严格恢复 | 未重跑 C40-C60，未修改物理状态 |

证据支持“关机中断后处理”，不支持把本次中断归类为机制失败。`Responding=true`、
CPU 累计值或旧进度文件也不能单独证明长链持续推进。

## 3. C60 数值审核

性能窗口为最后 10 周期 `500-600 s`；能量/质量窗口为最后完整周期 `590-600 s`，
`10001` 个样本。不同窗口的热流不能直接混算 COP。

| 项目 | C60 数值 | 判定 |
|---|---:|---|
| 全部机制门禁 | 1 | 通过；采集窗口 C3 起，阈值不变 |
| Eq.9 温跨 | 28.5275424536 K | 暂态预测，不是 zero-load root |
| Eq.10 冷量 / SCP | 13.1381101926 W / 0.314182307961 W/g | 最后 10 周期，沿用结果中 SE 质量基准 |
| 周期端点温度漂移 | 0.0158631093 K | 小于 0.05 K |
| 同相位温度 max / P99 / RMS | 0.262630 / 0.0436283 / 0.00989871 K | P99/RMS 通过，max 保留诊断 |
| 相分数端点漂移 | 8.65152e-6 | 小于 1e-4 |
| 同相位相分数 max / P99 / RMS | 0.0119812 / 0.00207742 / 0.000471679 | P99 超 0.002，RMS 超 0.0004 |
| periodic / near | 0 / 0 | 必须继续当前参数暂态续算 |
| SHEX / HHEX / CHEX KCL RMS | 1.7052e-13 / 3.2628e-11 / 0 W | 小于 1e-6 W |
| 外部净热输入 / 总模型储能率 | 3.11786316 / 3.27556536 W | 含流体、buffer、固体和潜热 |
| 模型热残差 / 相对值 | -0.157702197 W / 1.88695874e-4 | 小于 1e-3 |
| 闭环流体质量相对漂移 | 3.07676038e-6 | 小于 1e-5 |
| 寄生泵功 | 11.8422325 W | 仅报告，尚未热耦合 |

旧 summary 的 `heat_driven_system_COP=0.0159063211` 实际仅为 Eq.10 冷量与 SHEX 正向
源输入之比，字段名不构成完整设备 COP 授权。泵耗散及附件边界尚未完整赋值，
`complete_device_first_law_closure=false`，完整设备 COP 继续 withheld。

## 4. 严格恢复结论更正

旧恢复烟测没有匹配生产的 Simscape 日志上限、历史长度、SaveFinalState 和
SaveOperatingPoint。在同一 C60 raw/OP 上，旧配置失败，匹配生产配置后通过，文件哈希
不变。因此旧失败不能单独证明 OP 在生产配置下不可恢复。

证据目录：`gx101r1_R69_remote/outputs_storage_audit/shutdown_recovery_20260905`。
`c60_production_settings_strict_audit.json` 给出 strict/complete restore 为 true，
partial diagnostic 和 contents mismatch 为 false；旧失败 JSON 均保留，不覆盖历史。

第十二阶段对 C200/C246“当前模型绝对不可恢复”的概括也过强：二者尚未按本次匹配配置
分别重测，应表述为“当前续算未获授权”。C246 历史生产桥接确实使用过 warning 并出现
无效内部状态，这条独立风险仍成立。C60 通过不能自动恢复 C200/C246 资格。

完整 OP 含隐藏状态/求解器状态，日志配置可能影响接口兼容性，参见
[MathWorks 完整状态说明](https://www.mathworks.com/help/simulink/ug/save-state-information.html)
及 [接口校验说明](https://www.mathworks.com/help/simulink/gui/operatingpointinterfacechecksummismatch.html)。

## 5. 全部代码修改

源代码根目录：`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote`。

| 文件 | 修改与验收 |
|---|---|
| `Resolve_HeatDriveECC_FigurePolicy.m` | 模型 options 外解析绘图开关；只接受标量 true/false |
| `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` | 使用后处理开关，避免每段重复生成旧版图 |
| `verification/Test_HeatDriveECC_OutputOptions.m` | 默认/开关/非法值；两种开关下模型 defaults 完全相同；实际 MATLAB 通过 |
| `verification/Audit_HeatDriveECC_SavedResult.m` | 从完整 MAT 重建原审核输入，不仿真、不提升状态 |
| `verification/Audit_HeatDriveECC_OperatingPointRestore.m` | 匹配生产日志/状态配置；可选 warning 探针不得产生恢复授权 |
| `verification/Prepare_HeatDriveECC_InterruptedRecovery.m` | 父链、时间、机制、能量/质量、严格恢复、前后 SHA 通过才生成新目录恢复设置 |
| `verification/Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1` | 复核合同、原状态未改及 C60/C200/C246 哈希；生成原位数据清单 |
| `verification/Audit_FinalHeatDriveECC_Package.ps1` | v12 总包调用本阶段独立审核，纳入 C60 证据，并区分暂态恢复源与 C200 论文基准 |
| `verification/WaitAndCheck_HeatDriveECC.ps1` | 无 worker 且无 STOP 识别中断；计时前后 CPU 差与命令行进入一次性 JSON |
| `verification/Test_HeatDriveECC_MonitorTermination.ps1` | 旧目录不能掩盖中断；机制失败 STOP 保留原因；实际 PowerShell 通过 |
| `verification/Manage_HeatDriveECC_OutputStorage.ps1` | 未显式拒绝/替代的 raw/OP 默认保护；识别相对命令行中的本项目 MATLAB |

没有修改本构、换热参数、热容、PI 增益、物性域或周期稳态阈值；没有放宽 checksum 门禁。
新恢复目录仍接受原始状态流，不重置热容、buffer、本构、温度、相分数或路线 PI 记忆。

## 6. 完整结果包与哈希

结果包采用“原位数据 + 清单 + 审核代码”，不额外复制数 GiB MAT。以下路径相对于源代码根。

原链：`outputs/qian_coupled_runtime_strict_coldstart_gate3_20260904`。
C60 子目录：`qian2019_table2_table4_simscape_60cycle_20260904_204717`。
C40 子目录：`qian2019_table2_table4_simscape_40cycle_20260904_183855`。

```text
C60 physical_simscape_result.mat
91C799777FBF750E9803B7D6971AECA144099D7756B15B38FBDC6A2D22BA3E19
C60 final_operating_point.mat
67D7E1C38D4F83F06112D1B5042700ACE824ED76D1F56B4711D1AB61E4406E59
C40 physical_simscape_result.mat
80C12F151242EB9ED079319776AE45B2F835F9940A881954A8731A5A7B0D7DF1
C40 final_operating_point.mat
D8A49BD2EC81B8CBFF128F390AF68D2BE417BAFD002BBDDD2AB85DC34954E25A
```

已审核恢复目录：`outputs/qian_coupled_runtime_shutdown_recovery_from60_20260905`。
其中 `audited_recovery_contract.json` 和 `audited_recovery_settings.mat` 是恢复入口；
新日志/进度/状态均写入此目录，旧链 state 不改写。

本阶段包审核输出：`outputs_storage_audit/shutdown_recovery_20260905/package`。
`manifest_sha256.csv` 记录原位路径/大小/SHA；`package_audit.json` 区分包完整性通过、
机制通过、未稳态与未复现。清单不是独立可搬运压缩包。

总包 PowerShell v12 已纳入本阶段独立审核，不再把当前恢复源写成 none。
`Verify_FinalHeatDriveECC_Package.m` 继续管理历史 MATLAB 结果包；其中旧严格烟测只是
历史证据，不能替代本阶段配置更正后的恢复审核。

提交后的完整受 Git 管理代码/模型/文档快照为
`outputs_storage_audit/shutdown_recovery_20260905/source_snapshot.zip`，版本和哈希在同目录
`source_snapshot_sha256.json`。该 ZIP 不包含 `.git` 历史或 outputs 大数据；MAT 由上述
原位结果清单定位。这既给出完整代码快照，也避免重复占用大型原始数据空间。

## 7. 工作区与 Git 管理实绩

接手时工作区约 `13.6 GiB`，不是此前的 `120 GB`。此前多轮清理已经完成，不计作本回合释放。
本次清理记录：`outputs_storage_audit/cleanup_summary_20260905_175550.txt`。

- outputs 从 `12.923 GiB` 降至 `12.879 GiB`，删除 `52` 个旧图/密集 probe，共约 `0.044 GiB`。
- 最初 dry-run 为 51 项；离线审核另生成一个可重建 probe，最终 Apply 清单为 52 项。
- 保留 C200/C246/C40/C60 raw/OP；没有删除正在运行的 MATLAB 数据。
- 保留旧链报告、参数、cycle summary、日志、progress/state、拒绝说明、必要 JSON 与 SCI 图。
- Git 约 `0.06 GiB`，无垃圾对象；未使用破坏性 reset、历史改写或把多 GiB MAT 放进 Git。
- 未被显式拒绝/替代的 raw/OP 默认保护，不采用“白名单以外全部删除”。

审计可能再次产生可重建 probe，因此清理后的瞬时大小不是后续运行的永久上限。
代码/报告/合同/测试进入 Git，结果以原位 manifest 管理。

## 8. 负责人可执行复核

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
pwsh -File .\verification\Test_HeatDriveECC_MonitorTermination.ps1
pwsh -File .\verification\Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1
pwsh -File .\verification\Manage_HeatDriveECC_OutputStorage.ps1
git status --short --branch
```

清理命令默认只审计；无本工程 MATLAB 运行且已审核逐文件清单后才可添加 `-Apply`。
在本工程 MATLAB 空闲时，可运行以下复核；不要与活动长仿真争用同一模型：

```matlab
addpath(pwd); addpath('verification');
Test_HeatDriveECC_OutputOptions;
d = fullfile('outputs','qian_coupled_runtime_strict_coldstart_gate3_20260904', ...
  'qian2019_table2_table4_simscape_60cycle_20260904_204717');
r = fullfile(d,'physical_simscape_result.mat');
op = fullfile(d,'final_operating_point.mat');
a = Audit_HeatDriveECC_SavedResult(r);
e = Audit_HeatDriveECC_SystemEnergyResult(r,fullfile(d,'independent_energy_audit.json'));
s = Audit_HeatDriveECC_OperatingPointRestore(r,op,fullfile(d,'independent_strict_audit.json'));
assert(a.mechanism_pass && e.modeled_thermal_closure_pass && ...
       e.fluid_mass_conservation_pass && s.strict_restore_pass);
assert(~a.performance.periodic_steady_state);
```

恢复准备器拒绝覆盖已有目录，不要重复启动。正式监测使用唯一的 30 分钟定时命令：

完整续算入口如下，仅在没有同目录 worker、未开始该新链时使用；已运行时不要重复调用：

```matlab
S = load(fullfile('outputs','qian_coupled_runtime_shutdown_recovery_from60_20260905', ...
  'audited_recovery_settings.mat'),'settings');
state = Run_HeatDriveECC_LongSteadyContinuation(S.settings);
```

```powershell
pwsh -File .\verification\WaitAndCheck_HeatDriveECC.ps1 -WaitMinutes 30 `
  -OutputRoot "$PWD\outputs\qian_coupled_runtime_shutdown_recovery_from60_20260905"
```

计时期间不发“仍在运行”等窗口消息；保持同一回合挂在定时进程，JSON 返回后才检查。

## 9. 文献对比的具体位置

完整本地文件名、PDF 页码、DOI 与模型映射见：
[Qian 文献定位索引](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。
本阶段沿用已核对索引，不宣称重新读完 Zotero。页码均从本地 PDF 第一页起计。

| 文献 | PDF 位置 | 对比方法与限制 |
|---|---|---|
| Qian 2019, Energy 182, 881-899 | 第 5 页 Eqs.9-10；第 16-17 页 Table 4 | 同公式、质量基准、最后 10 周期；26.2 K 与 0.64 W/g 是不同端点 |
| Tan 2020, Energy 197, 117261 | 第 6 页兼容方程；第 7-9 页热输入和质量比 | 复核机械兼容和输入热边界，不替代瞬态解 |
| Qian 2015, IJR 56, 65-80 | 第 6-8 页控制体；第 10 页周期稳态 | 流体/管路/热容纳入审核，同相位漂移不只看端点 |
| Qian 2017, Energy 141, 744-756 | 第 6 页稳态/网格；第 9-10 页匹配原则 | 相变有效域及周期收敛通过后才比较性能 |

C60 非稳态且有正冷量，不能因储库温差恰为 26.2 K 就宣称 zero-load 已复现。
`28.53 K` 对 `26.2 K`、`0.314 W/g` 对 `0.64 W/g` 不是同边界复现误差，不能直接归因 UA。

## 10. 尚未完成与下一步

1. 先从已审 C60 OP 连续推进 20-cycle 分段，保持全部状态，达到原周期门禁。
2. 在严格恢复且稳态的 runtime 基线上，执行有界固定 Tc 外层求解；每点须通过机制、
   同相位周期、热/质量、物性域和完整恢复门禁。
3. UA、热容、buffer、库存、回热、相变做有效域正交敏感性；失败点不进入拟合。
4. 获得共同参数/窗口下 zero-load 与 zero-lift 两个端点，再作 paired Table 4 strict audit。
5. 完成泵功热耦合/附件散热、网格/步长收敛与独立 validation。
6. 稳态后生成正式 SCI 图、逐图解释状态/控制/能量和文献对照，形成论文工作图。

上述工作尚未完成。本阶段没有新生成可冒充最终稳态成果的 SCI 图集，没有宣称目标完成。

## 11. 后续更新（2026-09-06）

本报告所列 C60 续算已实际推进至 C180，六个分段机制通过，原已声明周期门禁通过并
正常 STOP；独立严格恢复再次通过。七图 v3、完整哈希、库存/buffer/PI 审核缺口和存储
治理见[第十四阶段报告](C:/Users/86182/Desktop/正逆耦合/项目文档/报告/SMA-SE正逆耦合_第十四阶段C180严格恢复基线与图集存储报告.md)。
上述下一步第 2 条应增加先决条件：全部内部状态周期审核未通过前，不得启动求根研究。
