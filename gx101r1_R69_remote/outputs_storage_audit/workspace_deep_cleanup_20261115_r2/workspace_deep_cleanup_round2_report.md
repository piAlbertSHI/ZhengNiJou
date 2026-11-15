# Agent5 工作区深度清理第二轮

## 范围

本轮只处理：

`C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合\gx101r1_R69_remote`

没有启动 MATLAB/Simulink，没有触碰其他 worktree、`New project`、`Agentheat2`、`Agent6`、保护中的主模型 SLX 或未确认目录。

## 实际清理

删除了 v40（C22）和 v41（C42 restart）的四个旧中间轨迹文件。它们不是字节重复副本，而是不同阶段的同结构观测记录；清理依据是：

- v40/v41 的 storage receipt 已将其标识为非生产恢复结果，且 `production_recovery_allowed=false`；
- 每个阶段仍保留 `cold_public_targets.mat`、`diagnostic_complete_operating_point.mat`、配置和 storage receipt；
- v43 C62 的同类原始 observations/state 作为最长代表性原始记录保留；
- 精确路径检索没有发现生产脚本直接引用，运行进程命令行也没有引用；
- 删除前完成 SHA-256 和 MATLAB 7.3/HDF5 结构核验。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `v40_storage_warmup_r2/native/observations.mat` | 1,077,726,286 | `BA06531B5311ED4C0788BAD446A2036D6F57C7CADABF160E49E48290202C0CA4` |
| `v40_storage_warmup_r2/native/diagnostic_state_observation.mat` | 752,530,073 | `A48EAE35A3B156706CE44B688B57C056C03D4F16447B4A94A44DE72A20361F63` |
| `v41_storage_warmup_from_C22_r1/native/observations.mat` | 1,069,520,964 | `1A4583092CBF35EF274170D7688793E6B4E272A80A34116D0E316E4DBB8F13B1` |
| `v41_storage_warmup_from_C22_r1/native/diagnostic_state_observation.mat` | 751,880,582 | `AC5B90AD7A3063794E8C58B3C46D7396E86F86CC5A5BB402E129D8E8A02D3825` |

本轮实际释放 `3,651,657,905` bytes，约 `3.400871 GiB`。runtime worktree 从 `37,434,232,396` bytes 降至 `33,782,574,491` bytes。

## 结构核验

- `observations.mat`：MATLAB 7.3/HDF5，9,469 datasets，51 个 shape 类别；v40、v41、保留的 v43 结构一致，但属于不同阶段记录。
- `diagnostic_state_observation.mat`：MATLAB 7.3/HDF5，528 datasets，30 个 shape 类别；v40、v41、保留的 v43 结构一致，但属于不同阶段记录。
- 保留的 v43 C62 原始文件及其 receipt 哈希在删除后复核通过。

## 保留与替代

保留的代表性原始文件：

`C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合\gx101r1_R69_remote\outputs\v43_storage_warmup_from_C42_r1\native\observations.mat`

`C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合\gx101r1_R69_remote\outputs\v43_storage_warmup_from_C42_r1\native\diagnostic_state_observation.mat`

每个被删除阶段仍保留 compact public targets、diagnostic OP/configuration 和对应的：

- `C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v40_storage_snapshot_20261014\storage_receipt.json`
- `C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v41_storage_snapshot_20261015\storage_receipt.json`

C200 `physical_simscape_result.mat` 未处理，仍是受保护的唯一性能基准。其他历史 raw MAT、其他 worktree 及未确认归属对象不因本轮结果自动进入清理。

## 工作树与 Git 核查

当前四个已确认 Agent5 worktree：

| Worktree | 当前占用 |
|---|---:|
| `fixed-stage4-kp237-endpoint` | 3.024863 GiB |
| `runtime-cv-json-contract` | 31.517957 GiB |
| `stage4-default-cold-diagnostic` | 1.406391 GiB |
| `stage4-phase-local-blend-diagnostic` | 54.375151 GiB |

`git worktree list --porcelain` 正常；`git fsck --full --no-progress` 退出码为 0，报告 194 个 dangling object 行，未执行 `gc`、`prune` 或 `clean`。本轮两个审计脚本和本轮清单已提交到 `faf8abd`；主工作树只剩既有保护性 `heatdrive_ecc_coupled_se21.slx` 修改和 `Agent6/` 未跟踪目录，未覆盖或回退这些保护项。

## 回执与清单

- [runtime 大文件清单](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2\runtime_cv_json_large_files.json)
- [精确白名单计划](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2\round2_runtime_cv_retirement_plan.json)
- [清理回执](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2\round2_runtime_cv_retirement_receipt.json)
- [第二轮收尾 JSON](C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2\workspace_deep_cleanup_round2_closeout.json)

## 下一轮

下一轮应先审查 `stage4-phase-local-blend-diagnostic` 中有明确 `HISTORICAL_*_RETIRED`、`COMPLETED_*_RETIRED` 和 storage receipt 的原始观测组，逐组保留一个最长代表性 raw 和一个最终候选；不得把本轮 v40/v41 的规则直接扩展到未核验的 physical result、C200/C100 或未确认 worktree。
