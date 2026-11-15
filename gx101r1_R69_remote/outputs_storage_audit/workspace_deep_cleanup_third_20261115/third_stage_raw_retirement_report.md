# Third-stage raw retirement report

Date: 2026-11-15
Thread: `019e9312-444b-7090-a68e-0888598c1598`

## Result

- Deleted 68 exact file-level raw targets.
- Reclaimed `22,249,589,122` bytes (`20.721545 GiB`).
- No MATLAB/Simulink process was active at deletion or post-check.
- No exact candidate path reference was found in the inspected verification/report roots.
- Main SLX, Agent6, C200, v43 representative raw, New project, Agentheat2, positive/pressure worktrees, and `native_chamber_endpoint_run` were untouched.
- The physical model and scientific gates were unchanged.

## Deleted bytes by branch

| Branch | Deleted files | Bytes |
|---|---:|---:|
| v26-v29 directional raw | 8 | 7,234,214,428 |
| v31 stable constitutive raw | 6 | 5,491,483,798 |
| v9/v16 obsolete warmup native raw | 2 | 2,053,015,956 |
| v56 intermediate C044-C050 observations/states | 8 | 1,804,319,107 |
| v61 intermediate C100-C106 observations/states | 8 | 1,811,930,956 |
| v67/v68/v70/v71 split-comparison raw | 36 | 3,854,624,877 |
| **Total** | **68** | **22,249,589,122** |

## Retained evidence

- v26-v29: `configuration.mat`, `diagnostic_complete_operating_point.mat`, `runtime_evidence_contract.mat`, contracts, logs, state captures, and audit closeouts.
- v31 groups: configuration, OP, runtime contract, contracts, and the `v32_stable_evidence_snapshot_20261013` compact evidence.
- v9/v16: rejection/warmup markers, public targets, contracts, runtime evidence, and retained key evidence.
- v56: packet C052 raw representative; v61: packet C108 raw representative.
- v67/v68/v70: packet C060 raw representatives; v71: packet C050 raw representative.
- v67/v68/v70/v71 split-comparison JSON, manifests, cycle summaries, temperature probes, and compact gate evidence remain.
- Post-check confirmed 14 representative raw files and 766 compact evidence files present with current hashes; zero deleted paths remain.

## Worktree logical sizes after cleanup

| Worktree | Logical bytes after |
|---|---:|
| `fixed-stage4-kp237-endpoint` | 3,247,922,139 |
| `runtime-cv-json-contract` | 19,062,460,134 |
| `stage4-default-cold-diagnostic` | 1,510,100,816 |
| `stage4-phase-local-blend-diagnostic` | 34,947,644,847 |
| **Total** | **58,768,127,936** |

The totals are logical file-length sums. C200 checkout paths are hard-link/junction aliases and are not counted as independent physical storage.

## Audit artifacts

- `third_stage_raw_retirement_whitelist.json`: exact paths, sizes, SHA-256, replacements, and reference conclusions.
- `third_stage_raw_retirement_receipt.json`: deletion receipt and model hash check.
- `third_stage_postcheck.json`: retained representative/evidence hash verification.
- `Retire_HeatDriveECC_ThirdStageRaw.ps1`: repeatable guarded procedure.
