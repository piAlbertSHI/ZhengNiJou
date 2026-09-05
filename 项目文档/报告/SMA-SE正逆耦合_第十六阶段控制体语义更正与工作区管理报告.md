# SMA-SE 正逆耦合：第十六阶段控制体语义更正与工作区管理报告

日期：2026-09-06。本报告承接第十五阶段的实际 C180 -> runtime 观测 C200；不把 3 步诊断称为新一轮 20 cycle，不宣称完整目标通过。

## 1. 本阶段结论

已完成两个重要更正，二者均有模型源码和实际观测支持：

1. 旧四条 `*_buffer_T_K` 是罐的流体 A 端口温度，不是罐内原生 `T_I`。旧漂移数值仍有效，但原“内部 buffer 慢漂移”的解释过强，予以更正。
2. 全部 67 根管路都关闭动态可压缩性。其实际储能方程使用固定 `rho_nominal`，旧后处理却使用 `rho_I(t)*V`。变容罐还需明确压力体积功。旧 system-energy JSON 的通过值不能继续视为方程匹配的完整控制体闭合证据。

因此 C180 原始数据、OP 及严格恢复证据继续保留，**生产续算暂停，仅允许明确标记的库存诊断**。这不是发现了 OP 被重置；本次 3 步仿真严格恢复成功，无 checksum 降级，无诊断 OP 保存或传播。

第十四、十五阶段的原报告、图及代码 ZIP 保留为历史发布记录。本报告及总报告第 21 节是有效更正；不无痕改写旧结果。

## 2. 实际完成的工作

- 从 hash 验证的 C180 恢复，仿真 `1800..1800.003 s`，步长仍为 1 ms、ode3、accelerator、原生日志历史仍为 10002 点。没有改物性、控制参数、热容、buffer、相分数或 PI 状态。
- 列出 119 个实际原生储能元件：67 Pipe (TL)、4 Tank (TL)、2 Constant Volume Chamber (TL)、46 Thermal Mass。记录实际路径、库引用、原生变量单位、几何/热容参数表达式和值。
- 在同一次仿真的相同 4 个样本上比较四条工作区温度、原生 `A.T` 与原生 `T_I`，避免把终止点事件差异误当成状态不连续。
- 另建相同来源模型，仅只读导出实际模式和两套流体物性表，不做新的生产仿真。67 根管路均为 `dynamic_compressibility=false`；46 个 Thermal Mass 均为 constant。
- 建成逐元件 JSON/CSV 清单、短窗口能量/质量诊断工具、恢复用途守卫、更正覆盖审核 v3、Fig08 v2 和结果包审计脚本。

两次 native 诊断均正常退出。最终端口对照入口 PID 68904 退出码 0，stderr 空；元数据/守卫测试入口 PID 59192 退出码 0。没有停止或修改其他 MATLAB 工程。

## 3. 端口温度与内部温度

| 罐 | 旧工作区信号 | 与 A.T 最大绝对差 | 与内部 T_I 最大绝对差 |
| --- | --- | ---: | ---: |
| SHEXFluidBuffer | shex_buffer_temp_out | 0 K | 1.48885017227 K |
| HotFluidBuffer | hot_buffer_temp_out | 0 K | 0.000042752674 K |
| SMAHotFluidBuffer | sma_hot_buffer_temp_out | 0 K | 0.115934678426 K |
| ColdFluidBuffer | cold_buffer_temp_out | 0 K | 0.159446651343 K |

例如 1800 s 同次样本：SHEX A.T=`378.237566309 K`，T_I=`379.726416482 K`。这不是用两个不同运行的终止值相减，而是原生流体端口与内部状态的直接对照。

源码位置：`Integrate_HeatDriveECC_Constitutive21_Interface.m` 的 `add_sma_stage13_observability`、`add_tl_temperature_probe`；`Build_HeatDriveECC_EighthRound_Simulink_Model.m` 的 `add_sma_hot_buffer_temperature_probe`。`Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` 将这些工作区信号赋给旧 buffer 字段。原 raw 字段不改名、不重写，以保持其 SHA-256。

官方 [Pressure & Temperature Sensor (TL)](https://www.mathworks.com/help/simscape/ref/pressuretemperaturesensortl.html) 描述的是连接节点测量；[Tank (TL)](https://www.mathworks.com/help/hydro/ref/tanktl.html) 明确区分罐内部温度及流体入口。实际数值与源码连接共同支持上述更正。

## 4. 管路库存账本的问题

本机 MATLAB R2025b 可读源码：

`C:\Program Files\MATLAB\R2025b\toolbox\physmod\simscape\library\m\+foundation\+thermal_liquid\+elements\pipe.ssc`

在 `~dynamic_compressibility` 分支中，质量流入与流出相抵，能量积累为 `rho_nominal*V*du_I/dt`。名义密度由本域物性表在 `T_nominal,p_nominal` 上确定。与之匹配的管内模型库存应取固定质量 `M_model=rho_nominal*V`、`U_model=M_model*u_I`。

旧 `collect_fluid_inventory_energy` / `finite_volume_internal_energy` 计算的是瞬时 `rho_I*V` 及其与 `u_I` 的乘积。该值可以作为某种物性库存诊断，但不能代替当前准稳态压力元件的储能/质量方程。因此 C180/C200 旧 residual 或质量漂移虽低于数值限值，尚不能说明正确账本也通过。

官方 [Pipe (TL)](https://www.mathworks.com/help/simscape/ref/pipetl.html) 的名义温度/压力参数说明与上述本机源码一致。本次导出了两套物性表及每根管的名义参数，**尚未完成逐管物性域连接映射及 rho_nominal 数值重建**。不以路径名字或 995 维求解器数组顺序猜测。

旧门禁和 raw 没有修改。正确做法是生成独立方程匹配账本，保留旧账本对照，再决定是否更新生产输出合同；不是调高容限去覆盖问题。

## 5. 变容罐与其他热容边界

四个 Tank 是变体积库存，不能当作固定质量热容。短窗口工具同时列出 `delta(M*u)`、`integral(p dV)`、`delta(M*h)` 和端口净能量积分。常压下 `delta(M*h)=delta(M*u)+p*delta(V)`；该恒等式在本次各罐数据上残差约 1e-12 J，但这只是量纲和热力学恒等式检查，不是周期能量闭合。

ColdFluidBuffer 的 3 ms 窗口示例：压力体积功 `0.00944577231 J`；仅用 delta U 的残差 `0.0137013631 J`，计入压力体积功后为 `0.00425559076 J`。其他罐短窗口残差并非都改善至零。该窗口处于换向事件、仅 3 个步长，梯形积分与离散求解误差未分离，**不据此宣称完整系统已校正或通过**。

46 个 Thermal Mass 包括 SMA/SE 共 42 个固体节点、SHEX/HHEX/CHEX 3 个端点热容，以及 ColdLoadMass。`mass.ssc` 中大写 `M` 是热端口，不是质量数值；清单使用实际 constant 模式及 mask 的 mass/sp_heat。SMA/SE 潜热在本构热源账本中另列，不能重复计入显热块；ColdLoadMass 是否位于目标总控制体、是否与固定温度源断开，仍需拓扑审核。

## 6. Fig08 v2 逐面板说明

原运行目录内的新位置：`figures_state_audit_v2/Fig08_internal_state_observation.{png,pdf}`。旧 `figures_state_audit` 完整保留。

- (a) SMA PI：第 198/199/200 周期，保留最后终止点及“reset not commanded”注释。不是把终点尖峰隐藏掉。
- (b) SE stage 2 PI：独立路线记忆，三周期叠图，数值漂移仍以原 state JSON 为准。
- (c) SE stage 4 PI：另一条独立记忆，不与其他积分器混画。
- (d) 四个罐 **PORT** 温度的一周期滞后 RMS，明确写明不是内部罐温。原数值不变：SHEX 0.0344621 K、SE-HHEX 3.23399e-5 K、SMA-HHEX 0.0175657 K、CHEX 5.43990e-5 K。原始切片为 1900..2000 s；做 10 s 滞后后实际比较区间为 1910..2000 s。参考线只是原固体温度 RMS 上限，不是新增端口门禁。

PNG 为 600 dpi；PDF 经 Poppler 渲染，与 PNG 分别看图复核。图例、端点、文字及对数坐标未重叠或裁切，QA 绑定两文件哈希。只是技术可读性审核，不能称为期刊同行评审。

## 7. 代码与复核命令

新增 MATLAB：`Audit_HeatDriveECC_NativeInventoryProbe.m`、`Audit_HeatDriveECC_StorageModelMetadata.m`、`Assert_HeatDriveECC_InventoryRecoveryUse.m`、`Test_HeatDriveECC_InventoryRecoveryUse.m`。

新增 Python：`Audit_HeatDriveECC_NativeInventoryCatalog.py`、`test_native_inventory_catalog.py`。更新覆盖和绘图脚本，以 v3/v2 独立输出纠正语义；新增 `Audit_HeatDriveECC_InventoryCorrectionPackage.ps1`。

验证：相关 MATLAB checkcode 无问题，5 项恢复用途测试通过；真实 C180 默认生产解析器在模型构建前以 `HeatDriveECC:InventoryBasisUnderReview` 拒绝。原 10 项状态测试及新增 6 项库存/单位/缺失值/端口测试均通过。真实 119 元件输入解析完成，没有用合成测试替代实际观测。

以下只复核已有数据，不启动长仿真：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
$d = 'outputs_storage_audit\native_inventory_port_comparison_20260906'
$m = 'outputs_storage_audit\native_inventory_model_metadata_20260906\storage_model_metadata.json'
python -m unittest discover -s verification -p 'test_*state*.py' -v
python -m unittest discover -s verification -p 'test_native_inventory_catalog.py' -v
python verification\Audit_HeatDriveECC_NativeInventoryCatalog.py "$d\native_inventory_probe.json" --model-metadata $m --output "$d\native_inventory_catalog.json"
pwsh -File verification\Audit_HeatDriveECC_InventoryCorrectionPackage.ps1
```

更正图重绘命令：`python verification\Plot_HeatDriveECC_StateObservation.py --coverage "$d\internal_state_coverage_v3.json"`。重绘后的 PDF 哈希可能改变，必须重新看图并更新 QA，不能沿用旧 QA。

若需复现 3 步诊断，在 MATLAB 中执行 `addpath('verification'); Audit_HeatDriveECC_NativeInventoryProbe(<新的输出目录>);`。已有 probe MAT/JSON 禁止覆盖；新诊断不保存 OP。纯元数据入口为 `Audit_HeatDriveECC_StorageModelMetadata(<新的输出目录>)`。新生产长链暂不启动。

## 8. 结果包、溯源和存储

基目录：`C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote`。

- 原生对照与清单：`outputs_storage_audit/native_inventory_port_comparison_20260906`。
- 实际模式和物性表：`outputs_storage_audit/native_inventory_model_metadata_20260906`。
- 新代码完整 ZIP、逐文件 SHA-256 清单及包审核：`outputs_storage_audit/inventory_correction_release_20260906`。不复制多 GiB 的 raw 进入 ZIP，清单按原位文件封装。
- 生产 C180 -> C200 数据仍来自提交 `43def30`；本次小诊断在 `a6806b6` 基础的未提交工作树定义上执行，未在执行前冻结独立诊断源码快照。发布 ZIP 保留最终诊断定义及守卫修正，不能冒称它就是事前冻结的诊断执行提交。

C180 raw/OP、runtime 观测 C200 raw/OP/状态 sidecar、论文冻结 C200 均保持原位，不重写；历史 source_snapshot.zip 不覆盖。恢复权限的修改是新证据引起的用途限制，不是删除旧成功记录。

04:27 存储 dry-run：outputs **16.731 GiB**、候选数 **0**。清单为 `outputs_storage_audit/cleanup_candidates_20260906_042751.csv`，摘要同时间戳。本阶段新增的 probe MAT 约 5.78 MiB，属于有效证据而非淘汰大数据。不重复累计前阶段已释放的空间，也不把用户最初约 120 GB 的估计当成实测删除基数。

大型结果不入 Git；只提交代码、合同、报告及复核入口。代码 ZIP 和原位结果由 package manifest 绑定，Git 提交号及归档哈希写在 `source_snapshot_sha256.json`。

## 9. 下一步及文献边界

1. 以实际连接关系核对每根管所属流体域，从实际物性表及名义参数重建 rho_nominal；用原生 u_I 验证模型库存。不得仅以块路径猜测流体。
2. 对变容罐完整记录 T_I、mass、volume、p_I、u_I、h_I、各端口 Phi/mdot/Q；分开验证 delta U、压力体积功与传热。保留 ColdLoadMass 边界审核。
3. 先验证短分段严格 OP 续算与不分段轨迹在相同命令终止时刻的一致性，再用保持原日志历史设置的分段方式收集多周期原生库存。不得通过改变原生日志历史、部分恢复或重复冷启动拼出伪连续数据。
4. 元件账本及完整内部周期审核通过后，才能恢复生产权限、运行固定 Tc 外层求根、正交敏感性和 Table 4 配对端点。旧 C200 相分数 RMS=0.000400591810392 仍未通过 0.0004，任何本次语义更正都不改变这个失败。
5. 泵耗散、附件、步长/网格收敛及独立实验 validation 仍未完成。

Qian 文献精确位置仍以 `项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md` 为准。本阶段新增阅读/核对的是 MATLAB 元件官方资料与本机方程，没有声称新增读取全部 Qian 论文，也没有产生新的文献端点复现结论。
