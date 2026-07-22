# 历史接口与未接入辅助函数

以下文件经 2026-07-22 静态调用、模型依赖和字符串入口联合审计，均不在当前
`Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` 执行闭包内：

- `Run_Simulink_Exchange_Hook.m`：旧 SE Stage 2/4 单阶段接口。
- `HeatDriveECC_BranchStorageJ.m`：未被当前 21 节点推进调用的储热辅助函数。
- `Initialize_HeatDriveECC_FiniteVolumeBranchState.m`：未被当前初始化链调用的旧辅助函数。

文件内容未改，只移动路径。当前正逆耦合模型仍保留全部 21 节点动态推进函数。
