# Stage4 settled-core 积分门控与审计时间轴诊断

日期：2026-09-30

## 目的

针对完整 20-cycle 审核暴露的跨周期路线 PI 记忆漂移，验证“仅在每个活动 Stage 的 settled core 内积分，同时保持 P 通道活动”的结构候选。该分支不导入 C200，不重置或替换热容、buffer、本构、温度、相分数或独立路线 PI 记忆。

## 修正与审计合同

- `a716fb3`：加入 Stage2/Stage4 settled-core I gate。
- `f91b31b`：将 P 通道与 I gate 分离，避免 settled mask 误关 P 反馈。
- `b72b979`：将 I gate 放到固定仿真时间轴，避免稀疏阀门 profile 吞掉 `+0.3/-0.3 s` 边界。
- `1cfc2e1`：修正 MATLAB `interp1` 的 logical 类型输入。
- `633721b`：修正构建审计对 P 稀疏时间轴和 I 固定时间轴的错误尺寸假设；审计在 P 轴重采样 I gate，不放宽科学门禁。

## 诊断结果

执行目录：`stage4_fixedgrid_settled_i_auditgrid_20260929_2cycle`。native arm 完成，observations SHA-256 为 `7D48CEF83C4B58C2EF7892768432FA9B7BCBFB2945E6FA1605A75178D6231731`；conservative arm 与根 execution contract 未完成，故 collection/scientific gate 均为 false，raw 包写入 `REJECTED_INCOMPLETE_TWO_ARM_COLLECTION.txt`。

native 仅作结构诊断：第 1 周期严格窗 RMS 相对误差约 `1.3457%`，最大绝对误差约 `4.8741%`；第 2 周期 RMS 约 `14.3375%`，最大绝对误差约 `37.2286%`，积分质量相对误差约 `-12.1953%`。I 状态已非零，说明固定网格门控实现生效，但跨周期性能劣于原始全阶段积分方案的第 2 周期 RMS `10.8985%`。因此该候选拒绝，不得进入 20-cycle seed、恢复、outer solve、敏感性、paired endpoint 或 Table 4。

## 审计合理性

本轮识别并修正了两个实现/审计层缺陷：logical 值不能直接作为 MATLAB `interp1` 采样值；以及审计不应要求 P/I 命令共享同一时间网格。修正后的科学门禁仍保持 `15%` 点值与 `5%` RMS，并未因候选失败而放宽。候选失败的剩余原因是控制目标、沿程输运和跨周期路线记忆的动态合同失配，不是该时间轴审计修正造成的误判。

## 后续

停止继续扫描该 settled-core 方案。下一结构诊断应直接审核“目标流量定义、入口测点、泵压力源和路线记忆状态”是否在同一输运延迟坐标中闭合，并同时输出 P/I enable、压力源 A/B、入口/出口流量、route integral 与控制体质量/能量账本。
