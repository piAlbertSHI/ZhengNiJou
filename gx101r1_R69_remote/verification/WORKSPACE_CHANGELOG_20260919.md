# Workspace Change Log: 2026-09-19

## Git and modification review

The active branch is `codex/conservative-chamber-cold-diagnostic`. The recent
commits `3255ca4`, `1eb702a`, and `ed8d8dc` record the failed cold-seed
retirement, strict control-volume seed rejection, provenance fixes, and the
round-seven closeout. The C200 mainline result and checkpoint remain the only
production recovery authority. The unexplained binary change to
`heatdrive_ecc_coupled_se21.slx` remains uncommitted and untouched. The
parent-level `Agent6/` directory remains outside the repository and untouched.

## Targeted storage retirement

Added `verification/Retire_HeatDriveECC_SupersededCold120Raw.ps1`. The script
is an explicit, hash-bound contract: it requires the 120/225 execution
contract to be complete but non-recoverable, rejects checkpoints and Table 4
claims, checks the retained 125/225 replacement, and refuses to apply while a
HeatDriveECC MATLAB process is active. It deletes only the two dense
120/225 `observations.mat` files and writes a plan, receipt, and
`SUPERSEDED_RAW_COMPACTED.txt` marker.

Applied deletion:

| Arm | Bytes | SHA-256 |
|---|---:|---|
| native | 165,241,941 | `E2118B5980C9105799DE6962B869B66A53F5D5701431755612257B214A4EE81A` |
| conservative | 166,594,511 | `E6E278B173A8DDF1907BE8C155EEC5627300B52D14A193F7C081F8B83C37AF1B` |

Total deleted: `331,836,452` bytes (`0.309046 GiB`). The execution contract,
logs, configuration, inventory/topology metadata, summaries, and audit receipt
remain under the 120/225 directory. The retained 125/225 package, v13 seed,
C200/C180 authority files, control-volume evidence, checkpoints, and `Agent6/`
were excluded from the deletion scope.

Receipt:
`outputs_storage_audit/superseded_cold120_raw_retirement_20260919/retirement_receipt.json`.

This storage change does not change any mechanism, periodic, energy, mass,
outer-solve, sensitivity, paired-endpoint, or Table 4 conclusion.
