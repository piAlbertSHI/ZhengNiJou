# round35 控制体合同与 Stage4 结构诊断

日期：2026-09-26

## 1. 本轮目的

本轮按《SE21_SMA-SE耦合_完整修改与审核报告》第八节推进。C200 继续作为唯一冻结的主线性能/恢复参考，
不重置热容、buffer、本构、温度、相分数或独立路线 PI 记忆。本轮不启动 20-cycle、outer solve、敏感性或 paired endpoint；
先修正诊断审计并复核控制体合同。

C200 冻结合同：

- `gx101r1_R69_remote/verification/c200_mainline_freeze_contract.json`
- physical result SHA-256：`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`
- `final_operating_point.mat` SHA-256：`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD5DD7D17DA7F798EBAAF4816`

冻结状态仍是 `mechanism=1`、`periodic=1`、严格 Table 4 reproduction=`false`。当前模型的完整 Operating Point restore
合同仍未通过 checksum，因此该文件是唯一主线参考，不授权把不匹配的状态直接注入新模型。

## 2. 控制体合同复核

现行合同为 `heatdrive_ecc_control_volume_contract_v2`，包括十个边界/库存：
SHEX source sensor、CHEX sensor、SHEX/HHEX/CHEX 流体节点、SMA、SE、SMA/SE route buffer、
finite pipes/manifolds、SMA/SE pumps；同时明确 Eq.9、Eq.10、泵功、系统热 COP、热一阶残差和闭环质量漂移。

合同文件：

`gx101r1_R69_remote/outputs_storage_audit/control_volume_contract_20260916_mainline/control_volume_contract.json`

结构审核重新通过：10/10 control volumes、10/10 metrics、末 10 个完整周期窗口、SE active mass
`0.04181683646625444 kg`。该结果只证明声明完整，不证明物理实现闭合。

实现审核使用 v4 独立冷态双臂证据：

`gx101r1_R69_remote/outputs_storage_audit/control_volume_contract_20260916_mainline/control_volume_implementation_audit_rerun_20260926.json`

结果为：

| 项目 | native | conservative |
|---|---:|---:|
| 初始坐标/局部库存/源端口 | 通过 | 通过 |
| endpoint residual | `-1.0716556489742288 J` | `2.313640834472608e-9 J` |
| endpoint inventory gate | 失败 | 通过 |
| seed/outer/paired eligibility | false | false |

native 残差主要来自 `Constant Volume Chamber (TL)` `-1.0131058255943324 J` 和 `Tank (TL)`
`-0.05854982417985445 J`，而不是 Pipe 或 Thermal Mass。这个差异是更高层的控制体/初始状态语义问题，
不能用放宽门限或增加 cycle 解决。v4 双臂仍是拒绝的冷态证据，不得作为恢复源。

## 3. v48/v49 Stage4 结构诊断

v48 在 runner 尚未允许 Stage4 bounded viscosity blend 时提前退出，保留为 `REJECTED_DO_NOT_RESUME`，
未进入模型计算。随后修复 allowlist 和 runner 合同，并在执行提交
`393be6f000d9421c159b8c191f6f2c65ac24c185` 上完成 v49。

v49 设置为 Stage2 `Kp=-126`、Stage4 `Kp=-50`、Stage4 endpoint viscosity blend `0.6`，从 v47 观测证据初始化，
未导入 C200，也未保存生产 checkpoint。v49 native/conservative 末窗口结果相同到报告精度：

| 指标 | v47 blend=1 | v49 blend=0.6 |
|---|---:|---:|
| 平均流量 kg/s | `0.00341166` | `0.00329655` |
| RMS 相对误差 | `8.2371%` | `6.2695%` |
| 最大绝对相对误差 | `11.8209%` | `11.0209%` |
| 积分质量相对误差 | `+6.6219%` | `+3.0239%` |
| 反向流 | `0` | `0` |
| 1 ms 交替模式 | false | false |

v49 仍未通过 Stage4 流量门禁，因此 `seed_eligible=false`、`outer_solve_eligible=false`、
`paired_table4_eligible=false`。这不是机制门禁自动失败，而是动态流量跟踪和前馈闭合尚未达到播种要求。

## 4. 审计工具修正

`Analyze_HeatDriveECC_Stage4FeedforwardCandidates.py` 修正为始终使用固定物性表中的参考黏度，
不再从当前 blend 的算术均值反推参考量；同时按实际 blend 验证当前公式。v49 v2 输出：

`gx101r1_R69_remote/outputs_storage_audit/stage4_blend060_kp50_20260926_v49_evidence/stage4_feedforward_candidate_analysis_v2.json`

native 的候选平均黏度比为：算术端点 `3.45949`、几何端点 `2.42393`、对数端点 `2.75985`、
算术温度黏度 `1.69380`。这些值只用于物理候选量级比较，不授权选择生产方程。

定向测试和 Python 编译通过；所有诊断输出保持 `diagnostic_only=true`，没有提高任何恢复或 Table 4 权限。

## 5. 下一步

下一轮应建立物理沿程黏度闭合的独立诊断：保留当前算术端点闭合作为对照，增加有等端点回退的
log-mean/distributed-route closure，并审计温度测点延迟、Pressure Source A/B、单位和控制相位。
该分支必须是新的隔离 10 s 双臂包；只有流量、压力、库存、能量和机制门禁同时通过，才允许进入 20-cycle。

不得把 v49 的改善直接写成 Table 4 改善，也不得宣称 `validated` 或 `reproduced`。

## 6. 存储与 Git

v49 原始双臂包约 `0.326 GiB`，审计回执放在
`gx101r1_R69_remote/outputs_storage_audit/stage4_blend060_kp50_20260926_v49_evidence/`。
v47/v49 失败或未达 seed 的包继续作为最近结构诊断证据保留；更早可再生且已被严格拒绝的 raw 不再作为恢复链。
C200/C180 继续受冻结合同保护。受保护的 `.slx` 二进制修改和顶层 `Agent6/` 不读取、不修改、不删除、不提交。
