# Native Matched Cold C1: Authority and Limits

## Keep

- Latest compressed selected observations, ONE copy of each, outside Git:
  C:/tmp/se21_shared_SMA_cold_cycle_r1_20261026/dual/selected_observations.mat
  (56,091,114 bytes) and shared/selected_observations.mat (39,583,307 bytes).
- The two MAT files are distinct physical arms, not duplicates. Together:
  95,674,421 bytes. Neither contains a complete OP/restart checkpoint.
- Keep this folder's final review, figure, execution/preflight/controller
  metadata, solver-time samples, rejected r1 evidence and retirement receipts.
- Source native configuration, Git archive and source code are required for
  repeating the case. The failed conservative-arm initialization is not a seed.
- Small 0.01 s selected JSON remain unit-test fixtures. Do not remove them
  without migrating their explicitly referenced regression inputs.

## What Was Verified

Two actual 10 s runs from measured 303.15 K SMA bed initial temperatures.
Native constant-mass pipe energy uses rho_nominal*V*u, not rho(T,p)*V*u.
The full selected pipe record has 1 ms BE samples with small residuals.
Actual original gate commands agree at native 1 ms timestamps; variable-step
ToWorkspace timestamps themselves differ and were NOT forced identical.
The shared command equals the maximum of the actual original commands.

## What Is Not Qualified

Not periodic, not Table4, not a twenty-cycle seed, not production recovery.
SE fluid flux/storage, full device energy, all pump A/B gates and actual
Eq9 HHEX/CHEX outlet integrals are not fully captured in this selected package.
The native hydraulic variant differs from the conservative-offset comparison
variant: these results do not validate that other constructor/initialization.
No C200 performance deviation is causally attributed by this cold C1.

## Retired Exact Prefix Data

Two 0.2 s JSON observations were checked against C1: all 438/249 physical
series, times, constitutive outputs and recorded gates match exactly.
Their original bytes are not duplicated by the different MAT serialization.
Only those obsolete selected prefixes plus seven exact regenerable Git model
copies were deleted: 9 files, 11,481,680 logical bytes. Older prefix reader paths
are intentionally no longer raw-data sources; retain summaries/coverage proof
and use the complete C1 for numeric prefix review.
No result MAT, configuration, library or checkpoint was deleted. No prior
policy-denied target was retried. Small cache directories remain classified
as regenerable; this round does not claim whole-disk cleanup.
