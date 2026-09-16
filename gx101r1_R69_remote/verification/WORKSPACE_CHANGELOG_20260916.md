# Workspace Change Summary and Storage Closeout

## Git state

Branch: `codex/conservative-chamber-cold-diagnostic`.

Recent tracked milestones are already committed in Git:

- `3456f23` consolidated the prior modification history and storage policy;
- `428d067` retired archived obsolete outputs and rebuildable cache;
- `f2b0496` audited C200 control-volume evidence before any outer solve;
- `1423807` recorded the C200 evidence snapshot;
- `3fecedd` exposed explicit control-volume rejection reasons in the outer guard;
- `25bd47b` extended observation evidence and cleanup records;
- `3827fbf` mapped native TL energy flows and Tank single-port topology;
- `13cd1cb` recorded native Pressure Source child IDs.

The frozen C200 result and checkpoint remain the only recovery authority. The
untracked parent-level `Agent6/` directory is unrelated to this repository and
was not read, moved, deleted, or committed.

## Code and scientific boundary

The observation layer now records finite SHEX/HHEX/CHEX fluid signals, SMA/SE
solid states, buffer inventories, pipe/manifold inventories, native Pipe
`mdot_A`/`mdot_B` and `Phi_A`/`Phi_B`, and native Pressure Source child IDs.
The v6/v7 one-cycle cold smoke packages both remain `mechanism_failure`, with
`periodic_steady_state=0`, `current_cycles=0`, and `pumps=partial`. Neither is
an Operating Point or a valid input for C200 recovery, outer solve,
sensitivity, paired endpoints, or Table 4 claims.

## Storage classification

| Class | Treatment |
|---|---|
| Frozen C200 result, checkpoint, freeze contract | Hash-lock and retain |
| C180 restricted reference and audit evidence | Retain; no deletion without a separate contract |
| Observation summaries, validation reports, contracts, state/progress files | Retain for reproducibility and diagnosis |
| v6/v7 rejected raw time-series MAT and failed checkpoints | Retire only after SHA-256 and strict evidence audit |
| `Agent6/` | Leave untouched and outside this repository |

The v6/v7 retirement manifest is
`outputs_storage_audit/c200_control_volume_observation_v6_v7_retirement_20260916.json`.
The package-level rejection markers prevent accidental resumption. The actual
deletion is performed only by `Manage_HeatDriveECC_OutputStorage.ps1`, which
checks for active MATLAB references and preserves the frozen C200 raw files.

The applied receipt is
`outputs_storage_audit/cleanup_summary_20260916_023522.txt` with candidate list
`outputs_storage_audit/cleanup_candidates_20260916_023522.csv`: six explicitly
listed v6/v7 files, `120,652,798` bytes, were deleted; outputs fell from
`12.044283 GiB` to `11.931917 GiB`. The post-cleanup check confirmed all six
targets are absent, while the frozen C200 hashes remain
`0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD` and
`FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD5DD7D17DA7F798EBAAF4816`.

The post-cleanup workspace classification is recorded under
`outputs_storage_audit/workspace_governance_20260916_post_cleanup/`: 599
directories and `16.068590 GiB` classified, with both C200 and C180 authority
hash sets passing and `untracked_Agent6_untouched=true`. The governance script
was made runtime-compatible by using URI-based relative paths instead of a
runtime-dependent static `GetRelativePath` call.

## Gate still open

The remaining control-volume deficiency is the pump inlet/outlet pressure
cross-check. The native Pressure Source log exposes `A`, `B`, `P`, `Phi_A`,
`Phi_B`, `mdot_A`, `mdot_B`, `power`, `q_A`, `q_B`, `rho_A`, and `rho_B`, but
not `p_A` or `p_B`. Commands or a duplicated proxy pressure are not valid
substitutes. The next permitted diagnostic is an independent cold model with
named two-port pressure sensors, followed by a one-cycle smoke and strict
re-audit.

## v8 follow-up

The v8 diagnostic completed that permitted pressure-probe smoke. All three
pressure sources now have finite named A/B signals, and the hydraulic-power
cross-check is complete. The one-cycle run still fails the mechanism and
periodic gates, so it is diagnostic evidence only and is rejected for
recovery or Table 4 use. Its strict evidence contract is
`outputs_storage_audit/c200_control_volume_evidence_v8_20260916/`; the raw
MAT and dense probe data are eligible for retirement after hashing.

## Pre-cleanup Git and workspace consolidation

The current branch remains `codex/conservative-chamber-cold-diagnostic`.
The next tracked change records the segment-observation/checkpoint-merge
implementation in `Run_HeatDriveECC_EighthRound_Simulink_Cycles.m` and the
corresponding modification summary in
`项目文档/报告/2026-09-16_前序修改汇总与工作区治理.md`.

The working tree also contains an uncommitted binary change to
`heatdrive_ecc_coupled_se21.slx` (current SHA-256
`77E2ACD5B983A0BA72DFB72D3AD106F4D0BC524C2EC56C79C096EEBB5DA88599`; Git
baseline object `7b7afea69c0ff1b547592f96f02498e3f487aa33`). It is deliberately
left unstaged because the diagnostic probe contract says instrumentation is
in-memory only and no provenance currently explains a saved-model change.
The file is preserved, not reverted or overwritten. `Agent6/` remains outside
the repository and untouched.

The authoritative C200 hashes and the v8 rejection boundary remain unchanged.
Before any output deletion, the storage manager must generate an audit-only
candidate list; only explicitly rejected or superseded raw artifacts may then
be applied for cleanup. No cleanup is allowed to remove the frozen C200/C180
dependencies or any result that has not been assigned a replacement contract.

## Round-two classification

`Audit_HeatDriveECC_WorkspaceGovernance.ps1` completed at
`outputs_storage_audit/workspace_governance_20260916_round2/`: 606 directories,
`16.068887 GiB` classified, C200/C180 hash checks passed, and
`untracked_Agent6_untouched=true`. The standard output-storage manager found
zero new candidates. The specialized retirement contracts were rechecked and
reported their targets already retired: 8 cold-tuning files (`1.236441 GiB`),
2 rejected 124/225 files (`0.309055 GiB`), and the 2 non-authoritative runtime
physical/OP files (`5,020,592,058` bytes). The C40/C60 prefix retirement audit
also completed with a passing compact recovery package and no production or
Table 4 promotion.

No additional deletion was applied in this round. The largest remaining
diagnostic raw packages (v13, 120/225, and 125/225) remain explicit dependencies
of the existing cold-state comparison reports and therefore require a new
replacement contract before removal. Historical directories without an exact
retirement contract remain classified as pending review.

## C200->C201 contract audit

The canonical model in the main worktree has an unexplained uncommitted binary
change and therefore cannot be used for strict C200 continuation. An isolated
worktree at `tmp/c200_continuation_worktree` uses the model from Git `4df0ab9`,
whose SHA-256 matches the C200 checkpoint:
`f1d07fde12f442afb2f735d5a9a833269cf433437896e2096f23ae984575ea5e`.

The new read-only `Audit_HeatDriveECC_CheckpointContract.m` completed a
checkpoint/current, prior/current, and time-continuity comparison with all three
passing. The JSON result is
`outputs_storage_audit/checkpoint_contract_diff_c200_c201_20260916.json`.
The compatibility fix strips the legacy non-state configurability metadata and
rebinds only the prior options' model-path metadata to the verified worktree
model; no plant or state parameter is relaxed, and no Operating Point is
imported by the audit.

## Round-three audit-only decision (2026-09-16 04:43)

After confirming that no MATLAB process referenced `gx101r1_R69_remote/outputs`,
`Manage_HeatDriveECC_OutputStorage.ps1` was run in audit-only mode. The output
root was `11.932 GiB`; `candidate_count=0`, so no deletion was applied. The
candidate CSV and summary receipt are:

- `outputs_storage_audit/cleanup_candidates_20260916_044231.csv`
- `outputs_storage_audit/cleanup_summary_20260916_044231.txt`

`Audit_HeatDriveECC_WorkspaceGovernance.ps1` then produced
`outputs_storage_audit/workspace_governance_20260916_round3/` with 608
directories and `16.069150 GiB` classified. C200/C180 authority hashes pass and
`Agent6` remains untouched. The no-op cleanup is intentional: v13, 120/225,
and 125/225 still have report dependencies and no hash-bound replacement
package, while the explicit raw retirement receipts already show their listed
targets as absent.

The duplicate detached worktree `tmp/c200_continuation_worktree` was retired
with `git worktree remove --force` after confirming no MATLAB process was
active. The current `tmp/c200_c201_worktree_v2` worktree is retained because
it is the active contract-compatible diagnostic copy. No result, checkpoint,
model, or scientific evidence was deleted.

## Round-four pre-cleanup Git checkpoint

The preceding implementation and governance work was reconciled before a new
storage pass. The branch is `codex/conservative-chamber-cold-diagnostic` at
`00f4e92`, and no tracked script change is uncommitted. The sole repository
artifact intentionally left unstaged is the unexplained binary change to
`gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx` (SHA-256
`77E2ACD5B983A0BA72DFB72D3AD106F4D0BC524C2EC56C79C096EEBB5DA88599`; tracked
baseline object `7b7afea69c0ff1b547592f96f02498e3f487aa33`). It is preserved and
neither reverted nor committed. `Agent6/` remains outside repository scope and
untouched.

This checkpoint precedes the next audit-only storage classification. Deletion
requires an explicit rejection/supersession contract, no active MATLAB
reference, preserved authority hashes, and a receipt; age, size, or directory
name alone is insufficient.

## Round-four storage cleanup receipt

After the pre-cleanup Git checkpoint, the standard output manager and workspace
governance audit were rerun. No MATLAB process referenced the outputs root.
The standard manager again found zero automatic candidates. A dedicated
contract, `Retire_HeatDriveECC_RejectedColdFullcycleRaw.ps1`, then retired only
the six native/conservative `observations.mat` files from the rejected,
checkpoint-free v8/v9/v12 cold packages. The audit pass recorded all six
SHA-256 values before deletion; the apply pass rechecked them and wrote
`outputs_storage_audit/rejected_cold_fullcycle_raw_retirement_20260916/retirement_receipt.json`.

Deleted bytes: `995,933,748` (`0.927 GiB`). Execution contracts, rejection
markers, configuration/connectivity/inventory metadata, diaries, public target
files, and scalar audit evidence remain. C200/C180, v13, 120/225, and 125/225
were excluded by contract. The prior v18/v19 dense-observation retirement was
confirmed by its existing applied receipt; no duplicate deletion was attempted.

The post-cleanup output root is `11.004 GiB`, the standard candidate count is
zero, the round-five governance snapshot is
`outputs_storage_audit/workspace_governance_20260916_round5/`, and all frozen
authority hashes pass. `Agent6/` remains untouched and outside repository
scope.

## Failed cold seed cleanup and current retained set

The successful dual-arm package
`tmp/cold_chamber_control_volume_seed_20260916_v4` is retained with both raw
observations pending strict audit. Its native/conservative observation hashes
are `50ED667E...94347587` and `E8CC406A...A8B4137B`; it is diagnostic only and
cannot be used for production recovery.

`Retire_HeatDriveECC_FailedColdSeedAttempts.ps1` classified and retired three
failed setup attempts only after recording all file hashes and confirming that
they contain no checkpoint and assert no recovery, periodic, Table 4, or
full-device first-law status. Lightweight execution, configuration, topology,
inventory and diary evidence was copied to
`outputs_storage_audit/failed_cold_seed_retirement_20260916/preserved_metadata/`.
The applied receipt records `167,662,928` deleted package bytes and `144,777`
deleted cache bytes. The obsolete renamed audit junction was removed after its
target was checked; the target audit directory remains intact.

The post-cleanup output manager still reports zero candidates and `11.004 GiB`.
Round-six governance reports 615 classified directories and `15.144344 GiB`,
with all frozen C200/C180 authority hashes passing. The active isolated
worktree, successful v4 raw package, unresolved main-worktree SLX modification,
and `Agent6/` were not deleted or altered.
