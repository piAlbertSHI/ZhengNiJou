# Agent5 工作区深度清理第三轮

## 范围

本轮只处理：

`C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote`

未处理 runtime-cv-json-contract、fixed-stage4、stage4-default、positive-bias、pressure-bias、New project、Agentheat2、Agent6 或任何未确认目录；未启动 MATLAB/Simulink。

## 实际清理

本轮只删除 v55 的 C44-C52 原始 observations/state 文件，共 10 个文件：

`v55_runtime_Tc276p85_precision_fromC40_r2/packet_C044_attempt01`

`v55_runtime_Tc276p85_precision_fromC40_r2/packet_C046_attempt01`

`v55_runtime_Tc276p85_precision_fromC40_r2/packet_C048_attempt01`

`v55_runtime_Tc276p85_precision_fromC40_r2/packet_C050_attempt01`

`v55_runtime_Tc276p85_precision_fromC40_r2/packet_C052_attempt01`

每个 packet 的 `observations.mat` 和 `observed_states.mat` 均在删除前完成 SHA-256。它们均为 MATLAB 7.3/HDF5；observations 文件包含 9,359 datasets、46 个 shape 类别，observed_states 文件包含 527 datasets、30 个 shape 类别。

删除依据：

- v55 有 `COMPLETED_RAW_PREFIX_RETIRED.json`、`collection_result.json` 和已完成的 raw-prefix retirement receipt；
- v55 的 storage receipt 已保留 compact collection/progress/recipe 证据；
- 每个被删除 packet 的 `cycle_physical_summary.csv`、`stage_temperature_probes_50samples.csv`、`packet_manifest.json` 均保留；
- 精确脚本路径检索和运行进程命令行均无引用；
- v56 同周期相邻参数分支的 10 个原始文件已哈希并完整保留，作为代表性 precision raw 结果。

本轮释放 `2,255,273,364` bytes，约 `2.100387 GiB`。该 worktree 从 `58,316,082,803` bytes 降至 `56,060,809,439` bytes。

## 未处理候选

以下候选只完成了清单和凭证定位，没有扩大删除：

- `v71case3`：最大 sensitivity 候选，未见同等明确的退休凭证，保留；
- `v65c1`、`v70case2`、`v66_sensitivity_nominal_20261017`、`v68r2`、`v64c1`：存在 compact 或历史标记，但各自 raw 分段和代表性关系仍需单独核验；本轮不删除；
- `v61c1`、`v48_native_recording_C64_C72_r1`：有 collection/compact 证据，但没有纳入本轮精确白名单；保留。

## 保留代表性结果

保留：

`C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v56_runtime_Tc277p05_precision_fromC40_r1`

其 C44-C52 raw observations/state 文件全部保留并在删除后重新复核哈希。所有代码、模型、compact summaries、temperature probes、packet manifests、审计回执和其他候选组未触碰。

## 回执与核查

- [阶段大文件清单](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r3\phase_local_blend_large_files.json)
- [第三轮计划](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r3\round3_retention_plan.json)
- [清理回执](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r3\round3_phase_local_retirement_receipt.json)
- [删除前凭证](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r3\round3_predelete_evidence.json)

下一轮建议继续从 v65/v64 这类明确 phase rejection 且已有 compact archive 的组中，先选一组完成同样的文件级核验；不要直接按目录名批量删除 v71 或任意 sensitivity raw。
