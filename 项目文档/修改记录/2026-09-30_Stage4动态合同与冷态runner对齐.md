# 2026-09-30 Stage4 动态合同与冷态 runner 对齐

## 本轮目的

把已在隔离诊断分支使用过的 Stage4 结构诊断开关纳入主线冷态 runner，避免后续实验依赖
手工 MATLAB 命令，并修复外部证据路径缺少 C200 freeze contract 时的 fail-closed 异常类型。

## 修改

- `Run_HeatDriveECC_ColdChamberDiagnostic.m` 增加并严格限制：
  - `se_stage4_endpoint_viscosity_blend_periodic`；
  - `se_stage4_commutation_precharge_fraction`，范围 `[0,1]`。
- `Audit_HeatDriveECC_ColdBufferCoupled.py` 在外部证据路径缺少本地 C200 freeze contract 时显式抛出 `ValueError`。
- 增加回归断言，确保两个开关不会绕过独立冷态和恢复禁止合同。

## 验证

- `test_cold_buffer_coupled.py`: 23 tests passed。
- `test_cold_chamber_diagnostic.py`: 5 tests passed。
- `test_stage4_controller_probes.py`: 8 tests passed。
- `test_cold_chamber_cycle.py`: 8 tests passed。
- MATLAB `checkcode(Run_HeatDriveECC_ColdChamberDiagnostic.m)`: passed。

Git commit: `6dbaafa Expose bounded Stage4 cold diagnostics`。

本轮没有启动新的长周期仿真，没有改变 C200、热容、buffer、本构、温度、相分数或 PI 状态，也没有把任何失败诊断包提升为恢复源。
