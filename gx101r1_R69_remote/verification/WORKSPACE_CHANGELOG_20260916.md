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
