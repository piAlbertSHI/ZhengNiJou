# 2026-09-30 Stage4 launcher 参数合同

## 修改

`Start_HeatDriveECC_IndependentColdDiagnostic.ps1` 现在显式接受并写入 execution contract：

- `Stage4PrechargeFraction`，限制为 `[0,1]`；
- `Stage4BlendPeriodic`，布尔类型。

两项参数同时传递给 MATLAB runner 的 `diagnostic_branch_overrides`，避免 launcher、MATLAB
函数和审计 JSON 三者不一致。

## 验证边界

本轮只做 PowerShell 语法解析和静态合同检查，没有启动新的 MATLAB 仿真。参数仍属于独立
冷态诊断，不改变 C200，不导入恢复状态，不授权 20-cycle、outer solve 或 Table 4。
