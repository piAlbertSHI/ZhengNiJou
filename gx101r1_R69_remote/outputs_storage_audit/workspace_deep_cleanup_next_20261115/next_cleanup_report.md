# Next cleanup whitelist and execution report

Date: 2026-11-15
Thread: `019e9312-444b-7090-a68e-0888598c1598`

## Execution result

- MATLAB/Simulink was not started or interrupted by this cleanup.
- Two unrelated short MATLAB audit processes appeared during the first attempt; the process guard refused to delete anything. They exited naturally. The final run rechecked the guard and completed.
- Deleted files: 67 regenerable build/cache files from terminal rejected runs.
- Reclaimed bytes: 973,987 (`0.000907 GiB`).
- Scientific gates, model files, source code, configurations, public targets, audit files, plots, and raw scientific observations were unchanged.
- Main SLX, `Agent6`, New project, Agentheat2, positive/pressure worktrees, and `native_chamber_endpoint_run` were untouched.

The exact file-level whitelist, pre-deletion SHA-256 values, replacements, and post-deletion state are in `next_cleanup_whitelist.json`; the execution receipt is `next_cleanup_execution_receipt.json`.

## Why the large files were not deleted

The six large runtime raw files were individually hashed and retained as blocked objects. Each has a terminal/rejection marker and compact evidence, but the compact evidence is not a complete replacement for the full native diagnostic trajectory. The current storage policy and recovery records therefore still retain them.

The six phase-local groups `v56_runtime_Tc277p05_precision_fromC40_r1`, `v61c1`, `v67c1`, `v68c1`, `v70c1`, and `v71c1` remain blocked. Their raw files are tied to current or protected precision, L8, split-comparison, or protected-packet evidence. No deletion was authorized from these groups.

## C200 duplicate accounting

The four checkout paths for `physical_simscape_result.mat` and their `final_operating_point.mat` paths are already NTFS hard links. Their SHA-256 values match the frozen C200 hashes, and `fsutil hardlink list` confirms one physical content object per file. Removing checkout paths would reclaim zero disk space and would break local relative contracts, so no C200 path was modified.

## Scope boundary

The next cleanup script is `verification/Build_HeatDriveECC_NextCleanupWhitelist.ps1`. It refuses to operate while MATLAB/Simulink is alive, rejects reparse points, requires terminal markers for cache targets, hashes every candidate, and leaves blocked raw files untouched.
