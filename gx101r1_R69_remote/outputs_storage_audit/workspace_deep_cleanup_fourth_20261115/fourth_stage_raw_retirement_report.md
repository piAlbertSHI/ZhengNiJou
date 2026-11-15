# Fourth-stage raw retirement report

Date: 2026-11-15
Thread: `019e9312-444b-7090-a68e-0888598c1598`

## Result

- Deleted 43 exact historical/intermediate raw files.
- Reclaimed `8,902,021,648` bytes (`8.290654 GiB`).
- No MATLAB/Simulink process was active during deletion or post-check.
- Exact raw path references outside outputs/audits: none.
- Scientific gates, model files, C200, v43, v56-C052, v61-C108, v64/v65, and Agent6 were not modified.

## Deleted groups

| Branch | Deleted content | Bytes |
|---|---|---:|
| Runtime v19/v36/v39/v24/v14 | obsolete trajectory/state and rejected public raw | 4,236,455,268 |
| Phase v48 | C066/C068/C070 observations, states, configurations | 1,394,693,456 |
| Phase v52 | C024/C026 observations, states, configurations | 932,113,985 |
| Phase v59 | C094/C096 observations, states, configurations | 930,490,615 |
| Phase v58 | C090 observations, state, configuration | 465,274,382 |
| Phase v51 | C020 observations, state, configuration | 466,102,230 |
| Phase v63 | duplicate horizon reference and short-reference raw | 476,891,712 |
| **Total** | **43 files** | **8,902,021,648** |

## Retained representatives

- Runtime: OP/configuration/mechanism representatives for v19, v24, v36, and v39; rejection/public evidence for v14.
- Phase: C072, C028, C098, C092, and C022 representative packets.
- v63 extended horizon representative and preflight compact evidence.
- All packet manifests, cycle summaries, temperature probes, mechanism/boundary JSON, contracts, receipts, and reports remain.
- Blocked groups remain listed in `fourth_stage_raw_retirement_whitelist.json`, including v37, v15, v5t, v4, qian cold branches, qian stage4 20-cycle failure branches, and protected v64/v65.

Post-check verified 22 retained representative files and 785 compact evidence files; deleted paths remaining: zero.

## Current logical inventory

The refreshed four-worktree logical inventory reports:

- `fixed-stage4-kp237-endpoint`: 8,230,149,480 bytes
- `runtime-cv-json-contract`: 14,277,487,687 bytes
- `stage4-default-cold-diagnostic`: 6,494,284,147 bytes
- `stage4-phase-local-blend-diagnostic`: 35,054,238,092 bytes

These are logical file-length sums and include hard-link/junction aliases. The C200 reconciliation remains the authority for physical deduplication.

## Audit artifacts

- `fourth_stage_raw_retirement_whitelist.json`
- `fourth_stage_raw_retirement_receipt.json`
- `fourth_stage_postcheck.json`
- `Retire_HeatDriveECC_FourthStageRaw.ps1`
