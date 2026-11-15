# Minimal-retention cleanup execution report

Date: 2026-11-15 17:22 UTC
Thread: `019e9312-444b-7090-a68e-0888598c1598`
Scope: Agent5-owned minimal-retention groups only

## Result

The exact whitelist from `minimal_retention_audit.json` was executed after the read-only audit and hash/reference checks completed.

- Deleted files: 64
- Reclaimed bytes: 13,711,080,912
- Reclaimed space: 12.769439 GiB
- Scientific gates changed: no
- MATLAB/Simulink started or interrupted: no
- Main model SLX touched: no
- `Agent6`, New project, Agentheat2, other worktrees, and unconfirmed directories touched: no
- External HDF5 links found in the six groups or audit roots: none

## Deleted groups

| Group | Deleted content | Bytes |
|---|---|---:|
| `v64c1` | C116 `observed_states.mat` and native `observations.mat` | 455,675,100 |
| `v65c1` | C116/C118/C120/C122/C124 raw observation/state pairs | 2,278,489,794 |
| `v66_sensitivity_nominal_20261017` | fresh probe and C002/C012/C014/C016/C018 raw observations/states | 2,284,038,958 |
| `v68r2` | fresh probe and C002/C012/C014/C016/C018 raw observations/states | 2,283,274,836 |
| `v70case2` | fresh probe and C002/C012/C014/C016/C018 raw observations/states | 2,284,283,935 |
| `v71case3` | fresh probe and C002/C004/C006/C008/C010/C012/C014/C016/C018 raw observations/states | 4,125,318,289 |
| **Total** | **64 exact whitelist paths** | **13,711,080,912** |

Each deleted file's size and SHA-256 are recorded in `minimal_retention_execution_receipt.json`; the pre-deletion structure and candidate classification are recorded in `minimal_retention_audit.json` and `minimal_retention_raw_inventory.csv`.

## Retained evidence

- Source code, scripts, models, configurations, probe contracts, manifests, compact summaries, gates, storage receipts, retirement receipts, and historical retirement markers were retained.
- Representative raw packets retained: `v64c1` C110/C118, `v65c1` C110/C126, and C020 for v66, v68, v70, and v71.
- v65 C124 raw data was removed because its compact target-window evidence remains and both `precision_pass` and `periodic_steady_state` were false. Its `target_window_stability.json` and `measured_window.json` hashes remain in the execution receipt.
- The four byte-identical C200 checkout copies were outside the deletion whitelist and remain protected. Their known physical-result hash is `0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD`; the corresponding operating-point hash is `FA116BB32B7EF8D2AA7B9097735FAC063A11692EE5DD5DD7D17DA7F798EBAAF4816`.
- A fresh SHA-256 recheck after cleanup found all four C200 physical-result copies present and matching the expected hash.

## Worktree space

| Worktree | Before bytes | After bytes | Released |
|---|---:|---:|---:|
| `fixed-stage4-kp237-endpoint` | 3,247,922,139 | 3,247,922,139 | 0 |
| `runtime-cv-json-contract` | 33,842,148,303 | 33,842,148,303 | 0 |
| `stage4-default-cold-diagnostic` | 1,510,100,816 | 1,510,100,816 | 0 |
| `stage4-phase-local-blend-diagnostic` | 56,129,600,699 | 42,418,519,787 | 13,711,080,912 |
| **Total** | **94,729,771,957** | **81,018,691,045** | **13,711,080,912** |

## Integrity and boundaries

The execution receipt records no direct script references, no live-process references, unchanged scientific gates, and untouched protected paths. The cleanup script itself is `verification/Retire_HeatDriveECC_MinimalRetentionConvergence.ps1`; it uses the exact candidate whitelist and refuses candidates with reparse ancestors, direct references, or live-process references.

This report does not claim the retained diagnostic runs are scientifically validated. They are retained as bounded evidence and recovery/audit context only; the C200 result remains the frozen performance reference and is not by itself a strict Table 4 reproduction claim.
