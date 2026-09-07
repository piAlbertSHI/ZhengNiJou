# 第三十七阶段：C200热态目标映射与恢复边界审核

日期：2026-09-08。本文是状态迁移前置步骤，不是整机守恒修复或最终复现报告。

## 1. 实际推进了什么

上一阶段完整C201外部源端净输入30.208217647J，与119组件端点库存变化加pdV
31.614228137J仍差-1.406010490J。新增观测没有消除这个科学门禁失败。本轮没有
重跑旧周期、修改生产连接腔、删除失败证据或将诊断工作点纳入生产恢复链。

本轮完成：真实R2025b模型的公开初始化目标导出；目标与C200原生观测的名称、单位、
时刻匹配；非网络状态的独立MAT复核；热态候选目标的实际MATLAB保存/重载精确测试。
两个MATLAB程序自然退出0，checkcode未报告问题；181项Python回归通过。

## 2. 数量与含义

| 项目 | 实测结果 | 不能据此宣称什么 |
|---|---:|---|
| Prestart公开目标 | 2668 | 不是2668个独立动态状态 |
| 原生储能组件观测 | 1240 | 不是完整隐含求解器状态 |
| 精确名称和单位匹配 | 619 | 其余目标不可猜值补齐 |
| 有优先级的初始化目标 | 125，121 High、4 Low | Low可能在初始化中被调整 |
| 与C200热态不同的默认目标 | 123/125 | 默认初始化不能替代恢复 |
| 非网络注册状态 | 72组、381标量通道 | 记录完整不等于已经成功恢复 |
| 未解释的求解器向量 | 995通道 | 没有尝试猜测下标映射 |

全部125个有优先级目标均有C200具名原生观测。映射选用严格、未延长200周期命令
窗口的2000s首样本，不使用2000.001s端点，也不使用C201边界事件之后的状态。
另将72组注册状态逐项与既有MAT的两个时刻比较，防止只相信摘要中的数值。

## 3. 两种Operating Point不能混淆

R2025b本机`simscape.op.create.m`明确说明：`Prestart`更新模型并读取初始化前
目标；`Start`才请求初始化。当前在线文档已采用较新的`Target`名称，本轮使用
实际安装版本的`Prestart`。本轮没有请求Start或sim。

公开Simscape目标只规定变量值、单位和优先级，应用后求解器仍需执行初始化；
找不到对应变量的目标可能被忽略。因此必须先检验同一未修改模型的初始化结果。
参见[MathWorks初始化说明](https://www.mathworks.com/help/simscape/ug/using-operating-point-data-for-model-initialization.html)。

`Simulink.op.ModelOperatingPoint`还包含隐藏块状态、求解器和执行引擎状态；官方的
续算一致性描述以模型未修改为前提。不能把125个公开目标等同于完整工作点。
参见[MathWorks完整工作点说明](https://www.mathworks.com/help/simulink/slref/simulink.op.modeloperatingpoint.html)。

本次Prestart导出对象含private data；热态候选从空白公开对象构造，只写125个已核对
目标，不复制默认/private data。保存后重新加载，逐项核对名称、单位、数值、优先级，
全部精确一致。此处的serialization_pass仅指序列化测试通过，不指模型恢复通过。

## 4. 修改代码与结果位置

代码均在`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/verification/`：

- `Export_HeatDriveECC_StateTargetCatalog.m`：归档模型只读Prestart导出、参数不变检查、错误证据。
- `Audit_HeatDriveECC_StateTargetMapping.py`：保护C200哈希，独立匹配619目标、125候选与72组记忆。
- `Build_HeatDriveECC_C200TargetCandidate.m`：公开API构造、保存及重载验证；不启动模型。
- `test_state_target_mapping.py`：新增8项测试，覆盖缺失、重复、单位、时间、非有限值和优先级。
- `Audit_HeatDriveECC_StateTargetPackage.py`：独立重算、上一周期包递归审核、源代码补丁和文件哈希审核。

结果根目录：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/state_target_catalog_20260908/`

- `target_catalog.json`、`public_targets.mat`：实际模型默认目标，不能当热态恢复数据。
- `c200_target_mapping.json`：619对应关系、125候选、72组非网络记忆及明确缺口。
- `candidate/DO_NOT_RESUME_TARGET_CANDIDATE.mat`：只含初始化目标，不是生产OP。
- `candidate/target_candidate_audit.json`：125项重载验证及禁止恢复标志。

映射JSON SHA-256：`61E847FD8008CBEDEEB89A0D7736CA276A1A97E9434EA50D09C84505B32FE1D0`。
候选MAT SHA-256：`A4E88C6CDB603B82B9EF4A20F79C3444A3F36197A64F0A2F8C52427D279A1D59`。

## 5. 验证命令和完整代码

在PowerShell运行，不启动仿真，也不覆盖现有证据：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合'
python gx101r1_R69_remote/verification/Audit_HeatDriveECC_StateTargetPackage.py
python -m unittest discover -s gx101r1_R69_remote/verification -p 'test_*.py'
git status --short --branch
```

包目录`outputs_storage_audit/state_target_release_20260908/`中的`release.json`记录源代码
提交；`result_manifest.csv`列明全部必要文件的大小和哈希。完整代码沿用已有
`tl_inventory_release_20260906/source_snapshot.zip`加本包直接相对该基线的
`source_delta.patch`，不复制生产原始大MAT。缺少、改动文件或重算不一致都会报错。

## 6. 工作区与Git治理

本轮实测工作区约18.79GiB；新增目录约57.3MiB，含公开目标MAT、候选MAT和独立构建缓存。
本轮复制生产原始数据0字节、删除0字节。当前outputs约16.878GiB；现有治理规则dry-run
候选0，见`cleanup_candidates_20260908_044205.csv`及配套summary。

保留C200唯一主线参考、完整C201原始证据、失败/中断记录和独立审核链。旧C201与新增
源端C201的原有轨迹确实重复，但旧原始文件仍被多个独立审核器引用，不在缺少替代
解析合同和退休凭据时直接删除。本轮新增程序均隔离输出，不写归档物理源代码。

## 7. 下一步的准入条件

1. 在未改动归档模型上验证公开热态目标与72组Simulink状态的联合初始化。先确定公开
   状态导入接口保留时间、类型、采样与重置事件语义，不因初始化方便而把时间退到0。
2. 同时检查125个物理目标、72组注册状态、原生库存和控制事件前后观测。不能仅凭
   MATLAB退出0通过；任何温度/相分数/PI记忆变化必须定位，并保留拒绝证据。
3. 只有同模型重建通过，才测试两个连接腔的守恒状态变换；新增摩擦、壁体热容是
   明确物理变更，不通过填零壁温或修改全局库存来制造连续性。
4. 结构迁移、一步门禁、完整周期、十周期稳态依次通过后，才恢复固定Tc求解、敏感性、
   成对Table4边界与COP/SCP主线。原-1.406J差额不因本次映射通过而撤销。

本轮没有新增论文性能对比或重新阅读Qian全文。现有文献精确位置沿用主报告及
`项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md`；本轮新增依据是
MATLAB公开接口和实际模型目标。整机第一定律、结构恢复和Table4复现均仍未通过。
