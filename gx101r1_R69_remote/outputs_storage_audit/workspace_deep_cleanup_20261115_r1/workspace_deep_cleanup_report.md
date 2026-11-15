# Agent5 工作区分轮清理报告（2026-11-15）

## 范围与归属

本轮只处理 Agent5 当前线程 `019e9312-444b-7090-a68e-0888598c1598` 附着的四个工作树。`runtime-cv-json-contract` 实际是完整 checkout，和“runtime-cv-contract 为空”的描述冲突，因此该工作树没有删除任何文件。`stage4-positive-bias-diagnostic`、`stage4-pressure-bias-diagnostic`、`tmp/native_chamber_endpoint_run`、`tmp/independent_cold_v37` 均未清理。

| 工作树 | Git HEAD/分支 | 清理前 | 清理后 | 处理 |
|---|---|---:|---:|---|
| fixed-stage4-kp237-endpoint | `1ba3a32` detached | 3.025 GiB | 3.025 GiB | 仅删除可再生缓存 `583,770` bytes |
| runtime-cv-json-contract | `7f5516f` detached | 34.919 GiB | 34.919 GiB | 归属冲突，未删除 |
| stage4-default-cold-diagnostic | `94ed874` detached | 1.407 GiB | 1.407 GiB | 仅删除可再生缓存 `133,094` bytes |
| stage4-phase-local-blend-diagnostic | `de1abba` `codex/buffer-geometry-cold-diagnostic` | 55.097 GiB | 54.375 GiB | 失败分包原始数据和缓存 `4,202,423` bytes |

四个工作树合计从 `101,412,094,989` bytes 降到 `100,636,703,226` bytes，回收 `775,391,763` bytes（约 `0.72214 GiB`）。

## 已执行清理

1. 失败的 `v47_C62_recording_split_preflight_r2` 删除 3 个原始失败载荷，共 `770,472,476` bytes。
   - `mechanism.json` SHA-256 `9EB0CB7D4553CF2431183D86A7F79AD60CB611A480BD0B8CEAD79E2796A543A8`
   - `native/observations.mat` SHA-256 `5A35761579204BB98D104B5D0910BD9191139295C77D3CD9E5C2048C7364F845`
   - `observed_states.mat` SHA-256 `B5B1844CE0FECC2B337B837FC3D8000E90E1EEDDAB9B82639A5699156E577DD0`
2. 删除三棵确认工作树内可再生 `cache/codegen/slprj/simulink_cache`，共 `4,919,287` bytes；未触及 runtime-cv-json-contract。

失败门禁、`REJECTED_DO_NOT_RESUME.json`、`split_observation_preflight.json`、日志、配置和审计回执均保留。未删除任何 operating point、模型、代码、最终图、C200、论文汇总结果或 `retained_key_evidence_shared_*.h5`。

## 当前 C100 计算结果

最新独立诊断已完成 100 cycles，终端 OP SHA-256 为 `88C0F4DBB8BB01F8756336F48AC646B49D6285EEE42574D3041C1A037CBD3ADE`。流量子门禁通过，但温度 endpoint、temperature max 和 p99 仍未通过；因此 `periodic_steady_state=false`，outer solve、Table 4 和生产恢复均未授权。

## Git 与未处理项

`git worktree list --porcelain` 正常返回全部登记 worktree；四个确认工作树均 clean。`git fsck --full --no-progress` 未报损坏对象，但报告 192 行 dangling objects；未执行 `git gc`、`git prune`、`git clean` 或任何 Git 清理。主工作树受保护的 dirty SLX 和 `Agent6/` 未触碰。

详细机器清单：

- `workspace_ownership_and_space_inventory_pre_cleanup.json/csv`
- `workspace_ownership_and_space_inventory.json/csv`
- `file_retention_classification.csv`
- `round2_retention_classification_and_candidate_plan.json`
- `round2_retirement_receipt.json`
- `cache_retirement_receipt.json`
- `workspace_deep_cleanup_closeout.json`

下一轮必须先解决 `runtime-cv-contract` 与 `runtime-cv-json-contract` 的归属/命名冲突，再评估历史 v40/v41/v43 观测原始数据及其他 phase-local 候选；本轮不对这些未充分核验对象删除。
